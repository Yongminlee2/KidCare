import Testing
@testable import KidCare

/// 정렬·반올림·해시는 코틀린·자바 표준 함수의 뜻을 그대로 따라야 한다(계획서 판정 기록 10).
/// 기대값은 자바에서 알려진 값이다 — "polygenelubricants".hashCode() 가 Int.MIN_VALUE 인 것은
/// 자바 문서·Stack Overflow 에서 널리 인용되는 넘침 사례다.
struct KotlinMathTests {

    @Test("String.hashCode — UTF-16 단위에 31 을 곱해 더하고 32비트로 넘친다")
    func 자바_해시() {
        #expect(KotlinMath.javaHashCode("") == 0)
        #expect(KotlinMath.javaHashCode("a") == 97)
        #expect(KotlinMath.javaHashCode("학교") == 1_737_495)
        #expect(KotlinMath.javaHashCode("polygenelubricants") == Int32.min)
        #expect(KotlinMath.javaHashCode("3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f") == 1_153_660_321)
    }

    @Test("Math.floorMod — 음수 해시도 0..<m 로 떨어진다(PlaceAdapter.kt:71)")
    func 바닥_나머지() {
        #expect(KotlinMath.floorMod(Int32.min, 4) == 0)
        #expect(KotlinMath.floorMod(-1, 4) == 3)
        #expect(KotlinMath.floorMod(1_737_495, 4) == 3)
    }

    @Test("roundToInt = Math.round = floor(x + 0.5) — 음수 .5 에서 Swift rounded() 와 갈린다")
    func 반올림() {
        #expect(KotlinMath.roundToInt(1.5) == 2)
        #expect(KotlinMath.roundToInt(0.5) == 1)
        #expect(KotlinMath.roundToInt(-1.5) == -1)
        #expect(KotlinMath.roundToInt(200.4) == 200)
        #expect(KotlinMath.roundToInt(200.5) == 201)
    }

    @Test("String.compareTo — UTF-16 단위 순서라 이모지(D83D…)가 전각 A(FF21)보다 앞선다")
    func 문자열_순서() {
        #expect(KotlinMath.precedes("가게", "학원"))
        #expect(KotlinMath.precedes("Zoo", "가게"))
        #expect(KotlinMath.precedes("😀", "Ａ"))
        #expect(!KotlinMath.precedes("Ａ", "😀"))
        #expect(!KotlinMath.precedes("같다", "같다"))
    }
}
