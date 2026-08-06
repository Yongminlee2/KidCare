package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class DayPickerTest {

    private val seoul: ZoneId = ZoneId.of("Asia/Seoul")

    /** 2026-08-07 14:00 KST */
    private val now = java.time.LocalDateTime.of(2026, 8, 7, 14, 0)
        .atZone(seoul).toInstant().toEpochMilli()

    @Test
    fun `오늘 키는 기기 시간대 기준이다`() {
        assertEquals("2026-08-07", DayPicker.todayKey(seoul, now))
    }

    @Test
    fun `시간대가 다르면 날짜가 달라질 수 있다`() {
        // 서울 8월 7일 14:00 은 UTC 로 8월 7일 05:00 — 같은 날이지만,
        // 서울 8월 7일 08:00 은 UTC 로 8월 6일 23:00 이다.
        val earlyMorning = java.time.LocalDateTime.of(2026, 8, 7, 8, 0)
            .atZone(seoul).toInstant().toEpochMilli()
        assertEquals("2026-08-07", DayPicker.todayKey(seoul, earlyMorning))
        assertEquals("2026-08-06", DayPicker.todayKey(ZoneId.of("UTC"), earlyMorning))
    }

    @Test
    fun `하루 앞뒤로 옮긴다`() {
        assertEquals("2026-08-06", DayPicker.shift("2026-08-07", -1))
        assertEquals("2026-08-08", DayPicker.shift("2026-08-07", 1))
    }

    @Test
    fun `월과 해의 경계를 넘는다`() {
        assertEquals("2026-07-31", DayPicker.shift("2026-08-01", -1))
        assertEquals("2027-01-01", DayPicker.shift("2026-12-31", 1))
    }

    @Test
    fun `윤년 2월을 정확히 넘는다`() {
        // 2028년은 윤년이다.
        assertEquals("2028-02-29", DayPicker.shift("2028-02-28", 1))
        assertEquals("2028-03-01", DayPicker.shift("2028-02-29", 1))
    }

    @Test
    fun `내일은 미래다`() {
        assertTrue(DayPicker.isFuture("2026-08-08", seoul, now))
        assertFalse(DayPicker.isFuture("2026-08-07", seoul, now))
        assertFalse(DayPicker.isFuture("2026-08-06", seoul, now))
    }

    @Test
    fun `오늘과 어제는 이름으로 부른다`() {
        assertEquals("오늘", DayPicker.headerText("2026-08-07", seoul, now))
        assertEquals("어제", DayPicker.headerText("2026-08-06", seoul, now))
    }

    @Test
    fun `그 이전은 날짜와 요일로 쓴다`() {
        // 2026-08-05 는 수요일이다.
        assertEquals("8월 5일 (수)", DayPicker.headerText("2026-08-05", seoul, now))
    }
}
