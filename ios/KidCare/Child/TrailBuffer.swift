import Foundation

/// 오늘 확보한 점을 메모리에 쌓고, 날짜가 바뀌면 비우고 새로 시작한다.
/// 정본은 안드로이드 `child/TrailUploader.kt:73-104`(그 클래스의 버퍼 부분만 떼어 온 것이다 —
/// 올리는 일은 `TrailUploader.swift` 가 한다).
///
/// 자정 직전의 마지막 업로드 뒤에 들어온 점 몇 개는 어제 문서에 안 담긴 채 버려지는데
/// **그건 의도된 것이다** — 어제 문서를 다시 쓰려면 쓰기가 하나 더 들고, 자정 무렵 몇 분의
/// 점을 위해 가족당 하루 20쓰기 예산을 쓸 이유가 없다(`TrailUploader.kt:38-44`).
@MainActor
final class TrailBuffer {

    private(set) var points: [Fix] = []
    private(set) var dayKey: String?

    /// 프로세스가 죽었다 살아난 경우 오늘 걸어온 길을 파일에서 되찾는다. 뜰 때 딱 한 번 부른다.
    /// 파일이 어제 것이면 아무것도 안 한다 — 다음 [append] 가 날짜 불일치를 보고 새로 만든다.
    ///
    /// 돌려주는 마지막 점은 호출자가 **필터의 기준점**으로 이어 쓴다. 서비스가 다시 뜬 직후의
    /// 첫 좌표를 무조건 새 출발점으로 넣으면 실제로는 가만히 있어도 이전 마지막 점과 GPS
    /// 오차만큼 비스듬한 선이 하나 생긴다(`TrailUploader.kt:79-82`).
    ///
    /// **그 복구된 점으로는 절대 상태 문서를 쓰지 않는다** — 몇 시간 전 점이 서버 시각으로
    /// "방금"이 되어 부모가 그걸 방금 확인한 위치로 읽는다(`TrackingService.kt:713-717`).
    /// 그 규율은 `TrackingCoordinator` 가 지킨다(복구한 점을 `lastFix` 에 넣지 않는다).
    @discardableResult
    func restore(store: TrailStore, zone: TimeZone, nowMillis: Int64) -> Fix? {
        guard let saved = store.load() else { return nil }
        guard saved.dayKey == DayPicker.todayKey(zone: zone, nowMillis: nowMillis) else { return nil }
        points += saved.points
        dayKey = saved.dayKey
        return saved.points.last
    }

    /// 점 하나를 쌓는다. **Firestore 에는 아무것도 안 나간다**(`TrailUploader.kt:95-104`).
    func append(_ fix: Fix, store: TrailStore, zone: TimeZone) {
        let key = DayPicker.todayKey(zone: zone, nowMillis: fix.at)
        if key != dayKey {
            points.removeAll()
            dayKey = key
            store.reset(dayKey: key)
        }
        points.append(fix)
        store.append(fix)
    }
}
