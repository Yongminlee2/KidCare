import Foundation
import Testing
@testable import KidCare

/// 정본은 `logic/GeofenceEvaluator.kt`. 안드로이드 테스트를 옮긴 것이고, 넓은 입력 대조는
/// `GoldenComparisonTests.지오펜스_판정_대조` 가 따로 한다.
struct GeofenceEvaluatorTests {

    /// 위도 1도의 남북 거리(m). `LocationFilter.distanceMeters` 와 같은 지구 반지름에서 나온다 —
    /// 테스트가 "정확히 몇 m 떨어진 점"을 만들 때 쓴다.
    private static let 위도1도 = Double.pi / 180.0 * 6_371_000.0
    private func 북쪽(_ lat: Double, _ meters: Double) -> Double { lat + meters / Self.위도1도 }

    private let 기준위도 = 37.5665
    private let 기준경도 = 126.9780

    private func 장소(_ id: String = "p1", radius: Double = 100, enter: Bool = true, exit: Bool = true) -> Place {
        Place(id: id, name: "학교", lat: 기준위도, lng: 기준경도, radiusMeters: radius,
              notifyEnter: enter, notifyExit: exit)
    }

    private func 점(_ meters: Double, accuracy: Double = 10, at: Int64 = 1_000_000) -> Fix {
        Fix(lat: 북쪽(기준위도, meters), lng: 기준경도, accuracy: accuracy, at: at)
    }

    @Test("상수는 코틀린 그대로다 (:52, :55, :69)")
    func 상수() {
        #expect(GeofenceEvaluator.exitMarginMeters == 50.0)
        #expect(GeofenceEvaluator.dedupeMillis == 5 * 60 * 1000)
        // 숫자를 다시 적지 않고 참조를 옮긴다(:64-67). 두 숫자를 따로 두면 한쪽만 바뀌었을 때
        // 이 검사가 조용히 무의미해진다.
        #expect(GeofenceEvaluator.maxAccuracyMeters == LocationFilter.fallbackMaxAccuracyMeters)
    }

    @Test("못 믿는 점(오차 100m 초과)에서는 아무 판단도 안 하고 상태도 안 건드린다 (:78)")
    func 정확도_문턱() {
        let 이전 = [PlaceState(placeId: "p1", inside: false, lastEventAt: 0)]
        let (hits, next) = GeofenceEvaluator.evaluate(places: [장소()], states: 이전, fix: 점(0, accuracy: 100.5))
        #expect(hits.isEmpty)
        #expect(next == 이전, "못 믿는 점이 상태를 건드리면 다음 좋은 점에서 가짜 전환이 하나 만들어진다")
    }

    @Test("오차가 정확히 100m 면 판정한다 — 문턱은 '초과'다 (:78)")
    func 정확도_경계() {
        let (hits, _) = GeofenceEvaluator.evaluate(
            places: [장소()],
            states: [PlaceState(placeId: "p1", inside: false, lastEventAt: 0)],
            fix: 점(0, accuracy: 100.0))
        #expect(hits.count == 1)
    }

    @Test("처음 보는 장소는 이미 안에 있어도 알리지 않고 기억만 한다 (:97-103)")
    func 처음_보는_장소() {
        let (hits, next) = GeofenceEvaluator.evaluate(places: [장소()], states: [], fix: 점(0))
        #expect(hits.isEmpty, "일어나지도 않은 도착을 지금 시각으로 지어내면 안 된다")
        #expect(next == [PlaceState(placeId: "p1", inside: true, lastEventAt: 0)])
    }

    @Test("반경 안으로 들어오면 도착, 반경 + 여유 50m 를 넘어야 이탈이다 (:90-95)")
    func 히스테리시스() {
        let 밖 = [PlaceState(placeId: "p1", inside: false, lastEventAt: 0)]
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 밖, fix: 점(99.5)).hits.count == 1)
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 밖, fix: 점(100.5)).hits.isEmpty)

        let 안 = [PlaceState(placeId: "p1", inside: true, lastEventAt: 0)]
        // 반경 100 + 여유 50 = 150. 149.5m 는 아직 안이고 150.5m 는 나갔다.
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안, fix: 점(149.5)).hits.isEmpty)
        let 나감 = GeofenceEvaluator.evaluate(places: [장소()], states: 안, fix: 점(150.5))
        #expect(나감.hits.map(\.entering) == [false])
    }

    @Test("5분 중복 억제 — 알린 적 없음(0)·시계 역행(음수)은 억제하지 않는다 (:109-114)")
    func 중복_억제() {
        let 안 = { (lastEventAt: Int64) in [PlaceState(placeId: "p1", inside: true, lastEventAt: lastEventAt)] }
        let 지금: Int64 = 10_000_000
        // 4분 59.999초 전에 알렸다 → 아직 억제
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안(지금 - 299_999), fix: 점(200, at: 지금)).hits.isEmpty)
        // 정확히 5분 → 낸다
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안(지금 - 300_000), fix: 점(200, at: 지금)).hits.count == 1)
        // 한 번도 안 알렸으면 억제할 것이 없다
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안(0), fix: 점(200, at: 지금)).hits.count == 1)
        // 폰 시계가 뒤로 갔다. '아직 5분이 안 지났다'로 읽으면 그 폰은 다시는 알림을 못 낸다.
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안(지금 + 60_000), fix: 점(200, at: 지금)).hits.count == 1)
    }

    @Test("억제된 전환도 inside 는 바꾸고 lastEventAt 은 안 민다 (:117-120, PlaceState 주석)")
    func 억제되어도_상태는_간다() {
        let 지금: Int64 = 10_000_000
        let 이전 = [PlaceState(placeId: "p1", inside: true, lastEventAt: 지금 - 1_000)]
        let (hits, next) = GeofenceEvaluator.evaluate(places: [장소()], states: 이전, fix: 점(200, at: 지금))
        #expect(hits.isEmpty)
        #expect(next == [PlaceState(placeId: "p1", inside: false, lastEventAt: 지금 - 1_000)],
                "아무도 못 본 사건이 5분 시계를 밀면 그다음 진짜 알림이 조용히 사라진다")
    }

    @Test("부모가 끈 방향은 안 알리지만 inside 는 갱신한다 (:105-107)")
    func 알림_스위치() {
        let 밖 = [PlaceState(placeId: "p1", inside: false, lastEventAt: 0)]
        let (hits, next) = GeofenceEvaluator.evaluate(places: [장소(enter: false)], states: 밖, fix: 점(0))
        #expect(hits.isEmpty)
        #expect(next[0].inside, "안 바꾸면 반대 방향 알림까지 영영 못 나간다")
    }

    @Test("지워진 장소의 상태는 사라진다 (:82-84)")
    func 지워진_장소_정리() {
        let 이전 = [PlaceState(placeId: "p1", inside: true, lastEventAt: 5),
                    PlaceState(placeId: "없어진곳", inside: true, lastEventAt: 7)]
        let (_, next) = GeofenceEvaluator.evaluate(places: [장소()], states: 이전, fix: 점(0))
        #expect(next.map(\.placeId) == ["p1"], "그 장소를 다시 만들었을 때 옛 판정이 되살아나면 안 된다")
    }
}
