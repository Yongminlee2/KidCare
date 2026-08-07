package com.kidcare.family.child

import android.content.Context

/**
 * 폰찾기 벨이 "볼륨을 원래대로 되돌려야 한다"는 사실과 그 원래 값을
 * 프로세스와 무관하게 남긴다.
 *
 * 그 값을 메모리에만 들고 있으면, 벨이 우는 도중 프로세스가 죽을 때(시스템의
 * 메모리 회수든, 아이가 "안 꺼지니까" 앱을 강제 종료하는 것이든 — 이건
 * 드문 경우가 아니라 이 기능이 끝나는 가장 흔한 방식이다) 그 값도 함께
 * 사라진다. 그러면 다음날 아침 아이의 알람이 최대 볼륨으로 울리는데,
 * 이 앱이 원인이라는 걸 아무도 알 길이 없다. 이 저장소가 그 값을
 * SharedPreferences 에 남겨, 다음에 뜨는 프로세스(TrackingService.onCreate →
 * FindPhoneController.recoverIfNeeded)가 복구할 수 있게 한다.
 *
 * [inProgress] 를 값과 따로 두는 이유: 저장된 볼륨값 자체가 0 이어도 정상이다
 * (사용자가 알람 볼륨을 실제로 0 으로 설정해 뒀을 수 있다). "복구가
 * 필요한가"를 값의 유무로 판단하면 0 을 "저장된 값 없음"과 헷갈리므로,
 * 이 플래그로만 판단해야 한다.
 *
 * RingerStateStore 와 비슷한 자리(자녀 폰 로컬, SharedPreferences)지만 담는
 * 값의 성격이 다르다 — 저건 "지금 강제해야 할 모드"라는 계속 유효한 설정값,
 * 이건 "벨이 켜져 있는 동안만 유효한, 죽었을 때만 쓰이는 일회성 복구 기록"이다.
 * 섞으면 두 개념이 헷갈릴 수 있어 파일을 분리했다.
 */
class FindPhoneStateStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_find_phone", Context.MODE_PRIVATE)

    /** 지금 되돌려야 할 볼륨 기록이 남아있는가. */
    val inProgress: Boolean get() = prefs.getBoolean(KEY_IN_PROGRESS, false)

    /** [inProgress] 가 true 일 때만 의미가 있다. */
    val savedAlarmVolume: Int get() = prefs.getInt(KEY_VOLUME, 0)

    /**
     * 벨을 켜기 시작하며 원래 볼륨을 기록한다.
     *
     * commit() 으로 동기 저장한다 — apply() 는 메모리 반영은 즉시지만 디스크
     * 반영은 백그라운드로 미룬다. 이 호출과 실제로 볼륨을 올리는 코드 사이의
     * 그 짧은 틈에 프로세스가 죽으면 디스크에 아직 안 쓰인 값을 잃는데, 그건
     * 이 저장소 자체가 막으려는 사고와 똑같다. 값 하나짜리 작은 파일이라
     * commit() 의 동기 비용은 무시할 만하다.
     */
    fun markRinging(currentVolume: Int) {
        prefs.edit()
            .putInt(KEY_VOLUME, currentVolume)
            .putBoolean(KEY_IN_PROGRESS, true)
            .commit()
    }

    /** 정상적으로 멈췄거나, 복구를 끝냈을 때 지운다. */
    fun clear() {
        prefs.edit().clear().apply()
    }

    private companion object {
        const val KEY_IN_PROGRESS = "in_progress"
        const val KEY_VOLUME = "saved_alarm_volume"
    }
}
