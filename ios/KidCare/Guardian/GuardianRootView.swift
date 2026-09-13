import SwiftUI
import UIKit

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
    /// 선택 탭. 주인은 `GuardianHomeView` 다 — 아이를 바꿔 이 뷰가 다시 만들어져도 보던 탭이 남아야 하고
    /// (recreateTabsForSelectedChild :293-298), 바깥의 선택기 줄이 지도 탭인지 알아야 한다(:330).
    @Binding var selectedTab: GuardianTab
    /// "이 아이폰을 가족에서 빼기". 서버에서 빠진 뒤 이 폰의 기록을 지우기 **전에** 다섯 탭을 떼게 정리를 건다(리뷰 M3) —
    /// 탭 콜백이 명령 기록·못 보낸 알림 깃발을 지운 뒤에 다시 쓰지 못하게. 미리보기·테스트처럼 없으면 걸지 않는다.
    @Environment(LeaveFamilyModel.self) private var leave: LeaveFamilyModel?
    @State private var 정리_열쇠 = UUID()
    /// 키보드가 올라온 동안에는 탭 띠를 숨긴다 — 예전 시스템 탭 막대가 키보드 뒤로 숨던 것과 같게.
    /// 붙박이 띠가 `VStack` 맨 아래라 그대로 두면 키보드 위로 떠올라 입력칸을 가린다.
    @State private var 키보드_올라옴 = false

    init(familyId: String, childUid: String?, selectedTab: Binding<GuardianTab>) {
        _selectedTab = selectedTab
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
        // 실기기 확인(-readOnlyCheck)에서는 진짜 가족에 읽음을 쓰지 않는다(6단계 판정 기록 10, 통합 검토 I2).
        let markRead = ReadOnlyCheck.alertMarkRead(readOnly: ReadOnlyCheck.isOn)
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
                    .toolbar(.hidden, for: .tabBar)
                AlertView(viewModel: alertViewModel)
                    // 처음 보일 때 구독(AlertFragment.onViewCreated :116), 그리고 보임을 맞춘다(onResume :177-180).
                    .onAppear {
                        alertViewModel.시작한다()
                        알림_보임을_맞춘다()
                    }
                    .tabItem { Label(GuardianTab.alert.title, systemImage: GuardianTab.alert.systemImage) }
                    .tag(GuardianTab.alert)
                    .toolbar(.hidden, for: .tabBar)
                ControlView(viewModel: controlViewModel)
                    // 안드로이드는 관리 탭을 처음 보여줄 때 프래그먼트를 만들고 subscribe 한다
                    // (showTab 의 tx.add :339-341). 두 번째부터는 뷰모델이 무시한다.
                    .onAppear { controlViewModel.시작한다() }
                    .tabItem { Label(GuardianTab.control.title, systemImage: GuardianTab.control.systemImage) }
                    .tag(GuardianTab.control)
                    .toolbar(.hidden, for: .tabBar)
                ScheduleView(viewModel: scheduleViewModel)
                    // 처음 보일 때 구독(ScheduleFragment.kt:279), 보일 때마다 못 보낸 알림 재시도 —
                    // 안드로이드는 첫 onResume(:293-297)과 onHiddenChanged(false)(:288-291)가 이 자리다.
                    .onAppear {
                        scheduleViewModel.시작한다()
                        scheduleViewModel.다시_알린다()
                    }
                    .tabItem { Label(GuardianTab.schedule.title, systemImage: GuardianTab.schedule.systemImage) }
                    .tag(GuardianTab.schedule)
                    .toolbar(.hidden, for: .tabBar)
                PlaceView(viewModel: placeViewModel)
                    // PlaceFragment.kt:232(subscribe), :290-294(onResume), :317-320(onHiddenChanged).
                    .onAppear {
                        placeViewModel.시작한다()
                        placeViewModel.다시_알린다()
                    }
                    .tabItem { Label(GuardianTab.place.title, systemImage: GuardianTab.place.systemImage) }
                    .tag(GuardianTab.place)
                    .toolbar(.hidden, for: .tabBar)
            }
            .tint(KidCarePalette.sky)
            // 탭 막대는 안드로이드 모양의 붙박이 띠로 따로 그린다(`KidCareTabBar` 머리 주석). `TabView` 는 선택과
            // 탭마다의 수명만 맡는다. 띠가 `TabView` 아래 칸을 차지하므로 어느 탭의 내용(밀려 들어간 편집 판 포함)도
            // 띠 밑으로 숨지 않는다.
            if !키보드_올라옴 {
                KidCareTabBar(selection: $selectedTab)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in 키보드_올라옴 = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in 키보드_올라옴 = false }
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
        // 아이를 바꾸면 `GuardianHomeView` 의 `.id(childUid)` 가 이 뷰를 통째로 새로 만들고, 옛 뷰의 이 자리가 불린다.
        .onAppear {
            let (map, control, schedule, place, alert) =
                (mapViewModel, controlViewModel, scheduleViewModel, placeViewModel, alertViewModel)
            leave?.떠나기_전에(정리_열쇠) {
                Self.탭을_모두_정리한다(map: map, control: control, schedule: schedule, place: place, alert: alert)
            }
        }
        .onDisappear {
            leave?.정리를_뗀다(정리_열쇠)
            Self.탭을_모두_정리한다(
                map: mapViewModel, control: controlViewModel, schedule: scheduleViewModel,
                place: placeViewModel, alert: alertViewModel
            )
        }
    }

    /// 다섯 탭 뷰모델의 리스너·명령 추적을 모두 뗀다(안드로이드 `recreateTabsForSelectedChild` 가 프래그먼트를 remove 해
    /// `onDestroyView` 를 부르는 자리, :288-300). 하나라도 빠지면 옛 아이의 리스너가 새 아이 화면 뒤에서 계속 돈다 —
    /// 그래서 목록을 한 함수에 두고 `GuardianChildSwitchTests` 가 이 함수를 직접 부른다.
    ///
    /// 옛 뷰모델은 새 뷰모델과 상태를 나누지 않는다(인스턴스가 다르다). 새 뷰의 `onAppear` 가 이 정리보다 먼저
    /// 불려도 옛 콜백이 새 아이 화면에 값을 흘릴 길은 없고, 정리 뒤의 콜백은 각 뷰모델의 닫힘 확인이 막는다.
    /// 예외 하나: 실시간 추적이 켜져 있었다면 지도 뷰모델이 옛 아이에게 종료 명령을 한 번 보낸다 — 안드로이드
    /// `onDestroyView` 의 `stopLiveTracking()` 과 같고, 옛 세션을 끝내는 명령이지 살아남는 추적이 아니다.
    static func 탭을_모두_정리한다(
        map: MapViewModel, control: ControlViewModel, schedule: ScheduleViewModel,
        place: PlaceViewModel, alert: AlertViewModel
    ) {
        map.정리한다()
        control.정리한다()
        schedule.정리한다()
        place.정리한다()
        alert.정리한다()
    }

    /// 알림 목록이 지금 부모 눈앞에 있는가 — 알림 탭이 골라져 있고 앱이 활성일 때뿐이다(`setVisible` :189-202).
    /// `phase` 는 onChange 가 넘기는 새 값이다(그 순간 환경값이 아직 옛 값일 수 있어 인자를 먼저 본다).
    private func 알림_보임을_맞춘다(phase: ScenePhase? = nil) {
        alertViewModel.보임이_바뀌었다(selectedTab == .alert && (phase ?? scenePhase) == .active)
    }
}
