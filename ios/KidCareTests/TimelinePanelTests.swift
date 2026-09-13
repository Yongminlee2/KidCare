import Testing
@testable import KidCare

/// `TimelinePanel` 의 순수 수학만 본다 — 화면·제스처 없이 경계값(56/96/340/0.72)을
/// 못박는다. 정본은 안드로이드 `MapTimelineFragment.settleTimelineDrag`(:968)·
/// `maxTimelineContentHeight`(:1003)와 그 동반 객체 상수(:1316-1329).
struct TimelinePanelTests {

    // MARK: - 상수 자체가 브리프 값과 같은지(:1324-1329, dp → pt 그대로)

    @Test("상수가 안드로이드 dp 값과 정확히 같다")
    func 상수가_안드로이드와_같다() {
        #expect(TimelinePanel.defaultContentHeight == 174)
        #expect(TimelinePanel.maxContentHeightFallback == 340)
        #expect(TimelinePanel.minExpandedContentHeight == 96)
        #expect(TimelinePanel.dragCollapseThreshold == 56)
        #expect(TimelinePanel.collapsedPanelHeight == 136)
        #expect(TimelinePanel.maxPanelHeightRatio == 0.72)
    }

    // MARK: - settle: 56 문턱

    @Test("56 미만이면 완전히 접힌다(0)")
    func 문턱_미만이면_접힌다() {
        #expect(TimelinePanel.settle(contentHeight: 55, basePanelHeight: 136, rootHeight: 800) == 0)
        #expect(TimelinePanel.settle(contentHeight: 0, basePanelHeight: 136, rootHeight: 800) == 0)
    }

    @Test("56은 이미 문턱을 넘었다 — 접히지 않고 최소 펼침 높이(96)로 튀어 오른다")
    func 문턱_경계는_접히지_않는다() {
        #expect(TimelinePanel.settle(contentHeight: 56, basePanelHeight: 136, rootHeight: 800) == 96)
    }

    @Test("56~96 사이에서 손을 떼면 96으로 밀어 올린다")
    func 문턱과_최소_사이는_최소로_밀린다() {
        #expect(TimelinePanel.settle(contentHeight: 70, basePanelHeight: 136, rootHeight: 800) == 96)
        #expect(TimelinePanel.settle(contentHeight: 95, basePanelHeight: 136, rootHeight: 800) == 96)
    }

    @Test("96은 이미 최소 펼침 높이다 — 그대로 안착한다")
    func 최소_경계는_그대로() {
        #expect(TimelinePanel.settle(contentHeight: 96, basePanelHeight: 136, rootHeight: 800) == 96)
    }

    @Test("최소와 최대 사이는 그대로 안착한다")
    func 범위_안이면_그대로() {
        #expect(TimelinePanel.settle(contentHeight: 200, basePanelHeight: 136, rootHeight: 800) == 200)
    }

    @Test("최대를 넘으면 화면 비율로 정한 최대로 눌린다")
    func 최대를_넘으면_눌린다() {
        // rootHeight 800, basePanelHeight 136 → maxPanelHeight = round(800*0.72) = 576
        // → maxContentHeight = 576 - 136 = 440.
        #expect(TimelinePanel.settle(contentHeight: 1000, basePanelHeight: 136, rootHeight: 800) == 440)
        #expect(TimelinePanel.settle(contentHeight: 440, basePanelHeight: 136, rootHeight: 800) == 440)
        #expect(TimelinePanel.settle(contentHeight: 439, basePanelHeight: 136, rootHeight: 800) == 439)
    }

    @Test("화면이 아주 작으면 화면 비율 상한이 최소 펼침 높이 밑으로 안 내려간다")
    func 작은_화면에서도_최소는_지킨다() {
        // rootHeight 150, basePanelHeight 136 → maxPanelHeight = round(150*0.72) = 108
        // → 108 - 136 = -28 → coerceAtLeast(96) = 96.
        #expect(TimelinePanel.maxContentHeight(basePanelHeight: 136, rootHeight: 150) == 96)
        #expect(TimelinePanel.settle(contentHeight: 300, basePanelHeight: 136, rootHeight: 150) == 96)
    }

    // MARK: - maxContentHeight: rootHeight 를 아직 모를 때(첫 레이아웃 패스 전)

    @Test("rootHeight 를 모르면(0 이하) 안드로이드 폴백 상수(340)로 물러난다")
    func 루트_높이_모르면_폴백() {
        #expect(TimelinePanel.maxContentHeight(basePanelHeight: 136, rootHeight: 0) == 340)
        #expect(TimelinePanel.maxContentHeight(basePanelHeight: 136, rootHeight: -1) == 340)
    }

    // MARK: - clampDuringDrag: 드래그 중에는 96 밑으로도 내려갈 수 있다(0까지)

    @Test("드래그 중에는 최소 펼침 높이보다 작아질 수 있다 — 접힘 판정은 settle 몫이다")
    func 드래그_중에는_최소_미만도_허용한다() {
        #expect(TimelinePanel.clampDuringDrag(contentHeight: 30, basePanelHeight: 136, rootHeight: 800) == 30)
        #expect(TimelinePanel.clampDuringDrag(contentHeight: 0, basePanelHeight: 136, rootHeight: 800) == 0)
    }

    @Test("드래그 중 손가락이 화면 밖으로 나가도 0과 최대 사이로 묶인다")
    func 드래그_중_범위를_벗어나면_묶인다() {
        #expect(TimelinePanel.clampDuringDrag(contentHeight: -500, basePanelHeight: 136, rootHeight: 800) == 0)
        #expect(TimelinePanel.clampDuringDrag(contentHeight: 5000, basePanelHeight: 136, rootHeight: 800) == 440)
    }

    // MARK: - toggledContentHeight: 토글 버튼

    @Test("토글로 접으면 콘텐츠 높이는 0이다")
    func 토글_접기() {
        #expect(TimelinePanel.toggledContentHeight(
            expanded: false, lastExpandedHeight: 250, basePanelHeight: 136, rootHeight: 800
        ) == 0)
    }

    @Test("토글로 펼치면 마지막 펼침 높이로 돌아간다")
    func 토글_펼치기() {
        #expect(TimelinePanel.toggledContentHeight(
            expanded: true, lastExpandedHeight: 250, basePanelHeight: 136, rootHeight: 800
        ) == 250)
    }

    @Test("마지막 펼침 높이가 지금 화면의 최대치보다 크면 그 최대치로 눌린다")
    func 토글_펼치기_최대로_눌린다() {
        #expect(TimelinePanel.toggledContentHeight(
            expanded: true, lastExpandedHeight: 5000, basePanelHeight: 136, rootHeight: 800
        ) == 440)
    }

    // MARK: - 통합 검토 M1: 손을 뗐을 때 탭/드래그 분기

    @Test("M1: 실제로 끌었으면 안착(settle), 문턱을 못 넘고 뗐으면(탭) 토글이다")
    func 손을_뗐을_때의_분기() {
        #expect(TimelinePanel.release(isDragging: true) == .settle)
        #expect(TimelinePanel.release(isDragging: false) == .toggle)
    }

    // MARK: - 통합 검토 M4: 앱 새 실행은 접힘으로 시작한다

    @Test("M4: 새 기억(앱을 새로 켠 것)은 접힘·기본 높이로 시작한다")
    @MainActor
    func 새_기억은_접힘으로_시작한다() {
        let store = TimelinePanelStore()
        #expect(store.isExpanded == false)
        #expect(store.contentHeight == TimelinePanel.defaultContentHeight)
    }
}
