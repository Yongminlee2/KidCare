import Testing
@testable import KidCare
import Foundation

/// 정본은 안드로이드 `logic/RoutePathRefinerTest.kt` 다. 케이스 하나하나를 같은 뜻으로 옮긴다.
///
/// 부동소수 비교는 좌표(위도·경도, 도 단위)를 다루므로 `1e-9` 를 허용 오차로 쓴다.
/// 지구 둘레 기준으로 위도·경도 1e-9 도는 약 0.0001m(0.1mm) 이하로, GPS 정확도(미터
/// 단위)와 비교하면 무의미한 잡음이고, 코틀린 테스트가 기대하는 "원본 좌표를 그대로
/// 유지" 같은 단언을 흐리지 않을 만큼 충분히 촘촘하다.
struct RoutePathRefinerTests {

    private let coordinateTolerance = 1e-9

    // 코틀린 테스트의 기본 speed(1.2)를 그대로 옮긴다. `Fix.init` 의 `speed` 기본
    // 인자로 실제로 설정 가능하다(예전에는 `let speed: Double = 0` 선언부 기본값
    // 때문에 스위프트가 memberwise 초기화 목록에서 이 필드를 통째로 빼버려 항상
    // 0으로 고정돼 있었다 — `Fix.swift` 의 "반드시 설정 가능해야 하는 이유" 주석
    // 참고). 대부분의 케이스에서 1.2 는 `BASE_PROCESS_SPEED_MPS`(4.0) 보다 작아
    // `max(4.0, speed)` 에 묻히므로 관측 가능한 차이가 없다 — 그래서 대다수 케이스는
    // 코틀린과 동일한 결과를 낸다. speed 차이가 실제로 드러나는 경우는 아래
    // `평활 필터는 속도가 빠를수록 원시 좌표를 더 강하게 따라간다` 케이스에서 따로
    // BASE_PROCESS_SPEED_MPS 를 넘는 speed 를 명시적으로 준다.
    private func fix(at: Int64, east: Double, accuracy: Double = 10, speed: Double = 1.2) -> Fix {
        Fix(
            lat: 37.5665,
            lng: 126.9780 + east / 88_800.0,
            accuracy: accuracy,
            at: at,
            speed: speed
        )
    }

    @Test("오차가 큰 중간 점은 실제 선에 사용하지 않는다")
    func 오차가_큰_중간_점은_실제_선에_사용하지_않는다() {
        let legs = RoutePathRefiner.refine(
            points: [fix(at: 1_000, east: 0.0), fix(at: 6_000, east: 20.0, accuracy: 70), fix(at: 11_000, east: 12.0)]
        )
        #expect(legs.count == 1)
        #expect(legs.first?.points.count == 2)
    }

    @Test("긴 GPS 공백 뒤 멀리 떨어진 위치는 직선으로 잇지 않는다")
    func 긴_GPS_공백_뒤_멀리_떨어진_위치는_직선으로_잇지_않는다() {
        let legs = RoutePathRefiner.refine(
            points: [fix(at: 1_000, east: 0.0), fix(at: 6_000, east: 8.0), fix(at: 700_000, east: 500.0)]
        )
        #expect(legs.count == 2)
    }

    @Test("부정확한 지그재그는 완화하고 정확한 출발점은 지킨다")
    func 부정확한_지그재그는_완화하고_정확한_출발점은_지킨다() {
        let raw = [
            fix(at: 1_000, east: 0.0, accuracy: 8),
            fix(at: 6_000, east: 20.0, accuracy: 25),
            fix(at: 11_000, east: 4.0, accuracy: 25),
            fix(at: 16_000, east: 24.0, accuracy: 25),
        ]
        let refined = RoutePathRefiner.refine(points: raw).first?.points ?? []
        #expect(abs(refined[0].lat - raw[0].lat) < coordinateTolerance)
        #expect(abs(refined[0].lng - raw[0].lng) < coordinateTolerance)
        let rawSwing = abs(raw[2].lng - raw[1].lng)
        let refinedSwing = abs(refined[2].lng - refined[1].lng)
        #expect(refinedSwing < rawSwing)
    }

    @Test("정확한 마지막 점은 현재 위치와 맞게 그대로 둔다")
    func 정확한_마지막_점은_현재_위치와_맞게_그대로_둔다() {
        let raw = [fix(at: 1_000, east: 0.0), fix(at: 6_000, east: 7.0), fix(at: 11_000, east: 14.0, accuracy: 8)]
        let refined = RoutePathRefiner.refine(points: raw).first?.points ?? []
        #expect(abs(refined.last!.lat - raw.last!.lat) < coordinateTolerance)
        #expect(abs(refined.last!.lng - raw.last!.lng) < coordinateTolerance)
    }

    @Test("한 점만 멀리 튀었다 바로 돌아온 GPS 스파이크는 제거한다")
    func 한_점만_멀리_튀었다_바로_돌아온_GPS_스파이크는_제거한다() {
        let refined = RoutePathRefiner.refine(
            points: [fix(at: 1_000, east: 0.0), fix(at: 6_000, east: 70.0), fix(at: 11_000, east: 4.0)]
        ).first?.points ?? []

        #expect(refined.count == 2)
        #expect(abs(refined.first!.lng - fix(at: 1_000, east: 0.0).lng) < coordinateTolerance)
        #expect(abs(refined.last!.lng - fix(at: 11_000, east: 4.0).lng) < coordinateTolerance)
    }

    @Test("계속 같은 방향으로 이동한 정상 경로는 스파이크로 제거하지 않는다")
    func 계속_같은_방향으로_이동한_정상_경로는_스파이크로_제거하지_않는다() {
        let refined = RoutePathRefiner.refine(
            points: [fix(at: 1_000, east: 0.0), fix(at: 6_000, east: 35.0), fix(at: 11_000, east: 70.0)]
        ).first?.points ?? []

        #expect(refined.count == 3)
    }

    // 코틀린 원본에는 없는, 이 포팅 과정에서 실제로 터진 결함을 고정하는 회귀
    // 테스트다: `Fix.speed` 가 한동안 memberwise 초기화 목록에서 빠져 있어 항상
    // 0으로 고정됐었다(자세한 경위는 `Fix.swift`, git 커밋 로그 참고). 위 6개
    // 케이스는 전부 speed 기본값(1.2)이 `BASE_PROCESS_SPEED_MPS`(4.0) 문턱 아래라
    // 그 결함이 있어도 통과했다 — 즉 "포팅한 테스트가 전부 통과한다"는 이 결함을
    // 못 잡는다. 여기서는 문턱을 넘는 speed 를 줘서 `RoutePathRefiner.kt:137` 의
    // `processSpeed = max(BASE_PROCESS_SPEED_MPS, fix.speed)` 가 실제로 평활 결과에
    // 반영되는지를 직접 확인한다.
    @Test("평활 필터는 속도가 빠를수록 원시 좌표를 더 강하게 따라간다")
    func 평활_필터는_속도가_빠를수록_원시_좌표를_더_강하게_따라간다() {
        // 좌표·시각·정확도는 두 시퀀스가 완전히 같고 p1 의 speed 만 다르다 — 다른
        // 경로가 아니라 같은 경로를 다른 속도로 지나갈 때의 차이만 보려는 것이다.
        func points(speedAtSecondPoint: Double) -> [Fix] {
            [
                fix(at: 1_000, east: 0.0, accuracy: 20, speed: 0),
                fix(at: 6_000, east: 20.0, accuracy: 20, speed: speedAtSecondPoint),
                fix(at: 11_000, east: 5.0, accuracy: 20, speed: 0),
                fix(at: 16_000, east: 25.0, accuracy: 20, speed: 0),
            ]
        }

        let slow = RoutePathRefiner.refine(points: points(speedAtSecondPoint: 0)).first?.points ?? []
        let fast = RoutePathRefiner.refine(points: points(speedAtSecondPoint: 30)).first?.points ?? []

        #expect(slow.count == 4)
        #expect(fast.count == 4)
        // p1 은 첫 점(그대로 유지)도, 정확한 마지막 점(그대로 유지되는 경우)도
        // 아니라서 두 시퀀스의 speed 차이가 그대로 평활 결과 차이로 드러나야 한다.
        // speed 가 무시된다면(과거의 결함처럼) 이 값은 완전히 같아진다.
        #expect(abs(slow[1].lng - fast[1].lng) > coordinateTolerance)
    }
}
