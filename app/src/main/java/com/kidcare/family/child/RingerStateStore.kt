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

    fun clearOverride() {
        overrideMode = null
        overrideUntil = 0L
    }

    private companion object {
        const val KEY_MODE = "override_mode"
        const val KEY_UNTIL = "override_until"
        const val KEY_LOCK = "lock_enabled"
        const val KEY_RULE_MODE = "rule_mode"
    }
}
