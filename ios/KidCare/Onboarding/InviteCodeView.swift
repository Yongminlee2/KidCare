import SwiftUI

/// 초대 코드를 발급해 보여준다. 새 가족을 시작할 때와, 이미 있는 가족에 아이나
/// 다른 보호자를 부를 때 같은 화면을 쓴다.
struct InviteCodeView: View {

    enum Mode {
        /// 가족을 새로 만들고 자녀용 코드를 낸다.
        case newFamily
        /// 이미 있는 가족에 이 역할을 부른다.
        case invite(familyId: String, role: MemberRole)
    }

    let mode: Mode

    @State private var 코드: String?
    @State private var 진행중 = true
    @State private var 오류: String?

    var body: some View {
        VStack(spacing: 16) {
            if 진행중 {
                ProgressView()
            } else if let 코드 {
                Text("invite_code_hint")
                Text(코드)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
            } else if let 오류 {
                Text(오류).foregroundStyle(.red)
            }
        }
        .padding()
        .task { await 발급한다() }
    }

    private func 발급한다() async {
        진행중 = true
        defer { 진행중 = false }
        do {
            let uid = try await AuthGateway.uid()
            let (familyId, role): (String, MemberRole)
            switch mode {
            case .newFamily:
                let id = try await FamilyRepository.createFamily(guardianUid: uid)
                RoleStore.shared.role = .guardian
                RoleStore.shared.familyId = id
                (familyId, role) = (id, .child)
            case let .invite(id, r):
                (familyId, role) = (id, r)
            }
            코드 = try await FamilyRepository.createInvite(
                familyId: familyId, role: role, previousCode: nil
            ).code
        } catch {
            오류 = error.localizedDescription
        }
    }
}
