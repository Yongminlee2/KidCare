import SwiftUI

/// 지도 화면. 아이의 마지막 위치 마커와 그 날의 경로선, 그 날의 타임라인을 띄운다.
/// `◀ 오늘 ▶` 로 어제·그제를 넘겨볼 수 있다.
///
/// **화면이 뜰 때 한 번만 읽는다 — 구독하지 않는다.** 안드로이드
/// `FamilyRepository.fetchChildStatus`·`TrailRepository` 주석과 같은 이유다: 아이
/// 폰이 더 이상 주기적으로 위치를 올리지 않아 이 문서들은 하루 한 번, 또는 부모가
/// '지금 위치 확인'을 눌렀을 때만 바뀐다. 그런데도 화면이 떠 있는 내내 리스너를
/// 붙들면 Spark 무료 읽기 한도를 공짜로 태운다. 실시간으로 지켜보는 화면은 이후
/// Task 가 '지금 위치 확인' 버튼을 눌렀을 때만 잠깐 붙이는 라이브 세션으로 따로
/// 만들고, 그건 `FamilyRepository.observeChildStatus` 를 그때 다시 쓴다.
///
/// **상태는 이 뷰가 아니라 `MapViewModel` 이 들고 있다.** Task 4 가 옮겼다 — 이유는
/// `MapViewModel` 타입 주석 참고. 이 뷰는 뷰모델을 그리기만 한다.
struct ChildMapView: View {

    let familyId: String
    let childUid: String?

    @State private var viewModel: MapViewModel
    /// 마커가 처음 생겼을 때 카메라를 한 번만 맞추는 플래그. 지도 렌더링(`NaverMapView`)
    /// 만의 관심사라 `MapViewModel` 로 옮기지 않았다 — 날짜를 넘겨도, 다시 읽어도
    /// 상관없이 이 화면이 떠 있는 동안에는 계속 지켜야 하는 뷰 쪽 그리기 상태다.
    @State private var 카메라를_한번_맞췄나 = false

    init(familyId: String, childUid: String?) {
        self.familyId = familyId
        self.childUid = childUid
        _viewModel = State(initialValue: MapViewModel(familyId: familyId, childUid: childUid))
    }

    /// Task 6: 접힘 뼈대(손잡이+경로 요약 줄+날짜 이동 줄) + 지금 콘텐츠 높이 —
    /// 지도 컨트롤(현재 위치 버튼)과 네이버 로고 여백이 이 값만큼 패널 위로
    /// 떠야 한다. 정본은 안드로이드 `timelinePanelHeight()`(:1338).
    private var 패널_전체_높이: CGFloat {
        TimelinePanel.collapsedPanelHeight + viewModel.타임라인_콘텐츠_높이
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                NaverMapView(
                    markerAt: viewModel.상태.map { (lat: $0.lat, lng: $0.lng) },
                    routeSections: viewModel.경로_구간,
                    panelHeight: 패널_전체_높이,
                    카메라를_한번_맞췄나: $카메라를_한번_맞췄나,
                    카메라를_다시_맞춰야_한다: Binding(
                        get: { viewModel.카메라를_다시_맞춰야_한다 },
                        set: { if !$0 { viewModel.카메라_재조준을_마쳤다() } }
                    )
                )
                .ignoresSafeArea()

                // I1(리뷰): 상태 카드는 항상 그린다 — 안드로이드 `status_card` 가
                // 아이 선택 여부와 무관하게 늘 떠 있고 그 안의 한 줄만 바뀌는 것과
                // 같다(:222). 대기 문구·오류·명령 진행 상태를 전부 이 한 줄이
                // 맡는다(`StatusCardView.상태_문구` 참고) — 예전처럼 지도 위에
                // 따로 겹쳐 그리면 그 배너가 이 카드를 덮어 "전달 중…"/실패 문구가
                // 안 보이거나 잘렸다(리뷰 shot0~shot3). 패널은 화면 아래쪽에 따로
                // 뜨므로(overlay(alignment: .bottom) 참고) 패널이 아무리 커져도
                // 이 카드를 가리지 않는다.
                StatusCardView(
                    childName: viewModel.아이_이름,
                    status: viewModel.상태,
                    nowMillis: viewModel.서버기준_지금,
                    hasChild: childUid != nil,
                    loadError: viewModel.오류,
                    // Task 7: 실시간 추적이 켜져 있는 동안(off 가 아닌 동안)에는
                    // 그 문구가 '지금 위치 확인' 진행 문구보다 우선한다 — 두
                    // 버튼이 인터락되어(위치확인 버튼이 실시간 추적 중엔 막힌다)
                    // 동시에 보여줄 실제 경합이 없다.
                    commandStatusText: viewModel.실시간_상태_문구 ?? viewModel.명령_상태_문구,
                    isCommandBusy: viewModel.commandProgress.isInFlight || viewModel.liveTrackingState == .starting
                )
            }
            .overlay(alignment: .bottomTrailing) {
                // 정본은 안드로이드 `updateMapControls`(:1204) — 버튼 하단 여백을
                // 패널의 지금 높이에 맞춰 띄운다(고정 dp 가 아니다). 패널이
                // 접혀 있어도 뼈대(136)만큼은 항상 비켜 서 있어야 한다.
                VStack(spacing: 10) {
                    실시간_버튼
                    지금위치_버튼
                }
                .padding(.trailing, 14)
                .padding(.bottom, 패널_전체_높이 + 12)
            }
            .overlay(alignment: .bottom) {
                // Task 6: 패널이 지도 위에 뜬다(예전의 VStack 나열이 아니다) —
                // `TimelinePanelView` 타입 주석의 "패널이 지도 위에 뜬다" 참고.
                TimelinePanelView(viewModel: viewModel, rootHeight: geo.size.height)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        // `.task` 는 화면이 사라지면 스스로 취소한다 — 구독이 아니라 한 번의
        // 읽기라 onDisappear 에서 따로 걷어낼 리스너가 없다.
        .task { await viewModel.하루를_읽는다() }
        // C1-b(리뷰): 화면이 떠 있는 동안 "지금"을 60초마다 다시 잰다(Firestore 를
        // 새로 타지 않는다 — `MapViewModel.시계를_돈다()` 주석 참고). `.task` 라
        // 화면이 사라지면 이 태스크도 스스로 취소된다.
        .task { await viewModel.시계를_돈다() }
        // '지금 위치 확인'의 명령 리스너·60초 타이머는 `.task` 처럼 스스로 걷히지
        // 않는다(그 값이 구독이 아니라 명시적인 `ListenerRegistration` 이라서다) —
        // 화면이 사라질 때 반드시 여기서 정리한다(브리프 "Testability").
        .onDisappear {
            viewModel.명령_추적을_정리한다()
            // Task 7: 화면이 사라질 때 실시간 세션의 리스너·타이머도 반드시
            // 뗀다(브리프 "Remove it ... when the screen disappears") — 안 하면
            // 화면을 나가도 아이 상태 구독이 몇 초마다 계속 읽기를 태운다.
            viewModel.실시간_추적을_정리한다()
        }
    }

    /// '지금 위치 확인' 버튼. 정본은 안드로이드 `fragment_map_timeline.xml` 의
    /// `locate_button`(원형, 지도 오른쪽 아래) — `status_card` 의 일부가 아니라
    /// 별도로 떠 있는 요소다(진행 문구·스피너만 카드 쪽, `StatusCardView` 참고).
    private var 지금위치_버튼: some View {
        Button {
            Task { await viewModel.지금_위치를_확인한다() }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.위치확인_버튼_활성화)
        // 비활성 상태가 눈에 보여야 한다 — 안드로이드 `setLocateButtonEnabled` 가
        // alpha 를 0.48 로 낮추는 것과 같은 값(브리프 "A disabled button must
        // look disabled").
        .opacity(viewModel.위치확인_버튼_활성화 ? 1 : 0.48)
        .accessibilityLabel(Text("map_locate_now"))
    }

    /// Task 7: 실시간 보기 토글. 정본은 안드로이드 `liveTrackingButton`(:906) —
    /// 켜짐/전환 중/꺼짐 세 배경색까지는 옮기지 않지만(이 앱은 시스템 accent
    /// 하나로 켜짐을 표시한다), 안드로이드처럼 **보이는 문구**(`실시간_버튼_문구`)
    /// 와 접근성 문구(`실시간_버튼_접근성_문구`)를 둘 다 옮긴다 — 아이콘 하나뿐인
    /// '지금 위치 확인' 버튼과 달리, 이 버튼은 지금 상태(꺼짐/연결 중/켜짐)를
    /// 문구로도 보여줘야 하는 세 갈래짜리 토글이라서다(브리프).
    private var 실시간_버튼: some View {
        Button {
            Task { await viewModel.실시간_추적을_토글한다() }
        } label: {
            Label {
                Text(viewModel.실시간_버튼_문구)
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: viewModel.liveTrackingState == .off ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right.slash")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.liveTrackingState == .off ? Color(.systemGray5) : Color.green)
        .foregroundStyle(viewModel.liveTrackingState == .off ? Color.primary : Color.white)
        .disabled(childUid == nil)
        // 비활성 상태가 눈에 보여야 한다 — 안드로이드 `renderLiveTrackingState` 의
        // alpha 0.55 와 같은 값.
        .opacity(childUid == nil ? 0.55 : 1)
        .accessibilityLabel(Text(viewModel.실시간_버튼_접근성_문구))
    }
}
