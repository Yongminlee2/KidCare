import SwiftUI

/// 보호자 본 화면 — 하단 탭 다섯의 컨테이너. 정본은 안드로이드 `GuardianMainActivity`.
///
/// **탭마다의 뷰모델을 여기서 소유한다.** 안드로이드는 프래그먼트를 태그로 찾아 두고
/// show/hide 로만 오가서(`:39-42`, `showTab` :329-353), 다른 탭을 보는 동안에도 지도
/// 프래그먼트의 명령 추적·실시간 세션이 살아 있다. SwiftUI `TabView` 도 탭 뷰의 상태는
/// 살려 두지만 탭을 옮길 때마다 `onDisappear` 를 부르므로, 수명이 걸린 정리는 탭 뷰가
/// 아니라 이 뷰의 `onDisappear`(= 안드로이드 `onDestroyView` 자리)에 둔다.
struct GuardianRootView: View {

    @State private var mapViewModel: MapViewModel
    /// 관리 탭 뷰모델. 지도와 같은 이유로 탭 전환보다 오래 산다 — 안드로이드 관리 프래그먼트도
    /// show/hide 로만 오가며 `settings/ringer` 리스너를 붙든 채 둔다(계획서 판정 기록 2).
    @State private var controlViewModel: ControlViewModel
    /// 예약 탭 뷰모델. 지도·관리와 같은 수명(계획서 5단계 판정 기록 7).
    @State private var scheduleViewModel: ScheduleViewModel
    /// 장소 탭 뷰모델. 지도·관리와 같은 수명(계획서 5단계 판정 기록 7) — 편집 화면을 연 채 다른 탭을
    /// 봤다 돌아와도 편집 중인 좌표가 남는다(판정 기록 9).
    @State private var placeViewModel: PlaceViewModel
    /// 알림 탭 뷰모델. 지도·관리·예약·장소와 같은 수명이다. 보임은 이 뷰가 탭 선택과 앱 활성으로 알려준다.
    @State private var alertViewModel: AlertViewModel
    /// 무응답 배너의 유일한 주인(안드로이드 `GuardianMainActivity` :53-56).
    @State private var banner: DisconnectBanner
    @Environment(\.scenePhase) private var scenePhase
    /// 안드로이드 `onSaveInstanceState` 의 `KEY_SELECTED_TAB`(:459-462) 자리. 처음엔 지도(:172).
    @SceneStorage("guardian.selectedTab") private var selectedTab: GuardianTab = .map

    init(familyId: String, childUid: String?) {
        let map = MapViewModel(familyId: familyId, childUid: childUid)
        let banner = DisconnectBanner(childUid: childUid)
        // 둘 다 같은 init 안에서 만들어 서로를 잇는다. SwiftUI 가 init 을 여러 번 불러도
        // @State 는 첫 쌍만 붙들므로 살아남는 지도 뷰모델은 살아남는 배너를 가리킨다.
        map.대답이_기록되면 = { [weak banner] in banner?.다시_판정한다() }
        _mapViewModel = State(initialValue: map)
        _banner = State(initialValue: banner)
        let control = ControlViewModel(familyId: familyId, childUid: childUid)
        // 관리 탭의 대답도 배너를 곧바로 다시 판정하게 한다(ControlFragment.kt:747-750).
        control.대답이_기록되면 = { [weak banner] in banner?.다시_판정한다() }
        _controlViewModel = State(initialValue: control)
        _scheduleViewModel = State(initialValue: ScheduleViewModel(familyId: familyId, childUid: childUid))
        _placeViewModel = State(initialValue: PlaceViewModel(familyId: familyId, childUid: childUid))
        // 실기기 확인(-readOnlyCheck)에서는 진짜 가족에 읽음을 쓰지 않는다(6단계 판정 기록 10).
        let markRead: AlertViewModel.MarkRead
        if ReadOnlyCheck.isOn {
            markRead = { _, _ in }
        } else {
            markRead = { familyId, ids in try await EventRepository.markRead(familyId: familyId, ids: ids) }
        }
        _alertViewModel = State(initialValue: AlertViewModel(familyId: familyId, childUid: childUid, markRead: markRead))
    }

    var body: some View {
        // 배너는 탭 컨테이너 **밖**, 위에 둔다(activity_guardian_main.xml:65-73) — 어느 탭을
        // 보든 같은 자리에 같은 문장이다.
        VStack(spacing: 0) {
            if let 문구 = banner.문구 {
                DisconnectBannerView(text: 문구)
            }
            TabView(selection: $selectedTab) {
                ChildMapView(viewModel: mapViewModel)
                    .tabItem { Label(GuardianTab.map.title, systemImage: GuardianTab.map.systemImage) }
                    .tag(GuardianTab.map)
                AlertView(viewModel: alertViewModel)
                    // 처음 보일 때 구독(AlertFragment.onViewCreated :116), 그리고 보임을 맞춘다(onResume :177-180).
                    .onAppear {
                        alertViewModel.시작한다()
                        알림_보임을_맞춘다()
                    }
                    .tabItem { Label(GuardianTab.alert.title, systemImage: GuardianTab.alert.systemImage) }
                    .tag(GuardianTab.alert)
                ControlView(viewModel: controlViewModel)
                    // 안드로이드는 관리 탭을 처음 보여줄 때 프래그먼트를 만들고 subscribe 한다
                    // (showTab 의 tx.add :339-341). 두 번째부터는 뷰모델이 무시한다.
                    .onAppear { controlViewModel.시작한다() }
                    .tabItem { Label(GuardianTab.control.title, systemImage: GuardianTab.control.systemImage) }
                    .tag(GuardianTab.control)
                ScheduleView(viewModel: scheduleViewModel)
                    // 처음 보일 때 구독(ScheduleFragment.kt:279), 보일 때마다 못 보낸 알림 재시도 —
                    // 안드로이드는 첫 onResume(:293-297)과 onHiddenChanged(false)(:288-291)가 이 자리다.
                    .onAppear {
                        scheduleViewModel.시작한다()
                        scheduleViewModel.다시_알린다()
                    }
                    .tabItem { Label(GuardianTab.schedule.title, systemImage: GuardianTab.schedule.systemImage) }
                    .tag(GuardianTab.schedule)
                PlaceView(viewModel: placeViewModel)
                    // PlaceFragment.kt:232(subscribe), :290-294(onResume), :317-320(onHiddenChanged).
                    .onAppear {
                        placeViewModel.시작한다()
                        placeViewModel.다시_알린다()
                    }
                    .tabItem { Label(GuardianTab.place.title, systemImage: GuardianTab.place.systemImage) }
                    .tag(GuardianTab.place)
            }
            // themes.xml:186-195 — 탭 띠 바탕 paper_card, 선택 항목 sky. 지도 위에서도 탭 띠가
            // 투명해지지 않게 바탕을 늘 보이게 둔다(안드로이드는 그림자 대신 선으로 띠를 뗀다).
            .tint(KidCarePalette.sky)
            .toolbarBackground(KidCarePalette.paperCard, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
        // 안드로이드 onStart 에서 곧바로 한 번 판정하고 1분마다, onStop 에서 멈춘다(:395-421).
        // scenePhase 가 바뀌면 이 task 가 취소되고 새로 시작한다.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await banner.주기적으로_판정한다()
        }
        // 앱으로 돌아왔을 때는 **보고 있는** 탭만 재시도한다 — 안드로이드 onResume 의 `if (!isHidden)`
        // (ScheduleFragment.kt:294-297, PlaceFragment.kt:290-294).
        .onChange(of: scenePhase) { _, phase in
            // 알림 목록은 백그라운드로 내려갈 때도 알아야 한다(AlertFragment.onPause :182-187) — guard 보다 앞.
            알림_보임을_맞춘다(phase: phase)
            guard phase == .active else { return }
            if selectedTab == .schedule { scheduleViewModel.다시_알린다() }
            if selectedTab == .place { placeViewModel.다시_알린다() }
        }
        // 탭 전환은 안드로이드 onHiddenChanged(:172-175) 자리다.
        .onChange(of: selectedTab) { _, _ in 알림_보임을_맞춘다() }
        .onDisappear {
            mapViewModel.정리한다()
            controlViewModel.정리한다()
            scheduleViewModel.정리한다()
            placeViewModel.정리한다()
            alertViewModel.정리한다()
        }
    }

    /// 알림 목록이 지금 부모 눈앞에 있는가 — 알림 탭이 골라져 있고 앱이 활성일 때뿐이다(`setVisible` :189-202).
    /// `phase` 는 onChange 가 넘기는 새 값이다(그 순간 환경값이 아직 옛 값일 수 있어 인자를 먼저 본다).
    private func 알림_보임을_맞춘다(phase: ScenePhase? = nil) {
        alertViewModel.보임이_바뀌었다(selectedTab == .alert && (phase ?? scenePhase) == .active)
    }
}
