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

    @Environment(\.dismiss) private var dismiss

    @State private var 코드: String?
    @State private var 진행중 = true
    @State private var 오류: String?

    /// 이 인스턴스가 `Self.아이_리스너` 를 직접 붙인 장본인인지. 재진입이 만드는
    /// 다른 인스턴스가 이미 붙여둔 리스너라면 이 인스턴스는 그걸 모르므로(각자
    /// `@State` 라서), "내가 붙였다"는 사실 자체를 이 플래그로 따로 기억해둬야
    /// `onDisappear` 에서 남의 리스너를 잘못 지우지 않는다.
    @State private var 이_화면이_리스너를_붙였다 = false

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "InviteCodeView")

    /// `.newFamily` 한 판(가족 확보 → 초대 코드 발급)을 **프로세스 전체에서 딱
    /// 한 세트만** 돌게 지키는 손잡이. 왜 인스턴스별 `@State` 로는 부족한지는
    /// `새_가족_코드를_확보한다()` 주석 참고.
    @MainActor private static var 준비_작업: Task<String, Error>?

    /// 아이 합류를 감시하는 리스너. 인스턴스 하나가 아니라 타입 전체가
    /// 공유한다 — 재진입이 만드는 새 인스턴스가 자기 것도 하나 더 붙이면
    /// 같은 쿼리를 중복으로 구독해 Firestore 읽기 비용이 배로 나간다.
    @MainActor private static var 아이_리스너: ListenerRegistration?

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
                // 재사용하던 familyId 가 죽어(가족 삭제, 멤버 제거 등) 이 화면이
                // 막다른 골목이 될 수 있다. 안드로이드 GuardianPairingActivity 의
                // 되돌리기(resetRoleButton)와 같은 탈출구 — 저장소를 지우고
                // 역할 선택으로 돌려보낸다.
                Button("pairing_reset") { 역할을_다시_고른다() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .task { await 발급한다() }
        .onDisappear {
            // 이 인스턴스가 실제로 붙인 리스너일 때만 치운다. 재진입으로 생긴
            // 다른 인스턴스가 대신 붙였다면, 그 리스너는 그 인스턴스가 사라질
            // 때 자기 책임으로 치운다 — 아직 화면에 남아 화면을 지켜보는 중일
            // 수도 있는 리스너를, 방금 스쳐 지나간 유령 인스턴스가 걷어차면 안
            // 된다.
            if 이_화면이_리스너를_붙였다 {
                Self.아이_리스너?.remove()
                Self.아이_리스너 = nil
                이_화면이_리스너를_붙였다 = false
            }
        }
    }

    private func 발급한다() async {
        진행중 = true
        오류 = nil
        defer { 진행중 = false }
        do {
            let (familyId, role): (String, MemberRole)
            switch mode {
            case .newFamily:
                코드 = try await Self.새_가족_코드를_확보한다()
                (familyId, role) = (RoleStore.shared.familyId ?? "", .child)
            case let .invite(id, r):
                // 로그인만 확인해둔다 — createInvite 자체는 uid 를 안 받지만
                // 규칙이 인증된 호출만 허용한다.
                _ = try await AuthGateway.uid()
                코드 = try await FamilyRepository.createInvite(
                    familyId: id, role: r, previousCode: nil
                ).code
                (familyId, role) = (id, r)
            }
            if role == .child, !familyId.isEmpty { 아이를_기다린다(familyId: familyId) }
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

    /// 가족을 확보하고(있으면 재사용, 없으면 새로 만들고) 자녀용 초대 코드를
    /// 발급한다. **`.newFamily` 처리 전체를 프로세스에 하나뿐인 `Task` 뒤에
    /// 가둔다** — 인스턴스별 `@State` 가드(1차 수정)는 절반짜리였다: 재진입이
    /// 만드는 새 인스턴스는 첫 인스턴스의 `@State` 를 전혀 모르는 별개의
    /// 저장소라서, `createInvite()` 재호출과 리스너 중복 부착까지는 못
    /// 막았다(2차 리뷰가 실측 없이도 정확히 짚은 지점). 그리고 두 인스턴스의
    /// `.task` 가 `createFamily()` 가 끝나기도 **전에** 동시에 "아직 없다"를
    /// 보고 겹쳐 도는 경합(TOCTOU)은, 인스턴스 하나가 자기 `Task` 를 스스로
    /// 취소하는 방식으로는 아예 닿을 수 없다 — 취소는 서로 다른 저장소를 가진
    /// 상대 인스턴스에 전달할 방법이 없기 때문이다. 그래서 `AuthGateway.
    /// signInInternal()` 이 동시 로그인을 막는 것과 같은 손잡이(타입 하나에
    /// 공유되는 in-flight `Task`)를 그대로 가져왔다: 두 번째 호출은 새
    /// `createFamily()`/`createInvite()` 를 부르지 않고 첫 번째가 진행 중인
    /// `Task` 를 그대로 기다린다. `Task` 는 끝난 뒤에도 `.value` 를 다시
    /// 물으면 캐시된 결과를 그대로 주므로, 재진입이 몇 초 뒤에 와도 새
    /// 네트워크 호출 없이 같은 코드를 받는다 — 재시도가 하나도 안 겹칠
    /// 뿐더러, "화면이 사라질 때 취소" 같은 타이밍에 기대지 않아도 되어 더
    /// 확실하다(취소는 작업이 그 사이에 이미 다 끝나버리면 손을 못 쓴다).
    ///
    /// 실패하면 캐시로 남겨두지 않는다 — 안 남기면 "역할 다시 고르기" 뒤의
    /// 진짜 재시도가 매번 같은 옛 실패를 돌려받는 사고를 막는다.
    private static func 새_가족_코드를_확보한다() async throws -> String {
        if let inFlight = 준비_작업 {
            do {
                return try await inFlight.value
            } catch {
                준비_작업 = nil
                throw error
            }
        }
        let task = Task<String, Error> {
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
            return try await FamilyRepository.createInvite(
                familyId: familyId, role: .child, previousCode: nil
            ).code
        }
        준비_작업 = task
        do {
            return try await task.value
        } catch {
            준비_작업 = nil
            throw error
        }
    }

    /// 코드를 보여준 뒤 아이가 실제로 들어오는 순간을 감시한다 — 그래야 이 화면이
    /// "아이가 연결됐다"를 스스로 알고 다음으로 넘어갈 수 있다(안드로이드
    /// `GuardianPairingActivity` 와 같은 얼개). 리스너를 타입 전체가 공유하는
    /// 이유는 위 `준비_작업` 과 같다 — 재진입이 만드는 새 인스턴스가 이미 붙은
    /// 리스너를 모른 채 자기 것도 붙이면 같은 쿼리를 중복 구독하게 된다.
    /// `RoleStore.shared` 는 `@MainActor` 라 리스너 콜백(메인 스레드라는 보장이
    /// 없는 자리) 안에서 곧장 건드리면 안 되고, `Task { @MainActor in }` 로
    /// 건너가야 한다 — `FamilyRepository` 의 콜백 타입 자체는 격리를 강제하지
    /// 않으므로(그래야 다른 화면이 다른 방식으로 쓸 수 있다) 그 책임은 부르는
    /// 쪽인 여기에 있다.
    private func 아이를_기다린다(familyId: String) {
        // 이미 다른 인스턴스가 붙여뒀으면 하나 더 붙이지 않는다. 이 사이에
        // `await` 가 없어 두 인스턴스가 동시에 이 검사를 통과할 수 없다(둘 다
        // MainActor 위에서 끊기지 않고 도는 코드라서) — `준비_작업` 의 in-flight
        // 검사와 같은 원리다.
        guard Self.아이_리스너 == nil else { return }
        // 재진입으로 생긴 인스턴스가 여기 왔을 땐, 진짜 화면이 이미 아이를
        // 찾아 `RoleStore.shared.childUid` 를 채우고 넘어간 뒤일 수 있다 —
        // 그러면 다시 들을 이유가 없다. 리스너를 붙였다 곧바로 (이 인스턴스가
        // 사라지며) 떼는 헛수고 한 판을 아예 건너뛴다.
        if RoleStore.shared.childUid != nil {
            onDone()
            return
        }
        이_화면이_리스너를_붙였다 = true
        Self.아이_리스너 = FamilyRepository.observeChildJoined(
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

    /// 죽은 familyId 에 갇혔을 때의 탈출구. 안드로이드 `GuardianPairingActivity.
    /// resetRoleButton` 과 같은 순서를 따른다 — 진행 중이던 손잡이를 먼저 치우고
    /// (남의 화면에 새어나가지 않게), 저장소를 비운 뒤, 역할 선택으로 돌아간다.
    private func 역할을_다시_고른다() {
        Self.아이_리스너?.remove()
        Self.아이_리스너 = nil
        Self.준비_작업 = nil
        RoleStore.shared.clear()
        dismiss()
    }
}
