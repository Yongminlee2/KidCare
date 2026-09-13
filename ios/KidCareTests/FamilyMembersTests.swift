import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 멤버 목록 읽기를 에뮬레이터로 확인한다(firestore.rules:99 `memberOf`). 정본은 `FamilyRepository.kt:245-278`.
@Suite(.serialized)
struct FamilyMembersTests {

    init() async { await EmulatorHarness.start() }

    actor 목록 {
        private(set) var 마지막: [FamilyMember] = []
        func 기록(_ m: [FamilyMember]) { 마지막 = m }
    }

    @Test("한 번 읽기와 구독이 같은 멤버(역할·이름·가입 시각)를 준다")
    func 멤버를_읽는다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)

        let fetched = try await FamilyRepository.fetchMembers(familyId: familyId)
        #expect(Set(fetched.map(\.uid)) == [guardianUid, child.uid])
        let 아이 = try #require(fetched.first { $0.uid == child.uid })
        #expect(아이.role == "child")
        #expect(아이.displayName == "")
        #expect(아이.joinedAt > 0)
        // 이름은 비워서 저장한다 — 안드로이드 FamilyRepository.kt createFamily 와 같다(origin/main 0feb0e3).
        // 화면은 이 폰의 언어로 child_default_name 을 입힌다(ChildSelectorModel.표시_이름).
        #expect(fetched.first { $0.uid == guardianUid }?.displayName == "")
        let family = try await Firestore.firestore().collection("families").document(familyId).getDocument()
        #expect(family.data()?["name"] as? String == "")

        let 기록 = 목록()
        let listener = FamilyRepository.observeMembers(
            familyId: familyId,
            onChange: { members in Task { await 기록.기록(members) } },
            onError: { error in Issue.record("구독 실패: \(error)") }
        )
        defer { listener.remove() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, await 기록.마지막.count < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(Set(await 기록.마지막) == Set(fetched))
    }
}
