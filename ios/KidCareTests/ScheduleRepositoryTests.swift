import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 설정 문서 쓰기를 에뮬레이터로 확인한다 — 보안 규칙(firestore.rules:208-214)까지 태운다.
@Suite(.serialized)
struct ScheduleRepositoryTests {

    init() async { await EmulatorHarness.start() }

    private func 가족과_자녀() async throws -> (familyId: String, child: EmulatorHarness.ChildSession) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)
        return (familyId, child)
    }

    private func 설정_문서(_ db: Firestore, familyId: String, childUid: String) -> DocumentReference {
        db.collection("families").document(familyId).collection("children").document(childUid)
            .collection("settings").document("ringer")
    }

    @Test("잠금 저장은 lockEnabled 하나만 병합한다 — 예약 탭의 holidayOff·defaultMode 를 지우지 않는다")
    func 잠금_저장은_다른_설정을_안_지운다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let ref = 설정_문서(Firestore.firestore(), familyId: familyId, childUid: child.uid)
        try await ref.setData(["holidayOff": true, "defaultMode": "vibrate"])

        try await ScheduleRepository.setRingerLock(familyId: familyId, childUid: child.uid, enabled: true)

        let data = try #require(try await ref.getDocument(source: .server).data())
        #expect(data["lockEnabled"] as? Bool == true)
        #expect(data["holidayOff"] as? Bool == true)
        #expect(data["defaultMode"] as? String == "vibrate")
        #expect(Set(data.keys) == ["lockEnabled", "holidayOff", "defaultMode"])
    }

    @Test("구독은 문서가 없으면 기본값(false)을, 저장하면 새 값을 준다")
    func 구독이_값을_따라온다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let 받은_값 = 값_기록()
        let listener = ScheduleRepository.observeRingerSettings(
            familyId: familyId, childUid: child.uid,
            onChange: { doc in Task { await 받은_값.기록(doc.lockEnabled) } },
            onError: { _ in }
        )
        defer { listener.remove() }
        try await 기다린다 { await 받은_값.값들.contains(false) }
        try await ScheduleRepository.setRingerLock(familyId: familyId, childUid: child.uid, enabled: true)
        try await 기다린다 { await 받은_값.값들.last == true }
    }

    @Test("아이는 잠금을 못 바꾼다 — 규칙이 보호자만 허용한다")
    func 아이는_못_쓴다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 설정_문서(child.db, familyId: familyId, childUid: child.uid)
                .setData(["lockEnabled": false], merge: true)
        }
    }

    private actor 값_기록 {
        private(set) var 값들: [Bool] = []
        func 기록(_ value: Bool) { 값들.append(value) }
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
