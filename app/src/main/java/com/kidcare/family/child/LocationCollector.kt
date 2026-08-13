package com.kidcare.family.child

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import com.google.android.gms.location.Granularity
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.kidcare.family.logic.AdaptiveMovementState
import com.kidcare.family.logic.Fix

/**
 * FusedLocationProvider 래퍼.
 *
 * 활동 인식, 좌표 기반 이동 확인, 등록 장소 여부를 합쳐 수집 주기를 바꾼다.
 * 이동 가능성을 확인하는 동안은 5초, 실제 이동이 아니면 30초, 활동 인식 정지는
 * 5분, 등록 장소 머무름은 1분이다. 부모가 실시간 보기를 켠 동안만 2초로 고정한다.
 * 활동 인식 권한이 없어도 좌표가 30초 동안 실제 진행을 보이지 않으면 저주기 확인으로
 * 내려가므로 하루 종일 5초 GPS가 켜진 채 남지 않는다.
 */
class LocationCollector(private val context: Context) {

    private val client = LocationServices.getFusedLocationProviderClient(context)
    private var callback: LocationCallback? = null
    private var onFixCallback: ((Fix, Boolean) -> Unit)? = null

    // 처음에는 이동 가능성을 빠르게 확인한다. 실제 진행이 없으면 판정기가 30초 뒤
    // 저주기 확인으로 내리므로 활동 인식 권한이 없는 기기도 5초 고정으로 남지 않는다.
    private var activityMoving = true
    private var adaptiveState = AdaptiveMovementState.FAST_PROBE
    private var insideKnownPlace = false
    private var liveTracking = false

    /**
     * 권한은 호출 전에 확인돼 있어야 한다. TrackingService.onCreate 가 startForeground
     * 를 부르기 전에 이미 확인하고, 확인에 실패하면 이 함수 자체를 부르지 않으므로
     * 여기 도달했다는 것은 그 확인을 통과했다는 뜻이다.
     */
    @SuppressLint("MissingPermission")
    fun start(onFix: (Fix, Boolean) -> Unit) {
        onFixCallback = onFix
        requestUpdates()
    }

    /**
     * 주기를 바꿀 때는 기존 요청을 지우고 다시 건다. clearUpdates() 를 항상 먼저
     * 불러 이전 콜백을 명시적으로 제거한다 — 안 그러면 이전 주기와 새 주기가
     * 동시에 도는 채로 남아 배터리가 오히려 더 나빠질 수 있다.
     */
    @SuppressLint("MissingPermission")
    private fun requestUpdates() {
        val onFix = onFixCallback ?: return
        clearUpdates()

        val interval = when {
            liveTracking -> LIVE_INTERVAL_MILLIS
            !activityMoving -> STILL_INTERVAL_MILLIS
            insideKnownPlace -> KNOWN_PLACE_INTERVAL_MILLIS
            adaptiveState == AdaptiveMovementState.MOVING -> MOVING_INTERVAL_MILLIS
            adaptiveState == AdaptiveMovementState.FAST_PROBE -> MOVING_INTERVAL_MILLIS
            else -> SLOW_PROBE_INTERVAL_MILLIS
        }
        val mode = when {
            liveTracking -> "실시간"
            !activityMoving -> "활동 인식 정지"
            insideKnownPlace -> "등록 장소 머무름"
            adaptiveState == AdaptiveMovementState.MOVING -> "이동 확정"
            adaptiveState == AdaptiveMovementState.FAST_PROBE -> "이동 확인"
            else -> "저주기 확인"
        }
        Log.i(TAG, "수집 주기 변경: $mode ${interval / 1000}초")

        // 정지 중에도 PRIORITY_HIGH_ACCURACY 를 쓴다(2026-08-07 변경. 예전엔 정지에
        // PRIORITY_BALANCED_POWER_ACCURACY 였다).
        //
        // "가만히 있는 폰에 왜 GPS 를 켜 두나"가 당연히 나올 질문이라 근거를 남긴다.
        // BALANCED 는 WiFi·기지국 측위라 오차가 보통 20~60m, 나쁘면 그보다 훨씬 크다.
        // 그런데 **아이가 하루의 대부분을 보내는 곳이 바로 그 정지 구간**이다(학교·집·
        // 학원). 그리고 머무름 구간의 좌표를 역지오코딩해서 "△△초등학교" 같은 이름을
        // 만드는 것도(PlaceNamer) 그 점들이다. 즉 옛 설정은 **가장 부정확한 점이 장소
        // 이름을 정하게** 만들어 놨고, 부모가 실제로 겪은 불만("장소가 옆 건물로 나온다")이
        // 정확히 그것이다.
        //
        // 배터리는 우선순위 플래그보다 **깨어나는 빈도**가 지배한다. 정지 주기 5분은
        // 그대로 두므로 GPS 는 5분에 한 번 짧게 잡고 그 사이에는 무선을 재운다 —
        // 이동(5초)과 비교하면 같은 HIGH_ACCURACY 라도 깨우는 횟수가 1/60이다.
        // 실기기에서 하루 소모를 재 보고 그래도 과하면 사용자용 "배터리 아끼기"
        // 토글을 다는 것이 다음 수순이다(docs/known-issues.md).
        val builder = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, interval)
            .setMinUpdateIntervalMillis(interval)
            .setGranularity(Granularity.GRANULARITY_FINE)
            // 실시간 보기를 시작할 때 캐시된 오래된 위치 대신 새 측정값을 기다린다.
            .setMaxUpdateAgeMillis(0L)
            // 여러 위치를 묶어 늦게 전달하지 않고 요청 주기에 맞춰 바로 전달한다.
            .setMaxUpdateDelayMillis(interval)
            // 첫 콜백을 빨리 주려고 기지국·Wi-Fi 기반의 거친 좌표를 먼저 내보내는
            // 대신, 가능한 경우 GNSS 고정밀 좌표를 잠깐 기다린다. 경로 시작점이 옆
            // 블록에서 출발하는 모양을 줄이되 주기 자체(이동 5초)는 바꾸지 않는다.
            .setWaitForAccurateLocation(true)

        if (
            activityMoving && !liveTracking && !insideKnownPlace &&
            adaptiveState == AdaptiveMovementState.MOVING
        ) {
            // 3m는 보행 5초(보통 5~8m)를 삼키지 않으면서 아주 작은 좌표 흔들림은
            // 무선 계층에서 먼저 줄이는 값이다. 최종 기록 여부는 정확도 반경과 속도를
            // 함께 보는 MovementTrailFilter가 결정한다.
            //
            // 완전히 멈춘 폰은 이 필터 때문에 콜백이 굶을 수 있으므로, 좌표 판정까지
            // 끝난 MOVING 상태에만 건다. 빠른/느린 확인·등록 장소·활동 인식 정지에는
            // 필터가 없어 하트비트와 상태 검사가 계속 기회를 얻는다.
            builder.setMinUpdateDistanceMeters(MOVING_MIN_UPDATE_DISTANCE_METERS)
        }

        val request = builder.build()

        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                // 제조사 구현이나 잠깐의 절전 뒤에는 한 콜백에 여러 위치가 묶여 올 수
                // 있다. lastLocation 하나만 쓰면 그 사이의 모퉁이가 사라져 경로가 건물을
                // 가로지르는 직선이 된다. 묶음 안의 모든 점을 시간순으로 넘긴다.
                result.locations.sortedBy { it.time }.forEach { loc ->
                    onFix(
                        Fix(
                            lat = loc.latitude,
                            lng = loc.longitude,
                            accuracy = loc.accuracy,
                            at = loc.time,
                            speed = loc.speed,
                            speedAccuracy = if (loc.hasSpeedAccuracy()) {
                                loc.speedAccuracyMetersPerSecond
                            } else {
                                Float.POSITIVE_INFINITY
                            },
                        ),
                        activityMoving,
                    )
                }
            }
        }
        callback = cb
        client.requestLocationUpdates(request, cb, context.mainLooper)
    }

    fun stop() {
        clearUpdates()
        onFixCallback = null
    }

    private fun clearUpdates() {
        callback?.let { client.removeLocationUpdates(it) }
        callback = null
    }

    /**
     * 활동 인식 전환을 받은 TrackingService 가 부른다. 전환 API 는 같은 상태를
     * 중복으로 보낼 수 있어(예: STILL 진입을 두 번), 실제로 바뀌었을 때만 요청을
     * 다시 건다 — 안 그러면 같은 주기인데도 매번 지웠다 다시 걸어 배터리를 더 쓴다.
     */
    fun onMovingChanged(nowMoving: Boolean) {
        if (activityMoving == nowMoving) return
        activityMoving = nowMoving
        adaptiveState = AdaptiveMovementState.FAST_PROBE
        requestUpdates()
    }

    /** 좌표 증거로 확인한 이동 상태에 맞춰 평상시 수집 주기만 바꾼다. */
    fun setAdaptiveMovementState(state: AdaptiveMovementState) {
        if (adaptiveState == state) return
        adaptiveState = state
        requestUpdates()
    }

    /** 등록 장소 안에서는 작은 실내 움직임을 경로로 만들지 않고 이탈만 느슨하게 확인한다. */
    fun setInsideKnownPlace(inside: Boolean) {
        if (insideKnownPlace == inside) return
        insideKnownPlace = inside
        requestUpdates()
    }

    /** 부모가 실시간 보기를 켠 동안에만 2초 고정밀 요청으로 전환한다. */
    fun setLiveTrackingEnabled(enabled: Boolean) {
        if (liveTracking == enabled) return
        liveTracking = enabled
        requestUpdates()
    }

    private companion object {
        const val TAG = "LocationCollector"

        /**
         * 이동 중에는 모퉁이를 놓치지 않도록 5초마다 후보 위치를 받는다.
         *
         * 60초 × MIN_MOVE_METERS 50m 조합은 걸을 때 점이 약 70m 마다 하나라 경로선이
         * 모퉁이를 잘라먹었고, 차 안에서는 1km 에 한 점이었다. 설계서 §4.1 참고.
         */
        const val MOVING_INTERVAL_MILLIS = 5_000L

        const val LIVE_INTERVAL_MILLIS = 2_000L

        /** 활동 전환을 놓쳤을 때 실제 이동이 시작됐는지 확인하는 저주기 후보 수집. */
        const val SLOW_PROBE_INTERVAL_MILLIS = 30_000L

        /** 집·학교처럼 등록한 장소 안에서는 OS 지오펜스와 함께 이 주기로 이탈을 보조 확인한다. */
        const val KNOWN_PLACE_INTERVAL_MILLIS = 60_000L

        /** 정지 중 주기. 설계서 §4.1 */
        const val STILL_INTERVAL_MILLIS = 5 * 60_000L

        /** 이동 요청에만 거는 최소 이동 거리. 값의 근거는 requestUpdates() 주석. */
        const val MOVING_MIN_UPDATE_DISTANCE_METERS = 3f
    }
}
