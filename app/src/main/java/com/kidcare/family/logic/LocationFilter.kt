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
    /**
     * 기기가 보고한 속도 오차(1-sigma, m/s). 현재 수집 중인 점의 이동 여부를
     * 판정할 때만 쓰며, 예전 로컬 파일·서버 문서에는 이 값이 없으므로 기본값은
     * '알 수 없음'이다.
     */
    val speedAccuracy: Float = Float.POSITIVE_INFINITY,
)

enum class Decision {
    /** Firestore 에 올린다. */
    UPLOAD,

    /**
     * 올리긴 하는데, 평소 기준이면 버렸을 점이다.
     *
     * 오차가 [LocationFilter.MAX_ACCURACY_METERS] 를 넘지만 마지막 업로드로부터
     * [LocationFilter.STALE_FALLBACK_MILLIS] 가 지나 **아무것도 못 올리고 있는 상태**라,
     * 완화 기준([LocationFilter.FALLBACK_MAX_ACCURACY_METERS])까지 받아들였다는 뜻이다.
     *
     * 값을 [UPLOAD] 와 따로 둔 이유는 보호자에게 보여주려는 게 아니다(보호자는 이미
     * 지도의 정확도 원으로 오차 크기 자체를 본다 — 그게 참/거짓 한 비트보다 낫다).
     * 두 가지 때문이다.
     *  1. **로그.** `docs/known-issues.md` 의 '정확도 기아 상태' 항목은 `adb logcat -s
     *     TrackingService:W` 로 진단하라고 적혀 있는데, 완화 승인이 정상 승인과 똑같이
     *     조용하면 "신호가 계속 나쁜 채로 간신히 버티는 중"과 "다 정상"을 구분할 방법이
     *     없다. 이 값이 있어야 그 상태가 로그에 드러난다.
     *  2. **테스트.** 이 값이 없으면 "완화 창이 지나 60m 를 받아들였다"는 테스트가
     *     [UPLOAD] 만 확인하게 되는데, 그건 문턱을 그냥 100m 로 되돌려도 똑같이
     *     통과한다 — 완화 경로를 고정하지 못하는 테스트다.
     */
    UPLOAD_STALE_FALLBACK,

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

    /**
     * 평소 오차 문턱. 이보다 크면 버린다. 설계서 4.1
     *
     * 100m 에서 50m 로 내렸다(2026-08-07). 90m 짜리 점도 지도에서는 확신에 찬 점
     * 하나로 그려지는데, 그 점이 [com.kidcare.family.child.PlaceNamer] 를 통해 장소
     * 이름까지 만들어내면 "옆 건물 이름"이 그대로 부모 화면에 박힌다.
     */
    const val MAX_ACCURACY_METERS: Float = 50f

    /**
     * 오래 아무것도 못 올렸을 때만 쓰는 완화 문턱(= 옛 [MAX_ACCURACY_METERS] 값).
     *
     * 문턱을 조이면 신호가 나쁜 실내에서 들어오는 fix 가 **전부** 거절돼 점이 하나도
     * 안 올라갈 수 있다(`docs/known-issues.md` '정확도 기아 상태'). 부모가 실제로
     * 묻는 것은 "지금 우리 애 어디 있냐"인데, 100m 오차는 그 질문에 답이 되고 침묵은
     * 답이 안 된다. 그래서 굶는 것보다 거친 점을 택한다.
     */
    const val FALLBACK_MAX_ACCURACY_METERS: Float = 100f

    /**
     * 마지막 업로드로부터 이만큼 지나면 완화 문턱을 연다.
     *
     * [HEARTBEAT_MILLIS](10분)보다 **길어야 한다.** 같거나 짧으면 정상 동작 중에도
     * (하트비트 주기마다) 완화가 상시로 열려 문턱을 조인 의미가 사라진다.
     * 15분은 하트비트를 한 번 통째로 놓친 뒤에야 열린다는 뜻이다.
     */
    const val STALE_FALLBACK_MILLIS: Long = 15 * 60 * 1000L

    /**
     * 이만큼 안 움직였으면 안 올린다. 설계서 4.1
     *
     * 50m 에서 25m 로 내렸다(2026-08-07). 이동 주기 60초 × 50m 문턱이면 걸어갈 때
     * 점이 약 70m 마다 하나라 경로선이 모퉁이를 잘라먹고, 차 안에서는 1km 에 하나였다.
     * [com.kidcare.family.logic.SegmentBuilder.STAY_RADIUS_METERS](100m) 판정은 점
     * 사이 간격이 아니라 '기준점에서의 절대 거리'로 하므로 이 값을 내려도 영향이 없다.
     */
    const val MIN_MOVE_METERS: Double = 25.0

    /** 시속 200km. 이보다 빠르면 GPS 오류로 본다. */
    const val MAX_SPEED_MPS: Double = 55.6

    /** 안 움직여도 이 시간이 지나면 살아있다는 뜻으로 한 번 올린다. */
    const val HEARTBEAT_MILLIS: Long = 10 * 60 * 1000L

    private const val EARTH_RADIUS_METERS = 6_371_000.0

    fun decide(previous: Fix?, candidate: Fix): Decision {
        // 올린 게 하나도 없다 = 부모 화면이 통째로 비어 있다. "오래 못 올렸다"의
        // 가장 극단이므로 완화 문턱을 그대로 적용한다. 여기서 평소 문턱(50m)을
        // 고집하면, 실내에서 막 켠 서비스가 GPS 를 잡을 때까지 지도가 빈 채로
        // 남는다 — 이 작업이 없애려던 바로 그 침묵이다.
        if (previous == null) return acceptByAccuracy(candidate, stale = true)

        val elapsed = candidate.at - previous.at
        if (elapsed <= 0L) return Decision.REJECT_IMPOSSIBLE

        val stale = elapsed >= STALE_FALLBACK_MILLIS
        val accuracyVerdict = acceptByAccuracy(candidate, stale)
        if (accuracyVerdict == Decision.REJECT_INACCURATE) return accuracyVerdict

        val distance = distanceMeters(previous, candidate)
        if (distance / (elapsed / 1000.0) > MAX_SPEED_MPS) return Decision.REJECT_IMPOSSIBLE

        // 완화로 통과한 점은 여기서 확정한다 — 순간이동 검사를 **지난 뒤**여야 한다.
        // 목이 마르다고 튄 좌표까지 받아들이면 지도에 없는 곳이 찍힌다.
        // 거리·하트비트 검사를 건너뛰는 것은 판단이 아니라 산술이다: stale 이 참이라는
        // 것은 이미 15분이 지났다는 뜻이고, 그러면 하트비트(10분)도 반드시 지났다.
        if (accuracyVerdict == Decision.UPLOAD_STALE_FALLBACK) return accuracyVerdict

        if (distance >= MIN_MOVE_METERS) return Decision.UPLOAD
        if (elapsed >= HEARTBEAT_MILLIS) return Decision.UPLOAD
        return Decision.SKIP_TOO_CLOSE
    }

    /** 오차만 보고 내리는 1차 판정. 문턱은 [stale] 여부로 갈린다. */
    private fun acceptByAccuracy(candidate: Fix, stale: Boolean): Decision = when {
        candidate.accuracy <= MAX_ACCURACY_METERS -> Decision.UPLOAD
        stale && candidate.accuracy <= FALLBACK_MAX_ACCURACY_METERS -> Decision.UPLOAD_STALE_FALLBACK
        else -> Decision.REJECT_INACCURATE
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
