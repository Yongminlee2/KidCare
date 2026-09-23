import SwiftUI

/// 역할이 child 일 때의 뿌리. **탭이 없다** — 아이는 보호자 화면을 하나도 못 본다(설계서 §2-2).
///
/// **이 뷰는 파이프라인을 만들지 않는다.** 수집기·시계·장소 감시·업로더·조건 감시는
/// `KidCareApp.init()` 이 부른 `ChildSession` 이 이미 만들었다 — 지역 전환이나 중요 위치
/// 변경으로 앱이 **백그라운드에** 되살아나면 이 body 가 아예 안 돌 수 있기 때문이다
/// (3단계 판정 기록 1). 여기서 만들면 그 실행에서는 아무 일도 안 일어난다.
///
/// 하는 일은 셋을 잇는 것뿐이다 — 화면이 앞으로 나올 때 **다시 읽어 달라**(`onRefresh`),
/// 권한을 물어 달라(`onAsk`), 역할을 지우고 멈춰 달라(`onRepair`). 그 셋은 전부
/// `ChildSession` 이 가진 것을 부른다: 권한을 읽는 `CLLocationManager` 는 앱이 사는 동안
/// 하나여야 하고(설계서 §5.2) 그 하나는 `LocationCollector` 가 들고 있다.
struct ChildRootView: View {

    @State private var session = ChildSession.shared

    var body: some View {
        // 화면이 앞으로 나올 때(`onAppear`·`scenePhase == .active`) `onRefresh` 를 부르는 것은
        // `ChildHomeView` 가 이미 한다 — 여기서 한 번 더 걸면 가족 멤버 확인(읽기 하나)이
        // 화면이 뜰 때마다 두 번 나간다.
        ChildHomeView(
            model: session.home,
            onRefresh: { session.refreshHome(checkMembership: true) },
            onAsk: { session.requestAuthorization() },
            onRepair: {
                // 서버가 "이 기기는 이 가족의 멤버가 아니다"라고 확답했을 때만 뜨는 버튼이다
                // (판정 기록 13). 역할을 지우면 `RouterView` 가 역할 선택으로 되돌린다.
                RoleStore.shared.clear()
                session.stop()
            },
            // 세션이 못 떴을 때만 뜬다(`ChildHomeModel.cannotStart`). 앱을 껐다 켜라고 시키지
            // 않는 이유는, 그 사이에도 이 폰은 아무것도 기록하지 않기 때문이다(통합 검토 I3).
            onRetry: { session.retryStart() }
        )
    }
}
