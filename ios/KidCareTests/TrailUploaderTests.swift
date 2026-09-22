import Foundation
import Testing
@testable import KidCare

/// 하루 문서 하나를 만드는 규칙(솎기·구간·겹치기 금지)과 상태 문서의 내용을 고정한다.
/// 정본은 안드로이드 `child/TrailUploader.kt` 와 `TrackingService.uploadNow()`(:719-729).
@MainActor
struct TrailUploaderTests {

    private let t0: Int64 = 1_790_035_200_000

    /// 쓰기를 가로채 기록한다. 에뮬레이터를 안 쓴다 — 규칙 통과는 `ChildTrailWriteTests` 가 본다.
    @MainActor
    final class 기록 {
        var 상태: [(familyId: String, childUid: String, write: ChildStatusWrite)] = []
        var 하루: [(familyId: String, childUid: String, doc: TrailDoc)] = []
    }

    /// 아무것도 안 하는 이름표. **이 파일의 어떤 테스트도 네트워크를 타면 안 된다** — 기본값은
    /// 진짜 `PlaceNamer`(Nominatim) 라서 반드시 넣어 준다. 이름 붙이기는 `TrailUploaderNamingTests` 몫이다.
    @MainActor
    final class 이름없음: PlaceNaming {
        func cachedName(lat: Double, lng: Double) async -> String? { nil }
        func name(lat: Double, lng: Double, timeout: TimeInterval, budgetLeftMillis: Int64?) async -> String? { nil }
    }

    private func 만든다(_ 기록장: 기록, 배터리: Float = 0.77, 충전: Bool = false, 통신: String = NetworkKind.wifi) -> TrailUploader {
        TrailUploader(
            device: DeviceState(battery: { (배터리, 충전 ? .charging : .unplugged) }, network: { 통신 }),
            report: { familyId, childUid, write in
                await MainActor.run { 기록장.상태.append((familyId, childUid, write)) }
            },
            saveTrail: { familyId, childUid, doc in
                await MainActor.run { 기록장.하루.append((familyId, childUid, doc)) }
            },
            uid: { "child-uid" },
            now: { self.t0 + 1 },
            namer: 이름없음()
        )
    }

    private func fix(_ at: Int64, lat: Double = 37.5, speed: Double = 0) -> Fix {
        Fix(lat: lat, lng: 127.0, accuracy: 10, at: at, speed: speed)
    }

    @Test("쓰기는 둘이다 — 상태 문서 하나와 하루 문서 하나")
    func 쓰기는_둘() async throws {
        let 기록장 = 기록()
        try await 만든다(기록장).upload(
            familyId: "F1",
            fix: fix(t0, speed: 1.25),
            points: [fix(t0), fix(t0 + 600_000)],
            dayKey: "2026-09-22"
        )
        #expect(기록장.상태.count == 1)
        #expect(기록장.하루.count == 1)
        #expect(기록장.상태[0].childUid == "child-uid")
        #expect(기록장.하루[0].doc.dayKey == "2026-09-22")
        #expect(기록장.하루[0].doc.updatedAt == t0 + 1)
    }

    @Test("상태 문서에 배터리·충전·통신이 실린다 — 시뮬레이터 값도 그대로 간다")
    func 상태_내용() async throws {
        let 기록장 = 기록()
        try await 만든다(기록장, 배터리: 0.77, 충전: true, 통신: NetworkKind.cell)
            .upload(familyId: "F1", fix: fix(t0, speed: 1.25), points: [], dayKey: nil)
        let write = try #require(기록장.상태.first?.write)
        #expect(write.battery == 77)
        #expect(write.charging)
        #expect(write.network == "cell")
        #expect(write.fix.speed == 1.25)
    }

    @Test("오늘 확보한 점이 하나도 없으면 하루 문서는 건너뛰고 상태만 쓴다(TrailUploader.kt:125-129)")
    func 점이_없으면_상태만() async throws {
        let 기록장 = 기록()
        try await 만든다(기록장).upload(familyId: "F1", fix: fix(t0), points: [], dayKey: nil)
        #expect(기록장.상태.count == 1)
        #expect(기록장.하루.isEmpty)
    }

    @Test("구간은 **솎기 전 원본**으로 만든다(TrailUploader.kt:135-138) — 서버 상한에 맞춘 뒤 계산하면 머무름 경계점이 빠진다")
    func 구간은_원본으로() async throws {
        let 기록장 = 기록()
        // 상한(2000)을 넘기는 하루. 앞 절반은 한 곳에 머물고 뒤 절반은 북쪽으로 걷는다.
        var points: [Fix] = []
        for index in 0..<2_500 {
            let at = t0 + Int64(index) * 5_000
            let 북쪽 = index < 1_250 ? 0.0 : Double(index - 1_250) * 5.0
            points.append(Fix(lat: 37.5 + 북쪽 / 111_194.9, lng: 127.0, accuracy: 10, at: at))
        }
        try await 만든다(기록장).upload(familyId: "F1", fix: points[0], points: points, dayKey: "2026-09-22")
        let doc = try #require(기록장.하루.first?.doc)
        #expect(doc.points.count == TrailCodec.maxPoints, "점은 2000개로 솎는다")
        #expect(doc.segments.count == SegmentBuilder.build(points: points).count, "구간은 원본 전체로 만든다")
        #expect(doc.segments.first?.type == "STAY")
    }

    @Test("업로드가 도는 중이면 두 번째 호출은 건너뛴다 — 같은 문서를 또 쓰는 헛일이다(TrailUploader.kt:58-64)")
    func 겹치면_건너뛴다() async throws {
        let 기록장 = 기록()
        let uploader = TrailUploader(
            device: DeviceState(battery: { (0.5, .unplugged) }, network: { NetworkKind.none }),
            report: { familyId, childUid, write in
                // 첫 업로드가 아직 안 끝난 사이에 두 번째가 들어온 상황을 만든다.
                try? await Task.sleep(nanoseconds: 30_000_000)
                await MainActor.run { 기록장.상태.append((familyId, childUid, write)) }
            },
            saveTrail: { _, _, _ in },
            uid: { "child-uid" },
            now: { 0 },
            namer: 이름없음()
        )
        async let 첫째: Void = uploader.upload(familyId: "F1", fix: fix(t0), points: [fix(t0)], dayKey: "2026-09-22")
        async let 둘째: Void = uploader.upload(familyId: "F1", fix: fix(t0), points: [fix(t0)], dayKey: "2026-09-22")
        _ = try await (첫째, 둘째)
        #expect(기록장.상태.count == 1, "대기하지 않고 건너뛴다 — 큐에 쌓으면 이미 최신인 문서를 또 쓴다")

        // 끝난 뒤의 호출은 정상으로 돈다.
        try await uploader.upload(familyId: "F1", fix: fix(t0), points: [fix(t0)], dayKey: "2026-09-22")
        #expect(기록장.상태.count == 2)
    }

    @Test("이름표가 모르는 곳은 빈 이름으로 올라간다 — 이름 하나 때문에 하루 문서가 막히면 안 된다")
    func 이름을_못_얻으면_빈_칸() async throws {
        let 기록장 = 기록()
        let points = [
            Fix(lat: 37.5, lng: 127, accuracy: 10, at: t0),
            Fix(lat: 37.5, lng: 127, accuracy: 10, at: t0 + 600_000),
        ]
        try await 만든다(기록장).upload(familyId: "F1", fix: points[0], points: points, dayKey: "2026-09-22")
        let segments = try #require(기록장.하루.first?.doc.segments)
        #expect(segments.first?.type == "STAY")
        #expect(segments.allSatisfy { $0.placeName.isEmpty })
    }
}
