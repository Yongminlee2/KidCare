import FirebaseFirestore
import Testing
@testable import KidCare

/// 보안 규칙 상대의 통합 테스트. 에뮬레이터가 떠 있어야 돈다.
///
/// `.serialized` 인 이유: 익명 계정을 갈아타며 "누가 요청했는가"를 바꾸는 테스트라
/// 병렬로 돌면 서로의 로그인 상태를 덮어쓴다. 다만 `.serialized` 가 지켜주는 것은
/// **이 suite 안의** 테스트 순서뿐이다 — `AuthGatewayTests` 와 이 suite 가 같은
/// 전역 `Auth.auth()` 세션을 나눠 쓰는데도 실제로 서로 겹쳐 돌지 않는 이유는
/// `ios/project.yml` 이 만든 스킴의 `parallelizable = "NO"`(생성된
/// `KidCare.xcscheme` 확인) 때문이다 — 그게 스위트 전체를 순차 실행으로 묶는다.
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
        #expect(member.displayName == "아빠")
    }

    @Test("이름 없이 합류하면 \"보호자\" 가 아니라 빈 이름을 저장한다 — 안드로이드 joinFamily 와 같다(규칙도 빈 문자열을 받는다)")
    func 빈_이름으로_합류() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .guardian, previousCode: nil)

        let iphone = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(
            code: invite.code, uid: iphone, expectedRole: .guardian, displayName: "   "
        )
        let snap = try await Firestore.firestore()
            .collection("families").document(familyId)
            .collection("members").document(iphone).getDocument()
        let member = try #require(MemberDoc(snap.data() ?? [:]))
        #expect(member.displayName == "")
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

    /// 규칙 카나리아. 위의 여섯 테스트는 전부 `FamilyRepository` 를 거치는데,
    /// 그러면 이 suite 가 "내 코드의 정상 경로가 맞는가"만 증명하고 "규칙이 실제로
    /// 막는가"는 하나도 증명하지 못한다 — `firestore.rules` 를 통째로
    /// `allow read, write: if true` 로 바꿔도 저 여섯은 똑같이 초록일 수 있다
    /// (역할이 다른 코드·없는 코드 거부는 클라이언트 쪽 검사만으로도 통과하는
    /// 테스트라 규칙까지 갈 필요가 없었다). 그래서 `FamilyRepository` 를 거치지
    /// 않고 Firestore 를 **직접** 두드려, 가족 멤버가 아닌 사용자가
    /// `role: guardian` 에 가짜 `joinCode` 를 실어 자기 멤버 문서를 만들려는 시도가
    /// `firestore.rules:107` 의 `members/{uid}` create 규칙에서 진짜로 거부되는지
    /// 확인한다. 규칙이 사라지거나 배포가 안 되면 이 테스트만 빨갛게 남는다.
    @Test("카나리아: 멤버가 아닌 사용자가 가짜 joinCode 로 직접 쓰면 규칙이 막는다")
    func 규칙_카나리아() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)

        let intruder = try await EmulatorHarness.freshUser()
        let forged = MemberDoc(
            role: .guardian, displayName: "침입자", updatedAt: 0, joinCode: "FAKE99", joinedAt: 0
        )

        do {
            try await Firestore.firestore()
                .collection("families").document(familyId)
                .collection("members").document(intruder)
                .setData(forged.firestoreData)
            Issue.record("규칙이 막아야 하는 쓰기가 통과했다 — 규칙이 사라졌거나 게시되지 않았다")
        } catch {
            let ns = error as NSError
            #expect(ns.domain == FirestoreErrorDomain)
            #expect(ns.code == FirestoreErrorCode.permissionDenied.rawValue)
        }
    }
}
