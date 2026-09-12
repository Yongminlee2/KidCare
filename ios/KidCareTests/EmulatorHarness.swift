import FirebaseAuth
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
}
