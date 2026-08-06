package com.kidcare.family.child

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.RoleStore
import com.kidcare.family.logic.Decision
import com.kidcare.family.logic.Fix
import com.kidcare.family.logic.LocationFilter
import com.kidcare.family.onboarding.PermissionStep
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * 아이 폰에서 상시 도는 서비스.
 *
 * 알림줄에 아이콘이 계속 뜬다. 안드로이드가 요구하는 것이기도 하고,
 * '몰래 감시하지 않는다'는 이 앱의 원칙에도 맞는다.
 */
class TrackingService : LifecycleService() {

    private val collector by lazy { LocationCollector(this) }
    private val reporter = StatusReporter()
    private var lastUploaded: Fix? = null
    private val segmentUploader = SegmentUploader()
    private var lastSegmentRebuildAt = 0L
    private val pointsCleaner = PointsCleaner()
    private var lastPointsCleanupAt = 0L

    // onCreate 에서 확인한 결과. ChildHomeActivity 는 PermissionStep.firstMissing 이
    // null 일 때만(=모든 권한이 켜져 있을 때만) 이 서비스를 켜지만, 그 뒤 사용자가
    // 시스템 설정에서 위치 권한을 직접 끌 수 있고, BootReceiver 는 권한을 전혀
    // 확인하지 않고 부팅 즉시 서비스를 띄운다. location 타입 포그라운드 서비스는
    // 안드로이드 14(API 34)부터 이 권한이 없는 채로 startForeground 를 부르면
    // 그 자리에서 SecurityException 으로 죽으므로, startForeground 를 부르기
    // 전에 반드시 먼저 확인해야 한다.
    private var hasLocationPermission = false

    // 이 인스턴스가 활동 인식 구독을 실제로(성공까지) 걸었는지. removeActivityTransitionUpdates
    // 는 권한을 요구하지 않으므로, 해제 여부는 "지금 권한이 있는가"가 아니라 "이 값"으로만
    // 판단해야 한다 — 아래 unregisterActivityTransitions() 주석 참고.
    private var transitionsRegistered = false

    override fun onCreate() {
        super.onCreate()
        hasLocationPermission = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasLocationPermission) {
            // 알림도 띄우지 않고 조용히 멈춘다. startForeground 를 아예 부르지 않고
            // stopSelf() 로 끝내는 것은 안드로이드가 허용하는 정상 종료 경로라
            // "startForeground 를 제때 안 불렀다"는 ANR 로 이어지지 않는다.
            Log.w(TAG, "위치 권한이 없어 서비스를 시작하지 않는다")
            stopSelf()
            return
        }
        promoteToForeground(NOTIFICATION_ID, buildNotification())

        // ActivityTransitionReceiver(매니페스트 등록, 별도 인스턴스)가 지금 도는
        // 서비스의 collector 에 닿을 방법이 없어 정적 참조로 다리를 놓는다.
        // onDestroy 에서 반드시 null 로 되돌린다 — 안 그러면 죽은 서비스의
        // collector 를 계속 붙들어 leak 이 된다.
        activeCollector = collector
        registerActivityTransitions()
    }

    /**
     * 활동 인식 전환 구독을 건다. onCreate 는 이 서비스 인스턴스당 한 번만 불리므로
     * (Android 는 같은 Service 클래스의 인스턴스를 프로세스마다 하나만 유지하고,
     * onStartCommand 가 여러 번 불려도 onCreate 는 다시 안 부른다) 이 함수도 인스턴스당
     * 한 번만 실행된다. 프로세스가 죽었다 BootReceiver/START_STICKY 로 다시 뜨는
     * 경우에도, PendingIntent 는 (컴포넌트·요청 코드·FLAG_UPDATE_CURRENT) 조합으로
     * 동일하게 다시 만들어지므로 구글 플레이 서비스 쪽에서 새 구독이 아니라 기존
     * 구독을 갱신한 것으로 취급한다 — 중복 등록이 쌓이지 않는다.
     */
    @SuppressLint("MissingPermission")
    private fun registerActivityTransitions() {
        if (!PermissionStep.ACTIVITY_RECOGNITION.isGranted(this)) {
            // 권한이 없으면 등록 자체를 건너뛴다. LocationCollector 는 moving=true 로
            // 시작해 그대로 유지되므로 1분 주기가 계속된다 — 배터리보다 위치
            // 신뢰성이 먼저다.
            Log.i(TAG, "활동 인식 권한 없음 — 이동(1분) 고정으로 계속 동작")
            return
        }
        val request = ActivityTransitionRequest(
            listOf(
                ActivityTransition.Builder()
                    .setActivityType(DetectedActivity.STILL)
                    .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                    .build(),
                ActivityTransition.Builder()
                    .setActivityType(DetectedActivity.STILL)
                    .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_EXIT)
                    .build(),
            )
        )
        ActivityRecognition.getClient(this)
            .requestActivityTransitionUpdates(request, activityTransitionPendingIntent())
            .addOnSuccessListener { transitionsRegistered = true }
            .addOnFailureListener { e -> Log.w(TAG, "활동 인식 등록 실패", e) }
    }

    /**
     * removeActivityTransitionUpdates 는 requestActivityTransitionUpdates 와 달리
     * 권한을 요구하지 않는다 — LocationCollector.clearUpdates() 가 removeLocationUpdates
     * 를 무조건 부르는 것과 같은 이유다. "지금 권한이 있는가"로 이 해제를 게이트하면,
     * 등록해 둔 뒤 권한이 취소된 경우 딱 그 순간 해제가 통째로 스킵돼 구글 플레이
     * 서비스 쪽 구독이 아무도 못 지우는 채로 영원히 남는다(배터리 누수). 그래서 여기는
     * "이 인스턴스가 실제로 등록했는가"(transitionsRegistered)로만 판단한다.
     */
    private fun unregisterActivityTransitions() {
        if (!transitionsRegistered) return
        transitionsRegistered = false
        ActivityRecognition.getClient(this)
            .removeActivityTransitionUpdates(activityTransitionPendingIntent())
    }

    /**
     * 매니페스트에 등록한 명시적 컴포넌트를 향한 PendingIntent. 구글 플레이
     * 서비스는 전환 정보를 이 PendingIntent 로 브로드캐스트를 '보낼 때' Intent 에
     * extra 로 채워 넣는다(fill-in) — FLAG_IMMUTABLE 로 만들면 그 채워 넣기 자체가
     * 막혀 API 31+ 에서 전환 정보가 비어 오거나 등록이 거부된다. 그래서 여기는
     * FLAG_MUTABLE 이 맞다. FLAG_UPDATE_CURRENT 는 등록/해제 양쪽에서 같은
     * PendingIntent 를 다시 얻기 위한 것이다 — request/remove 는 시스템 안에서
     * '같은 PendingIntent 인지'로 짝을 맞추므로, 플래그·요청 코드·Intent 모양이
     * 조금이라도 다르면 remove 가 등록을 못 찾아 해제가 실패한다.
     */
    private fun activityTransitionPendingIntent(): PendingIntent {
        val intent = Intent(this, ActivityTransitionReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        return PendingIntent.getBroadcast(this, ACTIVITY_TRANSITION_REQUEST_CODE, intent, flags)
    }

    // Service.startForeground(int, Notification) 를 그대로 오버로드하듯 가리면
    // 컴파일러가 override 지정을 요구한다(현재 SDK 스텁에서 이 메서드가 open 이라
    // 그렇다) — 상위 메서드와 이름이 같으면 나중에 실수로 진짜 오버라이드로 착각하기
    // 쉬우므로 아예 다른 이름을 쓴다.
    private fun promoteToForeground(id: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(id, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        // onCreate 에서 권한이 없어 이미 stopSelf() 를 예약해 뒀다면 여기서도 아무
        // 일도 하지 않는다 — collector.start() 가 권한 없이 불리는 일을 막는다.
        if (!hasLocationPermission) return START_NOT_STICKY

        // START_STICKY 로 시스템이 죽은 프로세스를 되살릴 때 intent 는 null 로 온다.
        // 여기서 필요한 정보(familyId)는 애초에 Intent extra 가 아니라 RoleStore
        // (SharedPreferences, 프로세스와 무관하게 남아 있다)에서 읽으므로 intent 가
        // null 이어도 그대로 이어서 동작한다.
        val store = RoleStore(this)
        val familyId = store.familyId
        if (familyId == null) {
            // 페어링이 풀린 상태(store.clear() 등)에서 재시작됐다는 뜻이다. 더 돌 이유가 없다.
            stopSelf()
            return START_NOT_STICKY
        }

        collector.start { fix -> handle(familyId, fix) }
        return START_STICKY
    }

    private fun handle(familyId: String, fix: Fix) {
        // 활동 인식 권한은 서비스가 도는 도중에도 설정에서 언제든 꺼질 수 있다.
        // 정지 상태(5분 주기)로 넘어가 있는 채로 권한이 사라지면, 그 뒤로는 '이동'
        // 전환이 다시 올 수 없어 아이가 실제로 움직이기 시작해도 5분 주기에 영원히
        // 갇힌다 — "정지 5분은 진짜 정지 전환이 있을 때만"이라는 규칙이 깨진다.
        // fix 는 정지 중에도 최소 5분마다 한 번은 여기를 지나가므로, 매 fix 마다
        // 확인하면 늦어도 한 주기 안에 감지한다. 되돌릴 값은 5분이 아니라 1분이다 —
        // 위치 신뢰성이 배터리보다 먼저다.
        if (transitionsRegistered && !PermissionStep.ACTIVITY_RECOGNITION.isGranted(this)) {
            Log.w(TAG, "활동 인식 권한이 도중에 취소됨 — 구독 해제하고 이동(1분)으로 되돌림")
            unregisterActivityTransitions()
            collector.onMovingChanged(true)
        }

        // 시계가 거꾸로 갔으면(아이가 설정에서 일부러 되돌리거나, NTP 재동기화로
        // 우연히) lastUploaded.at 이 미래 시각인 채로 남는다. LocationFilter.decide 는
        // elapsed(=fix.at - lastUploaded.at) <= 0 이면 무조건 REJECT_IMPOSSIBLE 이라,
        // 그 뒤로 오는 모든 정상 fix 가 영원히 막힌다 — 서비스는 멀쩡히 돌고 로그도
        // 조용해서, 위치가 안 올라온다는 사실 자체를 알아챌 방법이 없다. lastUploaded
        // 를 버려서 다음 fix 를 첫 fix 취급으로 되살린다(LocationFilter 는 그대로 두고
        // 여기서만 고친다 — 그 클래스는 순수하고 이미 단위테스트로 고정돼 있다).
        val previous = lastUploaded
        if (previous != null && fix.at < previous.at) {
            Log.w(TAG, "시계가 거꾸로 감: lastUploaded.at=${previous.at} > fix.at=${fix.at} — lastUploaded 초기화")
            lastUploaded = null
        }

        when (LocationFilter.decide(lastUploaded, fix)) {
            Decision.UPLOAD -> Unit
            // 거절 사유가 전부 조용히 버려지면 "GPS 가 아직 안 잡혔다"와 구분이
            // 안 된다. adb logcat 에서라도 보이게 남긴다.
            Decision.SKIP_TOO_CLOSE -> {
                Log.d(TAG, "SKIP_TOO_CLOSE: familyId=$familyId at=${fix.at}")
                return
            }
            Decision.REJECT_INACCURATE -> {
                Log.w(TAG, "REJECT_INACCURATE: familyId=$familyId accuracy=${fix.accuracy}")
                return
            }
            Decision.REJECT_IMPOSSIBLE -> {
                Log.w(TAG, "REJECT_IMPOSSIBLE: familyId=$familyId at=${fix.at} previous=${lastUploaded?.at}")
                return
            }
        }

        lifecycleScope.launch {
            try {
                val childUid = AuthGateway.currentUid() ?: AuthGateway.signIn()
                reporter.report(familyId, childUid, fix, batteryPercent(), isCharging())
                // 성공했을 때만 갱신한다. 실패한 fix 를 '올린 걸로' 쳐 버리면 다음 판정이
                // 그 위치를 기준으로 거리를 재서, 진짜 새 위치가 와도 SKIP_TOO_CLOSE 로
                // 계속 버려질 수 있다.
                lastUploaded = fix
                // SegmentUploader 가 이 fix 를 메모리 버퍼에 쌓는다 — decide() 가
                // UPLOAD 를 준 것 중에서도 실제 Firestore 쓰기(report)가 성공한
                // 것만 여기 도달하므로, 버퍼는 pointsOfDay 가 나중에 읽을 값과
                // 정확히 같은 집합이 된다.
                segmentUploader.onUploaded(fix)

                // 재계산 자체는(버퍼 덕분에) 대부분 Firestore 읽기가 없지만, 그래도
                // 매 fix 마다 부르면 SegmentBuilder.build 를 하루치 점 전체에 대해
                // 반복 실행하고 replaceSegmentsOfDay 배치 쓰기도 매번 나간다.
                //
                // 10분이 아니라 15분인 이유: LocationFilter.HEARTBEAT_MILLIS 도
                // 10분이다. 값이 같으면, 완전히 멈춰 있는 아이는 "안 움직여도
                // 10분마다 한 번 올린다"는 하트비트 업로드가 재계산 주기도 거의
                // 매번 함께 넘겨 버려서, 정지한 날일수록 오히려 재계산이 더 자주
                // 도는 역설이 생긴다. 15분으로 일부러 두 주기를 어긋나게 둔다.
                val now = System.currentTimeMillis()
                if (now - lastSegmentRebuildAt >= SEGMENT_REBUILD_INTERVAL_MILLIS) {
                    // 재계산이 실패해도 시각은 먼저(또는 여기서 바로) 갱신해 둔다 — 안
                    // 그러면 색인이 없어 매번 FAILED_PRECONDITION 으로 죽는 상황에서
                    // fix 가 올라올 때마다 실패를 반복해 같은 비용을 다시 문다.
                    lastSegmentRebuildAt = now
                    runCatching { segmentUploader.rebuildToday(familyId, childUid) }
                        .onFailure { e ->
                            // runCatching 은 CancellationException 도 삼킨다 — 이 저장소가
                            // 같은 실수를 네 번 고쳤다. 서비스가 죽으며 취소된 것뿐이면
                            // 그대로 다시 던져 취소를 완성시켜야 한다.
                            if (e is CancellationException) throw e
                            // 색인 누락은 FAILED_PRECONDITION 예외 메시지에 색인 생성
                            // URL 을 담아 오는데, 그 URL 은 logcat 에서만 보인다. e.message
                            // 만 잘라 찍으면 URL 이 잘려 나갈 수 있으므로 예외 객체
                            // 자체를 Log.w 에 넘긴다.
                            Log.w(TAG, "구간 재계산 실패", e)
                        }
                }

                // 30일 지난 위치 점 정리(known-issues 4) — 하루에 한 번이면 충분하다.
                // 위 구간 재계산과 같은 방식(마지막 실행 시각 비교)으로 붙인다. 이 서비스는
                // 자녀 폰에서만 돈다 — 규칙상으로도 children/{childUid} 아래는 그 아이
                // 본인만 지울 수 있어 보호자 폰에서는 애초에 부를 수 없는 경로다.
                if (now - lastPointsCleanupAt >= POINTS_CLEANUP_INTERVAL_MILLIS) {
                    // 재계산과 같은 이유로 실패해도 시각을 먼저 갱신해 둔다 — 실패를
                    // fix 마다 반복해서 같은 비용을 다시 물지 않게 한다.
                    lastPointsCleanupAt = now
                    runCatching { pointsCleaner.cleanOldPoints(familyId, childUid) }
                        .onFailure { e ->
                            // 여기도 CancellationException 을 먼저 다시 던진다 — 위
                            // 구간 재계산과 같은 이유(runCatching 이 삼키는 문제).
                            if (e is CancellationException) throw e
                            Log.w(TAG, "오래된 위치 점 정리 실패", e)
                        }
                }
            } catch (e: CancellationException) {
                // 서비스가 죽으면서 lifecycleScope 가 취소된 것뿐인 정상 종료다.
                // GuardianPairingActivity 에서 두 번 고친 것과 같은 실수(취소를 실패로
                // 오인해 삼키는 것)를 반복하지 않도록 그대로 다시 던져 취소를 완성시킨다.
                throw e
            } catch (e: Exception) {
                // Firestore 쓰기 실패는 화면이 없는 이 서비스에서 사용자에게 보여줄
                // 방법이 없다. adb logcat 으로라도 보이게 남겨두지 않으면 보호자
                // 지도가 그냥 비어 있는데 원인을 알아낼 방법이 없다.
                Log.w(TAG, "위치 업로드 실패: familyId=$familyId", e)
            }
        }
    }

    private fun batteryPercent(): Int {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    private fun isCharging(): Boolean {
        // receiver 자리에 null 을 넘기면 실제로 리시버를 등록하지 않고 마지막
        // sticky 브로드캐스트만 즉시 읽어온다. 안드로이드 13(API 33)부터 생긴
        // RECEIVER_EXPORTED/RECEIVER_NOT_EXPORTED 필수 지정은 리시버를 실제로
        // 등록하는 호출에만 적용되고, 이 null-리시버 경로는 그 검사 자체를 타지
        // 않으므로 targetSdk 36 에서도 플래그 없이 그대로 동작한다.
        val status = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.channel_tracking),
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.tracking_notification_title))
            .setContentText(getString(R.string.tracking_notification_text))
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        // 서비스가 죽으면서 활동 인식 구독을 그대로 두면, 서비스는 없는데 센서만
        // 계속 도는 배터리 누수가 된다 — 이 작업이 막으려는 것과 정반대다.
        unregisterActivityTransitions()
        activeCollector = null
        collector.stop()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "TrackingService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "tracking"
        private const val ACTIVITY_TRANSITION_REQUEST_CODE = 2001
        // LocationFilter.HEARTBEAT_MILLIS(10분)와 일부러 다른 값을 쓴다. 위
        // handle() 안의 주석 참고.
        private const val SEGMENT_REBUILD_INTERVAL_MILLIS = 15 * 60 * 1000L
        // 오래된 위치 점 정리는 하루 한 번이면 충분하다(PointsCleaner 참고).
        private const val POINTS_CLEANUP_INTERVAL_MILLIS = 24 * 60 * 60 * 1000L

        // ActivityTransitionReceiver(매니페스트 등록, 이 서비스와 다른 컴포넌트)가
        // 지금 살아있는 서비스의 LocationCollector 를 부를 통로. 서비스가 없을 때
        // (activeCollector == null) 전환이 와도 조용히 버린다 — 그때는 위치 수집도
        // 멈춰 있어 주기를 바꿀 대상 자체가 없다.
        @Volatile
        private var activeCollector: LocationCollector? = null

        fun notifyMovingChanged(nowMoving: Boolean) {
            activeCollector?.onMovingChanged(nowMoving)
        }

        fun start(context: Context) {
            context.startForegroundService(Intent(context, TrackingService::class.java))
        }
    }
}
