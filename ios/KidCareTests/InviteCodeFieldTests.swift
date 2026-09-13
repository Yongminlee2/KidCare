import Testing
@testable import KidCare

/// 정본은 안드로이드 `activity_child_pairing.xml:41-50`(maxLength=8, textCapCharacters).
struct InviteCodeFieldTests {

    @Test("최대 길이는 안드로이드와 같은 8 이다")
    func 최대_길이() {
        #expect(InviteCodeField.maxLength == 8)
    }

    @Test("8자를 넘으면 뒤를 자르고, 짧으면 그대로 둔다")
    func 자르기() {
        #expect(InviteCodeField.clamp("ABC-234-XY") == "ABC-234-")
        #expect(InviteCodeField.clamp("abc") == "abc")
        #expect(InviteCodeField.clamp("") == "")
    }

    @Test("끊어 적은 6자리는 잘린 뒤에도 유효하다 — 8 이 6 보다 넉넉한 이유")
    func 끊어_적어도_유효() {
        #expect(InviteCode.isValid(InviteCodeField.clamp("abc 234")))
        #expect(InviteCode.isValid(InviteCodeField.clamp("ABC-234")))
    }

    @Test("한글 자판으로 친 자모는 normalize 가 못 고친다 — ASCII 자판을 강제하는 이유")
    func 한글_자모는_유효하지_않다() {
        #expect(InviteCode.isValid("ㅁㅠㅊ234") == false)
    }
}
