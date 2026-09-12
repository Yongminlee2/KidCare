import SwiftUI

/// 첫 실행 화면. 보호자는 두 갈래(새 가족 / 합류)로 갈린다.
///
/// 아이 버튼을 **지우지 않고 안내로 두는 이유**는 설계서 §1 에 있다 — 지우면
/// 나중에 붙일 자리를 되살려야 하고, 흐리게만 두면 왜 안 되는지를 말해주지 못한다.
struct RoleSelectView: View {

    @State private var 보호자_갈래를_묻는다 = false
    @State private var 아이는_안된다고_알린다 = false
    @State private var 합류로_간다 = false
    @State private var 발급으로_간다 = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("role_select_title").font(.title2).bold()

                Button("role_guardian") { 보호자_갈래를_묻는다 = true }
                    .buttonStyle(.borderedProminent)

                Button("role_child") { 아이는_안된다고_알린다 = true }
                    .buttonStyle(.bordered)
            }
            .padding()
            .confirmationDialog("guardian_start_title", isPresented: $보호자_갈래를_묻는다) {
                Button("guardian_start_new_family") { 발급으로_간다 = true }
                Button("guardian_start_join_family") { 합류로_간다 = true }
                Button("dialog_cancel", role: .cancel) {}
            }
            .alert("ios_child_unsupported_title", isPresented: $아이는_안된다고_알린다) {
                Button("dialog_ok", role: .cancel) {}
            } message: {
                Text("ios_child_unsupported_body")
            }
            .navigationDestination(isPresented: $합류로_간다) {
                JoinFamilyView(expectedRole: .guardian)
            }
            .navigationDestination(isPresented: $발급으로_간다) {
                InviteCodeView(mode: .newFamily)
            }
        }
    }
}
