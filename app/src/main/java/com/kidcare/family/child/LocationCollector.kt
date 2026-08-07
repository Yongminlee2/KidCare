package com.kidcare.family.child

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.kidcare.family.logic.Fix

/**
 * FusedLocationProvider 래퍼.
 *
 * 1~2단계는 고정 주기(1분, 고정밀)로만 받았다. 그때는 설계서 4.1의 '정지/이동에
 * 따른 주기 전환'을 일부러 미뤘다 — ActivityRecognition 까지 같이 넣으면, 위치가
 * 안 올라올 때 원인이 수집 주기 변경 쪽인지 업로드 경로 쪽인지 가려낼 수 없었기
 * 때문이다. 업로드 경로가 검증된 지금(3단계) 주기 전환을 붙인다.
 *
 * 활동 인식 전환 이벤트는 TrackingService 가 받아 onMovingChanged 로 넘겨준다.
 * 권한이 없거나, 있어도 전환 이벤트가 한 번도 안 오면 moving 은 시작값(true, 이동)
 * 그대로 남는다 — '모른다'를 '정지'로 해석해 주기를 5분으로 늘리는 일은 절대
 * 없다. 배터리보다 위치 신뢰성이 먼저라는 판단이다.
 */
class LocationCollector(private val context: Context) {

    private val client = LocationServices.getFusedLocationProviderClient(context)
    private var callback: LocationCallback? = null
    private var onFixCallback: ((Fix) -> Unit)? = null

    // 활동 인식이 아직 아무것도 알려주지 않았을 때의 기본값. true(이동)로 두는 이유는
    // 둘이다 — 서비스가 막 켜졌을 때 첫 위치를 늦지 않게 잡아야 하고, 이미 가만히
    // 앉아 있는 아이는 '정지 시작' 전환 자체가 원래 안 온다(전환은 상태가 바뀔 때만
    // 오지, 지금 상태를 알려주지 않는다) — 그런 아이를 계속 5분 주기로 방치하면 안 된다.
    private var moving = true

    /**
     * 권한은 호출 전에 확인돼 있어야 한다. TrackingService.onCreate 가 startForeground
     * 를 부르기 전에 이미 확인하고, 확인에 실패하면 이 함수 자체를 부르지 않으므로
     * 여기 도달했다는 것은 그 확인을 통과했다는 뜻이다.
     */
    @SuppressLint("MissingPermission")
    fun start(onFix: (Fix) -> Unit) {
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

        val interval = if (moving) MOVING_INTERVAL_MILLIS else STILL_INTERVAL_MILLIS
        Log.i(TAG, "수집 주기 변경: ${if (moving) "이동" else "정지"} ${interval / 1000}초")

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
        // 이동(30초)과 비교하면 같은 HIGH_ACCURACY 라도 duty cycle 이 1/10 이다.
        // 실기기에서 하루 소모를 재 보고 그래도 과하면 사용자용 "배터리 아끼기"
        // 토글을 다는 것이 다음 수순이다(docs/known-issues.md).
        val builder = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, interval)
            .setMinUpdateIntervalMillis(interval / 2)

        if (moving) {
            // 이동 상태인데 실제로는 가만히 있는 폰(활동 인식 권한이 없어 moving 이
            // true 로 굳은 경우가 대표적이다)을 30초마다 깨우지 않으려는 것이다.
            //
            // 20m 인 이유는 LocationFilter.MIN_MOVE_METERS(25m)를 **넘지 않기 위해서**다.
            // 이 값이 25m 이상이면 무선 계층이 LocationFilter 가 올렸을 fix 를 먼저
            // 삼켜버려, "얼마나 움직여야 올리는가"를 정하는 곳이 두 군데로 갈린다 —
            // 그 판단은 단위테스트로 고정된 LocationFilter 한 곳에만 있어야 한다.
            // 20m 는 좋은 fix 의 흔들림(보통 3~8m)보다는 위라, 진짜로 멈춰 있는 폰의
            // 잡음성 깨우기는 걸러진다.
            //
            // 대가가 있다: 완전히 멈춘 폰은 콜백 자체가 안 와서 LocationFilter 의
            // 하트비트(10분)가 탈 fix 가 없어질 수 있다. 그래서 **정지 요청에는
            // 이 필터를 걸지 않는다** — 활동 인식이 정상이면 STILL 전환이 1분 안에
            // 와서 5분 주기(필터 없음)로 넘어가 생존 신호가 회복된다. 활동 인식
            // 권한이 아예 없는 폰에서만 이 구멍이 남고, 그건 실기기에서 확인할
            // 항목으로 known-issues 에 적어뒀다.
            builder.setMinUpdateDistanceMeters(MOVING_MIN_UPDATE_DISTANCE_METERS)
        }

        val request = builder.build()

        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                onFix(Fix(loc.latitude, loc.longitude, loc.accuracy, loc.time, loc.speed))
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
        if (moving == nowMoving) return
        moving = nowMoving
        requestUpdates()
    }

    private companion object {
        const val TAG = "LocationCollector"

        /**
         * 이동 중 주기. 60초에서 30초로 줄였다(2026-08-07).
         *
         * 60초 × MIN_MOVE_METERS 50m 조합은 걸을 때 점이 약 70m 마다 하나라 경로선이
         * 모퉁이를 잘라먹었고, 차 안에서는 1km 에 한 점이었다. 설계서 §4.1 참고.
         */
        const val MOVING_INTERVAL_MILLIS = 30_000L

        /** 정지 중 주기. 설계서 §4.1 */
        const val STILL_INTERVAL_MILLIS = 5 * 60_000L

        /** 이동 요청에만 거는 최소 이동 거리. 값의 근거는 requestUpdates() 주석. */
        const val MOVING_MIN_UPDATE_DISTANCE_METERS = 20f
    }
}
