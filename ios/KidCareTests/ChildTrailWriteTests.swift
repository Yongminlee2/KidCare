import FirebaseAuth
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 아이 쪽 쓰기 경로가 규칙을 **실제로** 통과하는지 본다. 규칙을 못 지킨 쓰기는 조용히 거부되므로
/// 단위 테스트로는 절대 안 잡힌다(설계서 §12.3). 에뮬레이터만 상대한다.
///
/// 사건·장소 쓰기는 2단계라 여기 없다.
@Suite(.serialized)
struct ChildTrailWriteTests {

    init() async { await EmulatorHarness.start() }

    private let dayKey = "2026-09-22"
    private let t0: Int64 = 1_790_035_200_000

    private func 하루문서(_ 원본: [Fix]) -> TrailDoc {
        TrailDoc(
            dayKey: dayKey,
            points: 원본.map { TrailPoint($0) },
            segments: TrailUploader.buildSegments(원본),
            updatedAt: t0 + 1
        )
    }

    private var 원본_점: [Fix] {
        [
            Fix(lat: 37.5665, lng: 126.9780, accuracy: 12.5, at: t0, speed: 1.25),
            Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: t0 + 600_000, speed: 0),
        ]
    }

    /// 기본 세션을 **아이**로 만든다 — `ChildStatusReporter`·`TrailRepository` 는 기본
    /// `Firestore.firestore()` 를 쓰므로, 그 코드를 그대로 태우려면 로그인 세션이 아이여야 한다.
    private func 아이가_된다() async throws -> (familyId: String, childUid: String) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let childUid = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(
            code: invite.code, uid: childUid, expectedRole: .child, displayName: "아이"
        )
        return (familyId, childUid)
    }

    @Test("아이 세션이 자기 상태 문서를 platform 까지 포함해 쓴다 — 규칙이 통과시킨다")
    func 상태문서_쓰기() async throws {
        let (familyId, childUid) = try await 아이가_된다()

        try await ChildStatusReporter.report(
            familyId: familyId,
            childUid: childUid,
            write: ChildStatusWrite(
                fix: Fix(lat: 37.5665, lng: 126.9780, accuracy: 12.5, at: t0, speed: 1.25),
                battery: 77, charging: false, network: NetworkKind.wifi, lastSeenAt: t0 + 1
            )
        )

        let snap = try await Firestore.firestore().collection("families").document(familyId)
            .collection("children").document(childUid).getDocument()
        let data = try #require(snap.data())
        #expect(Set(data.keys) == [
            "lat", "lng", "accuracy", "at", "battery", "charging",
            "ringerMode", "dnd", "network", "lastSeenAt", "lastSeenServerAt", "platform",
        ])
        #expect(data["platform"] as? String == "ios")
        #expect(data["battery"] as? Int == 77)
        #expect(data["ringerMode"] as? String == "")
        // 서버가 자기 시각으로 채운 값이라 아이 폰 시계가 아니다.
        #expect(data["lastSeenServerAt"] is Timestamp)
        #expect(data["wifiOn"] == nil, "아이폰은 와이파이 스위치를 못 읽는다 — false 와 모름은 다른 말이다")

        // 보호자 쪽 읽기 모양으로도 그대로 들어온다.
        let doc = try #require(ChildStatusDoc(data))
        #expect(doc.platform == "ios")
        #expect(doc.battery == 77)
        #expect(doc.wifiOn == nil)
    }

    @Test("아이 세션이 자기 하루 문서를 쓴다")
    func 하루문서_쓰기() async throws {
        let (familyId, childUid) = try await 아이가_된다()
        try await TrailRepository.save(familyId: familyId, childUid: childUid, doc: 하루문서(원본_점))

        let snap = try await Firestore.firestore().collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("trails").document(dayKey).getDocument()
        let data = try #require(snap.data())
        #expect(Set(data.keys) == ["dayKey", "points", "segments", "updatedAt"])
        let points = try #require(data["points"] as? [[String: Any]])
        #expect(points.count == 2)
        #expect(Set(points[0].keys) == ["lat", "lng", "accuracy", "speed", "at"])
    }

    @Test("올린 하루 문서를 보호자가 TrailRepository.fetch 로 그대로 읽는다 — 필드가 한 칸도 안 샌다")
    func 보호자가_읽는다() async throws {
        // 이 테스트가 1단계의 핵심 계약이다: 아이가 쓴 것을 지금 있는 보호자 코드가
        // **한 줄도 안 고치고** 읽는다. 그래서 기본 세션은 보호자로 두고, 아이는 두 번째 앱이다.
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)

        let 원본 = 원본_점
        try await child.db.collection("families").document(familyId)
            .collection("children").document(child.uid)
            .collection("trails").document(dayKey)
            .setData(하루문서(원본).firestoreData)

        let doc = try #require(try await TrailRepository.fetch(familyId: familyId, childUid: child.uid, dayKey: dayKey))
        #expect(doc.dayKey == dayKey)
        #expect(doc.points.count == 원본.count)
        #expect(doc.points.first?.speed == 1.25, "speed 가 0 으로 굳지 않는다")
        #expect(doc.points.first?.accuracy == 12.5)
        #expect(doc.segments.first?.type == "STAY")
        #expect(doc.segments.first?.placeName == "", "머무름 이름은 2단계다")
        #expect(doc.updatedAt == t0 + 1)
    }

    @Test("남의 아이 자리에 쓰면 거부된다(firestore.rules:148, :165)")
    func 남의_자리는_거부() async throws {
        let (familyId, childUid) = try await 아이가_된다()
        let 남의_uid = childUid + "-남"

        await #expect(throws: (any Error).self) {
            try await TrailRepository.save(familyId: familyId, childUid: 남의_uid, doc: 하루문서(원본_점))
        }
        await #expect(throws: (any Error).self) {
            try await ChildStatusReporter.report(
                familyId: familyId, childUid: 남의_uid,
                write: ChildStatusWrite(
                    fix: Fix(lat: 37.5, lng: 127, accuracy: 10, at: t0),
                    battery: 50, charging: false, network: NetworkKind.none, lastSeenAt: t0
                )
            )
        }
    }

    @Test("보호자 세션이 아이의 trails 에 쓰면 거부된다")
    func 보호자는_못_쓴다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)

        // 기본 세션은 여전히 보호자다 — 규칙이 `request.auth.uid == childUid` 를 요구한다.
        await #expect(throws: (any Error).self) {
            try await TrailRepository.save(familyId: familyId, childUid: child.uid, doc: 하루문서(원본_점))
        }
    }
}
