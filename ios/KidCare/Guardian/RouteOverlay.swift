import Foundation

/// 원시 GPS 점을 이동(MOVE) 구간별 선으로 나눈다. 정본은 안드로이드
/// `MapTimelineFragment.buildRouteSections`(:1144)다.
///
/// 안드로이드의 `RouteSection`(구간 하나 = 여러 레그의 목록)보다 이 타입은 더
/// 단순하다 — 레그 하나마다 원소 하나를 만든다. 같은 이동 구간에서 GPS 공백으로
/// 레그가 여럿 갈리면(`RoutePathRefiner` 가 gapBreak 로 자른 경우) 그 레그들이
/// 같은 [segmentIndex] 를 공유한다. `segmentIndex` 는 [RouteOverlay.sections] 에
/// 넘긴 `segments` 배열 안에서 그 구간의 위치다 — 옛 기록(원시점 없음)을 근사할 때
/// 그 앞뒤 구간을 가리키는 데도 같은 인덱스를 쓴다.
struct RouteSection {
    let segmentIndex: Int?
    /// Task 8: 이 구간을 낸 `SegmentDoc.startAt`. 정본은 안드로이드 `RouteSection`
    /// (`MapTimelineFragment.kt`) — 숨김 상태(`MapViewModel.hiddenRouteStarts`)는
    /// **이 값으로** 키를 삼는다, [segmentIndex] 가 아니다: 날짜를 다시 읽거나 새
    /// 구간이 앞에 끼어들면 인덱스가 바뀌어 숨긴 선이 엉뚱한 구간으로 옮겨 붙는다
    /// (브리프). [segmentIndex] 는 행·구간을 찾는 용도로만 남긴다.
    let startAt: Int64
    let coordinates: [(lat: Double, lng: Double)]
}

enum RouteOverlay {

    /// 하루 원시 점과 구간 요약을 받아 지도에 그릴 선들을 만든다.
    ///
    /// 창은 구간의 startAt..endAt 그대로가 아니라 [RouteWindows.partition] 으로
    /// **하루 전체를 빈틈없이 나눈 것**을 쓴다 — 안드로이드
    /// `buildRouteSections` 주석과 같은 이유다. 창 밖(머무름 기준점, 마지막 이동
    /// 뒤의 최신 점)에 떨어진 점이 어느 선에도 안 들어가 조용히 사라지는 것을
    /// 막는다. 흔들림 정리는 창이 아니라 [RoutePathRefiner] 가 맡는다.
    static func sections(points: [TrailPoint], segments: [SegmentDoc]) -> [RouteSection] {
        let sortedPoints = points.sorted { $0.at < $1.at }
        let moveEntries = segments.enumerated().filter { $0.element.type == "MOVE" }
        guard !moveEntries.isEmpty else { return [] }
        let sortedMoves = moveEntries.sorted { $0.element.startAt < $1.element.startAt }

        let windows = RouteWindows.partition(
            moves: sortedMoves.map { $0.element.startAt..<($0.element.endAt + 1) }
        )

        var result: [RouteSection] = []
        for (windowIndex, entry) in sortedMoves.enumerated() {
            let originalIndex = entry.offset
            let startAt = entry.element.startAt
            let window = windows[windowIndex]
            let windowPoints = sortedPoints.filter { window.contains($0.at) }

            var legs: [[(lat: Double, lng: Double)]] = []
            if windowPoints.count >= 2 {
                legs = RoutePathRefiner.refine(points: windowPoints.map(\.asFix))
                    .map { leg in leg.points.map { (lat: $0.lat, lng: $0.lng) } }
                    .filter { $0.count >= 2 }
            }

            // points 가 없던 옛 기록도 양옆 구간 좌표로 근사해 계속 볼 수 있게
            // 한다 — 안드로이드 buildRouteSections 의 fallback 과 같은 이유.
            if legs.isEmpty {
                let fallback = [originalIndex - 1, originalIndex, originalIndex + 1]
                    .filter { segments.indices.contains($0) }
                    .map { segments[$0] }
                    .filter { $0.lat.isFinite && $0.lng.isFinite }
                    .reduce(into: [(lat: Double, lng: Double)]()) { acc, seg in
                        if !acc.contains(where: { $0.lat == seg.lat && $0.lng == seg.lng }) {
                            acc.append((lat: seg.lat, lng: seg.lng))
                        }
                    }
                if fallback.count >= 2 { legs = [fallback] }
            }

            for leg in legs {
                result.append(RouteSection(segmentIndex: originalIndex, startAt: startAt, coordinates: leg))
            }
        }
        return result
    }
}
