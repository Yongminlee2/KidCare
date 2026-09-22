import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 아이 폰이 하는 쓰기가 규칙을 **실제로** 통과하는지 본다(설계서 §11.1·§12.3).
/// 규칙을 못 지킨 쓰기는 조용히 거부되므로 단위 테스트로는 절대 안 잡힌다.
///
/// 아이 세션의 **원시 쓰기**로 규칙을 태운다 — 기본 `FirebaseApp` 은 보호자이고 익명 계정은 uid 를
/// 고를 수 없어 아이로 만들 수 없다(판정 기록 13). 이 dict 가 `EventDoc.firestoreData` 와 같은지는
/// `EventDocumentsTests.아이가_싣는_본문` 이 본다.
@Suite(.serialized)
struct ChildEventWriteTests {

    init() async { await EmulatorHarness.start() }

    private func 가족과_자녀() async throws -> (familyId: String, child: EmulatorHarness.ChildSession) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)
        return (familyId, child)
    }

    private func 지금() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// `EventDoc.firestoreData` 와 **같은 모양**이어야 한다 — 그 대조는 단위 테스트가 한다.
    private func 본문(_ childUid: String, at: Int64, read: Bool = false) -> [String: Any] {
        ["id": "", "type": EventType.placeEnter, "at": at,
         "childUid": childUid, "placeName": "학교", "detail": "", "read": read]
    }

    private func 쓴다(_ child: EmulatorHarness.ChildSession, _ familyId: String, _ data: [String: Any]) async throws {
        try await child.db.collection("families").document(familyId)
            .collection("events").document().setData(data)
    }

    @Test("아이가 자기 이름으로 read:false, at 이 창 안이면 통과한다 (firestore.rules:306-310)")
    func 통과() async throws {
        let (familyId, child) = try await 가족과_자녀()
        try await 쓴다(child, familyId, 본문(child.uid, at: 지금()))
    }

    @Test("at 이 8일 전이면 거부된다 — 창은 7일이다(판정 기록 12)")
    func 너무_옛날() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 쓴다(child, familyId, 본문(child.uid, at: 지금() - 8 * 24 * 60 * 60 * 1000))
        }
    }

    @Test("at 이 2시간 뒤면 거부된다 — 미래 창은 1시간이다")
    func 너무_미래() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 쓴다(child, familyId, 본문(child.uid, at: 지금() + 2 * 60 * 60 * 1000))
        }
    }

    @Test("read: true 로 만들면 거부된다 — 아이가 자기 사건을 미리 읽음 처리할 수 없다 (:308)")
    func 읽음으로_만들기() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 쓴다(child, familyId, 본문(child.uid, at: 지금(), read: true))
        }
    }

    @Test("남의 childUid 로 만들면 거부된다 (:307)")
    func 남의_이름() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 쓴다(child, familyId, 본문("남의uid", at: 지금()))
        }
    }

    @Test("아이가 자기 사건을 읽음 처리하면 거부된다 — 부모의 안 읽은 목록에서 지울 수 없다 (:315-318)")
    func 아이는_읽음을_못_쓴다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let ref = child.db.collection("families").document(familyId).collection("events").document()
        try await ref.setData(본문(child.uid, at: 지금()))
        await #expect(throws: (any Error).self) { try await ref.updateData(["read": true]) }
    }

    @Test("아이는 자기 places/ 를 읽을 수 있다 (:217-218) — 상시 구독의 근거다")
    func 장소_읽기() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let snapshot = try await child.db.collection("families").document(familyId)
            .collection("children").document(child.uid).collection("places").getDocuments()
        #expect(snapshot.documents.isEmpty)
    }

    @Test("아이는 places/ 를 쓸 수 없다 — 장소는 부모가 정한다 (:219-221)")
    func 장소_쓰기_거부() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await child.db.collection("families").document(familyId)
                .collection("children").document(child.uid).collection("places").document("p1")
                .setData(["id": "", "name": "내가 만든 곳", "lat": 37.5, "lng": 127.0,
                          "radiusMeters": 100, "notifyEnter": true, "notifyExit": true])
        }
    }
}
