import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 규칙·장소·설정 쓰기를 에뮬레이터에서 확인한다. 보안 규칙(firestore.rules:208-230)도 함께 태운다.
/// 자녀 세션은 4단계 Task 3 이 `EmulatorHarness` 로 옮긴 도우미를 쓴다.
@Suite(.serialized)
struct RuleRepositoryTests {

    init() async { await EmulatorHarness.start() }

    private func 가족과_자녀() async throws -> (familyId: String, child: EmulatorHarness.ChildSession) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)
        return (familyId, child)
    }

    private func 자녀_문서(_ db: Firestore, _ familyId: String, _ childUid: String) -> DocumentReference {
        db.collection("families").document(familyId).collection("children").document(childUid)
    }

    /// 구독 콜백이 넘겨준 것 중 테스트가 보는 값만 담는다(ID 목록과 캐시본 여부).
    private actor 스냅샷_기록 {
        private(set) var 마지막: (ids: [String], fromCache: Bool)?
        func 기록(_ ids: [String], _ fromCache: Bool) { 마지막 = (ids, fromCache) }
    }

    @Test("규칙 저장은 일곱 필드로 쓰이고, 구독은 서버가 확인한 스냅샷을 fromCache=false 로 준다")
    func 규칙_저장과_구독() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let 기록 = 스냅샷_기록()
        let listener = ScheduleRepository.observeSchedules(
            familyId: familyId, childUid: child.uid,
            onChange: { docs, fromCache in
                let ids = docs.map(\.id)
                Task { await 기록.기록(ids, fromCache) }
            },
            onError: { _ in }
        )
        defer { listener.remove() }

        let id = try await ScheduleRepository.saveSchedule(
            familyId: familyId, childUid: child.uid,
            doc: ScheduleDoc(id: "", days: [1, 2, 3, 4, 5], startMinute: 1260, endMinute: 420,
                             mode: RingerMode.vibrate, enabled: true, priority: 1)
        )
        #expect(!id.isEmpty)
        let data = try #require(try await 자녀_문서(Firestore.firestore(), familyId, child.uid)
            .collection("schedules").document(id).getDocument(source: .server).data())
        #expect(Set(data.keys) == ["id", "days", "startMinute", "endMinute", "mode", "enabled", "priority"])
        try await 기다린다 {
            let 마지막 = await 기록.마지막
            return 마지막?.ids == [id] && 마지막?.fromCache == false
        }
    }

    @Test("같은 ID 로 두 번 저장하면 규칙은 하나다 — 편집을 열 때 ID 를 정해 두는 이유(ScheduleFragment.kt:151-160)")
    func 두_번_저장() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let doc = ScheduleDoc(id: "fixed", days: [6, 7], startMinute: 540, endMinute: 600, mode: RingerMode.silent, enabled: true, priority: 1)
        try await ScheduleRepository.saveSchedule(familyId: familyId, childUid: child.uid, doc: doc)
        try await ScheduleRepository.saveSchedule(familyId: familyId, childUid: child.uid, doc: doc)
        let snapshot = try await 자녀_문서(Firestore.firestore(), familyId, child.uid)
            .collection("schedules").getDocuments(source: .server)
        #expect(snapshot.documents.map(\.documentID) == ["fixed"])

        try await ScheduleRepository.deleteSchedule(familyId: familyId, childUid: child.uid, id: "fixed")
        let 지운_뒤 = try await 자녀_문서(Firestore.firestore(), familyId, child.uid)
            .collection("schedules").getDocuments(source: .server)
        #expect(지운_뒤.documents.isEmpty)
    }

    @Test("기본 모드·공휴일은 한 필드씩 병합한다 — 관리 탭의 lockEnabled 를 지우지 않는다(ScheduleRepository.kt:88-107)")
    func 설정_병합() async throws {
        let (familyId, child) = try await 가족과_자녀()
        try await ScheduleRepository.setRingerLock(familyId: familyId, childUid: child.uid, enabled: true)
        try await ScheduleRepository.setDefaultMode(familyId: familyId, childUid: child.uid, mode: RingerMode.silent)
        try await ScheduleRepository.setHolidayOff(familyId: familyId, childUid: child.uid, enabled: true)

        let data = try #require(try await 자녀_문서(Firestore.firestore(), familyId, child.uid)
            .collection("settings").document("ringer").getDocument(source: .server).data())
        #expect(data["lockEnabled"] as? Bool == true)
        #expect(data["defaultMode"] as? String == RingerMode.silent)
        #expect(data["holidayOff"] as? Bool == true)
        #expect(Set(data.keys) == ["lockEnabled", "defaultMode", "holidayOff"])
    }

    @Test("장소 저장은 일곱 필드, 삭제하면 사라진다")
    func 장소_저장과_삭제() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let id = try await PlaceRepository.savePlace(
            familyId: familyId, childUid: child.uid,
            doc: PlaceDoc(id: "", name: "학교", lat: 37.5665, lng: 126.978, radiusMeters: 200, notifyEnter: true, notifyExit: false)
        )
        let ref = 자녀_문서(Firestore.firestore(), familyId, child.uid).collection("places").document(id)
        let data = try #require(try await ref.getDocument(source: .server).data())
        #expect(Set(data.keys) == ["id", "name", "lat", "lng", "radiusMeters", "notifyEnter", "notifyExit"])
        #expect(data["name"] as? String == "학교")

        try await PlaceRepository.deletePlace(familyId: familyId, childUid: child.uid, id: id)
        #expect(try await ref.getDocument(source: .server).exists == false)
    }

    @Test("아이는 자기 규칙·장소를 읽을 수 있지만 쓸 수는 없다(firestore.rules:216-230)")
    func 아이는_읽기만() async throws {
        let (familyId, child) = try await 가족과_자녀()
        _ = try await PlaceRepository.savePlace(
            familyId: familyId, childUid: child.uid,
            doc: PlaceDoc(id: "p", name: "학교", lat: 37.5, lng: 127, radiusMeters: 200)
        )
        let 자녀_경로 = 자녀_문서(child.db, familyId, child.uid)
        let 읽음 = try await 자녀_경로.collection("places").getDocuments(source: .server)
        #expect(읽음.documents.count == 1)

        await #expect(throws: (any Error).self) {
            try await 자녀_경로.collection("places").document("p").setData(["radiusMeters": 0], merge: true)
        }
        await #expect(throws: (any Error).self) {
            try await 자녀_경로.collection("schedules").document("s").setData(ScheduleDoc(id: "s").firestoreData)
        }
    }

    private func 기다린다(timeoutSeconds: Double = 5, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("조건이 \(timeoutSeconds)초 안에 참이 되지 않았다")
    }
}
