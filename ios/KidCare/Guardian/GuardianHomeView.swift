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
    /// "이 아이폰을 가족에서 빼기"(7단계 판정 기록 8). 메뉴(`ChildMenu`)가 환경에서 꺼내 쓴다.
    @State private var leave: LeaveFamilyModel

    /// 빼기 모델에 선택기 정리를 거는 열쇠(리뷰 M3).
    @State private var 정리_열쇠 = UUID()

    init(familyId: String, onLeft: @escaping LeaveFamilyModel.OnLeft = { _ in }) {
        self.familyId = familyId
        _selector = State(initialValue: ChildSelectorModel(familyId: familyId, roleStore: RoleStore.shared))
        _leave = State(initialValue: LeaveFamilyModel(familyId: familyId, onLeft: onLeft))
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
        .environment(leave)
        // 확인 → 빼기. 누르는 순간 대화상자는 닫히고(isPresented 가 false 로) 빼기는 따로 돈다.
        // 마지막 보호자 경고의 보호자 수는 선택기의 멤버 구독에서 온다(아직 못 받았으면 0 → 경고 쪽).
        .confirmationDialog(
            Text("leave_family_title"),
            isPresented: Binding(get: { leave.묻는중 }, set: { if !$0 { leave.취소한다() } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) { Task { await leave.뺀다() } } label: { Text("leave_family_confirm") }
            Button(role: .cancel) { leave.취소한다() } label: { Text("dialog_cancel") }
        } message: {
            Text(verbatim: LeaveFamilyModel.확인_문구(보호자_수: selector.guardians.count))
        }
        // 제목도 모델이 정한다 — "빼지 못했어요"(서버가 거부)와 "확인하지 못했어요"(시간 초과, 리뷰 I1)가 다르다.
        .alert(
            Text(verbatim: leave.실패?.제목 ?? ""),
            isPresented: Binding(get: { leave.실패 != nil }, set: { if !$0 { leave.실패를_닫는다() } })
        ) {
            Button(role: .cancel) { leave.실패를_닫는다() } label: { Text("ios_leave_family_failed_ok") }
        } message: {
            Text(verbatim: leave.실패?.문구 ?? "")
        }
        // 빼는 동안에는 다른 버튼을 누를 수 없게 덮는다 — 반쯤 빠진 가족에 명령이 나가지 않게.
        .overlay {
            if leave.빼는중 {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("leave_family_in_progress")
                            .font(.system(size: 15))
                            .foregroundStyle(KidCarePalette.ink)
                    }
                    .padding(24)
                    .background(KidCarePalette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .onAppear {
            selector.시작한다()
            // 서버에서 빠진 뒤 이 폰의 기록을 지우기 전에 멤버 리스너를 뗀다 — 늦은 스냅샷이 childUid 를 다시 쓰지 못하게.
            let selector = selector
            leave.떠나기_전에(정리_열쇠) { selector.정리한다() }
        }
        .onDisappear {
            leave.정리를_뗀다(정리_열쇠)
            selector.정리한다()
        }
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
