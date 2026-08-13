package com.kidcare.family.logic

import kotlin.math.max

/** 지도에 경로를 그리기 전에 GPS 흔들림과 위치 공백을 정리한다. */
object RoutePathRefiner {

    /** 이보다 거친 경로점은 선에 사용하지 않는다. 옛 기록과의 호환 상한이다. */
    const val MAX_DISPLAY_ACCURACY_METERS = 50f

    /** 이 시간 동안 위치가 없고 멀리 이동했다면 두 점을 추측으로 직선 연결하지 않는다. */
    const val GAP_BREAK_MILLIS = 10 * 60_000L
    const val GAP_BREAK_DISTANCE_METERS = 150.0

    private const val UNKNOWN_ACCURACY_METERS = 30.0
    private const val MIN_ACCURACY_METERS = 5.0
    private const val BASE_PROCESS_SPEED_MPS = 4.0
    private const val PRECISE_ENDPOINT_METERS = 12f
    private const val SPIKE_MAX_SPAN_MILLIS = 20_000L
    private const val SPIKE_MIN_ARM_METERS = 25.0
    private const val SPIKE_MAX_BRIDGE_METERS = 15.0
    private const val SPIKE_MIN_DETOUR_RATIO = 4.0

    data class Leg(val points: List<Fix>)

    /**
     * 정확도가 좋은 점은 거의 그대로 두고, 오차가 큰 점일수록 앞선 위치와 더 강하게
     * 합친다. 이동 속도가 빠를 때는 필터가 즉시 따라가도록 과정 잡음을 높여 자동차나
     * 급회전 경로가 둥글게 잘려 나가지 않게 한다.
     */
    fun refine(points: List<Fix>): List<Leg> {
        val sorted = points
            .asSequence()
            .filter(::isUsable)
            .sortedBy { it.at }
            .toList()
        if (sorted.isEmpty()) return emptyList()
        val cleaned = removeIsolatedSpikes(sorted)

        val rawLegs = mutableListOf<MutableList<Fix>>()
        var current = mutableListOf<Fix>()
        var previous: Fix? = null

        cleaned.forEach { candidate ->
            val before = previous
            if (before != null && shouldBreak(before, candidate)) {
                if (current.isNotEmpty()) rawLegs += current
                current = mutableListOf()
            }
            // 같은 시각의 중복 콜백은 선을 두껍게 만들 뿐 정보가 없다.
            if (before == null || candidate.at > before.at) current += candidate
            previous = candidate
        }
        if (current.isNotEmpty()) rawLegs += current

        return rawLegs.map { raw -> Leg(smooth(raw)) }
    }

    /**
     * A→B→C 중 B만 멀리 튀었다가 20초 안에 A 근처로 돌아오는 전형적인 GPS 반사
     * 오차를 제거한다. 정상적인 직선·코너는 A-C 거리도 함께 커지므로 이 조건에
     * 걸리지 않는다. 보행과 자전거의 짧은 실제 왕복을 지우지 않도록 네 조건을 모두
     * 만족하는 아주 뚜렷한 단일 스파이크만 대상으로 한다.
     */
    private fun removeIsolatedSpikes(points: List<Fix>): List<Fix> {
        if (points.size < 3) return points
        val result = ArrayList<Fix>(points.size)
        result += points.first()
        for (index in 1 until points.lastIndex) {
            val previous = result.last()
            val candidate = points[index]
            val next = points[index + 1]
            if (!isIsolatedSpike(previous, candidate, next)) result += candidate
        }
        result += points.last()
        return result
    }

    private fun isIsolatedSpike(previous: Fix, candidate: Fix, next: Fix): Boolean {
        val span = next.at - previous.at
        if (span <= 0L || span > SPIKE_MAX_SPAN_MILLIS) return false
        val firstArm = LocationFilter.distanceMeters(previous, candidate)
        val secondArm = LocationFilter.distanceMeters(candidate, next)
        if (firstArm < SPIKE_MIN_ARM_METERS || secondArm < SPIKE_MIN_ARM_METERS) return false
        val bridge = LocationFilter.distanceMeters(previous, next)
        if (bridge > SPIKE_MAX_BRIDGE_METERS) return false
        val detourRatio = (firstArm + secondArm) / bridge.coerceAtLeast(1.0)
        return detourRatio >= SPIKE_MIN_DETOUR_RATIO
    }

    private fun isUsable(fix: Fix): Boolean {
        if (!fix.lat.isFinite() || !fix.lng.isFinite() || !fix.accuracy.isFinite()) return false
        if (fix.lat !in -90.0..90.0 || fix.lng !in -180.0..180.0 || fix.at <= 0L) return false
        // accuracy=0 은 정확도 필드가 없던 옛 기록이다. 버리지 않고 '모름'으로 다룬다.
        return fix.accuracy <= 0f || fix.accuracy <= MAX_DISPLAY_ACCURACY_METERS
    }

    private fun shouldBreak(previous: Fix, candidate: Fix): Boolean {
        val elapsed = candidate.at - previous.at
        if (elapsed <= 0L) return false
        val distance = LocationFilter.distanceMeters(previous, candidate)
        val impliedSpeed = distance / (elapsed / 1_000.0)
        if (impliedSpeed > LocationFilter.MAX_SPEED_MPS) return true
        return elapsed > GAP_BREAK_MILLIS && distance > GAP_BREAK_DISTANCE_METERS
    }

    private fun smooth(raw: List<Fix>): List<Fix> {
        if (raw.size < 2) return raw
        val filter = AdaptiveLocationFilter()
        val smoothed = raw.map(filter::add).toMutableList()
        // 출발점은 경로의 기준이므로 그대로 둔다. 마지막 점도 충분히 정확하면 부모가
        // 보는 현재 위치와 경로 끝이 어긋나지 않도록 원시 좌표를 유지한다.
        smoothed[0] = raw.first()
        if (raw.last().accuracy > 0f && raw.last().accuracy <= PRECISE_ENDPOINT_METERS) {
            smoothed[smoothed.lastIndex] = raw.last()
        }
        return smoothed
    }

    private class AdaptiveLocationFilter {
        private var lat = 0.0
        private var lng = 0.0
        private var variance = -1.0
        private var at = 0L

        fun add(fix: Fix): Fix {
            val accuracy = normalizedAccuracy(fix)
            if (variance < 0.0) {
                lat = fix.lat
                lng = fix.lng
                variance = accuracy * accuracy
                at = fix.at
                return fix
            }

            val elapsedSeconds = (fix.at - at).coerceAtLeast(0L) / 1_000.0
            val processSpeed = max(BASE_PROCESS_SPEED_MPS, fix.speed.toDouble().coerceAtLeast(0.0))
            variance += elapsedSeconds * processSpeed * processSpeed

            val measurementVariance = accuracy * accuracy
            val gain = variance / (variance + measurementVariance)
            lat += gain * (fix.lat - lat)
            lng += gain * (fix.lng - lng)
            variance *= 1.0 - gain
            at = fix.at
            return fix.copy(lat = lat, lng = lng)
        }

        private fun normalizedAccuracy(fix: Fix): Double =
            if (fix.accuracy > 0f) max(MIN_ACCURACY_METERS, fix.accuracy.toDouble())
            else UNKNOWN_ACCURACY_METERS
    }
}
