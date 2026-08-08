package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class TrailCodecTest {

    private fun fix(at: Long, lat: Double = 37.5665, lng: Double = 126.9780) =
        Fix(lat = lat, lng = lng, accuracy = 12.5f, at = at, speed = 1.25f)

    @Test
    fun `한 점을 줄로 바꿨다가 되돌리면 그대로다`() {
        val original = fix(1_754_500_000_000L)
        val decoded = TrailCodec.decode(TrailCodec.encodeLine(original))
        assertEquals(listOf(original), decoded)
    }

    @Test
    fun `여러 줄을 순서 그대로 되돌린다`() {
        val points = listOf(fix(100L), fix(200L, lat = 37.6), fix(300L, lng = 127.1))
        val text = points.joinToString("\n") { TrailCodec.encodeLine(it) }
        assertEquals(points, TrailCodec.decode(text))
    }

    @Test
    fun `깨진 줄은 버리고 나머지는 살린다`() {
        // 파일 끝에 덧붙이는 방식이라 프로세스가 쓰기 도중 죽으면 마지막 줄이 잘린다.
        // 그 한 줄 때문에 하루치를 통째로 잃으면 안 된다.
        val good = fix(100L)
        val text = TrailCodec.encodeLine(good) + "\n37.5,126.9,10.0"
        assertEquals(listOf(good), TrailCodec.decode(text))
    }

    @Test
    fun `숫자가 아닌 값이 섞인 줄도 버린다`() {
        val good = fix(100L)
        val text = "abc,def,ghi,jkl,mno\n" + TrailCodec.encodeLine(good)
        assertEquals(listOf(good), TrailCodec.decode(text))
    }

    @Test
    fun `빈 문자열은 빈 목록이다`() {
        assertEquals(emptyList<Fix>(), TrailCodec.decode(""))
    }

    @Test
    fun `상한 이하면 목록을 그대로 돌려준다`() {
        val points = (1..10).map { fix(it.toLong()) }
        // 새 리스트를 만들지 않는다 — 정상적인 하루는 전부 이 경로를 지난다.
        assertSame(points, TrailCodec.capped(points))
    }

    @Test
    fun `상한을 넘으면 출발과 도착을 남기고 하루 전체에서 고른다`() {
        val points = (1..TrailCodec.MAX_POINTS + 500).map { fix(it.toLong()) }
        val capped = TrailCodec.capped(points)
        assertEquals(TrailCodec.MAX_POINTS, capped.size)
        assertEquals(points.first(), capped.first())
        assertEquals(points.last(), capped.last())
        assertTrue(capped.zipWithNext().all { (a, b) -> a.at < b.at })
    }

    @Test
    fun `상한을 넘겨도 경로의 큰 회전점은 남긴다`() {
        val cornerIndex = TrailCodec.MAX_POINTS / 2
        val points = (0..TrailCodec.MAX_POINTS + 500).map { index ->
            fix(
                at = index.toLong(),
                lat = if (index == cornerIndex) 37.9 else 37.5665,
                lng = 126.9780 + index * 0.000001,
            )
        }
        val capped = TrailCodec.capped(points)
        assertTrue(capped.contains(points[cornerIndex]))
    }

    @Test
    fun `상한에 딱 맞으면 아무것도 안 버린다`() {
        val points = (1..TrailCodec.MAX_POINTS).map { fix(it.toLong()) }
        assertEquals(points, TrailCodec.capped(points))
    }

    @Test
    fun `서버 경로 상한은 이천 점이다`() {
        // 이보다 키우는 것은 Firestore 문서 크기 측정 없이 해서는 안 된다.
        assertEquals(2_000, TrailCodec.MAX_POINTS)
    }
}
