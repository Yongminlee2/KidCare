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

    /// 마지막 요청으로 **수집기가 실제로 걸게 되는** 모드. `CollectionMode.select` 는
    /// `LocationCollector.updateMode` 가 부르는 바로 그 함수다.
    var 걸린_모드: CollectionMode? {
        guard let last = 모드_요청.last else { return nil }
        return CollectionMode.select(
            state: last.state,
            insideKnownPlace: last.inside,
            slowProbeSince: last.since,
            now: last.now
        )
    }
}

/// 테스트가 **직접 돌리는** 시계. 벽시계를 기다리지 않는다 — `tick` 을 손으로 부른다.
@MainActor
final class 가짜_시계: Ticking {
    var onTick: ((Int64) -> Void)?
    private(set) var 시작됨 = false

    func start() { 시작됨 = true }
    func stop() { 시작됨 = false }

    /// 한 주기가 지났다고 알린다.
    func 친다(_ now: Int64) { onTick?(now) }
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
        시계: 가짜_시계? = nil,
        onCondition: ((Int64) -> Void)? = nil,
        onPlaceFix: ((Fix) -> Void)? = nil,
        updateKnownPlace: ((Fix) -> Bool?)? = nil
    ) -> TrackingCoordinator {
        let c = TrackingCoordinator(
            familyId: "F1",
            zone: zone,
            store: TrailStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            uploader: 업로더,
            source: 좌표원,
            ticker: 시계
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
        let 좌표원 = 가짜_좌표원()
        let c = 만든다(좌표원: 좌표원)
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
        // **계산값이 아니라 수집기에 실제로 간 것**을 본다 — 코디네이터만 알고 수집기가 옛 모드를
        // 들고 있으면 거리 필터·정확도가 안 바뀌어 켠 모드가 다음 좌표까지 미뤄진다.
        #expect(좌표원.모드_요청.last?.state == .fastProbe)
        #expect(c.buffer.points.map(\.at).contains(t0 + 420_000), "변위 증거 점은 강제로 남긴다")

        // 이동 확정 없이 창이 다 가면 스스로 되돌아간다 — 안 그러면 배터리가 계속 샌다.
        c.handle(fix(at: t0 + 420_000 + TrackingCoordinator.coordinateKickWindowMillis + 1, meters: 201))
        #expect(c.coordinateKickExpiresAt == nil)
        #expect(c.mode == .slowProbe)
        #expect(좌표원.모드_요청.last?.state == .slowProbe,
                "만료가 판정기를 되돌린 **뒤**에 밀어야 한다 — 먼저 밀면 수집기가 5초·최고정확도에 남는다")
        #expect(좌표원.모드_요청.last?.since == nil)
    }

    @Test("변위 킥이 수집기까지 간다 — 판정기 표본으로는 15m 미만이지만 5분 기준점 대비 50m 인 구간")
    func 변위_킥이_수집기에_걸린다() {
        let 좌표원 = 가짜_좌표원()
        let c = 만든다(좌표원: 좌표원)
        // 1분 간격 정지 → 6분 뒤 정지 모드.
        c.handle(fix(at: t0))
        for step in 1...6 {
            c.handle(fix(at: t0 + Int64(step) * 60_000, meters: 1))
        }
        #expect(c.mode == .still)

        // 분당 13m 로 아주 느리게 옮겨간다. 판정기의 직전 표본(1분 전)과는 13m 라 이동 힌트
        // 문턱(15m)을 못 넘어 판정기는 계속 느린 확인이다 — 5분 기준점 대비 52m 가 되는 순간에만
        // 변위 증거가 선다. 이 구간이 I2 가 60초를 잃던 자리다.
        for (index, meters) in [14.0, 27.0, 40.0, 53.0].enumerated() {
            c.handle(fix(at: t0 + 420_000 + Int64(index) * 60_000, meters: meters))
        }
        #expect(c.coordinateKickExpiresAt != nil, "5분 기준점 대비 50m 가 변위 증거다")
        #expect(c.mode == .fastProbe)
        #expect(좌표원.모드_요청.last?.state == .fastProbe,
                "킥이 켠 5초 확인이 수집기에 안 가면 다음 좌표(정지 주기 60초)까지 그대로 잔다")
        #expect(좌표원.모드_요청.last?.since == nil, "저주기 시계도 함께 풀려야 한다")
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

    // MARK: 좌표 없이 도는 시계 — 안드로이드 활동 인식 STILL 전환의 자리

    /// 이동 확정(`.moving`)까지 올린다. `승격_버퍼` 와 같은 입력이다.
    private func 이동까지_올린다(_ c: TrackingCoordinator) {
        c.handle(fix(at: t0))
        c.handle(fix(at: t0 + 5_000, meters: 10))
        c.handle(fix(at: t0 + 10_000, meters: 20))
    }

    @Test("시계 주기는 정지 확인 시간과 같다 — 확인 창보다 촘촘할 이유도, 성길 이유도 없다")
    func 시계_주기() {
        #expect(TrackingTicker.periodMillis == AdaptiveMovementDetector.stopConfirmMillis)
        #expect(TrackingTicker.periodMillis == 60_000)
    }

    @Test("이동 중에 완전히 멈춘 폰이 좌표 없이도 이동에서 내려온다 — 3m 거리 필터가 자기를 가두지 않는다")
    func 멈춘_폰이_이동에서_내려온다() {
        let 좌표원 = 가짜_좌표원()
        let 시계 = 가짜_시계()
        let c = 만든다(좌표원: 좌표원, 시계: 시계)
        #expect(시계.시작됨, "코디네이터가 시계를 켜야 한다")
        이동까지_올린다(c)
        #expect(c.mode == .moving)
        #expect(좌표원.걸린_모드 == .moving, "이때만 3m 거리 필터가 걸린다")

        // 아이가 교실 책상에 폰을 둔다. 3m 를 안 넘는 콜백은 전부 버려져 `handle()` 이 안 돈다.
        시계.친다(t0 + 10_000 + AdaptiveMovementDetector.stopConfirmMillis)
        #expect(c.mode == .slowProbe, "정지 확인 시간이 지나면 좌표 없이도 내려와야 한다")
        #expect(좌표원.걸린_모드 == .slowProbe, "수집기까지 가야 거리 필터가 실제로 풀린다")

        // 그 뒤로도 조용하면 정지 승격 시계가 좌표 없이 흐른다(STILL_ESCALATE_MILLIS).
        시계.친다(t0 + 70_000 + CollectionMode.stillEscalateMillis)
        #expect(c.mode == .still)
        #expect(좌표원.걸린_모드 == .still)
    }

    @Test("시계는 좌표를 지어내지 않는다 — 점도, 기준점도, 상태 문서도 안 만든다")
    func 시계는_좌표를_지어내지_않는다() async {
        let 업로드 = 가짜_업로더()
        let 좌표원 = 가짜_좌표원()
        let 시계 = 가짜_시계()
        let c = 만든다(업로더: 업로드, 좌표원: 좌표원, 시계: 시계)

        // 좌표를 한 번도 못 받은 폰(권한 직후·실내)에서는 시계가 아무것도 안 한다.
        시계.친다(t0)
        시계.친다(t0 + 10 * 60_000)
        await c.uploadTask?.value
        #expect(업로드.횟수 == 0, "위치를 한 번도 못 잡았으면 올리지 않는다")
        #expect(좌표원.모드_요청.isEmpty)
        #expect(c.lastFix == nil)
        #expect(c.buffer.points.isEmpty)

        이동까지_올린다(c)
        let 점들 = c.buffer.points.map(\.at)
        let 기준점 = c.lastTrailFix?.at
        let 마지막_좌표 = c.lastFix?.at
        for step in 1...10 {
            시계.친다(t0 + 10_000 + Int64(step) * 60_000)
        }
        #expect(c.buffer.points.map(\.at) == 점들, "시계가 경로에 점을 더하면 없던 길이 생긴다")
        #expect(c.lastTrailFix?.at == 기준점)
        #expect(c.lastFix?.at == 마지막_좌표, "마지막 좌표는 실제로 받은 그 점 그대로다")
    }

    @Test("안 움직여도 4시간이 지나면 시계가 유휴 업로드를 낸다 — 좌표가 안 와도 '마지막 신호'가 멎지 않는다")
    func 시계가_유휴_업로드를_낸다() async {
        let 업로드 = 가짜_업로더()
        let 시계 = 가짜_시계()
        let c = 만든다(업로더: 업로드, 시계: 시계)
        c.handle(fix(at: t0))                       // 첫 좌표에서 한 번(설계서 §10.1)
        await c.uploadTask?.value
        #expect(업로드.횟수 == 1)

        시계.친다(t0 + TrackingCoordinator.uploadIdleIntervalMillis - 60_000)
        await c.uploadTask?.value
        #expect(업로드.횟수 == 1, "4시간이 안 됐다")

        시계.친다(t0 + TrackingCoordinator.uploadIdleIntervalMillis)
        await c.uploadTask?.value
        #expect(업로드.횟수 == 2)
        #expect(업로드.마지막_점?.at == t0, "지어낸 좌표가 아니라 마지막으로 **실제로 받은** 점이다")
        #expect(c.lastUploadAt == t0 + TrackingCoordinator.uploadIdleIntervalMillis)

        // 15분 **그리고** 25m 규칙은 좌표가 안 움직였으므로 여기서 절대 안 걸린다.
        시계.친다(t0 + TrackingCoordinator.uploadIdleIntervalMillis + 20 * 60_000)
        await c.uploadTask?.value
        #expect(업로드.횟수 == 2, "거리가 0 인데 15분마다 올리면 하루 96번 쓴다")
    }

    @Test("앱이 잠들었다 깨어나면 밀린 주기를 한 번에 정산한다 — 몰아치지도, 건너뛰지도 않는다")
    func 잠들었다_깨어난다() async {
        let 업로드 = 가짜_업로더()
        let 좌표원 = 가짜_좌표원()
        let 시계 = 가짜_시계()
        let c = 만든다(업로더: 업로드, 좌표원: 좌표원, 시계: 시계)
        이동까지_올린다(c)
        let 잠들기_전_요청 = 좌표원.모드_요청.count

        // 세 시간을 잠들어 있었다 — iOS 는 그동안 실행 시간을 주지 않으므로 tick 이 한 번도 안 온다.
        // 깨어난 뒤의 첫 한 번이 세 시간을 그대로 본다(주기 수가 아니라 **시각**으로 판정한다).
        let 깨어남 = t0 + 10_000 + 3 * 60 * 60_000
        시계.친다(깨어남)
        #expect(c.mode == .slowProbe, "한 번의 tick 으로 정지 확인이 끝난다")
        #expect(좌표원.모드_요청.count == 잠들기_전_요청 + 1, "밀린 주기만큼 몰아서 걸지 않는다")

        // 같은 시각(또는 과거)의 tick 이 한 번 더 와도 두 번 세지 않는다.
        시계.친다(깨어남)
        시계.친다(깨어남 - 60_000)
        await c.uploadTask?.value
        #expect(좌표원.모드_요청.count == 잠들기_전_요청 + 1)
        #expect(업로드.횟수 == 1, "깨어난 것만으로 업로드가 두 번 나가지 않는다")
    }
}
