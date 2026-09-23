import Foundation
import Testing
@testable import KidCare

/// 정본은 `logic/PlaceNameCache.kt`. 열쇠가 아니라 **거리**로 찾는 캐시다(:14-16).
struct PlaceNameCacheTests {

    private static let 위도1도 = Double.pi / 180.0 * 6_371_000.0
    private func 북쪽(_ lat: Double, _ meters: Double) -> Double { lat + meters / Self.위도1도 }
    private let 기준위도 = 37.5665
    private let 기준경도 = 126.9780

    @Test("상수는 코틀린 그대로다 (:67, :70)")
    func 상수() {
        #expect(PlaceNameCache.matchRadiusMeters == 30.0)
        #expect(PlaceNameCache.maxEntries == 300)
    }

    @Test("30m 안에서 가장 가까운 이름을 준다. 경계 밖은 nil (:33-44)")
    func 거리로_찾는다() {
        var cache = PlaceNameCache()
        cache.put(lat: 북쪽(기준위도, 25), lng: 기준경도, name: "먼 쪽")
        cache.put(lat: 북쪽(기준위도, 5), lng: 기준경도, name: "가까운 쪽")
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == "가까운 쪽")
        #expect(cache.find(lat: 북쪽(기준위도, 60), lng: 기준경도) == nil)
    }

    @Test("같은 자리에 넣으면 바꿔 끼운다 — 흔들린 좌표마다 한 칸씩 늘지 않는다 (:46-56)")
    func 같은_자리는_교체() {
        var cache = PlaceNameCache()
        cache.put(lat: 기준위도, lng: 기준경도, name: "옛 이름")
        cache.put(lat: 북쪽(기준위도, 10), lng: 기준경도, name: "새 이름")
        #expect(cache.size == 1)
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == "새 이름")
    }

    @Test("탭·줄바꿈은 공백으로 바꾸고 양끝을 다듬는다. 빈 이름은 안 넣는다 (:51-52)")
    func 이름_다듬기() {
        var cache = PlaceNameCache()
        cache.put(lat: 기준위도, lng: 기준경도, name: "  가\t나\n다\r라  ")
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == "가 나 다 라")
        cache.put(lat: 북쪽(기준위도, 100), lng: 기준경도, name: "   ")
        #expect(cache.size == 1)
    }

    /// 계획서 판정 기록 4 는 "코틀린 `trim()` 이 U+00A0 를 안 자른다"고 적었지만 **아니다** —
    /// 코틀린 `Char.isWhitespace()` 는 `Character.isWhitespace || Character.isSpaceChar` 라
    /// 비분리 공백도 자른다(kotlin-stdlib 바이트코드로 확인). 실제로 갈리는 자리는 둘이고
    /// 골든 `placeNameCache.put.sanitize` 가 그 둘을 싣는다.
    @Test("코틀린 trim() 과 같은 집합이다 — NEL 은 안 자르고 U+001C 는 자른다(판정 기록 4 정정)")
    func 자바와_같은_공백() {
        var cache = PlaceNameCache()
        cache.put(lat: 기준위도, lng: 기준경도, name: "\u{0085}NEL\u{0085}")
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == "\u{0085}NEL\u{0085}",
                "Swift 기본 .whitespacesAndNewlines 는 U+0085 를 자르는데 코틀린은 안 자른다")

        var 비분리 = PlaceNameCache()
        비분리.put(lat: 기준위도, lng: 기준경도, name: "\u{00A0}카페\u{00A0}")
        #expect(비분리.find(lat: 기준위도, lng: 기준경도) == "카페",
                "비분리 공백은 isSpaceChar 가 true 라 코틀린도 자른다")

        var 제어문자 = PlaceNameCache()
        제어문자.put(lat: 기준위도, lng: 기준경도, name: "\u{001C}집\u{001F}")
        #expect(제어문자.find(lat: 기준위도, lng: 기준경도) == "집",
                "U+001C~U+001F 는 자바 isWhitespace 가 true 라 코틀린이 자른다 — Swift 집합에는 없다")
    }

    @Test("상한을 넘으면 오래된 것부터 버린다 (:55)")
    func 상한() {
        var cache = PlaceNameCache(matchRadiusMeters: 30, maxEntries: 3)
        for i in 0..<5 { cache.put(lat: 북쪽(기준위도, Double(i) * 100), lng: 기준경도, name: "곳\(i)") }
        #expect(cache.size == 3)
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == nil, "가장 먼저 넣은 곳0 이 밀려났다")
        #expect(cache.find(lat: 북쪽(기준위도, 400), lng: 기준경도) == "곳4")
    }

    @Test("한 줄에 한 곳: 위도,경도<탭>이름 (:59)")
    func 부호화() {
        var cache = PlaceNameCache()
        cache.put(lat: 1.5, lng: 2.5, name: "가")
        cache.put(lat: 3.5, lng: 4.5, name: "나")
        #expect(cache.encode() == "1.5,2.5\t가\n3.5,4.5\t나")
    }

    @Test("망가진 줄은 조용히 건너뛴다 — 한 줄 때문에 이름 전체를 잃으면 안 된다 (:72-89)")
    func 복호화() {
        let cache = PlaceNameCache.decode(
            """
            1.5,2.5\t좋은 줄
            탭이없다
            \t앞이비었다
            1.5\t칸이하나
            a,2.5\t위도가숫자아님
            1.5,b\t경도가숫자아님
            3.5,4.5\t또 좋은 줄
            """)
        #expect(cache.size == 2)
        #expect(cache.find(lat: 1.5, lng: 2.5) == "좋은 줄")
        #expect(cache.find(lat: 3.5, lng: 4.5) == "또 좋은 줄")
    }

    /// 골든 `decode` 케이스가 이 자리를 안 싣는다(2단계 통합 검토 M2). 정본
    /// `logic/PlaceNameCache.kt:84-85` 의 `toDoubleOrNull` 이 받는 글자를 여기에 적어 둔다 —
    /// 이 줄을 건드리면 골든이 아니라 이 테스트가 잡는다.
    @Test func 코틀린이_받는_숫자를_똑같이_받는다() {
        let c = PlaceNameCache.decode("  37.5 , 127.0  \t집\n37.6d,127.1f\t학교\n")
        #expect(c.find(lat: 37.5, lng: 127.0) == "집")
        #expect(c.find(lat: 37.6, lng: 127.1) == "학교")
    }

    @Test func 코틀린도_안_받는_것은_안_받는다() {
        #expect(PlaceNameCache.decode("37,5,127.0\t집").find(lat: 37.5, lng: 127.0) == nil,
                "쉼표가 셋이면 좌표 칸이 둘이 아니다")
        #expect(PlaceNameCache.decode("abc,127.0\t집").find(lat: 37.5, lng: 127.0) == nil)
        #expect(PlaceNameCache.decode("37.5dd,127.0\t집").find(lat: 37.5, lng: 127.0) == nil,
                "접미사는 하나뿐이다")
    }
}
