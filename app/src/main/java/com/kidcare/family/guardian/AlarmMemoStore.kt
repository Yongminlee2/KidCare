package com.kidcare.family.guardian

import android.content.Context

/**
 * "애기폰에 알람을 맞춰 뒀다"는 사실을 부모 폰에 남긴다.
 *
 * ## 왜 필요한가
 *
 * 부모가 지금 알람이 걸려 있는지 볼 수 없으면 **세 개를 건다.** 그런데 이 앱에서 알람은
 * 아이 폰 안에만 있고([com.kidcare.family.child.RemoteAlarmStore]) 부모가 그걸 물어볼
 * 통로가 없다 — 아이 폰이 서버에 알람 상태를 쓰게 하려면 새 필드와 새 규칙, 그리고
 * 알람 하나에 서버 쓰기 하나가 따라붙는데(무료 한도, docs/known-issues.md 12번) 그건
 * 이번 범위가 아니다. 그래서 부모 폰이 자기가 보낸 것을 기억한다. `RequestLog` 가
 * "내가 언제 물어봤나"를 부모 폰에 남기는 것과 같은 자리, 같은 이유다.
 *
 * ## 이 기록이 뜻하는 것과 뜻하지 않는 것
 *
 * [confirmed] 는 **아이 폰이 done 이라고 적었다**는 것뿐이다(관리 탭의 '완료'와 같은
 * 뜻). 그 뒤에 아이가 앱을 강제 종료하면 안드로이드가 알람 예약을 지우는데, 그 사실은
 * 여기에 도착하지 않는다 — 그때 부모에게 말해주는 것은 이 줄이 아니라 연결 끊김 배너다
 * ([com.kidcare.family.logic.DisconnectRule]). 그래서 화면 문구도 "울린다"가 아니라
 * "맞춰져 있어요"까지만 말한다.
 *
 * ## 왜 24시간 뒤에 저절로 사라지나
 *
 * 원격 알람은 한 번만 울리고, 어느 시각을 골라도 24시간 안에는 반드시 그 순간이 지난다.
 * "오늘 07:00 인가 내일 07:00 인가"를 부모 폰이 계산하지 않는 것이 핵심이다 — 두 폰의
 * 시간대가 다르면 그 계산이 그대로 거짓말이 되고(이 기능이 절대 시각을 안 보내는 바로
 * 그 이유), 24시간이라는 상한은 시간대와 무관하게 항상 참이다. 대가는 이미 울린 알람이
 * 화면에 최대 하루 더 남는 것인데, 부모가 그걸 보고 '알람 끄기'를 눌러도 아이 폰에서는
 * 조용히 아무 일도 안 일어난다([com.kidcare.family.child.RemoteAlarmController.cancel]).
 */
class AlarmMemoStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_alarm_memo", Context.MODE_PRIVATE)

    /** 걸어 둔 알람. 없거나 24시간이 지났으면 null. */
    fun memo(childUid: String): Memo? {
        val minuteOfDay = prefs.getInt(key(KEY_MINUTE_OF_DAY, childUid), -1)
        if (minuteOfDay !in 0..MAX_MINUTE_OF_DAY) return null
        val sentAt = prefs.getLong(key(KEY_SENT_AT, childUid), 0L)
        if (System.currentTimeMillis() - sentAt >= EXPIRY_MILLIS) return null
        return Memo(
            minuteOfDay = minuteOfDay,
            label = prefs.getString(key(KEY_LABEL, childUid), "").orEmpty(),
            confirmed = prefs.getBoolean(key(KEY_CONFIRMED, childUid), false),
        )
    }

    /** 명령이 실제로 발행됐다. 아직 아이 폰의 대답은 못 들었다. */
    fun recordSent(childUid: String, minuteOfDay: Int, label: String) {
        prefs.edit()
            .putInt(key(KEY_MINUTE_OF_DAY, childUid), minuteOfDay)
            .putString(key(KEY_LABEL, childUid), label)
            .putLong(key(KEY_SENT_AT, childUid), System.currentTimeMillis())
            .putBoolean(key(KEY_CONFIRMED, childUid), false)
            .apply()
    }

    /** 아이 폰이 done 을 적었다. */
    fun recordConfirmed(childUid: String) {
        // 기록 자체가 없으면(24시간이 지나 만료됐거나 취소된 뒤 늦게 온 콜백) 되살리지
        // 않는다 — 없는 알람을 "맞춰져 있어요"로 만들어 버릴 자리다.
        if (prefs.getInt(key(KEY_MINUTE_OF_DAY, childUid), -1) !in 0..MAX_MINUTE_OF_DAY) return
        prefs.edit().putBoolean(key(KEY_CONFIRMED, childUid), true).apply()
    }

    /** 알람을 껐거나, 맞추기가 실패했다. */
    fun clear(childUid: String) {
        prefs.edit()
            .remove(key(KEY_MINUTE_OF_DAY, childUid))
            .remove(key(KEY_LABEL, childUid))
            .remove(key(KEY_SENT_AT, childUid))
            .remove(key(KEY_CONFIRMED, childUid))
            .apply()
    }

    private fun key(base: String, childUid: String) = "${base}_$childUid"

    data class Memo(val minuteOfDay: Int, val label: String, val confirmed: Boolean)

    private companion object {
        const val KEY_MINUTE_OF_DAY = "minute_of_day"
        const val KEY_LABEL = "label"
        const val KEY_SENT_AT = "sent_at"
        const val KEY_CONFIRMED = "confirmed"

        const val MAX_MINUTE_OF_DAY = 1439
        const val EXPIRY_MILLIS = 24 * 60 * 60 * 1000L
    }
}
