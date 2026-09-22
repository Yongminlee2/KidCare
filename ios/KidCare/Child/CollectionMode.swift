import CoreLocation
import Foundation

/// 지금 무슨 밀도로 위치를 받을 것인가. 정본은 안드로이드 `child/LocationCollector.kt:63-78` 의 `when` 둘이다.
///
/// **안드로이드의 "몇 밀리초마다 하나"가 아이폰에는 없다.** `CLLocationManager` 는 새 측정이 생길
/// 때마다 콜백을 준다(GNSS 가 붙어 있으면 대략 1초에 한 번). 손잡이는 `desiredAccuracy`(배터리를
/// 정한다)와 `distanceFilter`(이만큼 옮겨져야 준다) 둘뿐이라, **간격은 우리 코드가 만든다** —
/// 스트림을 계속 받되 [IntervalGate] 가 모드별 간격이 안 지난 점을 그 자리에서 버린다(설계서 §5.1).
///
/// 소프트웨어 게이트가 배터리를 아끼지는 않는다(버려진 콜백도 GNSS 는 이미 켜져 있었다).
/// 아이폰에서 배터리를 실제로 정하는 것은 `desiredAccuracy` 하나다 — `.best` ↔ `.nearestTenMeters`
/// 전환이 이 설계의 절약 장치 전부다(설계서 §9.2).
///
/// 실시간 보기(`LIVE_INTERVAL_MILLIS`, `LocationCollector.kt:207`)는 **안 옮긴다** — 1단계에는
/// 명령이 하나도 없다(계획서 "다루지 않는 것").
enum CollectionMode: String, Equatable, CaseIterable {
    case moving        // 판정기 MOVING
    case fastProbe     // 판정기 FAST_PROBE
    case slowProbe     // 판정기 SLOW_PROBE
    case knownPlace    // 등록 장소 반경 안 & 이동 아님 (2단계가 실제로 켠다)
    case still         // SLOW_PROBE 로 stillEscalateMillis 연속

    struct Settings: Equatable {
        let desiredAccuracy: CLLocationAccuracy
        /// nil = 거리 필터 없음(`kCLDistanceFilterNone`).
        let distanceFilterMeters: CLLocationDistance?
        let intervalMillis: Int64
    }

    /// 설계서 §5.1 의 표 그대로다. 간격 넷은 안드로이드 상수를 그대로 옮긴 값이다 —
    /// `MOVING_INTERVAL_MILLIS` 5초(`LocationCollector.kt:205`), `SLOW_PROBE_INTERVAL_MILLIS`
    /// 30초(`:210`), `KNOWN_PLACE_INTERVAL_MILLIS` 60초(`:213`), `STILL_INTERVAL_MILLIS`
    /// 60초(`:230`). 거리 필터 3m 는 `MOVING_MIN_UPDATE_DISTANCE_METERS`(`:233`) 다.
    ///
    /// **정지에 `.nearestTenMeters` 를 쓰는 근거**(설계서 §4.8): 안드로이드는 정지에도 일부러
    /// HIGH_ACCURACY 를 쓴다 — 하루의 대부분이 정지 구간이고 머무른 곳 이름이 그 점들로 정해진다
    /// (`LocationCollector.kt:81-96`). 거부한 대안은 `PRIORITY_BALANCED_POWER_ACCURACY`
    /// (WiFi·기지국, 오차 20~60m)였다. `.nearestTenMeters` 는 그 거부 대상이 아니라 GNSS 를 쓰되
    /// 듀티 사이클을 허용하는 등급이고, 오차 10m 는 50m 정확도 문턱과 40m 머무름 반경 안에 넉넉히 든다.
    /// **`.hundredMeters` 이하로는 절대 안 내린다** — 그게 안드로이드가 거부한 그 등급이다.
    ///
    /// **정지에 거리 필터를 안 거는 근거**: 걸면 완전히 멈춘 폰이 콜백을 하나도 못 받아 하트비트
    /// (10분)가 굶고 상태 문서의 `at` 이 멈춘다 — 안드로이드가 정확히 같은 이유로 이동 확정일
    /// 때만 걸었다(`LocationCollector.kt:109-121`, `known-issues.md` 11번).
    /// 등록 장소 안/밖과 **무관한** 값. 간격은 어느 모드에서도 이 축에 안 묶여서, 간격만 필요한
    /// 자리(`IntervalGate`)는 이것을 읽는다. 매니저에 실제로 거는 값은 아래 `settings(insideKnownPlace:)` 다.
    var settings: Settings { settings(insideKnownPlace: false) }

    /// 거리 필터 하나가 등록 장소 안/밖에 따라 갈린다(1단계 리뷰 M4).
    ///
    /// 안드로이드는 `activityMoving && !liveTracking && !insideKnownPlace && MOVING` 일 때만 3m 를
    /// 건다(`LocationCollector.kt:109-112`). **주기(5초)는 등록 장소 안에서도 그대로 쓰지만 거리
    /// 필터는 안 건다** — 집·학교 반경 안에서 이동이 확정된 동안 3m 미만 콜백까지 버리면 완전히
    /// 멈춘 폰의 콜백이 굶어(`:117-119`) 하트비트와 상태 검사가 기회를 잃는다. 1단계는 이 항이
    /// 빠진 채였고 `insideKnownPlace` 가 늘 false 라 드러나지 않았다 — 2단계가 `PlaceWatcher` 를
    /// 이으면서 그날부터 갈리므로 여기서 채운다.
    func settings(insideKnownPlace: Bool) -> Settings {
        switch self {
        case .moving:
            return Settings(desiredAccuracy: kCLLocationAccuracyBest,
                            distanceFilterMeters: insideKnownPlace ? nil : 3,
                            intervalMillis: 5_000)
        case .fastProbe:
            return Settings(desiredAccuracy: kCLLocationAccuracyBest, distanceFilterMeters: nil, intervalMillis: 5_000)
        case .slowProbe:
            return Settings(desiredAccuracy: kCLLocationAccuracyNearestTenMeters, distanceFilterMeters: nil, intervalMillis: 30_000)
        case .knownPlace, .still:
            return Settings(desiredAccuracy: kCLLocationAccuracyNearestTenMeters, distanceFilterMeters: nil, intervalMillis: 60_000)
        }
    }

    /// **아이폰에만 있는 상수다**(설계서 §4.8 끝, §15-3). 안드로이드의 정지 60초는 활동 인식이
    /// STILL 을 보고할 때 켜지는데(`LocationCollector.kt:65`) 아이폰은 v1 에서 CoreMotion 을 안 써
    /// 그 방아쇠가 없다. 그대로 두면 가만히 있는 폰이 영영 저주기(30초)에 머물러 안드로이드보다
    /// 배터리를 두 배로 쓴다.
    ///
    /// 5분인 이유: 안드로이드의 활동 인식이 STILL 을 보고하기까지 걸리는 시간(30초~2분,
    /// `LocationCollector.kt:220-221`)보다 넉넉히 길게 잡아 **진짜 정지에만** 켜지게 하려는 것이다.
    /// 짧게 잡으면 신호등 앞에서 기다리는 1분이 정지로 내려가 다시 올라오는 데 30초가 더 걸린다.
    ///
    /// 안드로이드에 대응이 없으므로 **골든 대조 대상이 아니다.** `CollectionModeTests` 가 고정한다.
    static let stillEscalateMillis: Int64 = 5 * 60_000

    /// 분기 **순서가 안드로이드와 같아야 한다**(`LocationCollector.kt:63-70`). 특히 등록 장소
    /// 분기가 이동 판정보다 **아래**다 — 위에 두면 집 반경 안의 놀이터에 다녀오는 동안 1분 주기에
    /// 묶여 그 경로가 통째로 빈다(그 주석 :58-62).
    ///
    /// - Parameter slowProbeSince: 판정기가 SLOW_PROBE 로 **연속해서** 머물기 시작한 시각.
    ///   FAST_PROBE·MOVING 으로 올라가는 순간 호출자가 `nil` 로 만든다(= 시계가 0 으로 돌아간다).
    static func select(
        state: AdaptiveMovementState,
        insideKnownPlace: Bool,
        slowProbeSince: Int64?,
        now: Int64
    ) -> CollectionMode {
        // 안드로이드의 `!activityMoving` 자리다. 시간이 그 비트를 대신한다.
        // 시계가 거꾸로 간 경우(now < since)는 음수 경과라 여기 안 걸린다 — 음수를 5분으로 읽지 않는다.
        if state == .slowProbe, let since = slowProbeSince, now - since >= stillEscalateMillis {
            return .still
        }
        if state == .moving { return .moving }
        if state == .fastProbe { return .fastProbe }
        if insideKnownPlace { return .knownPlace }
        return .slowProbe
    }
}

/// 모드별 소프트웨어 간격을 강제한다. **마지막으로 통과시킨 점**만 기준이 된다 — 버린 점이
/// 시계를 밀면 간격이 실제보다 길어져 밀도가 안드로이드보다 성글어진다.
struct IntervalGate {
    private var lastAcceptedAt: Int64?
    private var bypassNext = false

    /// 시간이 거꾸로 온 점은 **통과시킨다.** 여기서 막으면 시계 역행 뒤의 모든 점이 영영 막히는데,
    /// 그 상황을 푸는 것은 `TrackingCoordinator` 의 시계 역행 감지다(`TrackingService.kt:552-568`).
    mutating func accept(at: Int64, interval: Int64) -> Bool {
        if bypassNext {
            bypassNext = false
            lastAcceptedAt = at
            return true
        }
        guard let last = lastAcceptedAt else {
            lastAcceptedAt = at
            return true
        }
        if at >= last, at - last < interval { return false }
        lastAcceptedAt = at
        return true
    }

    /// 다음 한 점만 간격을 안 본다(2단계 판정 기록 5).
    ///
    /// 지역 전환으로 OS 가 앱을 깨웠을 때 부탁하는 좌표 한 점을 위한 문이다. 이 게이트는
    /// **아이폰에만 있는 장치**라(설계서 §5.1 — 안드로이드는 간격이 요청 매개변수다) 정지 60초
    /// 게이트가 그 한 점을 삼키면 OS 가 깨워 준 사건이 통째로 사라진다. 안드로이드에 대응이 없어
    /// 골든 대조 대상이 아니고 `CollectionModeTests` 가 고정한다.
    mutating func bypassOnce() { bypassNext = true }

    mutating func reset() {
        lastAcceptedAt = nil
        bypassNext = false
    }
}
