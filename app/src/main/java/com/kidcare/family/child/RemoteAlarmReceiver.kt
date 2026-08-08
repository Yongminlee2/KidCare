package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 원격 알람이 울 시각이 됐다는 신호와, 아이가 '알람 끄기'를 눌렀다는 신호를 받는다.
 *
 * ## 왜 [ScheduleAlarmReceiver] 에 얹지 않았나
 *
 * 재부팅·시각변경 재등록은 그쪽에 얹었지만(그 리시버 주석 참고), **울리는 신호만은**
 * 따로 둔다. `ScheduleAlarmReceiver` 는 들어온 인텐트를 전부 "예약 규칙을 다시 계산해라"
 * 로 읽고, 그 예약 경계 알람도 액션이 없는 인텐트다 — 둘을 한 리시버에서 받으면 액션
 * 하나로만 갈리는 분기가 생기고, 그 분기를 잘못 타면 알람이 안 울리거나 예약이 안 돈다.
 * 신호가 서로 다른 일을 시키므로 받는 문도 따로 둔다.
 *
 * ## 정지 액션이 왜 매니페스트 리시버인가
 *
 * [FindPhoneController] 는 정지 액션을 **코드로 등록한** 리시버로 받는다. 그 방식은
 * 등록한 프로세스가 살아 있는 동안만 동작해서, 울리는 도중 프로세스가 죽으면 알림줄에
 * 남은 '끄기' 버튼이 아무 일도 안 하는 버튼이 된다. 여기서는 매니페스트에 선언된 이
 * 리시버가 언제나 받으므로(안드로이드가 프로세스를 필요하면 다시 띄운다) 그 구멍이 없다 —
 * 그리고 등록·해제를 짝맞출 일도 없어진다.
 *
 * ## 울리는 일 자체는 여기서 하지 않는다
 *
 * 리시버는 `onReceive` 가 끝나면 시스템이 지켜 줄 이유가 없어지는 컴포넌트다. 5분을
 * 우는 일을 여기서 시작하면 그 5분 내내 **아무 포그라운드 컴포넌트도 없는 프로세스**가
 * 소리를 내게 된다([RemoteAlarmService] 주석). 그래서 여기서는 서비스를 띄우기만 한다.
 */
class RemoteAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // 리시버에 들어온 context 는 onReceive 가 끝나면 못 쓴다. 이 기능이 만드는
        // MediaPlayer·Handler 는 5분을 사는 물건이라 반드시 applicationContext 를 넘긴다.
        val app = context.applicationContext
        Log.i(TAG, "원격 알람 신호: action=${intent.action}")
        if (intent.action == RemoteAlarmController.ACTION_STOP) {
            // 끄는 일은 서비스가 필요 없다. 이미 떠 있으면 stop() 이 그 서비스를 함께
            // 내리고(RemoteAlarmController.onStopped), 프로세스가 죽었다 살아난 경우엔
            // 남아 있던 알림만 거두면 된다.
            RemoteAlarmController.stop(app)
            return
        }
        try {
            RemoteAlarmService.start(app)
        } catch (e: Exception) {
            // 포그라운드 서비스 시작이 거부됐다(안드로이드 12+ 의 백그라운드 제한).
            // 정확한 알람은 그 예외 목록에 있지만, 제조사 롬이나 앞으로의 정책 변화까지
            // 믿을 이유는 없다 — 그때는 이 프로세스에서 그냥 울린다. 회수될 수도 있는
            // 프로세스에서 우는 것이 아예 안 우는 것보다 낫다.
            Log.w(TAG, "알람 서비스를 못 띄웠다 — 이 프로세스에서 그대로 울린다", e)
            RemoteAlarmController.ring(app)
        }
    }

    private companion object {
        const val TAG = "RemoteAlarmReceiver"
    }
}
