import Foundation

/// 위치 점 목록을 머무름/이동 구간으로 묶는다. 정본은 안드로이드 `logic/SegmentBuilder.kt`.
///
/// 판정 기준은 설계서 §4.2 다:
///   - 반경 40m 안에 5분 이상 있으면 머무름
///   - 반경을 벗어난 점이 **연속 2개** 나와야 머무름이 끝난다. 1개는 GPS 가 튄 것으로 본다.
///   - 5분을 못 채운 정지는 이동에 흡수한다(신호 대기 같은 것)
///
/// "연속 2개" 규칙이 핵심이다. 실내에서는 좌표가 수십 미터씩 흔들리고 가끔 수백 미터를 튀는데,
/// 한 점만 보고 머무름을 끊으면 학교에 있는 6시간이 수십 개 구간으로 쪼개진다.
enum SegmentBuilder {

    /// 이 반경 안에 있으면 같은 자리로 본다. `SegmentBuilder.kt:63` (40.0).
    ///
    /// **100m 는 아이의 하루를 한 덩어리로 만들었다.** 집·놀이터·학원이 모두 반경 100m 안에 있는
    /// 생활권이면 그 전부가 머무름 **하나**로 묶이고, 이동 구간이 아예 안 생겨 지도에 선이 한 줄도
    /// 안 나온다. 40m 는 걸어서 1분 거리(약 70m)를 서로 다른 곳으로 가른다.
    static let stayRadiusMeters: Double = 40.0

    /// 이 시간 이상 머물러야 머무름으로 인정한다. `:66` (5분).
    static let minStayMillis: Int64 = 5 * 60 * 1000

    /// 반경을 벗어난 점이 이만큼 연속돼야 머무름을 끝낸다. `:69`.
    static let exitConfirmPoints: Int = 2

    /// 가중 평균에서 오차를 이 값보다 작게 치지 않는다. `:79` (5.0).
    ///
    /// 두 가지를 막는다. (1) 0 으로 나누기 — 옛 `PointDoc.accuracy` 는 0 으로 읽힐 수 있다.
    /// (2) 그 0 이 "완벽한 점"으로 해석돼 가중치를 독점하는 것 — **0 은 완벽하다는 뜻이 아니라
    /// 모른다는 뜻이다.** 소비자용 GPS 가 실제로 5m 보다 정확해지는 일은 없다.
    static let minWeightAccuracyMeters: Double = 5.0

    /// `:81-98`.
    static func build(points: [Fix]) -> [Segment] {
        // Firestore 쿼리 결과 순서를 믿지 않는다. 오차가 큰 점은 계산 자체에서 뺀다.
        //
        // 문턱이 `LocationFilter.maxAccuracyMeters`(평소 50m)가 아니라 **완화 문턱(100m)** 인 이유:
        // 그 완화 문턱까지는 `LocationFilter` 가 **일부러** 올린 점이다(`UPLOAD_STALE_FALLBACK`).
        // 여기서 50m 로 자르면 신호가 나빠 간신히 건진 그 점들이 구간 계산에서 통째로 빠져 —
        // 지도 마커는 움직이는데 타임라인만 비는, 원인을 알 수 없는 상태가 된다(`:84-92`).
        let sorted = points
            .filter { $0.accuracy <= LocationFilter.fallbackMaxAccuracyMeters }
            .sorted { $0.at < $1.at }
        if sorted.count < 2 { return [] }

        let stays = findStayRanges(sorted)
        return assemble(sorted, stays)
    }

    /// 머무름으로 인정된 구간의 인덱스 범위들. 서로 겹치지 않고 앞에서부터 정렬돼 있다. `:101-129`.
    private static func findStayRanges(_ points: [Fix]) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        var start = 0
        while start < points.count {
            let anchor = points[start]
            var lastInside = start
            var outsideRun = 0
            var cursor = start
            while cursor + 1 < points.count {
                cursor += 1
                if LocationFilter.distanceMeters(anchor, points[cursor]) <= stayRadiusMeters {
                    lastInside = cursor
                    outsideRun = 0
                } else {
                    outsideRun += 1
                    // 이 `break` 의 자리를 한 칸이라도 밀면 실내에서 6시간짜리 머무름이 수십 개로
                    // 쪼개진다(`:116`).
                    if outsideRun >= exitConfirmPoints { break }
                }
            }
            let lasted = points[lastInside].at - anchor.at
            if lastInside > start, lasted >= minStayMillis {
                ranges.append(start...lastInside)
                start = lastInside + 1
            } else {
                // 머무름이 아니면 한 칸만 밀고 다시 본다. 하루 점이 수백 개라 이 정도면 충분하다.
                start += 1
            }
        }
        return ranges
    }

    /// 머무름 범위 사이를 이동 구간으로 채운다. 이동은 앞뒤 머무름의 끝점을 공유해 선이 끊기지
    /// 않게 한다. `:132-142`.
    private static func assemble(_ points: [Fix], _ stays: [ClosedRange<Int>]) -> [Segment] {
        var result: [Segment] = []
        var cursor = 0
        for stay in stays {
            if stay.lowerBound > cursor { addMove(points, cursor, stay.lowerBound, &result) }
            result.append(staySegment(points, stay))
            cursor = stay.upperBound
        }
        if cursor < points.count - 1 { addMove(points, cursor, points.count - 1, &result) }
        return result
    }

    /// `:144-161`.
    private static func addMove(_ points: [Fix], _ from: Int, _ to: Int, _ into: inout [Segment]) {
        if to <= from { return }
        var distance = 0.0
        for i in from..<to { distance += LocationFilter.distanceMeters(points[i], points[i + 1]) }
        into.append(Segment(
            type: .move,
            startAt: points[from].at,
            endAt: points[to].at,
            lat: points[to].lat,
            lng: points[to].lng,
            distanceMeters: distance,
            pointCount: to - from + 1,
            // 이동 구간에는 이름을 안 붙이므로 가중 평균을 낼 이유가 없다. 도착 지점을 그대로 둔다.
            nameLat: points[to].lat,
            nameLng: points[to].lng
        ))
    }

    /// `:163-184`.
    private static func staySegment(_ points: [Fix], _ range: ClosedRange<Int>) -> Segment {
        let slice = Array(points[range])
        // 가중치는 1/오차². 오차를 표준편차로 보면 역분산 가중이 되어 정확한 점이 이름을 결정한다.
        // 합이 0 이 되는 경우는 없다 — 아래 floor 때문에 모든 가중치가 양수다(`:168-171`).
        let weights = slice.map { fix -> Double in
            let a = max(fix.accuracy, minWeightAccuracyMeters)
            return 1.0 / (a * a)
        }
        let weightSum = weights.reduce(0, +)
        return Segment(
            type: .stay,
            startAt: slice[0].at,
            endAt: slice[slice.count - 1].at,
            lat: slice.reduce(0) { $0 + $1.lat } / Double(slice.count),
            lng: slice.reduce(0) { $0 + $1.lng } / Double(slice.count),
            distanceMeters: 0.0,
            pointCount: slice.count,
            nameLat: slice.indices.reduce(0) { $0 + slice[$1].lat * weights[$1] } / weightSum,
            nameLng: slice.indices.reduce(0) { $0 + slice[$1].lng * weights[$1] } / weightSum
        )
    }
}
