package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SegmentBuilderTest {

    private val baseLat = 37.5665
    private val baseLng = 126.9780
    private val t0 = 1_700_000_000_000L

    /** 기준점에서 북쪽으로 [meters] 만큼, [minutes] 분 뒤의 점. 위도 1도 = 약 111,320m. */
    private fun p(meters: Double, minutes: Long, accuracy: Float = 10f) = Fix(
        lat = baseLat + meters / 111_320.0,
        lng = baseLng,
        accuracy = accuracy,
        at = t0 + minutes * 60_000L,
    )

    @Test
    fun `점이 없으면 구간도 없다`() {
        assertEquals(emptyList<Segment>(), SegmentBuilder.build(emptyList()))
    }

    @Test
    fun `점이 하나면 구간을 만들지 않는다`() {
        // 구간은 시작과 끝이 있어야 의미가 있다. 점 하나로는 머무름인지 이동인지 알 수 없다.
        assertEquals(emptyList<Segment>(), SegmentBuilder.build(listOf(p(0.0, 0))))
    }

    @Test
    fun `하루 종일 같은 자리에 있으면 머무름 하나로 묶인다`() {
        val points = (0..20).map { p(it * 2.0, it * 10L) }   // 10분 간격, 2m 씩만 흔들림
        val segments = SegmentBuilder.build(points)
        assertEquals(1, segments.size)
        assertEquals(SegmentType.STAY, segments[0].type)
        assertEquals(t0, segments[0].startAt)
        assertEquals(t0 + 200 * 60_000L, segments[0].endAt)
        assertEquals(21, segments[0].pointCount)
    }

    @Test
    fun `5분을 못 채운 정지는 머무름이 아니다`() {
        // 0분과 3분에 같은 자리, 그 뒤 멀리 이동 → 정지 3분은 머무름이 아니라 이동에 흡수된다.
        val points = listOf(
            p(0.0, 0), p(5.0, 3),
            p(2000.0, 10), p(4000.0, 20),
        )
        val segments = SegmentBuilder.build(points)
        assertTrue("머무름이 하나도 없어야 한다: $segments", segments.none { it.type == SegmentType.STAY })
    }

    @Test
    fun `정확히 5분 머무르면 머무름으로 인정한다`() {
        // 경계값. MIN_STAY_MILLIS 는 '이상' 이어야 한다.
        val points = listOf(p(0.0, 0), p(5.0, 5), p(3000.0, 20), p(6000.0, 30))
        val segments = SegmentBuilder.build(points)
        assertEquals(SegmentType.STAY, segments.first().type)
        assertEquals(5 * 60_000L, segments.first().endAt - segments.first().startAt)
    }

    @Test
    fun `GPS 가 한 번 튀어도 머무름이 깨지지 않는다`() {
        // 반경을 벗어난 점이 연속 2개여야 머무름이 끝난다. 1개는 튄 것으로 본다.
        val points = listOf(
            p(0.0, 0), p(10.0, 10),
            p(500.0, 20),           // 튐 (연속 1개)
            p(15.0, 30), p(20.0, 40),
        )
        val segments = SegmentBuilder.build(points)
        assertEquals(1, segments.size)
        assertEquals(SegmentType.STAY, segments[0].type)
        assertEquals(t0 + 40 * 60_000L, segments[0].endAt)
    }

    @Test
    fun `반경을 벗어난 점이 연속 두 개면 머무름이 끝난다`() {
        val points = listOf(
            p(0.0, 0), p(10.0, 10), p(20.0, 20),
            p(3000.0, 30), p(6000.0, 40),        // 연속 2개 → 머무름 종료
            p(9000.0, 50), p(12000.0, 60),
        )
        val segments = SegmentBuilder.build(points)
        assertEquals(SegmentType.STAY, segments[0].type)
        assertEquals(t0 + 20 * 60_000L, segments[0].endAt)
        assertEquals(SegmentType.MOVE, segments[1].type)
    }

    @Test
    fun `머무름 이동 머무름 순서로 나온다`() {
        val points = buildList {
            // 학교: 0~40분
            addAll((0..4).map { p(it * 5.0, it * 10L) })
            // 이동: 50~60분
            add(p(1500.0, 50)); add(p(3000.0, 60))
            // 학원: 70~120분 (3000m 지점 근처)
            addAll((0..5).map { p(3000.0 + it * 5.0, 70 + it * 10L) })
        }
        val segments = SegmentBuilder.build(points)
        assertEquals(
            listOf(SegmentType.STAY, SegmentType.MOVE, SegmentType.STAY),
            segments.map { it.type },
        )
    }

    @Test
    fun `이동 구간은 앞뒤 머무름과 시각이 이어진다`() {
        // 지도에 선을 그릴 때 구간 사이가 끊기면 안 된다.
        val points = buildList {
            addAll((0..4).map { p(it * 5.0, it * 10L) })
            add(p(1500.0, 50)); add(p(3000.0, 60))
            addAll((0..5).map { p(3000.0 + it * 5.0, 70 + it * 10L) })
        }
        val segments = SegmentBuilder.build(points)
        for (i in 0 until segments.size - 1) {
            assertEquals(
                "구간 $i 의 끝과 ${i + 1} 의 시작이 어긋난다: $segments",
                segments[i].endAt, segments[i + 1].startAt,
            )
        }
    }

    @Test
    fun `이동 거리는 점 사이 거리의 합이다`() {
        val points = listOf(
            p(0.0, 0), p(5.0, 5),          // 머무름
            p(1000.0, 20), p(2000.0, 30),  // 이동
            p(3000.0, 40), p(3005.0, 50),  // 머무름
        )
        val move = SegmentBuilder.build(points).first { it.type == SegmentType.MOVE }
        assertTrue("이동 거리가 ${move.distanceMeters}m 로 예상 범위(2800~3200)를 벗어났다",
            move.distanceMeters in 2800.0..3200.0)
    }

    @Test
    fun `머무름의 좌표는 그 구간 점들의 평균이다`() {
        val points = listOf(p(0.0, 0), p(100.0, 5), p(3000.0, 30), p(6000.0, 40))
        val stay = SegmentBuilder.build(points).first { it.type == SegmentType.STAY }
        // 0m 와 100m 의 평균 = 50m 지점
        val expectedLat = baseLat + 50.0 / 111_320.0
        assertEquals(expectedLat, stay.lat, 1e-6)
    }

    @Test
    fun `시각이 뒤섞여 들어와도 정렬해서 처리한다`() {
        // Firestore 쿼리 결과 순서를 믿지 않는다.
        val ordered = (0..10).map { p(it * 2.0, it * 10L) }
        assertEquals(SegmentBuilder.build(ordered), SegmentBuilder.build(ordered.shuffled()))
    }

    @Test
    fun `정확도가 나쁜 점은 계산에서 뺀다`() {
        // 100m 초과 오차는 LocationFilter 가 이미 업로드 단계에서 걸러내지만,
        // 옛 데이터나 다른 경로로 섞여 들어올 수 있으므로 여기서도 방어한다.
        val points = listOf(
            p(0.0, 0), p(5.0, 10),
            p(5000.0, 15, accuracy = 500f),   // 오차 500m — 무시돼야 한다
            p(10.0, 20), p(15.0, 30),
        )
        val segments = SegmentBuilder.build(points)
        assertEquals(1, segments.size)
        assertEquals(SegmentType.STAY, segments[0].type)
        assertEquals(4, segments[0].pointCount)
    }
}
