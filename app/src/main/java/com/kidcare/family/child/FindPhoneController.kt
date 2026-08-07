package com.kidcare.family.child

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioManager
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
import androidx.core.content.ContextCompat
import com.kidcare.family.R

/**
 * 폰찾기 벨. 알람 스트림으로 재생하므로 벨소리가 무음·진동이어도 울린다.
 *
 * 5분이 지나면 스스로 멈춘다(설계서 §4.5). 부모가 중지 명령을 못 보내는 상황
 * — 부모 폰 배터리가 나갔다든지 — 에서 아이 폰이 수업 시간 내내 울리는 사고를 막는다.
 *
 * 알람 볼륨을 최대로 올리기 전에 원래 값을 기억했다가 멈출 때 되돌린다.
 * 안 그러면 아이 폰의 알람 소리가 영구히 최대가 된다.
 *
 * CommandHandler 는 TrackingService 안에서만 이 오브젝트를 부른다(Task 3) — 즉
 * 벨이 울리는 동안은 그 서비스가 이미 포그라운드로 띄워 둔 프로세스 안에서
 * 실행된다는 뜻이다. 그래서 여기서 별도 포그라운드 서비스를 새로 시작하지 않는다.
 */
object FindPhoneController {

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var savedAlarmVolume: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    private var autoStop: Runnable? = null

    // 알림의 중지 액션이 눌리는 순간 화면을 열지 않고 바로 벨을 끄기 위한
    // 수신자. start() 에서 등록하고 stop() 에서 반드시 해제한다 —
    // TrackingService.ringerReceiver 와 같은 이유로, 해제를 빼먹으면 벨이 없을
    // 때도 계속 살아있는 leak 이 된다.
    private var stopReceiver: BroadcastReceiver? = null

    val isRinging: Boolean get() = player != null

    fun start(context: Context) {
        // 이미 울리고 있으면 아무것도 하지 않는다 — 부모가 두 번 누르거나
        // Firestore 스냅샷이 같은 명령을 다시 흘려보내도(CommandHandler 의
        // handled 중복 제거로 대부분 걸러지지만, 재시작 직후처럼 걸러지지
        // 않는 경로가 있어도) 여기서 한 번 더 막는다. 두 번째 MediaPlayer가
        // 겹쳐 시작되면 소리가 두 겹으로 울리고, 저장해 둔 원래 볼륨값도
        // 두 번째 호출이 "이미 최대로 올려놓은 값"으로 덮어써 버려 stop() 이
        // 원래 값이 아니라 최대값으로 복구하는 사고로 이어진다.
        if (isRinging) return

        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        savedAlarmVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        audio.setStreamVolume(
            AudioManager.STREAM_ALARM,
            audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            0,
        )

        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        player = MediaPlayer().apply {
            // USAGE_ALARM 이 핵심이다 — 벨소리 스트림이 아니라 알람 스트림으로
            // 재생하므로 링거가 무음·진동이어도, 방해 금지 접근 권한이 전혀
            // 없어도 그대로 울린다(RingerController.hasDndAccess 와 무관한 경로).
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

        vibrator = vibratorOf(context).also {
            it.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0))
        }

        stopReceiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                stop(context)
            }
        }.also {
            ContextCompat.registerReceiver(
                context, it, IntentFilter(ACTION_STOP), ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        }

        showNotification(context)

        autoStop = Runnable {
            Log.i(TAG, "5분이 지나 폰찾기를 자동으로 멈춘다")
            stop(context)
        }.also { handler.postDelayed(it, AUTO_STOP_MILLIS) }

        Log.i(TAG, "폰찾기 시작")
    }

    fun stop(context: Context) {
        // 울리고 있지 않을 때(STOP_FIND 가 중복으로 오거나, 5분 자동 정지 뒤에
        // 부모가 뒤늦게 중지를 또 누르는 경우) 아래 줄들은 전부 null-안전
        // 호출이라 예외 없이 그냥 아무 일도 안 하고 지나간다.
        autoStop?.let { handler.removeCallbacks(it) }
        autoStop = null

        player?.runCatching { stop(); release() }
        player = null

        vibrator?.cancel()
        vibrator = null

        stopReceiver?.let { context.unregisterReceiver(it) }
        stopReceiver = null

        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)

        savedAlarmVolume?.let {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.setStreamVolume(AudioManager.STREAM_ALARM, it, 0)
        }
        savedAlarmVolume = null
        Log.i(TAG, "폰찾기 중지")
    }

    /**
     * 중지 액션이 달린 헤드업 알림을 띄우고, 전체화면도 함께 건다.
     *
     * 안드로이드 14(API 34)부터 USE_FULL_SCREEN_INTENT 는 전화·알람 앱이
     * 아니면 자동으로 승인되지 않는다 — 그래서 전체화면은 "되면 좋은 것"으로
     * 두고, 소리·진동은(위에서 이미 시작했으니) 그와 무관하게 울린다. 전체
     * 화면이 안 떠도 헤드업 알림과 중지 버튼은 항상 뜬다.
     */
    @SuppressLint("MissingPermission")
    private fun showNotification(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.channel_find_phone),
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // canUseFullScreenIntent 는 API 34부터 있다. 값 자체는 아무 것도
            // 바꾸지 않는다 — 나중에 "전체화면이 왜 안 떴냐"를 진단할 사람이
            // logcat 에서 바로 원인을 볼 수 있게 남겨 두는 것뿐이다.
            Log.i(TAG, "전체화면 알림 가능 여부(API 34+): ${manager.canUseFullScreenIntent()}")
        }

        val openActivity = PendingIntent.getActivity(
            context, REQUEST_CODE_OPEN,
            Intent(context, FindPhoneActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopAction = PendingIntent.getBroadcast(
            context, REQUEST_CODE_STOP,
            Intent(ACTION_STOP).setPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_silent_mode_off)
            .setContentTitle(context.getString(R.string.find_phone_notification_title))
            .setContentText(context.getString(R.string.find_phone_notification_text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(openActivity)
            .setFullScreenIntent(openActivity, true)
            .addAction(0, context.getString(R.string.find_phone_stop), stopAction)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    private fun vibratorOf(context: Context): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    private const val TAG = "FindPhone"
    private const val AUTO_STOP_MILLIS = 5 * 60 * 1000L
    private const val CHANNEL_ID = "find_phone"
    private const val NOTIFICATION_ID = 1002
    private const val REQUEST_CODE_OPEN = 3001
    private const val REQUEST_CODE_STOP = 3002
    private const val ACTION_STOP = "com.kidcare.family.child.ACTION_STOP_FIND"
}
