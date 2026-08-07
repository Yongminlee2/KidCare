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
    fun `정확도 50m 는 경계값으로 받아들인다`() {
        // 문턱은 '초과'여야 한다. 딱 50m 는 통과다. 완화(UPLOAD_STALE_FALLBACK)가
        // 아니라 평소 승인(UPLOAD)이어야 경계가 맞다 — 첫 위치라 완화 창이 열려
        // 있는 상태인데도 평소 문턱만으로 통과한다는 뜻이다.
        val edge = seoulCityHall.copy(accuracy = 50f)
        assertEquals(Decision.UPLOAD, LocationFilter.decide(null, edge))
    }

    @Test
    fun `50m 를 조금만 넘어도 평소에는 버린다`() {
        // 경계 바로 위. 완화 창이 아직 안 열렸으므로 거절이 맞다.
        val justOver = near(meters = 5.0, afterMillis = 60_000L, accuracy = 50.001f)
        assertEquals(Decision.REJECT_INACCURATE, LocationFilter.decide(seoulCityHall, justOver))
    }

    @Test
    fun `60m 짜리 점은 평소에는 버린다`() {
        val coarse = near(meters = 5.0, afterMillis = 60_000L, accuracy = 60f)
        assertEquals(Decision.REJECT_INACCURATE, LocationFilter.decide(seoulCityHall, coarse))
    }

    @Test
    fun `15분 동안 못 올렸으면 같은 60m 짜리 점도 받아들인다`() {
        // 거친 점이라도 빈 지도보다는 낫다. UPLOAD 가 아니라 완화 승인으로 구분된다 —
        // 이게 UPLOAD 면 문턱을 그냥 100m 로 되돌려도 통과해 버려 완화 경로를 못 잡는다.
        val coarse = near(meters = 5.0, afterMillis = 15 * 60 * 1000L, accuracy = 60f)
        assertEquals(Decision.UPLOAD_STALE_FALLBACK, LocationFilter.decide(seoulCityHall, coarse))
    }

    @Test
    fun `완화 창의 경계는 15분이다`() {
        // 1밀리초 모자라면 아직 평소 문턱이다.
        val justBefore = near(meters = 5.0, afterMillis = 15 * 60 * 1000L - 1, accuracy = 60f)
        assertEquals(Decision.REJECT_INACCURATE, LocationFilter.decide(seoulCityHall, justBefore))
    }

    @Test
    fun `완화 창이 열려도 120m 짜리 점은 버린다`() {
        // 완화는 옛 문턱(100m)까지다. 그 위는 창이 열려 있어도 못 믿는다.
        val tooCoarse = near(meters = 5.0, afterMillis = 30 * 60 * 1000L, accuracy = 120f)
        assertEquals(Decision.REJECT_INACCURATE, LocationFilter.decide(seoulCityHall, tooCoarse))
    }

    @Test
    fun `완화 창이 열려도 순간이동은 버린다`() {
        // 완화가 순간이동 검사보다 뒤에 있어야 한다 — 목이 마르다고 튄 좌표를
        // 받아들이면 지도에 아이가 가지도 않은 곳이 찍힌다.
        // 15분에 1000km = 시속 4000km.
        val teleport = near(meters = 1_000_000.0, afterMillis = 15 * 60 * 1000L, accuracy = 60f)
        assertEquals(Decision.REJECT_IMPOSSIBLE, LocationFilter.decide(seoulCityHall, teleport))
    }

    @Test
    fun `첫 위치는 올린 게 없으므로 완화 문턱을 그대로 쓴다`() {
        // previous == null 은 '부모 화면이 통째로 비어 있다' = 가장 목마른 상태다.
        val coarse = seoulCityHall.copy(accuracy = 90f)
        assertEquals(Decision.UPLOAD_STALE_FALLBACK, LocationFilter.decide(null, coarse))
    }

    @Test
    fun `25m 안 움직였으면 건너뛴다`() {
        val barelyMoved = near(meters = 10.0, afterMillis = 60_000L)
        assertEquals(Decision.SKIP_TOO_CLOSE, LocationFilter.decide(seoulCityHall, barelyMoved))
    }

    @Test
    fun `25m 넘게 움직이면 올린다`() {
        // 옛 문턱(50m)에서는 건너뛰던 거리다. 경로선이 모퉁이를 자르지 않게 하려고 내렸다.
        val moved = near(meters = 30.0, afterMillis = 60_000L)
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
