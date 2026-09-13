import Testing
@testable import KidCare

/// 정본은 안드로이드 `MapTimelineFragment.buildRouteSections`(:1144)와
/// `RouteWindows.partition` 이 나누는 창. 세 갈래를 브리프가 그대로 못 박았다:
/// 구간이 없을 때, 이동 구간 하나, 이동 구간 둘 사이에 머무름이 낀 경우.
struct RouteOverlayTests {

    private let baseLat = 37.5665

    /// `east` 미터만큼 동쪽으로 옮긴 좌표. `RoutePathRefinerTests.fix` 와 같은
    /// 변환(88_800m ≈ 이 위도에서 경도 1도)을 쓴다 — 걷는 속도(초당 1~2m) 안에서
    /// 점을 찍어야 `RoutePathRefiner` 의 순간이동 문턱(55.6m/s)에 안 걸린다.
    private func point(at: Int64, east: Double, speed: Double = 1.2) -> [String: Any] {
        ["lat": baseLat, "lng": 126.9780 + east / 88_800.0, "accuracy": 10.0, "speed": speed, "at": at]
    }

    private func move(startAt: Int64, endAt: Int64, east: Double) -> [String: Any] {
        ["type": "MOVE", "startAt": startAt, "endAt": endAt,
         "lat": baseLat, "lng": 126.9780 + east / 88_800.0,
         "distanceMeters": 10.0, "pointCount": 2, "placeName": ""]
    }

    private func stay(startAt: Int64, endAt: Int64, east: Double) -> [String: Any] {
        ["type": "STAY", "startAt": startAt, "endAt": endAt,
         "lat": baseLat, "lng": 126.9780 + east / 88_800.0,
         "distanceMeters": 0.0, "pointCount": 2, "placeName": ""]
    }

    @Test("구간이 없을 때는 그릴 선도 없다")
    func 구간이_없을_때() {
        let points = [point(at: 1_000, east: 0)].compactMap(TrailPoint.init)
        let sections = RouteOverlay.sections(points: points, segments: [])
        #expect(sections.isEmpty)
    }

    @Test("이동 구간이 하나면 그 창의 점들이 선 하나가 된다")
    func 이동_구간_하나() {
        let points = [
            point(at: 1_000, east: 0.0),
            point(at: 2_000, east: 1.5),
            point(at: 3_000, east: 3.0),
        ].compactMap(TrailPoint.init)
        let segments = [move(startAt: 1_000, endAt: 3_000, east: 3.0)].compactMap(SegmentDoc.init)

        let sections = RouteOverlay.sections(points: points, segments: segments)

        #expect(sections.count == 1)
        guard sections.count == 1 else { return }
        #expect(sections[0].segmentIndex == 0)
        // Task 8: 숨김 상태는 이 값(구간을 낸 SegmentDoc.startAt)으로 키를 잡는다
        // — 인덱스가 아니다(RouteSection.startAt 주석).
        #expect(sections[0].startAt == 1_000)
        #expect(sections[0].coordinates.count == 3)
        #expect(sections[0].coordinates.first?.lng == points[0].lng)
        #expect(sections[0].coordinates.last?.lng == points[2].lng)
    }

    @Test("이동 구간 둘 사이에 머무름이 끼면 점이 창의 한가운데에서 갈려 양쪽에 붙는다")
    func 이동_구간_둘_사이에_머무름() {
        // 이동1: 1000~2000, 머무름: 2000~6000, 이동2: 6000~7000.
        // RouteWindows 규칙대로 경계는 (2000+6000)/2 근방(≈4000).
        let points = [
            point(at: 1_000, east: 0.0),
            point(at: 2_000, east: 1.5),
            // 머무름 앞 절반(<4000) — 이동1 선에 붙어야 한다.
            point(at: 3_000, east: 1.5),
            // 머무름 뒷 절반(>=4000) — 이동2 선에 붙어야 한다.
            point(at: 5_000, east: 1.6),
            point(at: 6_000, east: 1.6),
            point(at: 7_000, east: 3.1),
        ].compactMap(TrailPoint.init)
        let segments = [
            move(startAt: 1_000, endAt: 2_000, east: 1.5),
            stay(startAt: 2_000, endAt: 6_000, east: 1.55),
            move(startAt: 6_000, endAt: 7_000, east: 3.1),
        ].compactMap(SegmentDoc.init)

        let sections = RouteOverlay.sections(points: points, segments: segments)

        // MOVE 는 인덱스 0, 2 다(가운데는 STAY). 두 선이 나와야 한다.
        #expect(sections.count == 2)
        let bySegment = Dictionary(uniqueKeysWithValues: sections.map { ($0.segmentIndex, $0) })
        #expect(bySegment[0]?.coordinates.count == 3)   // 1000, 2000, 3000(머무름 앞 절반)
        #expect(bySegment[2]?.coordinates.count == 3)   // 5000(머무름 뒷 절반), 6000, 7000
        // Task 8: 인덱스와 별개로 startAt 도 각 구간의 것과 일치해야 한다.
        #expect(bySegment[0]?.startAt == 1_000)
        #expect(bySegment[2]?.startAt == 6_000)
    }
}
