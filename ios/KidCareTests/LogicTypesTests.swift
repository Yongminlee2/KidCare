import Testing
@testable import KidCare

struct LogicTypesTests {

    @Test("Fix 의 speed 는 기본값 0 이다")
    func fix_기본속도() {
        // 이 필드가 없던 시절 문서를 읽으면 0 으로 들어온다 — 코틀린이 기본값을 둔 이유.
        let f = Fix(lat: 37.5, lng: 127.0, accuracy: 12, at: 1_757_000_000_000)
        #expect(f.speed == 0)
    }

    @Test("Segment 는 머무름과 이동을 구분한다")
    func segment_종류() {
        let s = Segment(type: .stay, startAt: 1, endAt: 2, lat: 37.5, lng: 127.0,
                        distanceMeters: 0, pointCount: 3)
        #expect(s.type == .stay)
        #expect(s.distanceMeters == 0)
    }
}
