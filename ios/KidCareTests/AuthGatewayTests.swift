import Testing
import FirebaseAuth
@testable import KidCare

@Suite(.serialized)
struct AuthGatewayTests {

    // start() 가 @MainActor 라서 init() 도 async 로 만들어 await 로 건너간다 —
    // Swift Testing 은 스위트 init 이 async 여도 그대로 기다려 준다.
    init() async { await EmulatorHarness.start() }

    @Test("익명 로그인이 uid 를 준다")
    func 로그인이_uid를_준다() async throws {
        _ = try await EmulatorHarness.freshUser()
        let uid = try await AuthGateway.signIn()
        #expect(!uid.isEmpty)
        #expect(AuthGateway.currentUid() == uid)
    }

    @Test("동시에 불러도 계정이 하나만 생긴다")
    func 동시_호출은_같은_uid를_준다() async throws {
        try? FirebaseAuth.Auth.auth().signOut()
        async let a = AuthGateway.signIn()
        async let b = AuthGateway.signIn()
        async let c = AuthGateway.signIn()
        let uids = try await [a, b, c]
        #expect(Set(uids).count == 1)
    }
}
