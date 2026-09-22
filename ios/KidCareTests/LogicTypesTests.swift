import Testing
@testable import KidCare

struct LogicTypesTests {

    @Test("Fix 의 speed 는 기본값 0 이다")
    func fix_기본속도() {
        // 이 필드가 없던 시절 문서를 읽으면 0 으로 들어온다 — 코틀린이 기본값을 둔 이유.
        let f = Fix(lat: 37.5, lng: 127.0, accuracy: 12, at: 1_757_000_000_000)
        #expect(f.speed == 0)
    }

    @Test("Fix 의 speed 는 값을 그대로 담는다")
    func fix_속도_설정() {
        // 회귀 테스트: `let speed: Double = 0` 처럼 선언부에 기본값을 준 저장
        // 프로퍼티는 스위프트가 memberwise 초기화 목록에서 통째로 빼버려(직접
        // 확인함 — `Fix(..., speed: 5)` 가 "extra argument" 컴파일 에러였다)
        // speed 가 절대 설정되지 않는 결함이 있었다. "필드가 있다"만 확인하는
        // 테스트는 이런 결함을 못 잡으므로, 여기서는 넣은 값이 그대로 나오는지
        // 값 자체를 확인한다 — `RoutePathRefiner.kt:137` 이 이 값으로 평활 필터의
        // 과정 잡음을 키우므로, 설정이 안 되면 안드로이드와 다른 경로선이 그려진다.
        let f = Fix(lat: 37.5, lng: 127.0, accuracy: 12, at: 1_757_000_000_000, speed: 7.5)
        #expect(f.speed == 7.5)
    }

    @Test("Fix.speedAccuracy 의 기본값은 '모름'(무한대)이다 — 0 이면 모든 속도가 신뢰할 만한 것이 된다")
    func fix_속도오차_기본값() {
        #expect(Fix(lat: 0, lng: 0, accuracy: 10, at: 0).speedAccuracy == .infinity)
    }

    @Test("Segment 는 머무름과 이동을 구분한다")
    func segment_종류() {
        let s = Segment(type: .stay, startAt: 1, endAt: 2, lat: 37.5, lng: 127.0,
                        distanceMeters: 0, pointCount: 3)
        #expect(s.type == .stay)
        #expect(s.distanceMeters == 0)
    }

    @Test("Segment 의 필드 집합은 nameLat/nameLng 없이 고정된다")
    func segment_필드집합() {
        // DocumentsTests 가 firestoreData.keys 로 내보내는 필드를 못박듯, 여기서는
        // Segment 가 값 타입 자체에 어떤 필드를 갖는지 못박는다. nameLat/nameLng 를
        // 도로 넣는 것은(코드 리뷰가 지적했듯 SegmentDoc 에 없는 값을 지어내게 되므로)
        // 실수로 일어나면 안 되고, 넣는다면 이 테스트를 고치는 의식적인 행위여야 한다.
        let s = Segment(type: .move, startAt: 1, endAt: 2, lat: 37.5, lng: 127.0,
                        distanceMeters: 10, pointCount: 2)
        let fields = Set(Mirror(reflecting: s).children.compactMap(\.label))
        #expect(fields == ["type", "startAt", "endAt", "lat", "lng", "distanceMeters", "pointCount"])
    }
}
