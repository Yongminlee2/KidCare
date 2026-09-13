import SwiftUI

/// 초대 코드를 발급해 보여준다. 새 가족을 시작할 때와, 이미 있는 가족에 아이나
/// 다른 보호자를 부를 때 같은 화면을 쓴다.
struct InviteCodeView: View {

    enum Mode {
        /// 가족을 새로 만들고 자녀용 코드를 낸다. 이 판을 소유하는 `NewFamilySession`
        /// 을 함께 받는다 — 왜 이 화면 자신이 소유하지 않는지는 `NewFamilySession`
        /// 타입 주석 참고.
        ///
        /// 이미 있는 가족에 아이나 다른 보호자를 부르는 갈래는 이 화면이 아니라 `GuardianInviteView` +
        /// `InviteSession` 이다(6단계). 소유자가 온보딩(`RoleSelectView`)이 아니라 본 화면의 선택기이고,
        /// 안드로이드도 그 갈래만 따로 그린다(`GuardianPairingActivity.renderInviteRole`).
        case newFamily(session: NewFamilySession)
    }

    let mode: Mode

    /// 이 화면이 할 일을 끝냈다고 `RouterView` 에 알린다. 아이가 실제로 들어오면 저절로 부른다 — 코드를 보여주는 것
    /// 자체는 "끝"이 아니다(`GuardianPairingActivity` 머리 주석, `RouterView` 주석). 안드로이드처럼 손으로 끝내는 버튼은
    /// 두지 않는다.
    let onDone: () -> Void

    /// "역할 다시 고르기" 로 세션 자체를 버릴 때, 이 화면을 띄운 쪽(`RoleSelectView`)
    /// 에 "네가 들고 있는 세션은 이제 버려도 된다"고 알린다.
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// '새 번호 받기'·'다시 시도' 가 끝났을 때 화면이 아직 있는지. 없으면 감시를 붙이지 않는다 — 아래 `.task` 의
    /// 취소 확인과 같은 이유(사라진 화면이 `onDone()` 을 부를 길을 열지 않는다).
    @State private var 보이는중 = false

    var body: some View {
        switch mode {
        case let .newFamily(session):
            화면(session)
                .task {
                    await session.코드를_확보한다()
                    // `.task` 는 화면이 사라지면 이 Task 를 취소한다. 취소된
                    // **뒤에도** 위 `await` 는 결국 정상적으로 끝난다(세션의
                    // 작업 자체는 화면과 별개로 계속 돈다 — `NewFamilySession`
                    // 주석 참고) — 그래서 그 결과를 이어받아 리스너를 붙이는
                    // 일은 반드시 취소 여부를 직접 확인한 뒤에만 해야 한다.
                    // 확인 없이 그냥 진행하면, 화면을 뒤로 나간 뒤에도 리스너가
                    // 붙어 `onDone()` 을 부를 길이 열린다(3차 리뷰의 Critical).
                    guard !Task.isCancelled else { return }
                    session.듣기를_시작한다()
                }
                .onAppear { 보이는중 = true }
                .onDisappear {
                    보이는중 = false
                    session.듣기를_멈춘다()
                }
        }
    }

    /// 정본 `activity_guardian_pairing.xml:8-103` — 제목·카드·안내·만료·진행·버튼, 그리고 맨 아래 '역할 다시 고르기'.
    /// 이 모드는 늘 자녀용 코드다(`NewFamilySession` 이 role: .child 로만 발급) — 제목·안내도 자녀 초대 문구다.
    private func 화면(_ session: NewFamilySession) -> some View {
        VStack(spacing: 0) {
            InviteCodePanel(
                title: String(localized: "pairing_guardian_title"),
                code: session.코드,
                // 실패 문구는 안내 자리에 대신 적는다(`showSetupFailure` :163-168).
                hint: session.오류 ?? String(localized: "pairing_guardian_hint"),
                expiry: session.만료_문구,
                busy: session.진행중,
                buttonTitle: session.버튼_문구,
                buttonEnabled: session.버튼_활성,
                onButton: { 버튼을_눌렀다(session) }
            )

            // 되돌리기가 주요 동작처럼 보이지 않게 화면 맨 아래로 민다(XML :91-96).
            Spacer(minLength: 24)

            // 가족을 만들다 멈췄거나 재사용하던 familyId 가 죽어도 이 화면이 막다른 골목이 되지 않는다.
            Button { 역할을_다시_고른다() } label: {
                Text("pairing_reset_role_button")
            }
            .buttonStyle(KidCareTextButtonStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KidCarePalette.paper.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(KidCarePalette.paper, for: .navigationBar)
    }

    private func 버튼을_눌렀다(_ session: NewFamilySession) {
        Task {
            await session.버튼을_눌렀다()
            guard 보이는중 else { return }
            session.듣기를_시작한다()
        }
    }

    private func 역할을_다시_고른다() {
        if case let .newFamily(session) = mode {
            session.invalidate()
        }
        RoleStore.shared.clear()
        onReset()
        dismiss()
    }
}
