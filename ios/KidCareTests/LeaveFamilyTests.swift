import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 보안 규칙 상대의 통합 테스트. 에뮬레이터가 떠 있어야 돈다. 규칙을 고치지 않고 빼기가 되는지를 본다(판정 기록 8).
@Suite(.serialized)
struct LeaveFamilyTests {

    init() async { await EmulatorHarness.start() }

    @Test("보호자가 빠지면 멤버 문서가 사라지고, 그 계정은 더는 가족을 못 읽는다 — 아이는 그대로 남는다")
    func 빠진다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)

        try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: owner)

        let members = try await child.db.collection("families").document(familyId)
            .collection("members").getDocuments(source: .server)
        #expect(members.documents.map(\.documentID) == [child.uid])
        await #expect(throws: (any Error).self) {
            _ = try await Firestore.firestore().collection("families").document(familyId).getDocument(source: .server)
        }
    }

    @Test("보호자가 둘이면 한 명이 빠져도 남은 보호자는 가족을 읽고 초대 번호를 만들 수 있다")
    func 남은_보호자() async throws {
        // 남는 보호자(가족을 만든 사람)는 이름 붙은 앱, 빠지는 보호자는 기본 앱이다.
        let owner = try await 따로_보호자_세션()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let guardianCode = InviteCode.generate()
        try await owner.db.collection("inviteCodes").document(guardianCode).setData(
            InviteCodeDoc(familyId: owner.familyId, expiresAt: now + 600_000, role: .guardian, createdByUid: owner.uid).firestoreData
        )
        let second = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(code: guardianCode, uid: second, expectedRole: .guardian, displayName: "보호자2")

        try await LeaveFamilyRepository.removeMember(familyId: owner.familyId, uid: second)

        // 빠진 쪽은 더는 못 읽는다.
        await #expect(throws: (any Error).self) {
            _ = try await Firestore.firestore().collection("families").document(owner.familyId).getDocument(source: .server)
        }
        // 남은 쪽은 그대로다 — 가족을 읽고, 멤버는 자기 하나이며, 새 아이 초대 번호도 만든다.
        let family = owner.db.collection("families").document(owner.familyId)
        _ = try await family.getDocument(source: .server)
        let members = try await family.collection("members").getDocuments(source: .server)
        #expect(members.documents.map(\.documentID) == [owner.uid])
        try await owner.db.collection("inviteCodes").document(InviteCode.generate()).setData(
            InviteCodeDoc(familyId: owner.familyId, expiresAt: now + 600_000, role: .child, createdByUid: owner.uid).firestoreData
        )
    }

    @Test("이미 빠진 뒤에 다시 불러도 성공한다 — 시간 초과 뒤 다시 누른 경우")
    func 다시_불러도_성공() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: owner)
        try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: owner)
    }

    @Test("아직 가족에 있는데 규칙이 거부하면 성공으로 삼키지 않는다 — 아이 역할 계정")
    func 멤버인데_거부되면_던진다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let childUid = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(code: invite.code, uid: childUid, expectedRole: .child, displayName: "아이")

        // 아이는 members delete 가 거부되지만(roleIn == guardian 아님) families get 은 된다 → 진짜 오류다.
        await #expect(throws: (any Error).self) {
            try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: childUid)
        }
        // 그리고 아이의 멤버 문서는 그대로다.
        let doc = try await Firestore.firestore().collection("families").document(familyId)
            .collection("members").document(childUid).getDocument(source: .server)
        #expect(doc.exists)
    }

    /// 15초 약속의 서버 쪽 절반. 확인되지 않은 삭제가 **나중에 몰래 서버에 닿으면** "아무것도 지우지 않았다"는 안내가
    /// 거짓이 된다. 보통 `delete()` 는 서버에 닿지 못하면 디스크 캐시의 쓰기 대기열에 남았다가, 앱을 다시 켜고 연결되는
    /// 순간 올라간다. 그래서 대기열에 남지 않는 트랜잭션으로 지운다.
    ///
    /// **`disableNetwork()` 로는 이것을 볼 수 없다(리뷰 M5 를 고치며 확인).** 연결을 끊어도 트랜잭션 커밋은 서버에 곧장
    /// 닿아(에뮬레이터에서 2ms 안에 확인, 문서 삭제) 전제가 늘 깨졌고, 옛 테스트는 조건문 덕에 공허하게 통과했다. 그래서
    /// 앱을 다시 켜는 것을 그대로 흉내 낸다 — 디스크 캐시를 쓰는 같은 앱을 아무도 듣지 않는 포트로 열어 빼기를 부르고
    /// (확인 없음), 그 인스턴스를 끝낸 뒤 진짜 에뮬레이터 포트로 다시 열어 대기열에 남은 쓰기가 올라갈 틈을 준다.
    @Test("서버에 닿지 못해 확인되지 않은 빼기는, 앱을 다시 켜고 연결된 뒤에도 서버에 닿지 않는다")
    func 확인_안_된_삭제는_나중에도_안_닿는다() async throws {
        let appName = "LeaveDisk-\(UUID().uuidString)"
        let app = try 디스크_앱(appName)
        let uid = try await Auth.auth(app: app).signInAnonymously().user.uid
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // 1) 살아 있는 포트로 가족과 멤버 문서를 만든다.
        let live = 디스크_Firestore(app, port: 8080)
        let family = live.collection("families").document()
        let familyId = family.documentID
        try await family.setData(["ownerUid": uid, "name": "", "inviteCode": "", "inviteExpiresAt": 0, "schemaVersion": 2, "createdAt": now])
        try await family.collection("members").document(uid).setData([
            "role": "guardian", "displayName": "", "fcmToken": "", "appVersion": "", "updatedAt": now, "joinedAt": now,
        ])
        try await live.terminate()

        // 2) 같은 앱(같은 디스크 캐시)을 죽은 포트로 다시 열고 빼기를 부른다. 확인이 오면 안 된다.
        _ = 디스크_Firestore(app, port: 1)
        let confirmed: Bool
        do {
            confirmed = try await firstToFinish(
                timeoutMillis: 3_000,
                sleep: { try? await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }
            ) {
                try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: uid, db: try LeaveFamilyTests.앱의_Firestore_(appName))
                return true
            } ?? false
        } catch {
            confirmed = false
        }
        try await LeaveFamilyTests.앱의_Firestore_(appName).terminate()
        // 전제: 서버에 닿지 못했으니 확인이 없어야 한다. 전제가 깨지면 아래 검사는 아무것도 증명하지 못하므로 조용히
        // 통과하지 않고 실패로 드러낸다(리뷰 M5).
        guard !confirmed else {
            Issue.record("전제가 깨졌다: 죽은 포트인데 빼기가 확인됐다 — 이 테스트는 늦은 삭제를 검사하지 못한다")
            return
        }

        // 3) 앱을 다시 켠 것처럼 진짜 포트로 연다. 디스크 대기열에 쓰기가 남았다면 이제 올라간다.
        let again = 디스크_Firestore(app, port: 8080)
        try await again.waitForPendingWrites()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let still = try await again.collection("families").document(familyId)
            .collection("members").document(uid).getDocument(source: .server)
        #expect(still.exists, "확인되지 않았다고 알렸는데 멤버 문서가 나중에 사라졌다")
        try await again.terminate()
        try? await again.clearPersistence()
    }

    @Test("서버에 전혀 닿지 않으면 확인되지 않는다(성공으로 오지 않는다)")
    func 닿지_않으면_확인_없음() async throws {
        let dead = try await 따로_보호자_세션(deadFirestore: true)
        let appName = dead.appName
        let familyId = dead.familyId, uid = dead.uid
        let confirmed: Bool
        do {
            confirmed = try await firstToFinish(
                timeoutMillis: 5_000,
                sleep: { try? await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }
            ) {
                try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: uid, db: try LeaveFamilyTests.앱의_Firestore_(appName))
                return true
            } ?? false
        } catch {
            confirmed = false
        }
        #expect(confirmed == false)
    }

    @Test("익명 계정을 지우면 로그인이 풀린다")
    func 계정_삭제() async throws {
        _ = try await EmulatorHarness.freshUser()
        let outcome = await LeaveFamilyRepository.deleteAuthUser()
        #expect(outcome == .deleted)
        #expect(Auth.auth().currentUser == nil)
    }

    @Test("계정 삭제 대신 로그아웃으로 물러나면 정말 로그아웃됐는지 보고 signedOutOnly 를 돌려준다(리뷰 M2)")
    func 로그아웃() async throws {
        _ = try await EmulatorHarness.freshUser()
        let outcome = await LeaveFamilyRepository.signOut()
        #expect(outcome == .signedOutOnly)
        #expect(Auth.auth().currentUser == nil)
    }

    // MARK: - 도우미

    struct 보호자_세션 {
        let uid: String
        let familyId: String
        /// 빼기를 부를 앱 이름. `Firestore` 는 Sendable 이 아니라 경주 클로저에 이름만 넘기고 안에서 꺼낸다.
        let appName: String
        let db: Firestore
    }

    private enum 세션오류: Error { case 앱_없음 }

    /// 에뮬레이터 Auth 를 쓰는 이름 붙은 앱. 디스크 캐시 경로는 앱 이름으로 갈리므로 다른 스위트와 섞이지 않는다.
    private func 디스크_앱(_ name: String) throws -> FirebaseApp {
        let options = FirebaseOptions(googleAppID: "1:000000000000:ios:0000000000000002", gcmSenderID: "000000000000")
        options.projectID = EmulatorHarness.projectId
        options.apiKey = "emulator-does-not-check-this"
        FirebaseApp.configure(name: name, options: options)
        let app = try #require(FirebaseApp.app(name: name))
        Auth.auth(app: app).useEmulator(withHost: "127.0.0.1", port: 9099)
        return app
    }

    /// 앱의 Firestore 를 **디스크 캐시**로 연다(앱과 같은 설정). `terminate()` 뒤에 부르면 새 인스턴스가 같은 캐시를 연다.
    private func 디스크_Firestore(_ app: FirebaseApp, port: Int) -> Firestore {
        let db = Firestore.firestore(app: app)
        db.useEmulator(withHost: "127.0.0.1", port: port)
        let settings = db.settings
        settings.cacheSettings = PersistentCacheSettings()
        settings.isSSLEnabled = false
        db.settings = settings
        return db
    }

    private static func 앱의_Firestore_(_ name: String) throws -> Firestore {
        guard let app = FirebaseApp.app(name: name) else { throw 세션오류.앱_없음 }
        return Firestore.firestore(app: app)
    }

    /// 기본 앱과 따로 노는 이름 붙은 앱으로 가족을 만든 보호자. 이 스위트의 설정(죽은 포트 등)이 다른 스위트의 기본 앱에 번지지
    /// 않게 한다. `deadFirestore` 면 가족은 진짜 에뮬레이터에 만들되, 빼기를 부를 Firestore 는 아무도 듣지 않는 포트를 본다.
    private func 따로_보호자_세션(deadFirestore: Bool = false) async throws -> 보호자_세션 {
        let appName = "LeaveGuardian-\(UUID().uuidString)"
        let options = FirebaseOptions(googleAppID: "1:000000000000:ios:0000000000000002", gcmSenderID: "000000000000")
        options.projectID = EmulatorHarness.projectId
        options.apiKey = "emulator-does-not-check-this"
        FirebaseApp.configure(name: appName, options: options)
        let app = try #require(FirebaseApp.app(name: appName))
        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app)
        db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings
        settings.cacheSettings = MemoryCacheSettings()
        settings.isSSLEnabled = false
        db.settings = settings

        let uid = try await auth.signInAnonymously().user.uid
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let family = db.collection("families").document()
        try await family.setData(["ownerUid": uid, "name": "", "inviteCode": "", "inviteExpiresAt": 0, "schemaVersion": 2, "createdAt": now])
        try await family.collection("members").document(uid).setData([
            "role": "guardian", "displayName": "", "fcmToken": "", "appVersion": "", "updatedAt": now, "joinedAt": now,
        ])
        guard deadFirestore else { return 보호자_세션(uid: uid, familyId: family.documentID, appName: appName, db: db) }

        // 같은 사용자로 로그인한 두 번째 앱을 만들 수는 없으므로(익명), 죽은 포트 쪽은 새 앱에서 같은 문서 경로만 부른다.
        // 규칙 판정까지 가지 못하는 것이 요점이라 누구로 로그인했는지는 상관없다.
        let deadName = "LeaveDead-\(UUID().uuidString)"
        FirebaseApp.configure(name: deadName, options: options)
        let deadApp = try #require(FirebaseApp.app(name: deadName))
        let deadAuth = Auth.auth(app: deadApp)
        deadAuth.useEmulator(withHost: "127.0.0.1", port: 9099)
        _ = try await deadAuth.signInAnonymously()
        let deadDb = Firestore.firestore(app: deadApp)
        deadDb.useEmulator(withHost: "127.0.0.1", port: 1)
        let deadSettings = deadDb.settings
        deadSettings.cacheSettings = MemoryCacheSettings()
        deadSettings.isSSLEnabled = false
        deadDb.settings = deadSettings
        return 보호자_세션(uid: uid, familyId: family.documentID, appName: deadName, db: deadDb)
    }
}
