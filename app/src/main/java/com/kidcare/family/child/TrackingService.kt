package com.kidcare.family.child

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.RoleStore
import com.kidcare.family.logic.Decision
import com.kidcare.family.logic.Fix
import com.kidcare.family.logic.LocationFilter
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

    // onCreate 에서 확인한 결과. ChildHomeActivity 는 PermissionStep.firstMissing 이
    // null 일 때만(=모든 권한이 켜져 있을 때만) 이 서비스를 켜지만, 그 뒤 사용자가
    // 시스템 설정에서 위치 권한을 직접 끌 수 있고, BootReceiver 는 권한을 전혀
    // 확인하지 않고 부팅 즉시 서비스를 띄운다. location 타입 포그라운드 서비스는
    // 안드로이드 14(API 34)부터 이 권한이 없는 채로 startForeground 를 부르면
    // 그 자리에서 SecurityException 으로 죽으므로, startForeground 를 부르기
    // 전에 반드시 먼저 확인해야 한다.
    private var hasLocationPermission = false

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
        collector.stop()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "TrackingService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "tracking"

        fun start(context: Context) {
            context.startForegroundService(Intent(context, TrackingService::class.java))
        }
    }
}
