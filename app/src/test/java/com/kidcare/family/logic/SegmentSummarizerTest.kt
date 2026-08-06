package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.ZoneId

class SegmentSummarizerTest {

    private val seoul: ZoneId = ZoneId.of("Asia/Seoul")

    private fun segment(startAt: Long, endAt: Long) = Segment(
        type = SegmentType.STAY,
        startAt = startAt, endAt = endAt,
        lat = 37.5, lng = 127.0, distanceMeters = 0.0, pointCount = 2,
    )

    @Test
    fun `시각 범위를 시분으로 보여준다`() {
        // 2026-08-07 14:10 KST = 05:10 UTC
        val start = 1_786_000_200_000L   // 아래 주석 참고
        val zoned = java.time.Instant.ofEpochMilli(start).atZone(seoul)
        val expected = "%02d:%02d~%02d:%02d".format(
            zoned.hour, zoned.minute,
            zoned.plusMinutes(90).hour, zoned.plusMinutes(90).minute,
        )
        assertEquals(expected, SegmentSummarizer.timeRange(segment(start, start + 90 * 60_000L), seoul))
    }

    @Test
    fun `자정을 넘는 구간도 시분만 보여준다`() {
        // 날짜별로 나눠 보여주는 화면이라 날짜는 헤더가 담당한다. 여기서는 시분만.
        val start = 1_786_000_200_000L
        val text = SegmentSummarizer.timeRange(segment(start, start + 12 * 3_600_000L), seoul)
        assertEquals(11, text.length)          // "HH:mm~HH:mm"
        assertEquals('~', text[5])
    }

    @Test
    fun `시간대가 다르면 표시도 달라진다`() {
        val start = 1_786_000_200_000L
        val seoulText = SegmentSummarizer.timeRange(segment(start, start + 60_000L), seoul)
        val utcText = SegmentSummarizer.timeRange(segment(start, start + 60_000L), ZoneId.of("UTC"))
        assertEquals("서울과 UTC 는 9시간 차이라 표시가 같을 수 없다", false, seoulText == utcText)
    }

    @Test
    fun `한 시간 이상이면 시간과 분을 함께 쓴다`() {
        assertEquals("1시간 30분", SegmentSummarizer.durationText(90 * 60_000L))
        assertEquals("2시간 5분", SegmentSummarizer.durationText(125 * 60_000L))
    }

    @Test
    fun `정각이면 분을 붙이지 않는다`() {
        assertEquals("2시간", SegmentSummarizer.durationText(120 * 60_000L))
    }

    @Test
    fun `한 시간 미만이면 분만 쓴다`() {
        assertEquals("25분", SegmentSummarizer.durationText(25 * 60_000L))
    }

    @Test
    fun `1분 미만은 따로 표기한다`() {
        assertEquals("1분 미만", SegmentSummarizer.durationText(30_000L))
        assertEquals("1분 미만", SegmentSummarizer.durationText(0L))
    }

    @Test
    fun `1km 이상은 킬로미터로 소수 한 자리까지 쓴다`() {
        assertEquals("1.2km", SegmentSummarizer.distanceText(1234.0))
        assertEquals("12.3km", SegmentSummarizer.distanceText(12_345.0))
    }

    @Test
    fun `1km 미만은 미터로 십 단위까지 쓴다`() {
        // 아이 위치에 1m 단위 정밀도를 보여주는 것은 없는 정확도를 있는 척하는 것이다.
        assertEquals("480m", SegmentSummarizer.distanceText(483.0))
        assertEquals("50m", SegmentSummarizer.distanceText(51.0))
    }

    @Test
    fun `아주 짧은 거리는 0m 대신 10m 미만으로 쓴다`() {
        assertEquals("10m 미만", SegmentSummarizer.distanceText(4.0))
        assertEquals("10m 미만", SegmentSummarizer.distanceText(0.0))
    }
}
