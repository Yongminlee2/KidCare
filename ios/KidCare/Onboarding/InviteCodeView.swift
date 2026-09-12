import FirebaseFirestore
import SwiftUI
import os

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

    /// 이 화면이 할 일을 끝냈다고 `RouterView` 에 알린다. 아이가 실제로 들어오면
    /// 저절로 부르고, 그때까지 안 기다리겠다면 "완료" 버튼으로 손수 부를 수도
    /// 있다. 코드를 보여주는 것 자체는 "끝"이 아니다 — 자세한 이유는 `RouterView`
    /// 주석 참고.
    let onDone: () -> Void

    @State private var 코드: String?
    @State private var 진행중 = true
    @State private var 오류: String?
    @State private var 아이_리스너: ListenerRegistration?

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "InviteCodeView")

    var body: some View {
        VStack(spacing: 16) {
            if 진행중 {
                ProgressView()
            } else if let 코드 {
                Text("invite_code_hint")
                Text(코드)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                // 아이가 들어오면 리스너가 알아서 다음으로 넘어가지만, 지금 옆에
                // 없는 아이를 무한정 기다리게 두지 않으려고 손으로 끝낼 길도 둔다.
                Button("invite_code_done") { onDone() }
                    .buttonStyle(.bordered)
            } else if let 오류 {
                Text(오류).foregroundStyle(.red)
            }
        }
        .padding()
        .task { await 발급한다() }
        .onDisappear {
            // 리스너를 그대로 두면 화면을 나간 뒤에도 Firestore 읽기 비용이
            // 계속 나간다(무료 플랜에서는 실비용이다).
            아이_리스너?.remove()
            아이_리스너 = nil
        }
    }

    private func 발급한다() async {
        진행중 = true
        defer { 진행중 = false }
        do {
            let uid = try await AuthGateway.uid()
            let (familyId, role): (String, MemberRole)
            switch mode {
            case .newFamily:
                // **이미 만든 가족이 있으면 다시 만들지 않는다.** 실측으로 확인된 이유:
                // `navigationDestination(isPresented:)` 로 띄운 이 화면은, 아이가
                // 들어와 `onDone()` → `RouterView.showMain = true` 가 발동해 이 화면이
                // 걷히는 바로 그 타이밍에, SwiftUI 가 `.task` 를 가진 **새 인스턴스를
                // 한 번 더 마운트**하는 경우가 실기기/시뮬레이터에서 재현됐다(로그로
                // 확인: `onJoined` 콜백 직후 25ms 안에 전혀 다른 `@State` 인스턴스의
                // `.task` 가 다시 시작됨 — `navigationDestination(isPresented:)` 가
                // 해제되는 순간과 겹치는 SwiftUI 쪽 타이밍 문제로 보인다). 그 새
                // 인스턴스가 가드 없이 `createFamily()` 를 다시 부르면, 방금 아이가
                // 들어온 진짜 가족과 다른 **유령 가족**을 만들고 `RoleStore.shared.
                // familyId` 를 그 유령 가족 id 로 덮어써서, 정작 지도 화면은 아이가
                // 없는 빈 가족을 가리키게 된다 — 코드는 보여줬지만 그 뒤로 아무도
                // 그 가족을 못 찾는 셈이다. 안드로이드 `GuardianPairingActivity.
                // startPairing()` 이 `store.familyId ?: FamilyRepository.
                // createFamily(...).also { store.familyId = it }` 로 정확히 같은
                // 재진입을 막아두는 이유와 같다 — "이미 가족을 만들었으면 새로
                // 만들지 않고 그 가족을 그대로 쓴다"는 이 앱의 오래된 불변식이다.
                let id: String
                if RoleStore.shared.role == .guardian, let existing = RoleStore.shared.familyId {
                    id = existing
                } else {
                    id = try await FamilyRepository.createFamily(guardianUid: uid)
                    RoleStore.shared.role = .guardian
                    RoleStore.shared.familyId = id
                }
                (familyId, role) = (id, .child)
            case let .invite(id, r):
                (familyId, role) = (id, r)
            }
            코드 = try await FamilyRepository.createInvite(
                familyId: familyId, role: role, previousCode: nil
            ).code
            if role == .child { 아이를_기다린다(familyId: familyId) }
        } catch is CancellationError {
            // `.task` 는 화면 생명주기에 묶여 있어, 화면이 사라지면 이 await 가
            // 취소된다. 그건 정상 종료지 오류가 아니다 — 아래 일반 catch 가
            // 이걸 삼켜 없는 실패를 화면에 적으면 안 된다. `FamilyRepository.
            // serverNow` 와 같은 규율이다.
            return
        } catch {
            Self.logger.error("초대 코드 발급 실패: \(String(describing: error), privacy: .public)")
            오류 = String(localized: "error_unknown")
        }
    }

    /// 코드를 보여준 뒤 아이가 실제로 들어오는 순간을 감시한다 — 그래야 이 화면이
    /// "아이가 연결됐다"를 스스로 알고 다음으로 넘어갈 수 있다(안드로이드
    /// `GuardianPairingActivity` 와 같은 얼개). `RoleStore.shared` 는 `@MainActor`
    /// 라 리스너 콜백(메인 스레드라는 보장이 없는 자리) 안에서 곧장 건드리면 안
    /// 되고, `Task { @MainActor in }` 로 건너가야 한다 — `FamilyRepository` 의
    /// 콜백 타입 자체는 격리를 강제하지 않으므로(그래야 다른 화면이 다른 방식으로
    /// 쓸 수 있다) 그 책임은 부르는 쪽인 여기에 있다.
    private func 아이를_기다린다(familyId: String) {
        아이_리스너 = FamilyRepository.observeChildJoined(
            familyId: familyId,
            preferredChildUid: nil,
            onJoined: { childUid in
                Task { @MainActor in
                    RoleStore.shared.childUid = childUid
                    onDone()
                }
            },
            onError: { error in
                // 코드는 화면에 그대로 두는 편이 사용자에게 낫다 — 리스너가
                // 끊겼다고 지금까지 보여주던 코드를 오류 문구로 덮으면, 정작
                // 아직 유효한 코드를 다시 볼 길이 없어진다. 대신 원인만
                // 로그로 남긴다("에러를 그냥 삼키지 않는다"는 안드로이드
                // 쪽 주석과 같은 이유).
                Self.logger.error("아이 합류 감시 실패: \(String(describing: error), privacy: .public)")
            }
        )
    }
}
