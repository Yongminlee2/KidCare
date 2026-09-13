import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// 정본은 `GuardianMainActivity.kt` 의 선택기 부분. 줄 번호는 테스트 이름에 적는다.
@MainActor
struct ChildSelectorModelTests {

    final class 가짜_구독: Sendable {
        let onChange = TestCallbackBox<([FamilyMember]) -> Void>()
        let onError = TestCallbackBox<(Error) -> Void>()
        let registration = TestListenerRegistration()
        private let 횟수_잠금 = OSAllocatedUnfairLock(initialState: 0)
        var 횟수: Int { 횟수_잠금.withLock { $0 } }
        func 불렸다() { 횟수_잠금.withLock { $0 += 1 } }
        func 보낸다(_ members: [FamilyMember]) { onChange.value?(members) }
    }

    @MainActor final class 초대_기록 {
        var 역할들: [MemberRole] = []
        var onJoined: (@MainActor (FamilyMember) -> Void)?
        var 모든_onJoined: [@MainActor (FamilyMember) -> Void] = []
    }

    private func 저장소(_ childUid: String? = nil) -> RoleStore {
        let store = RoleStore(defaults: TestDefaults.isolated("ChildSelectorModelTests"))
        store.childUid = childUid
        return store
    }

    private func 멤버(_ uid: String, _ role: String, _ name: String = "", joined: Int64 = 1) -> FamilyMember {
        FamilyMember(uid: uid, role: role, displayName: name, joinedAt: joined)
    }

    private func 만든다(
        _ store: RoleStore, _ 구독: 가짜_구독, 초대: 초대_기록 = 초대_기록(), 읽기_전용: Bool = false
    ) -> ChildSelectorModel {
        ChildSelectorModel(
            familyId: "fam",
            roleStore: store,
            읽기_전용: 읽기_전용,
            membersObserve: { _, onChange, onError in
                구독.onChange.set(onChange)
                구독.onError.set(onError)
                구독.불렸다()
                return 구독.registration
            },
            inviteFactory: { familyId, role, onJoined in
                초대.역할들.append(role)
                초대.onJoined = onJoined
                초대.모든_onJoined.append(onJoined)
                // 이 테스트는 세션을 시작하지 않는다 — 소유와 닫기만 본다.
                return InviteSession(
                    familyId: familyId, role: role,
                    create: { _, _, _ in throw CancellationError() },
                    fetch: { _ in [] },
                    observe: { _, _, _ in TestListenerRegistration() },
                    onJoined: onJoined
                )
            }
        )
    }

    @Test("저장된 아이가 아직 가족에 있으면 그대로, 보호자와 아이를 나눠 든다(:195-206)")
    func 저장된_아이를_유지한다() async {
        let store = 저장소("c2"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("c1", "child", "민준", joined: 1), 멤버("c2", "child", "서연", joined: 2), 멤버("g1", "guardian", "엄마")])
        await eventually { m.children.count == 2 }
        #expect(store.childUid == "c2")
        #expect(m.guardians.map(\.uid) == ["g1"])
        #expect(m.줄_문구 == "서연 보는 중 ▾")
        #expect(m.지도_이름 == "서연")
    }

    @Test("저장된 아이가 사라졌거나 처음이면 가장 먼저 들어온 아이로 옮긴다(ChildSelector.kt, :199-205)")
    func 사라지면_대체_아이() async {
        let store = 저장소("gone"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("c2", "child", "서연", joined: 2), 멤버("c1", "child", "민준", joined: 1)])
        await eventually { store.childUid == "c1" }
        #expect(m.줄_문구 == "민준 보는 중 ▾")
    }

    @Test("아이가 없으면 선택을 비우고 child_selector_empty, 지도 카드는 child_default_name(:221-222, :227-231)")
    func 아이가_없으면() async {
        let store = 저장소("c1"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("g1", "guardian")])
        await eventually { m.guardians.count == 1 }
        #expect(store.childUid == nil)
        #expect(m.줄_문구 == String(localized: "child_selector_empty"))
        #expect(m.지도_이름 == String(localized: "child_default_name"))
    }

    @Test("이름이 겹치면 uid 끝 네 자리를 붙이고, 빈 이름은 '아이'로 센다(:233-237)")
    func 같은_이름() async {
        let store = 저장소(), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("child-aaaa1111", "child", ""), 멤버("child-bbbb2222", "child", "아이"), 멤버("c3", "child", "민준")])
        await eventually { m.children.count == 3 }
        #expect(m.children.map(m.라벨) == ["아이 · 1111", "아이 · 2222", "민준"])
    }

    @Test("고르면 이 폰의 선택만 바뀐다 — 서버에는 쓰지 않는다(:271-278, 판정 기록 6)")
    func 고른다() async {
        let store = 저장소("c1"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("c1", "child", "민준", joined: 1), 멤버("c2", "child", "서연", joined: 2)])
        await eventually { m.children.count == 2 }
        m.고른다("c2")
        #expect(store.childUid == "c2")
        #expect(m.selectedUid == "c2")
    }

    @Test("멤버 구독 실패는 child_selector_load_failed, 다음 스냅샷이 오면 풀린다(:191, :218-225)")
    func 불러오기_실패() async {
        let store = 저장소(), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.onError.value?(NSError(domain: "test", code: 1))
        await eventually { m.불러오기_실패 }
        #expect(m.줄_문구 == String(localized: "child_selector_load_failed"))
        구독.보낸다([멤버("c1", "child", "민준")])
        await eventually { !m.불러오기_실패 }
        #expect(m.줄_문구 == "민준 보는 중 ▾")
    }

    @Test("'＋ 보호자 초대' 줄에 지금 보호자 수를 적는다(:251-256)")
    func 보호자_수() async {
        let store = 저장소(), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("g1", "guardian"), 멤버("g2", "guardian"), 멤버("c1", "child")])
        await eventually { m.guardians.count == 2 }
        // 수 조각 안 공백은 일부러 U+00A0 이다(6단계 S1) — "현재 / 2명" 으로 접히지 않게. 되돌리면 i18n 값과 같다.
        #expect(m.보호자_초대_문구 == "＋ 보호자 초대 · 현재\u{00A0}2명")
        #expect(m.보호자_초대_문구.replacingOccurrences(of: "\u{00A0}", with: " ") == "＋ 보호자 초대 · 현재 2명")
    }

    @Test("수 조각만 붙인다 — 앞 문구와 ' · ' 구분자의 공백은 그대로, 구분자가 없으면 손대지 않는다(6단계 S1)")
    func 수_조각만_붙인다() {
        #expect(ChildSelectorModel.수_조각을_붙인다("＋ Invite a parent · 1 now") == "＋ Invite a parent · 1\u{00A0}now")
        #expect(ChildSelectorModel.수_조각을_붙인다("＋ 보호자 초대 현재 1명") == "＋ 보호자 초대 현재 1명")
    }

    @Test("초대는 한 판만 열리고, 아이가 들어오면 그 아이를 고르고 닫는다(:280-286, GuardianPairingActivity.kt:217-230)")
    func 아이_초대() async {
        let store = 저장소("c1"), 구독 = 가짜_구독(), 초대 = 초대_기록()
        let m = 만든다(store, 구독, 초대: 초대)
        m.시작한다()
        m.초대한다(.child)
        m.초대한다(.guardian)
        #expect(초대.역할들 == [.child])
        #expect(m.초대?.role == .child)
        초대.onJoined?(멤버("c9", "child", "지우", joined: 9))
        #expect(store.childUid == "c9")
        #expect(m.초대 == nil)
    }

    @Test("읽기 전용 확인에서는 초대한다 를 불러도 초대 세션을 만들지 않는다 — 메뉴의 .disabled 에만 기대지 않는다(통합 검토 I3)")
    func 읽기_전용이면_초대하지_않는다() async {
        let store = 저장소("c1"), 구독 = 가짜_구독(), 초대 = 초대_기록()
        let m = 만든다(store, 구독, 초대: 초대, 읽기_전용: true)
        m.시작한다()
        m.초대한다(.child)
        m.초대한다(.guardian)
        // 팩토리가 한 번도 불리지 않았다 = InviteSession 이 없다 = 발급(inviteCodes 쓰기)으로 갈 길이 없다.
        #expect(초대.역할들.isEmpty)
        #expect(m.초대 == nil)
        #expect(store.childUid == "c1")
    }

    @Test("보호자가 초대로 들어오면 아이 선택은 그대로 두고 닫기만 한다(GuardianPairingActivity.kt:226 은 아이일 때만 고른다)")
    func 보호자_초대() async {
        let store = 저장소("c1"), 구독 = 가짜_구독(), 초대 = 초대_기록()
        let m = 만든다(store, 구독, 초대: 초대)
        m.시작한다()
        m.초대한다(.guardian)
        초대.onJoined?(멤버("g9", "guardian"))
        #expect(store.childUid == "c1")
        #expect(m.초대 == nil)
    }

    @Test("닫은 초대가 늦게 합류를 알려도 지금 열린 초대와 아이 선택은 그대로다(세대)")
    func 옛_초대의_늦은_합류() async {
        let store = 저장소("c1"), 구독 = 가짜_구독(), 초대 = 초대_기록()
        let m = 만든다(store, 구독, 초대: 초대)
        m.시작한다()
        m.초대한다(.child)
        m.초대를_닫는다()
        m.초대한다(.guardian)
        let 옛_알림 = 초대.모든_onJoined[0]
        옛_알림(멤버("c9", "child", "지우"))
        #expect(store.childUid == "c1")
        #expect(m.초대?.role == .guardian)
    }

    @Test("두 번 시작해도 구독은 하나, 정리하면 리스너를 떼고 초대를 닫고 늦은 스냅샷을 무시한다(:423-428)")
    func 정리() async {
        let store = 저장소("c1"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        m.시작한다()
        #expect(구독.횟수 == 1)
        m.초대한다(.child)
        m.정리한다()
        #expect(구독.registration.removed)
        #expect(m.초대 == nil)
        구독.보낸다([멤버("c2", "child", "서연")])
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(m.children.isEmpty)
        #expect(store.childUid == "c1")
        m.초대한다(.child)
        #expect(m.초대 == nil)
    }

    @Test("정리 뒤에 늦게 온 구독 오류는 실패 줄을 띄우지 않는다")
    func 정리_뒤_늦은_오류() async {
        let store = 저장소("c1"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        m.정리한다()
        구독.onError.value?(NSError(domain: "test", code: 2))
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(!m.불러오기_실패)
    }
}
