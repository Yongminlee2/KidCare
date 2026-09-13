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
/// 길이 없다. 아이 폰은 계속 기록을 올리지만 읽을 사람이 없다. 그래서 마지막 보호자에게는 기본 문구("새 초대 번호를 받아야
/// 해요")를 붙이지 않고 따로 쓴 문구를 보인다 — 되돌릴 수 없는 동작 앞에서 "다시 들어올 길이 있다"고 말하면 안 된다(리뷰 I2).
///
/// **확인하지 못함은 실패가 아니다(리뷰 I1).** 커밋 요청이 서버에 닿고 응답만 잃었거나, 15초 뒤에 늦게 커밋되면 서버에서는
/// 이미 빠졌다. 그래서 시간 초과·서버에 닿지 못함은 "빼지 못했다"가 아니라 "확인하지 못했다, 연결된 뒤 다시 눌러 달라"고 말한다.
/// 다시 누르면 `removeMember` 의 "이미 빠짐" 판정이 성공으로 받아 계정과 이 폰의 기록까지 마무리한다.
@MainActor
@Observable
final class LeaveFamilyModel {

    typealias RemoveMember = @Sendable (_ familyId: String, _ uid: String) async throws -> Void
    typealias DeleteAuth = @Sendable () async -> LeaveFamilyRepository.AuthOutcome
    /// 계정 삭제가 시간 안에 끝나지 않을 때 물러나는 길. 로그아웃이 정말 됐는지까지 보고 결과를 돌려준다.
    typealias SignOut = @MainActor () -> LeaveFamilyRepository.AuthOutcome
    /// 빠진 뒤 첫 화면이 결과를 알리게 한다. 이 모델은 본 화면과 함께 사라지므로 결과를 들고 있을 수 없다.
    typealias OnLeft = @MainActor (LeaveFamilyRepository.AuthOutcome?) -> Void

    /// 서버 확인을 기다리는 한도. `FamilyRepository.measureTimeoutNanos`(15초)와 같은 값이다 — 둘 다 "오프라인이면
    /// 서버 확인이 영영 안 온다"는 같은 사실을 막는 장치다.
    nonisolated static let timeoutMillis: Int64 = 15_000
    /// 계정 삭제를 기다리는 한도. 멤버 문서는 이미 지워졌으므로 여기서 오래 붙들 이유가 없다 — 느린 망에서 덮개가 끝없이
    /// 떠 있으면 부모가 앱을 꺼 버리고, 그러면 역할이 남은 채 서버에서는 빠진 상태가 된다(리뷰 I1 c).
    nonisolated static let authTimeoutMillis: Int64 = 10_000

    /// 알림 제목과 본문. 실패와 "확인하지 못함"은 제목부터 다르다.
    struct 안내: Equatable, Sendable {
        let 제목: String
        let 문구: String
    }

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
    private(set) var 실패: 안내?
    private(set) var 계정_결과: LeaveFamilyRepository.AuthOutcome?

    @ObservationIgnored private let currentUid: @Sendable () -> String?
    @ObservationIgnored private let removeMember: RemoveMember
    @ObservationIgnored private let deleteAuth: DeleteAuth
    @ObservationIgnored private let signOut: SignOut
    /// 이 폰의 기록을 지우기 **전에** 떼야 할 것들(선택기, 다섯 탭). 뷰가 나타날 때 걸고 사라질 때 뗀다(리뷰 M3).
    @ObservationIgnored private var 떠나기_전_정리: [UUID: @MainActor () -> Void] = [:]
    @ObservationIgnored private let clearLocal: @MainActor () -> Void
    @ObservationIgnored private let onLeft: OnLeft
    @ObservationIgnored private let sleep: @Sendable (Int64) async -> Void

    init(
        familyId: String,
        읽기_전용: Bool = ReadOnlyCheck.isOn,
        currentUid: @escaping @Sendable () -> String? = { AuthGateway.currentUid() },
        removeMember: @escaping RemoveMember = { try await LeaveFamilyRepository.removeMember(familyId: $0, uid: $1) },
        deleteAuth: @escaping DeleteAuth = { await LeaveFamilyRepository.deleteAuthUser() },
        signOut: @escaping SignOut = { LeaveFamilyRepository.signOut() },
        clearLocal: @escaping @MainActor () -> Void = { LeaveFamilyModel.이_폰의_기록을_지운다() },
        onLeft: @escaping OnLeft = { _ in },
        sleep: @escaping @Sendable (Int64) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }
    ) {
        self.familyId = familyId
        self.읽기_전용 = 읽기_전용
        self.currentUid = currentUid
        self.removeMember = removeMember
        self.deleteAuth = deleteAuth
        self.signOut = signOut
        self.clearLocal = clearLocal
        self.onLeft = onLeft
        self.sleep = sleep
    }

    /// 확인 대화상자 본문. 보호자가 이 폰 하나(또는 아직 목록을 못 받은 0)면 마지막 보호자용 문구를 따로 쓴다 — 막지는 않는다.
    /// 기본 문구를 뒤에 붙이지 않는 이유는 머리 주석의 "마지막 보호자".
    static func 확인_문구(보호자_수: Int) -> String {
        보호자_수 <= 1
            ? String(localized: "leave_family_last_guardian_message")
            : String(localized: "leave_family_message")
    }

    /// 빠진 뒤 첫 화면에 알리는 글. 계정까지 지웠는지, 로그아웃만 했는지를 있는 그대로 말한다.
    static func 끝_문구(_ outcome: LeaveFamilyRepository.AuthOutcome) -> String {
        switch outcome {
        case .deleted: String(localized: "leave_family_done_message")
        case .signedOutOnly: String(localized: "leave_family_done_signed_out_message")
        case .notSignedOut: String(localized: "ios_leave_family_done_not_signed_out_message")
        }
    }

    /// 서버 확인이 시간 안에 오지 않았다. 서버에서는 이미 빠졌을 수도 있으므로 실패라고 말하지 않는다.
    static var 확인하지_못함: 안내 {
        안내(
            제목: String(localized: "ios_leave_family_unconfirmed_title"),
            문구: String(localized: "leave_family_unconfirmed_message")
        )
    }

    /// 서버에 닿지 못했거나 기한을 넘긴 오류는 시간 초과와 같은 안내다 — 커밋이 서버에 닿았는지 알 수 없고, 부모가 할 일도
    /// 같다("연결된 뒤 다시"). 거부 등 서버가 분명히 답한 오류만 "빼지 못했어요"다.
    static func 실패_안내(for error: Error) -> 안내 {
        let ns = error as NSError
        let 알_수_없음: Set<Int> = [FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue]
        if ns.domain == FirestoreErrorDomain && 알_수_없음.contains(ns.code) {
            return 확인하지_못함
        }
        return 안내(제목: String(localized: "leave_family_failed_title"), 문구: errorMessage(error))
    }

    /// 이 폰의 기록을 지우기 전에 부를 정리를 건다. 같은 열쇠로 다시 걸면 바꾼다.
    func 떠나기_전에(_ 열쇠: UUID, 정리: @escaping @MainActor () -> Void) {
        떠나기_전_정리[열쇠] = 정리
    }

    /// 뷰가 사라질 때 건 정리를 뗀다(그 뷰는 자기 onDisappear 에서 이미 정리한다).
    func 정리를_뗀다(_ 열쇠: UUID) {
        떠나기_전_정리[열쇠] = nil
    }

    func 묻는다() {
        guard !읽기_전용, !빼는중 else { return }
        실패 = nil
        묻는중 = true
    }

    func 취소한다() {
        묻는중 = false
    }

    func 실패를_닫는다() {
        실패 = nil
    }

    func 뺀다() async {
        guard !읽기_전용, !빼는중 else { return }
        묻는중 = false
        빼는중 = true
        실패 = nil
        defer { 빼는중 = false }

        guard let uid = currentUid() else {
            // 본 화면에 있는데 로그인 정보가 없다(키체인 접근 실패 등, 리뷰 M4). 이 폰으로 가족에 들어왔으니 서버에는 멤버
            // 문서가 있을 것이다. 이 폰만 지우면 그 문서가 영영 남으므로 아무것도 지우지 않고 그렇다고 알린다.
            실패 = 안내(
                제목: String(localized: "leave_family_failed_title"),
                문구: String(localized: "leave_family_no_account")
            )
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
                실패 = Self.확인하지_못함
                return
            }
        } catch {
            실패 = Self.실패_안내(for: error)
            return
        }
        // 서버에서는 빠졌다. 선택기·탭 리스너와 그 콜백이 이 폰의 기록(RoleStore.childUid, 명령 기록, 못 보낸 알림 깃발)을
        // 다시 쓰지 못하게 기록을 지우기 전에, 그리고 계정 삭제를 기다리기 전에 뗀다(리뷰 M3).
        let 정리들 = 떠나기_전_정리.values
        떠나기_전_정리.removeAll()
        for 정리 in 정리들 { 정리() }

        let deleteAuth = deleteAuth
        let 삭제_결과 = try? await firstToFinish(timeoutMillis: Self.authTimeoutMillis, sleep: sleep) {
            await deleteAuth()
        }
        // 시간 안에 답이 없으면 로그아웃으로 물러난다. 늦게 끝난 삭제는 무해하다(어느 쪽이든 이 폰에서는 끝이다).
        let outcome = 삭제_결과 ?? signOut()
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
