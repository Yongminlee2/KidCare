import CoreLocation
import Foundation

/// `TrackingCoordinator` 가 보는 좌표 공급원. 테스트는 가짜를 넣는다(설계서 §12.1).
@MainActor
protocol LocationSource: AnyObject {
    /// 점 하나가 소프트웨어 간격 게이트를 통과했을 때 부른다.
    var onFix: ((Fix) -> Void)? { get set }
    func start()
    func stop()
    /// 판정기 상태·등록 장소 여부가 바뀌면 부른다. 모드가 실제로 바뀔 때만 매니저를 다시 건다.
    func updateMode(state: AdaptiveMovementState, insideKnownPlace: Bool, slowProbeSince: Int64?, now: Int64)
}

/// `CLLocationManager` 를 감싸고, 수집 모드에 따라 정확도·거리 필터를 바꾼다.
/// 정본은 안드로이드 `child/LocationCollector.kt`.
///
/// `@MainActor` 인 이유: `CLLocationManagerDelegate` 콜백은 **매니저를 만든 스레드의 런루프**로
/// 오므로 메인에서 만들면 메인으로 온다 — 안드로이드가 `context.mainLooper` 를 넘기는 것
/// (`LocationCollector.kt:150`)과 같은 선택이고, 버퍼를 만지는 스레드가 하나로 유지돼 잠금이
/// 필요 없어지는 것도 같다(`TrailUploader.kt:91-93`).
@MainActor
final class LocationCollector: NSObject, LocationSource {

    var onFix: ((Fix) -> Void)?
    /// 권한이 바뀌면 부른다. 1단계는 기록만 남기고, 화면과 이벤트는 3단계가 잇는다(설계서 §8.1).
    var onAuthorizationChange: ((CLAuthorizationStatus, CLAccuracyAuthorization) -> Void)?

    private let manager = CLLocationManager()
    private var gate = IntervalGate()
    private var mode: CollectionMode = .fastProbe
    private var started = false

    /// 지금 걸려 있는 모드. 화면(`ChildSimView`)과 테스트가 읽는다.
    var currentMode: CollectionMode { mode }

    override init() {
        super.init()
        manager.delegate = self
        // **가장 중요한 한 줄이다**(설계서 §5.2). 기본값 true 면 iOS 가 "이 사람 안 움직이네" 하고
        // 업데이트를 멈추는데, 멈춘 뒤에는 **스스로 다시 시작하지 않는다.** 그 하루가 통째로
        // 조용해진다 — 이 앱에서 침묵이 제일 나쁜 고장이다.
        manager.pausesLocationUpdatesAutomatically = false
        // 안드로이드의 상시 알림(`TrackingService.buildNotification`, :840)과 같은 자리다.
        // 몰래 감시하지 않는다는 원칙을 아이폰에서 지키는 방법 — 아이는 파란 표시를 보고
        // 지금 위치가 공유 중임을 안다.
        manager.showsBackgroundLocationIndicator = true
        // `.fitness`/`.automotiveNavigation` 은 iOS 가 그 활동에 맞춰 스트림을 조절한다.
        // 아이가 걷는지 버스를 타는지는 우리가 모른다.
        manager.activityType = .other
        apply(mode)
    }

    func start() {
        guard !started else { return }
        started = true
        // `allowsBackgroundLocationUpdates` 는 '항상 허용' 이전에 켜면 예외로 죽는다.
        // 권한이 실제로 들어온 뒤(아래 델리게이트)에 켠다.
        applyBackgroundUpdates()
        manager.startUpdatingLocation()
        // 되살아나는 길(설계서 §5.3-1). 약 500m 이동마다 아주 적은 배터리로 앱을 **다시 띄운다**
        // — 재부팅 뒤에도 살고, 지오펜스 20개 자리를 안 쓴다. 지역 감시(§5.3-2)는 장소 목록이
        // 있어야 걸 수 있어 2단계다(1단계 판정 기록 16).
        //
        // **강제 종료 뒤에는 이 길도 앱을 되살리지 않는다**(설계서 §5.3·§15-2). 여기에
        // "죽어도 계속 기록한다"고 적지 않는다 — 부모에게 그것을 말하는 일은 3단계다.
        manager.startMonitoringSignificantLocationChanges()
    }

    func stop() {
        started = false
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        gate.reset()
    }

    func requestAuthorization() {
        // iOS 는 '항상'을 곧바로 못 묻는다. 반드시 두 걸음이다(설계서 §8.1). 1단계는 첫 걸음만
        // 부르고, 두 번째 걸음과 화면 안내는 3단계가 정한다.
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func updateMode(state: AdaptiveMovementState, insideKnownPlace: Bool, slowProbeSince: Int64?, now: Int64) {
        let next = CollectionMode.select(state: state, insideKnownPlace: insideKnownPlace, slowProbeSince: slowProbeSince, now: now)
        guard next != mode else { return }   // 같은 모드면 다시 안 건다(LocationCollector.kt:168-172 와 같은 이유)
        mode = next
        apply(next)
    }

    private func apply(_ mode: CollectionMode) {
        let s = mode.settings
        manager.desiredAccuracy = s.desiredAccuracy
        manager.distanceFilter = s.distanceFilterMeters ?? kCLDistanceFilterNone
    }

    private func applyBackgroundUpdates() {
        // '항상 허용'이 실제로 들어온 뒤에만 켠다 — 그 전에 켜면 예외로 죽는다.
        manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
    }

    /// CoreLocation 의 "못 믿음" 표기를 안드로이드 모양으로 옮긴다(1단계 판정 기록 19).
    ///
    /// 순수 함수라 `nonisolated` 다 — 델리게이트와 테스트가 같은 함수를 부른다.
    nonisolated static func fix(from location: CLLocation) -> Fix {
        Fix(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            // 음수는 "이 좌표를 믿지 마라"는 뜻이다. 무한대로 올리면 모든 정확도 게이트가
            // 거절한다 — 지어내지 않는다.
            accuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : .infinity,
            at: Int64((location.timestamp.timeIntervalSince1970 * 1000).rounded()),
            // 코틀린 `loc.speed` 는 모를 때 0 이다(`Fix.speed` 주석).
            speed: location.speed >= 0 ? location.speed : 0,
            // 코틀린 `loc.hasSpeedAccuracy()` 가 false 일 때와 같다(`LocationCollector.kt:138-142`).
            speedAccuracy: location.speedAccuracy >= 0 ? location.speedAccuracy : .infinity
        )
    }
}

extension LocationCollector: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 델리게이트는 매니저를 만든 런루프(메인)로 온다는 사실에 기댄다. 그 전제가 깨지면
        // 런타임에 즉시 죽는다 — 조용히 틀리는 것보다 낫다. `@unchecked Sendable` 은 쓰지 않는다.
        MainActor.assumeIsolated {
            // 묶음으로 올 수 있다. `last` 하나만 쓰면 그 사이의 모퉁이가 사라져 경로가 건물을
            // 가로지르는 직선이 된다(`LocationCollector.kt:127-130`). 시간순으로 전부 넘긴다.
            for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                let fix = Self.fix(from: location)
                guard gate.accept(at: fix.at, interval: mode.settings.intervalMillis) else { continue }
                onFix?(fix)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 넘어온 `manager` 를 클로저 안으로 들고 들어가지 않는다 — `CLLocationManager` 는
        // Sendable 이 아니라 Swift 6 가 그 자리에서 거절한다. 어차피 같은 객체이므로
        // `@MainActor` 안의 우리 것(`self.manager`)을 읽는다.
        MainActor.assumeIsolated {
            applyBackgroundUpdates()
            onAuthorizationChange?(self.manager.authorizationStatus, self.manager.accuracyAuthorization)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 삼키되 아무 일도 안 한다. 위치 실패는 흔하고(실내 진입 등) 다음 콜백이 곧 온다 —
        // 여기서 수집을 멈추면 신호가 잠깐 나쁜 날이 하루치 침묵이 된다.
    }
}
