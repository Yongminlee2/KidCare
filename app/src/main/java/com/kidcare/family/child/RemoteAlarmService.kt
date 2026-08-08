package com.kidcare.family.child

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 부모가 맞춘 알람이 우는 **5분 동안만** 사는 포그라운드 서비스.
 *
 * ## 왜 서비스가 필요한가
 *
 * [RemoteAlarmController.ring] 은 `MediaPlayer` 하나와 `Vibrator` 하나, 그리고
 * 5분짜리 [android.os.Handler] 타이머를 만든다. 셋 다 **이 프로세스가 살아 있어야만**
 * 의미가 있는 물건인데, 알람을 깨우는 것은 매니페스트 리시버([RemoteAlarmReceiver])
 * 하나뿐이다 — `onReceive` 가 끝나는 순간 이 앱에는 시스템이 지켜 줄 이유가 있는
 * 컴포넌트가 하나도 없을 수 있다. 그러면 안드로이드는 이 프로세스를 언제 회수해도
 * 되는 것으로 보고, 실제로 회수하면 **소리가 조용히 끊긴다.**
 *
 * [FindPhoneController] 는 같은 일을 하면서도 서비스를 두지 않았다. 근거는 그 클래스
 * 주석에 있다 — 폰찾기는 `CommandHandler` 를 통해서만 시작하고, `CommandHandler` 는
 * `TrackingService`(이미 포그라운드) 안에서만 돈다. **원격 알람에는 그 전제가 없다.**
 * 위치 권한이 꺼진 폰이 정확히 그 반례다: `TrackingService.onCreate` 는 권한이 없으면
 * `stopSelf()` 로 스스로 멈추지만 `AlarmManager` 예약은 그대로 남아 있어서, 알람은
 * 포그라운드 서비스가 하나도 없는 프로세스에서 울게 된다. 오디오 재생 중인 프로세스를
 * 시스템이 조금 봐주기는 하지만 그건 보장이 아니고, 이 앱에서 그 실패는 **완전히
 * 조용하다** — 부모는 알람을 걸었고, 아이는 안 깼고, 어느 화면에도 아무 말이 없다.
 *
 * ## 5분을 어떻게 버티는가
 *
 * 포그라운드 서비스가 도는 동안 그 프로세스는 시스템의 메모리 회수 대상에서 사실상
 * 맨 뒤로 간다. 이 서비스는 [RemoteAlarmController.ring] 이 시작될 때 떠서 알람이
 * **멎을 때** 내려가므로(아래 콜백), 살아 있는 구간이 우는 구간과 정확히 같다.
 * `goAsync()` 로는 대신할 수 없다 — 그건 리시버를 10초 남짓 더 살려 줄 뿐이고,
 * 5분을 버티는 수단이 아니다.
 *
 * ## 왜 `specialUse` 인가
 *
 * `shortService` 는 3분 상한이라 5분짜리 알람을 못 담는다(상한을 넘기면 시스템이
 * 서비스를 끊는다). `mediaPlayback` 은 권한을 하나 더 요구하는 데다 이건 미디어가
 * 아니라 알람이다. `specialUse` 는 [com.kidcare.family.guardian.AlertService] 가 이미
 * 쓰는 타입이라 권한 선언이 매니페스트에 있고, 이 앱은 플레이스토어에 올리지 않는
 * 사이드로드 전용이라(설계서 §1) 심사 사유를 적을 일도 없다.
 *
 * ## 시작이 거부되면
 *
 * 안드로이드 12+ 는 백그라운드에서의 포그라운드 서비스 시작을 막지만, **정확한
 * 알람(`setAlarmClock`)이 울려서 시작되는 경우는 그 예외 목록에 들어 있다.** 그래도
 * 예외가 나면 [RemoteAlarmReceiver] 가 서비스 없이 그대로 울린다 — 회수될 수도 있는
 * 프로세스에서 우는 것이 아예 안 우는 것보다 낫다.
 */
class RemoteAlarmService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // startForeground 를 먼저 부른다 — 시작 뒤 몇 초 안에 부르지 않으면 시스템이
        // 이 서비스를 ANR 로 죽인다. 알림은 컨트롤러가 울릴 때 쓰는 바로 그것이다.
        // 이름은 지금 읽는다: ring() 이 기록을 지우므로 그 뒤에는 읽을 수 없다.
        val label = RemoteAlarmStore(this).label
        try {
            promoteToForeground(RemoteAlarmController.buildRingNotification(this, label))
        } catch (e: Exception) {
            // 포그라운드로 못 올라갔다. 그래도 울린다 — 아래 ring() 이 알림을 직접
            // 띄우므로 아이에게는 '끄기' 손잡이가 그대로 남고, 잃는 것은 프로세스가
            // 5분을 못 채울 수도 있다는 것뿐이다.
            Log.w(TAG, "포그라운드 승격 실패 — 회수될 수 있는 프로세스에서 그대로 울린다", e)
        }

        // 애플리케이션 컨텍스트를 넘긴다 — 컨트롤러가 만드는 물건은 이 서비스보다
        // 오래 살 수 있다(승격에 실패해 서비스가 먼저 죽는 갈래).
        RemoteAlarmController.ring(applicationContext) {
            // 알람이 멎었으면 이 서비스가 있을 이유도 끝났다. REMOVE 로 알림까지 확실히
            // 거둔다 — 포그라운드로 떠 있는 동안에는 cancel() 이 먹지 않아서, 이 줄이
            // 없으면 아이 폰에 아무 일도 안 하는 알람 알림 하나가 남는다.
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }

        // 되살리지 않는다. ring() 이 기록을 이미 지웠으므로 시스템이 intent 없이 이
        // 서비스를 되살리면 다 끝난 알람을 한 번 더 울리게 된다.
        return START_NOT_STICKY
    }

    /** 이름을 다르게 둔 이유는 [TrackingService.promoteToForeground] 와 같다. */
    private fun promoteToForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                RemoteAlarmController.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            // API 33 이하에는 specialUse 타입 자체가 없다. 타입 없이 부르면 매니페스트에
            // 적힌 타입이 그대로 적용된다([com.kidcare.family.guardian.AlertService] 와 같다).
            startForeground(RemoteAlarmController.NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val TAG = "RemoteAlarmService"

        fun start(context: Context) {
            context.startForegroundService(Intent(context, RemoteAlarmService::class.java))
        }
    }
}
