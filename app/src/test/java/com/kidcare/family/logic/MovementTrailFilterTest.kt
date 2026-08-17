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
    fun `버스 구간의 40m 오차 점도 경로에 남긴다`() {
        // 상한이 30m 이던 시절 이 점은 정확도만으로 거절돼 경로 중간이 통째로 비었다.
        // 상한은 이제 50m 다.
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
    fun `걷는 5초 변위는 오차가 거칠어도 경로점으로 남긴다`() {
        // **이 테스트가 이번 변경의 핵심이다.** 아이가 5초 동안 걷는 거리는 약 6m 인데,
        // 예전에는 오차 반경(hypot)을 요구해서 오차 20m 면 28m 를 넘어야 기록했다.
        // 즉 걸어서는 경로점이 하나도 안 남았다. 이제 3m 만 넘으면 남기고, 흔들림
        // 정리는 그리는 쪽(RoutePathRefiner)이 맡는다.
        assertTrue(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 20f),
                fix(5_000L, metersEast = 6.0, accuracy = 20f),
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
    fun `같은 자리의 반복 좌표는 기록하지 않는다`() {
        // 3m 문턱이 걸러내는 것은 "사실상 같은 점"뿐이다.
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 10f),
                fix(5_000L, metersEast = 2.0, accuracy = 10f),
                reportedMoving = true,
            )
        )
    }

    @Test
    fun `속도가 없어도 실제로 이동하면 기록한다`() {
        assertTrue(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 10f),
                fix(5_000L, metersEast = 16.0, accuracy = 10f),
                reportedMoving = true,
            )
        )
    }

    @Test
    fun `정지로 판정된 동안에는 무엇이 와도 기록하지 않는다`() {
        // 제자리 흔들림을 막는 책임은 이제 이 필터가 아니라 상류의 이동 판정기에 있다.
        // 판정기가 정지라고 하면(reportedMoving=false) 거친 점이든 속도가 튄 점이든
        // 한 줄도 안 남는다 — 그것이 이 구조에서 정지 보호가 사는 자리다.
        assertFalse(
            MovementTrailFilter.shouldRecord(
                fix(0L, accuracy = 25f),
                fix(5_000L, metersEast = 20.0, accuracy = 25f, speed = 4f),
                reportedMoving = false,
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
