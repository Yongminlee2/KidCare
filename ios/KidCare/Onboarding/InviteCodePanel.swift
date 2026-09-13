import SwiftUI

/// 초대 번호 한 장 — 제목, 번호 카드, 안내, 만료 줄, 진행 표시, '새 번호 받기' 버튼.
/// 정본은 `activity_guardian_pairing.xml:18-89`. 온보딩의 새 가족 화면(`InviteCodeView`)과 본 화면의 초대
/// 화면(`GuardianInviteView`)이 같은 레이아웃이라 한 곳에 둔다 — 안드로이드도 두 갈래가 같은 XML 을 쓴다.
/// 아래쪽(빈 공간, '역할 다시 고르기')은 화면마다 다르므로 부르는 쪽이 붙인다.
struct InviteCodePanel: View {
    let title: String
    let code: String?
    let hint: String
    let expiry: String?
    let busy: Bool
    let buttonTitle: String
    let buttonEnabled: Bool
    let onButton: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // HeadlineSmall 24 medium.
            Text(verbatim: title)
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.24)
                .foregroundStyle(KidCarePalette.ink)
                .multilineTextAlignment(.center)

            // 코드가 없을 때도 자리가 쪼그라들지 않게 자리표시자를 둔다(XML :34-36).
            // DisplayMedium 34 medium, letterSpacing 0.25, colorPrimaryContainer 카드 모서리 ExtraLarge 28.
            Text(verbatim: code ?? String(localized: "pairing_code_placeholder"))
                .font(.system(size: 34, weight: .medium))
                .tracking(34 * 0.25)
                .foregroundStyle(KidCarePalette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 28)
                .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.top, 24)

            // BodyMedium 15, colorOnSurfaceVariant.
            Text(verbatim: hint)
                .font(.system(size: 15))
                .lineSpacing(5)
                .foregroundStyle(KidCarePalette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            // BodySmall 13 — 발급 순간의 스냅샷(XML :61-63).
            if let expiry {
                Text(verbatim: expiry)
                    .font(.system(size: 13))
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            if busy {
                ProgressView().padding(.top, 28)
            }

            Button(action: onButton) {
                Text(verbatim: buttonTitle)
            }
            .buttonStyle(KidCareTonalButtonStyle())
            .disabled(!buttonEnabled)
            .padding(.top, 24)
        }
    }
}
