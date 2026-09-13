import FirebaseFirestore
import Foundation
import Observation

/// N:N 자녀 선택기. 정본은 `GuardianMainActivity.kt` 의 `subscribeMembers`·`applyMembers`·`childLabel`·
/// `showChildMenu`·`selectChild`·`openInvite`(:185-286).
///
/// **아이를 바꿔도 살아남는다.** `GuardianHomeView` 가 소유하고, 선택이 바뀌면 그 안의 `GuardianRootView` 만
/// `.id(childUid)` 로 다시 만들어진다(안드로이드가 액티비티는 두고 프래그먼트만 다시 만드는 것, :288-300 —
/// 계획서 판정 기록 7). 선택 결과는 `RoleStore.childUid` 하나에만 적는다. 서버에는 쓰지 않는다(판정 기록 6).
///
/// ## 정리 뒤에는 아무것도 만지지 않는다
/// `닫힘` 규율은 `AlertViewModel`·`InviteSession` 과 같다. 멤버 리스너 콜백은 `remove()` 직전에 대기열에 올라 있을
/// 수 있어 첫 줄에서 닫힘을 본다. 초대의 합류 알림은 `초대_세대` 로 가른다 — 닫은 초대가 늦게 알려 와도 지금 열린
/// 초대를 닫거나 아이 선택을 바꾸지 않는다.
@MainActor
@Observable
final class ChildSelectorModel {

    typealias InviteFactory = @MainActor (
        _ familyId: String, _ role: MemberRole, _ onJoined: @escaping @MainActor (FamilyMember) -> Void
    ) -> InviteSession

    let familyId: String
    /// 실기기 읽기 전용 확인(-readOnlyCheck). 켜져 있으면 `초대한다` 가 초대 세션을 만들지 않는다.
    let 읽기_전용: Bool
    private(set) var children: [FamilyMember] = []
    private(set) var guardians: [FamilyMember] = []
    /// 멤버 구독이 실패했다(:191). 다음 스냅샷이 오면 풀린다.
    private(set) var 불러오기_실패 = false
    /// 열려 있는 초대 한 판. nil 이면 번호 화면이 닫혀 있다.
    private(set) var 초대: InviteSession?

    private let roleStore: RoleStore
    private let membersObserve: InviteSession.Observe
    private let inviteFactory: InviteFactory
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var 시작함 = false
    /// `정리한다()` 뒤로는 구독도 선택 변경도 초대도 새로 만들지 않는다. 되돌려지지 않는다.
    @ObservationIgnored private var 닫힘 = false
    @ObservationIgnored private var 초대_세대 = 0

    init(
        familyId: String,
        roleStore: RoleStore,
        읽기_전용: Bool = ReadOnlyCheck.isOn,
        membersObserve: @escaping InviteSession.Observe = FamilyRepository.observeMembers,
        inviteFactory: @escaping InviteFactory = { familyId, role, onJoined in
            InviteSession(familyId: familyId, role: role, onJoined: onJoined)
        }
    ) {
        self.familyId = familyId
        self.roleStore = roleStore
        self.읽기_전용 = 읽기_전용
        self.membersObserve = membersObserve
        self.inviteFactory = inviteFactory
    }

    var selectedUid: String? { roleStore.childUid }

    /// 선택기 줄의 글(:218-225). 구독 실패면 그 사실을 적는다(:191).
    var 줄_문구: String {
        if 불러오기_실패 { return String(localized: "child_selector_load_failed") }
        guard let selected = children.first(where: { $0.uid == selectedUid }) else {
            return String(localized: "child_selector_empty")
        }
        return String(format: String(localized: "child_selector_value"), 라벨(selected))
    }

    /// 지도 카드의 아이 이름(`selectedChildLabelText`, :227-231).
    var 지도_이름: String {
        children.first(where: { $0.uid == selectedUid }).map(라벨) ?? String(localized: "child_default_name")
    }

    /// '＋ 보호자 초대 · 현재 N명'(:251-256).
    ///
    /// 마지막 " · " 뒤의 수 조각 안 공백만 U+00A0 으로 바꾼다(6단계 S1, 알림 시각 A1 과 같은 처리). 메뉴 줄이 좁으면
    /// "현재 / 1명" 처럼 어구 중간에서 접히기 때문이다. 앞쪽 문구와 구분자, i18n 원본은 그대로다 — 줄은 구분자에서 접힌다.
    /// 구분자가 없는 번역이면 손대지 않는다.
    var 보호자_초대_문구: String {
        Self.수_조각을_붙인다(String(format: String(localized: "child_selector_add_guardian_count"), guardians.count))
    }

    static func 수_조각을_붙인다(_ 문구: String) -> String {
        guard let 구분 = 문구.range(of: " · ", options: .backwards) else { return 문구 }
        return 문구[..<구분.upperBound] + 문구[구분.upperBound...].replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// 이름이 겹치는 아이는 uid 끝 네 자리로 가른다(:233-237). 두 아이가 다 "아이"면 메뉴에서 구분이 안 된다.
    func 라벨(_ child: FamilyMember) -> String {
        let base = Self.이름(child)
        return children.filter { Self.이름($0) == base }.count > 1 ? "\(base) · \(child.uid.suffix(4))" : base
    }

    /// 본 화면이 뜰 때 구독한다(:182). 두 번째부터는 무시한다.
    func 시작한다() {
        guard !시작함, !닫힘 else { return }
        시작함 = true
        listener = membersObserve(familyId, { [weak self] members in
            Task { @MainActor in self?.멤버를_반영한다(members) }
        }, { [weak self] _ in
            Task { @MainActor in self?.구독이_실패했다() }
        })
    }

    /// 메뉴에서 아이를 골랐다(:271-278). 같은 아이면 아무 일도 하지 않는다 — 다시 적으면 탭이 괜히 다시 만들어진다.
    func 고른다(_ uid: String) {
        guard !닫힘, roleStore.childUid != uid else { return }
        roleStore.childUid = uid
    }

    /// '＋ 아이 추가'·'＋ 보호자 초대'(:280-286). 이미 열린 초대가 있으면 새로 열지 않는다.
    /// 세션은 여기, 버튼 액션에서 만든다 — 뷰 빌더 안에서 만들면 한 번의 표시에 여러 번 만들어진다(`NewFamilySession` 주석).
    ///
    /// 읽기 전용 확인에서는 메뉴 줄의 `.disabled` 에만 기대지 않고 여기서도 막는다(6단계 통합 검토 I3) — 지도 카드 메뉴
    /// 변형이나 딥 링크처럼 이 함수를 부르는 입구가 늘어도 진짜 가족에 `inviteCodes` 문서가 생기지 않는다.
    func 초대한다(_ role: MemberRole) {
        guard !닫힘, !읽기_전용, 초대 == nil else { return }
        초대_세대 += 1
        let 세대 = 초대_세대
        초대 = inviteFactory(familyId, role) { [weak self] member in
            self?.초대로_들어왔다(member, 세대: 세대)
        }
    }

    /// 번호 화면을 닫는다(뒤로 버튼, 합류 완료, 정리). 세대를 올려 닫은 초대의 늦은 알림을 무해하게 만든다.
    func 초대를_닫는다() {
        초대_세대 += 1
        초대?.정리한다()
        초대 = nil
    }

    /// 본 화면이 사라진다(`onDestroy`, :423-428).
    func 정리한다() {
        닫힘 = true
        listener?.remove()
        listener = nil
        초대를_닫는다()
    }

    /// `applyMembers`(:195-216). 옛 가족 자료 옮기기(:209-212)는 하지 않는다(판정 기록 6).
    private func 멤버를_반영한다(_ members: [FamilyMember]) {
        guard !닫힘 else { return }
        불러오기_실패 = false
        let next = members.filter { $0.role == MemberRole.child.rawValue }
        guardians = members.filter { $0.role == MemberRole.guardian.rawValue }
        children = next
        let selected = ChildSelector.select(
            children: next.map { SelectableChild(uid: $0.uid, displayName: $0.displayName, joinedAt: $0.joinedAt) },
            preferredUid: roleStore.childUid
        )
        if roleStore.childUid != selected?.uid {
            roleStore.childUid = selected?.uid
        }
    }

    /// 구독 오류(:191). 마지막으로 받은 목록은 비우지 않는다 — 안드로이드도 글자만 바꾼다.
    private func 구독이_실패했다() {
        guard !닫힘 else { return }
        불러오기_실패 = true
    }

    /// `goToMain`(GuardianPairingActivity.kt:217-230): 아이가 들어왔으면 그 아이를 고른다. 보호자면 닫기만 한다.
    private func 초대로_들어왔다(_ member: FamilyMember, 세대: Int) {
        guard !닫힘, 세대 == 초대_세대, 초대 != nil else { return }
        if member.role == MemberRole.child.rawValue {
            roleStore.childUid = member.uid
        }
        초대를_닫는다()
    }

    private static func 이름(_ child: FamilyMember) -> String {
        child.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "child_default_name")
            : child.displayName
    }
}
