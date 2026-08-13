package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveLocationRefinerTest {

    private val first = Fix(37.5665, 126.9780, 10f, 1_000_000L)

    @Test
    fun `정확도가 50m를 넘는 위치는 버린다`() {
        assertNull(LiveLocationRefiner.refine(first, first.copy(accuracy = 51f, at = 1_002_000L)))
    }

    @Test
    fun `정지 중 작은 흔들림은 두 좌표 사이로 완화한다`() {
        val jitter = first.copy(lat = first.lat + 4.0 / 111_320.0, at = 1_002_000L)
        val refined = LiveLocationRefiner.refine(first, jitter)!!

        assertTrue(refined.lat > first.lat)
        assertTrue(refined.lat < jitter.lat)
        assertEquals(jitter.at, refined.at)
    }

    @Test
    fun `속도가 확인된 실제 이동은 최신 측정값을 그대로 쓴다`() {
        val moving = first.copy(
            lat = first.lat + 8.0 / 111_320.0,
            at = 1_002_000L,
            speed = 4f,
            speedAccuracy = 1f,
        )
        assertEquals(moving, LiveLocationRefiner.refine(first, moving))
    }

    @Test
    fun `물리적으로 불가능한 순간이동은 버린다`() {
        val teleport = first.copy(lat = first.lat + 1_000.0 / 111_320.0, at = 1_002_000L)
        assertNull(LiveLocationRefiner.refine(first, teleport))
    }
}
