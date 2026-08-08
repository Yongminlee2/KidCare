package com.kidcare.family.logic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DisconnectRuleTest {

    private val threshold = DisconnectRule.THRESHOLD_MILLIS
    private val now = 1_754_500_000_000L

    @Test
    fun `한 번도 안 물어본 폰은 절대 고발하지 않는다`() {
        // 페어링만 끝내고 '지금 위치 확인'을 한 번도 안 누른 부모. 아무리 시간이
        // 흘러도 배너가 뜨면 안 된다 — 대답하지 않은 게 아니라 물어본 적이 없다.
        assertFalse(DisconnectRule.isDisconnected(0L, 0L, now))
        assertFalse(DisconnectRule.isDisconnected(0L, 0L, now + 10 * threshold))
    }

    @Test
    fun `물어본 뒤 문턱을 넘게 대답이 없으면 띄운다`() {
        val asked = now - threshold
        assertTrue(DisconnectRule.isDisconnected(asked, 0L, now))
    }

    @Test
    fun `문턱 직전에는 아직 안 띄운다`() {
        // 한 번의 무응답(터널·Doze 창)으로 헛경보를 내면 부모가 이 문구를 안 읽게 된다.
        val asked = now - threshold + 1
        assertFalse(DisconnectRule.isDisconnected(asked, 0L, now))
    }

    @Test
    fun `마지막 물음에 대답이 왔으면 안 띄운다`() {
        val asked = now - 5 * threshold
        val answered = asked + 1000
        assertFalse(DisconnectRule.isDisconnected(asked, answered, now))
    }

    @Test
    fun `옛 대답만 있고 최근 물음에 답이 없으면 띄운다`() {
        // 어제는 잘 대답하던 폰이 오늘 아침부터 죽어 있는 경우다.
        val answered = now - 10 * threshold
        val asked = now - 2 * threshold
        assertTrue(DisconnectRule.isDisconnected(asked, answered, now))
    }

    @Test
    fun `대답 시각이 물음과 같으면 대답한 것으로 본다`() {
        // 같은 밀리초에 물음과 대답이 적히는 것은 실제로 일어날 수 있다(캐시 응답).
        // 그때 배너를 띄우면 대답을 받아 놓고 못 받았다고 말하는 셈이다.
        val asked = now - 2 * threshold
        assertFalse(DisconnectRule.isDisconnected(asked, asked, now))
    }

    @Test
    fun `방금 물어본 직후에는 안 띄운다`() {
        assertFalse(DisconnectRule.isDisconnected(now, 0L, now))
    }
}
