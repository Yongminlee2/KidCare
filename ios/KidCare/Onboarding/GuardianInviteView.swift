import SwiftUI

/// 본 화면에서 여는 초대 번호 화면. 정본은 `activity_guardian_pairing.xml` 과 `GuardianPairingActivity` 의 초대 갈래.
///
/// 부모가 하는 일은 여섯 글자를 소리 내어 읽어주는 것 하나다 — 번호를 카드 한 장에 크게 얹는다(XML 머리 주석).
/// '역할 다시 고르기'는 두지 않는다. 본 화면에서 누르면 이 폰의 가족 연결을 지우는 버튼이라 뒤로 버튼이 나가는
/// 길을 대신한다(계획서 판정 기록 8). 커버라 시스템 뒤로 버튼이 없으므로 왼쪽 위에 직접 둔다.
struct GuardianInviteView: View {
    let session: InviteSession
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(session.제목)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)
                    .multilineTextAlignment(.center)

                // 코드가 없을 때도 자리가 쪼그라들지 않게 자리표시자를 둔다(XML :34-36).
                Text(session.코드 ?? String(localized: "pairing_code_placeholder"))
                    .font(.system(size: 34, weight: .medium))
                    .tracking(34 * 0.25)
                    .foregroundStyle(KidCarePalette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 28)
                    .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.top, 24)

                Text(session.안내)
                    .font(.system(size: 15))
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                if let 만료 = session.만료_문구 {
                    Text(만료)
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.top, 8)
                }

                if session.진행중 {
                    ProgressView().padding(.top, 28)
                }

                Button { session.버튼을_눌렀다() } label: {
                    Text(session.버튼_문구)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(KidCarePalette.sky)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 50)
                        .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!session.버튼_활성)
                .opacity(session.버튼_활성 ? 1 : 0.5)
                .padding(.top, 24)

                Spacer(minLength: 0)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KidCarePalette.paper)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // VoiceOver 는 이 기호를 시스템 이름("뒤로")으로 읽는다 — 새 문구 키가 필요 없다.
                    Button(action: onClose) {
                        Image(systemName: "chevron.backward").font(.system(size: 17, weight: .semibold))
                    }
                    .tint(KidCarePalette.sky)
                }
            }
            .toolbarBackground(KidCarePalette.paper, for: .navigationBar)
        }
        .task { session.시작한다() }
    }
}
