import Foundation
import os

/// OS 지역 감시를 거는 쪽. 실제 구현은 `LocationCollector` 가 갖는다 — `PlaceWatcher` 가
/// `CLLocationManager` 를 직접 만지면 테스트에서 그 매니저를 세울 수 없고, 매니저는 앱이 사는 동안
/// 하나여야 한다(설계서 §5.2).
@MainActor
protocol RegionMonitor: AnyObject {
    /// **전부 지우고 다시 건다**(`PlaceWatcher.kt:142-152`). 부모가 지운 장소의 전환이 계속
    /// 올라오는 것을 막는다. 개별 삭제로 맞추려면 "직전에 무엇을 걸었는지"를 따로 기억해야 하는데,
    /// 스무 개짜리 목록을 통째로 다시 거는 비용이 그 기억을 관리하는 비용보다 싸다.
    func replaceMonitoredRegions(_ places: [Place])

    /// 지금 좌표 한 점을 부탁한다. iOS 의 지역 콜백은 좌표를 안 주기 때문이다(설계서 §7.1).
    func requestOneShotFix()
}

/// 아이 폰의 장소 판정. `GeofenceEvaluator` 를 아이폰에 붙이는 껍데기다. 정본 `child/PlaceWatcher.kt`.
///
/// ## OS 지역 감시는 "알림"이 아니라 "판정해 보라는 신호"다 (`:22-35`)
///
/// 전환 콜백에서 곧장 `events/` 에 적으면 히스테리시스(반경 + 50m)도, 5분 중복 억제도, 정확도
/// 문턱도 통째로 건너뛴다 — 경계에 앉은 아이 하나 때문에 부모 폰이 하루 종일 운다. 아이폰에서는
/// 이유가 하나 더 있다: 그 콜백에는 **좌표가 아예 안 실려 온다.** 그래서 `regionCrossed` 는 좌표
/// 한 점을 부탁하기만 하고, 알릴지 말지는 언제나 판정기가 정한다.
///
/// OS 지역 감시를 그래도 거는 이유는 **앱이 죽어 있어도 되살리기 때문**이다(설계서 §7.4).
/// 되살아나면 장소를 읽고, 상태 저장소를 읽고, 판정하고, 필요하면 이벤트를 쓰고, 즉시 업로드한다.
@MainActor
final class PlaceWatcher {

    private let stateStore: PlaceStateStore
    private let monitor: RegionMonitor
    private let addEvent: (String, EventDoc) async throws -> Void
    private let logger = Logger(subsystem: "com.kidcare.family", category: "PlaceWatcher")

    /// 마지막으로 읽어 온 장소 목록. 구독이 채우고 `onFix` 가 읽는다.
    /// 코틀린은 두 코루틴이 부딪혀 `@Volatile` 이었는데(`:46-52`), 여기서는 둘 다 `@MainActor` 라
    /// 잠금이 필요 없다 — `TrailBuffer` 가 스레드를 하나로 유지하는 것과 같은 선택이다(설계서 §3.6).
    private(set) var places: [Place] = []

    init(stateStore: PlaceStateStore,
         monitor: RegionMonitor,
         addEvent: @escaping (String, EventDoc) async throws -> Void = { familyId, doc in
             try await EventRepository.add(familyId: familyId, doc: doc)
         }) {
        self.stateStore = stateStore
        self.monitor = monitor
        self.addEvent = addEvent
    }

    /// 장소 목록을 갈아 끼우고 OS 지역을 다시 건다(`:63-67`). 부르는 곳은
    /// `PlaceRepository.observePlaces` 의 스냅샷 하나뿐이다 — 앱이 (다시) 뜰 때의 첫 스냅샷이
    /// 안드로이드의 `refresh` 자리이고, 그 뒤의 스냅샷이 `sync_rules` 자리다(설계서 §7.3).
    ///
    /// OS 등록은 **고른 결과가 실제로 달라졌을 때만** 다시 건다. `observePlaces` 가
    /// `includeMetadataChanges: true`(`PlaceRepository.swift:42`)라 앱이 뜨자마자 캐시본·서버본으로
    /// 두 번 도는데, 그때마다 스무 개를 지웠다 다시 걸면 iOS 의 초기 상태 판정이 매번 처음부터
    /// 시작한다(2단계 통합 검토 M3). 비교는 OS 에 실제로 가는 넷 — id·lat·lng·반경 — 으로만 한다.
    /// 이름이나 알림 스위치가 바뀌어도 원은 그대로다.
    ///
    /// **`places` 는 언제나 갱신한다.** 건너뛰는 것은 OS 등록뿐이다 — 이 구분을 놓치면 부모가
    /// 지운 장소의 판정이 살아남는다.
    func apply(placeDocs: [PlaceDoc]) {
        places = placeDocs.map(\.asPlace)
        let report = GeofenceRegionSelection.chooseWithReport(places)
        if report.dropped > 0 {
            // 조용히 실패하면 "왜 도착 알림이 안 오지"를 알아낼 방법이 없다(`:172-174`).
            logger.warning("장소 \(self.places.count)개 중 \(report.chosen.count)개만 지역으로 걸었다(상한 \(GeofenceRegionSelection.maxRegions) · 반경 0 제외)")
        }
        let regions = report.chosen.map(RegionKey.init)
        // **첫 apply 는 언제나 건다**(`appliedRegions` 가 아직 nil 이다). 앱이 죽어 있는 동안
        // 부모가 장소를 전부 지웠으면 OS 에는 옛 원이 그대로 남아 있는데, 빈 목록을 "같다"고
        // 넘기면 그 원들이 영영 안 걷힌다.
        guard appliedRegions != regions else { return }
        appliedRegions = regions
        monitor.replaceMonitoredRegions(report.chosen)
    }

    /// 감시를 접는다 — OS 에 걸어 둔 원을 **전부 걷는다**(통합 검토 M2).
    ///
    /// `LocationCollector.stop()` 은 `stopUpdatingLocation`·`stopMonitoringSignificantLocationChanges`
    /// 만 부르고 등록한 지역은 그대로 둔다. 그래서 '다시 연결'로 역할을 지운 뒤에도 옛 가족의
    /// 원 스무 개가 남아 계속 앱을 깨운다. 다시 페어링하면 새 `PlaceWatcher` 의 첫 `apply` 가
    /// 저절로 낫지만, 다시 페어링하지 않는 폰에서는 영영 남는다(대가는 헛깨움과 배터리다 —
    /// 가족이 없어 사건은 안 나간다). 거는 쪽이 `apply` 이므로 걷는 쪽도 여기에 둔다.
    ///
    /// `appliedRegions` 를 `[]` 로 적는다 — "아직 한 번도 안 걸었다"(`nil`)가 아니라
    /// "지금 OS 에 걸린 것이 없다"가 사실이기 때문이다.
    func stopMonitoring() {
        appliedRegions = []
        monitor.replaceMonitoredRegions([])
    }

    /// OS 에 실제로 가는 값만 담는다 — 이름·알림 스위치는 원을 바꾸지 않으므로 뺀다.
    private struct RegionKey: Equatable {
        let id: String
        let lat: Double
        let lng: Double
        let radiusMeters: Double

        init(_ place: Place) {
            id = place.id
            lat = place.lat
            lng = place.lng
            radiusMeters = place.radiusMeters
        }
    }

    /// 마지막으로 OS 에 건 원들. `nil` 은 "아직 한 번도 안 걸었다"로, 빈 배열(`[]`, 걸 것이
    /// 하나도 없다)과 다른 말이다.
    private var appliedRegions: [RegionKey]?

    /// 현재 좌표가 부모가 등록한 장소 안인지 빠르게 확인한다(`:69-100`).
    ///
    /// 이 값은 알림 판정이 아니라 **수집 주기를 낮추는 데만** 쓴다(설계서 §5.1 의 '등록 장소 머무름'
    /// 갈래). 정확도가 나쁜 점으로 모드를 바꾸면 실제로 학교를 나갔는데도 1분 주기에 머물 수 있으므로
    /// 평상시 문턱(50m)을 넘는 점에서는 판단을 보류한다(nil). 이미 안으로 판정된 장소에는 이탈 여유를
    /// 그대로 적용해 경계의 흔들림으로 주기가 출렁이지 않게 한다.
    func isInsideKnownPlace(_ fix: Fix) -> Bool? {
        guard fix.lat.isFinite, fix.lng.isFinite,
              (-90.0...90.0).contains(fix.lat), (-180.0...180.0).contains(fix.lng),
              fix.accuracy.isFinite, fix.accuracy >= 0,
              fix.accuracy <= LocationFilter.maxAccuracyMeters else { return nil }

        if places.isEmpty { return false }
        let statesById = Dictionary(stateStore.states.map { ($0.placeId, $0) }, uniquingKeysWith: { _, last in last })
        return places.contains { place in
            let distance = LocationFilter.distanceMeters(
                Fix(lat: place.lat, lng: place.lng, accuracy: 0, at: 0), fix)
            let margin = statesById[place.id]?.inside == true ? GeofenceEvaluator.exitMarginMeters : 0
            return distance <= place.radiusMeters + margin
        }
    }

    /// 위치 한 점으로 판정하고, 알릴 것이 나오면 `events/` 에 적는다(`:102-140`).
    /// 돌려주는 값은 **실제로 쓴 사건 수**다 — 부르는 쪽(`TrackingCoordinator`)이 설계서 §6.4-3
    /// ("사건 직후에는 업로드 규칙 1·2를 무시한다")을 켜려면 그 사실을 알아야 한다.
    ///
    /// 장소를 아직 한 번도 못 읽었거나 정말 하나도 없으면 그대로 돌아간다. **저장된 상태를 지우지
    /// 않는 것이 중요하다** — 여기서 빈 목록으로 판정하면 판정기가 "지금 있는 장소만 남긴다" 규칙에
    /// 따라 상태를 통째로 비우고, 잠시 뒤 장소를 읽어오면 아이가 이미 안에 있는 곳들이 전부
    /// "처음 보는 장소"가 된다(`:105-108`).
    ///
    /// 실패는 여기서 삼키지 않고 위로 던진다(`:110-112`).
    @discardableResult
    func onFix(familyId: String, childUid: String, fix: Fix) async throws -> Int {
        let known = places
        if known.isEmpty { return 0 }

        let previous = stateStore.states
        let (hits, next) = GeofenceEvaluator.evaluate(places: known, states: previous, fix: fix)
        // 상태를 **먼저** 저장한다(`:120-123`). 이벤트 쓰기가 실패해 예외로 빠져나가더라도 "안에
        // 있다"는 사실은 남아야 한다. 반대 순서면 오프라인일 때 같은 전환이 위치 점마다 다시 잡혀
        // 연결이 돌아오는 순간 같은 도착이 여러 번 올라간다.
        if next != previous { stateStore.states = next }

        var written = 0
        for hit in hits {
            try await addEvent(familyId, EventDoc(
                id: "",
                type: hit.entering ? EventType.placeEnter : EventType.placeExit,
                // 폰 시계로 잰 값이다(위치가 잡힌 순간). 규칙이 서버 시각과 대조하므로 아이 폰 시계가
                // 한 시간 넘게 앞서 있으면 이 쓰기가 막힌다 — 그건 그 폰의 시계 문제이고, 여기서
                // "지금"으로 바꿔치기하면 일어난 시각을 지어내는 셈이 된다(`:130-133`).
                at: hit.at,
                childUid: childUid,
                placeName: hit.placeName))
            written += 1
        }
        return written
    }

    /// OS 가 "경계를 넘었다"고 앱을 깨웠다. **여기서 아무것도 판정하지 않는다**(설계서 §7.1).
    /// iOS 는 `CLRegion` 만 주고 좌표를 안 주므로 지금 좌표 한 점을 부탁하고 끝낸다. 그 점이 보통
    /// 점과 똑같은 길(`TrackingCoordinator.handle`)을 지나 `onFix` 로 온다. 못 얻으면 아무 판단도
    /// 하지 않는다 — 지어내지 않는다.
    func regionCrossed(placeId: String) {
        logger.info("지역 전환 신호: placeId=\(placeId, privacy: .public) — 좌표 한 점을 부탁한다")
        monitor.requestOneShotFix()
    }
}
