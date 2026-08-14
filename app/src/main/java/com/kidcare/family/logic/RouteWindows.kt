package com.kidcare.family.logic

/**
 * 이동 구간(MOVE)들의 시간 범위를 받아, **하루의 모든 시각이 정확히 한 창에
 * 들어가도록** 각 구간의 창을 넓힌다.
 *
 * 왜 필요한가: 지도의 경로선은 이동 카드 하나에 선 하나를 붙이려고 MOVE 구간의
 * 시간 창으로 점을 나눠 그린다. 그런데 창을 구간의 startAt..endAt 그대로 쓰면
 * **그 사이에 있는 점이 어느 창에도 안 들어가 지도에서 그냥 사라진다** — 머무름
 * 기준점, 활동 인식이 늦게 붙은 출발 직후, 업로드 시점과 구간 계산의 미세한
 * 어긋남이 전부 그 틈에 떨어진다. 아이 폰에는 다 쌓여 있는데 부모 지도에서만
 * 중간이 삭제된 것처럼 보였던 원인이다.
 *
 * 나누는 법: 이웃한 두 구간 사이 공백(=머무름)의 **한가운데**에서 가른다. 머무름
 * 앞 절반의 점은 앞 이동선에, 뒤 절반은 뒤 이동선에 붙어 선이 머무른 곳까지
 * 이어진다. 첫 구간의 창은 하루 시작까지, 마지막 구간의 창은 하루 끝까지 연다 —
 * 마지막 이동 뒤에 들어온 최신 점이 버려지지 않는 것이 특히 중요하다(부모가
 * 제일 궁금한 것이 바로 그 최신 구간이다).
 */
object RouteWindows {

    /**
     * [moves] 는 시작 시각 기준 정렬을 요구하지 않는다 — 여기서 정렬한다.
     * 돌려주는 목록은 정렬된 구간 순서와 같은 순서다. 겹치는 입력이 와도(비정상
     * 데이터) 창끼리는 겹치지 않게 잘라, 한 점이 두 선에 이중으로 그려지는 일은 없다.
     */
    fun partition(moves: List<LongRange>): List<LongRange> {
        if (moves.isEmpty()) return emptyList()
        val sorted = moves.sortedBy { it.first }
        return sorted.mapIndexed { index, range ->
            val lo = if (index == 0) {
                Long.MIN_VALUE
            } else {
                midpoint(sorted[index - 1].last, range.first)
            }
            val hi = if (index == sorted.lastIndex) {
                Long.MAX_VALUE
            } else {
                midpoint(range.last, sorted[index + 1].first) - 1
            }
            lo..maxOf(lo, hi)
        }
    }

    /** epoch 밀리초끼리의 중간값. 합이 Long 을 넘칠 일은 없지만(±2.9e11년) 습관대로 안전하게. */
    private fun midpoint(a: Long, b: Long): Long = a / 2 + b / 2 + (a % 2 + b % 2) / 2
}
