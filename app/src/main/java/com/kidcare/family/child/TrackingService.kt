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
import android.media.AudioManager
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
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.model.CommandType
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

    /**
     * 마지막으로 **받아들인** fix. 옛 이름은 lastUploaded 였는데, 이제 이 값이
     * 곧바로 Firestore 로 가지 않으므로(하루 문서 정책, docs/known-issues.md 12번)
     * 이름이 거짓이 됐다. LocationFilter.decide 의 "직전 점" 역할은 그대로다.
     */
    private var lastFix: Fix? = null

    private val trailUploader by lazy { TrailUploader(this) }

    /**
     * 마지막으로 Firestore 에 올린 시각. 안전 업로드(하루 한 번) 판정에만 쓴다.
     *
     * **일부러 저장하지 않는다(메모리에만).** 서비스가 다시 뜰 때마다 0 이 되어
     * 안전 업로드가 한 번 더 나가는데, 그건 손해가 아니라 이득이다 — 아이 폰이
     * 재부팅되거나 프로세스가 죽었다 살아난 직후에 부모가 최신 상태를 한 번 받게
     * 된다. 대가는 재시작 1회당 쓰기 2번이고, 재시작이 하루 수십 번 일어나는 폰은
     * 이미 다른 문제가 더 크다.
     */
    private var lastUploadAt = 0L

    // 받은 명령을 분배·실행하는 곳(Task 3). 리스너 자체는 subscribeToCommands 가
    // 걸고 뗀다. locate_now 는 이 서비스만 답할 수 있으므로(위치 버퍼가 여기 있다)
    // 콜백으로 넘겨준다 — CommandHandler 가 서비스를 거꾸로 붙들지 않게 하려는 것이다.
    private val commandHandler by lazy { CommandHandler(this, ::uploadNow, placeWatcher) }
    private var commandListener: ListenerRegistration? = null

    // status 문서의 ringerMode 를 채우는 데 쓴다(Task 4) — 지금 실제로 무슨 소리
    // 모드인지 매 업로드마다 다시 읽어야 하므로 캐시하지 않는다.
    private val ringerController by lazy { RingerController(this) }

    // 장소 도착·이탈 판정(5단계 Task 3). 서비스와 수명을 같이한다 — 읽어 둔 장소
    // 목록을 들고 있고, 그 목록이 위치 점마다 도는 판정의 재료다.
    private val placeWatcher by lazy { PlaceWatcher(this) }

    // 배터리·권한 감시(5단계 Task 7). 상태를 SharedPreferences 에만 두므로 이 인스턴스가
    // 죽었다 살아나도 "이미 알렸다"가 그대로 남는다.
    private val conditionWatcher by lazy { ConditionWatcher(this) }

    // 잠금 스위치가 켜져 있을 때 아이가 모드를 바꾸면 되돌린다(Task 5). onCreate 에서
    // 코드로 등록하고 onDestroy 에서 반드시 해제한다 — 매니페스트 정적 등록은 서비스가
    // 안 떠 있을 때도 깨어나 배터리만 먹는다(RingerModeReceiver 주석 참고).
    private var ringerReceiver: RingerModeReceiver? = null

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

        // 프로세스가 새로 뜰 때마다 가장 먼저 한다 — 아래 위치 권한 분기와
        // 무관하게 해야 한다. 이전 프로세스가 폰찾기 벨을 끄지 못한 채(볼륨
        // 복구도 못한 채) 죽었을 수 있는데, 그 복구를 "위치 권한이 있어야만"
        // 하게 묶어두면 위치 권한이 꺼진 폰에서는 다음날 아침까지도 알람이
        // 최대 볼륨으로 남는다(FindPhoneController.recoverIfNeeded 주석 참고).
        FindPhoneController.recoverIfNeeded(this)

        // 원격 알람도 같은 자리에서, 같은 이유로 되살린다(5단계 Task 6). 아이가 앱을
        // 강제 종료하면 안드로이드가 이 앱의 AlarmManager 예약을 전부 지우는데, 그
        // 사실을 아무도 부모에게 말해주지 않는다 — 이 앱이 다시 뜨는 순간이 잃어버린
        // 알람을 되찾는 유일한 기회다. 아래 위치 권한 분기보다 앞에 두는 것도
        // FindPhoneController 와 같은 판단이다: 위치 권한이 꺼진 폰에서도 부모가 맞춘
        // 알람은 울려야 한다.
        RemoteAlarmController.recoverIfNeeded(this)

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

        // 프로세스가 죽었다 살아났으면 오늘 걸어온 길이 아직 파일에 남아 있다.
        // 이걸 안 되찾으면 부모가 오후에 '지금 위치 확인'을 눌렀을 때 오전 기록이
        // 통째로 사라진 하루 문서가 올라간다 — 옛 구조에서는 점이 이미 한 개씩
        // Firestore 에 들어가 있어 이런 위험 자체가 없었다.
        trailUploader.restore()

        // ActivityTransitionReceiver(매니페스트 등록, 별도 인스턴스)가 지금 도는
        // 서비스의 collector 에 닿을 방법이 없어 정적 참조로 다리를 놓는다.
        // onDestroy 에서 반드시 null 로 되돌린다 — 안 그러면 죽은 서비스의
        // collector 를 계속 붙들어 leak 이 된다.
        activeCollector = collector
        registerActivityTransitions()

        ringerReceiver = RingerModeReceiver(ringerController, RingerStateStore(this)).also {
            ContextCompat.registerReceiver(
                this, it,
                IntentFilter(AudioManager.RINGER_MODE_CHANGED_ACTION),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        }
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
            // 시작해 그대로 유지되므로 30초 주기가 계속된다 — 배터리보다 위치
            // 신뢰성이 먼저다.
            Log.i(TAG, "활동 인식 권한 없음 — 이동(30초) 고정으로 계속 동작")
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

        // START_STICKY 로 시스템이 죽은 프로세스를 되살릴 때 intent 는 null 로 온다.
        // 여기서 필요한 정보(familyId)는 애초에 Intent extra 가 아니라 RoleStore
        // (SharedPreferences, 프로세스와 무관하게 남아 있다)에서 읽으므로 intent 가
        // null 이어도 그대로 이어서 동작한다.
        val store = RoleStore(this)
        val familyId = store.familyId

        // 상태 검사는 **위치 권한 분기보다 앞이다.** 여기가 위치 권한이 꺼진 사실을
        // 부모에게 알릴 수 있는 유일한 순간이기 때문이다: 사용자가 설정에서 런타임
        // 권한을 취소하면 안드로이드가 이 앱 프로세스를 죽이고, START_STICKY 가 서비스를
        // 되살리고, onCreate 는 권한이 없는 것을 보고 곧장 stopSelf() 한다. 그 뒤로는
        // 위치 점이 하나도 안 들어오므로 아래 handle() 의 검사가 영원히 안 돈다 —
        // 이 한 줄을 아래로 내리면 이 앱에서 제일 중요한 경고가 정확히 제일 중요한
        // 순간에만 침묵한다(ConditionWatcher 클래스 주석).
        if (familyId != null) checkConditions(familyId)

        // onCreate 에서 권한이 없어 이미 stopSelf() 를 예약해 뒀다면 여기서도 아무
        // 일도 하지 않는다 — collector.start() 가 권한 없이 불리는 일을 막는다.
        if (!hasLocationPermission) return START_NOT_STICKY

        if (familyId == null) {
            // 페어링이 풀린 상태(store.clear() 등)에서 재시작됐다는 뜻이다. 더 돌 이유가 없다.
            stopSelf()
            return START_NOT_STICKY
        }

        subscribeToCommands(familyId)
        refreshSchedule(familyId)
        refreshPlaces(familyId)

        // 매니페스트에 등록된 PlaceGeofenceReceiver 가 지금 도는 이 서비스에 닿을
        // 방법이 없어 정적 참조로 다리를 놓는다(activeCollector 와 같은 방식).
        // onDestroy 에서 반드시 null 로 되돌린다.
        activePlaceHook = { fix -> evaluatePlaces(familyId, fix) }

        collector.start { fix -> handle(familyId, fix) }
        return START_STICKY
    }

    /**
     * 장소를 다시 읽어 OS 지오펜스를 다시 건다(5단계 Task 3).
     *
     * 서비스가 (재)시작될 때마다 부르는 이유가 [refreshSchedule] 과 같다: **재부팅 때
     * OS 가 등록된 지오펜스를 전부 지운다**(설계서 §4.6). 부팅 뒤 이 서비스를 띄우는
     * 것은 [BootReceiver] 이고, 그 경로가 여기를 지나므로 재등록이 저절로 따라온다 —
     * 리시버에 같은 일을 한 번 더 적으면 두 곳이 갈라진다.
     *
     * 실패해도(오프라인 등) 서비스는 그대로 돈다. 잃는 것은 절전 상태에서의 반응
     * 속도뿐이고, 다음 시작이나 `sync_rules` 명령이 다시 시도한다.
     */
    private fun refreshPlaces(familyId: String) {
        lifecycleScope.launch {
            try {
                placeWatcher.refresh(familyId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "장소를 못 읽어 지오펜스를 다시 걸지 못했다", e)
            }
        }
    }

    /**
     * 위치 한 점으로 장소 도착·이탈을 판정한다. 재료가 전부 여기 있으므로
     * [PlaceGeofenceReceiver] 도 [notifyGeofenceCrossing] 을 거쳐 이 함수로 들어온다.
     *
     * 실패를 삼키지 않고 로그로 남기는 이유는 안전 업로드와 같다 — 화면이 없는
     * 서비스라 부모에게 말할 방법이 없고, 조용히 실패하면 "왜 도착 알림이 안 오지"를
     * 알아낼 단서가 하나도 안 남는다.
     */
    private fun evaluatePlaces(familyId: String, fix: Fix) {
        lifecycleScope.launch {
            try {
                val childUid = AuthGateway.currentUid() ?: AuthGateway.signIn()
                placeWatcher.onFix(familyId, childUid, fix)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "장소 판정 실패: familyId=$familyId at=${fix.at}", e)
            }
        }
    }

    /**
     * 배터리와 권한을 훑어 달라진 것이 있으면 `events/` 에 적는다(5단계 Task 7).
     *
     * **부르는 곳이 둘이고, 둘이 서로의 사각을 덮는다.**
     * - [onStartCommand]: 서비스가 (재)시작될 때마다. 권한 취소로 프로세스가 죽었다
     *   살아난 직후가 여기다 — 위치 권한이 꺼진 경우 이것 말고는 기회가 없다.
     * - [handle]: 위치 점이 들어올 때마다(이동 30초·정지 5분). 서비스가 계속 살아 있는
     *   동안 꺼지는 권한(방해 금지 접근은 런타임 권한이 아니라 프로세스도 안 죽는다)과
     *   서서히 닳는 배터리는 이쪽이 잡는다.
     *
     * 위치 점마다 도는데도 통신 비용이 늘지 않는다. 검사는 전부 폰 안에서 끝나고
     * (배터리 한 번 + 권한 넷), Firestore 는 **상태가 실제로 바뀐 순간에만** 건드린다.
     * 별도 주기 알람을 새로 걸지 않은 이유이기도 하다 — 이미 규칙적으로 도는 자리가
     * 있는데 알람을 하나 더 걸면 재부팅·강제종료·정확한 알람 권한 같은 함정이 따라온다.
     *
     * 배터리 값을 여기서 읽어 넘기는 것은 [uploadNow] 가 쓰는 [batteryPercent] 를
     * 그대로 재사용하려는 것이다(같은 값을 두 곳에서 다르게 읽지 않는다).
     */
    private fun checkConditions(familyId: String) {
        val battery = batteryPercent()
        lifecycleScope.launch {
            try {
                val childUid = AuthGateway.currentUid() ?: AuthGateway.signIn()
                conditionWatcher.check(familyId, childUid, battery)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "상태 경고 기록 실패: familyId=$familyId", e)
            }
        }
    }

    /**
     * 예약 규칙을 다시 읽어 적용하고 다음 경계 알람을 건다(Task 8).
     *
     * 재부팅·시각변경·SYNC_RULES 는 [ScheduleAlarmReceiver] 가 각자 트리거를 받아
     * 처리하지만, 그 셋 중 아무것도 아직 안 일어난 상태(막 페어링을 끝내고 이
     * 서비스가 처음 뜨는 경우, 부모가 이미 규칙을 만들어 둔 채로 아이 폰에 앱을
     * 새로 깐 경우)에는 알람이 걸린 적 자체가 없다. onStartCommand 는 서비스가
     * (재)시작될 때마다 불리므로 여기서도 한 번 걸어야 그런 첫 순간을 놓치지 않는다.
     * ScheduleApplier.refresh 는 실패해도(오프라인 등) 내부에서 재시도 알람으로
     * 물러나므로 여기서 별도 재시도 로직은 두지 않는다.
     */
    private fun refreshSchedule(familyId: String) {
        lifecycleScope.launch {
            try {
                ScheduleApplier(this@TrackingService).refresh(familyId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "서비스 시작 시 예약 규칙 적용 실패", e)
            }
        }
    }

    /**
     * 명령 리스너를 (다시) 건다.
     *
     * onStartCommand 는 START_STICKY 재시작·BootReceiver·중복 시작으로 여러 번
     * 불릴 수 있다. 기존 리스너를 먼저 떼지 않으면 그때마다 리스너가 하나씩 더
     * 붙어 같은 명령 스냅샷이 여러 리스너에서 동시에 들어오고, CommandHandler.handle
     * 이 병렬로 여러 번 불린다 — handled 중복 제거가 있어도 애초에 리스너가 여러
     * 개면 그만큼 markDelivered 경합이 늘어난다. 그래서 매번 무조건 먼저 뗀다.
     */
    private fun subscribeToCommands(familyId: String) {
        commandListener?.remove()
        commandListener = null

        // childUid 는 AuthGateway.currentUid() 로만 얻는다 — 로그인을 여기서
        // 새로 시도하지 않는다(그건 handle() 의 위치 업로드 경로가 이미 한다).
        // uid 가 없는 채로 구독하면 리스너가 아무것도 안 받는 채로 조용히
        // 살아만 있어 명령이 영영 안 오는 상태를 알아챌 방법이 없다.
        val childUid = AuthGateway.currentUid()
        if (childUid == null) {
            Log.w(TAG, "childUid 가 없어 명령을 구독하지 않는다 — 로그인 전이거나 세션이 끊긴 상태")
            return
        }
        commandListener = CommandRepository.observePending(
            familyId = familyId,
            childUid = childUid,
            onCommand = { cmd ->
                lifecycleScope.launch { commandHandler.handle(familyId, childUid, cmd) }
            },
            onError = { e -> Log.w(TAG, "명령 리스너 실패 — 명령이 안 올 수 있다", e) },
        )
    }

    private fun handle(familyId: String, fix: Fix) {
        // 이 fix 를 받아들일지와 무관하게 먼저 한다(5단계 Task 7). 아래 판정에서 걸러지는
        // 점(너무 가깝다·오차가 크다)이라도 "이 폰이 아직 살아 있고 지금 배터리와 권한이
        // 이렇다"는 사실은 똑같이 유효하다. 판정 안쪽으로 넣으면 신호가 나쁜 날에는 배터리
        // 경고까지 같이 굶는다.
        checkConditions(familyId)

        // 활동 인식 권한은 서비스가 도는 도중에도 설정에서 언제든 꺼질 수 있다.
        // 정지 상태(5분 주기)로 넘어가 있는 채로 권한이 사라지면, 그 뒤로는 '이동'
        // 전환이 다시 올 수 없어 아이가 실제로 움직이기 시작해도 5분 주기에 영원히
        // 갇힌다 — "정지 5분은 진짜 정지 전환이 있을 때만"이라는 규칙이 깨진다.
        // fix 는 정지 중에도 최소 5분마다 한 번은 여기를 지나가므로, 매 fix 마다
        // 확인하면 늦어도 한 주기 안에 감지한다. 되돌릴 값은 5분이 아니라 30초다 —
        // 위치 신뢰성이 배터리보다 먼저다.
        if (transitionsRegistered && !PermissionStep.ACTIVITY_RECOGNITION.isGranted(this)) {
            Log.w(TAG, "활동 인식 권한이 도중에 취소됨 — 구독 해제하고 이동(30초)으로 되돌림")
            unregisterActivityTransitions()
            collector.onMovingChanged(true)
        }

        // 시계가 거꾸로 갔으면(아이가 설정에서 일부러 되돌리거나, NTP 재동기화로
        // 우연히) lastFix.at 이 미래 시각인 채로 남는다. LocationFilter.decide 는
        // elapsed(=fix.at - lastFix.at) <= 0 이면 무조건 REJECT_IMPOSSIBLE 이라,
        // 그 뒤로 오는 모든 정상 fix 가 영원히 막힌다 — 서비스는 멀쩡히 돌고 로그도
        // 조용해서, 위치가 안 쌓인다는 사실 자체를 알아챌 방법이 없다. lastFix
        // 를 버려서 다음 fix 를 첫 fix 취급으로 되살린다(LocationFilter 는 그대로 두고
        // 여기서만 고친다 — 그 클래스는 순수하고 이미 단위테스트로 고정돼 있다).
        val previous = lastFix
        if (previous != null && fix.at < previous.at) {
            Log.w(TAG, "시계가 거꾸로 감: lastFix.at=${previous.at} > fix.at=${fix.at} — lastFix 초기화")
            lastFix = null
        }

        val decision = LocationFilter.decide(lastFix, fix)

        // 장소 판정은 업로드 판정과 **독립이다.** 못 믿는 점(정확도·순간이동)만 빼고
        // 전부 넘긴다 — 특히 SKIP_TOO_CLOSE 를 빼면 안 된다. 그건 "직전 점에서 25m 도
        // 안 움직였다"는 뜻일 뿐인데, 경계에서 몇 걸음 옮겨 안으로 들어간 순간이 정확히
        // 그 모양이다. 업로드에는 값이 없는 점이 도착 알림에는 결정적일 수 있다.
        // GeofenceEvaluator 는 자기 정확도 문턱을 또 갖고 있으므로 여기서 한 번 더 걸러도
        // 판단이 겹칠 뿐 어긋나지 않는다.
        if (decision != Decision.REJECT_INACCURATE && decision != Decision.REJECT_IMPOSSIBLE) {
            evaluatePlaces(familyId, fix)
        }

        when (decision) {
            Decision.UPLOAD -> Unit
            // 완화 문턱으로 간신히 통과한 점이다. 올리는 동작은 UPLOAD 와 똑같지만
            // 반드시 W 로 남긴다 — known-issues 의 '정확도 기아 상태'는 이 태그
            // (`adb logcat -s TrackingService:W`)로 진단하게 돼 있는데, 완화 승인이
            // 조용하면 "신호가 계속 나빠 15분에 한 번씩 간신히 올리는 중"과 "다 정상"이
            // 로그에서 똑같이 보인다. 그 둘을 못 가르면 실기기에서 판단할 근거가 없다.
            Decision.UPLOAD_STALE_FALLBACK -> Log.w(
                TAG,
                "UPLOAD_STALE_FALLBACK: 오래 못 올려 완화 문턱으로 받음 familyId=$familyId accuracy=${fix.accuracy}",
            )
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
                Log.w(TAG, "REJECT_IMPOSSIBLE: familyId=$familyId at=${fix.at} previous=${lastFix?.at}")
                return
            }
        }

        // 여기서 Firestore 로 나가는 것은 **아무것도 없다.** 점은 폰 안(메모리 버퍼 +
        // 파일)에만 쌓인다. 옛 코드는 이 자리에서 status 문서 쓰기 한 번과 points
        // 문서 생성 한 번을 했고, 그게 하루 약 1,040번이 되어 무료 한도를 55배
        // 넘겼다(docs/known-issues.md 12번).
        lastFix = fix
        trailUploader.onCollected(fix)

        // 하루 한 번 안전 업로드. 부모가 하루 종일 앱을 안 열어도 그날 기록이 서버에
        // 한 번은 남아야 한다 — 아이 폰을 잃어버리거나 망가뜨리면 폰 안의 파일은
        // 함께 사라지기 때문이다. 이것 말고 주기적으로 올리는 경로는 없다.
        val now = System.currentTimeMillis()
        if (now - lastUploadAt < SAFETY_UPLOAD_INTERVAL_MILLIS) return
        // 실패해도 시각을 먼저 갱신한다 — 안 그러면 실패가 이어질 때 fix 마다 재시도해
        // 같은 비용(과 쓰기)을 반복해서 문다.
        lastUploadAt = now
        lifecycleScope.launch {
            try {
                val childUid = AuthGateway.currentUid() ?: AuthGateway.signIn()
                uploadNow(familyId, childUid)
            } catch (e: CancellationException) {
                // 서비스가 죽으면서 lifecycleScope 가 취소된 것뿐인 정상 종료다.
                // GuardianPairingActivity 에서 두 번 고친 것과 같은 실수(취소를 실패로
                // 오인해 삼키는 것)를 반복하지 않도록 그대로 다시 던져 취소를 완성시킨다.
                throw e
            } catch (e: Exception) {
                // 화면이 없는 이 서비스에서 사용자에게 보여줄 방법이 없다. adb logcat
                // 으로라도 보이게 남겨두지 않으면 보호자 지도가 그냥 비어 있는데
                // 원인을 알아낼 방법이 없다. 다음 안전 업로드 창(24시간 뒤)이나
                // 부모의 '지금 위치 확인'이 다시 시도한다.
                Log.w(TAG, "안전 업로드 실패: familyId=$familyId", e)
            }
        }
    }

    /**
     * 지금 상태와 오늘 경로를 Firestore 에 올린다. **쓰기 두 번**(상태 문서 1,
     * 하루 문서 1)이고, 이 앱에서 위치 데이터가 서버로 가는 유일한 경로다.
     *
     * 부르는 곳은 둘뿐이다 — [CommandHandler] 가 `locate_now` 명령을 받았을 때,
     * 그리고 위 [handle] 의 하루 한 번 안전 업로드.
     *
     * 이 프로세스가 아직 위치를 한 번도 못 잡았으면 예외를 던진다. 그러면
     * [CommandHandler] 가 그 메시지를 명령 문서의 error 로 적고 부모 화면이
     * "아직 위치를 못 잡았다"고 말한다 — 여기서 조용히 돌아가면 명령이 "완료"로
     * 끝나고, 부모는 지도에 떠 있는 옛 위치를 방금 확인한 것으로 읽는다.
     *
     * 파일에서 복구한 옛 점([TrailUploader.restore])으로 대신 채우지 않는 것도 같은
     * 이유다. 그 점은 프로세스가 죽기 전의 것이라 몇 시간 전일 수 있는데, 상태 문서에
     * 넣는 순간 서버 시각이 "방금"으로 찍혀 부모 화면에는 "방금 확인한 위치"로 뜬다.
     * 이 프로세스가 실제로 받은 fix 만 쓰면 그 점은 아무리 늦어도 한 수집 주기(정지
     * 5분) 안쪽이다.
     */
    private suspend fun uploadNow(familyId: String, childUid: String) {
        val fix = lastFix ?: error(CommandType.ERROR_NO_FIX)
        reporter.report(
            familyId, childUid, fix, batteryPercent(), isCharging(),
            ringerController.currentMode(),
        )
        trailUploader.upload(familyId, childUid)
        lastUploadAt = System.currentTimeMillis()
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
        // 지오펜스 다리도 끊는다. 안 끊으면 죽은 서비스의 lifecycleScope 를 붙든 람다가
        // 남아, 다음 전환에서 이미 취소된 스코프에 코루틴을 던진다.
        activePlaceHook = null
        collector.stop()
        // 되돌리기 리시버도 같은 이유로 뗀다 — cancelPending 을 먼저 부르지 않으면
        // 서비스가 죽은 뒤 3초 지연 중이던 Runnable 이 죽은 컨트롤러를 붙든 채 터진다.
        ringerReceiver?.let {
            it.cancelPending()
            unregisterReceiver(it)
        }
        ringerReceiver = null
        // 명령 리스너도 같은 이유로 뗀다 — 서비스 없이 리스너만 남으면 handle() 을
        // 부를 lifecycleScope 도 이미 취소된 상태라 부르는 순간 예외만 난다.
        commandListener?.remove()
        commandListener = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "TrackingService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "tracking"
        private const val ACTIVITY_TRANSITION_REQUEST_CODE = 2001

        /**
         * 안전 업로드 간격. 부모가 아무것도 안 물어봐도 이만큼에 한 번은 그날
         * 기록이 서버에 남는다 — 아이 폰을 잃어버렸을 때 남는 유일한 사본이다.
         *
         * 24시간인 이유: 가족당 하루 20쓰기라는 예산에서 안전 업로드가 차지하는
         * 몫은 2쓰기다(상태 1 + 하루 문서 1). 이 값을 6시간으로 줄이면 8쓰기가
         * 되어 부모가 위치를 확인할 수 있는 횟수가 그만큼 줄어든다 — 부모가
         * 실제로 쓰는 기능 쪽에 예산을 남긴다.
         */
        private const val SAFETY_UPLOAD_INTERVAL_MILLIS = 24 * 60 * 60 * 1000L

        // ActivityTransitionReceiver(매니페스트 등록, 이 서비스와 다른 컴포넌트)가
        // 지금 살아있는 서비스의 LocationCollector 를 부를 통로. 서비스가 없을 때
        // (activeCollector == null) 전환이 와도 조용히 버린다 — 그때는 위치 수집도
        // 멈춰 있어 주기를 바꿀 대상 자체가 없다.
        @Volatile
        private var activeCollector: LocationCollector? = null

        fun notifyMovingChanged(nowMoving: Boolean) {
            activeCollector?.onMovingChanged(nowMoving)
        }

        /**
         * [PlaceGeofenceReceiver] 가 지금 살아있는 서비스에 전환 위치를 넘기는 통로.
         * 판정에 필요한 재료(장소 목록·가족 ID·uid)가 전부 서비스 쪽에 있어서다.
         *
         * 서비스가 없으면(hook == null) 조용히 버린다 — 그때는 위치 수집도 멈춰 있어
         * 어차피 판정할 재료가 없고, 서비스가 다시 뜨면 첫 위치 점이 같은 판정을 한다
         * ([PlaceGeofenceReceiver] 주석, [notifyMovingChanged] 와 같은 규율).
         */
        @Volatile
        private var activePlaceHook: ((Fix) -> Unit)? = null

        fun notifyGeofenceCrossing(fix: Fix) {
            activePlaceHook?.invoke(fix)
        }

        fun start(context: Context) {
            context.startForegroundService(Intent(context, TrackingService::class.java))
        }
    }
}
