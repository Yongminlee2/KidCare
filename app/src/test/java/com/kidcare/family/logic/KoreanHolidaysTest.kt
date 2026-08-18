package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * 대체공휴일 규칙을 **실제로 있었던 해**로 검산한다.
 *
 * 2025년을 고른 이유: 그 해는 대체공휴일 세 개가 서로 다른 이유로 생겼다 —
 * 삼일절이 토요일(주말 겹침), 어린이날이 부처님오신날과 같은 날(공휴일 겹침),
 * 추석 연휴가 일요일을 물었다(연휴 규칙). 규칙 세 갈래를 한 해로 전부 확인할 수 있다.
 */
class KoreanHolidaysTest {

    private fun anchors2025() = LunarAnchors(
        seollal = LocalDate.of(2025, 1, 29),
        chuseok = LocalDate.of(2025, 10, 6),
        buddha = LocalDate.of(2025, 5, 5),
    )

    private fun anchors2026() = LunarAnchors(
        seollal = LocalDate.of(2026, 2, 17),
        chuseok = LocalDate.of(2026, 9, 25),
        buddha = LocalDate.of(2026, 5, 24),
    )

    private fun d(year: Int, month: Int, day: Int) = LocalDate.of(year, month, day)

    @Test
    fun `2025년 공휴일이 실제와 같다`() {
        val days = KoreanHolidays.of(2025, anchors2025()).keys
        val expected = setOf(
            d(2025, 1, 1),
            d(2025, 1, 28), d(2025, 1, 29), d(2025, 1, 30),   // 설 연휴 (화·수·목 — 대체 없음)
            d(2025, 3, 1), d(2025, 3, 3),                      // 삼일절 토요일 → 월요일 대체
            d(2025, 5, 5), d(2025, 5, 6),                      // 어린이날 = 부처님오신날 → 대체
            d(2025, 6, 6),
            d(2025, 8, 15),
            d(2025, 10, 3),
            d(2025, 10, 5), d(2025, 10, 6), d(2025, 10, 7),    // 추석 연휴 (일·월·화)
            d(2025, 10, 8),                                    // 연휴가 일요일을 물어 대체
            d(2025, 10, 9),
            d(2025, 12, 25),
        )
        assertEquals(expected, days)
    }

    @Test
    fun `2026년 공휴일이 실제와 같다`() {
        val days = KoreanHolidays.of(2026, anchors2026()).keys
        val expected = setOf(
            d(2026, 1, 1),
            d(2026, 2, 16), d(2026, 2, 17), d(2026, 2, 18),    // 설 연휴 (월·화·수)
            d(2026, 3, 1), d(2026, 3, 2),                      // 삼일절 일요일 → 대체
            d(2026, 5, 5),
            d(2026, 5, 24), d(2026, 5, 25),                    // 부처님오신날 일요일 → 대체
            d(2026, 6, 6),                                     // 현충일 토요일 — 대체 없음
            d(2026, 8, 15), d(2026, 8, 17),                    // 광복절 토요일 → 월요일 대체
            d(2026, 9, 24), d(2026, 9, 25), d(2026, 9, 26),    // 추석 연휴 (목·금·토)
            d(2026, 10, 3), d(2026, 10, 5),                    // 개천절 토요일 → 일요일 건너뛰고 월요일
            d(2026, 10, 9),
            d(2026, 12, 25),
        )
        assertEquals(expected, days)
    }

    @Test
    fun `현충일과 신정은 주말에 걸려도 대체공휴일이 없다`() {
        // 2026년 현충일은 토요일, 2028년 신정은 토요일이다. 둘 다 규정상 대체 대상이 아니다.
        val y2026 = KoreanHolidays.of(2026, anchors2026())
        assertEquals(java.time.DayOfWeek.SATURDAY, d(2026, 6, 6).dayOfWeek)
        assertFalse("현충일 다음 월요일이 쉬는 날이 됐다", y2026.containsKey(d(2026, 6, 8)))
    }

    @Test
    fun `설 연휴가 토요일만 물면 대체공휴일이 없다`() {
        // 연휴 규칙은 일요일만 본다. 2026년 추석(목·금·토)이 그 경우다.
        val days = KoreanHolidays.of(2026, anchors2026())
        assertEquals(java.time.DayOfWeek.SATURDAY, d(2026, 9, 26).dayOfWeek)
        assertFalse("토요일만 물었는데 대체공휴일이 생겼다", days.containsKey(d(2026, 9, 28)))
    }

    @Test
    fun `대체공휴일은 주말에 앉히지 않는다`() {
        // 2026년 개천절은 토요일이고 그 다음 날은 일요일이다. 대체는 월요일이어야 한다.
        val days = KoreanHolidays.of(2026, anchors2026())
        assertTrue(days.containsKey(d(2026, 10, 5)))
        assertEquals(Holiday.SUBSTITUTE, days[d(2026, 10, 5)])
        assertFalse(days.containsKey(d(2026, 10, 4)))
    }

    @Test
    fun `연휴 이름은 대체공휴일과 구분된다`() {
        val days = KoreanHolidays.of(2026, anchors2026())
        assertEquals(Holiday.SEOLLAL, days[d(2026, 2, 16)])
        assertEquals(Holiday.CHUSEOK, days[d(2026, 9, 25)])
        assertEquals(Holiday.SUBSTITUTE, days[d(2026, 3, 2)])
    }
}
