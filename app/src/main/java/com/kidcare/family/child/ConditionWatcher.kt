package com.kidcare.family.child

import android.content.Context
import com.kidcare.family.R
import com.kidcare.family.core.EventRepository
import com.kidcare.family.core.model.EventDoc
import com.kidcare.family.core.model.EventType
import com.kidcare.family.onboarding.PermissionStep

/**
 * 아이 폰이 **자기 상태**를 감시해 부모에게 알린다(5단계 Task 7).
 *
 * 장소 사건([PlaceWatcher])이 "아이가 어디 갔다"라면 여기는 "이 폰이 지금 제구실을
 * 못 하고 있다"이다. 쓰는 길은 완전히 같다 — [EventRepository.add] 로 `events/` 에
 * 문서 하나. 규칙과의 계약(childUid·read==false·`at` 은 Long 밀리초)도 그대로다.
 *
 * ## 권한이 꺼진 것이 이 앱에서 제일 중요한 경고다
 *
 * 배터리가 없으면 폰이 꺼지고, 폰이 꺼지면 부모 화면의 연결 끊김 배너가 결국 뜬다 —
 * 늦어도 알기는 안다. 그런데 **권한만 꺼지면 앱은 멀쩡히 켜져 있다.** 상시 알림도
 * 그대로 뜨고, 명령을 보내면 대답도 하고, 부모 화면에는 아무 경고도 안 뜬다. 그저
 * 그날 하루가 조용할 뿐이다 — 아이가 학교에 도착해도 알림이 없고, 예약해 둔 무음도
 * 안 걸린다. 부모는 그것을 "오늘은 별일 없었구나"로 읽는다. 침묵이 이 앱에서 제일
 * 나쁜 고장이라는 규율([PlaceStateStore] 주석)이 여기서 가장 크게 걸린다.
 *
 * ## 지켜보는 권한 넷과, 넷만 보는 이유
 *
 * [PermissionStep] 의 여섯 중 넷이다. 고른 기준은 **꺼진 것이 다른 방법으로는 절대
 * 안 보이는가**이다.
 *
 * - [PermissionStep.LOCATION_FINE] — 이게 없으면 위치가 통째로 멈춘다. 이 앱의 전부다.
 * - [PermissionStep.LOCATION_BACKGROUND] — '앱 사용 중만 허용'으로 내려가면 OS 지오펜스
 *   등록이 [SecurityException] 으로 튕기고(PlaceWatcher.registerGeofences) 절전 상태의
 *   장소 판정이 사라진다. 화면상으로는 위치 권한이 여전히 '허용'이라 아무도 모른다.
 * - [PermissionStep.DND_ACCESS] — 무음·진동으로 바꾸는 권한이다. 이게 꺼지면 부모가
 *   보낸 즉시 변경은 실패로라도 뜨지만(CommandHandler 의 `ringer_denied`), **예약해 둔
 *   무음은 아무 흔적 없이 그냥 안 걸린다.** 아무도 안 물어보는 실패다.
 * - [PermissionStep.NOTIFICATION] — 꺼지면 부모가 보낸 메시지도 원격 알람도 아이 화면에
 *   안 뜨고, 상시 알림까지 사라져 **아이 눈에서도 앱이 없어진다.** 이 앱은 몰래 하지
 *   않는다는 원칙(설계서 §1)이 그 순간 조용히 깨진다.
 *
 * 뺀 둘:
 * - [PermissionStep.BATTERY_UNRESTRICTED] — 이게 꺼지면 폰이 절전에서 얼어붙어 **부모의
 *   물음에 대답을 못 하게 된다.** 그건 4단계의 연결 끊김 배너가 이미 덮는 자리다
 *   ([com.kidcare.family.logic.DisconnectRule]). 게다가 OEM 의 자동 절전 관리가 사람
 *   손 없이 이 값을 껐다 켰다 하는 기기가 있어, 알리기 시작하면 헛경보가 섞인다.
 * - [PermissionStep.ACTIVITY_RECOGNITION] — 없어도 앱이 망가지지 않는다. 좌표 기반
 *   적응형 판정이 처음 30초를 확인한 뒤 30초 저주기로 내려가며 이동을 계속 찾는다.
 *
 * ## 한 번만 알린다 — 프로세스가 죽어도
 *
 * "이미 알렸다"를 메모리에 두면 아이가 앱을 강제 종료하거나 폰이 재부팅될 때마다
 * 잊어버려, 12% 에 앉아 있는 폰이 재시작할 때마다 같은 경고를 새로 올린다. 그래서
 * SharedPreferences 에 `commit()`(동기)으로 적는다 — [PlaceStateStore] 와 같은 판단이고,
 * `apply()` 가 미루는 그 짧은 순간에 프로세스가 사라지는 것이 정확히 이 저장소가
 * 막으려는 사고다.
 *
 * **표시를 Firestore 쓰기보다 먼저 한다.** 반대 순서면 오프라인일 때 쓰기가 매달린 채로
 * 검사가 다시 돌아 같은 경고가 여러 번 큐에 쌓이고, 연결이 돌아오는 순간 한꺼번에 올라간다
 * ([PlaceWatcher.onFix] 가 상태를 먼저 저장하는 것과 같은 이유). 대가는 "쓰기가 진짜로
 * 거부되면 그 경고 하나를 잃는다"인데, 규칙이 이벤트를 거부하는 경우는 폰 시계가 하루
 * 넘게 어긋났을 때뿐이다([EventDoc][com.kidcare.family.core.model.EventDoc] 주석).
 */
class ConditionWatcher(private val context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_conditions", Context.MODE_PRIVATE)

    /**
     * 한 번 훑고, 달라진 것이 있을 때만 `events/` 에 적는다.
     *
     * **아무것도 안 달라졌으면 Firestore 를 한 번도 안 건드린다** — 읽기도 쓰기도 0 이다.
     * "이미 알렸는가"를 서버에 물어보게 만들면 검사할 때마다 읽기가 하나씩 붙어 무료
     * 한도(docs/known-issues.md 12번)를 검사 주기에 그대로 곱하게 된다. 그래서 그 기억은
     * 아이 폰 안에만 있다.
     *
     * [batteryPercent] 를 여기서 읽지 않고 받는 이유: [TrackingService] 가 상태 업로드용으로
     * 이미 같은 값을 읽는 함수를 갖고 있다. 두 번 적으면 언젠가 한쪽만 고친다.
     */
    suspend fun check(familyId: String, childUid: String, batteryPercent: Int) {
        checkBattery(familyId, childUid, batteryPercent)
        checkPermissions(familyId, childUid)
    }

    /**
     * 배터리가 [LOW_PERCENT] 아래로 **처음** 내려갔을 때 한 번. 충전해서 [REARM_PERCENT]
     * 위로 올라오면 다시 한 번 알릴 수 있게 풀린다.
     *
     * 알리는 문턱과 푸는 문턱을 벌려 둔 것이 핵심이다. 같은 값(15%)으로 두면 14↔15 를
     * 오가는 폰이 경고를 계속 올린다 — [com.kidcare.family.logic.GeofenceEvaluator] 가
     * 반경에 50m 를 얹어 이탈을 인정하는 것과 정확히 같은 히스테리시스다. 20% 를 넘으려면
     * 실제로 몇 분은 꽂아 둬야 하므로 "충전했다"는 사실의 대용으로 충분하고, 충전
     * 상태(플러그를 꽂았는가)를 재료로 쓰지 않아 보조배터리에 잠깐 스친 경우까지 저절로
     * 걸러진다.
     */
    private suspend fun checkBattery(familyId: String, childUid: String, percent: Int) {
        // 못 읽으면(BATTERY_PROPERTY_CAPACITY 가 -1) 아무 판단도 하지 않는다. -1 을 그대로
        // 흘려보내면 "0% 미만"이 되어 폰마다 켜자마자 거짓 경고가 하나 나간다.
        if (percent !in 1..100) return

        val reported = prefs.getBoolean(KEY_BATTERY_REPORTED, false)
        if (reported) {
            if (percent >= REARM_PERCENT) prefs.edit().putBoolean(KEY_BATTERY_REPORTED, false).commit()
            return
        }
        if (percent >= LOW_PERCENT) return

        prefs.edit().putBoolean(KEY_BATTERY_REPORTED, true).commit()
        add(familyId, childUid, EventType.LOW_BATTERY, context.getString(R.string.event_detail_battery, percent))
    }

    /**
     * 켜져 있던 권한이 꺼졌으면 한 번 알린다.
     *
     * 지금 꺼져 있는 것들의 이름 집합을 통째로 기억한다. 이렇게 두면 "언제 꺼졌는가"를
     * 따로 적을 필요 없이, **집합이 늘어난 순간**이 곧 전환이다. 다시 켠 것(집합이 줄어든
     * 것)은 기억만 갱신하고 알리지 않는다 — 부모가 원하던 상태로 돌아간 것이라 알림이
     * 아니라 소음이다.
     *
     * 여럿이 한꺼번에 꺼져도 문서는 하나다. 위치를 통째로 끄면 '위치 권한'과 '항상 허용'이
     * 같이 꺼지는데, 그때 줄이 둘 뜨면 부모는 사고가 두 개 난 줄로 읽는다. 쓰기도 하나로
     * 끝난다(docs/known-issues.md 14번).
     */
    private suspend fun checkPermissions(familyId: String, childUid: String) {
        val offNow = WATCHED.filterNot { it.isGranted(context) }
        // getStringSet 이 돌려준 집합은 손대면 안 되고 내용도 언제 바뀔지 모른다(SDK 문서).
        // 그래서 바로 복사본을 만든다.
        val reported = prefs.getStringSet(KEY_PERMISSIONS_OFF, null)?.toSet().orEmpty()
        val names = offNow.map { it.name }.toSet()
        if (names == reported) return

        prefs.edit().putStringSet(KEY_PERMISSIONS_OFF, names).commit()

        val fresh = offNow.filter { it.name !in reported }
        if (fresh.isEmpty()) return
        add(
            familyId, childUid, EventType.PERMISSION_OFF,
            context.getString(
                R.string.event_detail_permission,
                fresh.joinToString(", ") { context.getString(it.titleRes) },
            ),
        )
    }

    /**
     * `at` 은 폰 시계다([PlaceWatcher.onFix] 와 같은 판단) — 규칙이 서버 시각과 대조해
     * 과거 24시간 ~ 미래 1시간 밖이면 거부하지만, 여기서 "지금"으로 바꿔치기하면 일어난
     * 시각을 지어내는 셈이다.
     *
     * 실패는 삼키지 않고 위로 던진다. 부르는 쪽([TrackingService.checkConditions])이 로그로
     * 남긴다 — 이벤트 하나를 못 쓴 것 때문에 위치 수집이 멈추면 안 된다.
     */
    private suspend fun add(familyId: String, childUid: String, type: String, detail: String) {
        EventRepository.add(
            familyId,
            EventDoc(
                type = type,
                at = System.currentTimeMillis(),
                childUid = childUid,
                detail = detail,
            ),
        )
    }

    private companion object {
        /**
         * 이 아래로 내려가면 알린다.
         *
         * 안드로이드가 스스로 '배터리 부족'이라고 말하는 값이 15% 라 아이도 같은 순간에
         * 같은 경고를 본다 — 부모의 알림과 아이 폰 화면이 어긋나지 않는다. 더 높게(예:
         * 30%) 잡으면 하교 무렵마다 울려 부모가 곧 안 읽게 되고, 더 낮게(5%) 잡으면
         * 부모가 전화를 걸어볼 시간이 안 남는다.
         */
        const val LOW_PERCENT = 15

        /** 여기까지 충전되면 다음 한 번을 다시 알릴 수 있다. 문턱을 벌린 이유는 위 참고. */
        const val REARM_PERCENT = 20

        /** 꺼진 것이 다른 방법으로는 안 보이는 권한들. 고른 기준은 클래스 주석 참고. */
        val WATCHED = listOf(
            PermissionStep.LOCATION_FINE,
            PermissionStep.LOCATION_BACKGROUND,
            PermissionStep.DND_ACCESS,
            PermissionStep.NOTIFICATION,
        )

        const val KEY_BATTERY_REPORTED = "battery_reported"
        const val KEY_PERMISSIONS_OFF = "permissions_off"
    }
}
