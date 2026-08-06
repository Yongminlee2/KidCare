package com.kidcare.family.child

import android.annotation.SuppressLint
import android.content.Context
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.kidcare.family.logic.Fix

/**
 * FusedLocationProvider 래퍼.
 *
 * 1단계에서는 고정 주기(1분, 고정밀)로만 받는다. 설계서 4.1 의 '정지/이동에 따른
 * 주기 전환'은 ActivityRecognition 이 필요한데, 그건 위치가 제대로 올라오는 것을
 * 확인한 뒤 3단계에서 붙인다. 지금 둘을 같이 넣으면 위치가 안 올라올 때
 * 원인이 수집 주기인지 업로드인지 가려내기 어렵다.
 */
class LocationCollector(private val context: Context) {

    private val client = LocationServices.getFusedLocationProviderClient(context)
    private var callback: LocationCallback? = null

    /**
     * 권한은 호출 전에 확인돼 있어야 한다. TrackingService.onCreate 가 startForeground
     * 를 부르기 전에 이미 확인하고, 확인에 실패하면 이 함수 자체를 부르지 않으므로
     * 여기 도달했다는 것은 그 확인을 통과했다는 뜻이다.
     */
    @SuppressLint("MissingPermission")
    fun start(onFix: (Fix) -> Unit) {
        stop()
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, INTERVAL_MILLIS)
            .setMinUpdateIntervalMillis(INTERVAL_MILLIS / 2)
            .build()

        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                onFix(Fix(loc.latitude, loc.longitude, loc.accuracy, loc.time))
            }
        }
        callback = cb
        client.requestLocationUpdates(request, cb, context.mainLooper)
    }

    fun stop() {
        callback?.let { client.removeLocationUpdates(it) }
        callback = null
    }

    private companion object {
        const val INTERVAL_MILLIS = 60_000L
    }
}
