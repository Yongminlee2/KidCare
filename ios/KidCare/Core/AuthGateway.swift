import FirebaseAuth

/// 익명 로그인. 이 앱의 모든 Firestore 접근이 여기서 받은 uid 로 이뤄진다.
///
/// **동시 호출 가드가 핵심이다.** 화면 둘이 같은 순간에 로그인을 시작하면 익명 계정이
/// 둘 생기고, 그러면 한쪽이 만든 가족을 다른 쪽이 못 읽는다 — 증상은 "가족을 찾을 수
/// 없어요" 인데 원인은 로그인이라 찾는 데 오래 걸린다. actor 로 진입을 하나로 묶는다.
actor AuthGateway {

    static let shared = AuthGateway()

    private var inFlight: Task<String, Error>?

    /// 로그인된 uid. 없으면 nil — 부르는 쪽이 `signIn()` 을 기다릴지 정한다.
    nonisolated static func currentUid() -> String? {
        Auth.auth().currentUser?.uid
    }

    static func signIn() async throws -> String {
        try await shared.signInInternal()
    }

    /// 있으면 그대로, 없으면 로그인해서 uid 를 준다.
    ///
    /// **`currentUid() ?? signIn()` 으로 쓰지 않는 이유**: `??` 의 우변은 async 가 될 수
    /// 없어서 컴파일되지 않는다. 부르는 쪽마다 if-let 을 반복하느니 여기 한 번 둔다.
    static func uid() async throws -> String {
        if let uid = currentUid() { return uid }
        return try await signIn()
    }

    private func signInInternal() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        if let inFlight { return try await inFlight.value }

        let task = Task { () -> String in
            let result = try await Auth.auth().signInAnonymously()
            return result.user.uid
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
