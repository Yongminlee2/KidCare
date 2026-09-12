import SwiftUI

/// 초대 코드를 발급해 보여준다. 새 가족을 시작할 때와, 이미 있는 가족에 아이나
/// 다른 보호자를 부를 때 같은 화면을 쓴다.
struct InviteCodeView: View {

    enum Mode {
        /// 가족을 새로 만들고 자녀용 코드를 낸다. 이 판을 소유하는 `NewFamilySession`
        /// 을 함께 받는다 — 왜 이 화면 자신이 소유하지 않는지는 `NewFamilySession`
        /// 타입 주석 참고.
        ///
        /// 이미 있는 가족에 아이나 다른 보호자를 부르는 갈래(`.invite`)는 아직
        /// 아무도 안 만들어서 뺐다(YAGNI) — Phase 3가 실제 호출부를 달 때, 그때
        /// 가서야 알 수 있는 소유 구조(`.newFamily` 처럼 `NavigationStack` 재진입
        /// 경합을 겪을지, 로컬 상태로 충분할지)에 맞춰 다시 추가한다.
        case newFamily(session: NewFamilySession)
    }

    let mode: Mode

    /// 이 화면이 할 일을 끝냈다고 `RouterView` 에 알린다. 아이가 실제로 들어오면
    /// 저절로 부르고, 그때까지 안 기다리겠다면 "완료" 버튼으로 손수 부를 수도
    /// 있다. 코드를 보여주는 것 자체는 "끝"이 아니다 — 자세한 이유는 `RouterView`
    /// 주석 참고.
    let onDone: () -> Void

    /// "역할 다시 고르기" 로 세션 자체를 버릴 때, 이 화면을 띄운 쪽(`RoleSelectView`)
    /// 에 "네가 들고 있는 세션은 이제 버려도 된다"고 알린다.
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch mode {
        case let .newFamily(session):
            내용(코드: session.코드, 진행중: session.진행중, 오류: session.오류)
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
                .onDisappear { session.듣기를_멈춘다() }
        }
    }

    @ViewBuilder
    private func 내용(코드: String?, 진행중: Bool, 오류: String?) -> some View {
        VStack(spacing: 16) {
            if 진행중 {
                ProgressView()
            } else if let 코드 {
                // 이 모드는 늘 자녀용 코드다(NewFamilySession 이 role: .child 로만
                // 발급) — 안드로이드가 같은 화면(보호자가 아이 폰에 입력할 번호를
                // 보여줌)에 쓰는 pairing_guardian_hint 를 그대로 쓴다. 10분 만료
                // 안내는 안드로이드도 이 문구에 안 넣고 따로 보여준다(설계 §7.3 —
                // 없는 개념을 지어내지 않고 있는 그대로 빌린다).
                Text("pairing_guardian_hint")
                Text(코드)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                // 아이가 들어오면 세션이 알아서 다음으로 넘어가지만, 지금 옆에
                // 없는 아이를 무한정 기다리게 두지 않으려고 손으로 끝낼 길도 둔다.
                Button("invite_code_done") { onDone() }
                    .buttonStyle(.bordered)
            } else if let 오류 {
                Text(오류).foregroundStyle(.red)
                // 재사용하던 familyId 가 죽어(가족 삭제, 멤버 제거 등) 이 화면이
                // 막다른 골목이 될 수 있다. 안드로이드 GuardianPairingActivity 의
                // 되돌리기(resetRoleButton)와 같은 탈출구 — 저장소를 지우고
                // 역할 선택으로 돌려보낸다.
                Button("pairing_reset_role_button") { 역할을_다시_고른다() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
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
