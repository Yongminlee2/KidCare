import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
@testable import KidCare

/// 테스트가 에뮬레이터를 상대하게 만들고, 테스트마다 새 익명 계정으로 갈아탄다.
///
/// 계정을 갈아타는 것이 왜 필요한가: 보안 규칙 검증은 "이 uid 가 이 문서를 만들 수
/// 있는가"를 묻는다. 테스트 전부가 한 uid 를 공유하면 앞 테스트에서 이미 멤버가 된
/// 계정으로 "아직 멤버가 아닌 사람"을 흉내 낼 수 없다.
enum EmulatorHarness {

    static let projectId = "kidcare-emulator"

    /// `FirebaseBootstrap` 이 `@MainActor` 라서(전역 `configured` 플래그를 안전하게
    /// 지키려고) 이 함수도 `@MainActor` 로 맞춘다 — 부르는 쪽(`AuthGatewayTests.init()`)
    /// 이 `await` 로 건너오게 만든다.
    @MainActor
    static func start() {
        FirebaseBootstrap.configureForEmulator(projectId: projectId)
    }

    /// 지금 계정을 버리고 새 익명 계정으로 로그인해 그 uid 를 준다.
    @discardableResult
    static func freshUser() async throws -> String {
        try? Auth.auth().signOut()
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    /// 자녀 폰을 흉내 내는 두 번째 세션(`CommandRepositoryTests` 에서 옮겨 왔다 —
    /// `ScheduleRepositoryTests` 도 "보호자 세션 + 가족에 들어온 자녀"가 필요한데,
    /// `freshUser()` 로 자녀로 갈아타면 익명 보호자 계정으로 돌아갈 방법이 없다).
    ///
    /// 명령·설정은 보호자가 쓰고 자녀는 제 경로만 쓴다 — 방향이 반대인 두 역할을 한
    /// 프로세스에서 동시에 검증하려면 로그인 세션이 둘 있어야 한다. 기본 앱은 보호자로
    /// 두고, 자녀는 이름 붙은 두 번째 `FirebaseApp`(자기 `Auth`·`Firestore` 를 따로 갖는다)
    /// 으로 흉내 낸다. `FirebaseBootstrap` 이 "에뮬레이터 전환이 일어나는 유일한 자리"라고
    /// 못 박은 것은 **기본 앱**의 전환이고, 이 두 번째 앱은 운영으로 갈 일이 없는 테스트
    /// 전용 인스턴스라 그 규율과 충돌하지 않는다. 테스트마다 이름을 다르게 줘 서로 다른
    /// `FirebaseApp` 을 쓰게 한다 — 안 그러면 이미 로그인된 세션을 재사용해 "새 자녀"를
    /// 흉내 낼 수 없다.
    struct ChildSession {
        let uid: String
        let db: Firestore
    }

    enum HarnessError: Error { case appMissing }

    static func freshChildSession() async throws -> ChildSession {
        // FIRApp 이름은 영문·숫자·하이픈·밑줄만 허용한다 — `#function`(한글 테스트
        // 이름 + 괄호)을 그대로 붙이면 그 자리에서 예외로 죽는다.
        let appName = "ChildSession-\(UUID().uuidString)"
        let options = FirebaseOptions(
            googleAppID: "1:000000000000:ios:0000000000000001",
            gcmSenderID: "000000000000"
        )
        options.projectID = projectId
        options.apiKey = "emulator-does-not-check-this"
        FirebaseApp.configure(name: appName, options: options)
        guard let app = FirebaseApp.app(name: appName) else { throw HarnessError.appMissing }

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

    /// 자녀 세션으로 `families/{familyId}/members/{childUid}` 를 만든다 —
    /// `FamilyRepository.joinFamily` 와 정확히 같은 필드를 쓰되, 그 함수는 기본
    /// `Firestore.firestore()`(보호자 세션)만 상대해서 자녀 세션에는 못 쓴다. 규칙(초대
    /// 코드로 자녀 자리를 가져가는 갈래)은 그대로 태운다.
    static func joinAsChild(_ child: ChildSession, familyId: String, joinCode: String) async throws {
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
}
