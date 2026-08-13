package com.kidcare.family.logic

import kotlin.math.hypot
import kotlin.math.max

enum class AdaptiveMovementState { FAST_PROBE, SLOW_PROBE, MOVING }

data class AdaptiveMovementUpdate(
    val state: AdaptiveMovementState,
    /** 이동 확정 직전의 점들. 경로 시작 부분이 잘리지 않도록 확정 시 한 번만 돌려준다. */
    val promotionBuffer: List<Fix> = emptyList(),
)

/**
 * 활동 인식 결과를 바로 이동으로 믿지 않고 실제 좌표·속도 증거로 확인한다.
 *
 * 빠른 확인은 최대 30초만 유지하고, 이동 증거가 없으면 느린 확인으로 내려간다.
 * 실제 이동 중에도 60초간 오차 반경 안에 머물면 다시 느린 확인으로 돌아간다.
 */
class AdaptiveMovementDetector {

    private val samples = ArrayDeque<Fix>()
    private var fastProbeStartedAt: Long? = null
    var state: AdaptiveMovementState = AdaptiveMovementState.FAST_PROBE
        private set

    fun reset(fast: Boolean = true) {
        samples.clear()
        fastProbeStartedAt = null
        state = if (fast) AdaptiveMovementState.FAST_PROBE else AdaptiveMovementState.SLOW_PROBE
    }

    fun onFix(candidate: Fix): AdaptiveMovementUpdate {
        if (!hasValidCoordinatesAndTime(candidate)) return AdaptiveMovementUpdate(state)
        if (state == AdaptiveMovementState.FAST_PROBE && fastProbeStartedAt == null) {
            fastProbeStartedAt = candidate.at
        }
        if (!isUsable(candidate)) {
            val startedAt = fastProbeStartedAt
            if (
                state == AdaptiveMovementState.FAST_PROBE && startedAt != null &&
                candidate.at - startedAt >= FAST_PROBE_MILLIS
            ) {
                reset(fast = false)
            }
            return AdaptiveMovementUpdate(state)
        }
        val last = samples.lastOrNull()
        if (last != null && candidate.at <= last.at) return AdaptiveMovementUpdate(state)

        return when (state) {
            AdaptiveMovementState.FAST_PROBE -> onFastProbe(candidate)
            AdaptiveMovementState.SLOW_PROBE -> onSlowProbe(candidate)
            AdaptiveMovementState.MOVING -> onMoving(candidate)
        }
    }

    private fun onFastProbe(candidate: Fix): AdaptiveMovementUpdate {
        samples += candidate
        trimBefore(candidate.at - FAST_PROBE_MILLIS)

        if (hasConfirmedMovement()) {
            state = AdaptiveMovementState.MOVING
            fastProbeStartedAt = null
            return AdaptiveMovementUpdate(state, samples.toList())
        }

        val startedAt = fastProbeStartedAt
        if (startedAt != null && candidate.at - startedAt >= FAST_PROBE_MILLIS) {
            keepOnly(candidate)
            state = AdaptiveMovementState.SLOW_PROBE
            fastProbeStartedAt = null
        }
        return AdaptiveMovementUpdate(state)
    }

    private fun onSlowProbe(candidate: Fix): AdaptiveMovementUpdate {
        val previous = samples.lastOrNull()
        keepOnly(candidate)
        if (previous != null && hasMovementHint(previous, candidate)) {
            samples.clear()
            samples += previous
            samples += candidate
            state = AdaptiveMovementState.FAST_PROBE
            fastProbeStartedAt = candidate.at
        }
        return AdaptiveMovementUpdate(state)
    }

    private fun onMoving(candidate: Fix): AdaptiveMovementUpdate {
        samples += candidate
        trimBefore(candidate.at - STOP_CONFIRM_MILLIS)

        val first = samples.firstOrNull() ?: return AdaptiveMovementUpdate(state)
        if (candidate.at - first.at >= STOP_CONFIRM_MILLIS && looksStationary()) {
            keepOnly(candidate)
            state = AdaptiveMovementState.SLOW_PROBE
        }
        return AdaptiveMovementUpdate(state)
    }

    private fun hasConfirmedMovement(): Boolean {
        if (samples.size < MIN_CONFIRM_POINTS) return false
        val points = samples.toList()
        val first = points.first()
        val last = points.last()
        if (last.at - first.at < MIN_CONFIRM_MILLIS) return false

        val recentSpeedEvidence = points.takeLast(2).all(::hasReliableWalkingSpeed)
        val recentDistance = LocationFilter.distanceMeters(points[points.lastIndex - 1], last)
        if (recentSpeedEvidence && recentDistance >= MIN_SPEED_DISPLACEMENT_METERS) return true

        val threshold = max(
            MIN_NET_DISPLACEMENT_METERS,
            hypot(first.accuracy.toDouble(), last.accuracy.toDouble()) * NOISE_MULTIPLIER,
        )
        val penultimateDistance = LocationFilter.distanceMeters(first, points[points.lastIndex - 1])
        val netDistance = LocationFilter.distanceMeters(first, last)
        return penultimateDistance >= threshold * MIN_PROGRESS_RATIO && netDistance >= threshold
    }

    private fun hasMovementHint(previous: Fix, candidate: Fix): Boolean {
        val distance = LocationFilter.distanceMeters(previous, candidate)
        val elapsedSeconds = (candidate.at - previous.at) / 1_000.0
        if (elapsedSeconds <= 0.0 || distance / elapsedSeconds > LocationFilter.MAX_SPEED_MPS) {
            return false
        }
        if (hasReliableWalkingSpeed(candidate) && distance >= MIN_SPEED_DISPLACEMENT_METERS) {
            return true
        }
        val noise = max(
            SLOW_PROBE_MIN_DISPLACEMENT_METERS,
            hypot(previous.accuracy.toDouble(), candidate.accuracy.toDouble()) * NOISE_MULTIPLIER,
        )
        return distance >= noise
    }

    private fun looksStationary(): Boolean {
        val points = samples.toList()
        if (points.any(::hasReliableWalkingSpeed)) return false
        val first = points.first()
        val maxDistance = points.maxOf { LocationFilter.distanceMeters(first, it) }
        val maxAccuracy = points.maxOf { it.accuracy.toDouble() }
        return maxDistance <= max(STOP_RADIUS_METERS, maxAccuracy * NOISE_MULTIPLIER)
    }

    private fun hasReliableWalkingSpeed(fix: Fix): Boolean =
        fix.accuracy <= SPEED_TRUST_MAX_ACCURACY_METERS &&
            fix.speedAccuracy.isFinite() &&
            fix.speed - fix.speedAccuracy >= MIN_CONFIDENT_SPEED_MPS

    private fun isUsable(fix: Fix): Boolean =
        hasValidCoordinatesAndTime(fix) &&
            fix.accuracy.isFinite() && fix.accuracy in 0f..MAX_ACCURACY_METERS &&
            fix.speed <= LocationFilter.MAX_SPEED_MPS

    private fun hasValidCoordinatesAndTime(fix: Fix): Boolean =
        fix.at >= 0L && fix.lat.isFinite() && fix.lng.isFinite() &&
            fix.lat in -90.0..90.0 && fix.lng in -180.0..180.0

    private fun trimBefore(oldestAt: Long) {
        while (samples.size > 1 && samples.first().at < oldestAt) samples.removeFirst()
    }

    private fun keepOnly(fix: Fix) {
        samples.clear()
        samples += fix
    }

    companion object {
        const val MAX_ACCURACY_METERS = 30f
        const val FAST_PROBE_MILLIS = 30_000L
        const val STOP_CONFIRM_MILLIS = 60_000L
        const val MIN_CONFIRM_MILLIS = 10_000L
        const val MIN_CONFIRM_POINTS = 3
        const val SPEED_TRUST_MAX_ACCURACY_METERS = 15f
        const val MIN_CONFIDENT_SPEED_MPS = 0.35f
        const val MIN_SPEED_DISPLACEMENT_METERS = 3.0
        const val MIN_NET_DISPLACEMENT_METERS = 30.0
        const val SLOW_PROBE_MIN_DISPLACEMENT_METERS = 15.0
        const val STOP_RADIUS_METERS = 15.0
        const val NOISE_MULTIPLIER = 2.0
        const val MIN_PROGRESS_RATIO = 0.6
    }
}
