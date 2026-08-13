package com.kidcare.family.logic

import kotlin.math.max
import kotlin.math.sqrt

/**
 * 실시간 화면에 올릴 위치를 고른다.
 *
 * 정확도가 나쁜 점과 순간이동을 버리고, 기기가 정지한 것으로 보이는 동안에만
 * 연속 좌표를 정확도 가중 평균해 GPS 흔들림을 줄인다. 실제 이동으로 판단되면
 * 경로가 뒤처지지 않도록 최신 측정값을 그대로 사용한다.
 */
object LiveLocationRefiner {

    fun refine(previous: Fix?, candidate: Fix): Fix? {
        if (!candidate.lat.isFinite() || !candidate.lng.isFinite()) return null
        if (candidate.lat !in -90.0..90.0 || candidate.lng !in -180.0..180.0) return null
        if (!candidate.accuracy.isFinite() || candidate.accuracy <= 0f ||
            candidate.accuracy > LocationFilter.MAX_ACCURACY_METERS
        ) return null
        if (previous == null) return candidate

        val elapsedMillis = candidate.at - previous.at
        if (elapsedMillis <= 0L) return null
        if (elapsedMillis > RESET_AFTER_MILLIS) return candidate

        val distance = LocationFilter.distanceMeters(previous, candidate)
        val elapsedSeconds = elapsedMillis / 1_000.0
        if (distance / elapsedSeconds > LocationFilter.MAX_SPEED_MPS) return null

        val reportedMoving = candidate.speed >= MIN_MOVING_SPEED_MPS &&
            candidate.speedAccuracy.isFinite() &&
            candidate.speedAccuracy <= MAX_USEFUL_SPEED_ACCURACY_MPS
        val movedBeyondNoise = distance > max(
            MIN_MOVING_DISTANCE_METERS,
            (previous.accuracy + candidate.accuracy).toDouble(),
        )
        if (reportedMoving || movedBeyondNoise) return candidate

        val previousVariance = max(previous.accuracy.toDouble(), MIN_ACCURACY_METERS).let { it * it }
        val measurementVariance = max(candidate.accuracy.toDouble(), MIN_ACCURACY_METERS).let { it * it }
        val predictedVariance = previousVariance + PROCESS_NOISE_METERS_PER_SECOND *
            PROCESS_NOISE_METERS_PER_SECOND * elapsedSeconds
        val gain = predictedVariance / (predictedVariance + measurementVariance)

        return candidate.copy(
            lat = previous.lat + gain * (candidate.lat - previous.lat),
            lng = previous.lng + gain * (candidate.lng - previous.lng),
            accuracy = sqrt((1.0 - gain) * predictedVariance).toFloat(),
        )
    }

    private const val RESET_AFTER_MILLIS = 20_000L
    private const val MIN_MOVING_SPEED_MPS = 0.8f
    private const val MAX_USEFUL_SPEED_ACCURACY_MPS = 2.5f
    private const val MIN_MOVING_DISTANCE_METERS = 8.0
    private const val MIN_ACCURACY_METERS = 3.0
    private const val PROCESS_NOISE_METERS_PER_SECOND = 2.0
}
