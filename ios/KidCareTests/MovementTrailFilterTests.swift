import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `app/src/test/.../MovementTrailFilterTest.kt` 다 — `@Test` 를 하나도 빼지 않고 옮겼다.
/// 코틀린의 `fix(...)` 도우미를 그대로 쓴다(경도 1도 ≈ 88,800m).
struct MovementTrailFilterTests {

    /// 코틀린 `speedAccuracy: Float = Float.POSITIVE_INFINITY` 는 여기서 `.infinity` 다 — "모른다"는 뜻이고,
    /// 0 으로 두면 `speed - speedAccuracy` 가 곧 `speed` 라 실내 오보고가 전부 '확실한 보행'으로 통과한다.
    private func fix(
        _ at: Int64,
        metersEast: Double = 0,
        accuracy: Double = 5,
        speed: Double = 0,
        speedAccuracy: Double = .infinity
    ) -> Fix {
        Fix(
            lat: 37.5665,
            lng: 126.9780 + metersEast / 88_800.0,
            accuracy: accuracy,
            at: at,
            speed: speed,
            speedAccuracy: speedAccuracy
        )
    }

    @Test("정지 상태에서는 위치가 흔들려도 기록하지 않는다")
    func 정지_상태() {
        #expect(!MovementTrailFilter.shouldRecord(previous: nil, candidate: fix(5_000), reportedMoving: false))
    }

    @Test("이동 상태의 첫 정확한 점은 출발점으로 남긴다")
    func 첫_점() {
        #expect(MovementTrailFilter.shouldRecord(previous: nil, candidate: fix(5_000), reportedMoving: true))
    }

    @Test("오차가 큰 점은 이동 중에도 버린다")
    func 오차_상한() {
        #expect(!MovementTrailFilter.shouldRecord(
            previous: nil, candidate: fix(5_000, accuracy: 51), reportedMoving: true
        ))
    }

    @Test("버스 구간의 40m 오차 점도 경로에 남긴다")
    func 버스_구간() {
        // 상한이 30m 이던 시절 이 점은 정확도만으로 거절돼 경로 중간이 통째로 비었다. 상한은 이제 50m 다.
        #expect(MovementTrailFilter.shouldRecord(
            previous: fix(0, accuracy: 40),
            candidate: fix(5_000, metersEast: 80, accuracy: 40),
            reportedMoving: true
        ))
    }

    @Test("집 앞 놀이터 거리도 좌표가 좋으면 이동의 증거다")
    func 놀이터_변위() {
        // **짧은 외출을 지키는 자리다.** 오차 10m → 문턱 max(50, hypot(10,10)×1.5 ≈ 21) = 50m.
        #expect(MovementTrailFilter.isDisplacementEvidence(
            previous: fix(0, accuracy: 10),
            candidate: fix(60_000, metersEast: 60, accuracy: 10)
        ))
    }

    @Test("좌표가 거칠면 같은 거리라도 증거로 쓰지 않는다")
    func 거친_좌표_변위() {
        // hypot(40,40) ≈ 57m → 문턱 max(50, 85) = 85m.
        #expect(!MovementTrailFilter.isDisplacementEvidence(
            previous: fix(0, accuracy: 40),
            candidate: fix(60_000, metersEast: 60, accuracy: 40)
        ))
    }

    @Test("좌표가 거칠어도 충분히 멀면 증거가 된다")
    func 거친_좌표_먼_변위() {
        #expect(MovementTrailFilter.isDisplacementEvidence(
            previous: fix(0, accuracy: 40),
            candidate: fix(60_000, metersEast: 120, accuracy: 40)
        ))
    }

    @Test("50m 미만 변위는 좌표가 아무리 좋아도 증거가 아니다")
    func 고정_문턱() {
        #expect(!MovementTrailFilter.isDisplacementEvidence(
            previous: fix(0, accuracy: 5),
            candidate: fix(60_000, metersEast: 45, accuracy: 5)
        ))
    }

    @Test("이전 점이 없으면 변위 증거를 만들 수 없다")
    func 이전_점_없음() {
        #expect(!MovementTrailFilter.isDisplacementEvidence(
            previous: nil, candidate: fix(300_000, metersEast: 500)
        ))
    }

    @Test("오차 상한을 넘는 점은 변위 증거로 쓰지 않는다")
    func 변위_오차_상한() {
        #expect(!MovementTrailFilter.isDisplacementEvidence(
            previous: fix(0),
            candidate: fix(300_000, metersEast: 500, accuracy: 80)
        ))
    }

    @Test("순간이동 속도의 변위는 증거가 아니라 오류다")
    func 변위_순간이동() {
        #expect(!MovementTrailFilter.isDisplacementEvidence(
            previous: fix(0),
            candidate: fix(1_000, metersEast: 500)
        ))
    }

    @Test("5초가 되기 전 후보는 기록하지 않는다")
    func 간격_미달() {
        #expect(!MovementTrailFilter.shouldRecord(
            previous: fix(0),
            candidate: fix(4_999, metersEast: 20, speed: 1.2),
            reportedMoving: true
        ))
    }

    @Test("보행 속도가 확인되면 5초마다 기록한다")
    func 보행_속도() {
        #expect(MovementTrailFilter.shouldRecord(
            previous: fix(0),
            candidate: fix(5_000, metersEast: 4, speed: 1.2),
            reportedMoving: true
        ))
    }

    @Test("좌표가 그대로인데 속도만 튄 점은 이동 경로로 기록하지 않는다")
    func 속도만_튐() {
        #expect(!MovementTrailFilter.shouldRecord(
            previous: fix(0),
            candidate: fix(5_000, speed: 1.2),
            reportedMoving: true
        ))
    }

    @Test("속도 오차를 빼도 이동 중이고 실제 변위가 있으면 기록한다")
    func 속도_오차_보정() {
        #expect(MovementTrailFilter.shouldRecord(
            previous: fix(0),
            candidate: fix(5_000, metersEast: 6, speed: 1.3, speedAccuracy: 0.4),
            reportedMoving: true
        ))
    }

    @Test("걷는 5초 변위는 오차가 거칠어도 경로점으로 남긴다")
    func 걷는_변위() {
        // **이 테스트가 3m 문턱의 존재 이유다.** 예전에는 오차 20m 면 28m 를 요구해
        // 걸어서는 경로점이 하나도 안 남았다.
        #expect(MovementTrailFilter.shouldRecord(
            previous: fix(0, accuracy: 20),
            candidate: fix(5_000, metersEast: 6, accuracy: 20),
            reportedMoving: true
        ))
    }

    @Test("15m 정확도에서도 보행 속도가 확인되면 모퉁이를 남긴다")
    func 속도_신뢰_경계() {
        #expect(MovementTrailFilter.shouldRecord(
            previous: fix(0, accuracy: 15),
            candidate: fix(5_000, metersEast: 6, accuracy: 15, speed: 1.2),
            reportedMoving: true
        ))
    }

    @Test("같은 자리의 반복 좌표는 기록하지 않는다")
    func 반복_좌표() {
        #expect(!MovementTrailFilter.shouldRecord(
            previous: fix(0, accuracy: 10),
            candidate: fix(5_000, metersEast: 2, accuracy: 10),
            reportedMoving: true
        ))
    }

    @Test("속도가 없어도 실제로 이동하면 기록한다")
    func 속도_없이_이동() {
        #expect(MovementTrailFilter.shouldRecord(
            previous: fix(0, accuracy: 10),
            candidate: fix(5_000, metersEast: 16, accuracy: 10),
            reportedMoving: true
        ))
    }

    @Test("정지로 판정된 동안에는 무엇이 와도 기록하지 않는다")
    func 정지_판정_우선() {
        // 제자리 흔들림을 막는 책임은 이 필터가 아니라 상류의 이동 판정기에 있다.
        #expect(!MovementTrailFilter.shouldRecord(
            previous: fix(0, accuracy: 25),
            candidate: fix(5_000, metersEast: 20, accuracy: 25, speed: 4),
            reportedMoving: false
        ))
    }

    @Test("순간이동 좌표는 경로에 넣지 않는다")
    func 기록_순간이동() {
        #expect(!MovementTrailFilter.shouldRecord(
            previous: fix(0),
            candidate: fix(5_000, metersEast: 1_000, speed: 0),
            reportedMoving: true
        ))
    }

    @Test("기기가 비현실적인 속도를 보고하면 경로에 넣지 않는다")
    func 기록_속도_초과() {
        #expect(!MovementTrailFilter.shouldRecord(
            previous: fix(0),
            candidate: fix(5_000, metersEast: 10, speed: 60),
            reportedMoving: true
        ))
    }
}
