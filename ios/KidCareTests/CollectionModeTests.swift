import CoreLocation
import Foundation
import Testing
@testable import KidCare

/// 수집 모드 표(설계서 §5.1)와 분기 순서, 그리고 아이폰에만 있는 `STILL_ESCALATE_MILLIS` 를 고정한다.
///
/// **골든 대조가 이 둘을 못 잡는다.** 안드로이드에는 대응하는 순수 함수가 없다 —
/// `LocationCollector.kt:63-70` 은 `requestUpdates()` 안의 `when` 이고, 정지 모드의 방아쇠는
/// 활동 인식 전환이라 아이폰에 그 입력 자체가 없다(설계서 §4.8 끝). 그래서 여기서 못박는다.
struct CollectionModeTests {

    private let t0: Int64 = 1_700_000_000_000

    // MARK: 표 — 설계서 §5.1

    @Test("이동 확정은 .best · 거리 필터 3m · 5초")
    func 이동_확정_설정() {
        let s = CollectionMode.moving.settings
        #expect(s.desiredAccuracy == kCLLocationAccuracyBest)
        #expect(s.distanceFilterMeters == 3)
        #expect(s.intervalMillis == 5_000)
    }

    @Test("이동 확인은 .best · 거리 필터 없음 · 5초")
    func 이동_확인_설정() {
        let s = CollectionMode.fastProbe.settings
        #expect(s.desiredAccuracy == kCLLocationAccuracyBest)
        #expect(s.distanceFilterMeters == nil)
        #expect(s.intervalMillis == 5_000)
    }

    @Test("저주기 확인은 .nearestTenMeters · 거리 필터 없음 · 30초")
    func 저주기_설정() {
        let s = CollectionMode.slowProbe.settings
        #expect(s.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)
        #expect(s.distanceFilterMeters == nil)
        #expect(s.intervalMillis == 30_000)
    }

    @Test("등록 장소 머무름과 정지는 .nearestTenMeters · 거리 필터 없음 · 60초")
    func 정지_설정() {
        for mode in [CollectionMode.knownPlace, .still] {
            let s = mode.settings
            #expect(s.desiredAccuracy == kCLLocationAccuracyNearestTenMeters, "\(mode)")
            #expect(s.distanceFilterMeters == nil, "\(mode)")
            #expect(s.intervalMillis == 60_000, "\(mode)")
        }
    }

    @Test("정지에도 .hundredMeters 이하로는 절대 안 내려간다 — 그게 안드로이드가 거부한 등급이다(설계서 §4.8)")
    func 정확도_바닥() {
        for mode in [CollectionMode.slowProbe, .knownPlace, .still] {
            #expect(mode.settings.desiredAccuracy <= kCLLocationAccuracyNearestTenMeters, "\(mode)")
        }
    }

    @Test("정지 갈래에는 거리 필터를 절대 안 건다 — 완전히 멈춘 폰이 하트비트까지 굶는다(known-issues 11번)")
    func 정지에는_거리필터_없음() {
        for mode in [CollectionMode.fastProbe, .slowProbe, .knownPlace, .still] {
            #expect(mode.settings.distanceFilterMeters == nil, "\(mode)")
        }
        #expect(CollectionMode.moving.settings.distanceFilterMeters == 3)
    }

    @Test("등록 장소 안에서는 이동 확정이어도 3m 거리 필터를 안 건다(LocationCollector.kt:109-112, 1단계 리뷰 M4)")
    func 등록장소_안에서는_거리필터_없음() {
        #expect(CollectionMode.moving.settings(insideKnownPlace: true).distanceFilterMeters == nil,
                "집·학교 안에서 3m 미만 콜백을 버리면 완전히 멈춘 폰의 하트비트가 굶는다")
        #expect(CollectionMode.moving.settings(insideKnownPlace: false).distanceFilterMeters == 3)
        // 주기는 이 축에 안 묶인다 — 안드로이드도 MOVING 이면 등록 장소 안에서도 5초다(`:63-70`).
        #expect(CollectionMode.moving.settings(insideKnownPlace: true).intervalMillis == 5_000)
        #expect(CollectionMode.moving.settings(insideKnownPlace: true).desiredAccuracy
                == CollectionMode.moving.settings.desiredAccuracy)
        // 나머지 넷은 원래 거리 필터가 없어 이 축과 무관하다.
        for mode in [CollectionMode.fastProbe, .slowProbe, .knownPlace, .still] {
            #expect(mode.settings(insideKnownPlace: true) == mode.settings, "\(mode)")
        }
    }

    // MARK: 분기 순서 — LocationCollector.kt:63-70

    @Test("등록 장소 분기는 이동 판정보다 **아래**다 — 위에 두면 집 반경 안의 놀이터 경로가 통째로 빈다")
    func 등록장소는_이동보다_아래() {
        #expect(CollectionMode.select(state: .moving, insideKnownPlace: true, slowProbeSince: nil, now: t0) == .moving)
        #expect(CollectionMode.select(state: .fastProbe, insideKnownPlace: true, slowProbeSince: nil, now: t0) == .fastProbe)
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: true, slowProbeSince: t0, now: t0) == .knownPlace)
    }

    @Test("등록 장소 밖의 저주기는 slowProbe 다")
    func 저주기_기본() {
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0, now: t0) == .slowProbe)
    }

    // MARK: STILL_ESCALATE_MILLIS — 아이폰에만 있는 상수(설계서 §4.8)

    @Test("SLOW_PROBE 로 5분을 채우면 정지로 내려간다")
    func 정지_승격() {
        let five: Int64 = 5 * 60_000
        #expect(CollectionMode.stillEscalateMillis == five)
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0, now: t0 + five - 1) == .slowProbe)
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0, now: t0 + five) == .still)
    }

    @Test("정지 승격은 등록 장소 분기보다 **위**다 — 둘 다 60초라 결과는 같지만 순서는 안드로이드와 같아야 한다")
    func 정지가_등록장소보다_위() {
        let five: Int64 = 5 * 60_000
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: true, slowProbeSince: t0, now: t0 + five) == .still)
    }

    @Test("FAST_PROBE 로 올라가면 시계가 0 으로 돌아간다 — 호출자가 slowProbeSince 를 nil 로 준다")
    func 시계_초기화() {
        #expect(CollectionMode.select(state: .fastProbe, insideKnownPlace: false, slowProbeSince: nil, now: t0 + 999_999) == .fastProbe)
        // 다시 내려온 직후에는 시계가 지금부터다.
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0 + 999_999, now: t0 + 999_999) == .slowProbe)
    }

    @Test("시계가 없으면(막 내려왔거나 모름) 정지로 내려가지 않는다")
    func 시계_없음() {
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: nil, now: t0 + 10 * 60_000) == .slowProbe)
    }

    @Test("시계가 거꾸로 가도 정지로 안 내려간다 — 음수 경과를 5분으로 읽지 않는다")
    func 시계_역행() {
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0 + 60_000, now: t0) == .slowProbe)
    }

    // MARK: 소프트웨어 간격 게이트

    @Test("간격 게이트는 마지막으로 **처리한** 점을 기준으로 한다 — 버린 점은 시계를 안 민다")
    func 간격_게이트() {
        var gate = IntervalGate()
        #expect(gate.accept(at: t0, interval: 5_000) == true)          // 첫 점은 항상 통과
        #expect(gate.accept(at: t0 + 4_999, interval: 5_000) == false)
        #expect(gate.accept(at: t0 + 5_000, interval: 5_000) == true)
        // 버린 점(t0+4_999)이 기준이 됐다면 다음 통과가 t0+9_999 가 됐을 것이다.
        #expect(gate.accept(at: t0 + 10_000, interval: 5_000) == true)
    }

    @Test("시간이 거꾸로 온 점은 통과시킨다 — 판정 쪽이 시계 역행을 처리한다(TrackingService.kt:552-568)")
    func 간격_게이트_역행() {
        var gate = IntervalGate()
        _ = gate.accept(at: t0 + 60_000, interval: 5_000)
        #expect(gate.accept(at: t0, interval: 5_000) == true)
    }

    @Test("reset 뒤의 첫 점은 다시 무조건 통과한다 — 수집을 멈췄다 켜면 기준이 사라진다")
    func 게이트_초기화() {
        var gate = IntervalGate()
        _ = gate.accept(at: t0, interval: 60_000)
        #expect(gate.accept(at: t0 + 1, interval: 60_000) == false)
        gate.reset()
        #expect(gate.accept(at: t0 + 1, interval: 60_000) == true)
    }

    @Test("지역 전환으로 부탁한 점은 간격을 **한 번만** 건너뛴다(2단계 판정 기록 5)")
    func 게이트_한번_건너뛰기() {
        var gate = IntervalGate()
        _ = gate.accept(at: t0, interval: 60_000)
        #expect(gate.accept(at: t0 + 1, interval: 60_000) == false)
        gate.bypassOnce()
        #expect(gate.accept(at: t0 + 2, interval: 60_000) == true,
                "이 한 점을 삼키면 OS 가 깨워 준 지역 전환이 통째로 사라진다")
        #expect(gate.accept(at: t0 + 3, interval: 60_000) == false, "문은 한 번만 열린다")
        // 건너뛴 점이 기준이 된다 — 그래야 그 뒤 60초가 그 점부터 흐른다.
        #expect(gate.accept(at: t0 + 60_002, interval: 60_000) == true)
    }

    @Test("reset 은 열어 둔 문도 닫는다 — 수집을 멈췄다 켰는데 옛 부탁이 남아 있으면 안 된다")
    func 게이트_초기화가_문도_닫는다() {
        var gate = IntervalGate()
        _ = gate.accept(at: t0, interval: 60_000)
        gate.bypassOnce()
        gate.reset()
        _ = gate.accept(at: t0 + 1, interval: 60_000)   // reset 뒤 첫 점(항상 통과)
        #expect(gate.accept(at: t0 + 2, interval: 60_000) == false, "문이 남아 있으면 여기서 통과한다")
    }

    // MARK: CoreLocation → Fix (1단계 판정 기록 19)

    @Test("음수 정확도는 무한대다 — 모든 정확도 게이트가 거절한다. 지어내지 않는다")
    func 무효_정확도() {
        let fix = LocationCollector.fix(from: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            altitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1,
            course: -1, speed: -1, timestamp: Date(timeIntervalSince1970: 1.5)
        ))
        #expect(fix.accuracy == .infinity)
        // 코틀린 `loc.speed` 는 모를 때 0 이다(`Fix.speed` 주석).
        #expect(fix.speed == 0)
        // 코틀린 `loc.hasSpeedAccuracy()` 가 false 일 때와 같다(LocationCollector.kt:138-142).
        #expect(fix.speedAccuracy == .infinity)
        #expect(fix.at == 1_500)
    }

    @Test("유효한 값은 그대로 넘어간다")
    func 유효_값() {
        let fix = LocationCollector.fix(from: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            altitude: 0, horizontalAccuracy: 12.5, verticalAccuracy: 3,
            course: 0, courseAccuracy: 0, speed: 1.25, speedAccuracy: 0.5,
            timestamp: Date(timeIntervalSince1970: 2)
        ))
        #expect(fix.accuracy == 12.5)
        #expect(fix.speed == 1.25)
        #expect(fix.speedAccuracy == 0.5)
        #expect(fix.at == 2_000)
        #expect(fix.lat == 37.5665)
        #expect(fix.lng == 126.9780)
    }
}
