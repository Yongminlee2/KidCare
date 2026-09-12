import SwiftUI
import os

/// 초대 코드를 입력해 가족에 합류한다. 아이폰 보호자의 주된 입구다.
struct JoinFamilyView: View {

    let expectedRole: MemberRole

    /// 합류가 성공했을 때 `RouterView` 에 알린다. 자세한 이유는 `RouterView` 주석
    /// 참고 — 이 화면이 직접 `RoleStore` 를 써도 `RouterView` 가 저절로 알아채지
    /// 않는다, 알아채면 오히려 문제였다.
    let onJoined: () -> Void

    @State private var 입력 = ""
    @State private var 진행중 = false
    @State private var 오류: String?

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "JoinFamilyView")

    private var 보낼_수_있나: Bool { InviteCode.isValid(입력) && !진행중 }

    var body: some View {
        VStack(spacing: 16) {
            Text("pairing_guardian_join_title")
            TextField("pairing_code_placeholder", text: $입력)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(.largeTitle, design: .monospaced))
                .textFieldStyle(.roundedBorder)

            if let 오류 { Text(오류).foregroundStyle(.red) }

            Button("pairing_child_join") { Task { await 합류한다() } }
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
            onJoined()
        } catch is CancellationError {
            // 화면이 사라지며 정상 취소된 것이다 — 이미 사라지는 화면에 오류를
            // 적어봐야 아무도 못 보고, 다음에 이 화면이 다시 뜰 때 "오류"로
            // 시작하는 것도 사실과 다르다. `FamilyRepository.serverNow` 와 같은
            // 규율이다.
            return
        } catch let e as PairingError {
            오류 = String(localized: 문구키(e))
        } catch {
            // Firestore/네트워크 원문은 영어라 그대로 보여주면 로캘라이즈 규칙을
            // 어긴다. 화면에는 공용 문구만 보여주고, 실제 원인은 로그로만 남긴다.
            Self.logger.error("가족 합류 실패: \(String(describing: error), privacy: .public)")
            오류 = String(localized: "error_unknown")
        }
    }

    /// 예외를 화면 문장으로 바꾸는 자리는 여기 하나다. 안드로이드 `ErrorText` 와 같은 역할이고,
    /// 3단계에서 공용 `errorMessage(_:)` 로 옮긴다(Phase 3 Task 3 예정 — 그때까지는 이 화면에만 둔다).
    private func 문구키(_ e: PairingError) -> String.LocalizationValue {
        switch e {
        case .notFound: "pairing_not_found"
        case .offline: "pairing_offline"
        case .expired: "pairing_expired"
        case .wrongRole: "pairing_wrong_role"
        }
    }
}
