import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `app/src/test/.../AdaptiveMovementDetectorTest.kt` 다 — `@Test` 를 하나도 빼지 않고 옮겼다.
struct AdaptiveMovementDetectorTests {

    /// 코틀린 `fix(...)` 도우미 그대로. 경도 1도 ≈ 88,800m, `at` 은 초 × 1000.
    private func fix(
        _ seconds: Int64,
        metersEast: Double = 0,
        accuracy: Double = 5,
        speed: Double = 0,
        speedAccuracy: Double = .infinity
    ) -> Fix {
        Fix(
            lat: 37.5665,
            lng: 126.9780 + metersEast / 88_800.0,
            accuracy: accuracy,
            at: seconds * 1_000,
            speed: speed,
            speedAccuracy: speedAccuracy
        )
    }

    @Test("GPS 흔들림만 30초 이어지면 느린 확인으로 전환한다")
    func 흔들림_30초() {
        let detector = AdaptiveMovementDetector()
        for (time, distance) in [(Int64(0), 0.0), (5, 3.0), (10, -2.0), (20, 4.0), (30, 1.0)] {
            _ = detector.onFix(fix(time, metersEast: distance))
        }
        #expect(detector.state == .slowProbe)
    }

    @Test("오차 반경 안의 작은 흔들림은 이동으로 확정하지 않는다")
    func 작은_흔들림() {
        // 오차 10m 에서 문턱은 max(15, hypot(10,10)×1.0) = 15m 다.
        // 20초 동안 9m 는 서 있는 폰의 흔들림 범위라 확정하면 안 된다.
        let detector = AdaptiveMovementDetector()
        _ = detector.onFix(fix(0, metersEast: 0, accuracy: 10))
        _ = detector.onFix(fix(10, metersEast: 5, accuracy: 10))
        let result = detector.onFix(fix(20, metersEast: 9, accuracy: 10))

        #expect(result.state == .fastProbe)
        #expect(result.promotionBuffer.isEmpty)
    }

    @Test("속도값이 없어도 걷는 속도로 꾸준히 나아가면 이동으로 확정한다")
    func 보행_확정() {
        // **이 테스트가 이 판정기의 존재 이유다.** 20초에 24m(=1.2m/s), 오차 10m, 속도값 없음.
        // 예전 배수(×2)에서는 문턱이 28m 라 통과할 수 없었고, 판정기가 영영 저주기에 머물렀다.
        let detector = AdaptiveMovementDetector()
        _ = detector.onFix(fix(0, metersEast: 0, accuracy: 10))
        _ = detector.onFix(fix(10, metersEast: 12, accuracy: 10))
        let result = detector.onFix(fix(20, metersEast: 24, accuracy: 10))

        #expect(result.state == .moving)
        #expect(!result.promotionBuffer.isEmpty, "출발 부분이 잘리지 않게 확정 직전 점들을 돌려준다")
    }

    @Test("저주기로 내려가도 걷는 거리면 다시 확인으로 올라온다")
    func 저주기_복귀() {
        // 한번 저주기에 갇히면 못 나오던 함정. 30초 간격 두 점이 36m(=1.2m/s) 벌어지면 걷고 있는 것이다.
        let detector = AdaptiveMovementDetector()
        detector.reset(fast: false)
        _ = detector.onFix(fix(0, metersEast: 0, accuracy: 15))
        let result = detector.onFix(fix(30, metersEast: 36, accuracy: 15))

        #expect(result.state == .fastProbe)
    }

    @Test("오차 상한을 넘는 좌표는 이동 판정 표본에서 제외한다")
    func 오차_상한_제외() {
        // 상한은 50m 다(30m 시절에는 버스·번화가의 30~50m 구간이 통째로 빠졌다).
        let detector = AdaptiveMovementDetector()
        for seconds in stride(from: Int64(0), through: 30, by: 5) {
            _ = detector.onFix(
                fix(seconds, metersEast: Double(seconds) * 8, accuracy: 55, speed: 2, speedAccuracy: 0.1)
            )
        }
        #expect(detector.state == .slowProbe)
    }

    @Test("45m 오차라도 오차 배수 이상 꾸준히 나아가면 이동으로 확정한다")
    func 거친_오차_확정() {
        // 버스 구간의 전형: 오차는 거칠지만 30초에 240m 를 전진한다.
        let detector = AdaptiveMovementDetector()
        var promoted = false
        for seconds in stride(from: Int64(0), through: 30, by: 5) {
            let result = detector.onFix(fix(seconds, metersEast: Double(seconds) * 8, accuracy: 45))
            if result.state == .moving { promoted = true }
        }
        #expect(promoted)
    }

    @Test("지속적인 보행은 세 점 뒤 실제 이동으로 확정한다")
    func 세_점_확정() {
        let detector = AdaptiveMovementDetector()
        _ = detector.onFix(fix(0, metersEast: 0, speed: 1.2, speedAccuracy: 0.2))
        _ = detector.onFix(fix(5, metersEast: 7, speed: 1.2, speedAccuracy: 0.2))
        let result = detector.onFix(fix(10, metersEast: 14, speed: 1.2, speedAccuracy: 0.2))

        #expect(result.state == .moving)
        #expect(result.promotionBuffer.count == 3)
    }

    @Test("속도 정보가 없어도 오차보다 큰 지속 이동은 확정한다")
    func 속도_없이_확정() {
        let detector = AdaptiveMovementDetector()
        _ = detector.onFix(fix(0, metersEast: 0, accuracy: 7))
        _ = detector.onFix(fix(5, metersEast: 20, accuracy: 7))
        let result = detector.onFix(fix(10, metersEast: 34, accuracy: 7))

        #expect(result.state == .moving)
    }

    @Test("느린 확인 중 큰 변화가 보이면 바로 빠른 확인으로 복귀한다")
    func 느린_확인_복귀() {
        let detector = AdaptiveMovementDetector()
        for seconds in [Int64(0), 10, 20, 30] { _ = detector.onFix(fix(seconds)) }
        #expect(detector.state == .slowProbe)

        _ = detector.onFix(fix(60, metersEast: 35))
        #expect(detector.state == .fastProbe)
    }

    @Test("이동 확정 뒤 60초간 머물면 느린 확인으로 내려간다")
    func 정지_확인() {
        let detector = AdaptiveMovementDetector()
        _ = detector.onFix(fix(0, metersEast: 0, speed: 1.2, speedAccuracy: 0.2))
        _ = detector.onFix(fix(5, metersEast: 7, speed: 1.2, speedAccuracy: 0.2))
        _ = detector.onFix(fix(10, metersEast: 14, speed: 1.2, speedAccuracy: 0.2))
        #expect(detector.state == .moving)

        var result = AdaptiveMovementUpdate(state: detector.state)
        for seconds in stride(from: Int64(15), through: 75, by: 5) {
            result = detector.onFix(fix(seconds, metersEast: 14.0 + Double(seconds % 3)))
        }
        #expect(result.state == .slowProbe)
        #expect(result.promotionBuffer.isEmpty)
    }
}
