package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptiveMovementDetectorTest {

    private fun fix(
        seconds: Long,
        metersEast: Double = 0.0,
        accuracy: Float = 5f,
        speed: Float = 0f,
        speedAccuracy: Float = Float.POSITIVE_INFINITY,
    ) = Fix(
        lat = 37.5665,
        lng = 126.9780 + metersEast / 88_800.0,
        accuracy = accuracy,
        at = seconds * 1_000L,
        speed = speed,
        speedAccuracy = speedAccuracy,
    )

    @Test
    fun `GPS 흔들림만 30초 이어지면 느린 확인으로 전환한다`() {
        val detector = AdaptiveMovementDetector()
        listOf(0L to 0.0, 5L to 3.0, 10L to -2.0, 20L to 4.0, 30L to 1.0)
            .forEach { (time, distance) -> detector.onFix(fix(time, distance)) }

        assertEquals(AdaptiveMovementState.SLOW_PROBE, detector.state)
    }

    @Test
    fun `오차 반경 안의 작은 흔들림은 이동으로 확정하지 않는다`() {
        // 오차 10m 에서 문턱은 max(15, hypot(10,10)×1.0) = 15m 다.
        // 20초 동안 9m 는 서 있는 폰의 흔들림 범위라 확정하면 안 된다.
        val detector = AdaptiveMovementDetector()
        detector.onFix(fix(0, 0.0, accuracy = 10f))
        detector.onFix(fix(10, 5.0, accuracy = 10f))
        val result = detector.onFix(fix(20, 9.0, accuracy = 10f))

        assertEquals(AdaptiveMovementState.FAST_PROBE, result.state)
        assertTrue(result.promotionBuffer.isEmpty())
    }

    @Test
    fun `속도값이 없어도 걷는 속도로 꾸준히 나아가면 이동으로 확정한다`() {
        // **이 테스트가 이 판정기의 존재 이유다.** 아이가 집 앞 놀이터에 걸어가는 것이
        // 정확히 이 모양이다 — 20초에 24m(=1.2m/s), 오차 10m, 속도값 없음.
        // 예전 배수(×2)에서는 문턱이 28m 라 통과할 수 없었고, 그래서 판정기가 영영
        // 저주기에 머물러 경로가 한 줄도 안 남았다.
        val detector = AdaptiveMovementDetector()
        detector.onFix(fix(0, 0.0, accuracy = 10f))
        detector.onFix(fix(10, 12.0, accuracy = 10f))
        val result = detector.onFix(fix(20, 24.0, accuracy = 10f))

        assertEquals(AdaptiveMovementState.MOVING, result.state)
        assertTrue("출발 부분이 잘리지 않게 확정 직전 점들을 돌려준다", result.promotionBuffer.isNotEmpty())
    }

    @Test
    fun `저주기로 내려가도 걷는 거리면 다시 확인으로 올라온다`() {
        // 한번 저주기에 갇히면 못 나오던 함정. 30초 간격 두 점이 36m(=1.2m/s) 벌어지면
        // 걷고 있는 것이므로 빠른 확인으로 복귀해야 한다. 예전에는 오차 15m 에서
        // 42m 를 요구해 걸어서는 복귀가 불가능했다.
        val detector = AdaptiveMovementDetector()
        detector.reset(fast = false)
        detector.onFix(fix(0, 0.0, accuracy = 15f))
        val result = detector.onFix(fix(30, 36.0, accuracy = 15f))

        assertEquals(AdaptiveMovementState.FAST_PROBE, result.state)
    }

    @Test
    fun `오차 상한을 넘는 좌표는 이동 판정 표본에서 제외한다`() {
        // 상한은 50m 다(30m 시절에는 버스·번화가의 30~50m 구간이 통째로 빠졌다).
        val detector = AdaptiveMovementDetector()
        for (seconds in 0L..30L step 5L) {
            detector.onFix(
                fix(seconds, seconds * 8.0, accuracy = 55f, speed = 2f, speedAccuracy = 0.1f),
            )
        }

        assertEquals(AdaptiveMovementState.SLOW_PROBE, detector.state)
    }

    @Test
    fun `45m 오차라도 오차 배수 이상 꾸준히 나아가면 이동으로 확정한다`() {
        // 버스 구간의 전형: 오차는 거칠지만 30초에 240m 를 전진한다. 확정 문턱이
        // 오차에 비례(hypot×2 ≈ 127m)하므로 정지 흔들림은 여기 못 미친다.
        val detector = AdaptiveMovementDetector()
        var promoted = false
        for (seconds in 0L..30L step 5L) {
            val result = detector.onFix(fix(seconds, seconds * 8.0, accuracy = 45f))
            if (result.state == AdaptiveMovementState.MOVING) promoted = true
        }

        assertTrue(promoted)
    }

    @Test
    fun `지속적인 보행은 세 점 뒤 실제 이동으로 확정한다`() {
        val detector = AdaptiveMovementDetector()
        detector.onFix(fix(0, 0.0, speed = 1.2f, speedAccuracy = 0.2f))
        detector.onFix(fix(5, 7.0, speed = 1.2f, speedAccuracy = 0.2f))
        val result = detector.onFix(fix(10, 14.0, speed = 1.2f, speedAccuracy = 0.2f))

        assertEquals(AdaptiveMovementState.MOVING, result.state)
        assertEquals(3, result.promotionBuffer.size)
    }

    @Test
    fun `속도 정보가 없어도 오차보다 큰 지속 이동은 확정한다`() {
        val detector = AdaptiveMovementDetector()
        detector.onFix(fix(0, 0.0, accuracy = 7f))
        detector.onFix(fix(5, 20.0, accuracy = 7f))
        val result = detector.onFix(fix(10, 34.0, accuracy = 7f))

        assertEquals(AdaptiveMovementState.MOVING, result.state)
    }

    @Test
    fun `느린 확인 중 큰 변화가 보이면 바로 빠른 확인으로 복귀한다`() {
        val detector = AdaptiveMovementDetector()
        listOf(0L, 10L, 20L, 30L).forEach { detector.onFix(fix(it)) }
        assertEquals(AdaptiveMovementState.SLOW_PROBE, detector.state)

        detector.onFix(fix(60, 35.0))
        assertEquals(AdaptiveMovementState.FAST_PROBE, detector.state)
    }

    @Test
    fun `이동 확정 뒤 60초간 머물면 느린 확인으로 내려간다`() {
        val detector = AdaptiveMovementDetector()
        detector.onFix(fix(0, 0.0, speed = 1.2f, speedAccuracy = 0.2f))
        detector.onFix(fix(5, 7.0, speed = 1.2f, speedAccuracy = 0.2f))
        detector.onFix(fix(10, 14.0, speed = 1.2f, speedAccuracy = 0.2f))
        assertEquals(AdaptiveMovementState.MOVING, detector.state)

        var result = AdaptiveMovementUpdate(detector.state)
        for (seconds in 15L..75L step 5) {
            result = detector.onFix(fix(seconds, 14.0 + (seconds % 3)))
        }
        assertEquals(AdaptiveMovementState.SLOW_PROBE, result.state)
        assertTrue(result.promotionBuffer.isEmpty())
    }
}
