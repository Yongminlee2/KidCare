import Testing
@testable import KidCare

struct DocumentsTests {

    @Test("MemberDoc 은 안드로이드가 쓴 필드 이름을 그대로 읽는다")
    func 멤버문서_읽기() throws {
        let doc = try #require(MemberDoc([
            "role": "guardian",
            "displayName": "엄마",
            "fcmToken": "",
            "appVersion": "0.8",
            "updatedAt": Int64(1_757_000_000_000),
            "joinCode": "ABC234",
            "joinedAt": Int64(1_757_000_000_000),
        ]))
        #expect(doc.role == .guardian)
        #expect(doc.displayName == "엄마")
        #expect(doc.joinCode == "ABC234")
    }

    @Test("MemberDoc 쓰기는 선언한 필드만 내보낸다")
    func 멤버문서_쓰기는_필드를_안_늘린다() {
        let doc = MemberDoc(role: .child, displayName: "아이", updatedAt: 1, joinCode: "ABC234", joinedAt: 1)
        let keys = Set(doc.firestoreData.keys)
        // 규칙이 hasOnly() 로 검사하는 자리가 있어 필드가 하나만 더 나가도 쓰기가
        // 통째로 거부된다. 그래서 "무엇이 나가는가"를 테스트로 못 박는다.
        #expect(keys == ["role", "displayName", "fcmToken", "appVersion", "updatedAt", "joinCode", "joinedAt"])
    }

    @Test("ChildStatusDoc 의 wifiOn 은 없으면 nil 이다")
    func 옛문서의_wifiOn은_nil() throws {
        let doc = try #require(ChildStatusDoc([
            "lat": 37.5, "lng": 127.0, "accuracy": 12.0,
            "at": Int64(1_757_000_000_000), "battery": 80, "charging": false,
            "ringerMode": "normal", "lastSeenAt": Int64(1_757_000_000_000),
        ]))
        // false(꺼짐)와 nil(모름)은 다른 말이다 — 안드로이드 주석이 그렇게 못 박았다.
        #expect(doc.wifiOn == nil)
        #expect(doc.lat == 37.5)
    }

    @Test("InviteCodeDoc 의 role 기본값은 child 다")
    func 옛_초대코드는_child로_읽힌다() throws {
        let doc = try #require(InviteCodeDoc([
            "familyId": "F1", "expiresAt": Int64(1_757_000_600_000),
        ]))
        #expect(doc.role == .child)
        #expect(doc.createdByUid == "")
    }

    // MemberDoc 만 이 스타일로 못 박혀 있었다 — FamilyDoc 과 InviteCodeDoc 도
    // 똑같이 Firestore 에 쓰이는데 필드 집합이 하나도 테스트로 안 잠겨 있었다.
    // hasOnly() 를 쓰는 update 규칙들과 직접 맞물리는 건 아니지만(finding 11 —
    // 이 두 문서의 create 경로 자체가 그 검사를 맞지 않는다), "무엇이 나가는가"를
    // 손으로 확인할 수 있어야 한다는 Documents.swift 의 이유는 세 구조체 모두에
    // 똑같이 적용된다.
    @Test("FamilyDoc 쓰기는 선언한 필드만 내보낸다")
    func 가족문서_쓰기는_필드를_안_늘린다() {
        let doc = FamilyDoc(name: "우리 가족", createdAt: 1, ownerUid: "U1", schemaVersion: 2)
        let keys = Set(doc.firestoreData.keys)
        #expect(keys == ["name", "createdAt", "inviteCode", "inviteExpiresAt", "ownerUid", "schemaVersion", "primaryChildUid"])
    }

    @Test("InviteCodeDoc 쓰기는 선언한 필드만 내보낸다")
    func 초대코드문서_쓰기는_필드를_안_늘린다() {
        let doc = InviteCodeDoc(familyId: "F1", expiresAt: 1, role: .child, createdByUid: "U1")
        let keys = Set(doc.firestoreData.keys)
        #expect(keys == ["familyId", "expiresAt", "role", "createdByUid"])
    }
}
