import FirebaseFirestore
import Testing
@testable import KidCare

/// 보안 규칙 상대의 통합 테스트. 에뮬레이터가 떠 있어야 돈다.
///
/// `.serialized` 인 이유: 익명 계정을 갈아타며 "누가 요청했는가"를 바꾸는 테스트라
/// 병렬로 돌면 서로의 로그인 상태를 덮어쓴다.
@Suite(.serialized)
struct GuardianJoinTests {

    // `init() async` 여야 한다. 3단계에서 `FirebaseBootstrap` 이 @MainActor 가 되면서
    // `EmulatorHarness.start()` 도 @MainActor 로 올라갔다 — 동기 init 에서는 부를 수 없다.
    init() async { await EmulatorHarness.start() }

    @Test("보호자가 가족을 만들면 자기 멤버 문서가 생긴다")
    func 가족_생성() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)

        let snap = try await Firestore.firestore()
            .collection("families").document(familyId)
            .collection("members").document(owner).getDocument()
        let member = try #require(MemberDoc(snap.data() ?? [:]))
        #expect(member.role == .guardian)
    }

    @Test("★ 두 번째 보호자가 보호자 코드로 같은 가족에 합류한다")
    func 보호자_합류() async throws {
        // 첫 보호자(안드로이드 폰 역할)가 가족을 만들고 보호자용 코드를 발급한다.
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(
            familyId: familyId, role: .guardian, previousCode: nil
        )
        #expect(invite.role == .guardian)

        // 아이폰 역할: 완전히 다른 익명 계정으로 갈아탄 뒤 그 코드로 합류한다.
        let iphone = try await EmulatorHarness.freshUser()
        #expect(iphone != owner)

        let result = try await FamilyRepository.joinFamily(
            code: invite.code, uid: iphone, expectedRole: .guardian, displayName: "아빠"
        )
        #expect(result.familyId == familyId)
        #expect(result.role == .guardian)

        // 규칙이 실제로 통과시켰는지 문서로 확인한다 — 반환값만 보면 거짓말일 수 있다.
        let snap = try await Firestore.firestore()
            .collection("families").document(familyId)
            .collection("members").document(iphone).getDocument()
        let member = try #require(MemberDoc(snap.data() ?? [:]))
        #expect(member.role == .guardian)
        #expect(member.joinCode == invite.code)
    }

    @Test("합류한 보호자는 가족의 멤버 목록을 읽을 수 있다")
    func 합류한_보호자가_멤버를_읽는다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .guardian, previousCode: nil)

        let iphone = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(code: invite.code, uid: iphone, expectedRole: .guardian, displayName: "아빠")

        let members = try await Firestore.firestore()
            .collection("families").document(familyId).collection("members").getDocuments()
        #expect(members.documents.count == 2)
    }

    @Test("자녀용 코드로 보호자가 되려 하면 막힌다")
    func 역할이_다른_코드는_거부된다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let childInvite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)

        let iphone = try await EmulatorHarness.freshUser()
        await #expect(throws: PairingError.wrongRole) {
            _ = try await FamilyRepository.joinFamily(
                code: childInvite.code, uid: iphone, expectedRole: .guardian, displayName: "아빠"
            )
        }
    }

    @Test("없는 코드는 notFound 다")
    func 없는_코드() async throws {
        _ = try await EmulatorHarness.freshUser()
        await #expect(throws: PairingError.notFound) {
            _ = try await FamilyRepository.joinFamily(
                code: "ZZZZZZ", uid: AuthGateway.currentUid()!, expectedRole: .guardian, displayName: "아빠"
            )
        }
    }

    @Test("합류하면 쓴 코드가 지워진다")
    func 쓴_코드는_지워진다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .guardian, previousCode: nil)

        let iphone = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(code: invite.code, uid: iphone, expectedRole: .guardian, displayName: "아빠")

        let snap = try await Firestore.firestore().collection("inviteCodes").document(invite.code).getDocument()
        #expect(!snap.exists)
    }
}
