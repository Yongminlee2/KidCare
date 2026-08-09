package com.kidcare.family.guardian

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.EventRepository
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.model.EventDoc
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 보호자 폰에서 상시 도는 서비스. `events/` 를 구독하다가 새 사건이 오면 이 폰에
 * 로컬 알림을 띄운다.
 *
 * ## 왜 포그라운드 서비스여야 하는가
 *
 * 이 앱에는 FCM 이 없다. 무료 요금제(Spark)에 Cloud Functions 를 안 쓰기로 했고
 * (설계서 Global Constraints), 그러면 **아이 폰이 부모 폰을 깨울 방법이 하나도
 * 없다.** 아이 폰은 Firestore 에 문서를 하나 쓸 뿐이고, 그 사실을 부모 폰이 알려면
 * 부모 폰 쪽에서 누군가 듣고 있어야 한다.
 *
 * 그런데 Firestore 리스너는 앱이 백그라운드로 내려가는 순간 안전하지 않다. 절전
 * (Doze)에 들어가면 소켓이 끊기고, 다시 이어지는 시점은 폰이 정하지 우리가 정하지
 * 않는다. 그렇게 만든 알림은 **부모가 앱을 열었을 때 비로소 뜬다** — 아이가 학교에
 * 도착한 지 세 시간 뒤에 뜨는 도착 알림은 알림이 아니라 기록이다. 알림의 값은
 * 전부 "제때"에 있다.
 *
 * 포그라운드 서비스는 안드로이드가 절전에서 예외로 두는 유일한 정직한 통로이고,
 * 그 대가로 **부모 폰 알림줄에도 표시가 하나 계속 뜬다.** 그 대가를 부모가 치를지는
 * 부모가 정한다 — 그래서 기본값이 꺼짐이고([isEnabled]), 켜기 전에 무엇이 생기는지
 * 알림 탭 맨 위에서 한 줄로 먼저 말한다(`alert_service_hint`).
 *
 * ## 포그라운드 서비스 타입이 specialUse 인 이유
 *
 * 겉보기에는 `dataSync` 가 맞아 보인다. 하지만 안드로이드 15(API 35)부터 `dataSync`
 * 는 **24시간에 6시간**만 돌 수 있고, 넘으면 시스템이 서비스를 끊는다. targetSdk 가
 * 36 이라 그 제한을 그대로 받으므로, 하루의 4분의 3 동안 알림이 안 오는데 화면에는
 * 아무 표시가 없는 상태가 된다 — 이 저장소가 제일 싫어하는 조용한 고장이다.
 * `specialUse` 에는 그 시간 제한이 없다. 플레이스토어라면 심사에서 사유를 대야 하지만
 * 이 앱은 가족끼리 APK 를 직접 까는 배포다(README "배포 방식").
 *
 * ## 재시작 때 옛 사건으로 다시 알리지 않기
 *
 * `at` 으로 거르지 않는다 — 그 이유는 [EventRepository.observeEvents] 주석에 있다.
 * 대신 **이미 알린 문서 ID** 를 이 폰에 적어 둔다([notifiedIds]). 이 판단이 틀리는
 * 두 방향의 대가가 비대칭이라 그렇다: 기억이 사라지면 알림이 한 번 더 뜨고(성가심),
 * 창을 잘못 잡으면 알림이 아예 안 뜬다(고장). 안전한 쪽으로 실패하게 둔다.
 */
class AlertService : LifecycleService() {

    /** onCreate 에서 조건을 통과해 실제로 포그라운드로 올라갔는가. */
    private var active = false

    private var listener: ListenerRegistration? = null
    private var memberListener: ListenerRegistration? = null
    private var subscribeJob: Job? = null
    @Volatile private var childNames: Map<String, String> = emptyMap()

    override fun onCreate() {
        super.onCreate()

        // 조건을 먼저 보고, 아니면 startForeground 를 아예 부르지 않고 stopSelf() 로
        // 끝낸다. TrackingService.onCreate 의 위치 권한 분기와 같은 모양이고 같은
        // 이유다 — 안드로이드가 허용하는 정상 종료 경로라 "startForeground 를 제때
        // 안 불렀다"는 ANR 로 이어지지 않는다.
        val store = RoleStore(this)
        if (store.role != Role.GUARDIAN || !store.isPaired) {
            Log.w(TAG, "보호자 폰이 아니거나 페어링이 안 끝나 시작하지 않는다")
            stopSelf()
            return
        }
        if (!isEnabled(this)) {
            // 부모가 스위치를 껐는데 부팅 신호나 START_STICKY 로 되살아난 경우다.
            Log.i(TAG, "상시 수신이 꺼져 있어 시작하지 않는다")
            stopSelf()
            return
        }
        active = true
        promoteToForeground(ONGOING_NOTIFICATION_ID, buildOngoingNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (!active) return START_NOT_STICKY

        // START_STICKY 재시작에서는 intent 가 null 로 온다. 필요한 것(familyId)은
        // 애초에 extra 가 아니라 RoleStore 에서 읽으므로 그대로 이어서 동작한다
        // (TrackingService.onStartCommand 와 같은 규율).
        val familyId = RoleStore(this).familyId
        if (familyId == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        subscribe(familyId)
        return START_STICKY
    }

    /**
     * 이벤트 구독을 (다시) 건다.
     *
     * 로그인부터 확인하는 이유: 부팅 직후에는 프로세스가 갓 떴을 뿐이라 Firebase 가
     * 저장해 둔 익명 세션을 아직 복원하지 못했을 수 있다. 그 상태로 구독하면 규칙이
     * `request.auth` 를 못 봐서 PERMISSION_DENIED 로 죽고, 서비스는 알림줄에 멀쩡히
     * 떠 있는 채로 **아무것도 안 듣는다.** 실패하면 조용히 포기하지 않고 [RETRY_MILLIS]
     * 마다 다시 시도한다 — 알림줄에 표시를 띄워 놓고 일을 안 하는 것이 제일 나쁘다.
     *
     * 리스너를 매번 먼저 떼는 것은 onStartCommand 가 여러 번 불릴 수 있기 때문이다
     * (TrackingService.subscribeToCommands 와 같은 이유).
     */
    private fun subscribe(familyId: String) {
        subscribeJob?.cancel()
        listener?.remove()
        listener = null

        subscribeJob = lifecycleScope.launch {
            while (isActive) {
                try {
                    AuthGateway.signIn()
                    memberListener?.remove()
                    memberListener = FamilyRepository.observeMembers(
                        familyId,
                        onChange = { members ->
                            childNames = members.filter { it.role == "child" }
                                .associate { it.uid to it.displayName.ifBlank { getString(R.string.child_default_name) } }
                        },
                        onError = { e -> Log.w(TAG, "가족 이름 구독 실패 — 알림에는 기본 아이 이름을 쓴다", e) },
                    )
                    listener = EventRepository.observeEvents(
                        familyId = familyId,
                        // fromCache 는 여기서 안 본다 — 알림은 "새 문서가 보이면 띄운다"
                        // 이고, 캐시본에만 있는 문서는 이 폰이 어차피 서버에서 받아둔
                        // 것이다(부모 폰은 events/ 에 쓰지 않는다). 재연결로 같은 문서가
                        // 다시 흘러와도 [notifiedIds] 가 막는다(클래스 주석).
                        onChange = { docs, _ -> onEvents(docs) },
                        // Firestore 는 끊긴 리스너를 스스로 다시 잇는다. 여기서 할 수
                        // 있는 일은 흔적을 남기는 것뿐이다 — 규칙 미게시로 인한 영구
                        // 거부와 잠깐 끊긴 것을 로그로만 가릴 수 있다.
                        onError = { e -> Log.w(TAG, "이벤트 구독 실패 — 알림이 안 올 수 있다", e) },
                    )
                    return@launch
                } catch (e: CancellationException) {
                    // 서비스가 죽으면서 스코프가 취소된 정상 종료다. 다시 던져 취소를 완성시킨다.
                    throw e
                } catch (e: Exception) {
                    Log.w(TAG, "로그인 실패 — ${RETRY_MILLIS / 1000}초 뒤 다시 시도한다", e)
                    delay(RETRY_MILLIS)
                }
            }
        }
    }

    /**
     * 스냅샷 하나를 알림으로 옮긴다.
     *
     * 순서가 규칙이다. **알린 기록을 먼저 저장하고**, 그다음에 띄울지 말지 정한다.
     * 반대로 두면 "부모가 화면을 보고 있어서 안 띄웠다"가 "아직 안 알렸다"로 남아,
     * 부모가 탭을 떠난 직후 방금 눈으로 본 줄이 알림으로 한 번 더 뜬다.
     */
    private fun onEvents(docs: List<EventDoc>) {
        val known = notifiedIds(this)
        val current = docs.map { it.id }.toSet()
        val fresh = docs.filter { !it.read && it.id !in known }

        // 창(최근 [EventRepository.RECENT_LIMIT]건) 밖으로 밀려난 ID 는 버린다. 이렇게
        // 하면 기억이 창 크기 이상으로 자라지 않고, 밀려난 문서는 다시 창 안으로
        // 돌아올 수 없으므로 버려도 다시 알릴 일이 없다.
        setNotifiedIds(this, (known intersect current) + fresh.map { it.id })

        val unread = docs.filter { !it.read }
        if (unread.isEmpty()) {
            // 부모가 앱에서 다 읽었다. 알림줄에 남아 있으면 이미 처리한 일을 또 처리하라고
            // 조르는 셈이라 거둔다.
            cancelAlert(this)
            return
        }
        if (fresh.isEmpty()) return
        // 부모가 지금 그 줄을 눈으로 보고 있다. 같은 내용을 알림줄에 한 번 더 띄우는 것은
        // 알려주는 것이 아니라 방해다.
        if (listVisible) return

        postAlert(unread)
    }

    /**
     * 안 읽은 사건 전부를 **알림 하나**로 띄운다.
     *
     * 사건마다 알림을 하나씩 만들지 않는 이유가 곧 묶음(grouping) 처리다. 지오펜스
     * 전환은 몰려서 온다 — 아이가 학원 앞을 지나가면 도착·이탈이 잇달아 잡히고,
     * 오프라인이었다가 연결되면 밀려 있던 쓰기가 한꺼번에 올라온다. 알림을 낱개로
     * 만들면 그 순간 부모 폰에 알림 벽이 서고, 벽이 서면 부모는 그 채널을 끈다.
     *
     * 안드로이드의 그룹+요약(setGroup/setGroupSummary) 대신 **ID 하나를 계속 덮어쓰는**
     * 쪽을 골랐다. 그룹은 낱개 알림이 각자 한 번씩 소리를 내고 나서 묶이는 것이라
     * "벽이 안 선다"를 보장하지 못한다. ID 하나면 벽 자체가 생길 수 없다.
     *
     * 내용은 [fresh] 가 아니라 **안 읽은 것 전부**로 만든다. 그래야 알림줄에 보이는
     * 것과 알림 탭에 보이는 것이 항상 같다 — 새 사건 하나가 왔다고 앞서 온 안 읽은
     * 사건들이 알림줄에서 사라지면 부모는 그것들을 못 본 채 지나간다.
     */
    private fun postAlert(unread: List<EventDoc>) {
        // 최신순으로 온다([EventRepository.observeEvents]). 맨 앞이 제목이 된다.
        val lines = unread.map { event ->
            getString(
                R.string.alert_child_line,
                childNames[event.childUid] ?: getString(R.string.child_default_name),
                AlertText.line(this, event),
            )
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ALERT)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(lines.first())
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(openAlertsIntent(this))
        if (lines.size > 1) {
            builder.setNumber(lines.size)
            builder.setContentText(getString(R.string.alert_notification_more, lines.size - 1))
            val style = NotificationCompat.InboxStyle()
            lines.take(INBOX_LINES).forEach { style.addLine(it) }
            if (lines.size > INBOX_LINES) {
                style.setSummaryText(getString(R.string.alert_notification_more, lines.size - INBOX_LINES))
            }
            builder.setStyle(style)
        }
        // 안드로이드 13+ 에서 알림 권한이 없으면 시스템이 조용히 버린다. 그 권한은
        // 부모가 스위치를 켤 때 AlertFragment 가 물어보고, 거절하면 스위치를 켜지
        // 않는다 — 여기서 다시 막지 않는 이유다.
        getSystemService(NotificationManager::class.java).notify(ALERT_NOTIFICATION_ID, builder.build())
    }

    /** 알림줄에 계속 떠 있는 표시. 조용해야 하므로 채널 중요도가 낮다. */
    private fun buildOngoingNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ONGOING) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ONGOING,
                    getString(R.string.channel_alert_service),
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
        // 사건 알림 채널은 여기서 함께 만든다. 첫 사건이 왔을 때 만들면 그 알림 하나가
        // 채널 생성보다 먼저 나가 조용히 사라질 수 있다.
        if (manager.getNotificationChannel(CHANNEL_ALERT) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ALERT,
                    getString(R.string.channel_alert),
                    // 이 채널이 존재하는 이유가 "지금 봐야 한다"라서 HIGH 다. 낮추면
                    // 알림줄에 조용히 쌓이기만 하는데, 그건 앱을 열어야 보는 것과 같다.
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ONGOING)
            .setContentTitle(getString(R.string.alert_service_notification_title))
            .setContentText(getString(R.string.alert_service_notification_text))
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .setContentIntent(openAlertsIntent(this))
            .build()
    }

    /** 이름을 다르게 둔 이유는 [com.kidcare.family.child.TrackingService.promoteToForeground] 와 같다. */
    private fun promoteToForeground(id: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            // API 33 이하에는 specialUse 타입 자체가 없다. 타입 없이 부르면 매니페스트에
            // 적힌 타입이 그대로 적용되므로 이쪽이 맞다.
            startForeground(id, notification)
        }
    }

    override fun onDestroy() {
        subscribeJob?.cancel()
        subscribeJob = null
        // 리스너를 안 떼면 서비스 없이 리스너만 남아 죽은 스코프를 붙든 채로 콜백이
        // 돈다(TrackingService.onDestroy 와 같은 이유).
        listener?.remove()
        listener = null
        memberListener?.remove()
        memberListener = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "AlertService"

        private const val ONGOING_NOTIFICATION_ID = 1101
        private const val ALERT_NOTIFICATION_ID = 1102
        private const val CHANNEL_ONGOING = "alert_service"
        private const val CHANNEL_ALERT = "alert"

        /** 펼친 알림에 몇 줄까지 보여줄지. 넘는 것은 "외 N건"으로 접는다. */
        private const val INBOX_LINES = 5

        /** 로그인 실패 뒤 다시 시도하기까지. */
        private const val RETRY_MILLIS = 60_000L

        private const val PREFS = "kidcare_alert"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_NOTIFIED = "notified_ids"

        /**
         * 알림 탭이 지금 부모 눈앞에 있는가. [AlertFragment] 가 켜고 끈다.
         *
         * 정적 값인 이유는 [com.kidcare.family.child.TrackingService] 의 activeCollector
         * 와 같다 — 서비스와 화면은 서로를 붙들 수 없는 남남이고, 둘 다 있을 때만 뜻이
         * 있는 신호 하나를 주고받을 뿐이다. 화면이 사라질 때 반드시 false 로 되돌린다.
         */
        @Volatile
        private var listVisible = false

        fun setListVisible(visible: Boolean) {
            listVisible = visible
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /**
         * 상시 수신을 켜 뒀는가. **기본값은 꺼짐이다** — 묻지도 않고 남의 폰 알림줄에
         * 표시를 하나 심는 것은 무례하다(클래스 주석).
         */
        fun isEnabled(context: Context): Boolean =
            prefs(context).getBoolean(KEY_ENABLED, false)

        /**
         * 스위치를 켜고 끈다. 값 저장과 서비스 기동을 한 곳에 묶어 둔 이유: 나눠 두면
         * "저장은 됐는데 안 켜진" 상태가 만들어지고, 그 상태는 화면상 켜짐과 구분이 안 된다.
         *
         * `commit()`(동기)으로 쓰는 이유는 [ScheduleSyncStore] 와 같다 — 바로 다음 줄에서
         * 뜨는 서비스가 이 값을 다시 읽는다(onCreate 의 [isEnabled] 검사).
         */
        fun setEnabled(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean(KEY_ENABLED, enabled).commit()
            val intent = Intent(context, AlertService::class.java)
            if (enabled) {
                context.startForegroundService(intent)
            } else {
                context.stopService(intent)
                cancelAlert(context)
            }
        }

        /** 부팅 뒤 [com.kidcare.family.child.BootReceiver] 가 부른다. */
        fun startIfEnabled(context: Context) {
            if (!isEnabled(context)) return
            context.startForegroundService(Intent(context, AlertService::class.java))
        }

        /** 이미 알림을 띄운 문서 ID 들. 클래스 주석의 "안전한 쪽으로 실패" 참고. */
        private fun notifiedIds(context: Context): Set<String> =
            prefs(context).getStringSet(KEY_NOTIFIED, emptySet()) ?: emptySet()

        private fun setNotifiedIds(context: Context, ids: Set<String>) {
            // 돌려받은 Set 을 그대로 고쳐 넣으면 안 된다는 SharedPreferences 의 계약
            // 때문에 항상 새 집합을 만들어 넘긴다.
            prefs(context).edit().putStringSet(KEY_NOTIFIED, HashSet(ids)).apply()
        }

        /** 알림줄의 사건 알림만 거둔다(상시 표시는 그대로 둔다). */
        fun cancelAlert(context: Context) {
            context.getSystemService(NotificationManager::class.java).cancel(ALERT_NOTIFICATION_ID)
        }

        /**
         * 알림을 누르면 알림 탭이 열린다. 지도 탭이 열리면 부모는 방금 본 그 한 줄을
         * 다시 찾아 헤맨다.
         *
         * CLEAR_TOP|SINGLE_TOP 이라 이미 떠 있는 화면이 있으면 새로 만들지 않고
         * onNewIntent 로 들어간다([GuardianMainActivity.onNewIntent]).
         */
        private fun openAlertsIntent(context: Context): PendingIntent {
            val intent = Intent(context, GuardianMainActivity::class.java)
                .setFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
                .putExtra(GuardianMainActivity.EXTRA_OPEN_ALERTS, true)
            return PendingIntent.getActivity(
                context,
                OPEN_ALERTS_REQUEST_CODE,
                intent,
                // 우리가 담은 extra 를 남이 바꿔 끼우지 못하게 불변으로 둔다. 여기는
                // 시스템이 채워 넣을 것이 없어 FLAG_MUTABLE 이 필요 없다(지오펜스·활동
                // 인식 쪽과 다른 점).
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private const val OPEN_ALERTS_REQUEST_CODE = 4001
    }
}
