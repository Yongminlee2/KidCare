import SwiftUI

/// 타임라인 패널의 펼침 여부·마지막 펼침 높이를 **이 실행 동안만** 기억한다. 정본은
/// 안드로이드 `MapTimelineFragment` 의 `onSaveInstanceState`(:1292-1297)와
/// `onViewCreated`(:175-179)가 주고받는 `KEY_TIMELINE_EXPANDED`/
/// `KEY_TIMELINE_CONTENT_HEIGHT` — SharedPreferences 가 아니라 `savedInstanceState`
/// 다. 그래서 앱을 새로 켜면 접힘·기본 높이로 시작하고, 같은 실행 안에서 이 화면이
/// 다시 만들어질 때만 이어진다.
///
/// 통합 검토 M4: 예전 구현은 이 값을 기기 설정 저장소에 영구 저장해 앱을 다시 켜도
/// 펼친 채로 복원했고, 주석도 SharedPreferences 라고 잘못 적었다. 영구 저장을
/// 지우고 메모리에만 둔다.
@MainActor
final class TimelinePanelStore {
    /// 이 실행 동안 모든 `TimelinePanelView` 가 함께 쓰는 기억.
    static let shared = TimelinePanelStore()

    var isExpanded = false
    /// 마지막으로 펼쳐져 있던 콘텐츠 높이. 아직 한 번도 펼치지 않았으면 안드로이드
    /// `DEFAULT_TIMELINE_CONTENT_HEIGHT_DP` 와 같은 기본값이다.
    var contentHeight: CGFloat = TimelinePanel.defaultContentHeight

    init() {}
}

/// 지도 위에 뜨는, 접기·드래그 가능한 타임라인 패널. 정본은 안드로이드
/// `fragment_map_timeline.xml` 의 `timeline_panel` + `MapTimelineFragment`
/// `bindTimelineDragHandle`(:908)·`settleTimelineDrag`(:968)·
/// `renderTimelinePanel`(:876)·`renderTimelineToggleState`(:893)·
/// `collapsedPanelHeight`(:992). 높이 계산 자체(경계값 56/96/340/0.72)는
/// `Logic/TimelinePanel.swift` 의 순수 함수가 하고, 이 뷰는 제스처·레이아웃·
/// 같은 실행 안의 기억(`TimelinePanelStore`)만 맡는다.
///
/// **패널이 지도 위에 뜬다** — 안드로이드처럼 `ChildMapView` 가 이 뷰를
/// `NaverMapView` 와 같은 `ZStack` 의 `.bottom` 정렬 자식으로 얹는다(예전처럼
/// `VStack` 으로 나란히 두지 않는다). 그래야 지도가 패널 아래까지 꽉 차 보이고,
/// 패널을 접으면 지도가 더 넓어진다 — 그리고 이게 "네이버 지도 뷰가 제스처를
/// 삼킨다"는 hazard 가 실제로 생기는 이유이기도 하다(드래그 손잡이가 지도 바로
/// 위에 얹혀 있다, Phase 1 관측).
///
/// **제스처가 지도와 안 싸우는 이유:** 드래그 손잡이의 제스처를
/// `DragGesture(minimumDistance:)`(안드로이드 `ViewConfiguration.scaledTouchSlop`
/// 과 같은 발상 — 손가락이 일정 거리를 넘게 움직여야만 "드래그"로 인정한다)로
/// 두고, `.highPriorityGesture` 로 붙여 이 뷰 아래(지도)나 위 계층의 다른
/// 제스처보다 항상 먼저 이기게 한다. `minimumDistance` 밑에서 손을 떼면 이
/// 드래그 제스처는 아예 시작도 안 하므로, 같은 손잡이의 `.onTapGesture`(접기/
/// 펼치기)가 그 짧은 탭을 대신 받는다 — 안드로이드가 `dragging` 플래그로 탭과
/// 드래그를 가르고 `ACTION_UP` 에서 `performClick()` 을 직접 부르는 것과 같은
/// 결과를 SwiftUI 제스처 두 개의 조합으로 얻는다.
struct TimelinePanelView: View {
    let viewModel: MapViewModel
    /// 화면 전체 높이 — `TimelinePanel` 의 0.72 비율 계산에 쓴다. 정본은 안드로이드
    /// `_binding?.root?.height`.
    let rootHeight: CGFloat
    let store: TimelinePanelStore

    init(viewModel: MapViewModel, rootHeight: CGFloat, store: TimelinePanelStore = .shared) {
        self.viewModel = viewModel
        self.rootHeight = rootHeight
        self.store = store
        let restoredExpanded = store.isExpanded
        let restoredHeight = store.contentHeight
        _expanded = State(initialValue: restoredExpanded)
        _contentHeight = State(initialValue: restoredExpanded ? restoredHeight : 0)
        _lastExpandedHeight = State(initialValue: restoredHeight)
    }

    /// 정본은 안드로이드 `timelineExpanded`. 손을 뗀 자리(settle)와 토글 버튼만
    /// 바꾼다 — 드래그 도중에는 바뀌지 않는다(안드로이드도 같다).
    @State private var expanded: Bool
    /// 지금 그리는 콘텐츠 높이. 드래그 중에는 프레임마다 바뀌고, 손을 떼면
    /// `TimelinePanel.settle` 이 정한 값으로 스냅한다.
    @State private var contentHeight: CGFloat
    /// 정본은 안드로이드 `lastExpandedTimelineHeight` — 토글로 다시 펼 때 이
    /// 값으로 돌아간다.
    @State private var lastExpandedHeight: CGFloat
    @State private var dragStartContentHeight: CGFloat = 0
    @State private var isDragging = false

    /// 안드로이드 `collapsedPanelHeight()` 가 보통 때 되돌려주는 값과 같다 — 손잡이
    /// (28) + 경로 요약 줄(54) + 날짜 이동 줄(54) = 136, 상수 그 자체다. 세 줄
    /// 높이가 고정돼 있어 안드로이드처럼 매 프레임 실측할 필요가 없다.
    private var basePanelHeight: CGFloat { TimelinePanel.collapsedPanelHeight }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            routeSummaryRow
            timelineContent
            dayNavigationRow
        }
        .background(Self.panelBackground)
        .clipShape(.rect(topLeadingRadius: 20, topTrailingRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
        .onAppear {
            // 이어받은 값을 곧바로 MapViewModel(→ Task 8 자리)에 알린다 — 화면이
            // 처음 뜬 순간부터 지도 컨트롤·로고 여백이 그 높이를 반영해야 한다
            // (안드로이드는 `onViewCreated` 에서 savedInstanceState 를 읽고 첫
            // 레이아웃 때 `updateMapControls` 를 부르므로 같은 자리다).
            publish()
        }
    }

    /// 통합 검토 D1: 패널 바탕은 **불투명**하다 — 정본은 안드로이드 `timeline_panel`
    /// 의 `cardBackgroundColor="@color/paper_card"`. 예전엔 `.regularMaterial` 이었는데,
    /// 그 위에서 계층형 전경 스타일로 그린 것들(행의 시각·기간 줄 `.secondary`, 행 사이
    /// `Divider`)이 화면에 전혀 찍히지 않았다. 실기기(실제 가족 데이터)와 시뮬레이터
    /// (Task 6 스크린샷) 모두 데이터와 무관하게 "제목만 있고 아래 줄이 빈" 행이 됐다 —
    /// 줄 간격은 두 줄짜리 그대로 남아 있었다. 바탕만 불투명 색으로 바꾸자 같은
    /// 빌드에서 상세 줄이 그대로 나타났다(`TimelinePanelRenderTests` 가 픽셀로 확인한다).
    static var panelBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    // MARK: - 손잡이

    private var dragHandle: some View {
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 42, height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .contentShape(Rectangle())
        .accessibilityLabel(Text("timeline_drag_handle"))
        .accessibilityAddTraits(.isButton)
        // 이 gesture 하나 위에서 드래그와 탭을 함께 받는다 — 별도의 `.onTapGesture`
        // 를 더하지 않는다. `DragGesture(minimumDistance:)` 는 `onChanged` 는
        // `minimumDistance` 를 넘어야만 부르지만, **`onEnded` 는 손가락이 그 거리를
        // 못 넘기고 뗀 순수 탭에도 그대로 불린다**(시뮬레이터로 직접 눌러보고서야
        // 드러난 함정 — `isDragging` 을 안 보고 매번 `settle()` 만 부르던 첫 구현은
        // 접힌 채 탭해도 반응이 없었다). 그래서 `onEnded` 안에서 `isDragging` 으로
        // "정말 드래그였는지"를 직접 갈라 안드로이드 `dragging` 플래그 +
        // `performClick()` 과 같은 결과를 낸다.
        .highPriorityGesture(
            // 통합 검토 I3: `.global` 로 잰다. 손잡이는 패널이 커지는 만큼 함께
            // 올라가므로 `.local`(움직이는 손잡이 자신의 좌표)로 재면 번역값이 그
            // 이동만큼 줄어 반 속도로 따라오고 흔들렸다. 정본인 안드로이드도 화면
            // 좌표 `event.rawY` 로 잰다.
            DragGesture(minimumDistance: Self.touchSlop, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartContentHeight = contentHeight
                    }
                    // 위로 끌면(translation.height 가 음수) 패널이 커진다.
                    let candidate = dragStartContentHeight - value.translation.height
                    contentHeight = TimelinePanel.clampDuringDrag(
                        contentHeight: candidate, basePanelHeight: basePanelHeight, rootHeight: rootHeight
                    )
                    // 통합 검토 M3: 지도 버튼·네이버 로고 여백이 손가락을 따라 매
                    // 이동마다 움직여야 한다(안드로이드 ACTION_MOVE 의
                    // `updateMapControls`, :945-947) — 안착 때만 옮기면 드래그 도중
                    // 로고가 패널에 가려진다(SDK 약관).
                    viewModel.타임라인_패널을_끄는_중이다(콘텐츠_높이: contentHeight)
                }
                .onEnded { _ in
                    // 버그였던 자리(실기기로 직접 눌러보고서야 드러났다): `minimumDistance`
                    // 밑에서 손을 뗀 탭도 SwiftUI 는 이 `onEnded` 를 그대로 부른다(단지
                    // `onChanged` 를 건너뛸 뿐이다) — `isDragging` 을 보지 않고 매번
                    // `settle()` 만 부르면, 접힌 채 탭했을 때 "지금 높이(0)로 안착"만
                    // 반복해 토글이 전혀 안 먹혔다. 실제로 드래그가 있었을 때만
                    // settle 하고, 없었으면(순수 탭) toggle 한다 — 안드로이드
                    // `dragging` 플래그로 `performClick()` 을 가르는 것과 같은 분기다.
                    switch TimelinePanel.release(isDragging: isDragging) {
                    case .settle: settle()
                    case .toggle: toggle()
                    }
                    isDragging = false
                }
        )
    }

    /// SwiftUI 의 기본 드래그 인식 문턱(대략 10pt)과 같은 값을 명시적으로 쓴다 —
    /// 안드로이드 `ViewConfiguration.get(requireContext()).scaledTouchSlop` 과 같은
    /// 역할(손가락이 이 거리를 넘게 움직여야만 "드래그"로 본다)이지만, 안드로이드의
    /// dp 값을 그대로 옮기지 않는다: 그 값은 안드로이드 프레임워크의 터치 인식
    /// 상수라 iOS 로 그대로 옮길 근거가 없고, SwiftUI 자체의 기본 드래그 인식
    /// 문턱을 그대로 쓰는 편이 이 플랫폼에서 "자연스러운 드래그" 로 느껴진다.
    private static let touchSlop: CGFloat = 10

    // MARK: - 경로 요약 + 토글

    private var routeSummaryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(viewModel.경로_요약_문구)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Task 8: 전체 구간 숨김/보임. 정본은 안드로이드 `routeVisibilityButton`
            // + `renderRouteVisibilityState`(:1111).
            Button {
                viewModel.전체_경로를_토글한다()
            } label: {
                Image(systemName: viewModel.경로_전체_보임 ? "eye" : "eye.slash")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(!viewModel.경로_숨김_버튼_활성화)
            // 구간이 없으면 알아볼 수 있게 흐리게 — 안드로이드 alpha 0.38 과 같다(브리프).
            .opacity(viewModel.경로_숨김_버튼_활성화 ? 1 : 0.38)
            .accessibilityLabel(Text(viewModel.경로_숨김_버튼_접근성_문구))

            Button(action: toggle) {
                HStack(spacing: 4) {
                    Text(String(localized: expanded ? "timeline_collapse" : "timeline_view_records"))
                        .font(.caption.weight(.semibold))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            // 정본은 안드로이드 `renderTimelineToggleState`(:893) — 접혀 있으면
            // "펼치기" 설명을, 펼쳐져 있으면 "접기" 설명을 읽어준다. 기존 안드로이드
            // 키(`timeline_expand`/`timeline_collapse`)를 그대로 재사용한다 — 새
            // 키를 만들지 않는다(brief).
            .accessibilityLabel(Text(expanded ? "timeline_collapse" : "timeline_expand"))
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    // MARK: - 콘텐츠(타임라인 목록 / 빈 상태)

    /// 정본은 안드로이드 `setTimelineContentHeight`(:985) — 콘텐츠 높이를 직접
    /// 갱신하고, 0이면 감춘다(`content.isVisible = safeHeight > 0`).
    private var timelineContent: some View {
        Group {
            if viewModel.타임라인_행.isEmpty {
                Text(String(localized: "timeline_empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 정본은 안드로이드 `timeline_list`: 가로 `LinearLayoutManager`
                // (`MapTimelineFragment` :198-199), 목록 안쪽 여백 가로 10·세로 6,
                // `clipToPadding=false`. 카드마다 바깥 여백 가로 5·세로 2
                // (`item_timeline.xml`), 높이는 콘텐츠 높이를 채운다. 구분선은 없다.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(viewModel.타임라인_행, id: \.segmentIndex) { row in
                            TimelineRowView(row: row)
                                // Task 8: 정본은 안드로이드 타임라인 어댑터의 탭
                                // 처리(:894-896) — 이동 구간이면 그 선을 켜고
                                // 끄고, 그렇지 않으면(머무름 등) 그 좌표로
                                // 카메라를 포커스한다. 카드 전체가 탭 대상이다.
                                .onTapGesture { viewModel.타임라인_행을_탭한다(row) }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(height: max(contentHeight, 0))
        .clipped()
        .opacity(contentHeight > 0 ? 1 : 0)
        .allowsHitTesting(contentHeight > 0)
    }

    // MARK: - 날짜 이동

    /// `◀ 오늘 ▶`. Task 4 가 만든 것을 그대로 옮겨 왔다 — 정본은 안드로이드
    /// `fragment_map_timeline.xml` 의 `prev_day_button`/`day_header`/`next_day_button`
    /// + `renderDayHeader`(:867). 접근성 라벨(`day_prev`/`day_next`)은 기존 안드로이드
    /// 키를 그대로 쓴다.
    private var dayNavigationRow: some View {
        HStack {
            Button {
                Task { await viewModel.이전_날로() }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("day_prev"))

            Spacer()

            Text(viewModel.날짜_헤더_문구)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            Spacer()

            Button {
                Task { await viewModel.다음_날로() }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(!viewModel.다음_날로_갈_수_있는가)
            .accessibilityLabel(Text("day_next"))
        }
        .padding(.horizontal, 10)
        .buttonStyle(.plain)
        .frame(height: 54)
    }

    // MARK: - 상태 변화

    /// 짧은 탭(드래그가 시작되지 않은 채 손을 뗌)과 토글 버튼이 같이 쓴다. 정본은
    /// 안드로이드 `bindTimelineDragHandle` 의 `handle.setOnClickListener`(:920) —
    /// "펼침/접힘을 그대로 뒤집는다"만 하고 `renderTimelinePanel()` 을 다시 부른다.
    private func toggle() {
        expanded.toggle()
        contentHeight = TimelinePanel.toggledContentHeight(
            expanded: expanded, lastExpandedHeight: lastExpandedHeight,
            basePanelHeight: basePanelHeight, rootHeight: rootHeight
        )
        if expanded { lastExpandedHeight = contentHeight }
        publish()
    }

    /// 드래그를 놓았을 때. 정본은 안드로이드 `settleTimelineDrag`(:968).
    private func settle() {
        let settled = TimelinePanel.settle(
            contentHeight: contentHeight, basePanelHeight: basePanelHeight, rootHeight: rootHeight
        )
        contentHeight = settled
        expanded = settled > 0
        if expanded { lastExpandedHeight = settled }
        publish()
    }

    /// 정본은 안드로이드 `onSaveInstanceState` 가 남기는 `KEY_TIMELINE_EXPANDED`/
    /// `KEY_TIMELINE_CONTENT_HEIGHT`(이 앱은 `TimelinePanelStore` 메모리) +
    /// `MapViewModel.타임라인_패널_상태를_갱신한다` 를 통한 Task 8 자리 갱신을 한
    /// 곳에 모은다 — 토글·드래그 안착·화면 첫 등장 세 자리 모두 이 함수 하나를
    /// 지나가야 한다(잊어버리는 자리가 생기지 않게).
    private func publish() {
        store.isExpanded = expanded
        // 접혔을 때는 기억해 둔 "마지막 펼침 높이"를 건드리지 않는다 — 그래야 다음에
        // 펼쳤을 때(토글이든, 같은 실행에서 화면이 다시 만들어졌든) 방금 접기 전
        // 높이로 돌아간다.
        if expanded { store.contentHeight = lastExpandedHeight }
        viewModel.타임라인_패널_상태를_갱신한다(펼쳐짐: expanded, 콘텐츠_높이: contentHeight)
    }
}
