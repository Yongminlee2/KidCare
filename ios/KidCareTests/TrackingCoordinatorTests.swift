import Foundation
import Testing
@testable import KidCare

/// 점 하나가 들어왔을 때 부르는 순서를 세는 가짜 공급원.
@MainActor
final class 가짜_좌표원: LocationSource {
    var onFix: ((Fix) -> Void)?
    private(set) var 시작됨 = false
    private(set) var 모드_요청: [(state: AdaptiveMovementState, inside: Bool, since: Int64?, now: Int64)] = []

    func start() { 시작됨 = true }
    func stop() { 시작됨 = false }
    func updateMode(state: AdaptiveMovementState, insideKnownPlace: Bool, slowProbeSince: Int64?, now: Int64) {
        모드_요청.append((state, insideKnownPlace, slowProbeSince, now))
    }
}

/// 쓰기를 세기만 하는 가짜 업로더.
@MainActor
final class 가짜_업로더: ChildUploading {
    private(set) var 횟수 = 0
    private(set) var 마지막_점: Fix?
    private(set) var 마지막_dayKey: String?
    private(set) var 마지막_점묶음: [Fix] = []
    /// true 면 던진다 — "실패해도 시각을 먼저 민다"를 보는 데 쓴다.
    var 실패한다 = false

    enum 실패: Error { case 통신 }

    func upload(familyId: String, fix: Fix, points: [Fix], dayKey: String?) async throws {
        횟수 += 1
        마지막_점 = fix
        마지막_dayKey = dayKey
        마지막_점묶음 = points
        if 실패한다 { throw 실패.통신 }
    }
}

/// 설계서 §6.1 의 10단계 **순서**와 §6.4 의 업로드 판정을 고정한다. 순서가 곧 계약이라
/// (`TrackingService.kt:532-699`) 나중에 중간에 끼워 넣으면 조용히 틀어진다.
@MainActor
struct TrackingCoordinatorTests {

    /// 2026-09-22 09:00 KST.
    private let t0: Int64 = 1_790_035_200_000
    private let zone = TimeZone(identifier: "Asia/Seoul")!

    /// 하버사인이 실제로 쓰는 반지름으로 위도 1도의 길이를 만든다 — 그래야 `meters` 가 진짜 미터다.
    private static let 위도1도미터 = LocationFilter.earthRadiusMeters * .pi / 180

    private func fix(
        at: Int64,
        meters: Double = 0,
        accuracy: Double = 10,
        speed: Double = 0,
        speedAccuracy: Double = .infinity
    ) -> Fix {
        Fix(
            lat: 37.5 + meters / Self.위도1도미터,
            lng: 127.0,
            accuracy: accuracy,
            at: at,
            speed: speed,
            speedAccuracy: speedAccuracy
        )
    }

    private func 만든다(
        업로더: 가짜_업로더 = 가짜_업로더(),
        좌표원: 가짜_좌표원? = nil,
        onCondition: ((Int64) -> Void)? = nil,
        onPlaceFix: ((Fix) -> Void)? = nil,
        updateKnownPlace: ((Fix) -> Bool?)? = nil
    ) -> TrackingCoordinator {
        let c = TrackingCoordinator(
            familyId: "F1",
            zone: zone,
            store: TrailStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            uploader: 업로더,
            source: 좌표원
        )
        c.onCondition = onCondition
        c.onPlaceFix = onPlaceFix
        c.updateKnownPlace = updateKnownPlace
        return c
    }

    // MARK: 순서

    @Test("장소 판정은 업로드 판정에 안 묶인다 — SKIP_TOO_CLOSE 도 넘어간다(TrackingService.kt:631-639)")
    func 장소판정은_독립이다() {
        var 장소로_간_점: [Int64] = []
        let c = 만든다(onPlaceFix: { 장소로_간_점.append($0.at) })
        c.handle(fix(at: t0))                       // 첫 점 = UPLOAD
        c.handle(fix(at: t0 + 60_000, meters: 1))   // 25m 못 감 = SKIP_TOO_CLOSE
        #expect(장소로_간_점 == [t0, t0 + 60_000], "SKIP_TOO_CLOSE 가 장소 판정에서 빠졌다")
    }

    @Test("못 믿는 점(정확도)은 장소 판정에도 안 넘어간다")
    func 못_믿는_점은_안_넘어간다() {
        var 장소로_간_점: [Int64] = []
        let c = 만든다(onPlaceFix: { 장소로_간_점.append($0.at) })
        c.handle(fix(at: t0))
        c.handle(fix(at: t0 + 60_000, meters: 1, accuracy: 200))
        #expect(장소로_간_점 == [t0])
    }

    @Test("순간이동도 장소 판정에서 빠진다 — REJECT_IMPOSSIBLE")
    func 순간이동은_안_넘어간다() {
        var 장소로_간_점: [Int64] = []
        let c = 만든다(onPlaceFix: { 장소로_간_점.append($0.at) })
        c.handle(fix(at: t0))
        c.handle(fix(at: t0 + 1_000, meters: 100_000))   // 1초에 100km
        #expect(장소로_간_점 == [t0])
    }

    @Test("상태 검사는 점을 버릴지와 무관하게 **먼저** 한다(TrackingService.kt:533-537)")
    func 상태검사가_먼저다() {
        var 순서: [String] = []
        let c = 만든다(onCondition: { _ in 순서.append("condition") }, onPlaceFix: { _ in 순서.append("place") })
        c.handle(fix(at: t0, accuracy: 500))   // 정확도로 거절되는 점
        #expect(순서 == ["condition"], "거절되는 점에서도 상태 검사는 돈다")
    }

    @Test("시계가 거꾸로 가면 기준점을 버리고 다음 점을 첫 점처럼 받는다(TrackingService.kt:552-568)")
    func 시계_역행_복구() {
        let c = 만든다()
        c.handle(fix(at: t0 + 600_000))
        c.handle(fix(at: t0))                  // 과거
        #expect(c.lastFix?.at == t0, "과거 점을 첫 점 취급으로 받아야 그 뒤가 안 막힌다")
        c.handle(fix(at: t0 + 1_000, meters: 30))
        #expect(c.lastFix?.at == t0 + 1_000, "lastFix 초기화가 안 되면 이후 점이 영영 REJECT_IMPOSSIBLE 이다")
    }

    @Test("이동 확정 전의 점들도 승격 버퍼로 경로에 들어간다 — 출발 부분이 잘리지 않는다")
    func 승격_버퍼() {
        let c = 만든다()
        c.handle(fix(at: t0))                          // 첫 점(머무름 기준점)
        c.handle(fix(at: t0 + 5_000, meters: 10))      // 아직 FAST_PROBE — 5분 기준점도 아니라 안 남는다
        #expect(c.buffer.points.map(\.at) == [t0], "이 시점에는 가운데 점이 아직 안 들어간다")
        c.handle(fix(at: t0 + 10_000, meters: 20))     // 이동 확정 → 승격 버퍼가 돌아온다
        #expect(c.buffer.points.map(\.at) == [t0, t0 + 5_000, t0 + 10_000], "출발 부분이 잘렸다")
    }

    @Test("머무름은 5분 기준점만 남긴다(STAY_ANCHOR_INTERVAL_MILLIS)")
    func 머무름_기준점() {
        #expect(TrackingCoordinator.stayAnchorIntervalMillis == 5 * 60_000)
        let c = 만든다()
        c.handle(fix(at: t0))                              // 첫 점은 force
        c.handle(fix(at: t0 + 60_000, meters: 1))          // 5분 안 됐다
        c.handle(fix(at: t0 + 300_000, meters: 2))         // 5분
        #expect(c.buffer.points.map(\.at) == [t0, t0 + 300_000])
    }

    @Test("정지 주기 사이의 큰 변위는 이동 확인을 켠다 — 5분 뒤 만료되면 되돌아간다(COORDINATE_KICK_WINDOW_MILLIS)")
    func 좌표_변위_킥() {
        #expect(TrackingCoordinator.coordinateKickWindowMillis == 5 * 60_000)
        let c = 만든다()
        // 1분 간격으로 가만히 있으면 30초 뒤 SLOW_PROBE, 거기서 5분을 더 채우면 정지 모드다.
        c.handle(fix(at: t0))
        for step in 1...6 {
            c.handle(fix(at: t0 + Int64(step) * 60_000, meters: 1))
        }
        #expect(c.mode == .still, "정지 모드여야 좌표 변위가 '활동 인식이 놓친 이동'의 증거가 된다")

        // 정지 주기 한 번 사이에 200m — 가방 속 폰의 버스 이동이 이 모양이다.
        c.handle(fix(at: t0 + 420_000, meters: 200))
        #expect(c.coordinateKickExpiresAt == t0 + 420_000 + TrackingCoordinator.coordinateKickWindowMillis)
        #expect(c.mode == .fastProbe, "이동 확인(5초)으로 올라가야 그 구간이 안 빈다")
        #expect(c.buffer.points.map(\.at).contains(t0 + 420_000), "변위 증거 점은 강제로 남긴다")

        // 이동 확정 없이 창이 다 가면 스스로 되돌아간다 — 안 그러면 배터리가 계속 샌다.
        c.handle(fix(at: t0 + 420_000 + TrackingCoordinator.coordinateKickWindowMillis + 1, meters: 201))
        #expect(c.coordinateKickExpiresAt == nil)
        #expect(c.mode == .slowProbe)
    }

    @Test("수집 모드 변경은 좌표원에게 그대로 넘어간다 — 판정기 상태와 저주기 시계까지")
    func 모드를_공급원에_알린다() {
        let 좌표원 = 가짜_좌표원()
        let c = 만든다(좌표원: 좌표원)
        c.handle(fix(at: t0))
        #expect(좌표원.모드_요청.count == 1)
        #expect(좌표원.모드_요청[0].state == .fastProbe)
        #expect(좌표원.모드_요청[0].since == nil)
        c.handle(fix(at: t0 + 60_000, meters: 1))      // 30초를 넘겨 SLOW_PROBE
        #expect(좌표원.모드_요청[1].state == .slowProbe)
        #expect(좌표원.모드_요청[1].since == t0 + 60_000, "저주기에 처음 들어간 시각이 정지 승격의 시계다")
    }

    @Test("등록 장소 훅은 안/밖이 실제로 바뀔 때만 판정기를 되돌린다(TrackingService.kt:519-530)")
    func 등록장소_훅() {
        var 안에_있다: Bool? = false
        let c = 만든다(updateKnownPlace: { _ in 안에_있다 })
        c.handle(fix(at: t0))
        #expect(c.mode == .fastProbe)
        안에_있다 = true
        c.handle(fix(at: t0 + 60_000, meters: 1))
        // 안으로 들어가면 판정기를 느린 확인으로 되돌리고 등록 장소 주기(60초)로 간다.
        #expect(c.mode == .knownPlace)
        #expect(c.buffer.points.map(\.at) == [t0, t0 + 60_000], "들어간 순간은 기준점을 강제로 남긴다")
    }

    // MARK: 업로드 판정 — 설계서 §6.4

    @Test("첫 좌표에서 한 번 올린다 — lastUploadAt 이 0 이고 lastUploadedFix 가 nil 이라(설계서 §10.1)")
    func 첫_좌표_업로드() async {
        let 업로드 = 가짜_업로더()
        let c = 만든다(업로더: 업로드)
        c.handle(fix(at: t0))
        await c.uploadTask?.value
        #expect(업로드.횟수 == 1)
        #expect(업로드.마지막_dayKey == "2026-09-22")
        #expect(업로드.마지막_점묶음.count == 1)
    }

    @Test("15분 **그리고** 25m 를 둘 다 만족해야 올린다")
    func 주기_업로드() async {
        let 업로드 = 가짜_업로더()
        let c = 만든다(업로더: 업로드)
        c.handle(fix(at: t0))                                        // 1회
        await c.uploadTask?.value
        c.handle(fix(at: t0 + 15 * 60_000, meters: 10))              // 25m 못 감 → 안 올린다
        await c.uploadTask?.value
        #expect(업로드.횟수 == 1)
        c.handle(fix(at: t0 + 16 * 60_000, meters: 100))             // 둘 다 만족
        await c.uploadTask?.value
        #expect(업로드.횟수 == 2)
        c.handle(fix(at: t0 + 17 * 60_000, meters: 300))             // 15분 안 됐다
        await c.uploadTask?.value
        #expect(업로드.횟수 == 2)
    }

    @Test("안 움직여도 4시간이 지나면 한 번 올린다 — 부모 화면의 '마지막 신호'가 멎지 않게")
    func 유휴_업로드() async {
        #expect(TrackingCoordinator.uploadIdleIntervalMillis == 4 * 60 * 60_000)
        let 업로드 = 가짜_업로더()
        let c = 만든다(업로더: 업로드)
        let 네시간: Int64 = 4 * 60 * 60_000
        c.handle(fix(at: t0))                                        // 1회
        await c.uploadTask?.value
        // 가만히 있는 폰의 점은 하트비트(10분)를 넘겨야 판정 자체를 통과한다 — 그래서 4시간
        // 규칙도 하트비트 위에서만 만난다.
        c.handle(fix(at: t0 + 네시간 - 600_000, meters: 1))
        await c.uploadTask?.value
        #expect(업로드.횟수 == 1)
        c.handle(fix(at: t0 + 네시간, meters: 1))
        await c.uploadTask?.value
        #expect(업로드.횟수 == 2)
    }

    @Test("사건 직후에는 1·2번을 무시하고 올린다. 다만 1분 안에 또 나면 건너뛴다(known-issues 21번)")
    func 사건_직후_업로드() async {
        // 이 갈래를 부르는 코드는 2단계(장소 이벤트)다. 판정만 지금 고정한다(1단계 판정 기록 14).
        #expect(TrackingCoordinator.uploadEventMinGapMillis == 60_000)
        let 업로드 = 가짜_업로더()
        let c = 만든다(업로더: 업로드)
        c.handle(fix(at: t0))                                              // 1회
        await c.uploadTask?.value
        c.handle(fix(at: t0 + 30_000, meters: 30), eventJustWritten: true)  // 1분 안 → 건너뛴다
        await c.uploadTask?.value
        #expect(업로드.횟수 == 1)
        c.handle(fix(at: t0 + 61_000, meters: 60), eventJustWritten: true)  // 1분 지남 → 올린다
        await c.uploadTask?.value
        #expect(업로드.횟수 == 2)
    }

    @Test("판정 함수만 따로 봐도 규칙 셋이 그대로다")
    func 업로드_판정_직접() {
        let c = 만든다()
        let 기준 = fix(at: t0)
        #expect(c.shouldUpload(now: t0, fix: 기준, eventJustWritten: false), "한 번도 안 올렸으면 거리 조건은 만족")
        #expect(c.shouldUpload(now: t0, fix: 기준, eventJustWritten: true))
        #expect(TrackingCoordinator.uploadMinIntervalMillis == 15 * 60_000)
    }

    @Test("위치를 한 번도 못 잡았으면 올리지 않는다 — 조용히 건너뛴다(설계서 §6.4 끝)")
    func 좌표_없으면_안_올린다() async {
        let 업로드 = 가짜_업로더()
        let c = 만든다(업로더: 업로드)
        await c.uploadNow()
        #expect(업로드.횟수 == 0)
    }

    @Test("파일에서 복구한 옛 점으로는 상태 문서를 쓰지 않는다(TrackingService.kt:713-717)")
    func 복구된_점은_상태를_안_쓴다() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TrailStore(directory: dir)
        store.reset(dayKey: "2026-09-22")
        store.append(fix(at: t0))
        store.append(fix(at: t0 + 5_000, meters: 10))

        let 업로드 = 가짜_업로더()
        let c = TrackingCoordinator(familyId: "F1", zone: zone, store: store, uploader: 업로드)
        c.restore(nowMillis: t0 + 3 * 60 * 60_000)   // 세 시간 뒤에 되살아났다

        #expect(c.buffer.points.count == 2, "오늘 걸어온 길은 되찾는다")
        #expect(c.lastTrailFix?.at == t0 + 5_000, "마지막 점은 경로 필터의 기준점으로 이어 쓴다")
        #expect(c.lastFix == nil, "복구한 점은 상태 문서로 나갈 자격이 없다")
        await c.uploadNow()
        #expect(업로드.횟수 == 0)
    }

    @Test("업로드가 실패해도 lastUploadAt 을 먼저 갱신한다 — 실패가 이어질 때 fix 마다 재시도하지 않는다")
    func 실패해도_시각을_민다() async {
        let 업로드 = 가짜_업로더()
        업로드.실패한다 = true
        let c = 만든다(업로더: 업로드)
        c.handle(fix(at: t0))
        await c.uploadTask?.value
        #expect(업로드.횟수 == 1)
        #expect(c.lastUploadAt == t0, "실패해도 시각은 밀린다")
        c.handle(fix(at: t0 + 60_000, meters: 100))   // 25m 는 넘었지만 15분이 안 됐다
        await c.uploadTask?.value
        #expect(업로드.횟수 == 1, "실패를 곧바로 재시도하면 같은 비용을 반복해서 문다")
    }
}
