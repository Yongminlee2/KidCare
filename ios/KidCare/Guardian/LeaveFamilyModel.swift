import FirebaseFirestore
import Foundation
import Observation

/// "이 아이폰을 가족에서 빼기"의 판단(7단계 계획서 판정 기록 8). 순서는 **서버 확인 → 계정 → 이 폰** 이다.
///
/// 서버가 확인하기 전에 이 폰의 기록을 지우면, 가족에는 이 폰이 남았는데 이 폰은 빠졌다고 믿는 상태가 된다 — 그러면
/// 다시 합류해도 옛 멤버 문서가 영영 남는다. 그래서 서버 확인이 오기 전에는 아무것도 지우지 않는다. 확인되지 않은 삭제가
/// 나중에 몰래 서버에 닿지 않게 하는 것은 `LeaveFamilyRepository.removeMember` 의 몫이다(트랜잭션).
///
/// **마지막 보호자.** 막지 않는다 — 삭제를 막으면 5.1.1(v) 위반이다. 규칙상 보호자가 없는 가족은 아무도 초대 코드를
/// 만들 수 없고(`inviteCodes` create 가 `roleIn == 'guardian'`), 가족을 만든 익명 계정도 사라지므로 보호자 자리를 되찾을
/// 길이 없다. 아이 폰은 계속 기록을 올리지만 읽을 사람이 없다. 그래서 확인 문구 앞에 그 사실과 할 일을 붙인다.
@MainActor
@Observable
final class LeaveFamilyModel {

    typealias RemoveMember = @Sendable (_ familyId: String, _ uid: String) async throws -> Void
    typealias DeleteAuth = @Sendable () async -> LeaveFamilyRepository.AuthOutcome
    /// 빠진 뒤 첫 화면이 결과를 알리게 한다. 이 모델은 본 화면과 함께 사라지므로 결과를 들고 있을 수 없다.
    typealias OnLeft = @MainActor (LeaveFamilyRepository.AuthOutcome?) -> Void

    /// 서버 확인을 기다리는 한도. `FamilyRepository.measureTimeoutNanos`(15초)와 같은 값이다 — 둘 다 "오프라인이면
    /// 서버 확인이 영영 안 온다"는 같은 사실을 막는 장치다.
    nonisolated static let timeoutMillis: Int64 = 15_000

    /// 이 앱이 `UserDefaults.standard` 에 쓰는 가족 기록의 키 머리. `RoleStore` 의 세 키는 `RoleStore.clear()` 가 지운다.
    /// `RequestLog`(last_request_at_/last_answer_at_), `AlarmMemoStore`(alarm_memo_), `RuleSyncStore`
    /// (schedule_sync_…/place_sync_…). 저장소가 키를 바꾸면 `LeaveFamilyModelTests.이_폰의_기록` 이 실패한다.
    static let 이_앱의_키_머리 = [
        "last_request_at_", "last_answer_at_", "alarm_memo_",
        "\(RuleSyncStore.Kind.schedule.rawValue)_sync_pending_sync_",
        "\(RuleSyncStore.Kind.place.rawValue)_sync_pending_sync_",
    ]

    let familyId: String
    /// 실기기 읽기 전용 확인(-readOnlyCheck). 켜져 있으면 묻지도 빼지도 않는다 — 메뉴 줄의 `.disabled` 는 표시용이다.
    let 읽기_전용: Bool
    private(set) var 묻는중 = false
    private(set) var 빼는중 = false
    private(set) var 실패_문구: String?
    private(set) var 계정_결과: LeaveFamilyRepository.AuthOutcome?

    @ObservationIgnored private let currentUid: @Sendable () -> String?
    @ObservationIgnored private let removeMember: RemoveMember
    @ObservationIgnored private let deleteAuth: DeleteAuth
    @ObservationIgnored private let clearLocal: @MainActor () -> Void
    @ObservationIgnored private let onLeft: OnLeft
    @ObservationIgnored private let sleep: @Sendable (Int64) async -> Void

    init(
        familyId: String,
        읽기_전용: Bool = ReadOnlyCheck.isOn,
        currentUid: @escaping @Sendable () -> String? = { AuthGateway.currentUid() },
        removeMember: @escaping RemoveMember = { try await LeaveFamilyRepository.removeMember(familyId: $0, uid: $1) },
        deleteAuth: @escaping DeleteAuth = { await LeaveFamilyRepository.deleteAuthUser() },
        clearLocal: @escaping @MainActor () -> Void = { LeaveFamilyModel.이_폰의_기록을_지운다() },
        onLeft: @escaping OnLeft = { _ in },
        sleep: @escaping @Sendable (Int64) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }
    ) {
        self.familyId = familyId
        self.읽기_전용 = 읽기_전용
        self.currentUid = currentUid
        self.removeMember = removeMember
        self.deleteAuth = deleteAuth
        self.clearLocal = clearLocal
        self.onLeft = onLeft
        self.sleep = sleep
    }

    /// 확인 대화상자 본문. 보호자가 이 폰 하나(또는 아직 목록을 못 받은 0)면 경고를 앞에 붙인다 — 막지는 않는다.
    static func 확인_문구(보호자_수: Int) -> String {
        let base = String(localized: "ios_leave_family_message")
        guard 보호자_수 <= 1 else { return base }
        return String(format: String(localized: "ios_leave_family_last_guardian_format"), base)
    }

    /// 빠진 뒤 첫 화면에 알리는 글. 계정까지 지웠는지, 로그아웃만 했는지를 있는 그대로 말한다.
    static func 끝_문구(_ outcome: LeaveFamilyRepository.AuthOutcome) -> String {
        switch outcome {
        case .deleted: String(localized: "ios_leave_family_done_message")
        case .signedOutOnly: String(localized: "ios_leave_family_done_signed_out_message")
        }
    }

    /// 서버에 닿지 못한 오류는 시간 초과와 같은 안내를 쓴다 — 부모가 할 일이 같다("연결된 뒤 다시").
    static func 실패_문구(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FirestoreErrorDomain && ns.code == FirestoreErrorCode.unavailable.rawValue {
            return String(localized: "ios_leave_family_offline")
        }
        return errorMessage(error)
    }

    func 묻는다() {
        guard !읽기_전용, !빼는중 else { return }
        실패_문구 = nil
        묻는중 = true
    }

    func 취소한다() {
        묻는중 = false
    }

    func 실패를_닫는다() {
        실패_문구 = nil
    }

    func 뺀다() async {
        guard !읽기_전용, !빼는중 else { return }
        묻는중 = false
        빼는중 = true
        실패_문구 = nil
        defer { 빼는중 = false }

        guard let uid = currentUid() else {
            // 로그인한 적이 없으면 서버에 이 폰의 흔적이 없다. 이 폰의 기록만 지운다.
            onLeft(nil)
            clearLocal()
            return
        }
        let familyId = familyId
        let removeMember = removeMember
        do {
            let confirmed = try await firstToFinish(timeoutMillis: Self.timeoutMillis, sleep: sleep) {
                try await removeMember(familyId, uid)
                return true
            }
            guard confirmed == true else {
                실패_문구 = String(localized: "ios_leave_family_offline")
                return
            }
        } catch {
            실패_문구 = Self.실패_문구(for: error)
            return
        }
        let outcome = await deleteAuth()
        계정_결과 = outcome
        onLeft(outcome)
        clearLocal()
    }

    /// 이 폰에 남은 가족 기록을 지운다. 역할·가족·아이(`RoleStore`), 명령 기록(`RequestLog`), 알람 메모(`AlarmMemoStore`),
    /// 못 보낸 알림 깃발(`RuleSyncStore`)이 모두 같은 `UserDefaults.standard` 에 있다.
    ///
    /// **도메인을 통째로 지우지 않는다**(`removePersistentDomain`). 같은 도메인에 설정 앱의 앱별 언어(`AppleLanguages`)가
    /// 있다. 이 앱은 언어를 그 설정으로 고르게 하므로(선택기 줄의 지구본), 통째로 지우면 가족에서 빠지는 순간 언어가 바뀐다.
    static func 이_폰의_기록을_지운다(defaults: UserDefaults = .standard, roleStore: RoleStore = RoleStore.shared) {
        for key in defaults.dictionaryRepresentation().keys where 이_앱의_키_머리.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
        // 마지막에 부른다 — RouterView 가 familyId 가 nil 이 되는 것을 보고 첫 화면으로 간다.
        roleStore.clear()
    }
}
