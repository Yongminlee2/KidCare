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
     * 정지 주기 사이에 이만큼 옮겨졌으면 **좌표 자체가 이동의 증거**다.
     *
     * 활동 인식은 가방 속 폰의 버스 이동을 통째로 놓칠 수 있고, 전환 이벤트는 상태가
     * 바뀔 때만 오므로 한 번 놓치면 스스로는 못 돌아온다. 그때 좌표가 대신 깨운다.
     *
     * 150m 에서 50m 로 내렸다. 150m 는 **집 앞 놀이터·근처 슈퍼를 전부 놓쳤다** —
     * 그 거리가 애초에 60~100m 라 문턱에 닿지 못했고, 그래서 짧은 외출은 이동으로
     * 시작조차 되지 않았다.
     */
    const val DISPLACEMENT_EVIDENCE_METERS = 50.0

    /**
     * 변위를 증거로 인정할 때 오차에 곱하는 배수.
     *
     * 고정 문턱만 쓰면 안 되는 이유: 두 점 다 오차 40m 여도 통과하는데(상한이 50m),
     * 그 둘의 변위 잡음은 표준편차가 `hypot(40,40) ≈ 57m` 라 **가만히 있어도 50m 는
     * 예사로 벌어진다.** 그러면 서 있는 폰이 5초 주기를 계속 켜서 배터리만 태운다.
     *
     * 그래서 문턱은 `max(50m, hypot × 1.5)` 다. 좌표가 좋을 때(오차 10m 안팎)는 50m
     * 짜리 놀이터 외출이 잡히고, 좌표가 거칠 때는 애초에 구분할 수 없으므로 추측하지
     * 않는다 — 못 믿을 재료로 판단하느니 활동 인식과 지오펜스에 맡긴다.
     */
    const val DISPLACEMENT_EVIDENCE_NOISE_MULTIPLIER = 1.5

    /** 정확도가 좋은 야외에서 보행으로 볼 수 있는 최소 GNSS 속도. */
    const val MOVING_SPEED_MPS = 0.7f

    /**
     * 경로점으로 인정하는 최소 변위. 5m 에서 3m 로 내렸고, **오차에 비례해 키우지
     * 않는다.**
     *
     * 예전에는 `max(5m, hypot(오차1, 오차2))` 였다. 오차 20m 면 연속 두 점이 28m 는
     * 벌어져야 기록했는데, **아이가 5초 동안 걷는 거리는 6m** 다. 즉 걸어서는 경로점이
     * 하나도 안 남았고, 속도 근거 갈래(정확도 15m 이하 + 속도오차 확보)가 통과할 때만
     * 우연히 남았다. 실내·번화가에서 그 갈래가 막히면 하루 종일 점이 안 쌓인다.
     *
     * 이제 **수집은 넉넉히 하고 흔들림은 그릴 때 정리한다**(RoutePathRefiner 의 오차
     * 가중 평활과 단일 스파이크 제거). 버린 점은 영영 못 살리지만 남긴 점은 언제든
     * 다듬을 수 있기 때문이다. 저장 비용은 근거가 된다 — 한 점이 CSV 한 줄 약 50바이트라
     * 5초 간격으로 하루를 꽉 채워도 1MB 아래이고, 서버로는 어차피 하루 문서 하나만 간다.
     *
     * 3m 를 남긴 이유는 완전히 같은 좌표가 반복해 들어오는 것만 걸러내기 위해서다.
     */
    const val MIN_DISPLACEMENT_METERS = 3.0

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
        val threshold = max(
            DISPLACEMENT_EVIDENCE_METERS,
            hypot(previous.accuracy.toDouble(), candidate.accuracy.toDouble()) *
                DISPLACEMENT_EVIDENCE_NOISE_MULTIPLIER,
        )
        return distance >= threshold
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

        // 예전에는 여기서 오차에 비례한 반경(hypot)을 요구했다. 그 판정이 걷는 아이를
        // 통째로 지웠다([MIN_DISPLACEMENT_METERS] 주석). 이제는 같은 좌표의 반복만
        // 걸러내고, 흔들림 판단은 그리는 쪽으로 넘긴다.
        return distance >= MIN_DISPLACEMENT_METERS
    }
}
