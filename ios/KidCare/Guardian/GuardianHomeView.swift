import SwiftUI

/// 보호자 본 화면의 바깥 틀 — 선택기 줄, 선택 탭, 초대 번호 화면의 주인. 정본은 `GuardianMainActivity` 의
/// "액티비티 몫"(선택기·멤버 리스너·초대 열기)이고, 탭과 배너는 안쪽 `GuardianRootView` 몫이다.
///
/// 이렇게 두 겹인 이유(판정 기록 7): 아이를 바꾸면 탭 뷰모델은 새 아이로 **다시 만들어야** 하지만, 선택기와
/// 멤버 리스너와 보던 탭은 **살아남아야** 한다. `.id(childUid)` 를 안쪽에만 건다.
struct GuardianHomeView: View {

    let familyId: String
    @State private var store = RoleStore.shared
    @State private var selector: ChildSelectorModel
    /// 4단계 `GuardianRootView` 에 있던 것을 위로 올렸다. 키 문자열은 그대로라 저장된 선택 탭을 그대로 읽는다.
    @SceneStorage("guardian.selectedTab") private var selectedTab: GuardianTab = .map

    init(familyId: String) {
        self.familyId = familyId
        _selector = State(initialValue: ChildSelectorModel(familyId: familyId, roleStore: RoleStore.shared))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 지도 탭에서는 줄을 숨긴다(showTab :330). 지도는 상태 카드의 아이 이름이 같은 메뉴를 연다.
            if selectedTab != .map {
                ChildSelectorBar(model: selector)
            }
            GuardianRootView(familyId: familyId, childUid: store.childUid, selectedTab: $selectedTab)
                // 아이가 바뀌면 탭 뷰모델 다섯을 새 아이로 다시 만든다(recreateTabsForSelectedChild :288-300).
                // 옛 뷰의 onDisappear 가 `GuardianRootView.탭을_모두_정리한다` 로 옛 뷰모델들의 리스너를 뗀다.
                .id(store.childUid ?? "")
        }
        .environment(selector)
        .onAppear { selector.시작한다() }
        .onDisappear { selector.정리한다() }
        // 안드로이드는 새 액티비티로 띄운다(openInvite :280-286). 탭마다 NavigationStack 이 있어 바깥에서 push 할
        // 수 없으므로 전체 화면 커버로 띄우고 뒤로 버튼을 단다(판정 기록 8).
        .fullScreenCover(isPresented: Binding(
            get: { selector.초대 != nil },
            set: { if !$0 { selector.초대를_닫는다() } }
        )) {
            if let session = selector.초대 {
                GuardianInviteView(session: session, onClose: { selector.초대를_닫는다() })
            }
        }
    }
}
