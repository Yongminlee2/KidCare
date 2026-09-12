import SwiftUI

/// 앱을 열었을 때 어디로 갈지 정한다. 안드로이드 `RouterActivity` 와 같은 자리다.
///
/// 판단 재료는 저장소에 있는 것뿐이다 — 네트워크를 기다리지 않는다. 여기서 서버를
/// 물어보면 통신이 느린 날 첫 화면이 통째로 비어 있게 된다.
///
/// **`showMain` 은 딱 한 번, `init` 에서만 정한다.** 처음엔 `store.familyId` 를 body
/// 안에서 그대로 읽어 분기했는데, `@Observable` 이 그 읽기를 추적하는 바람에
/// `InviteCodeView` 가 `RoleStore.shared.familyId` 를 쓰는 순간(코드를 아직 받기도
/// 전에) `RouterView` 가 다시 그려져 `RoleSelectView`·`InviteCodeView` 를 통째로
/// 걷어내고 `ChildMapView` 로 바꿔치기했다 — 보호자가 코드를 읽기도 전에 지도로
/// 튕겨나가 아무도 그 코드를 못 봤다(1차 리뷰 CRITICAL). 안드로이드
/// `RouterActivity.destination()` 이 앱을 켤 때 딱 한 번만 도는 것과 같은 이유로,
/// 여기서도 판단은 시작할 때 한 번뿐이어야 한다 — 그 이후로는 온보딩 화면이
/// `onGuardianReady()` 를 불러야만(합류 성공, 또는 코드 화면에서 아이가 들어오거나
/// "완료" 를 누름) 넘어간다.
struct RouterView: View {

    @State private var store = RoleStore.shared
    @State private var showMain: Bool

    init() {
        let store = RoleStore.shared
        _showMain = State(initialValue: store.role == .guardian && store.familyId != nil)
    }

    var body: some View {
        if showMain, let familyId = store.familyId {
            ChildMapView(familyId: familyId, childUid: store.childUid)
        } else {
            RoleSelectView(onGuardianReady: { showMain = true })
        }
    }
}
