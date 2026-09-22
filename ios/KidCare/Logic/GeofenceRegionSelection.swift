import Foundation

/// 장소 목록에서 OS 에 걸 20개를 고른다. 정본 `child/PlaceWatcher.kt:168-174`(코틀린에서는 인라인).
///
/// 순수 함수로 따로 뺀 이유(설계서 §3.1·§7.2): 아이폰은 **OS 상한이 정확히 20** 이라 여기서 잘못
/// 자르면 그 장소의 알림이 통째로 사라지는데, `CLLocationManager` 를 끼고는 그것을 테스트할 수 없다.
enum GeofenceRegionSelection {

    /// `PlaceWatcher.kt:217`. 안드로이드는 OS 상한 100 중 스스로 20 으로 잘랐고, 아이폰은 그 20 이
    /// 곧 OS 상한이다 — 그래서 두 플랫폼의 숫자가 이미 같고 넘칠 일이 구조적으로 없다(설계서 §7.2).
    static let maxRegions = 20

    struct Report {
        let chosen: [Place]
        /// 상한·반경 0 으로 빠진 개수. 부르는 쪽이 로그로 남긴다(`:172-174`).
        let dropped: Int
    }

    static func choose(_ places: [Place], limit: Int = maxRegions) -> [Place] {
        chooseWithReport(places, limit: limit).chosen
    }

    static func chooseWithReport(_ places: [Place], limit: Int = maxRegions) -> Report {
        // 1. 반경이 0 이하인 장소를 뺀다. 안드로이드는 그런 값 하나가 목록 전체의 등록을
        //    실패시켰다(`:150-152`). iOS 도 반경 0 인 CLCircularRegion 은 전환을 주지 않는다.
        let usable = places.filter { $0.radiusMeters > 0 }
        // 2. **이름순으로** 앞에서 limit 개. 읽어온 순서로 자르면 어떤 장소는 하루는 걸리고
        //    하루는 안 걸린다(`:166-168`). 코틀린 sortedBy 는 안정 정렬이고 String.compareTo 는
        //    UTF-16 코드 단위 비교인데 Swift 는 둘 다 다르므로(판정 기록 3) 직접 맞춘다.
        let sorted = usable.enumerated().sorted { left, right in
            if left.element.name == right.element.name { return left.offset < right.offset }
            return utf16Less(left.element.name, right.element.name)
        }.map(\.element)
        let chosen = Array(sorted.prefix(limit))
        return Report(chosen: chosen, dropped: places.count - chosen.count)
    }

    /// 코틀린 `String.compareTo` 와 같은 순서 — UTF-16 코드 단위를 앞에서부터 비교하고,
    /// 한쪽이 다른 쪽의 접두사면 짧은 쪽이 앞이다.
    private static func utf16Less(_ a: String, _ b: String) -> Bool {
        var x = a.utf16.makeIterator()
        var y = b.utf16.makeIterator()
        while true {
            switch (x.next(), y.next()) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (l?, r?) where l != r: return l < r
            default: continue
            }
        }
    }
}
