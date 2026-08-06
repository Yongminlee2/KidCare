package com.kidcare.family.logic

enum class SegmentType { STAY, MOVE }

/**
 * 하루의 한 토막.
 *
 * STAY 는 한 곳에 머문 구간이고 [lat]/[lng] 는 그 구간 점들의 평균 좌표다.
 * MOVE 는 이동한 구간이고 [lat]/[lng] 는 도착 지점, [distanceMeters] 는 실제 이동 거리다.
 */
data class Segment(
    val type: SegmentType,
    val startAt: Long,
    val endAt: Long,
    val lat: Double,
    val lng: Double,
    val distanceMeters: Double,
    val pointCount: Int,
)

/**
 * 위치 점 목록을 머무름/이동 구간으로 묶는다.
 *
 * 판정 기준은 설계서 §4.2 다:
 *   - 반경 100m 안에 5분 이상 있으면 머무름
 *   - 반경을 벗어난 점이 **연속 2개** 나와야 머무름이 끝난다. 1개는 GPS 가 튄 것으로 본다.
 *   - 5분을 못 채운 정지는 이동에 흡수한다 (신호 대기 같은 것)
 *
 * "연속 2개" 규칙이 핵심이다. 실내에서는 좌표가 수십 미터씩 흔들리고 가끔 수백 미터를
 * 튀는데, 한 점만 보고 머무름을 끊으면 학교에 있는 6시간이 수십 개 구간으로 쪼개진다.
 *
 * 안드로이드 API 에 의존하지 않는다. JVM 단위 테스트 대상.
 */
object SegmentBuilder {

    /** 이 반경 안에 있으면 같은 자리로 본다. */
    const val STAY_RADIUS_METERS: Double = 100.0

    /** 이 시간 이상 머물러야 머무름으로 인정한다. */
    const val MIN_STAY_MILLIS: Long = 5 * 60 * 1000L

    /** 반경을 벗어난 점이 이만큼 연속돼야 머무름을 끝낸다. */
    const val EXIT_CONFIRM_POINTS: Int = 2

    fun build(points: List<Fix>): List<Segment> {
        // Firestore 쿼리 결과 순서를 믿지 않는다. 오차가 큰 점은 계산 자체에서 뺀다.
        val sorted = points
            .filter { it.accuracy <= LocationFilter.MAX_ACCURACY_METERS }
            .sortedBy { it.at }
        if (sorted.size < 2) return emptyList()

        val stays = findStayRanges(sorted)
        return assemble(sorted, stays)
    }

    /** 머무름으로 인정된 구간의 인덱스 범위들. 서로 겹치지 않고 앞에서부터 정렬돼 있다. */
    private fun findStayRanges(points: List<Fix>): List<IntRange> {
        val ranges = mutableListOf<IntRange>()
        var start = 0
        while (start < points.size) {
            val anchor = points[start]
            var lastInside = start
            var outsideRun = 0
            var cursor = start
            while (cursor + 1 < points.size) {
                cursor++
                if (LocationFilter.distanceMeters(anchor, points[cursor]) <= STAY_RADIUS_METERS) {
                    lastInside = cursor
                    outsideRun = 0
                } else {
                    outsideRun++
                    if (outsideRun >= EXIT_CONFIRM_POINTS) break
                }
            }
            val lasted = points[lastInside].at - anchor.at
            if (lastInside > start && lasted >= MIN_STAY_MILLIS) {
                ranges += start..lastInside
                start = lastInside + 1
            } else {
                // 머무름이 아니면 한 칸만 밀고 다시 본다. 하루 점이 수백 개라 이 정도면 충분하다.
                start++
            }
        }
        return ranges
    }

    /** 머무름 범위 사이를 이동 구간으로 채운다. 이동은 앞뒤 머무름의 끝점을 공유해 선이 끊기지 않게 한다. */
    private fun assemble(points: List<Fix>, stays: List<IntRange>): List<Segment> {
        val result = mutableListOf<Segment>()
        var cursor = 0
        for (stay in stays) {
            if (stay.first > cursor) addMove(points, cursor, stay.first, result)
            result += staySegment(points, stay)
            cursor = stay.last
        }
        if (cursor < points.lastIndex) addMove(points, cursor, points.lastIndex, result)
        return result
    }

    private fun addMove(points: List<Fix>, from: Int, to: Int, into: MutableList<Segment>) {
        if (to <= from) return
        var distance = 0.0
        for (i in from until to) distance += LocationFilter.distanceMeters(points[i], points[i + 1])
        into += Segment(
            type = SegmentType.MOVE,
            startAt = points[from].at,
            endAt = points[to].at,
            lat = points[to].lat,
            lng = points[to].lng,
            distanceMeters = distance,
            pointCount = to - from + 1,
        )
    }

    private fun staySegment(points: List<Fix>, range: IntRange): Segment {
        val slice = points.slice(range)
        return Segment(
            type = SegmentType.STAY,
            startAt = slice.first().at,
            endAt = slice.last().at,
            lat = slice.sumOf { it.lat } / slice.size,
            lng = slice.sumOf { it.lng } / slice.size,
            distanceMeters = 0.0,
            pointCount = slice.size,
        )
    }
}
