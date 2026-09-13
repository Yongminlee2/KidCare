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

    // MARK: - TrailDoc·TrailPoint·SegmentDoc
    //
    // 정본은 안드로이드 `core/model/Documents.kt:148-189`. 필드 이름이 한 글자라도
    // 어긋나면 안드로이드(자녀 폰)가 쓴 문서를 못 읽는다. 이 세 타입은 **읽기 전용**
    // 이다(보호자는 쓰지 않는다) — 그래서 firestoreData 를 만들지 않는다.

    @Test("TrailPoint 는 speed 를 0 으로 뭉개지 않고 그대로 읽는다")
    func 경로점_speed가_실린다() throws {
        // Phase 2 에서 Fix.speed 가 영원히 0 이던 버그를 고쳤다 — 그 고침이 실제로
        // 쓰이려면 여기서부터 speed 필드가 실려 와야 한다.
        let point = try #require(TrailPoint([
            "lat": 37.5665, "lng": 126.9780, "accuracy": 12.5, "speed": 1.8,
            "at": Int64(1_757_000_000_000),
        ]))
        #expect(point.lat == 37.5665)
        #expect(point.lng == 126.9780)
        #expect(point.accuracy == 12.5)
        #expect(point.speed == 1.8)
        #expect(point.at == 1_757_000_000_000)
    }

    @Test("TrailPoint.asFix 는 speed 를 포함해 그대로 옮긴다")
    func 경로점_asFix가_speed를_옮긴다() throws {
        let point = try #require(TrailPoint([
            "lat": 37.1, "lng": 127.2, "accuracy": 8.0, "speed": 3.4,
            "at": Int64(1_757_000_001_000),
        ]))
        let fix = point.asFix
        #expect(fix.lat == 37.1)
        #expect(fix.lng == 127.2)
        #expect(fix.accuracy == 8.0)
        #expect(fix.speed == 3.4)
        #expect(fix.at == 1_757_000_001_000)
    }

    @Test("옛 TrailPoint 문서에 speed 가 없으면 0 이다")
    func 옛_경로점은_speed가_0이다() throws {
        let point = try #require(TrailPoint([
            "lat": 37.0, "lng": 127.0, "accuracy": 10.0, "at": Int64(1_757_000_000_000),
        ]))
        #expect(point.speed == 0)
    }

    @Test("SegmentDoc 은 안드로이드 필드 이름을 그대로 읽는다")
    func 구간문서_읽기() throws {
        let doc = try #require(SegmentDoc([
            "type": "MOVE",
            "startAt": Int64(1_757_000_000_000),
            "endAt": Int64(1_757_000_060_000),
            "lat": 37.55, "lng": 126.99,
            "distanceMeters": 120.5,
            "pointCount": 6,
            "placeName": "",
        ]))
        #expect(doc.type == "MOVE")
        #expect(doc.startAt == 1_757_000_000_000)
        #expect(doc.endAt == 1_757_000_060_000)
        #expect(doc.distanceMeters == 120.5)
        #expect(doc.pointCount == 6)
        #expect(doc.placeName == "")
    }

    @Test("TrailDoc 은 하루치 점·구간 배열을 함께 읽는다")
    func 하루기록_읽기() {
        let doc = TrailDoc([
            "dayKey": "2026-09-13",
            "points": [
                ["lat": 37.0, "lng": 127.0, "accuracy": 10.0, "speed": 1.0, "at": Int64(1_000)],
                ["lat": 37.01, "lng": 127.01, "accuracy": 10.0, "speed": 1.5, "at": Int64(2_000)],
            ],
            "segments": [
                ["type": "MOVE", "startAt": Int64(1_000), "endAt": Int64(2_000),
                 "lat": 37.01, "lng": 127.01, "distanceMeters": 15.0, "pointCount": 2, "placeName": ""],
            ],
            "updatedAt": Int64(2_000),
        ])
        #expect(doc.dayKey == "2026-09-13")
        #expect(doc.points.count == 2)
        #expect(doc.points[1].speed == 1.5)
        #expect(doc.segments.count == 1)
        #expect(doc.segments[0].type == "MOVE")
        #expect(doc.updatedAt == 2_000)
    }

    @Test("빈 문서는 빈 배열로 읽힌다")
    func 빈_하루기록() {
        let doc = TrailDoc([:])
        #expect(doc.dayKey == "")
        #expect(doc.points.isEmpty)
        #expect(doc.segments.isEmpty)
        #expect(doc.updatedAt == 0)
    }
}
