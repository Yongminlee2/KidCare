import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 사건 구독과 읽음 쓰기를 에뮬레이터로 확인한다 — 보안 규칙(firestore.rules:267-321)까지 태운다.
@Suite(.serialized)
struct EventRepositoryTests {

    init() async { await EmulatorHarness.start() }

    private func 가족과_자녀() async throws -> (familyId: String, child: EmulatorHarness.ChildSession) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)
        return (familyId, child)
    }

    /// 아이 폰이 남기는 사건. 안드로이드 `EventRepository.add` 는 `doc.copy(id = "")` 를 통째로 쓴다(:53-58) —
    /// @Exclude 가 없어 본문에 "id": "" 가 실린다. 규칙: childUid 본인, read false, at 창 안(:306-310).
    private func 아이가_남긴다(_ child: EmulatorHarness.ChildSession, familyId: String, type: String, at: Int64) async throws -> String {
        let ref = child.db.collection("families").document(familyId).collection("events").document()
        try await ref.setData(["id": "", "type": type, "at": at, "childUid": child.uid, "placeName": "학교", "detail": "", "read": false])
        return ref.documentID
    }

    private func 지금() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    actor 스냅샷_기록 {
        private(set) var 마지막: (docs: [EventDoc], fromCache: Bool)?
        func 기록(_ docs: [EventDoc], _ fromCache: Bool) { 마지막 = (docs, fromCache) }
    }

    private func 기다린다(timeoutSeconds: Double = 5, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("\(timeoutSeconds)초 안에 조건이 참이 되지 않았다")
    }

    @Test("그 아이의 사건을 최신순으로, 서버 확인본(fromCache false)까지 준다(:86-112)")
    func 최신순_구독() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let 옛것 = try await 아이가_남긴다(child, familyId: familyId, type: EventType.placeEnter, at: 지금() - 2_000)
        let 새것 = try await 아이가_남긴다(child, familyId: familyId, type: EventType.placeExit, at: 지금() - 1_000)
        let 기록 = 스냅샷_기록()
        let listener = EventRepository.observeEvents(
            familyId: familyId, childUid: child.uid,
            onChange: { docs, fromCache in Task { await 기록.기록(docs, fromCache) } },
            onError: { error in Issue.record("구독 실패: \(error)") }
        )
        defer { listener.remove() }
        // `&&` 오른쪽에는 await 를 둘 수 없어 한 번 꺼내 본다.
        try await 기다린다 {
            let 마지막 = await 기록.마지막
            return 마지막?.fromCache == false && 마지막?.docs.count == 2
        }
        let docs = try #require(await 기록.마지막?.docs)
        #expect(docs.map(\.id) == [새것, 옛것])
        #expect(docs.allSatisfy { $0.childUid == child.uid && !$0.read })
        #expect(EventRepository.recentLimit == 100)
    }

    @Test("읽음 표시는 read 한 필드만 바꾼다 — 규칙 hasOnly(['read']) 를 통과한다(:131-136)")
    func 읽음은_한_필드() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let id = try await 아이가_남긴다(child, familyId: familyId, type: EventType.lowBattery, at: 지금() - 1_000)
        let ref = Firestore.firestore().collection("families").document(familyId).collection("events").document(id)
        let before = try #require(try await ref.getDocument(source: .server).data())

        try await EventRepository.markRead(familyId: familyId, ids: [id])

        let after = try #require(try await ref.getDocument(source: .server).data())
        #expect(Set(after.keys) == Set(before.keys))
        #expect(after["read"] as? Bool == true)
        #expect(after["type"] as? String == EventType.lowBattery)
        #expect((after["at"] as? NSNumber)?.int64Value == (before["at"] as? NSNumber)?.int64Value)
    }

    @Test("아이는 자기 사건을 읽음으로 못 바꾼다 — 부모의 안 읽은 목록에서 지우는 길을 규칙이 막는다(:311-318)")
    func 아이는_읽음을_못_쓴다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let id = try await 아이가_남긴다(child, familyId: familyId, type: EventType.placeExit, at: 지금() - 1_000)
        await #expect(throws: (any Error).self) {
            try await child.db.collection("families").document(familyId).collection("events").document(id).updateData(["read": true])
        }
    }

    @Test("빈 목록이면 아무것도 쓰지 않는다")
    func 빈_목록() async throws {
        let (familyId, _) = try await 가족과_자녀()
        try await EventRepository.markRead(familyId: familyId, ids: [])
    }
}
