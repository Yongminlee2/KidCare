package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.GeofencingEvent
import com.kidcare.family.logic.Fix

/**
 * 플레이 서비스가 장소 경계를 넘었다고 알릴 때 시스템이 이 리시버를 깨운다.
 *
 * ## 여기서 이벤트를 쓰지 않는다
 *
 * 이 콜백은 **판정 결과가 아니라 판정해 보라는 신호**다. 여기서 곧장 `events/` 에
 * 도착·이탈을 적으면 [com.kidcare.family.logic.GeofenceEvaluator] 의 히스테리시스(이탈은
 * 반경 + 50m)와 5분 중복 억제, 정확도 문턱을 통째로 건너뛴다 — 경계에 앉아 있는 아이
 * 하나 때문에 부모 폰이 하루 종일 운다. 그래서 전환에 실려 온 위치를 [Fix] 로만 바꿔
 * 넘기고, 알릴지 말지는 언제나 판정기가 정한다([PlaceWatcher] 클래스 주석).
 *
 * ## 서비스가 죽어 있으면 조용히 버린다
 *
 * 판정에 필요한 재료(장소 목록·가족 ID·로그인된 uid)는 전부 [TrackingService] 쪽에
 * 있다. 여기서 그것들을 다시 갖추려면 리시버가 깨어날 때마다 Firestore 를 읽어야 하는데,
 * 그건 전환 한 번당 읽기 한 번이라 무료 한도를 그대로 갉아먹는다(docs/known-issues.md
 * 12번). 서비스가 죽어 있다는 것은 위치 수집도 멈춰 있다는 뜻이고, 그 상태는
 * START_STICKY·BOOT_COMPLETED 로 곧 복구되며 그때 첫 위치 점이 같은 판정을 한다.
 * [ActivityTransitionReceiver] 가 같은 이유로 같은 선택을 했다.
 */
class PlaceGeofenceReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) {
            // 흔한 값이 GEOFENCE_NOT_AVAILABLE(1000)이다 — 기기에서 위치가 꺼졌거나
            // NLP 가 재시작된 경우로, 등록이 통째로 날아가 있다. 조용히 지나가면
            // "왜 도착 알림이 안 오지"를 알아낼 방법이 없다.
            Log.w(TAG, "지오펜스 전환 오류: errorCode=${event.errorCode}")
            return
        }
        val location = event.triggeringLocation ?: return

        // 시각은 위치가 잡힌 순간(location.time)이지 이 브로드캐스트가 배달된 순간이
        // 아니다. 절전 상태에서 배달이 몇 분 밀릴 수 있는데, 그때 '지금'을 쓰면 사건이
        // 실제로 일어난 시각을 지어내는 것이 된다. speed 는 판정에 안 쓰므로 안 채운다.
        TrackingService.notifyGeofenceCrossing(
            Fix(location.latitude, location.longitude, location.accuracy, location.time)
        )
    }

    private companion object {
        const val TAG = "PlaceGeofenceReceiver"
    }
}
