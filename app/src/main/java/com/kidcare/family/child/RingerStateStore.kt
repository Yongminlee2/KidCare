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

    fun clearOverride() {
        overrideMode = null
        overrideUntil = 0L
    }

    private companion object {
        const val KEY_MODE = "override_mode"
        const val KEY_UNTIL = "override_until"
        const val KEY_LOCK = "lock_enabled"
    }
}
