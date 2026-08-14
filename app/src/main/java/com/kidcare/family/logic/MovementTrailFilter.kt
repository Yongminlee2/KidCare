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

    /**
     * 경로점으로 받는 정확도 상한. 상태 업로드([LocationFilter])와 같은 50m 다.
     *
     * 처음에는 30m 로 더 조였는데, 실기기에서 그 값이 **경로 중간을 통째로 비웠다** —
     * 버스·번화가·실내 구간은 오차가 30~50m 로 몇 분씩 이어지는 게 정상이라, 그동안
     * 후보가 전부 거절돼 5분짜리 머무름 기준점만 남고 지도에는 그 구간이 삭제된
     * 것처럼 보였다. 거친 점의 흔들림은 아래 noiseRadius 판정이 오차에 비례해
     * 알아서 더 크게 요구하므로, 상한을 올려도 정지한 폰이 선을 그리지는 않는다.
     */
    const val MAX_ACCURACY_METERS = 50f

    /**
     * 정지 주기(5분) 사이에 이만큼 옮겨졌으면 **좌표 자체가 이동의 증거**다.
     *
     * 활동 인식은 가방 속 폰의 버스 이동 같은 것을 통째로 놓칠 수 있고, 전환 이벤트는
     * 상태가 바뀔 때만 오므로 한 번 놓치면 끝까지 5분 주기에 갇힌다. 두 점의 오차가
     * 최악으로 반대 방향이어도 100m(50m×2)를 넘을 수 없으므로 150m 는 흔들림으로는
     * 못 만드는 거리다.
     */
    const val DISPLACEMENT_EVIDENCE_METERS = 150.0

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

    /**
     * 활동 인식이 정지라고 하는데 좌표가 크게 옮겨졌는가.
     *
     * true 면 호출자([child.TrackingService])가 이동 확인(5초 주기)을 시작한다 —
     * 지오펜스 이탈을 이동 증거로 쓰는 것과 같은 원리다. 두 점 다 상태 업로드
     * 문턱(50m) 안쪽의 정확도여야 한다: 수백 미터 오차의 쓰레기 점 하나가
     * 5초 주기를 켜게 두면 안 된다.
     */
    fun isDisplacementEvidence(previous: Fix?, candidate: Fix): Boolean {
        if (previous == null) return false
        if (!candidate.accuracy.isFinite() || candidate.accuracy > LocationFilter.MAX_ACCURACY_METERS) return false
        if (!previous.accuracy.isFinite() || previous.accuracy > LocationFilter.MAX_ACCURACY_METERS) return false
        val elapsed = candidate.at - previous.at
        if (elapsed <= 0L) return false
        val distance = LocationFilter.distanceMeters(previous, candidate)
        if (distance / (elapsed / 1_000.0) > LocationFilter.MAX_SPEED_MPS) return false
        return distance >= DISPLACEMENT_EVIDENCE_METERS
    }

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
