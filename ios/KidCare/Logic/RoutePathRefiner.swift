import Foundation

/// 정본은 안드로이드 `logic/RoutePathRefiner.kt` 다. 지도에 경로를 그리기 전에 GPS
/// 흔들림과 위치 공백을 정리한다.
///
/// 거리 계산(`LocationFilter.distanceMeters`)과 순간이동 문턱(`MAX_SPEED_MPS`)은
/// 안드로이드에서 `LocationFilter` 가 갖고 있지만, 그 타입 자체는 아이 폰(안드로이드)
/// 전용이라 옮기지 않는다(`Fix.swift`, `Segment.swift` 와 같은 이유) — 대신 이
/// 파일이 실제로 쓰는 두 값(하버사인 공식·55.6m/s)만 그대로 복사해 이 파일 안에
/// 둔다. 문턱 숫자 하나만 어긋나도 지도 위의 선이 달라지므로, 아래 상수는 전부
/// 코틀린 원본의 리터럴을 그대로 옮긴 값이다.
struct Leg {
    let points: [Fix]
}

enum RoutePathRefiner {

    /// 이보다 거친 경로점은 선에 사용하지 않는다. 옛 기록과의 호환 상한이다.
    static let maxDisplayAccuracyMeters: Double = 50

    /// 이 시간 동안 위치가 없고 멀리 이동했다면 두 점을 추측으로 직선 연결하지 않는다.
    static let gapBreakMillis: Int64 = 10 * 60_000
    static let gapBreakDistanceMeters: Double = 150

    private static let unknownAccuracyMeters: Double = 30.0
    private static let minAccuracyMeters: Double = 5.0
    private static let baseProcessSpeedMps: Double = 4.0
    private static let preciseEndpointMeters: Double = 12
    private static let spikeMaxSpanMillis: Int64 = 20_000
    private static let spikeMinArmMeters: Double = 25.0
    private static let spikeMaxBridgeMeters: Double = 15.0
    private static let spikeMinDetourRatio: Double = 4.0

    /// 시속 200km. 이보다 빠르면 GPS 오류로 본다. 코틀린 `LocationFilter.MAX_SPEED_MPS` 그대로.
    private static let maxSpeedMps: Double = 55.6

    /// 하버사인 공식에 쓰는 지구 반지름(m). 코틀린 `LocationFilter.EARTH_RADIUS_METERS` 그대로 —
    /// 다른 반지름이나 다른 공식을 쓰면 모든 거리 문턱 비교가 같이 어긋난다.
    private static let earthRadiusMeters: Double = 6_371_000.0

    /// 하버사인 거리(m). 코틀린 `LocationFilter.distanceMeters` 를 그대로 옮긴 것이다.
    private static func distanceMeters(_ a: Fix, _ b: Fix) -> Double {
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let h = pow(sin(dLat / 2), 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * pow(sin(dLng / 2), 2)
        return 2 * earthRadiusMeters * asin(sqrt(h))
    }

    /// 정확도가 좋은 점은 거의 그대로 두고, 오차가 큰 점일수록 앞선 위치와 더 강하게
    /// 합친다. 이동 속도가 빠를 때는 필터가 즉시 따라가도록 과정 잡음을 높여 자동차나
    /// 급회전 경로가 둥글게 잘려 나가지 않게 한다.
    static func refine(points: [Fix]) -> [Leg] {
        // `sorted(by:)` 는 안정 정렬을 보장하지 않는다(코틀린 `sortedBy` 는 보장한다).
        // 같은 시각(at)의 콜백이 실제로 들어온다(:70 참고) — 원래 순서를 인덱스로
        // 함께 정렬해 동률일 때도 입력 순서가 그대로 유지되도록 계약으로 못박는다.
        let sorted = points
            .filter(isUsable)
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.at != rhs.element.at
                    ? lhs.element.at < rhs.element.at
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        if sorted.isEmpty { return [] }
        let cleaned = removeIsolatedSpikes(sorted)

        var rawLegs: [[Fix]] = []
        var current: [Fix] = []
        var previous: Fix?

        for candidate in cleaned {
            let before = previous
            if let before, shouldBreak(before, candidate) {
                if !current.isEmpty { rawLegs.append(current) }
                current = []
            }
            // 같은 시각의 중복 콜백은 선을 두껍게 만들 뿐 정보가 없다.
            if before == nil || candidate.at > before!.at { current.append(candidate) }
            previous = candidate
        }
        if !current.isEmpty { rawLegs.append(current) }

        return rawLegs.map { raw in Leg(points: smooth(raw)) }
    }

    /// A→B→C 중 B만 멀리 튀었다가 20초 안에 A 근처로 돌아오는 전형적인 GPS 반사
    /// 오차를 제거한다. 정상적인 직선·코너는 A-C 거리도 함께 커지므로 이 조건에
    /// 걸리지 않는다. 보행과 자전거의 짧은 실제 왕복을 지우지 않도록 네 조건을 모두
    /// 만족하는 아주 뚜렷한 단일 스파이크만 대상으로 한다.
    private static func removeIsolatedSpikes(_ points: [Fix]) -> [Fix] {
        if points.count < 3 { return points }
        var result: [Fix] = []
        result.reserveCapacity(points.count)
        result.append(points.first!)
        for index in 1..<(points.count - 1) {
            let previous = result.last!
            let candidate = points[index]
            let next = points[index + 1]
            if !isIsolatedSpike(previous, candidate, next) { result.append(candidate) }
        }
        result.append(points.last!)
        return result
    }

    private static func isIsolatedSpike(_ previous: Fix, _ candidate: Fix, _ next: Fix) -> Bool {
        let span = next.at - previous.at
        if span <= 0 || span > spikeMaxSpanMillis { return false }
        let firstArm = distanceMeters(previous, candidate)
        let secondArm = distanceMeters(candidate, next)
        if firstArm < spikeMinArmMeters || secondArm < spikeMinArmMeters { return false }
        let bridge = distanceMeters(previous, next)
        if bridge > spikeMaxBridgeMeters { return false }
        let detourRatio = (firstArm + secondArm) / max(bridge, 1.0)
        return detourRatio >= spikeMinDetourRatio
    }

    private static func isUsable(_ fix: Fix) -> Bool {
        if !fix.lat.isFinite || !fix.lng.isFinite || !fix.accuracy.isFinite { return false }
        if !(-90.0...90.0).contains(fix.lat) || !(-180.0...180.0).contains(fix.lng) || fix.at <= 0 { return false }
        // accuracy=0 은 정확도 필드가 없던 옛 기록이다. 버리지 않고 '모름'으로 다룬다.
        return fix.accuracy <= 0 || fix.accuracy <= maxDisplayAccuracyMeters
    }

    private static func shouldBreak(_ previous: Fix, _ candidate: Fix) -> Bool {
        let elapsed = candidate.at - previous.at
        if elapsed <= 0 { return false }
        let distance = distanceMeters(previous, candidate)
        let impliedSpeed = distance / (Double(elapsed) / 1_000.0)
        if impliedSpeed > maxSpeedMps { return true }
        return elapsed > gapBreakMillis && distance > gapBreakDistanceMeters
    }

    private static func smooth(_ raw: [Fix]) -> [Fix] {
        if raw.count < 2 { return raw }
        let filter = AdaptiveLocationFilter()
        var smoothed = raw.map { filter.add($0) }
        // 출발점은 경로의 기준이므로 그대로 둔다. 마지막 점도 충분히 정확하면 부모가
        // 보는 현재 위치와 경로 끝이 어긋나지 않도록 원시 좌표를 유지한다.
        smoothed[0] = raw.first!
        if raw.last!.accuracy > 0 && raw.last!.accuracy <= preciseEndpointMeters {
            smoothed[smoothed.count - 1] = raw.last!
        }
        return smoothed
    }

    private final class AdaptiveLocationFilter {
        private var lat = 0.0
        private var lng = 0.0
        private var variance = -1.0
        private var at: Int64 = 0

        func add(_ fix: Fix) -> Fix {
            let accuracy = normalizedAccuracy(fix)
            if variance < 0.0 {
                lat = fix.lat
                lng = fix.lng
                variance = accuracy * accuracy
                at = fix.at
                return fix
            }

            let elapsedSeconds = Double(max(fix.at - at, 0)) / 1_000.0
            let processSpeed = max(baseProcessSpeedMps, max(fix.speed, 0.0))
            variance += elapsedSeconds * processSpeed * processSpeed

            let measurementVariance = accuracy * accuracy
            let gain = variance / (variance + measurementVariance)
            lat += gain * (fix.lat - lat)
            lng += gain * (fix.lng - lng)
            variance *= 1.0 - gain
            at = fix.at
            // 코틀린의 `fix.copy(lat = lat, lng = lng)` 와 같다 — 좌표만 평활하고
            // speed 를 포함한 나머지 필드는 원본 그대로 들고 간다.
            return Fix(lat: lat, lng: lng, accuracy: fix.accuracy, at: fix.at, speed: fix.speed)
        }

        private func normalizedAccuracy(_ fix: Fix) -> Double {
            fix.accuracy > 0 ? max(minAccuracyMeters, fix.accuracy) : unknownAccuracyMeters
        }
    }
}
