import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `app/src/test/.../LocationFilterTest.kt` 다 — 그 파일의 테스트를 하나도 빼지 않고 옮겼다.
/// 골든 대조(`GoldenComparisonTests`)와 목적이 다르다: 저쪽은 "두 구현이 같은 함수인가"를 넓은 입력으로 보고,
/// 여기는 "사람이 정한 경계가 그대로인가"를 읽을 수 있는 이름으로 남긴다.
struct LocationFilterTests {

    private let seoulCityHall = Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: 1_000_000)

    /// 위도 1도 ≈ 111,320m. 북쪽으로 meters 만큼 옮긴다(코틀린 `near` 와 같은 식).
    private func near(meters: Double, afterMillis: Int64, accuracy: Double = 10) -> Fix {
        Fix(
            lat: seoulCityHall.lat + meters / 111_320.0,
            lng: seoulCityHall.lng,
            accuracy: accuracy,
            at: seoulCityHall.at + afterMillis
        )
    }

    @Test("첫 위치는 무조건 올린다")
    func 첫_위치() {
        #expect(LocationFilter.decide(previous: nil, candidate: seoulCityHall) == .upload)
    }

    @Test("정확도가 나쁘면 버린다")
    func 정확도_나쁨() {
        let bad = Fix(lat: seoulCityHall.lat, lng: seoulCityHall.lng, accuracy: 150, at: seoulCityHall.at)
        #expect(LocationFilter.decide(previous: nil, candidate: bad) == .rejectInaccurate)
    }

    @Test("정확도 50m 는 경계값으로 받아들인다 — 완화가 아니라 평소 승인이어야 한다")
    func 정확도_경계() {
        // 문턱은 '초과'여야 한다. 첫 위치라 완화 창이 열려 있는데도 평소 문턱만으로 통과한다는 뜻이다.
        let edge = Fix(lat: seoulCityHall.lat, lng: seoulCityHall.lng, accuracy: 50, at: seoulCityHall.at)
        #expect(LocationFilter.decide(previous: nil, candidate: edge) == .upload)
    }

    @Test("50m 를 조금만 넘어도 평소에는 버린다")
    func 정확도_경계_바로_위() {
        let justOver = near(meters: 5, afterMillis: 60_000, accuracy: 50.001)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: justOver) == .rejectInaccurate)
    }

    @Test("60m 짜리 점은 평소에는 버린다")
    func 거친_점은_평소에_버린다() {
        let coarse = near(meters: 5, afterMillis: 60_000, accuracy: 60)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: coarse) == .rejectInaccurate)
    }

    @Test("15분 동안 못 올렸으면 같은 60m 짜리 점도 받아들인다 — UPLOAD 가 아니라 완화 승인이다")
    func 완화_문턱() {
        // 이게 .upload 면 문턱을 그냥 100m 로 되돌려도 통과해 버려 완화 경로를 못 잡는다.
        let coarse = near(meters: 5, afterMillis: 15 * 60 * 1000, accuracy: 60)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: coarse) == .uploadStaleFallback)
    }

    @Test("완화 창의 경계는 15분이다")
    func 완화_창_경계() {
        // 1밀리초 모자라면 아직 평소 문턱이다.
        let justBefore = near(meters: 5, afterMillis: 15 * 60 * 1000 - 1, accuracy: 60)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: justBefore) == .rejectInaccurate)
    }

    @Test("완화 창이 열려도 120m 짜리 점은 버린다")
    func 완화_창_상한() {
        // 완화는 옛 문턱(100m)까지다. 그 위는 창이 열려 있어도 못 믿는다.
        let tooCoarse = near(meters: 5, afterMillis: 30 * 60 * 1000, accuracy: 120)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: tooCoarse) == .rejectInaccurate)
    }

    @Test("완화 창이 열려도 순간이동은 버린다")
    func 완화_창_순간이동() {
        // 완화 확정이 순간이동 검사보다 **뒤**에 있어야 한다 — 15분에 1000km = 시속 4000km.
        let teleport = near(meters: 1_000_000, afterMillis: 15 * 60 * 1000, accuracy: 60)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: teleport) == .rejectImpossible)
    }

    @Test("첫 위치는 올린 게 없으므로 완화 문턱을 그대로 쓴다")
    func 첫_위치는_완화_문턱() {
        // previous == nil 은 '부모 화면이 통째로 비어 있다' = 가장 목마른 상태다.
        let coarse = Fix(lat: seoulCityHall.lat, lng: seoulCityHall.lng, accuracy: 90, at: seoulCityHall.at)
        #expect(LocationFilter.decide(previous: nil, candidate: coarse) == .uploadStaleFallback)
    }

    @Test("25m 안 움직였으면 건너뛴다")
    func 이동_문턱_미만() {
        let barelyMoved = near(meters: 10, afterMillis: 60_000)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: barelyMoved) == .skipTooClose)
    }

    @Test("25m 넘게 움직이면 올린다")
    func 이동_문턱_초과() {
        let moved = near(meters: 30, afterMillis: 60_000)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: moved) == .upload)
    }

    @Test("안 움직여도 10분이 지나면 살아있다고 한 번 올린다")
    func 하트비트() {
        let stillThere = near(meters: 5, afterMillis: 10 * 60 * 1000)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: stillThere) == .upload)
    }

    @Test("시속 200km 를 넘는 이동은 GPS 오류로 보고 버린다")
    func 순간이동() {
        // 1초 만에 1km 이동 = 시속 3600km
        let teleport = near(meters: 1000, afterMillis: 1000)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: teleport) == .rejectImpossible)
    }

    @Test("시간이 거꾸로 간 위치는 버린다")
    func 시계_역행() {
        let past = near(meters: 500, afterMillis: -60_000)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: past) == .rejectImpossible)
    }

    @Test("하버사인 거리가 실제와 비슷하다")
    func 하버사인_거리() {
        // 서울시청 → 광화문, 약 1,050m
        let gwanghwamun = Fix(lat: 37.5759, lng: 126.9769, accuracy: 10, at: 2_000_000)
        let d = LocationFilter.distanceMeters(seoulCityHall, gwanghwamun)
        #expect((900.0...1100.0).contains(d), "계산된 거리가 \(d) m 로 예상 범위(900~1100m)를 벗어났다")
    }
}
