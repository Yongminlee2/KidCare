import Foundation

/// 코틀린·자바 표준 함수 넷의 뜻을 그대로 옮긴다(계획서 판정 기록 10).
///
/// 왜 따로 두는가: 장소 목록의 순서, 스티커 색, 반경 표기는 안드로이드 보호자 폰과 아이폰 보호자
/// 폰이 **나란히 보는** 값이다. Swift 의 가장 가까운 함수(`<`, `.rounded()`, `hashValue`)는 뜻이
/// 조금씩 달라서, 이모지 이름이나 음수 .5 같은 드문 입력에서 두 폰이 다른 그림을 그린다. 그런 어긋남은
/// 코드를 봐서는 안 보이므로 한 곳에 모으고 자바에서 알려진 값으로 테스트한다.
enum KotlinMath {

    /// `Double.roundToInt()` = `Math.round(double)` = `floor(x + 0.5)`.
    /// Swift `.rounded()` 는 `-1.5` 를 `-2` 로 보내지만 자바는 `-1` 이다.
    static func roundToInt(_ x: Double) -> Int {
        Int((x + 0.5).rounded(.down))
    }

    /// `String.hashCode()` — `s[0]*31^(n-1) + … + s[n-1]` 을 UTF-16 코드 단위로, 32비트 넘침 그대로.
    static func javaHashCode(_ s: String) -> Int32 {
        var hash: Int32 = 0
        for unit in s.utf16 {
            hash = hash &* 31 &+ Int32(unit)
        }
        return hash
    }

    /// `Math.floorMod(int, int)` — 결과가 늘 `0..<m` 이다(자바 `%` 는 음수를 돌려준다).
    static func floorMod(_ x: Int32, _ m: Int) -> Int {
        let r = Int(x) % m
        return r < 0 ? r + m : r
    }

    /// `String.compareTo` 의 "앞선다" — UTF-16 코드 단위 사전순. Swift `<` 는 유니코드 스칼라 순서라
    /// 보조 평면 문자(이모지)와 U+E000 이상 문자 사이에서 순서가 뒤집힌다.
    static func precedes(_ a: String, _ b: String) -> Bool {
        a.utf16.lexicographicallyPrecedes(b.utf16)
    }
}
