package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaceNameCacheTest {

    private val homeLat = 37.5665
    private val homeLng = 126.9780

    /** 기준점에서 북쪽으로 [meters] 만큼. 위도 1도 = 약 111,320m. */
    private fun north(meters: Double) = homeLat + meters / 111_320.0

    @Test
    fun `이름 좌표가 몇 미터 흔들려도 같은 이름을 찾는다`() {
        // **이 테스트가 느리던 이유를 막는 자리다.** 예전 캐시는 소수점 4자리로 반올림한
        // 좌표를 열쇠로 써서, 머무름 평균이 몇 미터만 움직여도 못 찾고 인터넷에 다시 물었다.
        val cache = PlaceNameCache()
        cache.put(homeLat, homeLng, "우리집")
        assertEquals("우리집", cache.find(north(12.0), homeLng))
    }

    @Test
    fun `반경 밖이면 찾지 않는다`() {
        val cache = PlaceNameCache()
        cache.put(homeLat, homeLng, "우리집")
        assertNull(cache.find(north(100.0), homeLng))
    }

    @Test
    fun `여럿이 반경 안이면 가장 가까운 이름을 준다`() {
        val cache = PlaceNameCache(matchRadiusMeters = 60.0)
        cache.put(homeLat, homeLng, "우리집")
        cache.put(north(50.0), homeLng, "놀이터")
        assertEquals("놀이터", cache.find(north(40.0), homeLng))
    }

    @Test
    fun `같은 자리에 다시 넣으면 한 칸만 차지한다`() {
        val cache = PlaceNameCache()
        cache.put(homeLat, homeLng, "우리집")
        cache.put(north(5.0), homeLng, "우리집")
        cache.put(north(9.0), homeLng, "우리집")
        assertEquals(1, cache.size)
    }

    @Test
    fun `상한을 넘으면 오래된 곳부터 버린다`() {
        val cache = PlaceNameCache(maxEntries = 2)
        cache.put(homeLat, homeLng, "첫째")
        cache.put(north(500.0), homeLng, "둘째")
        cache.put(north(1_000.0), homeLng, "셋째")
        assertEquals(2, cache.size)
        assertNull(cache.find(homeLat, homeLng))
        assertEquals("셋째", cache.find(north(1_000.0), homeLng))
    }

    @Test
    fun `저장했다 되읽으면 그대로다`() {
        val cache = PlaceNameCache()
        cache.put(homeLat, homeLng, "우리집")
        cache.put(north(800.0), homeLng, "피아노 학원")
        val restored = PlaceNameCache.decode(cache.encode())
        assertEquals(2, restored.size)
        assertEquals("피아노 학원", restored.find(north(805.0), homeLng))
    }

    @Test
    fun `망가진 줄은 건너뛰고 나머지는 살린다`() {
        val text = "이상한 줄\n37.5,abc\t깨진곳\n$homeLat,$homeLng\t우리집\n\n"
        val restored = PlaceNameCache.decode(text)
        assertEquals(1, restored.size)
        assertEquals("우리집", restored.find(homeLat, homeLng))
    }

    @Test
    fun `빈 이름은 넣지 않고 탭과 줄바꿈은 공백으로 바꾼다`() {
        val cache = PlaceNameCache()
        cache.put(homeLat, homeLng, "   ")
        assertEquals(0, cache.size)
        cache.put(homeLat, homeLng, "학원\t2층\n본관")
        assertEquals("학원 2층 본관", PlaceNameCache.decode(cache.encode()).find(homeLat, homeLng))
    }
}
