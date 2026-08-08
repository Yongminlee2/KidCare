package com.kidcare.family.child

import android.content.Context

/**
 * 지금 걸려 있는 원격 알람 하나를 프로세스 밖에 남긴다.
 *
 * ## 왜 저장해야 하나
 *
 * `AlarmManager` 의 예약은 **재부팅으로 통째로 사라지고**, 아이가 앱을 강제 종료해도
 * 사라진다. 메모리에만 들고 있으면 그 순간 알람은 아무 로그도 안 남기고 없어지는데,
 * 이 기능에서 그건 최악의 실패다 — 부모는 아이가 깨워질 거라고 믿고 있고, 두 폰
 * 어느 화면에도 "안 울린다"고 말해주는 곳이 없다. 그래서 다음에 뜨는 프로세스가
 * ([RemoteAlarmController.recoverIfNeeded]) 다시 걸 수 있게 여기 남긴다.
 * `FindPhoneStateStore` 가 볼륨 복구값을 남기는 것과 같은 자리, 같은 이유다.
 *
 * ## [minuteOfDay] 와 [atMillis] 를 **둘 다** 들고 있는 이유
 *
 * 재부팅 뒤에 다시 걸 때 필요한 것은 [atMillis](그 절대 순간)다. 반면 아이가 폰 시각을
 * 고치거나 시간대가 바뀌면 그 절대 순간은 더 이상 부모가 고른 "07:00"이 아니라서,
 * [minuteOfDay] 로 처음부터 다시 풀어야 한다([RemoteAlarmController.reresolve]).
 * 둘 중 하나만 두면 두 상황 중 하나가 반드시 어긋난다.
 *
 * 알람은 **하나만** 둔다(칸이 하나다). 새로 걸면 앞의 것을 덮어쓴다 — 근거는
 * [RemoteAlarmController] 클래스 주석 참고.
 */
class RemoteAlarmStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_remote_alarm", Context.MODE_PRIVATE)

    /** 걸린 알람이 있는가. 0 은 "없다"는 뜻이고, 실제 시각이 0 일 수는 없다(1970년). */
    val isSet: Boolean get() = atMillis != 0L

    /** 울릴 시각(자녀 폰 시계 기준 절대 밀리초). */
    val atMillis: Long get() = prefs.getLong(KEY_AT_MILLIS, 0L)

    /** 부모가 고른 하루 안의 분(0~1439). 걸린 알람이 없으면 -1. */
    val minuteOfDay: Int get() = prefs.getInt(KEY_MINUTE_OF_DAY, -1)

    /** 알람 이름. 비어 있을 수 있다(부모가 안 적었을 때). */
    val label: String get() = prefs.getString(KEY_LABEL, "").orEmpty()

    /**
     * commit()(동기)으로 쓴다. apply() 는 디스크 반영을 뒤로 미루는데, 이 기록이 막으려는
     * 사고가 바로 "그 사이에 프로세스가 사라지는 것"이다(`FindPhoneStateStore.markRinging`
     * 과 같은 판단). 값 셋짜리 작은 파일이라 동기 비용은 무시할 만하다.
     */
    fun save(atMillis: Long, minuteOfDay: Int, label: String) {
        prefs.edit()
            .putLong(KEY_AT_MILLIS, atMillis)
            .putInt(KEY_MINUTE_OF_DAY, minuteOfDay)
            .putString(KEY_LABEL, label)
            .commit()
    }

    /** 울렸거나, 취소됐거나, 이미 지나버려 포기했을 때 지운다. */
    fun clear() {
        prefs.edit().clear().commit()
    }

    private companion object {
        const val KEY_AT_MILLIS = "at_millis"
        const val KEY_MINUTE_OF_DAY = "minute_of_day"
        const val KEY_LABEL = "label"
    }
}
