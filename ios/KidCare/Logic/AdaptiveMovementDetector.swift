import Foundation

/// 정본은 코틀린 `AdaptiveMovementState`(`AdaptiveMovementDetector.kt:6`). `rawValue` 가 코틀린
/// 이름인 이유는 `Decision` 과 같다 — 골든 파일이 그 이름을 싣는다(1단계 판정 기록 6).
enum AdaptiveMovementState: String, Equatable {
    case fastProbe = "FAST_PROBE"
    case slowProbe = "SLOW_PROBE"
    case moving = "MOVING"
}

/// `:8-12`.
struct AdaptiveMovementUpdate: Equatable {
    let state: AdaptiveMovementState
    /// 이동 확정 직전의 점들. 경로 시작 부분이 잘리지 않도록 확정 시 한 번만 돌려준다.
    let promotionBuffer: [Fix]

    init(state: AdaptiveMovementState, promotionBuffer: [Fix] = []) {
        self.state = state
        self.promotionBuffer = promotionBuffer
    }
}

/// 활동 인식 결과를 바로 이동으로 믿지 않고 실제 좌표·속도 증거로 확인한다.
/// 정본은 안드로이드 `logic/AdaptiveMovementDetector.kt`.
///
/// 빠른 확인은 최대 30초만 유지하고, 이동 증거가 없으면 느린 확인으로 내려간다.
/// 실제 이동 중에도 60초간 오차 반경 안에 머물면 다시 느린 확인으로 돌아간다.
///
/// **아이폰에서는 이 판정기가 안드로이드보다 더 중요하다.** 안드로이드는 활동 인식(Activity
/// Recognition) 전환을 한 비트 더 갖고 있지만 아이폰은 v1 에서 CoreMotion 을 안 쓴다
/// (설계서 §17 열린 질문 5). 안드로이드도 활동 인식 권한이 없으면 이 판정기 하나로 도는 것이
/// 이미 검증된 갈래다(`ConditionWatcher.kt:47-48`).
///
/// 코틀린 `ArrayDeque<Fix>` 는 Swift `[Fix]` 로 옮긴다 — `removeFirst()` 가 O(n) 이지만 표본이
/// 30~60초 창이라 길어야 십여 개다.
///
/// `Sendable` 이 아니다 — 상태를 가진 클래스이고 `@MainActor` 인 `TrackingCoordinator` 안에서만
/// 산다. 격리를 넘길 일이 없으므로 `@unchecked Sendable` 을 붙이지 않는다(Global Constraints).
final class AdaptiveMovementDetector {

    /// `:175`. 30m 로 조였더니 버스·번화가의 30~50m 오차 구간에서 점을 전부 버려 이동 확정에
    /// 영영 못 올라갔다 — 판정 문턱들이 오차에 비례해 커지므로 상한을 올려도 정지 흔들림이
    /// 이동으로 승격되지는 않는다. `MovementTrailFilter` 와 같은 값.
    static let maxAccuracyMeters: Double = 50
    /// `:176`.
    static let fastProbeMillis: Int64 = 30_000
    /// `:177`.
    static let stopConfirmMillis: Int64 = 60_000
    /// `:178`.
    static let minConfirmMillis: Int64 = 10_000
    /// `:179`.
    static let minConfirmPoints = 3
    /// `:180` (`15f`).
    static let speedTrustMaxAccuracyMeters: Double = 15
    /// `:181` 의 `0.35f` 확장값(1단계 판정 기록 2). **`0.35` 라고 적으면 안 된다.**
    static let minConfidentSpeedMps: Double = 0.3499999940395355
    /// `:182`.
    static let minSpeedDisplacementMeters: Double = 3.0
    /// `:193`. 30m 에서 15m 로 내렸다 — 30m 이던 시절에는 **걷는 아이가 절대 통과하지 못했다**
    /// (확인 창 30초 × 보행 1.0~1.3m/s = 30~39m 인데 오차 15m 면 문턱이 42m 가 됐다).
    static let minNetDisplacementMeters: Double = 15.0
    /// `:194`.
    static let slowProbeMinDisplacementMeters: Double = 15.0
    /// `:195`.
    static let stopRadiusMeters: Double = 15.0
    /// `:209`. 2.0 에서 1.0 으로 내렸다 — 두 점의 변위 잡음은 표준편차가 `hypot` 이므로 1.0 배가
    /// 곧 1-시그마다. 2-시그마는 보행 속도로 도달할 수 없는 거리가 된다.
    static let noiseMultiplier: Double = 1.0
    /// `:210`.
    static let minProgressRatio: Double = 0.6

    private var samples: [Fix] = []
    private var fastProbeStartedAt: Int64?
    /// `:24-25`. 바깥에서 읽기만 한다.
    private(set) var state: AdaptiveMovementState = .fastProbe

    /// `:27-31`.
    func reset(fast: Bool = true) {
        samples.removeAll()
        fastProbeStartedAt = nil
        state = fast ? .fastProbe : .slowProbe
    }

    /// `:33-56`.
    func onFix(_ candidate: Fix) -> AdaptiveMovementUpdate {
        guard hasValidCoordinatesAndTime(candidate) else { return AdaptiveMovementUpdate(state: state) }
        if state == .fastProbe, fastProbeStartedAt == nil { fastProbeStartedAt = candidate.at }
        if !isUsable(candidate) {
            if state == .fastProbe, let startedAt = fastProbeStartedAt,
               candidate.at - startedAt >= Self.fastProbeMillis {
                reset(fast: false)
            }
            return AdaptiveMovementUpdate(state: state)
        }
        if let last = samples.last, candidate.at <= last.at { return AdaptiveMovementUpdate(state: state) }

        switch state {
        case .fastProbe: return onFastProbe(candidate)
        case .slowProbe: return onSlowProbe(candidate)
        case .moving: return onMoving(candidate)
        }
    }

    /// `:58-75`.
    private func onFastProbe(_ candidate: Fix) -> AdaptiveMovementUpdate {
        samples.append(candidate)
        trimBefore(candidate.at - Self.fastProbeMillis)

        if hasConfirmedMovement() {
            state = .moving
            fastProbeStartedAt = nil
            return AdaptiveMovementUpdate(state: state, promotionBuffer: samples)
        }
        if let startedAt = fastProbeStartedAt, candidate.at - startedAt >= Self.fastProbeMillis {
            keepOnly(candidate)
            state = .slowProbe
            fastProbeStartedAt = nil
        }
        return AdaptiveMovementUpdate(state: state)
    }

    /// `:77-88`.
    private func onSlowProbe(_ candidate: Fix) -> AdaptiveMovementUpdate {
        let previous = samples.last
        keepOnly(candidate)
        if let previous, hasMovementHint(previous, candidate) {
            samples = [previous, candidate]
            state = .fastProbe
            fastProbeStartedAt = candidate.at
        }
        return AdaptiveMovementUpdate(state: state)
    }

    /// `:90-100`.
    private func onMoving(_ candidate: Fix) -> AdaptiveMovementUpdate {
        samples.append(candidate)
        trimBefore(candidate.at - Self.stopConfirmMillis)

        guard let first = samples.first else { return AdaptiveMovementUpdate(state: state) }
        if candidate.at - first.at >= Self.stopConfirmMillis, looksStationary() {
            keepOnly(candidate)
            state = .slowProbe
        }
        return AdaptiveMovementUpdate(state: state)
    }

    /// `:102-120`.
    private func hasConfirmedMovement() -> Bool {
        if samples.count < Self.minConfirmPoints { return false }
        let points = samples
        let first = points[0]
        let last = points[points.count - 1]
        if last.at - first.at < Self.minConfirmMillis { return false }

        let recentSpeedEvidence = points.suffix(2).allSatisfy(Self.hasReliableWalkingSpeed)
        let recentDistance = LocationFilter.distanceMeters(points[points.count - 2], last)
        if recentSpeedEvidence, recentDistance >= Self.minSpeedDisplacementMeters { return true }

        let threshold = max(
            Self.minNetDisplacementMeters,
            hypot(first.accuracy, last.accuracy) * Self.noiseMultiplier
        )
        let penultimateDistance = LocationFilter.distanceMeters(first, points[points.count - 2])
        let netDistance = LocationFilter.distanceMeters(first, last)
        return penultimateDistance >= threshold * Self.minProgressRatio && netDistance >= threshold
    }

    /// `:122-136`.
    private func hasMovementHint(_ previous: Fix, _ candidate: Fix) -> Bool {
        let distance = LocationFilter.distanceMeters(previous, candidate)
        let elapsedSeconds = Double(candidate.at - previous.at) / 1_000.0
        if elapsedSeconds <= 0 || distance / elapsedSeconds > LocationFilter.maxSpeedMps { return false }
        if Self.hasReliableWalkingSpeed(candidate), distance >= Self.minSpeedDisplacementMeters { return true }
        let noise = max(
            Self.slowProbeMinDisplacementMeters,
            hypot(previous.accuracy, candidate.accuracy) * Self.noiseMultiplier
        )
        return distance >= noise
    }

    /// `:138-145`.
    private func looksStationary() -> Bool {
        let points = samples
        if points.contains(where: Self.hasReliableWalkingSpeed) { return false }
        guard let first = points.first else { return false }
        let maxDistance = points.map { LocationFilter.distanceMeters(first, $0) }.max() ?? 0
        let maxAccuracy = points.map(\.accuracy).max() ?? 0
        return maxDistance <= max(Self.stopRadiusMeters, maxAccuracy * Self.noiseMultiplier)
    }

    /// `:147-150`.
    private static func hasReliableWalkingSpeed(_ fix: Fix) -> Bool {
        fix.accuracy <= speedTrustMaxAccuracyMeters
            && fix.speedAccuracy.isFinite
            && fix.speed - fix.speedAccuracy >= minConfidentSpeedMps
    }

    /// `:152-155`. 코틀린 `fix.accuracy in 0f..MAX_ACCURACY_METERS` 를 두 비교로 푼다.
    private func isUsable(_ fix: Fix) -> Bool {
        hasValidCoordinatesAndTime(fix)
            && fix.accuracy.isFinite && fix.accuracy >= 0 && fix.accuracy <= Self.maxAccuracyMeters
            && fix.speed <= LocationFilter.maxSpeedMps
    }

    /// `:157-159`.
    private func hasValidCoordinatesAndTime(_ fix: Fix) -> Bool {
        fix.at >= 0 && fix.lat.isFinite && fix.lng.isFinite
            && fix.lat >= -90 && fix.lat <= 90 && fix.lng >= -180 && fix.lng <= 180
    }

    /// `:161-163`. `samples.count > 1` 은 "마지막 한 점은 아무리 오래돼도 남긴다"는 뜻이다 —
    /// 다 비우면 창보다 긴 공백 뒤의 점 하나가 기준점을 잃어 이동을 영영 못 알아본다.
    ///
    /// **다만 지금 호출부에서는 이 조건이 실제로 발동하지 않는다.** `onFastProbe`·`onMoving` 이
    /// 후보를 `append` 한 **직후에만** 부르므로 마지막 표본은 언제나 후보 자신이고, 후보의 `at` 이
    /// `후보.at - 창` 보다 작을 수는 없기 때문이다. 골든을 일부러 `> 0` 으로 망가뜨려도 빨개지지
    /// 않는 것을 확인했다. 그래도 코틀린과 같은 모양으로 남긴다 — 나중에 `append` 없이 트림하는
    /// 호출부가 생기면 그때 이 조건이 유일한 방어가 된다.
    private func trimBefore(_ oldestAt: Int64) {
        while samples.count > 1, samples[0].at < oldestAt { samples.removeFirst() }
    }

    /// `:165-168`.
    private func keepOnly(_ fix: Fix) {
        samples = [fix]
    }
}
