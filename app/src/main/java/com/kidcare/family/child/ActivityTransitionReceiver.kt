package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * ActivityRecognitionClient 가 정지(STILL) 진입/이탈을 알릴 때 시스템이 이 리시버를
 * 깨운다. 매니페스트에 등록돼 있어 TrackingService 가 도는 프로세스가 죽어 있어도
 * 시스템이 브로드캐스트를 배달할 수 있지만(그 경우 여기 인스턴스는 새로 만들어진다),
 * 실제로 주기를 바꿀 대상(LocationCollector)은 TrackingService 가 살아있을 때만
 * 존재한다. 서비스가 죽어 있으면 어차피 위치 수집도 멈춰 있으므로, 그럴 때 전환을
 * 조용히 버려도 안전하다 — TrackingService.notifyMovingChanged 가 그 경우 아무 일도
 * 하지 않는다.
 */
class ActivityTransitionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (!ActivityTransitionResult.hasResult(intent)) return
        val result = ActivityTransitionResult.extractResult(intent) ?: return

        for (event in result.transitionEvents) {
            if (event.activityType != DetectedActivity.STILL) continue
            // STILL 에서 벗어남(EXIT) = 움직이기 시작. STILL 로 들어감(ENTER) = 멈춤.
            val nowMoving = event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_EXIT
            Log.i(TAG, "활동 전환 수신: ${if (nowMoving) "이동 시작" else "정지 시작"}")
            TrackingService.notifyMovingChanged(nowMoving)
        }
    }

    private companion object {
        const val TAG = "ActivityTransitionReceiver"
    }
}
