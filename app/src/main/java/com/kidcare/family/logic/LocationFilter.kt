package com.kidcare.family.logic

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** 위치 한 점. 안드로이드 Location 에 의존하지 않는 값 객체다. */
data class Fix(
    val lat: Double,
    val lng: Double,
    val accuracy: Float,
    val at: Long,
    /**
     * m/s. 기기가 속도를 못 주면 0 이다.
     *
     * 기본값을 둔 이유: 이 필드가 없던 시절에 저장된 points 문서는 speed 가 0 으로
     * 읽히는데, 그걸 "정지"로 오해하면 안 된다. 속도는 참고용이고 구간 판정은
     * 좌표와 시각으로만 한다.
     */
    val speed: Float = 0f,
)

enum class Decision {
    /** Firestore 에 올린다. */
    UPLOAD,
    /** 거의 안 움직였다. 배터리·통신량을 아끼려고 건너뛴다. */
    SKIP_TOO_CLOSE,
    /** 오차가 너무 커서 못 믿는다. */
    REJECT_INACCURATE,
    /** 물리적으로 불가능한 이동. GPS 오류다. */
    REJECT_IMPOSSIBLE,
}

/**
 * 받은 위치를 올릴지 말지 판정한다.
 *
 * 순서가 중요하다: 못 믿을 점(정확도·순간이동)을 먼저 버리고, 남은 것 중에서
 * 안 움직인 것을 건너뛴다. 반대 순서면 튄 좌표가 '많이 움직였다'로 통과해 버린다.
 */
object LocationFilter {

    /** 이보다 오차가 크면 버린다. 설계서 4.1 */
    const val MAX_ACCURACY_METERS: Float = 100f

    /** 이만큼 안 움직였으면 안 올린다. 설계서 4.1 */
    const val MIN_MOVE_METERS: Double = 50.0

    /** 시속 200km. 이보다 빠르면 GPS 오류로 본다. */
    const val MAX_SPEED_MPS: Double = 55.6

    /** 안 움직여도 이 시간이 지나면 살아있다는 뜻으로 한 번 올린다. */
    const val HEARTBEAT_MILLIS: Long = 10 * 60 * 1000L

    private const val EARTH_RADIUS_METERS = 6_371_000.0

    fun decide(previous: Fix?, candidate: Fix): Decision {
        if (candidate.accuracy > MAX_ACCURACY_METERS) return Decision.REJECT_INACCURATE
        if (previous == null) return Decision.UPLOAD

        val elapsed = candidate.at - previous.at
        if (elapsed <= 0L) return Decision.REJECT_IMPOSSIBLE

        val distance = distanceMeters(previous, candidate)
        if (distance / (elapsed / 1000.0) > MAX_SPEED_MPS) return Decision.REJECT_IMPOSSIBLE

        if (distance >= MIN_MOVE_METERS) return Decision.UPLOAD
        if (elapsed >= HEARTBEAT_MILLIS) return Decision.UPLOAD
        return Decision.SKIP_TOO_CLOSE
    }

    /** 하버사인 거리(m). */
    fun distanceMeters(a: Fix, b: Fix): Double {
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLng = Math.toRadians(b.lng - a.lng)
        val h = sin(dLat / 2).pow(2) +
            cos(Math.toRadians(a.lat)) * cos(Math.toRadians(b.lat)) * sin(dLng / 2).pow(2)
        return 2 * EARTH_RADIUS_METERS * asin(sqrt(h))
    }
}
