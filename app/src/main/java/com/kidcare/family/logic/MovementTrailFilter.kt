package com.kidcare.family.logic

import kotlin.math.hypot
import kotlin.math.max

/**
 * 이동 경로 파일에 남길 점을 고른다.
 *
 * 위치 수집기는 이동 상태일 때 5초마다 후보를 보내지만, GPS가 말하는 한 점은 실제
 * 좌표가 아니라 [Fix.accuracy] 반경 안의 추정치다. 후보를 전부 쓰면 책상 위에 놓인
 * 폰도 작은 원을 계속 그린다. 활동 인식이 이동이라고 말하고, 정확도가 쓸 만하며,
 * 속도 또는 이전 점과의 거리가 오차 흔들림보다 클 때만 경로점으로 인정한다.
 *
 * 상태 보고에 쓰는 [LocationFilter]와 분리한 이유는 목적이 다르기 때문이다. 상태는
 * 25m/10분 간격이면 충분하지만, 경로는 모퉁이를 남기려면 이동 중 5초 점이 필요하다.
 */
object MovementTrailFilter {

    const val MIN_INTERVAL_MILLIS = 5_000L
    /** 상태 마커보다 엄격한 경로용 문턱. 거친 점으로 선을 잇는 것보다 짧은 공백이 낫다. */
    const val MAX_ACCURACY_METERS = 30f

    /** 정확도가 좋은 야외에서 보행으로 볼 수 있는 최소 GNSS 속도. */
    const val MOVING_SPEED_MPS = 0.7f

    /** 정확도 값이 지나치게 좋게 나와도 5m 이내 변화는 GPS 흔들림으로 본다. */
    const val MIN_DISPLACEMENT_METERS = 5.0

    /** 이 이하 오차의 GNSS 속도만 보행 판정의 보조 근거로 신뢰한다. */
    const val SPEED_TRUST_MAX_ACCURACY_METERS = 15f

    /** 속도 오차를 뺀 뒤에도 이 값 이상이어야 실제 이동 속도로 본다. */
    const val MIN_CONFIDENT_SPEED_MPS = 0.35f

    /** 속도값 하나만 튀어도 같은 좌표를 계속 기록하지 않도록 요구하는 최소 변위. */
    const val MIN_SPEED_EVIDENCE_DISPLACEMENT_METERS = 3.0

    fun shouldRecord(previous: Fix?, candidate: Fix, reportedMoving: Boolean): Boolean {
        if (!reportedMoving) return false
        if (candidate.accuracy > MAX_ACCURACY_METERS) return false
        if (candidate.speed > LocationFilter.MAX_SPEED_MPS) return false
        if (previous == null) return true

        val elapsed = candidate.at - previous.at
        if (elapsed < MIN_INTERVAL_MILLIS) return false

        val distance = LocationFilter.distanceMeters(previous, candidate)
        val impliedSpeed = distance / (elapsed / 1_000.0)
        if (impliedSpeed > LocationFilter.MAX_SPEED_MPS) return false

        // 정확도가 좋은 야외의 GNSS speed만 보조 근거로 쓴다. 실내에서는 정지한 폰도
        // 2~5m/s라고 잘못 보고하는 실기기 사례가 있어 오차가 큰 speed를 믿으면 안 된다.
        val speedEvidence = if (candidate.speedAccuracy.isFinite()) {
            candidate.speed - candidate.speedAccuracy >= MIN_CONFIDENT_SPEED_MPS
        } else {
            // 예전 기기/공급자가 속도 정확도를 주지 않을 때는 기존 속도 문턱을 쓰되,
            // 아래의 실제 변위 조건까지 함께 만족해야 한다.
            candidate.speed >= MOVING_SPEED_MPS
        }
        if (
            previous.accuracy <= SPEED_TRUST_MAX_ACCURACY_METERS &&
            candidate.accuracy <= SPEED_TRUST_MAX_ACCURACY_METERS &&
            speedEvidence &&
            distance >= MIN_SPEED_EVIDENCE_DISPLACEMENT_METERS
        ) return true

        // 같은 실제 위치에서 나온 두 점은 각각의 오차 원 안에서 반대 방향으로 흔들릴
        // 수 있다. 두 오차의 제곱합보다 멀리 벗어나야 실제 이동으로 인정한다.
        val noiseRadius = max(
            MIN_DISPLACEMENT_METERS,
            hypot(previous.accuracy.toDouble(), candidate.accuracy.toDouble()),
        )
        return distance >= noiseRadius
    }
}
