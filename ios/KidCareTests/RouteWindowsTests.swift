import Testing
@testable import KidCare

/// 정본은 안드로이드 `logic/RouteWindowsTest.kt` 다. 케이스 하나하나를 같은 뜻으로 옮긴다.
///
/// 코틀린의 `LongRange` 는 끝을 포함하고(`a..b`), 스위프트의 `Range<Int64>` 는 끝을
/// 포함하지 않는다(`a..<b`). 여기서는 "구간이 담는 마지막 밀리초가 `b`" 라는 뜻을
/// 그대로 지키기로 하고, 그걸 `a..<(b+1)` 로 옮긴다 — 즉 스위프트 쪽 `upperBound`
/// 는 항상 "그 구간에 담기는 마지막 순간 + 1" 이다. 코틀린 테스트의 `1_000L..2_000L`
/// 은 그래서 `1_000..<2_001` 이 된다.
struct RouteWindowsTests {

    @Test("구간이 없으면 창도 없다")
    func 구간이_없으면_창도_없다() {
        #expect(RouteWindows.partition(moves: []).isEmpty)
    }

    @Test("구간 하나면 하루 전체가 그 창이다")
    func 구간_하나면_하루_전체가_그_창이다() {
        let windows = RouteWindows.partition(moves: [1_000..<2_001])
        #expect(windows == [Int64.min..<Int64.max])
    }

    @Test("두 구간 사이 공백은 한가운데에서 갈린다")
    func 두_구간_사이_공백은_한가운데에서_갈린다() {
        // 이동 1000~2000, 머무름 2000~6000, 이동 6000~9000 → 경계는 4000.
        let windows = RouteWindows.partition(moves: [1_000..<2_001, 6_000..<9_001])
        #expect(windows[0] == Int64.min..<4_000)
        #expect(windows[1] == 4_000..<Int64.max)
    }

    @Test("모든 시각이 정확히 한 창에 들어간다")
    func 모든_시각이_정확히_한_창에_들어간다() {
        let windows = RouteWindows.partition(
            moves: [1_000..<2_001, 6_000..<9_001, 20_000..<30_001]
        )
        // 머무름 기준점(3500), 마지막 이동 뒤의 최신 점(99999)까지 전부 어딘가에 속한다.
        for at: Int64 in [0, 1_500, 3_500, 4_100, 15_000, 99_999] {
            #expect(windows.count { $0.contains(at) } == 1, "at=\(at)")
        }
    }

    @Test("정렬 안 된 입력도 시작 시각 순으로 창을 돌려준다")
    func 정렬_안_된_입력도_시작_시각_순으로_창을_돌려준다() {
        let windows = RouteWindows.partition(moves: [6_000..<9_001, 1_000..<2_001])
        #expect(windows[0].lowerBound < windows[1].lowerBound)
    }

    // MARK: - 끝 포함/제외 경계 못박기 (코틀린엔 없는, 이 포팅 고유의 회귀 테스트)

    @Test("공백 경계 바로 앞뒤 밀리초가 각각 다른 창에 붙는다")
    func 공백_경계_바로_앞뒤_밀리초가_각각_다른_창에_붙는다() {
        // midpoint(2000, 6000) = 4000. 3999는 앞 창, 4000은 뒤 창 — 겹치지도, 비지도 않는다.
        let windows = RouteWindows.partition(moves: [1_000..<2_001, 6_000..<9_001])
        #expect(windows[0].contains(3_999))
        #expect(!windows[0].contains(4_000))
        #expect(windows[1].contains(4_000))
        #expect(!windows[1].contains(3_999))
    }

    @Test("마지막 창은 Int64.max 바로 앞까지 이어지고 넘치지 않는다")
    func 마지막_창은_Int64_max_바로_앞까지_이어지고_넘치지_않는다() {
        // 코틀린은 마지막 창의 위쪽 끝을 Long.MAX_VALUE(포함)로 연다. Range<Int64> 는
        // 끝을 항상 배제하므로, 배제형으로는 Int64.max 자체를 나타낼 더 큰 값이 없다 —
        // 그래서 upperBound 는 Int64.max 로 못 박고(오버플로 없이), 그 한 순간만은
        // "포함"에서 "제외"로 바뀐다. 실제 시각은 epoch 밀리초라 이 경계 근처에 올 일이
        // 없으므로 무해하지만, 표현의 한계를 테스트로 남겨 둔다.
        let windows = RouteWindows.partition(moves: [1_000..<2_001])
        #expect(windows[0].upperBound == Int64.max)
        #expect(windows[0].contains(Int64.max - 1))
        #expect(!windows[0].contains(Int64.max))
    }

    @Test("홀수 합의 중간값도 정수 나눗셈으로 안정적으로 갈린다")
    func 홀수_합의_중간값도_정수_나눗셈으로_안정적으로_갈린다() {
        // 이동 1000~2001(마지막 순간 2001), 이동 6001~9000(시작 6001) →
        // midpoint(2001, 6001) = 1000 + 3000 + (1+1)/2 = 4001.
        let windows = RouteWindows.partition(moves: [1_000..<2_002, 6_001..<9_001])
        #expect(windows[0] == Int64.min..<4_001)
        #expect(windows[1] == 4_001..<Int64.max)
    }
}
