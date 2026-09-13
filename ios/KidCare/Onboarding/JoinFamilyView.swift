import SwiftUI
import os

/// 초대 코드를 입력해 가족에 합류한다. 아이폰 보호자의 주된 입구다.
///
/// 정본은 `ChildPairingActivity` 의 **보호자 갈래**다 — 안드로이드 `RoleSelectActivity.kt:37-41` 이 '초대 번호로 기존
/// 가족 참여'를 고르면 역할을 GUARDIAN 으로 적고 이 액티비티를 연다. 그래서 레이아웃도 `activity_child_pairing.xml`
/// 이고, 제목·이름 칸 안내만 보호자 문구로 바뀐다(`ChildPairingActivity.kt:45-51`).
struct JoinFamilyView: View {

    let expectedRole: MemberRole

    /// 합류가 성공했을 때 `RouterView` 에 알린다. 자세한 이유는 `RouterView` 주석
    /// 참고 — 이 화면이 직접 `RoleStore` 를 써도 `RouterView` 가 저절로 알아채지
    /// 않는다, 알아채면 오히려 문제였다.
    let onJoined: () -> Void

    @State private var 입력 = ""
    /// 안드로이드 `name_input`(XML :53-68) — 비워 두면 빈칸으로 저장하고 읽는 화면이 그 폰의 언어로 채운다(`FamilyRepository.joinFamily`, 안드로이드 2026-09-14 변경과 같음).
    @State private var 이름 = ""
    @State private var 진행중 = false
    @State private var 오류: String?
    /// `ChildPairingActivity.joinJob`. '역할 다시 고르기'가 먼저 취소해야 늦게 끝난 합류가 저장소를 다시 쓰지 않는다.
    @State private var 합류_작업: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "JoinFamilyView")

    /// 안드로이드 `pairing_guardian_name_hint` 칸의 `android:maxLength="20"`.
    static let nameMaxLength = 20

    private var 보낼_수_있나: Bool { InviteCode.isValid(입력) && !진행중 }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Image("Mascot3D")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .padding(.bottom, 16)
                        .accessibilityHidden(true)

                    // HeadlineSmall 24 medium.
                    Text(expectedRole == .guardian ? "pairing_guardian_join_title" : "pairing_child_title")
                        .font(.system(size: 24, weight: .medium))
                        .tracking(-0.24)
                        .lineSpacing(3)
                        .foregroundStyle(KidCarePalette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)

                    // 코드 칸: TitleLarge 21 medium, letterSpacing 0.2, 가운데, 최소 높이 72, maxLength 8.
                    KidCareOutlinedField(
                        label: "pairing_child_hint",
                        text: $입력,
                        keyboard: .inviteCode,
                        fontSize: 21,
                        fontWeight: .medium,
                        tracking: 21 * 0.2,
                        centered: true,
                        minHeight: 72,
                        maxLength: InviteCodeField.maxLength
                    )

                    // 이름 칸: BodyLarge 17, 최소 높이 64, maxLength 20.
                    KidCareOutlinedField(
                        label: expectedRole == .guardian ? "pairing_guardian_name_hint" : "pairing_child_name_hint",
                        text: $이름,
                        keyboard: .personName,
                        minHeight: 64,
                        maxLength: Self.nameMaxLength
                    )
                    .padding(.top, 12)

                    // 오류 줄은 자두빛 면 위에 놓는다(XML 머리 주석) — colorErrorContainer / colorOnErrorContainer.
                    if let 오류 {
                        Text(verbatim: 오류)
                            .font(.system(size: 15))
                            .foregroundStyle(KidCarePalette.onBerrySoft)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(KidCarePalette.berrySoft)
                            .padding(.top, 12)
                    }

                    Button { 합류_작업 = Task { await 합류한다() } } label: {
                        Text("pairing_child_join")
                    }
                    .buttonStyle(KidCareFilledButtonStyle(minHeight: 64))
                    .disabled(!보낼_수_있나)
                    .padding(.top, 24)

                    // 되돌리기가 주요 동작처럼 보이지 않게 화면 맨 아래로 민다(XML :92-96).
                    Spacer(minLength: 24)

                    Button { 역할을_다시_고른다() } label: {
                        Text("pairing_reset_role_button")
                    }
                    .buttonStyle(KidCareTextButtonStyle())
                }
                .padding(32)
                .frame(minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(KidCarePalette.paper.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(KidCarePalette.paper, for: .navigationBar)
        // 번호를 고치면 지난 오류는 지운다(`doAfterTextChanged` :53-56).
        .onChange(of: 입력) { _, _ in 오류 = nil }
    }

    /// '역할 다시 고르기'(`resetRoleButton` :59-69). 이 화면은 합류가 끝나기 전에는 저장소에 아무것도 쓰지 않으므로
    /// 지울 것이 없다 — 진행 중인 합류를 먼저 취소하고(cancel → navigate) 역할 선택으로 돌아간다.
    private func 역할을_다시_고른다() {
        합류_작업?.cancel()
        합류_작업 = nil
        dismiss()
    }

    private func 합류한다() async {
        진행중 = true
        오류 = nil
        defer { 진행중 = false }
        do {
            let uid = try await AuthGateway.uid()
            let result = try await FamilyRepository.joinFamily(
                code: 입력, uid: uid, expectedRole: expectedRole,
                displayName: 이름
            )
            // Firestore 호출은 취소에 응하지 않고 끝까지 돌아온다 — 되돌리기 뒤에 저장소를 쓰지 않게 여기서 멈춘다.
            try Task.checkCancellation()
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
