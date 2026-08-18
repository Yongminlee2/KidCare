package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

class ScheduleResolverTest {

    private val seoul: ZoneId = ZoneId.of("Asia/Seoul")

    private fun at(y: Int, m: Int, d: Int, h: Int, min: Int): Long =
        LocalDateTime.of(y, m, d, h, min).atZone(seoul).toInstant().toEpochMilli()

    private fun rule(
        id: String = "r", days: Set<Int> = setOf(1, 2, 3, 4, 5),
        start: Int = 9 * 60, end: Int = 15 * 60,
        mode: String = "vibrate", enabled: Boolean = true, priority: Int = 0,
    ) = ScheduleRule(id, days, start, end, mode, enabled, priority)

    // ------------------------------------------------------------------ 공휴일

    /** 2026-03-02(월)은 삼일절 대체공휴일이다. 그 주 월요일 하나만 쉬는 날이 된다. */
    private val substituteMonday = setOf(LocalDate.of(2026, 3, 2))

    @Test
    fun `공휴일에는 평일 규칙이 시작하지 않는다`() {
        val r = ScheduleResolver.resolveAt(
            listOf(rule()), at(2026, 3, 2, 10, 0), seoul, substituteMonday,
        )
        assertNull("대체공휴일 낮인데 평일 규칙이 걸렸다", r.mode)
    }

    @Test
    fun `공휴일 집합이 비면 예전처럼 요일만 본다`() {
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 3, 2, 10, 0), seoul)
        assertEquals("vibrate", r.mode)
    }

    @Test
    fun `공휴일 다음 날에는 다시 규칙이 돈다`() {
        val r = ScheduleResolver.resolveAt(
            listOf(rule()), at(2026, 3, 3, 10, 0), seoul, substituteMonday,
        )
        assertEquals("vibrate", r.mode)
    }

    @Test
    fun `공휴일 전날 밤에 시작한 규칙은 그 아침까지 이어진다`() {
        // 평일 22:00~07:00 규칙이 일요일 밤에 시작할 리는 없으니 금요일 밤으로 본다.
        // 2026-02-27(금) 밤에 시작해 28일 새벽까지 가는 구간이다. 시작일 기준이라는
        // 규칙이 요일과 공휴일 양쪽에 똑같이 적용되는지 확인한다.
        val night = rule(start = 22 * 60, end = 7 * 60)
        val holidays = setOf(LocalDate.of(2026, 2, 28))
        val r = ScheduleResolver.resolveAt(listOf(night), at(2026, 2, 28, 3, 0), seoul, holidays)
        assertEquals("28일이 쉬는 날이어도 27일 밤에 시작한 구간은 이어져야 한다", "vibrate", r.mode)
    }

    @Test
    fun `다음 경계도 공휴일을 건너뛴다`() {
        // 월요일이 쉬는 날이면 다음 시작은 화요일 09:00 이어야 한다.
        val r = ScheduleResolver.resolveAt(
            listOf(rule()), at(2026, 3, 2, 6, 0), seoul, substituteMonday,
        )
        assertEquals(at(2026, 3, 3, 9, 0), r.nextBoundaryMillis)
    }

    @Test
    fun `규칙이 없으면 강제하는 모드도 없다`() {
        val r = ScheduleResolver.resolveAt(emptyList(), at(2026, 8, 7, 10, 0), seoul)
        assertNull(r.mode)
        assertNull(r.nextBoundaryMillis)
    }

    @Test
    fun `꺼진 규칙은 무시한다`() {
        val rules = listOf(rule(enabled = false))
        assertNull(ScheduleResolver.resolveAt(rules, at(2026, 8, 7, 10, 0), seoul).mode)
    }

    @Test
    fun `평일 규칙이 금요일 낮에 적용된다`() {
        // 2026-08-07 은 금요일이다.
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 10, 0), seoul)
        assertEquals("vibrate", r.mode)
    }

    @Test
    fun `평일 규칙이 토요일에는 적용되지 않는다`() {
        // 2026-08-08 은 토요일이다.
        assertNull(ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 8, 10, 0), seoul).mode)
    }

    @Test
    fun `시작 시각 정각에 이미 적용된다`() {
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 9, 0), seoul)
        assertEquals("vibrate", r.mode)
    }

    @Test
    fun `끝 시각 정각에는 이미 풀린다`() {
        // 09:00~15:00 은 15:00 을 포함하지 않는다. 안 그러면 15:00 에 시작하는
        // 다음 규칙과 한 순간 겹친다.
        assertNull(ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 15, 0), seoul).mode)
    }

    @Test
    fun `자정을 넘는 규칙이 밤에 적용된다`() {
        val night = rule(id = "n", days = setOf(1, 2, 3, 4, 5, 6, 7),
                         start = 22 * 60, end = 7 * 60, mode = "silent")
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(night), at(2026, 8, 7, 23, 30), seoul).mode)
    }

    @Test
    fun `자정을 넘는 규칙이 새벽에도 적용된다`() {
        val night = rule(id = "n", days = setOf(1, 2, 3, 4, 5, 6, 7),
                         start = 22 * 60, end = 7 * 60, mode = "silent")
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(night), at(2026, 8, 8, 3, 0), seoul).mode)
    }

    @Test
    fun `자정을 넘는 규칙의 요일은 시작 시각 기준이다`() {
        // "평일 22:00~07:00" 은 금요일 밤에 시작하므로 토요일 새벽까지 이어진다.
        // 2026-08-07(금) 23:00 시작 -> 2026-08-08(토) 03:00 까지 적용.
        val night = rule(id = "n", days = setOf(1, 2, 3, 4, 5),
                         start = 22 * 60, end = 7 * 60, mode = "silent")
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(night), at(2026, 8, 8, 3, 0), seoul).mode)
        // 반대로 토요일 밤 23:00 은 토요일이 요일 집합에 없으므로 적용되지 않는다.
        assertNull(ScheduleResolver.resolveAt(listOf(night), at(2026, 8, 8, 23, 0), seoul).mode)
    }

    @Test
    fun `겹치면 우선순위가 큰 쪽이 이긴다`() {
        val a = rule(id = "a", mode = "vibrate", priority = 0)
        val b = rule(id = "b", mode = "silent", priority = 5)
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(a, b), at(2026, 8, 7, 10, 0), seoul).mode)
    }

    @Test
    fun `우선순위가 같으면 나중에 시작한 규칙이 이긴다`() {
        val early = rule(id = "e", start = 9 * 60, end = 15 * 60, mode = "vibrate")
        val late = rule(id = "l", start = 10 * 60, end = 15 * 60, mode = "silent")
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(early, late), at(2026, 8, 7, 11, 0), seoul).mode)
    }

    @Test
    fun `다음 경계 시각을 알려준다`() {
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 10, 0), seoul)
        assertEquals(at(2026, 8, 7, 15, 0), r.nextBoundaryMillis)
    }

    @Test
    fun `적용 중이 아닐 때는 다음 시작 시각이 경계다`() {
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 7, 0), seoul)
        assertNull(r.mode)
        assertEquals(at(2026, 8, 7, 9, 0), r.nextBoundaryMillis)
    }

    @Test
    fun `겹치는 규칙을 찾아준다`() {
        val existing = rule(id = "a", start = 9 * 60, end = 15 * 60)
        val candidate = rule(id = "b", start = 14 * 60, end = 18 * 60)
        val hits = ScheduleResolver.overlapsOf(listOf(existing), candidate)
        assertEquals(listOf("a"), hits.map { it.id })
    }

    @Test
    fun `자기 자신과는 겹친다고 하지 않는다`() {
        val a = rule(id = "a")
        assertTrue(ScheduleResolver.overlapsOf(listOf(a), a).isEmpty())
    }

    @Test
    fun `요일이 안 겹치면 시간이 겹쳐도 충돌이 아니다`() {
        val weekday = rule(id = "a", days = setOf(1, 2, 3, 4, 5))
        val weekend = rule(id = "b", days = setOf(6, 7))
        assertTrue(ScheduleResolver.overlapsOf(listOf(weekday), weekend).isEmpty())
    }
}
