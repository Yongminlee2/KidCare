import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// `CommandRepository.send`/`observeOne` 을 실제 에뮬레이터로 확인한다 — 보안
/// 규칙까지 실제로 태운다. 정본은 안드로이드 `FirestoreCommandTransport.kt`.
///
/// **왜 두 번째 `FirebaseApp` 이 필요한가.** 명령 문서는 보호자가 만들고
/// (`commands` create 규칙이 `roleIn(familyId) == 'guardian'` 을 요구한다) 자녀만
/// 상태를 옮긴다(update 규칙이 `request.auth.uid == childUid` 를 요구한다) — 방향이
/// 반대인 두 역할을 같은 프로세스 안에서 동시에 검증하려면 로그인 세션이 두 개
/// 있어야 한다. 기본 `Auth.auth()`/`Firestore.firestore()` 는 한 번에 한 사용자만
/// 붙들 수 있어서, 자녀 역할은 이름 붙은 두 번째 `FirebaseApp`(자기 `Auth`·
/// `Firestore` 를 따로 갖는다)으로 흉내 낸다. `FirebaseBootstrap` 이 "에뮬레이터
/// 전환이 일어나는 유일한 자리"라고 못 박은 것은 **기본 앱**의 운영/에뮬레이터
/// 전환이고, 이 두 번째 앱은 애초에 운영으로 갈 일이 없는 테스트 전용 인스턴스라
/// 그 규율과 충돌하지 않는다 — 여기서만, 테스트에서만 쓴다.
@Suite(.serialized)
struct CommandRepositoryTests {

    init() async { await EmulatorHarness.start() }

    /// 자녀 폰을 흉내 내는 두 번째 세션. 테스트마다 이름을 다르게 줘 서로 다른
    /// `FirebaseApp` 을 쓰게 한다 — 안 그러면 이미 로그인된 세션을 재사용해
    /// "새 자녀" 를 흉내 낼 수 없다.
    private struct ChildSession {
        let uid: String
        let db: Firestore
    }

    private func freshChildSession() async throws -> ChildSession {
        // FIRApp 이름은 영문·숫자·하이픈·밑줄만 허용한다 — `#function`(한글 테스트
        // 이름 + 괄호)을 그대로 붙이면 그 자리에서 예외로 죽는다. UUID 만으로도
        // 세션마다 다른 이름을 보장하기엔 충분하다.
        let appName = "CommandRepositoryTests-\(UUID().uuidString)"
        let options = FirebaseOptions(
            googleAppID: "1:000000000000:ios:0000000000000001",
            gcmSenderID: "000000000000"
        )
        options.projectID = EmulatorHarness.projectId
        options.apiKey = "emulator-does-not-check-this"
        FirebaseApp.configure(name: appName, options: options)
        let app = try #require(FirebaseApp.app(name: appName))

        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)

        let firestore = Firestore.firestore(app: app)
        firestore.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = firestore.settings
        settings.cacheSettings = MemoryCacheSettings()
        settings.isSSLEnabled = false
        firestore.settings = settings

        let result = try await auth.signInAnonymously()
        return ChildSession(uid: result.user.uid, db: firestore)
    }

    /// 자녀 세션으로 `families/{familyId}/members/{childUid}` 를 직접 만든다 —
    /// `FamilyRepository.joinFamily` 와 정확히 같은 필드를 쓰되, 그 함수는 기본
    /// `Firestore.firestore()`(보호자 세션)만 상대해서 여기(자녀 세션)에는 못
    /// 쓴다. 규칙(초대 코드로 자녀 자리를 가져가는 갈래)은 그대로 태운다.
    private func joinAsChild(_ child: ChildSession, familyId: String, joinCode: String) async throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try await child.db.collection("families").document(familyId)
            .collection("members").document(child.uid).setData([
                "role": "child",
                "displayName": "아이",
                "fcmToken": "",
                "appVersion": "",
                "updatedAt": now,
                "joinCode": joinCode,
                "joinedAt": now,
            ])
    }

    @Test("send() 는 pending 으로 시작하고 안드로이드가 읽는 필드 이름 그대로 저장한다")
    func 명령을_보내면_안드로이드와_같은_필드로_pending_문서가_생긴다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)

        let commandId = try await CommandRepository.send(
            familyId: familyId, childUid: "아무-child-uid", type: CommandType.locateNow
        )

        let snap = try await Firestore.firestore().collection("families").document(familyId)
            .collection("children").document("아무-child-uid")
            .collection("commands").document(commandId).getDocument()
        let data = try #require(snap.data())

        // 필드가 하나만 더 나가도 hasOnly() 를 쓰는 다른 자리(예: 업데이트)가
        // 나중에 말없이 거부될 수 있다 — Documents.swift 의 규율과 같은 이유로
        // "무엇이 나가는가"를 여기서도 못 박는다.
        #expect(Set(data.keys) == ["type", "payload", "state", "createdAt", "deliveredAt", "doneAt", "error"])
        #expect(data["type"] as? String == CommandType.locateNow)
        #expect(data["state"] as? String == CommandState.pending)
        #expect(data["payload"] as? [String: String] == [:])
        #expect(data["deliveredAt"] as? Int64 == 0)
        #expect(data["doneAt"] as? Int64 == 0)
        #expect(data["error"] as? String == "")
    }

    @Test("자녀는 명령을 만들 수 없다 — 규칙이 guardian 역할만 허용한다")
    func 자녀는_명령을_못_만든다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)

        // freshUser() 는 기본 세션(Auth.auth())을 자녀로 바꿔치기한다 — 지금부터
        // CommandRepository.send() 도 이 자녀 세션으로 나간다.
        let childUid = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(
            code: invite.code, uid: childUid, expectedRole: .child, displayName: "아이"
        )

        await #expect(throws: (any Error).self) {
            _ = try await CommandRepository.send(familyId: familyId, childUid: childUid, type: CommandType.locateNow)
        }
    }

    @Test("보호자가 보낸 명령을 자녀가 delivered→done 으로 옮기면 observeOne 이 그 변화를 그대로 받는다")
    func 명령_왕복을_리스너가_따라간다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)

        let child = try await freshChildSession()
        try await joinAsChild(child, familyId: familyId, joinCode: invite.code)

        // 여기서부터 기본 세션은 다시 보호자다(freshChildSession 은 두 번째 앱을
        // 쓰므로 기본 Auth.auth() 를 건드리지 않았다) — send() 가 guardian 역할을
        // 요구하는 규칙을 그대로 통과한다.
        let commandId = try await CommandRepository.send(
            familyId: familyId, childUid: child.uid, type: CommandType.locateNow
        )

        let recorder = Recorder()
        let listener = CommandRepository.observeOne(
            familyId: familyId, childUid: child.uid, commandId: commandId,
            onChange: { doc in Task { await recorder.record(doc) } },
            onError: { _ in }
        )
        defer { listener.remove() }

        try await waitUntil { await recorder.states.contains(CommandState.pending) }

        // 자녀 세션으로, 규칙이 강제하는 방향(pending→delivered→done) 그대로 옮긴다.
        let commandRef = child.db.collection("families").document(familyId)
            .collection("children").document(child.uid).collection("commands").document(commandId)
        try await commandRef.updateData([
            "state": CommandState.delivered, "deliveredAt": Int64(Date().timeIntervalSince1970 * 1000),
        ])
        try await waitUntil { await recorder.states.contains(CommandState.delivered) }

        try await commandRef.updateData([
            "state": CommandState.done, "doneAt": Int64(Date().timeIntervalSince1970 * 1000),
        ])
        try await waitUntil { await recorder.last?.state == CommandState.done }

        #expect(await recorder.states.contains(CommandState.delivered))
        #expect(await recorder.last?.state == CommandState.done)
    }

    @Test("자녀가 아니면 명령 상태를 옮길 수 없다 — 규칙이 auth.uid == childUid 를 요구한다")
    func 다른_사람은_명령_상태를_못_옮긴다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)

        let child = try await freshChildSession()
        try await joinAsChild(child, familyId: familyId, joinCode: invite.code)
        let commandId = try await CommandRepository.send(
            familyId: familyId, childUid: child.uid, type: CommandType.locateNow
        )

        // 보호자(기본 세션) 자신은 그 childUid 가 아니므로, 상태를 옮기려 하면
        // 규칙이 거부해야 한다 — "만든 사람이 곧바로 완료로 위조" 를 막는 자리다.
        await #expect(throws: (any Error).self) {
            try await Firestore.firestore().collection("families").document(familyId)
                .collection("children").document(child.uid).collection("commands").document(commandId)
                .updateData(["state": CommandState.delivered, "deliveredAt": Int64(0)])
        }
    }

    private actor Recorder {
        private(set) var docs: [CommandDoc] = []
        var states: [String] { docs.map(\.state) }
        var last: CommandDoc? { docs.last }
        func record(_ doc: CommandDoc) { docs.append(doc) }
    }

    /// 로컬 에뮬레이터 리스너는 보통 수십~수백 ms 안에 반응한다 — 실패로 끝나면
    /// (시간이 다 지나면) `Issue.record` 로 실패를 남긴다. 여기서 기다리는 것은
    /// `MapViewModel` 자신의 15초/60초 제한시간(그건 `MapViewModelCommandGenerationTests`
    /// 가 주입한 가짜 시계로 따로 다룬다)과 무관한, 순수 네트워크 왕복 대기다.
    private func waitUntil(timeoutSeconds: Double = 5, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("조건이 \(timeoutSeconds)초 안에 참이 되지 않았다")
    }
}
