import Foundation

/// 이동 구간(MOVE)들의 시간 범위를 받아, **하루의 모든 시각이 정확히 한 창에
/// 들어가도록** 각 구간의 창을 넓힌다.
///
/// 왜 필요한가: 지도의 경로선은 이동 카드 하나에 선 하나를 붙이려고 MOVE 구간의
/// 시간 창으로 점을 나눠 그린다. 그런데 창을 구간의 startAt..endAt 그대로 쓰면
/// **그 사이에 있는 점이 어느 창에도 안 들어가 지도에서 그냥 사라진다** — 머무름
/// 기준점, 활동 인식이 늦게 붙은 출발 직후, 업로드 시점과 구간 계산의 미세한
/// 어긋남이 전부 그 틈에 떨어진다. 아이 폰에는 다 쌓여 있는데 부모 지도에서만
/// 중간이 삭제된 것처럼 보였던 원인이다.
///
/// 나누는 법: 이웃한 두 구간 사이 공백(=머무름)의 **한가운데**에서 가른다. 머무름
/// 앞 절반의 점은 앞 이동선에, 뒤 절반은 뒤 이동선에 붙어 선이 머무른 곳까지
/// 이어진다. 첫 구간의 창은 하루 시작까지, 마지막 구간의 창은 하루 끝까지 연다 —
/// 마지막 이동 뒤에 들어온 최신 점이 버려지지 않는 것이 특히 중요하다(부모가
/// 제일 궁금한 것이 바로 그 최신 구간이다).
///
/// 정본은 안드로이드 `logic/RouteWindows.kt` 다.
///
/// ## 끝 포함/제외 경계를 옮긴 방법
///
/// 코틀린의 `LongRange` 는 끝을 포함한다(`a..b` 는 `b` 도 담는다). 스위프트의
/// `Range<Int64>` 는 끝을 항상 배제한다. 이 포팅에서는 "그 구간에 담기는 마지막
/// 밀리초"라는 뜻을 그대로 지키기로 하고, 입력과 출력 모두 `lowerBound..<(마지막
/// 순간 + 1)` 형태로 쓴다 — 즉 `upperBound` 는 언제나 "마지막으로 포함되는 순간 +
/// 1"이다. 이렇게 하면 `.last`(코틀린) 는 `.upperBound - 1`(스위프트)로,
/// `lo..maxOf(lo, hi)`(코틀린, 포함형) 는 `lo..<(max(lo, hi) + 1)`(스위프트,
/// 배제형)로 기계적으로 옮겨진다.
///
/// 딱 하나 못 옮기는 값이 있다: 마지막 창의 위쪽 끝은 코틀린에서 `Long.MAX_VALUE`
/// **포함**인데, 배제형인 `Range<Int64>` 는 그보다 큰 값이 없어 "Int64.max 포함"을
/// 나타낼 수 없다(`+1` 하면 오버플로). 그래서 이 한 경우만 `upperBound` 를
/// `Int64.max` 자체로 못박는다 — 결과적으로 그 순간 하나만 "포함"에서 "제외"로
/// 바뀐다. 실제 값은 epoch 밀리초라 이 경계 근처에 올 일이 없으므로(±2.9억 년)
/// 무해하다.
enum RouteWindows {

    /// `moves` 는 시작 시각 기준 정렬을 요구하지 않는다 — 여기서 정렬한다.
    /// 돌려주는 목록은 정렬된 구간 순서와 같은 순서다. 겹치는 입력이 와도(비정상
    /// 데이터) 창끼리는 겹치지 않게 잘라, 한 점이 두 선에 이중으로 그려지는 일은 없다.
    static func partition(moves: [Range<Int64>]) -> [Range<Int64>] {
        guard !moves.isEmpty else { return [] }
        // `sorted(by:)` 는 안정 정렬을 보장하지 않는다(코틀린 `sortedBy` 는 보장한다).
        // 겹치는 입력(비정상 데이터)은 lowerBound 가 같을 수 있으므로, 원래 순서를
        // 인덱스로 함께 정렬해 동률일 때도 입력 순서가 그대로 유지되도록 계약으로 못박는다.
        let sorted = moves
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.lowerBound != rhs.element.lowerBound
                    ? lhs.element.lowerBound < rhs.element.lowerBound
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        return sorted.indices.map { index in
            let lo: Int64
            if index == sorted.startIndex {
                lo = Int64.min
            } else {
                lo = midpoint(sorted[index - 1].upperBound - 1, sorted[index].lowerBound)
            }
            let hi: Int64
            if index == sorted.index(before: sorted.endIndex) {
                hi = Int64.max
            } else {
                hi = midpoint(sorted[index].upperBound - 1, sorted[index + 1].lowerBound) - 1
            }
            let closedHi = max(lo, hi)
            // Int64.max 는 배제형 upperBound 로 "그 순간까지 포함"을 못 나타내므로
            // (더 큰 값이 없다) +1 하지 않고 그대로 못박는다. 위 문서 참고.
            let upperBound = closedHi == Int64.max ? Int64.max : closedHi + 1
            return lo..<upperBound
        }
    }

    /// epoch 밀리초끼리의 중간값. 합이 Int64 를 넘칠 일은 없지만(±2.9e11년) 습관대로
    /// 안전하게 — a+b 를 직접 더하지 않고 나눠서 더한다.
    private static func midpoint(_ a: Int64, _ b: Int64) -> Int64 {
        a / 2 + b / 2 + (a % 2 + b % 2) / 2
    }
}
