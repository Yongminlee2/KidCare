package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RoutePathRefinerTest {

    private fun fix(at: Long, east: Double, accuracy: Float = 10f, speed: Float = 1.2f) = Fix(
        lat = 37.5665,
        lng = 126.9780 + east / 88_800.0,
        accuracy = accuracy,
        at = at,
        speed = speed,
    )

    @Test
    fun `오차가 큰 중간 점은 실제 선에 사용하지 않는다`() {
        val legs = RoutePathRefiner.refine(
            listOf(fix(1_000L, 0.0), fix(6_000L, 20.0, accuracy = 70f), fix(11_000L, 12.0))
        )
        assertEquals(1, legs.size)
        assertEquals(2, legs.single().points.size)
    }

    @Test
    fun `긴 GPS 공백 뒤 멀리 떨어진 위치는 직선으로 잇지 않는다`() {
        val legs = RoutePathRefiner.refine(
            listOf(fix(1_000L, 0.0), fix(6_000L, 8.0), fix(700_000L, 500.0))
        )
        assertEquals(2, legs.size)
    }

    @Test
    fun `부정확한 지그재그는 완화하고 정확한 출발점은 지킨다`() {
        val raw = listOf(
            fix(1_000L, 0.0, accuracy = 8f),
            fix(6_000L, 20.0, accuracy = 25f),
            fix(11_000L, 4.0, accuracy = 25f),
            fix(16_000L, 24.0, accuracy = 25f),
        )
        val refined = RoutePathRefiner.refine(raw).single().points
        assertEquals(raw.first().lat, refined.first().lat, 0.0)
        assertEquals(raw.first().lng, refined.first().lng, 0.0)
        val rawSwing = kotlin.math.abs(raw[2].lng - raw[1].lng)
        val refinedSwing = kotlin.math.abs(refined[2].lng - refined[1].lng)
        assertTrue(refinedSwing < rawSwing)
    }

    @Test
    fun `정확한 마지막 점은 현재 위치와 맞게 그대로 둔다`() {
        val raw = listOf(fix(1_000L, 0.0), fix(6_000L, 7.0), fix(11_000L, 14.0, accuracy = 8f))
        val refined = RoutePathRefiner.refine(raw).single().points
        assertEquals(raw.last().lat, refined.last().lat, 0.0)
        assertEquals(raw.last().lng, refined.last().lng, 0.0)
    }

    @Test
    fun `한 점만 멀리 튀었다 바로 돌아온 GPS 스파이크는 제거한다`() {
        val refined = RoutePathRefiner.refine(
            listOf(fix(1_000L, 0.0), fix(6_000L, 70.0), fix(11_000L, 4.0))
        ).single().points

        assertEquals(2, refined.size)
        assertEquals(fix(1_000L, 0.0).lng, refined.first().lng, 0.0)
        assertEquals(fix(11_000L, 4.0).lng, refined.last().lng, 0.0)
    }

    @Test
    fun `계속 같은 방향으로 이동한 정상 경로는 스파이크로 제거하지 않는다`() {
        val refined = RoutePathRefiner.refine(
            listOf(fix(1_000L, 0.0), fix(6_000L, 35.0), fix(11_000L, 70.0))
        ).single().points

        assertEquals(3, refined.size)
    }
}
