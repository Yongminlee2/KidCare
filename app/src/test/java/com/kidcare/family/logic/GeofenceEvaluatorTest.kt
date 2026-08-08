package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GeofenceEvaluatorTest {

    private val school = Place("p1", "학교", 37.5000, 127.0000, 200.0, true, true)

    /** 반경 안의 좌표. 위도 1도는 약 111km 라 0.001도는 약 111m 다. */
    private fun near(at: Long, dLat: Double) =
        Fix(37.5000 + dLat, 127.0000, 10f, at)

    /** 밖에 있었다는 기억. 처음 보는 장소는 판정이 다르므로(아래) 여기서 갈라 둔다. */
    private fun wasOutside(lastEventAt: Long = 1000L) =
        listOf(PlaceState("p1", inside = false, lastEventAt = lastEventAt))

    @Test
    fun `반경 안으로 들어오면 도착이다`() {
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(school), wasOutside(), near(999_000L, 0.0),
        )
        assertEquals(1, hits.size)
        assertTrue(hits[0].entering)
        assertTrue(states[0].inside)
    }

    @Test
    fun `이미 안에 있으면 다시 도착하지 않는다`() {
        val inside = PlaceState("p1", inside = true, lastEventAt = 1000L)
        val (hits, _) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(inside), near(999_000L, 0.0),
        )
        assertTrue(hits.isEmpty())
    }

    @Test
    fun `반경을 살짝 벗어난 것으로는 이탈이 아니다`() {
        // 반경 200m + 여유 50m = 250m 를 넘어야 이탈이다. 0.002도 = 약 222m.
        val inside = PlaceState("p1", inside = true, lastEventAt = 1000L)
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(inside), near(999_000L, 0.002),
        )
        assertTrue(hits.isEmpty())
        assertTrue("아직 안에 있는 것으로 본다", states[0].inside)
    }

    @Test
    fun `여유까지 벗어나면 이탈이다`() {
        // 0.003도 = 약 333m > 250m
        val inside = PlaceState("p1", inside = true, lastEventAt = 1000L)
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(inside), near(999_000L, 0.003),
        )
        assertEquals(1, hits.size)
        assertTrue(!hits[0].entering)
        assertTrue(!states[0].inside)
    }

    @Test
    fun `같은 장소의 같은 방향은 5분 안에 두 번 나오지 않는다`() {
        val justLeft = PlaceState("p1", inside = false, lastEventAt = 1_000_000L)
        // 1분 뒤 다시 들어옴 — 경계에 앉아 있는 상황
        val (hits, _) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(justLeft), near(1_060_000L, 0.0),
        )
        assertTrue("5분이 안 지났으므로 알리지 않는다", hits.isEmpty())
    }

    @Test
    fun `5분이 지나면 다시 알린다`() {
        val justLeft = PlaceState("p1", inside = false, lastEventAt = 1_000_000L)
        val (hits, _) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(justLeft), near(1_400_000L, 0.0),
        )
        assertEquals(1, hits.size)
    }

    @Test
    fun `알림을 끈 방향은 상태만 바뀌고 알리지 않는다`() {
        val quiet = school.copy(notifyEnter = false)
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(quiet), wasOutside(), near(999_000L, 0.0),
        )
        assertTrue("알림은 없다", hits.isEmpty())
        assertTrue("그래도 안에 있다는 사실은 기억한다", states[0].inside)
    }

    @Test
    fun `오차가 큰 점은 판정에 쓰지 않는다`() {
        // 정확도 300m 짜리 점으로 반경 200m 장소의 도착을 판정할 수는 없다.
        val vague = Fix(37.5000, 127.0000, 300f, 1000L)
        val (hits, states) = GeofenceEvaluator.evaluate(listOf(school), emptyList(), vague)
        assertTrue(hits.isEmpty())
        assertTrue("상태도 건드리지 않는다", states.isEmpty())
    }

    @Test
    fun `장소가 없으면 아무 일도 없다`() {
        val (hits, states) = GeofenceEvaluator.evaluate(emptyList(), emptyList(), near(1000L, 0.0))
        assertTrue(hits.isEmpty())
        assertTrue(states.isEmpty())
    }

    @Test
    fun `지워진 장소의 상태는 따라서 사라진다`() {
        val stale = PlaceState("없어진장소", inside = true, lastEventAt = 1000L)
        val (_, states) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(stale), near(999_000L, 0.0),
        )
        assertEquals(1, states.size)
        assertEquals("p1", states[0].placeId)
    }

    @Test
    fun `처음 보는 장소는 안에 있어도 알리지 않고 기억만 한다`() {
        // 부모가 방금 장소를 만들었는데 아이가 마침 그 안에 있는 상황이다. 여기서
        // "도착했어요"를 보내면 세 시간 전에 일어난 일을 지금 시각으로 지어내게 된다.
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(school), emptyList(), near(1000L, 0.0),
        )
        assertTrue("건너오는 것을 본 적이 없으면 도착이 아니다", hits.isEmpty())
        assertTrue("안에 있다는 사실은 기억한다", states[0].inside)
        assertEquals("알린 적이 없으므로 0 이다", 0L, states[0].lastEventAt)
    }

    @Test
    fun `처음 본 직후에 진짜로 나가면 그건 곧바로 알린다`() {
        // 위 시험의 다음 장면. 5분 억제는 '방금 알린 것'을 막는 장치지, 알린 적이
        // 없는 첫 사건까지 막으면 안 된다 — lastEventAt 0 이 그 구분이다.
        val (_, seeded) = GeofenceEvaluator.evaluate(listOf(school), emptyList(), near(1000L, 0.0))
        val (hits, _) = GeofenceEvaluator.evaluate(listOf(school), seeded, near(61_000L, 0.003))
        assertEquals(1, hits.size)
        assertTrue("이탈이다", !hits[0].entering)
    }

    @Test
    fun `경계에서 30초마다 뒤집혀도 5분에 한 번만 알린다`() {
        // 억제된 전환이 5분 시계를 다시 감으면 알림이 하나도 안 가고, 시계를 아예
        // 안 재면 스무 번이 간다. 둘 다 고장이다.
        var states = listOf(PlaceState("p1", inside = false, lastEventAt = 400_000L))
        var count = 0
        for (k in 0 until 20) {
            val (hits, next) = GeofenceEvaluator.evaluate(
                listOf(school), states,
                near(1_030_000L + k * 30_000L, if (k % 2 == 0) 0.0 else 0.003),
            )
            count += hits.size
            states = next
        }
        assertEquals("9분 30초 동안 두 번", 2, count)
    }

    @Test
    fun `알리지 않은 전환은 다음 알림의 5분 시계를 건드리지 않는다`() {
        val enterOnly = school.copy(notifyExit = false)
        val (first, afterEnter) = GeofenceEvaluator.evaluate(
            listOf(enterOnly), wasOutside(), near(1_000_000L, 0.0),
        )
        assertEquals(1, first.size)
        // 이탈은 부모가 끄라고 했으니 안 알린다. 그런데 이때 시계를 감으면 100초 뒤의
        // 진짜 도착이 '방금 알렸다'는 이유로 사라진다 — 아무도 못 본 사건 때문에.
        val (none, afterExit) = GeofenceEvaluator.evaluate(
            listOf(enterOnly), afterEnter, near(1_400_000L, 0.003),
        )
        assertTrue(none.isEmpty())
        val (again, _) = GeofenceEvaluator.evaluate(
            listOf(enterOnly), afterExit, near(1_500_000L, 0.0),
        )
        assertEquals("마지막으로 알린 지 500초가 지났다", 1, again.size)
    }

    @Test
    fun `오차가 큰 점은 지워진 장소의 상태까지 그대로 둔다`() {
        // 못 믿는 점에서는 아무 판단도 안 한다 — 지운 장소를 청소하는 것도 판단이다.
        // 다음 좋은 점 하나면 사라지므로 남겨두는 쪽이 싸고, 이 상태를 읽는 곳은
        // 이 함수뿐이라 남아 있는 동안 아무 일도 하지 않는다.
        val stale = PlaceState("없어진장소", inside = true, lastEventAt = 1000L)
        val vague = Fix(37.5000, 127.0000, 300f, 1000L)
        val (_, states) = GeofenceEvaluator.evaluate(listOf(school), listOf(stale), vague)
        assertEquals(listOf(stale), states)
    }

    @Test
    fun `시계가 뒤로 간 폰도 영영 조용해지지 않는다`() {
        // 폰 시계가 한 번 미래로 틀어져 있었으면 lastEventAt 이 미래에 남는다.
        // 그 음수 시간차를 '아직 5분이 안 지났다'로 읽으면 그 폰은 다시는 안 울린다.
        val future = PlaceState("p1", inside = false, lastEventAt = 9_999_999_999L)
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(future), near(1_000_000L, 0.0),
        )
        assertEquals(1, hits.size)
        assertEquals("시계는 이번 점 기준으로 다시 맞춰진다", 1_000_000L, states[0].lastEventAt)
    }

    @Test
    fun `장소가 여럿이면 각각 판정한다`() {
        // 집은 학교에서 약 1.1km 다. 한 점이 학교 도착이면서 동시에 집 이탈이다.
        val home = Place("p2", "집", 37.5100, 127.0000, 200.0, true, true)
        val states = listOf(
            PlaceState("p1", inside = false, lastEventAt = 1000L),
            PlaceState("p2", inside = true, lastEventAt = 1000L),
        )
        val (hits, next) = GeofenceEvaluator.evaluate(
            listOf(school, home), states, near(999_000L, 0.0),
        )
        assertEquals(
            setOf("p1" to true, "p2" to false),
            hits.map { it.placeId to it.entering }.toSet(),
        )
        assertEquals(2, next.size)
    }
}
