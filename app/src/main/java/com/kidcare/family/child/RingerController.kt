package com.kidcare.family.child

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.util.Log

/**
 * 자녀 폰의 소리 모드를 바꾼다.
 *
 * 무음·진동으로 바꾸는 것은 방해 금지 정책을 건드리는 일이라 권한이 없으면
 * AudioManager 가 조용히 무시하거나 SecurityException 을 던진다. 권한이 없을 때는
 * 실패로 보고해야 부모 화면에 "아이 폰에서 권한을 켜야 해요"가 뜬다 —
 * 조용히 실패하면 부모는 눌렀는데 왜 안 바뀌는지 알 길이 없다.
 */
class RingerController(private val context: Context) {

    private val audio: AudioManager
        get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun hasDndAccess(): Boolean =
        context.getSystemService(NotificationManager::class.java).isNotificationPolicyAccessGranted

    fun currentMode(): String = when (audio.ringerMode) {
        AudioManager.RINGER_MODE_SILENT -> RingerMode.SILENT
        AudioManager.RINGER_MODE_VIBRATE -> RingerMode.VIBRATE
        else -> RingerMode.NORMAL
    }

    /** 성공하면 true. 권한이 없거나 모드 값이 이상하면 false. */
    fun apply(mode: String): Boolean {
        if (!RingerMode.isValid(mode)) {
            Log.w(TAG, "모르는 모드: $mode")
            return false
        }
        if (mode != RingerMode.NORMAL && !hasDndAccess()) {
            Log.w(TAG, "방해 금지 접근 권한이 없어 $mode 로 바꿀 수 없다")
            return false
        }
        val target = when (mode) {
            RingerMode.SILENT -> AudioManager.RINGER_MODE_SILENT
            RingerMode.VIBRATE -> AudioManager.RINGER_MODE_VIBRATE
            else -> AudioManager.RINGER_MODE_NORMAL
        }
        return try {
            audio.ringerMode = target
            Log.i(TAG, "소리 모드 변경: $mode")
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "소리 모드 변경 거부됨", e)
            false
        }
    }

    /**
     * 지금 강제돼야 할 모드. null 이면 아무것도 강제하지 않는다.
     *
     * 즉시 변경은 [RingerStateStore.overrideUntil] 까지만 유효하다. 0 이면
     * 해제 시각이 없다는 뜻이라 계속 유효하다 — 적용 중인 예약 규칙이 하나도
     * 없을 때가 그렇다(설계서 §4.3). 예약 규칙은 Task 8 에서 여기에 합쳐진다.
     */
    fun desiredMode(state: RingerStateStore, nowMillis: Long = System.currentTimeMillis()): String? {
        val until = state.overrideUntil
        if (until != 0L && nowMillis >= until) {
            state.clearOverride()
            return null
        }
        return state.overrideMode
    }

    private companion object {
        const val TAG = "RingerController"
    }
}
