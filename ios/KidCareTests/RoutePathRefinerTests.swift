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

    // `Fix.speed` 는 이 타입의 표준 초기화 구문(memberwise init)에서 늘 0 으로
    // 고정된다 — 상수 기본값이 있는 `let` 저장 프로퍼티는 스위프트가 초기화 목록에
    // 아예 넣어주지 않는다(직접 확인: `Fix(lat:lng:accuracy:at:speed:)` 는 컴파일
    // 에러다). 코틀린 테스트도 매 케이스 speed 기본값이 1.2 인데, 평활기의
    // processSpeed 는 `max(BASE_PROCESS_SPEED_MPS=4.0, speed)` 라서 1.2 는 4.0 에
    // 묻혀 어차피 결과에 영향을 주지 못한다 — 즉 0 과 1.2 는 이 테스트들에서 관측
    // 가능한 차이가 없다. 그래서 speed 파라미터 없이 옮겨도 코틀린과 같은 결과가
    // 나온다.
    private func fix(at: Int64, east: Double, accuracy: Double = 10) -> Fix {
        Fix(
            lat: 37.5665,
            lng: 126.9780 + east / 88_800.0,
            accuracy: accuracy,
            at: at
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
}
