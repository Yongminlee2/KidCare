package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocationFilterTest {

    private val seoulCityHall = Fix(37.5665, 126.9780, accuracy = 10f, at = 1_000_000L)

    private fun near(meters: Double, afterMillis: Long, accuracy: Float = 10f): Fix {
        // 위도 1도 = 약 111,320m. 북쪽으로 meters 만큼 옮긴다.
        return Fix(
            lat = seoulCityHall.lat + meters / 111_320.0,
            lng = seoulCityHall.lng,
            accuracy = accuracy,
            at = seoulCityHall.at + afterMillis,
        )
    }

    @Test
    fun `첫 위치는 무조건 올린다`() {
        assertEquals(Decision.UPLOAD, LocationFilter.decide(null, seoulCityHall))
    }

    @Test
    fun `정확도가 나쁘면 버린다`() {
        val bad = seoulCityHall.copy(accuracy = 150f)
        assertEquals(Decision.REJECT_INACCURATE, LocationFilter.decide(null, bad))
    }

    @Test
    fun `정확도 100m 는 경계값으로 받아들인다`() {
        val edge = seoulCityHall.copy(accuracy = 100f)
        assertEquals(Decision.UPLOAD, LocationFilter.decide(null, edge))
    }

    @Test
    fun `50m 안 움직였으면 건너뛴다`() {
        val barelyMoved = near(meters = 30.0, afterMillis = 60_000L)
        assertEquals(Decision.SKIP_TOO_CLOSE, LocationFilter.decide(seoulCityHall, barelyMoved))
    }

    @Test
    fun `50m 넘게 움직이면 올린다`() {
        val moved = near(meters = 80.0, afterMillis = 60_000L)
        assertEquals(Decision.UPLOAD, LocationFilter.decide(seoulCityHall, moved))
    }

    @Test
    fun `안 움직여도 10분이 지나면 살아있다고 한 번 올린다`() {
        val stillThere = near(meters = 5.0, afterMillis = 10 * 60 * 1000L)
        assertEquals(Decision.UPLOAD, LocationFilter.decide(seoulCityHall, stillThere))
    }

    @Test
    fun `시속 200km 를 넘는 이동은 GPS 오류로 보고 버린다`() {
        // 1초 만에 1km 이동 = 시속 3600km
        val teleport = near(meters = 1000.0, afterMillis = 1000L)
        assertEquals(Decision.REJECT_IMPOSSIBLE, LocationFilter.decide(seoulCityHall, teleport))
    }

    @Test
    fun `시간이 거꾸로 간 위치는 버린다`() {
        val past = near(meters = 500.0, afterMillis = -60_000L)
        assertEquals(Decision.REJECT_IMPOSSIBLE, LocationFilter.decide(seoulCityHall, past))
    }

    @Test
    fun `하버사인 거리가 실제와 비슷하다`() {
        // 서울시청 → 광화문, 약 1,050m
        val gwanghwamun = Fix(37.5759, 126.9769, 10f, 2_000_000L)
        val d = LocationFilter.distanceMeters(seoulCityHall, gwanghwamun)
        assertTrue("계산된 거리가 $d m 로 예상 범위(900~1100m)를 벗어났다", d in 900.0..1100.0)
    }
}
