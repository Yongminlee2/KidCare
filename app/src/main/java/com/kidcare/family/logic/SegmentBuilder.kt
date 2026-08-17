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
    /**
     * **이름을 물어볼 좌표.** 역지오코딩([com.kidcare.family.child.PlaceNamer])에만 쓴다.
     *
     * [lat]/[lng] 와 따로 두는 이유: 저 둘은 지도에 찍고 선을 잇는 좌표라 의미를 바꾸면
     * 화면·타임라인·경로선이 전부 따라 바뀐다(그 계약은 건드리지 않는다). 반면 이름은
     * 좌표 하나를 건물 이름으로 바꾸는 일이라 **오차에 훨씬 민감하다** — 단순 평균은
     * 도착 순간의 나쁜 fix 한 개를 그대로 끌어안아서, 머무름 전체가 옆 건물 이름을
     * 달 수 있다. 특히 점이 2~3개뿐인 짧은 머무름에서는 나쁜 점 하나가 평균의 절반이다.
     *
     * 그래서 이 좌표는 **오차로 가중한 평균**이다(가중치 = 1/오차²). 오차를 표준편차로
     * 보면 이게 통계적으로 맞는 결합 방식이고, 정확한 점이 이름을 결정하게 된다.
     * MOVE 구간에서는 [lat]/[lng] 와 같은 값이다 — 이동 구간에는 애초에 이름을 안 붙인다.
     */
    val nameLat: Double,
    val nameLng: Double,
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

    /**
     * 이 반경 안에 있으면 같은 자리로 본다. 100m 에서 40m 로 내렸다.
     *
     * **100m 는 아이의 하루를 한 덩어리로 만들었다.** 집·놀이터·학원이 모두 반경
     * 100m 안에 있는 생활권이면 그 전부가 머무름 **하나**로 묶인다. 그러면 이동(MOVE)
     * 구간이 아예 안 생기고, 지도의 경로선은 MOVE 구간에만 그려지므로 **선이 한 줄도
     * 안 나온다.** 부모가 본 "집 앞 놀이터에 다녀왔는데 아무 기록이 없다"가 이것이다.
     *
     * 40m 는 걸어서 1분 거리(약 70m)를 서로 다른 곳으로 가른다. 실내 흔들림으로
     * 머무름이 쪼개지는 것은 [EXIT_CONFIRM_POINTS] 가 계속 막는다 — 반경을 벗어난 점이
     * **연속 2개** 나와야 끝나므로, 한 번 튄 좌표로는 안 끊긴다.
     */
    const val STAY_RADIUS_METERS: Double = 40.0

    /** 이 시간 이상 머물러야 머무름으로 인정한다. */
    const val MIN_STAY_MILLIS: Long = 5 * 60 * 1000L

    /** 반경을 벗어난 점이 이만큼 연속돼야 머무름을 끝낸다. */
    const val EXIT_CONFIRM_POINTS: Int = 2

    /**
     * 가중 평균에서 오차를 이 값보다 작게 치지 않는다.
     *
     * 두 가지를 막는다. (1) 0 으로 나누기 — `PointDoc.accuracy` 는 옛 문서에서 0 으로
     * 읽힐 수 있다. (2) 그 0 이 "완벽한 점"으로 해석돼 가중치를 독점하는 것 — 0 은
     * 완벽하다는 뜻이 아니라 **모른다**는 뜻이다. 소비자용 GPS 가 실제로 5m 보다
     * 정확해지는 일은 없으므로, 그 아래는 전부 5m 로 친다.
     */
    const val MIN_WEIGHT_ACCURACY_METERS: Double = 5.0

    fun build(points: List<Fix>): List<Segment> {
        // Firestore 쿼리 결과 순서를 믿지 않는다. 오차가 큰 점은 계산 자체에서 뺀다.
        //
        // 문턱이 LocationFilter.MAX_ACCURACY_METERS(평소 50m)가 아니라 완화 문턱인
        // 이유: 그 완화 문턱까지는 LocationFilter 가 **일부러** 올린 점이다(오래
        // 아무것도 못 올렸을 때의 UPLOAD_STALE_FALLBACK). 여기서 50m 로 자르면
        // 신호가 나빠 간신히 건진 그 점들이 구간 계산에서 통째로 빠져 — 지도 마커는
        // 움직이는데 타임라인만 비는, 원인을 알 수 없는 상태가 된다. 이 필터가 막으려는
        // 것은 '올린 적도 없는 쓰레기 값이 다른 경로로 섞여 들어오는 것'이지
        // '거칠지만 우리가 승인한 점'이 아니다.
        val sorted = points
            .filter { it.accuracy <= LocationFilter.FALLBACK_MAX_ACCURACY_METERS }
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
            // 이동 구간에는 이름을 안 붙이므로(SegmentUploader) 가중 평균을 낼 이유가
            // 없다. 도착 지점을 그대로 둔다.
            nameLat = points[to].lat,
            nameLng = points[to].lng,
        )
    }

    private fun staySegment(points: List<Fix>, range: IntRange): Segment {
        val slice = points.slice(range)
        // 가중치는 1/오차². 오차를 표준편차로 보면 역분산 가중이 되어, 정확한 점이
        // 이름을 결정한다. 합이 0 이 되는 경우는 없다 — 아래 floor 때문에 모든
        // 가중치가 양수다.
        val weights = slice.map { fix ->
            val a = maxOf(fix.accuracy.toDouble(), MIN_WEIGHT_ACCURACY_METERS)
            1.0 / (a * a)
        }
        val weightSum = weights.sum()
        return Segment(
            type = SegmentType.STAY,
            startAt = slice.first().at,
            endAt = slice.last().at,
            lat = slice.sumOf { it.lat } / slice.size,
            lng = slice.sumOf { it.lng } / slice.size,
            distanceMeters = 0.0,
            pointCount = slice.size,
            nameLat = slice.indices.sumOf { slice[it].lat * weights[it] } / weightSum,
            nameLng = slice.indices.sumOf { slice[it].lng * weights[it] } / weightSum,
        )
    }
}
