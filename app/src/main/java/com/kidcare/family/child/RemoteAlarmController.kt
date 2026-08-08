package com.kidcare.family.child

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.kidcare.family.R
import kotlinx.coroutines.CancellationException
import java.time.Instant
import java.time.ZoneId

/**
 * 부모가 걸어 준 알람시계 하나. 거는 것도, 울리는 것도, 되살리는 것도 여기다.
 *
 * ## 시각은 아이 폰이 푼다
 *
 * 부모 폰이 보내오는 것은 **하루 안의 분**(0~1439) 하나뿐이고
 * ([com.kidcare.family.core.model.CommandType.PAYLOAD_AT_MINUTE_OF_DAY]), "오늘 그 시각,
 * 이미 지났으면 내일"은 [resolveTrigger] 가 이 폰의 시계·시간대로 푼다. 부모 폰에서
 * 절대 시각(epoch)을 계산해 보내면 두 폰의 시간대·시계 차이가 그대로 어긋남이 된다 —
 * 4단계에서 즉시 변경의 해제 시각을 같은 이유로 이쪽으로 옮겼다.
 *
 * ## 왜 [AlarmManager.setAlarmClock] 인가 (두 가지다)
 *
 * 1. **Doze 를 확실히 뚫는다.** `setExactAndAllowWhileIdle` 은 절전 상태에서 호출 빈도가
 *    제한되고 실제 발화가 늦춰질 수 있지만, `setAlarmClock` 은 사용자가 맞춘 알람시계로
 *    취급돼 그 제한 밖이다. 알람시계에서 "몇십 분 늦게 울림"은 안 울린 것과 같다.
 * 2. **상태바에 알람 아이콘이 뜬다.** 즉 **아이도 알람이 걸린 것을 안다.** 이 앱은 몰래
 *    하지 않는다(설계서 §1). 아이콘을 누르면 [AlarmManager.AlarmClockInfo] 의 showIntent
 *    로 [ChildHomeActivity] 가 열려 "엄마 아빠랑 이어져 있어요" 화면을 본다.
 *
 * ## 볼륨을 건드리지 않는다
 *
 * [FindPhoneController] 는 알람 볼륨을 최대로 올렸다가 되돌린다 — 소파 밑에 있는 폰을
 * 찾아야 하니 그게 맞다. 알람시계는 **아이 옆에 있는 폰**이라 그 이유가 통째로 없어진다.
 * 그래서 여기서는 [android.media.AudioManager] 를 아예 만지지 않고 폰에 설정된 알람
 * 볼륨 그대로 운다. 그 결정이 곧 이 클래스에 볼륨 복구 기록이 없는 이유이기도 하다 —
 * 강제 종료로 아이 폰 볼륨이 밤새 최대로 남았던 사고(`FindPhoneStateStore` 주석)는
 * **되돌릴 것을 애초에 만들지 않아서** 여기서는 일어날 수 없다.
 *
 * ## 알람은 하나뿐이다
 *
 * 예약 칸이 하나고([RemoteAlarmStore]), 새로 걸면 앞의 것을 덮는다. 여럿을 두면 부모
 * 화면이 목록과 "이 중 무엇을 지울까"를 갖게 되고, 취소 명령도 어느 것인지 골라야 한다.
 * 이 통로는 알람 앱이 아니라 "지금 아이를 한 번 깨우는" 손잡이라 하나로 충분하다.
 *
 * ## 5분이면 스스로 멈춘다
 *
 * 아이가 못 듣거나 무시해도 수업 시간 내내 울지 않는다([FindPhoneController] 와 같은 값,
 * 설계서 §4.5). 스누즈는 두지 않았다 — 근거는 [showNotification] 참고.
 */
object RemoteAlarmController {

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private var autoStop: Runnable? = null

    /**
     * 지금 울리고 있는가. [player] 유무로 판단하지 않는 이유는 [FindPhoneController.ringing]
     * 과 같다 — 벨소리 URI 를 못 찾아 진동만 울리는 갈래에서도 5분 타이머와 알림 정리
     * 의무는 그대로 살아 있는 "진행 중" 세션이다.
     */
    private var ringing = false

    // ------------------------------------------------------------------ 걸기·끄기

    /**
     * 알람을 건다. 걸었으면 true, 정확한 알람을 걸 수 없어 안 걸었으면 false.
     *
     * false 를 부정확한 알람으로 조용히 바꿔치지 않는 이유는
     * [com.kidcare.family.core.model.CommandType.ERROR_ALARM_EXACT_DENIED] 주석에 적었다.
     */
    fun set(context: Context, minuteOfDay: Int, label: String): Boolean {
        val manager = context.getSystemService(AlarmManager::class.java)
        if (manager == null) {
            Log.w(TAG, "AlarmManager 서비스를 못 얻어 알람을 걸지 못했다")
            return false
        }
        if (!canScheduleExact(manager)) {
            Log.w(TAG, "canScheduleExactAlarms=false — 알람을 걸지 않고 실패로 돌려준다")
            return false
        }
        val at = resolveTrigger(minuteOfDay, System.currentTimeMillis())
        // 예약보다 **먼저** 적는다. 순서를 바꾸면 그 사이에 프로세스가 죽었을 때
        // 예약만 남고 기록이 없어, 재부팅 뒤 되살릴 근거가 사라진다.
        RemoteAlarmStore(context).save(at, minuteOfDay, label)
        register(context, manager, at)
        Log.i(TAG, "원격 알람 등록: minuteOfDay=$minuteOfDay at=$at")
        return true
    }

    /**
     * 걸린 알람을 지운다. **지금 울리고 있으면 함께 멈춘다** — 부모가 '알람 끄기'를
     * 눌렀는데 울고 있는 폰이 계속 우는 것은 취소가 아니다.
     *
     * 걸린 것이 없어도 조용히 지나간다: [AlarmManager.cancel] 은 없는 예약에 대해
     * 아무 일도 안 하고, [stop] 도 널 안전하다.
     */
    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(triggerIntent(context))
        RemoteAlarmStore(context).clear()
        stop(context)
        Log.i(TAG, "원격 알람 취소")
    }

    // ------------------------------------------------------------------ 되살리기

    /**
     * 프로세스가 새로 뜰 때([TrackingService.onCreate])와 재부팅 직후
     * ([ScheduleAlarmReceiver])에 부른다.
     *
     * **재부팅과 강제 종료는 `AlarmManager` 예약을 통째로 지운다.** 여기서 다시 걸지
     * 않으면 부모가 맞춰 둔 알람이 아무 흔적도 없이 사라진다. 저장해 둔 절대 시각을
     * 그대로 다시 거는 것이 핵심이다 — [reresolve] 처럼 분 단위로 다시 풀면 "오늘 22시에
     * 맞춰 둔 내일 07시 알람"이 재부팅 한 번에 오늘 07시(이미 지남)로 잘못 풀린다.
     *
     * 이미 지난 알람은 **늦게 울리지 않고 지운다.** 세 시간 늦은 알람은 알람이 아니라
     * 놀람이고, 그 시각에 아이는 이미 학원에 있거나 자고 있다.
     *
     * 알림을 무조건 한 번 거두는 이유: 울리는 도중 프로세스가 죽으면 소리는 프로세스와
     * 함께 멎지만 알림은 시스템이 들고 있어 그대로 남는다 — 아무리 눌러도 소리가 안 나는
     * 알림 하나가 아이 폰에 붙박이로 남는 셈이다. 이 시점에 이 프로세스가 울리고 있을 수
     * 없다는 근거는 [FindPhoneController.recoverIfNeeded] 와 같다(명령 리스너는 이보다
     * 나중에 걸린다).
     */
    fun recoverIfNeeded(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)

        val store = RemoteAlarmStore(context)
        if (!store.isSet) return
        if (store.atMillis <= System.currentTimeMillis()) {
            Log.w(TAG, "걸어 둔 원격 알람이 이미 지났다 — 늦게 울리지 않고 지운다: at=${store.atMillis}")
            store.clear()
            return
        }
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        register(context, manager, store.atMillis)
        Log.i(TAG, "원격 알람 재등록: at=${store.atMillis}")
    }

    /**
     * 폰 시각이나 시간대가 바뀌었을 때 부른다([ScheduleAlarmReceiver]).
     *
     * 걸어 둔 절대 밀리초는 시계가 바뀌는 순간 더 이상 부모가 고른 "07:00"이 아니다.
     * 그래서 여기서만은 [RemoteAlarmStore.minuteOfDay] 로 처음부터 다시 푼다 — 아이가
     * 폰 시각을 앞으로 돌려 알람을 지나가게 만드는 것도 이 한 번으로 막힌다.
     */
    fun reresolve(context: Context) {
        val store = RemoteAlarmStore(context)
        val minuteOfDay = store.minuteOfDay
        if (!store.isSet || minuteOfDay !in 0..MAX_MINUTE_OF_DAY) return
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val at = resolveTrigger(minuteOfDay, System.currentTimeMillis())
        store.save(at, minuteOfDay, store.label)
        register(context, manager, at)
        Log.i(TAG, "시각·시간대가 바뀌어 원격 알람을 다시 풀었다: minuteOfDay=$minuteOfDay at=$at")
    }

    // ------------------------------------------------------------------ 울리기

    /**
     * 알람이 울 시각이 됐다([RemoteAlarmReceiver] 가 부른다).
     *
     * 기록을 **울리기 전에** 지운다. 이 알람은 한 번만 우는 것이고, 지우지 않으면 우는
     * 도중 프로세스가 죽었을 때 다음 프로세스의 [recoverIfNeeded] 가 이미 울린 알람을
     * 다시 걸어 버린다.
     */
    fun ring(context: Context) {
        if (ringing) return
        ringing = true

        val store = RemoteAlarmStore(context)
        val label = store.label
        store.clear()

        player = buildPlayer(context)
        vibrator = vibratorOf(context).also {
            it.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 600), 0))
        }
        showNotification(context, label)

        autoStop = Runnable {
            Log.i(TAG, "5분이 지나 원격 알람을 자동으로 멈춘다")
            stop(context)
        }.also { handler.postDelayed(it, AUTO_STOP_MILLIS) }

        Log.i(TAG, if (player != null) "원격 알람 울림" else "원격 알람 울림 (소리 없이 진동만)")
    }

    /**
     * 알람을 멈춘다. 아이가 알림을 누르거나, 부모가 취소하거나, 5분이 지났을 때.
     *
     * 울리고 있지 않을 때 불려도(중복 취소 등) 아래 줄들이 전부 널 안전이라 조용히 지나간다.
     */
    fun stop(context: Context) {
        autoStop?.let { handler.removeCallbacks(it) }
        autoStop = null

        player?.runCatching { stop(); release() }
        player = null

        vibrator?.cancel()
        vibrator = null

        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        ringing = false
    }

    /**
     * 알람음 재생기를 준비한다. 실패를 밖으로 내보내지 않고 null 로 물러나 "소리 없이
     * 진동만"으로 격하시키는 판단은 [FindPhoneController.buildPlayer] 와 같다 — 기본
     * 알람음이 지정 안 된 롬이나 미디어스토어가 안 채워진 기기에서 실제로 벌어진다.
     */
    private fun buildPlayer(context: Context): MediaPlayer? {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        if (uri == null) {
            Log.w(TAG, "알람음·벨소리 URI 를 둘 다 못 찾음 — 소리 없이 진동만 울린다")
            return null
        }
        val candidate = MediaPlayer()
        return try {
            candidate.apply {
                // USAGE_ALARM: 알람 스트림으로 재생하므로 링거가 무음·진동이어도 울린다.
                // 볼륨은 **건드리지 않는다** — 폰에 설정된 알람 볼륨 그대로다(클래스 주석).
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(context, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "알람음 준비 실패 — 소리 없이 진동만 울린다: uri=$uri", e)
            candidate.runCatching { release() }
            null
        }
    }

    /**
     * 울리는 동안 뜨는 알림. 아이가 알람을 끄는 **유일한** 손잡이라 두 군데를 다 끄기로 뒀다 —
     * 액션 버튼('알람 끄기')과 알림 본문 자체. 자다 깬 아이의 손가락에 작은 버튼 하나만
     * 주면 안 된다.
     *
     * **스누즈는 두지 않았다.** 다시 울리려면 두 번째 예약과 그 예약의 재부팅 복구, 스누즈
     * 횟수 상한이 통째로 따라오는데, 그보다 큰 이유는 이 알람이 **부모가 건 알람**이라는
     * 것이다 — "학원 가야 해"를 아이가 9분씩 미룰 수 있으면 이 기능이 하려던 일이 사라진다.
     * 아이가 무시해도 5분이면 스스로 멈추므로 영원히 울지는 않는다([ring]).
     *
     * 별도 전체화면 액티비티를 만들지 않은 이유: 화면을 띄워도 거기 있는 것은 결국 '끄기'
     * 버튼 하나다. 안드로이드 14+ 는 `USE_FULL_SCREEN_INTENT` 를 자동 승인하지 않으므로
     * ([FindPhoneController.showNotification] 과 같은 사정) 그 화면은 어차피 "되면 좋은 것"
     * 인데, 헤드업 알림은 항상 뜬다. 있으면 좋은 것 하나를 위해 확실한 것을 복잡하게 만들지
     * 않았다.
     */
    @SuppressLint("MissingPermission")
    private fun showNotification(context: Context, label: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.channel_remote_alarm),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    // 소리·진동은 이 오브젝트가 알람 스트림과 Vibrator 로 직접 낸다.
                    // 채널까지 소리를 내면 두 겹으로 울린다.
                    setSound(null, null)
                    enableVibration(false)
                    setBypassDnd(true)
                }
            )
        }

        val stop = PendingIntent.getBroadcast(
            context, REQUEST_CODE_STOP,
            Intent(context, RemoteAlarmReceiver::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label.ifBlank { context.getString(R.string.remote_alarm_title) })
            .setContentText(context.getString(R.string.remote_alarm_notification_text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            // 잠금화면에서도 제목과 끄기 버튼이 보여야 한다. 담긴 내용이 부모가 붙인
            // 짧은 이름 한 줄뿐이라 메시지(VISIBILITY_PRIVATE)와 판단이 다르다.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(stop)
            .addAction(0, context.getString(R.string.remote_alarm_stop), stop)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    // ------------------------------------------------------------------ 도구

    /**
     * 하루 안의 분을 "오늘 그 시각, 이미 지났으면 내일"로 푼다.
     *
     * `LocalDate.atTime(...).atZone(zone)` 을 쓰는 이유: 서머타임으로 존재하지 않는 시각
     * (봄에 건너뛰는 한 시간)을 골라도 `atZone` 이 앞으로 밀어 유효한 순간으로 만들어 준다.
     * `plusMinutes` 로 자정에서 더해 올라가면 그 처리가 조용히 달라진다. 한국은 서머타임이
     * 없지만 이 함수는 폰의 시간대를 그대로 따르므로 여행 중인 폰에서도 맞아야 한다.
     *
     * **경계 판정은 `>` 다**: 고른 시각이 1초라도 남아 있으면 오늘로 둔다. 30초 뒤를 고른
     * 부모가 24시간을 기다리게 되는 쪽이, 이미 지난 시각이 곧바로 우는 쪽보다 훨씬 나쁘다 —
     * 앞의 것은 아무 화면에도 안 나타나는 침묵이고, 뒤의 것은 즉시 보이고 끌 수 있다.
     */
    private fun resolveTrigger(minuteOfDay: Int, nowMillis: Long): Long {
        val zone = ZoneId.systemDefault()
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val hour = minuteOfDay / 60
        val minute = minuteOfDay % 60
        val today = now.toLocalDate().atTime(hour, minute).atZone(zone).toInstant().toEpochMilli()
        if (today > nowMillis) return today
        return now.toLocalDate().plusDays(1).atTime(hour, minute).atZone(zone)
            .toInstant().toEpochMilli()
    }

    /**
     * [AlarmManager.setAlarmClock] 으로 건다. 권한이 없을 때만 정확 알람으로 물러난다.
     *
     * [set] 이 이미 같은 것을 확인하고 실패로 돌려주는데도 여기서 또 확인하는 이유:
     * [recoverIfNeeded]·[reresolve] 는 부모에게 실패를 말할 통로가 없다(명령이 이미 끝난
     * 뒤다). 그때는 아무것도 안 거는 것보다 조금 늦을지 모르는 알람이라도 거는 편이 낫다.
     * 물러날 때는 반드시 로그를 남긴다 — 안 남기면 "가끔 늦게 울린다"는 진단 불가능한
     * 증상이 된다(`ScheduleApplier.scheduleBoundaryAlarm` 과 같은 규율).
     */
    private fun register(context: Context, manager: AlarmManager, atMillis: Long) {
        val trigger = triggerIntent(context)
        if (canScheduleExact(manager)) {
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(atMillis, showIntent(context)), trigger)
            return
        }
        Log.w(
            TAG,
            "canScheduleExactAlarms=false — setAlarmClock 대신 setExactAndAllowWhileIdle 로 " +
                "물러난다. 절전 상태에서 늦게 울릴 수 있다: at=$atMillis",
        )
        manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, trigger)
    }

    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()

    /**
     * 알람이 울 때 깨어날 PendingIntent. 고정 요청 코드라 다시 걸면 새 예약을 쌓지 않고
     * 기존 것을 교체하고, `cancel()` 도 같은 것을 다시 얻어 정확히 그 예약을 지운다
     * (`ScheduleApplier.alarmPendingIntent` 와 같은 판단). 시스템이 extra 를 채워 넣을 일이
     * 없으므로 FLAG_IMMUTABLE 이 맞다.
     */
    private fun triggerIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, REQUEST_CODE_TRIGGER,
        Intent(context, RemoteAlarmReceiver::class.java).setAction(ACTION_RING),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** 상태바 알람 아이콘을 눌렀을 때 열리는 화면. 아이가 "무슨 알람이지?"를 볼 자리다. */
    private fun showIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context, REQUEST_CODE_SHOW,
        Intent(context, ChildHomeActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun vibratorOf(context: Context): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    /** [RemoteAlarmReceiver] 가 "울려라"와 "꺼라"를 가르는 값. */
    const val ACTION_RING = "com.kidcare.family.child.ACTION_RING_ALARM"
    const val ACTION_STOP = "com.kidcare.family.child.ACTION_STOP_ALARM"

    /** [com.kidcare.family.core.model.CommandType.PAYLOAD_AT_MINUTE_OF_DAY] 의 상한. */
    const val MAX_MINUTE_OF_DAY = 1439

    private const val TAG = "RemoteAlarm"

    /** [FindPhoneController] 와 같은 5분(설계서 §4.5). */
    private const val AUTO_STOP_MILLIS = 5 * 60 * 1000L

    private const val CHANNEL_ID = "remote_alarm"

    /** 위치 공유 1001, 폰찾기 1002 다음 칸. */
    private const val NOTIFICATION_ID = 1003

    private const val REQUEST_CODE_TRIGGER = 5001
    private const val REQUEST_CODE_STOP = 5002
    private const val REQUEST_CODE_SHOW = 5003
}
