package com.kidcare.family.child

import android.content.Context

object RingerMode {
    const val NORMAL = "normal"
    const val VIBRATE = "vibrate"
    const val SILENT = "silent"

    fun isValid(value: String) = value == NORMAL || value == VIBRATE || value == SILENT
}

/**
 * 즉시 변경과 잠금 스위치를 자녀 폰에 보관한다.
 *
 * Firestore 가 아니라 로컬에 두는 이유: 이 값을 실제로 강제하는 것은 자녀 폰뿐이고,
 * 서비스가 재시작돼도 살아남아야 하며, 네트워크가 끊긴 동안에도 판단이 가능해야 한다.
 * 보호자에게 보여줄 "지금 무슨 모드인가"는 status 문서의 ringerMode 로 따로 올린다.
 */
class RingerStateStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_ringer", Context.MODE_PRIVATE)

    /** 부모가 즉시 변경으로 지정한 모드. null 이면 예약 규칙이 정하는 대로 둔다. */
    var overrideMode: String?
        get() = prefs.getString(KEY_MODE, null)
        set(value) = prefs.edit().putString(KEY_MODE, value).apply()

    /**
     * 즉시 변경이 유효한 끝 시각(UTC 밀리초). 0 이면 해제 시각 없음 —
     * 적용 중인 예약 규칙이 하나도 없을 때다(설계서 §4.3).
     */
    var overrideUntil: Long
        get() = prefs.getLong(KEY_UNTIL, 0L)
        set(value) = prefs.edit().putLong(KEY_UNTIL, value).apply()

    /** "아이가 되돌리면 다시 바꾸기". */
    var lockEnabled: Boolean
        get() = prefs.getBoolean(KEY_LOCK, false)
        set(value) = prefs.edit().putBoolean(KEY_LOCK, value).apply()

    /**
     * 예약 규칙이 지금 강제하는 모드(Task 8). [ScheduleApplier] 가 규칙을 다시 읽을
     * 때마다(경계 알람, 재부팅, SYNC_RULES) 갱신한다. null 이면 지금 적용 중인 규칙이
     * 없다는 뜻이다.
     *
     * Firestore 가 아니라 여기(로컬)에 캐시하는 이유는 [overrideMode]·[overrideUntil]
     * 과 같다: [RingerController.desiredMode] 를 부르는 [RingerModeReceiver](되돌리기)는
     * 네트워크 왕복 없이 즉시 판단해야 하고, 규칙을 마지막으로 읽은 뒤 오프라인이
     * 되더라도 그 판단은 계속 가능해야 한다.
     */
    var ruleMode: String?
        get() = prefs.getString(KEY_RULE_MODE, null)
        set(value) = prefs.edit().putString(KEY_RULE_MODE, value).apply()

    /**
     * 즉시 변경의 **모드와 해제 시각을 한 번에** 쓴다.
     *
     * 따로 쓰면 안 되는 이유(Task 10 리뷰에서 잡힌 경합): [CommandHandler] 가
     * `overrideMode` 를 먼저 쓰고 `overrideUntil` 을 나중에 쓰면, 그 사이에 예약 경계
     * 알람이 자기 IO 코루틴에서 깨어나 [RingerController.desiredMode] 를 부를 수 있다.
     * 그 순간 저장소는 "새 모드 + 지나간 옛 해제 시각" 이라 만료로 판정되고,
     * `desiredMode` 는 즉시 변경을 **지워버린 뒤** 예약 모드를 다시 적용한다 —
     * 부모 화면에는 이미 "완료"가 떠 있는데 아이 폰은 예약 모드로 돌아가 있다.
     *
     * `SharedPreferences.Editor.apply()` 는 편집 묶음 전체를 메모리 맵에 **한 번에**
     * 반영한 뒤(그 구간은 잠금 안이다) 디스크 쓰기만 뒤로 미룬다. 그래서 다른
     * 스레드에서 `getString`/`getLong` 으로 읽는 쪽은 두 값을 항상 같이 보거나 같이
     * 못 본다 — 반쯤 바뀐 상태를 볼 수 없다.
     */
    fun setOverride(mode: String, untilMillis: Long) {
        prefs.edit()
            .putString(KEY_MODE, mode)
            .putLong(KEY_UNTIL, untilMillis)
            .apply()
    }

    /** 지우는 것도 같은 이유로 한 번에 한다([setOverride] 주석). */
    fun clearOverride() {
        prefs.edit()
            .remove(KEY_MODE)
            .putLong(KEY_UNTIL, 0L)
            .apply()
    }

    private companion object {
        const val KEY_MODE = "override_mode"
        const val KEY_UNTIL = "override_until"
        const val KEY_LOCK = "lock_enabled"
        const val KEY_RULE_MODE = "rule_mode"
    }
}
