package com.kidcare.family.guardian

import android.content.Context

/**
 * "언제 물어봤고 언제 대답을 받았나"를 부모 폰에 남긴다.
 *
 * 연결 끊김 배너([GuardianMainActivity])의 판정 재료다. 판정 자체는
 * [com.kidcare.family.logic.DisconnectRule] 이 하고, 여기는 값을 들고만 있는다.
 *
 * ## 왜 부모 폰 안에 두나
 *
 * 서버에 두면 그 자체가 쓰기·읽기라 무료 한도를 갉아먹는다 — 이 작업이 없애려던
 * 비용을 판정 재료가 되살리는 셈이다. 그리고 이 값은 **이 부모 폰이 무엇을 물었나**
 * 라는 이 기기만의 사실이라 애초에 공유할 이유가 없다.
 *
 * ## 왜 기기 시계를 그대로 쓰나
 *
 * 두 값을 적는 것도, 읽어서 빼는 것도 전부 이 폰이다. 그래서 폰 시계가 서버와
 * 얼마나 어긋나 있든 **차이는 정확하다.** 여기에 [com.kidcare.family.core
 * .FamilyRepository.serverNow] 같은 서버 보정 시각을 섞으면 오히려 보정 오차
 * (왕복 절반 추정)가 그대로 오차로 들어온다.
 *
 * [recordAnswer] 가 화면 갱신을 겸하지 않는 것에 주의할 것 — 배너를 즉시 지우려면
 * 부른 쪽이 [GuardianMainActivity.refreshBanner] 도 함께 불러야 한다.
 */
class RequestLog(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_requests", Context.MODE_PRIVATE)

    /** 마지막으로 '지금 위치 확인'을 보낸 시각. 0 이면 **한 번도 물어본 적이 없다.** */
    fun lastRequestAt(childUid: String?): Long = childUid?.let {
        prefs.getLong("${KEY_REQUEST}_$it", prefs.getLong(KEY_REQUEST, 0L))
    } ?: 0L

    /** 마지막으로 아이 폰의 대답을 확인한 시각. */
    fun lastAnswerAt(childUid: String?): Long = childUid?.let {
        prefs.getLong("${KEY_ANSWER}_$it", prefs.getLong(KEY_ANSWER, 0L))
    } ?: 0L

    fun recordRequest(childUid: String) {
        prefs.edit().putLong("${KEY_REQUEST}_$childUid", System.currentTimeMillis()).apply()
    }

    fun recordAnswer(childUid: String) {
        prefs.edit().putLong("${KEY_ANSWER}_$childUid", System.currentTimeMillis()).apply()
    }

    private companion object {
        const val KEY_REQUEST = "last_request_at"
        const val KEY_ANSWER = "last_answer_at"
    }
}
