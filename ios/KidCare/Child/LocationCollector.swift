import CoreLocation
import Foundation
import os

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

    /// 지역 전환 콜백을 받을 쪽. **약한 참조**다 — `PlaceWatcher` 는 코디네이터 쪽이 들고 있고,
    /// 여기서 세게 잡으면 파이프라인을 접어도 둘이 서로를 붙잡는다.
    weak var placeWatcher: PlaceWatcher?

    /// 지역 감시가 조용히 실패하면 "왜 도착 알림이 안 오지"를 알아낼 방법이 없다
    /// (`PlaceWatcher.kt:203-205` 와 같은 이유).
    private let regionLogger = Logger(subsystem: "com.kidcare.family", category: "LocationCollector")

    private let manager = CLLocationManager()
    private var gate = IntervalGate()
    private var mode: CollectionMode = .fastProbe
    /// 마지막으로 매니저에 건 "등록 장소 안인가". 모드가 그대로여도 이 값이 바뀌면 거리 필터가
    /// 달라지므로(M4) 다시 걸어야 한다.
    private var appliedInsideKnownPlace = false
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
        // 같은 모드면 다시 안 건다(LocationCollector.kt:168-172 와 같은 이유). 다만 `insideKnownPlace`
        // 는 모드가 같아도 거리 필터를 바꾸므로(M4) 함께 본다.
        guard next != mode || insideKnownPlace != appliedInsideKnownPlace else { return }
        mode = next
        appliedInsideKnownPlace = insideKnownPlace
        apply(next, insideKnownPlace: insideKnownPlace)
    }

    private func apply(_ mode: CollectionMode, insideKnownPlace: Bool = false) {
        let s = mode.settings(insideKnownPlace: insideKnownPlace)
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

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // `CLRegion` 은 Sendable 이 아니라 클로저 안으로 못 들고 간다(`manager` 와 같은 사정,
        // 1단계 보고서 4절 3항). 필요한 것은 식별자 한 글자뿐이므로 먼저 꺼낸다.
        let placeId = region.identifier
        MainActor.assumeIsolated { placeWatcher?.regionCrossed(placeId: placeId) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let placeId = region.identifier
        MainActor.assumeIsolated { placeWatcher?.regionCrossed(placeId: placeId) }
    }

    /// 지역 감시가 실패했다. 흔한 값이 권한 부족과 "위치가 꺼짐"이다 — 아이가 설정에서 언제든 끌 수
    /// 있으므로 예외가 아니라 흔한 상태다. 수집을 죽이지 않는다(`PlaceWatcher.kt:206-210`).
    /// 잃는 것은 앱이 죽어 있을 때의 반응뿐이고, 살아 있는 동안의 점마다 도는 판정은 그대로다.
    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let placeId = region?.identifier ?? "(없음)"
        let reason = String(describing: error)
        MainActor.assumeIsolated {
            regionLogger.warning("지역 감시 실패: \(placeId, privacy: .public) \(reason, privacy: .public)")
        }
    }
}

/// 지역 감시(설계서 §5.3-2·§7.3). `PlaceWatcher` 가 고른 스무 개를 그대로 건다.
extension LocationCollector: RegionMonitor {

    /// `CLLocationManager.startMonitoring(for:)` 을 쓴다. iOS 17 이 `CLMonitor` 로 대체했다고
    /// 표시했지만, **앱이 죽어 있을 때 되살리는 계약이 문서로 굳어 있고 오래 검증된 쪽**이 이것이다
    /// (설계서 §7.3·§17 열린 질문 2). 이 설계 전체가 그 계약에 기대고 있으므로 확실한 쪽을 고른다.
    /// deprecated 경고를 `@available` 로 덮지 않고 이 주석으로 남기는 이유이기도 하다 — 4단계
    /// 실기기에서 `CLMonitor` 가 똑같이 되살리는 것을 확인하면 그때 옮긴다.
    func replaceMonitoredRegions(_ places: [Place]) {
        // 먼저 전부 지운다. 부모가 **지운** 장소의 전환이 계속 올라오는 것을 막는다
        // (`PlaceWatcher.kt:142-152`, `:159-162` 의 "지우기는 조건 없이 먼저" 규율).
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        for place in places {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng),
                radius: place.radiusMeters,
                // 식별자가 곧 문서 ID 다 — 전환이 올 때 어느 장소인지 알아야 한다(`:185-187`).
                identifier: place.id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            // 안드로이드가 setInitialTrigger(0) 로 "등록하는 순간 이미 안에 있는 장소로 ENTER 를 쏘지
            // 않게" 한 것(`:181`)은 iOS 의 기본 동작이라 따로 할 일이 없다. 혹시 들어오더라도
            // GeofenceEvaluator 가 처음 보는 장소에는 조용히 상태만 심는다.
            manager.startMonitoring(for: region)
        }
    }

    /// 지역 전환 뒤 좌표 한 점. 결과는 `didUpdateLocations` 로 와서 보통 점과 같은 길을 지난다.
    func requestOneShotFix() {
        // 소프트웨어 간격 게이트가 이 한 점을 삼키면 OS 가 깨워 준 사건이 통째로 사라진다
        // (2단계 판정 기록 5). 게이트는 이 클래스가 갖고 있으므로 여기서 직접 연다 — 브리프는
        // 코디네이터에 두라고 했지만 1단계가 게이트를 수집기 안에 넣었다(`didUpdateLocations`).
        gate.bypassOnce()
        manager.requestLocation()
    }
}
