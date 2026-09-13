import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 초대 한 판을 진짜 저장소 함수로 에뮬레이터에서 끝까지 돌린다. **초대 발급은 진짜 가족에 쓰므로 이 테스트가
/// 확인의 전부다** — 실기기 확인(Task 5)은 초대를 만들지 않는다.
@Suite(.serialized)
@MainActor
struct InviteFlowTests {

    init() async { await EmulatorHarness.start() }

    @MainActor final class 합류_기록 { var 멤버들: [FamilyMember] = [] }

    @Test("아이 초대: 번호를 받고, 그 번호로 새 아이가 들어오면 그 아이로 한 번 넘어간다")
    func 아이가_들어온다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let 합류 = 합류_기록()
        let session = InviteSession(familyId: familyId, role: .child, onJoined: { 합류.멤버들.append($0) })
        defer { session.정리한다() }

        session.시작한다()
        await eventually(timeoutSeconds: 10) { session.코드 != nil }
        let code = try #require(session.코드)

        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: code)
        await eventually(timeoutSeconds: 10) { !합류.멤버들.isEmpty }
        #expect(합류.멤버들.map(\.uid) == [child.uid])
    }

    @Test("'새 번호 받기'는 새 코드를 만들고 이전 코드 문서를 지운다(FamilyRepository.createInvite previousCode)")
    func 새_번호는_옛_코드를_지운다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let session = InviteSession(familyId: familyId, role: .guardian, onJoined: { _ in })
        defer { session.정리한다() }

        session.시작한다()
        await eventually(timeoutSeconds: 10) { session.코드 != nil && session.버튼_활성 }
        let first = try #require(session.코드)
        session.버튼을_눌렀다()
        await eventually(timeoutSeconds: 10) { session.코드 != first && session.버튼_활성 }
        let old = try await Firestore.firestore().collection("inviteCodes").document(first).getDocument(source: .server)
        #expect(!old.exists)
    }
}
