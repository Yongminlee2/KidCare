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
        val points = listOf(p(0.0, 0), p(30.0, 5), p(3000.0, 30), p(6000.0, 40))
        val stay = SegmentBuilder.build(points).first { it.type == SegmentType.STAY }
        // 0m 와 30m 의 평균 = 15m 지점 (두 점 다 머무름 반경 40m 안이다)
        val expectedLat = baseLat + 15.0 / 111_320.0
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

    @Test
    fun `완화 문턱으로 올라온 거친 점은 계산에서 빼지 않는다`() {
        // 오차 50~100m 는 LocationFilter 가 "오래 아무것도 못 올렸을 때" 일부러
        // 올린 점이다(UPLOAD_STALE_FALLBACK). 여기서 빼 버리면 신호가 나쁜 날에
        // 지도 마커만 움직이고 타임라인은 텅 비는 상태가 된다.
        val points = listOf(
            p(0.0, 0), p(5.0, 10, accuracy = 90f), p(10.0, 20), p(15.0, 30),
        )
        val segments = SegmentBuilder.build(points)
        assertEquals(1, segments.size)
        assertEquals(4, segments[0].pointCount)
    }

    @Test
    fun `이름 좌표는 정확한 점 쪽으로 끌린다`() {
        // 도착 순간 한 번 크게 튄 fix(오차 90m)가 이름을 정하면 옆 건물이 나온다.
        // 단순 평균은 그 점을 그대로 끌어안지만 이름 좌표는 정확한 점 쪽에 붙어야 한다.
        // 나쁜 점도 머무름 반경(40m) 안이어야 같은 구간에 들어간다 — 밖으로 나가면
        // 이건 이름 문제가 아니라 구간이 갈리는 문제가 된다.
        val points = listOf(
            p(30.0, 0, accuracy = 90f),   // 도착 순간의 나쁜 점
            p(0.0, 10), p(0.0, 20), p(0.0, 30),
        )
        val stay = SegmentBuilder.build(points).first { it.type == SegmentType.STAY }
        val badLat = baseLat + 30.0 / 111_320.0
        val goodLat = baseLat

        val nameOffset = Math.abs(stay.nameLat - goodLat)
        val meanOffset = Math.abs(stay.lat - goodLat)
        assertTrue(
            "이름 좌표가 단순 평균보다 좋은 점에 가까워야 한다: name=${stay.nameLat} mean=${stay.lat}",
            nameOffset < meanOffset,
        )
        assertTrue(
            "이름 좌표가 나쁜 점 쪽으로 끌려갔다: ${stay.nameLat}",
            Math.abs(stay.nameLat - badLat) > Math.abs(stay.nameLat - goodLat),
        )
    }

    @Test
    fun `오차가 모두 같으면 이름 좌표는 단순 평균과 같다`() {
        // 가중치가 균일하면 가중 평균은 산술 평균이다 — 가중이 공짜로 좌표를
        // 흔들지 않는다는 확인이다.
        val points = listOf(p(0.0, 0), p(30.0, 5), p(3000.0, 30), p(6000.0, 40))
        val stay = SegmentBuilder.build(points).first { it.type == SegmentType.STAY }
        assertEquals(stay.lat, stay.nameLat, 1e-9)
        assertEquals(stay.lng, stay.nameLng, 1e-9)
    }

    @Test
    fun `오차 0 인 옛 점이 이름 좌표를 독점하지 않는다`() {
        // 옛 points 문서는 accuracy 가 0 으로 읽힌다. 0 은 완벽하다는 뜻이 아니라
        // 모른다는 뜻이라, 1/0² 로 무한대 가중치를 주면 안 된다.
        val points = listOf(
            p(30.0, 0, accuracy = 0f),
            p(0.0, 10), p(0.0, 20), p(0.0, 30),
        )
        val stay = SegmentBuilder.build(points).first { it.type == SegmentType.STAY }
        val loneLat = baseLat + 30.0 / 111_320.0

        // floor 가 없으면 1/0² = 무한대라 이 값이 NaN 이거나 loneLat 과 정확히 같아진다.
        assertTrue("이름 좌표가 유한해야 한다: ${stay.nameLat}", stay.nameLat.isFinite())
        assertTrue(
            "오차 0 짜리 점 하나가 이름 좌표를 통째로 가져갔다: ${stay.nameLat}",
            stay.nameLat < loneLat,
        )
        assertTrue(
            "나머지 점들이 이름 좌표를 통째로 가져갔다: ${stay.nameLat}",
            stay.nameLat > baseLat,
        )
    }

    @Test
    fun `이동 구간의 이름 좌표는 도착 지점 그대로다`() {
        val points = listOf(
            p(0.0, 0), p(5.0, 5),
            p(3000.0, 30), p(6000.0, 40),
        )
        val move = SegmentBuilder.build(points).first { it.type == SegmentType.MOVE }
        assertEquals(move.lat, move.nameLat, 1e-12)
        assertEquals(move.lng, move.nameLng, 1e-12)
    }
}
