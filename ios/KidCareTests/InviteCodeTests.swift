import Testing
@testable import KidCare

struct InviteCodeTests {

    @Test("코드는 6자리다")
    func 코드는_6자리다() {
        var rng = SeededGenerator(seed: 1)
        #expect(InviteCode.generate(using: &rng).count == 6)
    }

    @Test("코드는 헷갈리는 글자를 쓰지 않는다")
    func 헷갈리는_글자를_안_쓴다() {
        // 0/O, 1/I/L 은 손으로 옮겨 적을 때 잘못 읽힌다.
        for seed in 0..<500 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let code = InviteCode.generate(using: &rng)
            for c in code {
                #expect(!"01OIL".contains(c), "생성된 코드에 \(c) 가 들어있다: \(code)")
            }
        }
    }

    @Test("생성된 코드는 항상 유효하다")
    func 생성된_코드는_유효하다() {
        for seed in 0..<500 {
            var rng = SeededGenerator(seed: UInt64(seed))
            #expect(InviteCode.isValid(InviteCode.generate(using: &rng)))
        }
    }

    @Test("같은 시드는 같은 코드를 만든다")
    func 같은_시드는_같은_코드() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        #expect(InviteCode.generate(using: &a) == InviteCode.generate(using: &b))
    }

    @Test("소문자와 공백과 하이픈을 받아준다")
    func 소문자_공백_하이픈() {
        #expect(InviteCode.normalize(" abc-234 ") == "ABC234")
    }

    @Test("헷갈리는 글자를 교정한다")
    func 헷갈리는_글자를_교정한다() {
        // 0 과 O 는 둘 다 알파벳 밖이라 O -> 0 이 아니라 가까운 대체를 정해 둔다.
        #expect(InviteCode.normalize("aObcde") == "AQBCDE")
        #expect(InviteCode.normalize("023456") == "Q23456")
        #expect(InviteCode.normalize("I23456") == "J23456")
        #expect(InviteCode.normalize("l23456") == "J23456")
    }

    @Test("길이가 다르면 무효다")
    func 길이가_다르면_무효() {
        #expect(!InviteCode.isValid("ABC23"))
        #expect(!InviteCode.isValid("ABC2345"))
        #expect(!InviteCode.isValid(""))
    }

    @Test("알파벳에 없는 글자가 남으면 무효다")
    func 알파벳_밖_글자는_무효() {
        #expect(!InviteCode.isValid("가나다라마바"))
        #expect(!InviteCode.isValid("ABC@34"))
    }
}
