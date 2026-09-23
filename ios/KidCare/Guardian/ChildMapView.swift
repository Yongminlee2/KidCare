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

    /// 뷰모델은 `GuardianRootView` 가 소유한다 — 탭을 오가도 같은 인스턴스가 살아 있어야
    /// 명령 추적·실시간 세션이 끊기지 않는다(안드로이드 show/hide 와 같은 수명).
    let viewModel: MapViewModel
    /// 마커가 처음 생겼을 때 카메라를 한 번만 맞추는 플래그. 지도 렌더링(`NaverMapView`)
    /// 만의 관심사라 `MapViewModel` 로 옮기지 않았다 — 날짜를 넘겨도, 다시 읽어도
    /// 상관없이 이 화면이 떠 있는 동안에는 계속 지켜야 하는 뷰 쪽 그리기 상태다.
    @State private var 카메라를_한번_맞췄나 = false

    init(viewModel: MapViewModel) {
        self.viewModel = viewModel
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
                    // Task 8: 숨긴 구간을 뺀 것을 넘긴다 — 그려야 그릴 선도,
                    // fitWholeRoute 가 맞출 범위도 이 값 하나를 지나간다.
                    routeSections: viewModel.표시할_경로_구간,
                    panelHeight: 패널_전체_높이,
                    카메라를_한번_맞췄나: $카메라를_한번_맞췄나,
                    카메라를_다시_맞춰야_한다: Binding(
                        get: { viewModel.카메라를_다시_맞춰야_한다 },
                        set: { if !$0 { viewModel.카메라_재조준을_마쳤다() } }
                    ),
                    포커스_요청: Binding(
                        get: { viewModel.포커스_요청 },
                        set: { if $0 == nil { viewModel.포커스_요청을_마쳤다() } }
                    ),
                    경로_전체_보기_요청: viewModel.경로_전체_보기_요청
                )
                // 위쪽만 상태바 뒤로 편다. 아래쪽 안전 영역은 TabView 의 탭 바다 — 거기까지
                // 펴면 네이버 로고가 탭 바 뒤로 숨어 지도 SDK 약관을 어기고, 안드로이드도
                // 프래그먼트 자리가 하단 탭 위에서 끝난다(activity_guardian_main.xml:85-89).
                .ignoresSafeArea(edges: .top)

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
                    hasChild: viewModel.childUid != nil,
                    loadError: viewModel.오류,
                    // Task 7 + 통합 검토 I1·I2: 실시간 문구·명령 문구·그보다 나중에
                    // 쓴 오류 중 무엇이 이기는지는 `MapViewModel.상태_줄_덮어쓰기_문구`
                    // 한 곳이 정한다(안드로이드 statusBar 처럼 마지막으로 쓴 쪽이 이긴다).
                    commandStatusText: viewModel.상태_줄_덮어쓰기_문구,
                    isCommandBusy: viewModel.commandProgress.isInFlight || viewModel.liveTrackingState == .starting,
                    batteryInfoKey: viewModel.배터리_설명_키
                )
            }
            .overlay(alignment: .bottomTrailing) {
                // 정본은 안드로이드 `updateMapControls`(:1204) — 버튼 하단 여백을
                // 패널의 지금 높이에 맞춰 띄운다(고정 dp 가 아니다). 패널이
                // 접혀 있어도 뼈대(136)만큼은 항상 비켜 서 있어야 한다.
                //
                // 통합 검토 D2: 정본 `fragment_map_timeline.xml` 은 실시간 버튼
                // (`live_tracking_button`, marginEnd 76dp = 14 + 위치 버튼 52 + 간격 10)과
                // 위치 버튼(`locate_button`, marginEnd 14dp)을 **같은 줄**에 나란히 두고
                // 둘 다 bottomMargin = 패널 높이 + 12dp 다. 예전엔 세로로 쌓아 실시간
                // 알약이 네이버 줌 컨트롤 자리까지 올라가 "−" 를 가렸다.
                VStack(alignment: .trailing, spacing: 8) {
                    // 문구를 탭 꼭대기가 아니라 **버튼 옆**에 두는 이유(판정 기록 7): 지도 탭은
                    // 잠긴 것이 버튼 둘뿐이고 화면 대부분은 멀쩡하다. 꼭대기에 있으면 그 문장이
                    // 무엇을 가리키는지 알 수 없다.
                    if viewModel.아이폰이라_못_한다고_말할까 {
                        Text("ios_child_no_remote_control")
                            .font(.caption)
                            .foregroundStyle(KidCarePalette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(KidCarePalette.paperCard)
                                    .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(KidCarePalette.lineSoft, lineWidth: 1)
                            )
                            .frame(maxWidth: 260, alignment: .trailing)
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        실시간_버튼
                        지금위치_버튼
                    }
                }
                .padding(.trailing, 14)
                .padding(.bottom, 패널_전체_높이 + 12)
            }
            .overlay(alignment: .bottom) {
                // Task 6: 패널이 지도 위에 뜬다(예전의 VStack 나열이 아니다) —
                // `TimelinePanelView` 타입 주석의 "패널이 지도 위에 뜬다" 참고.
                TimelinePanelView(viewModel: viewModel, rootHeight: geo.size.height)
            }
            // 아래쪽 안전 영역을 무시하지 않는다 — 타임라인 패널이 탭 바 위에서 끝나야 한다.
        }
        // 첫 읽기는 뷰모델이 한 번만 한다 — `MapViewModel.처음이면_읽는다` 주석 참고.
        // `.task` 로 두면 탭을 옮길 때마다 취소되고 돌아올 때마다 다시 읽는다.
        .onAppear { viewModel.처음이면_읽는다() }
        // C1-b(리뷰): 화면이 떠 있는 동안 "지금"을 60초마다 다시 잰다(Firestore 를
        // 새로 타지 않는다 — `MapViewModel.시계를_돈다()` 주석 참고). `.task` 라
        // 화면이 사라지면 이 태스크도 스스로 취소된다.
        .task { await viewModel.시계를_돈다() }
        // 명령·실시간 리스너 정리는 여기서 하지 않는다 — TabView 는 탭을 옮길 때마다
        // onDisappear 를 부르므로, 여기서 떼면 관리 탭을 한 번 눌렀을 뿐인데 실시간
        // 보기가 꺼진다. 안드로이드는 onDestroyView 에서만 뗀다(MapTimelineFragment.kt
        // :1299-1311). 정리는 GuardianRootView.onDisappear 가 한다.
    }

    /// '지금 위치 확인' 버튼. 정본은 안드로이드 `fragment_map_timeline.xml` 의
    /// `locate_button`(:142-168) — `status_card` 의 일부가 아니라 별도로 떠 있는
    /// 요소다(진행 문구·스피너만 카드 쪽, `StatusCardView` 참고). 52 불투명 paper_card
    /// 원, 1 line_soft 테두리, 그림자 5, 가운데 28 `ic_map_crosshair`(sky).
    private var 지금위치_버튼: some View {
        Button {
            Task { await viewModel.지금_위치를_확인한다() }
        } label: {
            MapCrosshairIcon(color: KidCarePalette.sky)
                .frame(width: 28, height: 28)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(KidCarePalette.paperCard)
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 2) // cardElevation 5
                )
                .overlay(Circle().strokeBorder(KidCarePalette.lineSoft, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.위치확인_버튼_활성화)
        // 비활성 상태가 눈에 보여야 한다 — 안드로이드 `setLocateButtonEnabled` 가
        // alpha 를 0.48 로 낮추는 것과 같은 값(브리프 "A disabled button must
        // look disabled").
        .opacity(viewModel.위치확인_버튼_활성화 ? 1 : 0.48)
        .accessibilityLabel(Text("map_locate_now"))
    }

    /// Task 7: 실시간 보기 토글. 정본은 안드로이드 `live_tracking_button`
    /// (`fragment_map_timeline.xml:117-140`) + `renderLiveTrackingState`(:642-676) —
    /// 높이 48 알약(모서리 24), 그림자 5, 14 medium 글자, 20 `ic_map_crosshair`(글자와
    /// 7 띄움), 테두리 1. 세 갈래 색: 꺼짐 = paper_card 바탕·ink_soft 글자·line 테두리,
    /// 연결 중 = apricot 바탕·흰 글자, 켜짐 = grass 바탕·흰 글자(둘 다 테두리는 바탕색).
    /// **보이는 문구**(`실시간_버튼_문구`)와 접근성 문구(`실시간_버튼_접근성_문구`)를
    /// 둘 다 옮긴다 — 지금 상태(꺼짐/연결 중/켜짐)를 문구로도 보여줘야 하는 세 갈래
    /// 토글이라서다(브리프).
    private var 실시간_버튼: some View {
        let look = LiveButtonLook(state: viewModel.liveTrackingState)
        return Button {
            Task { await viewModel.실시간_추적을_토글한다() }
        } label: {
            HStack(spacing: 7) {
                MapCrosshairIcon(color: look.foreground)
                    .frame(width: 20, height: 20)
                Text(viewModel.실시간_버튼_문구)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(look.foreground)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24) // Widget.Material3.Button 좌우 여백
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(look.background)
                    .shadow(color: .black.opacity(0.14), radius: 5, y: 2) // elevation 5
            )
            .overlay(Capsule().strokeBorder(look.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // 아이가 없거나 아이폰 아이면 막는다 — 조건은 뷰모델 한 곳이 정한다(판정 기록 1).
        .disabled(!viewModel.실시간_버튼_활성화)
        // 비활성 상태가 눈에 보여야 한다 — 안드로이드 `renderLiveTrackingState` 의
        // alpha 0.55 와 같은 값.
        .opacity(viewModel.실시간_버튼_활성화 ? 1 : 0.55)
        .accessibilityLabel(Text(viewModel.실시간_버튼_접근성_문구))
    }
}

/// 실시간 버튼의 세 갈래 색. 정본은 안드로이드 `renderLiveTrackingState` 의
/// background/foreground/stroke `when`(:651-663) — 연결 중이 켜짐보다 먼저 이긴다.
struct LiveButtonLook: Equatable {
    let background: Color
    let foreground: Color
    let stroke: Color

    init(state: LiveTrackingState) {
        switch state {
        case .starting:
            background = KidCarePalette.apricot
            foreground = KidCarePalette.onAccent
            stroke = KidCarePalette.apricot
        case .on:
            background = KidCarePalette.grass
            foreground = KidCarePalette.onAccent
            stroke = KidCarePalette.grass
        case .off:
            background = KidCarePalette.paperCard
            foreground = KidCarePalette.inkSoft
            stroke = KidCarePalette.line
        }
    }
}

/// `ic_map_crosshair.xml` 을 `app:tint` 로 한 색에 물들인 모습. 틴트는 흰 밑획(6)과
/// 잉크 윗획(2.5)을 **둘 다** 같은 색으로 칠하므로, 화면에 남는 것은 굵기 6 짜리
/// 십자 네 획(둥근 끝)과 반지름 9 고리다(48 격자). 장소 편집 지도의 두 색 십자는
/// `PlaceCrosshair` 가 따로 그린다 — 그쪽은 틴트하지 않는다.
struct MapCrosshairIcon: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 48
            var 획 = Path()
            for (from, to) in [(CGPoint(x: 24, y: 6), CGPoint(x: 24, y: 18)),
                               (CGPoint(x: 24, y: 30), CGPoint(x: 24, y: 42)),
                               (CGPoint(x: 6, y: 24), CGPoint(x: 18, y: 24)),
                               (CGPoint(x: 30, y: 24), CGPoint(x: 42, y: 24))] {
                획.move(to: from)
                획.addLine(to: to)
            }
            let 크기 = CGAffineTransform(scaleX: scale, y: scale)
            let 고리 = Path(ellipseIn: CGRect(x: 15, y: 15, width: 18, height: 18)).applying(크기)
            context.stroke(획.applying(크기), with: .color(color), style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round))
            context.stroke(고리, with: .color(color), lineWidth: 6 * scale)
        }
        .accessibilityHidden(true)
    }
}
