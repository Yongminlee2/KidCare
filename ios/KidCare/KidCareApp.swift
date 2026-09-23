import NMapsMap
import SwiftUI
import os

@main
struct KidCareApp: App {

    init() {
        FirebaseBootstrap.configureForApp()

        // 지도 키는 Secrets.xcconfig → Info.plist 를 거쳐 들어온다. 비어 있으면 지도가
        // 조용히 회색 사각형이 되는데, 그 화면은 "인터넷이 안 되나?"로 읽혀서 원인을
        // 찾는 데 오래 걸린다. 그래서 여기서 크게 실패시킨다 — 안드로이드가 릴리스
        // 패키징 직전에 키를 검사하는 것과 같은 판단이다.
        //
        // assert 는 릴리스 빌드에서 통째로 빠진다(컴파일 조건부). 그러면 배포판에서는
        // 키가 비어도 조용히 회색 지도만 남고 아무 데도 원인이 안 남는다. 그래서
        // assert(디버그 중 즉시 중단)에 더해 os.Logger 로 항상(릴리스 포함) 콘솔에
        // 에러를 남긴다 — 디버그는 그 자리에서 멈춰서 알고, 릴리스는 콘솔 로그를
        // 뒤져서라도 알 수 있게 한다.
        let key = Bundle.main.object(forInfoDictionaryKey: "NMFNcpKeyId") as? String ?? ""
        if key.isEmpty {
            Logger(subsystem: "com.kidcare.family", category: "NaverMap").error(
                "네이버 지도 NCP Key ID 가 없습니다. ios/Config/Secrets.xcconfig 에 NAVER_MAP_NCP_KEY_ID = 발급받은_Key_ID 를 넣으세요. (Secrets.xcconfig.example 을 복사해 쓰면 됩니다)"
            )
        }
        assert(!key.isEmpty, """
            네이버 지도 NCP Key ID 가 없습니다. ios/Config/Secrets.xcconfig 에
            NAVER_MAP_NCP_KEY_ID = 발급받은_Key_ID 를 넣으세요.
            (Secrets.xcconfig.example 을 복사해 쓰면 됩니다)
            """)
        // 브리프가 준 `NMFNcpKeyClient`/`.client` 는 이 SDK 버전(3.23.3)의 실제 API 가
        // 아니다 — 헤더(NMFAuthManager.h)에는 `client` 프로퍼티도 `NMFNcpKeyClient`
        // 타입도 없다. 실제로는 `ncpKeyId` 를 직접 지정한다(Info.plist 의 NMFNcpKeyId
        // 로도 자동으로 읽히지만, 키가 비어 있을 때를 위에서 크게 실패시키는 지점과
        // 같은 자리에 두려고 명시적으로도 지정한다).
        NMFAuthManager.shared().ncpKeyId = key

        // 저장된 역할이 child 면 **화면과 무관하게** 수집을 시작한다. 지역 전환이나 중요 위치
        // 변경으로 앱이 백그라운드에서 되살아나면 `WindowGroup` 의 body 가 안 돌 수 있다 —
        // 그때도 이 줄은 돈다(2단계 통합 검토 I1, 1단계 M6). 테스트 프로세스에서는
        // `ChildSession` 이 스스로 문을 닫는다(`RouterView` 의 `isRunningTests` 와 같은 기준).
        ChildSession.shared.startIfChild()
    }

    var body: some Scene {
        WindowGroup { RouterView() }
    }
}
