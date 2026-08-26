package com.kidcare.family.child

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.provider.Settings
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

    /**
     * 방해 금지(DND) 상태.
     *
     * **이 값이 없으면 화면이 거짓말을 한다.** 방해 금지가 켜지면 안드로이드는
     * [AudioManager.getRingerMode] 로 **무조건 SILENT 를 돌려준다** — 아이가 벨소리로
     * 맞춰 놨어도 그렇다. 그래서 [currentMode] 만 올리면 부모 화면에 "무음"이 뜨고,
     * 부모는 소리 설정이 바뀐 줄 안다. 실제로는 방해 금지가 덮고 있을 뿐이다.
     *
     * 두 갈래로 읽는다. 먼저 공개 API 를 쓰고([NotificationManager.getCurrentInterruptionFilter],
     * 이 앱은 소리 변경 때문에 이미 방해 금지 접근 권한을 받아 둔다), 그것이 UNKNOWN
     * 이면 시스템 설정값을 직접 읽는다 — 권한 없이도 읽히는 자리라 권한을 아직 안 준
     * 폰에서도 답이 나온다.
     */
    fun dndState(): String = try {
        val manager = context.getSystemService(NotificationManager::class.java)
        when (manager?.currentInterruptionFilter) {
            NotificationManager.INTERRUPTION_FILTER_ALL -> Dnd.OFF
            NotificationManager.INTERRUPTION_FILTER_PRIORITY -> Dnd.PRIORITY
            NotificationManager.INTERRUPTION_FILTER_ALARMS -> Dnd.ALARMS
            NotificationManager.INTERRUPTION_FILTER_NONE -> Dnd.NONE
            else -> zenModeFallback()
        }
    } catch (e: Exception) {
        Log.w(TAG, "방해 금지 상태를 못 읽었다", e)
        Dnd.UNKNOWN
    }

    /** `zen_mode`: 0=꺼짐, 1=중요 알림만, 2=완전 차단, 3=알람만. */
    private fun zenModeFallback(): String = try {
        when (Settings.Global.getInt(context.contentResolver, "zen_mode", 0)) {
            0 -> Dnd.OFF
            1 -> Dnd.PRIORITY
            2 -> Dnd.NONE
            3 -> Dnd.ALARMS
            else -> Dnd.UNKNOWN
        }
    } catch (e: Exception) {
        Dnd.UNKNOWN
    }

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
     * 우선순위(설계서 §4.3): **즉시 변경이 살아 있으면 그것이 이기고, 아니면
     * 예약 규칙([RingerStateStore.ruleMode], [ScheduleApplier] 가 채운다)이 이긴다.**
     *
     * 즉시 변경은 [RingerStateStore.overrideUntil] 까지만 유효하다. 0 이면 해제
     * 시각이 없다는 뜻이라 계속 유효하다 — 적용 중인 예약 규칙이 하나도 없을 때가
     * 그렇다(그럴 땐 애초에 이 즉시 변경을 끝낼 다음 경계 자체가 없다). 만료됐으면
     * 여기서 지우고 규칙으로 넘어간다.
     *
     * 시그니처를 바꾸지 않은 이유: [RingerModeReceiver](되돌리기, Task 5)가 이 함수를
     * `desiredMode(state)` 형태로 부른다. 여기에 규칙을 인자로 추가하면 그 호출부도
     * 함께 고쳐야 하는데, 규칙은 이미 [state]([RingerStateStore.ruleMode]) 안에
     * 캐시돼 있으므로 그럴 필요가 없다 — 덕분에 되돌리기도 별도 수정 없이 자동으로
     * 예약 규칙까지 지키게 된다(아이가 규칙이 정한 모드를 손으로 되돌려도 잠금이
     * 켜져 있으면 3초 뒤 되돌아온다).
     */
    fun desiredMode(state: RingerStateStore, nowMillis: Long = System.currentTimeMillis()): String? {
        val until = state.overrideUntil
        val overrideExpired = until != 0L && nowMillis >= until
        if (overrideExpired) {
            state.clearOverride()
            return state.ruleMode
        }
        return state.overrideMode ?: state.ruleMode
    }

    private companion object {
        const val TAG = "RingerController"
    }
}
