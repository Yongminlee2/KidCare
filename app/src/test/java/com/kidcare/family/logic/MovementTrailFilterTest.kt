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
        speedAccuracy: Float = Float.POSITIVE_INFINITY,
    ) = Fix(
        lat = 37.5665,
        lng = 126.9780 + metersEast / 88_800.0,
        accuracy = accuracy,
        at = at,
        speed = speed,
        speedAccuracy = speedAccuracy,
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
    fun `버스 구간의 40m 오차 점도 오차 이상 움직였으면 경로에 남긴다`() {
        // 30m 상한이던 시절 이 점이 거절돼 경로 중간이 통째로 비었다.
        // noiseRadius = hypot(40,40) ≈ 57m 이므로 80m 변위면 흔들림이 아니다.
        assertTrue(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 40f),
                fix(5_000L, metersEast = 80.0, accuracy = 40f),
                reportedMoving = true,
            )
        )
    }

    @Test
    fun `정지 주기 사이 150m 변위는 이동의 증거다`() {
        assertTrue(
            MovementTrailFilter.isDisplacementEvidence(
                fix(0L, accuracy = 40f),
                fix(300_000L, metersEast = 160.0, accuracy = 40f),
            )
        )
    }

    @Test
    fun `150m 미만 변위는 오차 흔들림일 수 있어 증거가 아니다`() {
        assertFalse(
            MovementTrailFilter.isDisplacementEvidence(
                fix(0L, accuracy = 50f),
                fix(300_000L, metersEast = 99.0, accuracy = 50f),
            )
        )
    }

    @Test
    fun `이전 점이 없으면 변위 증거를 만들 수 없다`() {
        assertFalse(
            MovementTrailFilter.isDisplacementEvidence(null, fix(300_000L, metersEast = 500.0))
        )
    }

    @Test
    fun `오차 상한을 넘는 점은 변위 증거로 쓰지 않는다`() {
        assertFalse(
            MovementTrailFilter.isDisplacementEvidence(
                fix(0L),
                fix(300_000L, metersEast = 500.0, accuracy = 80f),
            )
        )
    }

    @Test
    fun `순간이동 속도의 변위는 증거가 아니라 오류다`() {
        assertFalse(
            MovementTrailFilter.isDisplacementEvidence(
                fix(0L),
                fix(1_000L, metersEast = 500.0),
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
    fun `좌표가 그대로인데 속도만 튄 점은 이동 경로로 기록하지 않는다`() {
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L), fix(5_000L, speed = 1.2f), reportedMoving = true,
            )
        )
    }

    @Test
    fun `속도 오차를 빼도 이동 중이고 실제 변위가 있으면 기록한다`() {
        assertTrue(
            MovementTrailFilter.shouldRecord(
                fix(0L),
                fix(5_000L, metersEast = 6.0, speed = 1.3f, speedAccuracy = 0.4f),
                reportedMoving = true,
            )
        )
    }

    @Test
    fun `속도 오차가 속도만큼 큰 점은 속도 근거로 기록하지 않는다`() {
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 10f),
                fix(
                    5_000L,
                    metersEast = 6.0,
                    accuracy = 10f,
                    speed = 1.2f,
                    speedAccuracy = 1.1f,
                ),
                reportedMoving = true,
            )
        )
    }

    @Test
    fun `15m 정확도에서도 보행 속도가 확인되면 모퉁이를 남긴다`() {
        assertTrue(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 15f),
                fix(5_000L, metersEast = 6.0, accuracy = 15f, speed = 1.2f),
                reportedMoving = true,
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
