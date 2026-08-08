package com.kidcare.family.logic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MovementTrailFilterTest {

    private fun fix(
        at: Long,
        metersEast: Double = 0.0,
        accuracy: Float = 5f,
        speed: Float = 0f,
    ) = Fix(
        lat = 37.5665,
        lng = 126.9780 + metersEast / 88_800.0,
        accuracy = accuracy,
        at = at,
        speed = speed,
    )

    @Test
    fun `정지 상태에서는 위치가 흔들려도 기록하지 않는다`() {
        assertFalse(MovementTrailFilter.shouldRecord(null, fix(5_000L), reportedMoving = false))
    }

    @Test
    fun `이동 상태의 첫 정확한 점은 출발점으로 남긴다`() {
        assertTrue(MovementTrailFilter.shouldRecord(null, fix(5_000L), reportedMoving = true))
    }

    @Test
    fun `오차가 큰 점은 이동 중에도 버린다`() {
        assertFalse(
            MovementTrailFilter.shouldRecord(
                null, fix(5_000L, accuracy = 51f), reportedMoving = true,
            )
        )
    }

    @Test
    fun `5초가 되기 전 후보는 기록하지 않는다`() {
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L), fix(4_999L, metersEast = 20.0, speed = 1.2f), reportedMoving = true,
            )
        )
    }

    @Test
    fun `보행 속도가 확인되면 5초마다 기록한다`() {
        assertTrue(
            MovementTrailFilter.shouldRecord(
                fix(0L), fix(5_000L, metersEast = 4.0, speed = 1.2f), reportedMoving = true,
            )
        )
    }

    @Test
    fun `속도가 없으면 오차 반경 안의 변화는 흔들림으로 본다`() {
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 10f),
                fix(5_000L, metersEast = 8.0, accuracy = 10f),
                reportedMoving = true,
            )
        )
    }

    @Test
    fun `속도가 없어도 오차 반경 밖으로 이동하면 기록한다`() {
        assertTrue(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 10f),
                fix(5_000L, metersEast = 16.0, accuracy = 10f),
                reportedMoving = true,
            )
        )
    }

    @Test
    fun `실내의 부정확한 속도값은 정지 흔들림을 이동으로 만들지 않는다`() {
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 25f),
                fix(5_000L, metersEast = 20.0, accuracy = 25f, speed = 4f),
                reportedMoving = true,
            )
        )
    }

    @Test
    fun `순간이동 좌표는 경로에 넣지 않는다`() {
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L), fix(5_000L, metersEast = 1_000.0, speed = 0f), reportedMoving = true,
            )
        )
    }

    @Test
    fun `기기가 비현실적인 속도를 보고하면 경로에 넣지 않는다`() {
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L), fix(5_000L, metersEast = 10.0, speed = 60f), reportedMoving = true,
            )
        )
    }
}
