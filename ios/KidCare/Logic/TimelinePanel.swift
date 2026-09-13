import Foundation

/// 지도 아래 타임라인 패널의 높이 계산 — 순수 수학만. 정본은 안드로이드
/// `MapTimelineFragment.bindTimelineDragHandle`(:908)·`settleTimelineDrag`(:968)·
/// `collapsedPanelHeight`(:992)·`maxTimelineContentHeight`(:1003), 상수는
/// `MapTimelineFragment` 동반 객체(:1316-1329).
///
/// **dp 를 그대로 pt 로 옮긴다.** 안드로이드가 `dp(...)` 로 기기 밀도에 맞춰 픽셀로
/// 바꾸는 것처럼, iOS 는 포인트(pt) 가 이미 그 역할이라 숫자만 그대로 옮기면 같은
/// 자리에 같은 크기로 앉는다.
///
/// **왜 `Logic/` 에 있나.** 이 파일은 Foundation 만 쓰는 순수 함수다 —
/// `TimelinePanelView`(SwiftUI, 실제 드래그 제스처)가 이 계산을 부르기만 한다.
/// 드래그 도중 프레임마다 불리는 계산이라 화면 없이도 경계값(56/96/340)을 테스트로
/// 못박아 둘 수 있는 이 자리가 낫다 — 시뮬레이터를 띄워야만 검증되면 회귀를
/// 놓치기 쉽다(이 Task 의 커밋 1이 놓친 티커 테스트와 같은 이유).
enum TimelinePanel {

    /// 펼쳤을 때 콘텐츠(타임라인 목록 영역)의 기본 높이.
    static let defaultContentHeight: CGFloat = 174
    /// 콘텐츠가 가질 수 있는 최대 높이. `maxContentHeight(basePanelHeight:rootHeight:)`
    /// 가 화면 비율로 구한 상한이 이보다 크더라도 결국 이 값이 상한이 되는 것은
    /// 아니다 — 화면이 크면 화면 비율 쪽이 이 값보다 커질 수 있다(안드로이드
    /// `maxTimelineContentHeight` 가 `MAX_TIMELINE_CONTENT_HEIGHT_DP` 를 "루트 높이를
    /// 모를 때의 폴백"으로만 쓰는 것과 같다 — 아래 함수 주석 참고).
    static let maxContentHeightFallback: CGFloat = 340
    /// 펼친 채로 안정될 수 있는 최소 콘텐츠 높이. 드래그 중에는 이보다 더 작아질 수
    /// 있다(0까지) — `settle(contentHeight:basePanelHeight:rootHeight:)` 가 손을 뗀
    /// 순간에만 이 아래를 "접힘(0)"과 "이 값"으로 밀어 올린다.
    static let minExpandedContentHeight: CGFloat = 96
    /// 드래그를 놓았을 때 이 아래면 아예 접힌다(0). `minExpandedContentHeight` 보다
    /// 작다 — 56~96 사이에서 손을 떼면 "접히기엔 아직 남았다"고 보고 96 으로
    /// 끌어올린다(둘 사이의 차이가 곧 "이해할 수 있는 스냅" 구간이다).
    static let dragCollapseThreshold: CGFloat = 56
    /// 접혔을 때 패널 전체 높이(손잡이 + 경로 요약 줄 + 날짜 이동 줄). 콘텐츠 영역이
    /// 없는 상태의 "기본 뼈대" 높이이기도 해서, `maxContentHeight` 가 이 값을
    /// `basePanelHeight` 인자의 기본 가정으로 쓴다.
    static let collapsedPanelHeight: CGFloat = 136
    /// 패널(뼈대 + 콘텐츠)이 화면 높이에서 차지할 수 있는 최대 비율.
    static let maxPanelHeightRatio: CGFloat = 0.72

    /// 지금 조건에서 콘텐츠가 가질 수 있는 최대 높이. 정본은 안드로이드
    /// `maxTimelineContentHeight`(:1003) — `rootHeight`(화면 전체 높이)를 아직 모르면
    /// (첫 레이아웃 패스 전) `maxContentHeightFallback` 으로 물러난다. 안드로이드는
    /// `_binding?.root?.height` 가 0일 때 이 폴백을 쓴다 — 뷰가 아직 한 번도
    /// 측정되지 않은 극초반 프레임을 위한 방어다.
    static func maxContentHeight(basePanelHeight: CGFloat, rootHeight: CGFloat) -> CGFloat {
        guard rootHeight > 0 else { return maxContentHeightFallback }
        let maxPanelHeight = (rootHeight * maxPanelHeightRatio).rounded()
        return max(maxPanelHeight - basePanelHeight, minExpandedContentHeight)
    }

    /// 드래그 도중(`ACTION_MOVE`, 아직 손을 떼지 않음) 콘텐츠 높이를 [0, 최대] 로만
    /// 묶는다 — `minExpandedContentHeight` 보다 작아지는 것을 허용한다. 정본은
    /// 안드로이드 `bindTimelineDragHandle` 의 `ACTION_MOVE` 갈래(:942)
    /// `(startContentHeight - deltaY.roundToInt()).coerceIn(0, maxTimelineContentHeight(...))`.
    static func clampDuringDrag(contentHeight: CGFloat, basePanelHeight: CGFloat, rootHeight: CGFloat) -> CGFloat {
        let maxHeight = maxContentHeight(basePanelHeight: basePanelHeight, rootHeight: rootHeight)
        return min(max(contentHeight, 0), maxHeight)
    }

    /// 손을 뗐을 때(`ACTION_UP`/`ACTION_CANCEL`) 콘텐츠 높이를 어디에 "안착"시킬지.
    /// 정본은 안드로이드 `settleTimelineDrag`(:968).
    ///
    /// - `dragCollapseThreshold`(56) 미만이면 0(완전히 접힘).
    /// - 그 외에는 [`minExpandedContentHeight`(96), 최대] 로 다시 한 번 묶는다 — 56과
    ///   96 사이에서 손을 떼면 "접히지 않고 96으로" 튀어 오른다(안드로이드
    ///   `coerceIn(MIN_EXPANDED_CONTENT_HEIGHT_DP, maxHeight)` 와 같다).
    static func settle(contentHeight: CGFloat, basePanelHeight: CGFloat, rootHeight: CGFloat) -> CGFloat {
        guard contentHeight >= dragCollapseThreshold else { return 0 }
        let maxHeight = maxContentHeight(basePanelHeight: basePanelHeight, rootHeight: rootHeight)
        return min(max(contentHeight, minExpandedContentHeight), maxHeight)
    }

    /// 손잡이에서 손을 뗐을 때 할 일.
    enum HandleRelease: Equatable {
        /// 실제로 끌었다 — 지금 높이를 [settle(contentHeight:basePanelHeight:rootHeight:)] 로 안착시킨다.
        case settle
        /// 끌기 문턱을 넘지 못한 채 뗐다(탭) — 접기/펼치기를 뒤집는다.
        case toggle
    }

    /// 통합 검토 M1: 손을 뗐을 때의 탭/드래그 분기를 화면 없이 못박는다. 정본은
    /// 안드로이드 `bindTimelineDragHandle` 의 `ACTION_UP` 갈래 — `dragging` 이면
    /// `settleTimelineDrag`, 아니면 `performClick()`. SwiftUI 는 `DragGesture` 의
    /// `onEnded` 를 문턱 밑의 순수 탭에도 부르므로(Task 6 이 실제로 밟은 함정),
    /// 이 분기가 틀리면 접힌 채 탭해도 반응이 없다.
    static func release(isDragging: Bool) -> HandleRelease {
        isDragging ? .settle : .toggle
    }

    /// 접기/펼치기 토글 버튼을 눌렀을 때의 목표 콘텐츠 높이. 정본은 안드로이드
    /// `renderTimelinePanel`(:876) — 펼쳐진 상태면 `lastExpandedTimelineHeight` 를
    /// (그 순간의 최대 높이로) 다시 한 번 클램프하고, 접힌 상태면 0이다.
    static func toggledContentHeight(
        expanded: Bool, lastExpandedHeight: CGFloat, basePanelHeight: CGFloat, rootHeight: CGFloat
    ) -> CGFloat {
        guard expanded else { return 0 }
        return min(lastExpandedHeight, maxContentHeight(basePanelHeight: basePanelHeight, rootHeight: rootHeight))
    }
}
