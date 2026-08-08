package com.kidcare.family.child

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.databinding.ActivityMessageBinding
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * 부모가 보낸 한마디를 아이 폰 화면에 크게 띄우고, '확인했어요' 한 번을 받는다.
 *
 * ## 폰찾기와 같은 것, 다른 것
 *
 * 같은 것은 통로다: 전체화면 인텐트가 달린 알림 하나([show])를 띄우고, 승인이 있으면
 * 시스템이 이 화면을 대신 열어준다([FindPhoneController.showNotification] 과 같은 모양).
 *
 * 다른 것이 셋이다.
 *
 * 1. **소리를 내지 않는다.** [FindPhoneController] 는 알람 스트림으로 재생해 무음·진동을
 *    뚫고, 그러려고 알람 볼륨을 최대로 올렸다가 되돌린다. 메시지는 폰찾기가 아니다 —
 *    여기서는 [AudioManager][android.media.AudioManager] 를 아예 건드리지 않는다.
 *    그래서 이 화면에는 [FindPhoneStateStore] 같은 복구 기록도 없다: 되돌릴 것을 애초에
 *    만들지 않았으므로 프로세스가 죽어도 아이 폰에 남는 흔적이 없다.
 * 2. **잠금화면을 강제로 깨우지 않는다.** 폰찾기 화면은 `setShowWhenLocked` 와
 *    `setTurnScreenOn` 으로 잠금 위에 뜨고 화면까지 켠다 — 폰을 못 찾는 상황이라 그게
 *    맞다. 메시지는 아이가 폰을 집을 때까지 기다려도 되는 일이라 그 둘을 쓰지 않는다
 *    (매니페스트에도 `showOnLockScreen` 류 속성이 없다). 잠긴 폰에서는 알림줄에 남아
 *    있다가 아이가 폰을 열면 그때 보인다.
 * 3. **자녀 폰이 done 을 자동으로 적지 않는다.** [CommandHandler] 는 이 명령을
 *    delivered 까지만 밀어두고 빠진다. done 은 아래 '확인했어요'가 적고, 그게 부모
 *    화면의 '읽음'이 된다 — 아이가 답하는 유일한 통로다.
 *
 * ## 무음·방해금지에서도 뜨게 하는 방법
 *
 * 폰찾기는 알람 스트림(USAGE_ALARM)으로 그걸 뚫지만 그건 소리 쪽 장치라 여기서 쓸 수
 * 없다. 대신 채널에 방해금지 예외를 준다([createChannel] 의 `setBypassDnd`) — 우리는
 * 이미 `ACCESS_NOTIFICATION_POLICY` 를 쓰는 앱이고, 그 접근이 아직 안 켜져 있으면
 * 시스템이 이 설정만 조용히 무시할 뿐 예외는 나지 않는다.
 *
 * ## 메시지가 둘 이상 왔을 때
 *
 * 알림은 **명령마다 하나**다([notificationId]). 화면은 하나(`singleTask`)라 나중에 온
 * 메시지가 앞의 것을 덮지만, 앞 메시지의 알림은 알림줄에 그대로 남아 있다 — 아이가 그걸
 * 다시 눌러 읽고 확인할 수 있다. 즉 화면에서는 교체, 알림줄에서는 쌓임이고, 어느 쪽으로도
 * 먼저 온 메시지가 **소리 없이 사라지지는 않는다.** 알림을 하나로 합치지 않은 이유가
 * 이것이고, 알림을 [NotificationCompat.Builder.setOngoing] 으로 둔 이유도 같다: 확인
 * 버튼을 누르기 전에는 손가락 한 번에 쓸려 나가지 않아야 한다.
 */
class MessageActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMessageBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMessageBinding.inflate(layoutInflater)
        setContentView(binding.root)
        render()
    }

    /**
     * `singleTask` 라 이 화면이 떠 있는 동안 두 번째 메시지가 오면 새 인스턴스가 아니라
     * 여기로 들어온다. [setIntent] 를 반드시 먼저 불러야 한다 — 안 부르면 화면에는 새
     * 문장이 뜨는데 '확인했어요'는 **앞 메시지**를 읽음으로 만든다.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render()
    }

    private fun render() {
        binding.messageText.text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
        binding.messageAckButton.isEnabled = true
        binding.messageAckButton.setOnClickListener { acknowledge() }
    }

    /**
     * 아이가 답하는 유일한 통로. 명령을 done 으로 밀어 부모 화면을 '읽음'으로 바꾼다.
     *
     * 서버 확인을 [ACK_WAIT_MILLIS] 까지만 기다리고 화면을 닫는다. Firestore 는
     * `update()` 를 부르는 순간 로컬에 적어 두고 나중에 서버로 보내므로, 여기서 기다림을
     * 끊어도 '읽음'은 인터넷이 붙는 대로 부모 폰에 도착한다. 기다림을 안 끊으면 지하철에
     * 있는 아이가 다 읽은 화면 앞에 붙잡혀 있게 된다 — 그건 이 화면이 할 일이 아니다.
     *
     * 로그인부터 확인하는 이유는 [com.kidcare.family.guardian.AlertService.subscribe] 와
     * 같다: 프로세스가 갓 떴으면(알림만 남고 앱이 죽어 있던 경우) Firebase 가 저장해 둔
     * 익명 세션을 아직 복원하지 못했을 수 있고, 그 상태로 쓰면 규칙이 `request.auth` 를
     * 못 봐서 거부한다.
     */
    private fun acknowledge() {
        val familyId = intent.getStringExtra(EXTRA_FAMILY_ID).orEmpty()
        val childUid = intent.getStringExtra(EXTRA_CHILD_UID).orEmpty()
        val commandId = intent.getStringExtra(EXTRA_COMMAND_ID).orEmpty()

        binding.messageAckButton.isEnabled = false
        // 알림은 쓰기 결과를 기다리지 않고 곧바로 거둔다. 결과를 기다렸다 거두면
        // 인터넷이 느릴 때 방금 확인한 메시지가 알림줄에 남아 "안 눌렸나?"로 읽힌다.
        NotificationManagerCompat.from(this).cancel(notificationId(commandId))

        if (familyId.isEmpty() || childUid.isEmpty() || commandId.isEmpty()) {
            // 여기까지 올 길이 없어야 정상이다(알림을 만든 쪽이 셋을 항상 넣는다).
            // 그래도 왔다면 아이에게 사과할 일은 아니므로 화면만 닫는다.
            Log.w(TAG, "명령 정보가 없는 메시지 화면 — 읽음 표시 없이 닫는다")
            finish()
            return
        }

        lifecycleScope.launch {
            try {
                withTimeoutOrNull(ACK_WAIT_MILLIS) {
                    AuthGateway.signIn()
                    CommandRepository.markDone(familyId, childUid, commandId)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 아이가 여기서 할 수 있는 일이 없다. 부모 화면은 계속 '아직 안 읽음'
                // 으로 남는데, 그건 거짓말이 아니라 사실이다.
                Log.w(TAG, "읽음 표시 실패 — 부모 화면은 '안 읽음'으로 남는다", e)
            }
            finish()
        }
    }

    companion object {

        private const val TAG = "MessageActivity"
        private const val CHANNEL_ID = "parent_message"

        /** 서버 확인을 여기까지만 기다린다. 자세한 이유는 [acknowledge] 참고. */
        private const val ACK_WAIT_MILLIS = 3_000L

        private const val EXTRA_FAMILY_ID = "family_id"
        private const val EXTRA_CHILD_UID = "child_uid"
        private const val EXTRA_COMMAND_ID = "command_id"
        private const val EXTRA_TEXT = "text"

        /**
         * 메시지 알림이 쓰는 ID 대역의 시작. 다른 알림(위치 공유 1001, 폰찾기 1002,
         * 보호자 쪽 1101·1102)과 겹치지 않게 멀찍이 떨어뜨렸다.
         */
        private const val NOTIFICATION_ID_BASE = 1_200_000

        /**
         * 명령 하나가 쓰는 알림 ID **이자 PendingIntent 요청 코드**.
         *
         * 요청 코드를 같이 나누는 것이 핵심이다. 메시지 둘이 같은 요청 코드를 쓰면
         * `FLAG_UPDATE_CURRENT` 가 앞 PendingIntent 의 extra 를 뒤 메시지 것으로 덮어써서,
         * 아이가 알림줄에 남은 **첫 메시지**를 눌러도 두 번째 문장이 뜨고 확인은 두 번째
         * 명령에 찍힌다 — 첫 메시지가 소리 없이 사라지는 바로 그 경로다.
         *
         * 문서 ID 의 해시 하위 16비트를 쓴다. 서로 다른 두 메시지가 같은 칸에 떨어질 확률은
         * 6만분의 1이고, 그러려면 그 둘이 동시에 안 읽힌 채 떠 있어야 한다.
         */
        private fun notificationId(commandId: String): Int =
            NOTIFICATION_ID_BASE + (commandId.hashCode() and 0xFFFF)

        /**
         * 메시지 알림을 띄운다. 실제로 띄웠으면 true.
         *
         * false 를 돌려주는 경우는 하나다: 아이 폰에서 알림 자체가 꺼져 있어 무엇을 해도
         * 아이 눈에 닿지 않는 상태. 그때는 [CommandHandler] 가 명령을 실패로 적어 부모에게
         * 사실대로 알린다 — 안 뜬 메시지를 done 으로 끝내면 부모는 아이가 읽었다고 읽는다.
         *
         * 전체화면 인텐트는 **되면 좋은 것**으로 둔다. 안드로이드 14(API 34)부터
         * `USE_FULL_SCREEN_INTENT` 는 전화·알람 앱이 아니면 자동 승인되지 않는데
         * ([FindPhoneController.showNotification] 과 같은 사정), 그래도 메시지는 도착한다:
         * 채널이 IMPORTANCE_HIGH 라 화면 위로 떠오르는 알림(헤드업)으로 오고, 본문 전체를
         * [NotificationCompat.BigTextStyle] 로 담아 두므로 **알림만으로도 다 읽을 수 있다.**
         * 아이가 그 알림을 누르면 이 화면이 열려 '확인했어요'를 누를 수 있다.
         *
         * 여기서 [Context.startActivity] 로 화면을 직접 띄우지 않는 이유: 안드로이드 10부터
         * 백그라운드 앱의 화면 띄우기는 막혀 있고, 포그라운드 서비스가 돌고 있다는 것만으로는
         * 예외가 되지 않는다. 막힌 길로 걸어 봐야 조용히 아무 일도 안 일어난다.
         */
        @SuppressLint("MissingPermission")
        fun show(
            context: Context,
            familyId: String,
            childUid: String,
            commandId: String,
            text: String,
        ): Boolean {
            val manager = context.getSystemService(NotificationManager::class.java)
            createChannel(context, manager)

            // 앱 전체 알림과 이 채널을 따로 본다. 아이가 이 채널 하나만 꺼 두면 앱 전체는
            // 켜져 있는 것으로 보이는데, 그 상태로 알림을 쏘면 시스템이 조용히 버린다 —
            // 명령은 done 도 failed 도 아닌 채 남고 부모는 아무것도 모른다. 이 앱의 위협
            // 모델에는 아이 본인이 들어 있다(firestore.rules 주석).
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled() ||
                manager.getNotificationChannel(CHANNEL_ID)?.importance ==
                NotificationManager.IMPORTANCE_NONE
            ) {
                Log.w(TAG, "알림이 꺼져 있어 메시지를 띄울 수 없다")
                return false
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // 값 자체는 아무것도 바꾸지 않는다. "왜 전체화면이 안 떴나"를 나중에
                // logcat 에서 바로 볼 수 있게 남기는 것뿐이다(폰찾기와 같은 이유).
                Log.i(TAG, "전체화면 알림 가능 여부(API 34+): ${manager.canUseFullScreenIntent()}")
            }

            val id = notificationId(commandId)
            val open = PendingIntent.getActivity(
                context, id,
                Intent(context, MessageActivity::class.java)
                    .putExtra(EXTRA_FAMILY_ID, familyId)
                    .putExtra(EXTRA_CHILD_UID, childUid)
                    .putExtra(EXTRA_COMMAND_ID, commandId)
                    .putExtra(EXTRA_TEXT, text),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_chat)
                .setContentTitle(context.getString(R.string.message_notification_title))
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                // 확인 버튼을 누르기 전에는 손가락 한 번에 쓸려 나가지 않게 한다
                // (클래스 주석 "메시지가 둘 이상 왔을 때" 참고).
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(open)
                .setFullScreenIntent(open, true)
                .build()

            NotificationManagerCompat.from(context).notify(id, notification)
            return true
        }

        /**
         * 채널을 만든다. 이 채널의 성격이 곧 이 기능의 성격이다 — 진동 한 번, 소리 없음.
         *
         * 채널 설정은 **만들 때 한 번만** 먹는다(만든 뒤 값을 바꿔도 시스템이 무시한다).
         * 그래서 소리를 끄는 일도, 방해금지 예외도 전부 여기서 결정된다.
         */
        private fun createChannel(context: Context, manager: NotificationManager) {
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.channel_message),
                    // "지금 봐야 한다"라서 HIGH 다. 낮추면 알림줄에 조용히 쌓이기만 하는데,
                    // 그건 앱을 열어야 보는 것과 같다(AlertService 의 사건 채널과 같은 판단).
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    // 소리 없음. 메시지는 폰찾기가 아니다 — 수업 중인 아이 폰이 울면
                    // 그 다음에 벌어지는 일은 아이가 이 앱을 끄는 것이다.
                    setSound(null, null)
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 400)
                    // 무음·방해금지에서도 화면은 떠야 한다(클래스 주석). 알림 정책 접근이
                    // 아직 안 켜진 폰에서는 이 한 줄이 조용히 무시될 뿐 예외는 안 난다.
                    setBypassDnd(true)
                },
            )
        }
    }
}
