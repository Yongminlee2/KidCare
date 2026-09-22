import Foundation
import Testing
@testable import KidCare

/// 머무름에 이름을 붙이는 순서와 예산. 정본 `child/TrailUploader.kt:158-224`.
///
/// **이 함수가 부모의 대기 시간을 정했다**(그 주석 `:160-166`) — 아이폰에서는 부모가 물어볼 수
/// 없으므로 대기 시간이 아니라 업로드 한 번의 비용이 걸린다.
///
/// 네트워크를 타는 테스트가 하나도 없다. `PlaceNaming` 가짜를 넣고, 예산 시계는
/// `TrailUploader` 가 이미 주입받던 `now`(코틀린 `System.currentTimeMillis()` 자리)를 그대로 쓴다.
@MainActor
struct TrailUploaderNamingTests {

    private let t0: Int64 = 1_790_035_200_000

    /// 예산을 재는 시계. 가짜 이름표가 "한 번 물을 때마다" 이만큼 민다 — 벽시계를 안 기다린다.
    @MainActor
    final class 시계 {
        var 밀리: Int64
        init(_ 밀리: Int64) { self.밀리 = 밀리 }
    }

    /// 이름 한 건에 [지연밀리] 만큼 걸리는 가짜. 실제 `PlaceNamer` 와 같은 모양만 갖춘다.
    @MainActor
    final class 가짜_이름표: PlaceNaming {
        private let 캐시: [String: String]
        private let 시계: 시계
        private let 지연밀리: Int64
        private(set) var 물어본_순서: [String] = []
        private(set) var 넘어온_제한시간: [TimeInterval] = []

        init(캐시: [String: String] = [:], 시계: 시계, 지연밀리: Int64 = 0) {
            self.캐시 = 캐시
            self.시계 = 시계
            self.지연밀리 = 지연밀리
        }

        nonisolated static func 열쇠(_ lat: Double, _ lng: Double) -> String {
            String(format: "%.4f,%.4f", lat, lng)
        }

        func cachedName(lat: Double, lng: Double) async -> String? { 캐시[Self.열쇠(lat, lng)] }

        func name(lat: Double, lng: Double, timeout: TimeInterval, budgetLeftMillis: Int64?) async -> String? {
            물어본_순서.append(Self.열쇠(lat, lng))
            넘어온_제한시간.append(timeout)
            시계.밀리 += 지연밀리
            return "물어본 \(Self.열쇠(lat, lng))"
        }
    }

    @MainActor
    final class 기록 {
        var 하루: [TrailDoc] = []
    }

    private func 만든다(_ 기록장: 기록, 이름표: PlaceNaming, 시계: 시계,
                      예산밀리: Int64 = PlaceNamer.geocodeBudgetMillis) -> TrailUploader {
        TrailUploader(
            device: DeviceState(battery: { (0.5, .unplugged) }, network: { NetworkKind.wifi }),
            report: { _, _, _ in },
            saveTrail: { _, _, doc in await MainActor.run { 기록장.하루.append(doc) } },
            uid: { "child-uid" },
            now: { 시계.밀리 },
            namer: 이름표,
            geocodeBudgetMillis: 예산밀리
        )
    }

    /// 머무름 셋(A→B→C)과 그 사이 이동. 머무름은 6분씩이라 `minStayMillis`(5분)를 넘는다.
    private var 세_머무름: [Fix] {
        func 점(_ 초: Int64, _ lat: Double) -> Fix {
            Fix(lat: lat, lng: 127.0, accuracy: 10, at: t0 + 초 * 1_000)
        }
        return [
            점(0, 37.5), 점(360, 37.5),          // A
            점(420, 37.55),                       // 이동
            점(480, 37.6), 점(840, 37.6),        // B
            점(900, 37.65),                       // 이동
            점(960, 37.7), 점(1_320, 37.7),      // C
        ]
    }

    private func 열쇠(_ lat: Double) -> String { 가짜_이름표.열쇠(lat, 127.0) }

    @Test("이동 구간에는 이름을 안 붙인다 (TrailUploader.kt:183-191)")
    func 이동은_이름_없음() async throws {
        let (기록장, 시계장) = (기록(), 시계(t0))
        let 이름표 = 가짜_이름표(시계: 시계장)
        try await 만든다(기록장, 이름표: 이름표, 시계: 시계장)
            .upload(familyId: "F1", fix: 세_머무름[0], points: 세_머무름, dayKey: "2026-09-22")
        let segments = try #require(기록장.하루.first?.segments)
        #expect(segments.contains { $0.type == "MOVE" })
        #expect(segments.allSatisfy { $0.type != "MOVE" || $0.placeName.isEmpty },
                "이동 중 좌표 하나를 주소로 바꿔봐야 지나가던 길 이름이다")
        #expect(segments.allSatisfy { $0.type != "STAY" || !$0.placeName.isEmpty })
    }

    @Test("아는 이름은 네트워크 없이 먼저 다 채운다 (TrailUploader.kt:183-191)")
    func 캐시가_먼저() async throws {
        let (기록장, 시계장) = (기록(), 시계(t0))
        let 이름표 = 가짜_이름표(
            캐시: [열쇠(37.5): "집", 열쇠(37.6): "학교", 열쇠(37.7): "학원"], 시계: 시계장)
        try await 만든다(기록장, 이름표: 이름표, 시계: 시계장)
            .upload(familyId: "F1", fix: 세_머무름[0], points: 세_머무름, dayKey: "2026-09-22")
        let stays = try #require(기록장.하루.first?.segments).filter { $0.type == "STAY" }
        #expect(stays.map(\.placeName) == ["집", "학교", "학원"])
        #expect(이름표.물어본_순서.isEmpty, "다 아는 날은 요청이 한 건도 안 나간다")
    }

    @Test("모르는 곳은 **가장 최근 머무름부터** 묻는다 — 부모가 제일 궁금한 것은 방금 있던 곳이다 (TrailUploader.kt:194)")
    func 최근부터_묻는다() async throws {
        let (기록장, 시계장) = (기록(), 시계(t0))
        let 이름표 = 가짜_이름표(캐시: [열쇠(37.6): "학교"], 시계: 시계장)
        try await 만든다(기록장, 이름표: 이름표, 시계: 시계장)
            .upload(familyId: "F1", fix: 세_머무름[0], points: 세_머무름, dayKey: "2026-09-22")
        #expect(이름표.물어본_순서 == [열쇠(37.7), 열쇠(37.5)], "아는 곳은 건너뛰고, 뒤에서 앞으로 묻는다")
        let stays = try #require(기록장.하루.first?.segments).filter { $0.type == "STAY" }
        #expect(stays.map(\.placeName) == ["물어본 \(열쇠(37.5))", "학교", "물어본 \(열쇠(37.7))"])
    }

    @Test("3초 예산을 넘긴 곳은 이번엔 이름 없이 올라간다 (TrailUploader.kt:197-198, :235)")
    func 예산을_넘기면_이름_없이() async throws {
        let (기록장, 시계장) = (기록(), 시계(t0))
        // 한 건에 1.5초 → 3초 예산으로 두 건까지만 물을 수 있다.
        let 이름표 = 가짜_이름표(시계: 시계장, 지연밀리: 1_500)
        try await 만든다(기록장, 이름표: 이름표, 시계: 시계장)
            .upload(familyId: "F1", fix: 세_머무름[0], points: 세_머무름, dayKey: "2026-09-22")
        #expect(이름표.물어본_순서 == [열쇠(37.7), 열쇠(37.6)])
        let stays = try #require(기록장.하루.first?.segments).filter { $0.type == "STAY" }
        #expect(stays[0].placeName == "", "가장 오래된 머무름은 이번엔 이름이 없다 — 다음 업로드가 다시 묻는다")
        #expect(stays[1].placeName == "물어본 \(열쇠(37.6))")
        #expect(stays[2].placeName == "물어본 \(열쇠(37.7))")
    }

    @Test("남은 예산이 5초보다 짧으면 그만큼만 기다린다 (TrailUploader.kt:200-203)")
    func 제한시간은_남은_예산() async throws {
        let (기록장, 시계장) = (기록(), 시계(t0))
        let 이름표 = 가짜_이름표(시계: 시계장)
        try await 만든다(기록장, 이름표: 이름표, 시계: 시계장)
            .upload(familyId: "F1", fix: 세_머무름[0], points: 세_머무름, dayKey: "2026-09-22")
        #expect(이름표.넘어온_제한시간.allSatisfy { $0 == 3.0 },
                "예산 3초가 제한시간 5초보다 짧다 — 짧은 쪽을 넘긴다")

        // 예산이 제한시간보다 길면 제한시간으로 잘린다.
        let (기록장2, 시계장2) = (기록(), 시계(t0))
        let 이름표2 = 가짜_이름표(시계: 시계장2)
        try await 만든다(기록장2, 이름표: 이름표2, 시계: 시계장2, 예산밀리: 8_000)
            .upload(familyId: "F1", fix: 세_머무름[0], points: 세_머무름, dayKey: "2026-09-22")
        #expect(이름표2.넘어온_제한시간.allSatisfy { $0 == PlaceNamer.timeoutSeconds })
    }

    @Test("구간은 솎기 전 원본으로 계산한다 — 서버 상한에 맞춘 뒤 계산하면 머무름 경계점이 빠진다 (TrailUploader.kt:135-138)")
    func 구간은_원본으로_이름도_원본으로() async throws {
        let (기록장, 시계장) = (기록(), 시계(t0))
        let 이름표 = 가짜_이름표(시계: 시계장)
        // 상한(2000)을 넘기는 하루 — 한 곳에 계속 머문다.
        var points: [Fix] = []
        for index in 0..<2_500 {
            points.append(Fix(lat: 37.5, lng: 127.0, accuracy: 10, at: t0 + Int64(index) * 5_000))
        }
        try await 만든다(기록장, 이름표: 이름표, 시계: 시계장)
            .upload(familyId: "F1", fix: points[0], points: points, dayKey: "2026-09-22")
        let doc = try #require(기록장.하루.first)
        #expect(doc.points.count == TrailCodec.maxPoints)
        #expect(doc.segments.count == SegmentBuilder.build(points: points).count)
        #expect(doc.segments.first?.pointCount == 2_500, "이름도 원본 전체의 가중 평균으로 묻는다")
        #expect(이름표.물어본_순서 == [열쇠(37.5)])
    }
}
