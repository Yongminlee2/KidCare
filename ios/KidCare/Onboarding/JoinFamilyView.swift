import SwiftUI

/// 초대 코드를 입력해 가족에 합류한다. 아이폰 보호자의 주된 입구다.
struct JoinFamilyView: View {

    let expectedRole: MemberRole

    @State private var 입력 = ""
    @State private var 진행중 = false
    @State private var 오류: String?

    private var 보낼_수_있나: Bool { InviteCode.isValid(입력) && !진행중 }

    var body: some View {
        VStack(spacing: 16) {
            Text("join_family_hint")
            TextField("join_family_code_placeholder", text: $입력)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(.largeTitle, design: .monospaced))
                .textFieldStyle(.roundedBorder)

            if let 오류 { Text(오류).foregroundStyle(.red) }

            Button("join_family_submit") { Task { await 합류한다() } }
                .buttonStyle(.borderedProminent)
                .disabled(!보낼_수_있나)
        }
        .padding()
    }

    private func 합류한다() async {
        진행중 = true
        오류 = nil
        defer { 진행중 = false }
        do {
            let uid = try await AuthGateway.uid()
            let result = try await FamilyRepository.joinFamily(
                code: 입력, uid: uid, expectedRole: expectedRole,
                displayName: String(localized: "role_guardian")
            )
            RoleStore.shared.role = result.role
            RoleStore.shared.familyId = result.familyId
            RoleStore.shared.childUid = try await FamilyRepository.findChildUid(
                familyId: result.familyId, preferred: nil
            )
        } catch let e as PairingError {
            오류 = String(localized: 문구키(e))
        } catch {
            오류 = error.localizedDescription
        }
    }

    /// 예외를 화면 문장으로 바꾸는 자리는 여기 하나다. 안드로이드 `ErrorText` 와 같은 역할이고,
    /// 3단계에서 공용 `errorMessage(_:)` 로 옮긴다(Phase 3 Task 3 예정 — 그때까지는 이 화면에만 둔다).
    private func 문구키(_ e: PairingError) -> String.LocalizationValue {
        switch e {
        case .notFound: "pairing_error_not_found"
        case .offline: "pairing_error_offline"
        case .expired: "pairing_error_expired"
        case .wrongRole: "pairing_error_wrong_role"
        }
    }
}
