package com.kidcare.family.child

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.kidcare.family.core.EventRepository
import com.kidcare.family.core.PlaceRepository
import com.kidcare.family.core.model.EventDoc
import com.kidcare.family.core.model.EventType
import com.kidcare.family.core.toPlace
import com.kidcare.family.logic.Fix
import com.kidcare.family.logic.GeofenceEvaluator
import com.kidcare.family.logic.Place

/**
 * 자녀 폰의 장소 판정(설계서 §4.6). [GeofenceEvaluator] 를 안드로이드에 붙이는 껍데기다.
 *
 * ## OS 지오펜스는 "알림"이 아니라 "판정해 보라는 신호"다
 *
 * [GeofencingClient][com.google.android.gms.location.GeofencingClient] 의 전환 콜백에서
 * 곧장 이벤트를 쓰면 안 된다. 그 콜백에는 히스테리시스도, 5분 중복 억제도, 정확도
 * 문턱도 없다 — 경계에 앉은 아이 하나 때문에 부모 폰이 하루 종일 운다. 그래서
 * [PlaceGeofenceReceiver] 는 전환 위치를 [Fix] 로 만들어 [onFix] 에 넘기기만 하고,
 * 알릴지 말지는 언제나 [GeofenceEvaluator] 가 정한다. 위치 수집이 주는 보통 fix 와
 * **완전히 같은 길**을 지나므로 상태(안에 있었는가·마지막으로 언제 알렸는가)도 하나다.
 *
 * OS 지오펜스를 그래도 거는 이유는 지연 때문이다. 절전(Doze) 상태에서는 우리 위치
 * 수집이 몇 분에서 십수 분씩 밀리는데, 플레이 서비스의 지오펜스 전환은 그 상태에서도
 * 제때 배달된다.
 *
 * ## 상태는 어디 있나
 *
 * [PlaceStateStore](SharedPreferences)다. 메모리에만 두면 강제 종료·재부팅으로 사라져
 * 그날의 이탈 알림이 통째로 없어진다 — 그 클래스 주석에 근거가 있다.
 */
class PlaceWatcher(private val context: Context) {

    private val stateStore = PlaceStateStore(context)

    /**
     * 마지막으로 읽어 온 장소 목록. [refresh] 가 채우고 [onFix] 가 읽는다.
     *
     * 두 호출이 서로 다른 코루틴(서비스의 시작 경로 / 위치 콜백)에서 오므로
     * `@Volatile` 이다. 목록 자체는 갈아 끼우기만 하고 안을 고치지 않으니 이걸로 충분하다.
     */
    @Volatile
    private var places: List<Place> = emptyList()

    /**
     * 장소를 다시 읽어 기억하고 OS 지오펜스를 다시 건다.
     *
     * 부르는 곳이 둘이다 — [TrackingService] 가 (재)시작될 때(재부팅 뒤 포함)와,
     * 부모가 장소를 고친 뒤 보내는 `sync_rules` 명령을 [CommandHandler] 가 받았을 때.
     * 재부팅 때 다시 걸어야 하는 이유는 OS 가 재부팅 시 등록된 지오펜스를 전부 지우기
     * 때문이다(설계서 §4.6).
     */
    suspend fun refresh(familyId: String, childUid: String) {
        val loaded = PlaceRepository.fetchPlaces(familyId, childUid).map { it.toPlace() }
        places = loaded
        registerGeofences(loaded)
    }

    /**
     * 위치 한 점으로 판정하고, 알릴 것이 나오면 `events/` 에 적는다.
     *
     * 장소를 아직 한 번도 못 읽었거나(오프라인 시작) 정말 하나도 없으면 그대로 돌아간다.
     * **저장된 상태를 지우지 않는 것이 중요하다** — 여기서 빈 목록으로 판정하면
     * [GeofenceEvaluator] 가 "지금 있는 장소만 남긴다" 규칙에 따라 상태를 통째로 비우고,
     * 잠시 뒤 장소를 읽어오면 아이가 이미 안에 있는 곳들이 전부 "처음 보는 장소"가 된다.
     *
     * 실패(권한 거부·오프라인)는 여기서 삼키지 않고 위로 던진다. 부르는 쪽
     * ([TrackingService])이 로그로 남기고, 다음 위치 점에서 다시 시도한다 — 이벤트
     * 하나를 못 쓴 것 때문에 위치 수집 자체가 멈추면 안 된다.
     */
    suspend fun onFix(familyId: String, childUid: String, fix: Fix) {
        val known = places
        if (known.isEmpty()) return

        val (hits, next) = GeofenceEvaluator.evaluate(known, stateStore.states, fix)
        // 상태를 **먼저** 저장한다. 이벤트 쓰기가 실패해 예외로 빠져나가더라도 "안에
        // 있다"는 사실은 남아야 한다. 반대 순서면, 오프라인일 때 같은 전환이 위치 점마다
        // 다시 잡혀 연결이 돌아오는 순간 같은 도착이 여러 번 올라간다.
        stateStore.states = next

        for (hit in hits) {
            EventRepository.add(
                familyId,
                EventDoc(
                    type = if (hit.entering) EventType.PLACE_ENTER else EventType.PLACE_EXIT,
                    // 폰 시계로 잰 값이다(위치가 잡힌 순간). 규칙이 서버 시각과 대조해
                    // 과거 24시간 ~ 미래 1시간 밖이면 거부하므로, 아이 폰 시계가 한 시간
                    // 넘게 앞서 있으면 이 쓰기가 막힌다 — 그건 그 폰의 시계 문제이고,
                    // 여기서 "지금"으로 바꿔치기하면 일어난 시각을 지어내는 셈이 된다.
                    at = hit.at,
                    childUid = childUid,
                    placeName = hit.placeName,
                ),
            )
        }
    }

    /**
     * OS 지오펜스를 통째로 다시 건다.
     *
     * 먼저 전부 지우고 다시 거는 이유: 부모가 장소를 **지웠을** 때 그 지오펜스를 남겨두면
     * 이미 없는 장소의 전환이 계속 올라온다. 개별 삭제(removeGeofences(ids))로 맞추려면
     * "직전에 무엇을 걸었는지"를 따로 기억해야 하는데, 스무 개짜리 목록을 통째로 다시
     * 거는 비용이 그 기억을 관리하는 비용보다 싸다.
     *
     * 반경이 0 이하인 장소는 건너뛴다 — [Geofence.Builder] 가 그런 값을 거부해서
     * **목록 전체의 등록이 실패**한다. 필드가 빠진 옛 문서 하나 때문에 멀쩡한 장소
     * 열아홉 개가 같이 죽으면 안 된다.
     */
    @SuppressLint("MissingPermission")
    private fun registerGeofences(places: List<Place>) {
        val client = LocationServices.getGeofencingClient(context)
        val pendingIntent = geofencePendingIntent(context)

        // 지우기는 권한을 요구하지 않는다. 등록 실패와 무관하게 옛 지오펜스는 반드시
        // 사라져야 하므로 조건 없이 먼저 부른다(TrackingService.unregisterActivityTransitions
        // 와 같은 규율).
        client.removeGeofences(pendingIntent)

        // 설계서 §4.6 의 실용 상한. OS 한도는 100 이지만 그만큼 걸면 배터리와 오탐이
        // 같이 늘고, 부모 화면도 20개에서 막는다. 이름순으로 자르는 것은 잘리는 대상이
        // 매번 같아야 하기 때문이다 — 읽어온 순서로 자르면 어떤 장소는 하루는 걸리고
        // 하루는 안 걸린다.
        val usable = places
            .filter { it.radiusMeters > 0.0 }
            .sortedBy { it.name }
            .take(MAX_GEOFENCES)
        if (usable.size < places.size) {
            Log.w(TAG, "장소 ${places.size}개 중 ${usable.size}개만 지오펜스로 걸었다(상한 $MAX_GEOFENCES·반경 0 제외)")
        }
        if (usable.isEmpty()) return

        val request = GeofencingRequest.Builder()
            // 등록하는 순간 이미 안에 있는 장소로 ENTER 를 쏘지 않게 한다(기본값이 그렇다).
            // 그 전환은 우리에게 새 정보가 아니다 — 이미 안에 있다는 사실은 상태 저장소가
            // 알고 있고, 아니라면 다음 위치 점이 곧 심는다. 폰만 한 번 깨우고 끝이다.
            .setInitialTrigger(0)
            .addGeofences(
                usable.map { place ->
                    Geofence.Builder()
                        // 요청 ID 가 곧 문서 ID 다. 전환이 올라올 때 어느 장소인지 알아야
                        // 하고, 같은 ID 로 다시 등록하면 옛 것을 덮어쓴다.
                        .setRequestId(place.id)
                        .setCircularRegion(place.lat, place.lng, place.radiusMeters.toFloat())
                        .setExpirationDuration(Geofence.NEVER_EXPIRE)
                        .setTransitionTypes(
                            Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT
                        )
                        .build()
                }
            )
            .build()

        try {
            client.addGeofences(request, pendingIntent)
                .addOnSuccessListener { Log.i(TAG, "지오펜스 ${usable.size}개 등록") }
                // 실패해도 장소 기능이 통째로 죽지는 않는다 — 위치 점마다 도는 [onFix]
                // 판정이 그대로 살아 있어서, 잃는 것은 절전 상태에서의 반응 속도뿐이다.
                // 그래도 반드시 로그로 남긴다: 실기기에서 이게 조용히 실패하면
                // "왜 알림이 늦지"를 알아낼 방법이 없다.
                .addOnFailureListener { e -> Log.w(TAG, "지오펜스 등록 실패", e) }
        } catch (e: SecurityException) {
            // 위치 '항상 허용'이 꺼져 있으면 여기서 바로 튄다. 아이가 설정에서 언제든
            // 끌 수 있으므로 예외가 아니라 흔한 상태다 — 서비스를 죽이지 않는다.
            Log.w(TAG, "지오펜스 등록 권한 없음 — 위치 점 판정만으로 동작한다", e)
        }
    }

    companion object {
        private const val TAG = "PlaceWatcher"

        /** 설계서 §4.6 의 실용 상한. 부모 화면의 장소 개수 상한과 같은 값이어야 한다. */
        const val MAX_GEOFENCES = 20

        private const val GEOFENCE_REQUEST_CODE = 3001

        /**
         * 전환을 받을 [PlaceGeofenceReceiver] 를 향한 PendingIntent.
         *
         * `FLAG_MUTABLE` 이어야 한다: 플레이 서비스가 이 Intent 에 전환 정보를 extra 로
         * 채워 넣어 보내는데(fill-in), 불변으로 만들면 그 채워 넣기가 막혀 전환이 빈 채로
         * 온다. `FLAG_UPDATE_CURRENT` 는 등록과 해제가 **같은** PendingIntent 를 얻게
         * 하려는 것이다 — 시스템은 그 동일성으로 짝을 맞추므로 플래그·요청 코드·Intent
         * 모양이 조금이라도 다르면 removeGeofences 가 등록을 못 찾는다.
         * (TrackingService.activityTransitionPendingIntent 와 같은 이유·같은 값이다.)
         */
        private fun geofencePendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, PlaceGeofenceReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            return PendingIntent.getBroadcast(context, GEOFENCE_REQUEST_CODE, intent, flags)
        }
    }
}
