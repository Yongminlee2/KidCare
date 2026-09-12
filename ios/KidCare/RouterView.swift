import SwiftUI

/// 앱을 열었을 때 어디로 갈지 정한다. 안드로이드 `RouterActivity` 와 같은 자리다.
///
/// 판단 재료는 저장소에 있는 것뿐이다 — 네트워크를 기다리지 않는다. 여기서 서버를
/// 물어보면 통신이 느린 날 첫 화면이 통째로 비어 있게 된다.
struct RouterView: View {

    @State private var store = RoleStore.shared

    var body: some View {
        if let familyId = store.familyId, store.role == .guardian {
            ChildMapView(familyId: familyId, childUid: store.childUid)
        } else {
            RoleSelectView()
        }
    }
}
