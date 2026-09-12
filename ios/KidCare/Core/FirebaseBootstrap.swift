import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Firebase 구성과 에뮬레이터 전환이 일어나는 **유일한** 자리.
///
/// 두 갈래를 한 파일에 가둔 이유: 에뮬레이터 전환을 부르는 쪽마다 흩어 놓으면
/// 언젠가 한 군데가 빠지고, 그러면 테스트가 **운영 Firestore 에 쓰기 시작한다.**
/// 그 사고는 조용히 성공하기 때문에 아무도 못 알아챈다.
/// `@MainActor` 인 이유: `configured` 플래그가 nonisolated 전역 가변 상태로 있으면
/// Swift 6 strict concurrency 가 "동시에 두 스레드가 건드릴 수 있다"며 컴파일을
/// 막는다. Firebase 구성은 원래 메인 스레드에서 한 번만 부르는 호출(앱 시작,
/// 테스트 스위트 시작)이라 MainActor 로 묶는 것이 `nonisolated(unsafe)` 로 검사를
/// 끄는 것보다 실제 호출 패턴에 맞는 진짜 격리다.
@MainActor
enum FirebaseBootstrap {

    private static var configured = false

    /// 실제 앱용. `GoogleService-Info.plist` 를 읽는다.
    static func configureForApp() {
        guard !configured else { return }

        // KidCareTests 는 KidCare.app 안에 호스팅되어 돈다(XcodeGen 이
        // KidCareTests → KidCare 의존을 보고 TEST_HOST 를 자동으로 채운다) — 즉
        // 테스트를 돌리기만 해도 이 앱의 init() 이 그대로 실행된다. 여기서
        // FirebaseApp.configure() 를 부르면 plist 가 없어 즉시 크래시하고, 그러면
        // EmulatorHarness 가 configureForEmulator 를 부를 기회조차 없다. 테스트
        // 프로세스 안에서는 아무것도 하지 않고 에뮬레이터 구성이 대신 하게 둔다.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        FirebaseApp.configure()
        configured = true
    }

    /// 테스트용. **plist 가 없어도 돈다** — 그래서 Firebase 콘솔 설정이 끝나기 전에도
    /// Task 4~6 의 테스트를 다 쓸 수 있다. 에뮬레이터는 apiKey 를 검사하지 않는다.
    static func configureForEmulator(projectId: String) {
        guard !configured else { return }
        let options = FirebaseOptions(
            googleAppID: "1:000000000000:ios:0000000000000000",
            gcmSenderID: "000000000000"
        )
        options.projectID = projectId
        options.apiKey = "emulator-does-not-check-this"
        FirebaseApp.configure(options: options)

        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
        Firestore.firestore().useEmulator(withHost: "127.0.0.1", port: 8080)

        // 캐시를 메모리로 둔다. 디스크 캐시가 남으면 다음 테스트가 앞 테스트의
        // 문서를 "서버에 있는 것"으로 착각한다. useEmulator 뒤에 설정을 바꿔야
        // 한다 — 순서가 바뀌면 Firestore 가 "이미 시작됐다"며 막는다.
        //
        // **isSSLEnabled 를 직접 꺼야 한다.** useEmulator(withHost:port:) 는 host 만
        // 바꾸고 SSL 기본값(켜짐)은 그대로 둔다(Firebase iOS SDK 12.19.0 소스로 확인:
        // FIRFirestore.mm 의 useEmulatorWithHost:port: 는 host 필드만 손댄다).
        // 에뮬레이터는 평문 gRPC 라서, 이 줄이 없으면 클라이언트가 TLS 핸드셰이크를
        // 시도하다 실패하고 백오프하며 영원히 재시도한다 — 크래시도, 에러 로그도
        // 눈에 띄게 뜨지 않아서(같은 메시지가 로그에 조용히 반복될 뿐) 테스트가
        // "멈춘 것"과 구분이 안 된다.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = MemoryCacheSettings()
        settings.isSSLEnabled = false
        Firestore.firestore().settings = settings

        configured = true
    }
}
