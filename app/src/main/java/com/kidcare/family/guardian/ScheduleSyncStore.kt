package com.kidcare.family.guardian

import android.content.Context
import com.kidcare.family.core.model.CommandType

/**
 * "예약 규칙을 바꿨는데 아직 아이 폰에 알리지 못했다"는 사실을 부모 폰에 남긴다.
 *
 * 이 깃발이 없으면 조용히 고장 난다. 자녀 폰이 다음 경계에 깨어나는 유일한 수단은
 * `ScheduleApplier` 가 걸어 둔 알람 하나뿐이고, 그걸 다시 걸게 만드는 신호가
 * [CommandType.SYNC_RULES] 다([ScheduleFragment] 클래스 주석). 규칙은 저장됐는데 그
 * 명령만 못 나가면, 부모는 예약을 해뒀다고 믿는데 아이 폰은 옛 규칙(또는 이미 지운
 * 규칙)의 알람을 그대로 물고 있다.
 *
 * ## 왜 onSaveInstanceState 로는 모자랐나
 *
 * 원래 이 깃발은 [android.app.Activity.onSaveInstanceState] 번들에만 있었다. 그건
 * **회전**은 살아남지만 **뒤로 가기**는 못 넘긴다 — 뒤로 가기는 액티비티를 끝내는
 * 것이라 저장 상태를 남기지 않는다. 그 순간 `onDestroyView` 가 진행 중이던 코루틴을
 * 취소하므로 `notifyChild()` 는 실행되지도 못하고, 깃발은 번들과 함께 사라진다.
 * 다음에 앱을 켜면 아무 흔적도 없다. 그래서 프로세스 밖(SharedPreferences)에 둔다 —
 * `child/RingerStateStore`·`child/FindPhoneStateStore` 가 자녀 폰에서 같은 이유로
 * 쓰는 방식이다.
 *
 * 가족 ID 로 나누지 않는 이유: 한 기기의 보호자는 한 가족에만 속한다(`RoleStore`).
 * 역할을 다시 고르면 가족이 바뀌는데, 그때 남은 깃발은 새 가족에 SYNC_RULES 를 한 번
 * 더 보내게 할 뿐이라 해가 없다(자녀 쪽은 규칙을 다시 읽어 알람을 다시 걸 뿐이다).
 */
class ScheduleSyncStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_schedule_sync", Context.MODE_PRIVATE)

    /**
     * commit()(동기)으로 쓴다. apply() 는 메모리 반영만 즉시고 디스크 쓰기는 뒤로
     * 미루는데, 이 깃발이 막으려는 사고가 바로 "그 사이에 프로세스가 사라지는 것"이라
     * 미루면 안 된다. 키 하나짜리 파일이라 동기 비용은 무시할 만하다
     * (`child/FindPhoneStateStore.markRinging` 과 같은 판단).
     */
    var pendingSync: Boolean
        get() = prefs.getBoolean(KEY_PENDING, false)
        set(value) {
            prefs.edit().putBoolean(KEY_PENDING, value).commit()
        }

    private companion object {
        const val KEY_PENDING = "pending_sync"
    }
}
