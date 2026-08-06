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
        val priority = if (moving) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY
        Log.i(TAG, "수집 주기 변경: ${if (moving) "이동" else "정지"} ${interval / 1000}초")

        val request = LocationRequest.Builder(priority, interval)
            .setMinUpdateIntervalMillis(interval / 2)
            .build()

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
        const val MOVING_INTERVAL_MILLIS = 60_000L

        /** 정지 중 주기. 설계서 §4.1 */
        const val STILL_INTERVAL_MILLIS = 5 * 60_000L
    }
}
