package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class InviteCodeTest {

    @Test
    fun `코드는 6자리다`() {
        assertEquals(6, InviteCode.generate(Random(1)).length)
    }

    @Test
    fun `코드는 헷갈리는 글자를 쓰지 않는다`() {
        // 0/O, 1/I/L 은 손으로 옮겨 적을 때 잘못 읽힌다.
        repeat(500) { seed ->
            val code = InviteCode.generate(Random(seed))
            for (c in code) {
                assertFalse("생성된 코드에 $c 가 들어있다: $code", c in "01OIL")
            }
        }
    }

    @Test
    fun `생성된 코드는 항상 유효하다`() {
        repeat(500) { seed ->
            assertTrue(InviteCode.isValid(InviteCode.generate(Random(seed))))
        }
    }

    @Test
    fun `같은 시드는 같은 코드를 만든다`() {
        assertEquals(InviteCode.generate(Random(42)), InviteCode.generate(Random(42)))
    }

    @Test
    fun `소문자와 공백과 하이픈을 받아준다`() {
        assertEquals("ABC234", InviteCode.normalize(" abc-234 "))
    }

    @Test
    fun `헷갈리는 글자를 교정한다`() {
        // 사용자가 O 를 입력하면 0 이 아니라 알파벳에 있는 글자로 바꿔야 한다.
        // 0 과 O 는 O -> 0 이 아니라 둘 다 알파벳 밖이므로, 가까운 대체를 정해둔다.
        assertEquals("AQBCDE", InviteCode.normalize("aObcde"))
        assertEquals("Q23456", InviteCode.normalize("023456"))
        assertEquals("J23456", InviteCode.normalize("I23456"))
        assertEquals("J23456", InviteCode.normalize("l23456"))
    }

    @Test
    fun `길이가 다르면 무효다`() {
        assertFalse(InviteCode.isValid("ABC23"))
        assertFalse(InviteCode.isValid("ABC2345"))
        assertFalse(InviteCode.isValid(""))
    }

    @Test
    fun `알파벳에 없는 글자가 남으면 무효다`() {
        assertFalse(InviteCode.isValid("가나다라마바"))
        assertFalse(InviteCode.isValid("ABC@34"))
    }
}
