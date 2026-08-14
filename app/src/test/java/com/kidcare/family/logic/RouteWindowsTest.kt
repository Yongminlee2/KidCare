package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteWindowsTest {

    @Test
    fun `구간이 없으면 창도 없다`() {
        assertTrue(RouteWindows.partition(emptyList()).isEmpty())
    }

    @Test
    fun `구간 하나면 하루 전체가 그 창이다`() {
        val windows = RouteWindows.partition(listOf(1_000L..2_000L))
        assertEquals(listOf(Long.MIN_VALUE..Long.MAX_VALUE), windows)
    }

    @Test
    fun `두 구간 사이 공백은 한가운데에서 갈린다`() {
        // 이동 1000~2000, 머무름 2000~6000, 이동 6000~9000 → 경계는 4000.
        val windows = RouteWindows.partition(listOf(1_000L..2_000L, 6_000L..9_000L))
        assertEquals(Long.MIN_VALUE..3_999L, windows[0])
        assertEquals(4_000L..Long.MAX_VALUE, windows[1])
    }

    @Test
    fun `모든 시각이 정확히 한 창에 들어간다`() {
        val windows = RouteWindows.partition(
            listOf(1_000L..2_000L, 6_000L..9_000L, 20_000L..30_000L),
        )
        // 머무름 기준점(3500), 마지막 이동 뒤의 최신 점(99999)까지 전부 어딘가에 속한다.
        for (at in listOf(0L, 1_500L, 3_500L, 4_100L, 15_000L, 99_999L)) {
            assertEquals("at=$at", 1, windows.count { at in it })
        }
    }

    @Test
    fun `정렬 안 된 입력도 시작 시각 순으로 창을 돌려준다`() {
        val windows = RouteWindows.partition(listOf(6_000L..9_000L, 1_000L..2_000L))
        assertTrue(windows[0].first < windows[1].first)
    }
}
