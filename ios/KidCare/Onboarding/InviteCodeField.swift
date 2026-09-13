import SwiftUI

/// 초대 코드 입력칸의 규칙. 정본은 안드로이드 `activity_child_pairing.xml:41-50`.
///
/// **왜 따로 두나:** 기기 언어가 한국어인 아이폰은 기본 자판이 한글이라, 코드 칸을 누르고
/// 그대로 치면 `ㅁㅠㅊ234` 가 들어간다. `InviteCode.normalize` 는 대문자화·공백 제거·
/// 헷갈리는 글자 교정만 해서 자모를 못 고치고, 합류 버튼은 영영 안 켜진다 — 부모 눈에는
/// "번호를 맞게 넣었는데 버튼이 안 눌린다"로 보인다.
enum InviteCodeField {

    /// 안드로이드 `android:maxLength="8"`. 6자리보다 두 칸 넉넉해 `ABC-234` 처럼 끊어
    /// 적어도 `normalize` 가 지우기 전에 잘리지 않는다.
    static let maxLength = 8

    static func clamp(_ raw: String) -> String {
        String(raw.prefix(maxLength))
    }
}

extension View {
    /// 초대 코드 칸의 자판. 설정마다의 근거는 계획서 Task 5 와 같다 — 요약하면 한글 자판을
    /// 빼고(`.asciiCapable`), 안드로이드 `textCapCharacters` 처럼 대문자로 보이게 하고,
    /// 자동 고침이 코드를 단어로 바꾸지 못하게 한다.
    func inviteCodeKeyboard() -> some View {
        self
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
    }
}
