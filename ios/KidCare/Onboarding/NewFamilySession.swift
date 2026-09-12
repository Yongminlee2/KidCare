import FirebaseFirestore
import Foundation
import Observation
import os

/// "새 가족 만들기" 한 판(가족 확보 → 초대 코드 발급 → 아이 합류 감시)을 소유한다.
///
/// **왜 `InviteCodeView` 가 아니라 별도 타입인가.** `InviteCodeView` 는
/// `NavigationStack` 의 push 대상이라, SwiftUI 가 그 인스턴스를 한 번 더
/// 마운트하는 경우가 실측으로 확인됐다(Task 7 1·2차 수정 보고서 — 로그로
/// 서로 다른 `@State` 인스턴스가 재진입마다 다시 일을 시작하는 것을 확인).
/// 1차 수정(인스턴스별 가드)과 2차 수정(타입에 붙는 정적 손잡이) 둘 다
/// "화면이 다시 그려져도 일은 한 번만" 을 뷰 쪽에서 흉내 내려 했는데, 그
/// 결과 일이 **화면보다 오래 사는** 문제가 생겼다 — 화면이 사라져도
/// `Task`/리스너를 아무도 안 멈추니, 나중에 되살아나 엉뚱한 화면에서
/// `onDone()` 을 부르거나 리스너를 영영 못 지우는 사고로 이어졌다(2차 리뷰가
/// 잡은 Critical/Important). 안드로이드에 이 문제가 없는 이유는
/// `GuardianPairingActivity` 가 처음부터 이 일(Job, 리스너)을 직접 소유하고,
/// 그 Activity 자체가 다시 만들어지는 일이 없기 때문이다 — 이 타입은 그
/// 소유 구조를 그대로 옮긴 것이다.
///
/// 이 세션은 `InviteCodeView` 를 띄우는 화면(`RoleSelectView`)이 만들어 들고
/// 있는다. `RoleSelectView` 자신은 push 된 목적지가 아니라서 그 마운트
/// 불안정을 겪지 않는다 — `RouterView` 가 본 화면으로 넘어갈 때만 사라지는,
/// 이 화면 전체에서 하나뿐인 안정된 자리다. `InviteCodeView` 는 이 세션을
/// 건네받아 상태만 읽어 그리는 화면으로 남는다 — 몇 번을 다시 그려도 세션은
/// 하나뿐이라 다시 시작할 일이 없다.
///
/// **세션 자체는 반드시 뷰 빌더 클로저가 아니라 버튼 액션에서 만들어야
/// 한다.** `RoleSelectView` 의 "새 가족 만들기" 버튼 액션 주석 참고 — 실측으로
/// 확인했다: `navigationDestination` 의 내용 클로저 안에서 `@State` 를 채우려
/// 하면, SwiftUI 가 그 클로저를 한 번의 네비게이션에도 여러 번 불러서 매번
/// nil 을 보고 새 세션을 만드는 사고로 이어진다.
@Observable
@MainActor
final class NewFamilySession {

    private(set) var 코드: String?
    private(set) var 만료시각: Int64?
    private(set) var 진행중 = true
    private(set) var 오류: String?

    private let onDone: () -> Void
    private var 준비_작업: Task<Void, Never>?
    private var 아이_리스너: ListenerRegistration?
    private var 무효화됨 = false

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "NewFamilySession")

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    /// 화면에 보이는 동안 부른다. 가족·코드가 아직 없거나 만료됐으면 새로
    /// 받고, 이미 유효하면 그대로 둔다(네트워크 호출 없음). 이미 진행 중인
    /// 시도가 있으면 그것을 그대로 기다린다 — 재진입(화면이 다시 그려지는
    /// 것 포함)마다 새 `createFamily`/`createInvite` 호출을 만들지 않는다.
    func 코드를_확보한다() async {
        if let 기존_작업 = 준비_작업 {
            await 기존_작업.value
            return
        }
        if 코드 == nil { 진행중 = true }
        오류 = nil
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.실제로_확보한다()
        }
        준비_작업 = task
        await task.value
        준비_작업 = nil
    }

    private func 실제로_확보한다() async {
        defer { 진행중 = false }
        do {
            let uid = try await AuthGateway.uid()
            let familyId: String
            if RoleStore.shared.role == .guardian, let existing = RoleStore.shared.familyId {
                // 이미 만든 가족이 있으면 다시 만들지 않는다 — 안드로이드
                // `GuardianPairingActivity.startPairing()` 의 `store.familyId ?:
                // FamilyRepository.createFamily(...).also { store.familyId = it }`
                // 와 같은 불변식이다.
                familyId = existing
            } else {
                familyId = try await FamilyRepository.createFamily(guardianUid: uid)
                RoleStore.shared.role = .guardian
                RoleStore.shared.familyId = familyId
            }

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if let 만료시각, 만료시각 > now {
                // 들고 있는 코드가 아직 안 죽었다 — 다시 받을 필요 없다.
                // 뒤로 나갔다 돌아온 것만으로 매번 새 코드를 발급하면, 이미
                // 상대 폰에 불러준 코드가 화면을 나갔다 돌아오는 사이에
                // 조용히 바뀌어버린다.
                return
            }
            // 죽었으면(또는 처음이면) 새로 받는다. `previousCode` 로 죽은
            // 코드 문서를 정리한다 — 안드로이드 `refreshCode()` 와 같은 뒷정리다.
            let info = try await FamilyRepository.createInvite(
                familyId: familyId, role: .child, previousCode: 코드
            )
            코드 = info.code
            만료시각 = info.expiresAt
        } catch is CancellationError {
            // 소유자(RoleSelectView)가 사라지며 `invalidate()` 가 이 Task 를
            // 취소한 것이다. 정상 종료지 오류가 아니다.
            return
        } catch {
            Self.logger.error("초대 코드 발급 실패: \(String(describing: error), privacy: .public)")
            오류 = String(localized: "error_unknown")
        }
    }

    /// 아이가 실제로 들어오는 순간을 감시한다. 화면이 보이는 동안에만
    /// 부른다(`InviteCodeView.task`) — 코드를 발급하는 일과 달리 감시는
    /// 화면이 없을 때 해봐야 소용이 없으므로, 화면이 사라지면
    /// `듣기를_멈춘다()` 로 끈다.
    func 듣기를_시작한다() {
        guard !무효화됨, 아이_리스너 == nil, let familyId = RoleStore.shared.familyId, 코드 != nil else { return }
        if RoleStore.shared.childUid != nil {
            // 이미 다른 경로(예: 재진입 전에 끝난 감시)로 아이가 기록돼
            // 있으면 다시 들을 이유 없이 바로 다음으로 넘어간다.
            onDone()
            return
        }
        아이_리스너 = FamilyRepository.observeChildJoined(
            familyId: familyId,
            preferredChildUid: nil,
            onJoined: { [weak self] childUid in
                Task { @MainActor in
                    // `self` 가 이미 무효화됐으면(소유자가 사라졌으면) 아무
                    // 것도 하지 않는다 — 무효화된 세션이 뒤늦게 RouterView
                    // 를 건드려 사용자가 지금 보고 있는 화면과 무관하게
                    // 지도로 튕겨나가면 안 된다.
                    guard let self, !self.무효화됨 else { return }
                    RoleStore.shared.childUid = childUid
                    self.onDone()
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

    /// 화면이 사라질 때(뒤로가기 등) 부른다. **듣기만 멈춘다 — 가족·코드
    /// 확보 작업까지 취소하지는 않는다.** 취소해도 이미 서버로 나간 쓰기는
    /// 막을 수 없고, 그 결과(가족, 코드)는 나중에 다시 들어왔을 때도 여전히
    /// 쓸모 있다 — 여기서 취소하면 오히려 "돌아왔는데 처음부터 다시" 가 된다.
    func 듣기를_멈춘다() {
        아이_리스너?.remove()
        아이_리스너 = nil
    }

    /// 이 세션의 소유자(`RoleSelectView`)가 사라질 때, 또는 "역할 다시
    /// 고르기"로 세션 자체가 완전히 버려질 때 부른다. 이후로는 진행 중이던
    /// 시도가 뒤늦게 끝나더라도 `onDone()` 을 부르지 않는다 — 소유자가 이미
    /// 없는 세션이 뒤늦게 `RouterView` 를 건드리면, 사용자가 지금 실제로
    /// 보고 있는 화면과 무관하게 지도로 튕겨나간다(2차 리뷰의 Critical).
    func invalidate() {
        무효화됨 = true
        준비_작업?.cancel()
        아이_리스너?.remove()
        아이_리스너 = nil
    }
}
