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

    @Test("roundToInt 끝값 — ±무한대·Int 범위 밖은 Int32 끝값(코틀린 Int 는 32비트), NaN 은 화면이 죽지 않게 0(코틀린은 던진다), 나머지는 자바 7+ Math.round 값(5단계 통합 검토 M3)")
    func 반올림_끝값() {
        #expect(KotlinMath.roundToInt(.infinity) == Int(Int32.max))
        #expect(KotlinMath.roundToInt(-.infinity) == Int(Int32.min))
        #expect(KotlinMath.roundToInt(1e19) == Int(Int32.max))
        #expect(KotlinMath.roundToInt(-1e19) == Int(Int32.min))
        // 2^31 과 2^63 사이 — 옛 판은 죽지 않았지만 안드로이드와 다른 숫자(3000000000)를 그렸다.
        #expect(KotlinMath.roundToInt(3_000_000_000) == Int(Int32.max))
        #expect(KotlinMath.roundToInt(2_147_483_647.4) == 2_147_483_647)
        #expect(KotlinMath.roundToInt(-2_147_483_648.4) == -2_147_483_648)
        #expect(KotlinMath.roundToInt(-2_147_483_647.6) == -2_147_483_648)
        #expect(KotlinMath.roundToInt(.nan) == 0)
        #expect(KotlinMath.roundToInt(0.5) == 1)
        #expect(KotlinMath.roundToInt(-0.5) == 0)
        #expect(KotlinMath.roundToInt(1.5) == 2)
        #expect(KotlinMath.roundToInt(-1.5) == -1)
        #expect(KotlinMath.roundToInt(-2.5) == -2)
        #expect(KotlinMath.roundToInt(-0.0) == 0)
        // x + 0.5 를 부동소수로 더하면 1.0 이 되는 값 — 자바 7+ 는 0 이다.
        #expect(KotlinMath.roundToInt(0.49999999999999994) == 0)
        #expect(KotlinMath.roundToInt(-0.49999999999999994) == 0)
        #expect(KotlinMath.roundToInt(-0.5000000000000001) == -1)
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
