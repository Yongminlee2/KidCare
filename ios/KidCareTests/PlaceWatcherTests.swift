import Foundation
import Testing
@testable import KidCare

/// 정본은 `child/PlaceWatcher.kt`. CoreLocation 과 Firestore 는 프로토콜·클로저로 가려 두고,
/// **순서**(상태를 먼저 저장하고 그다음에 이벤트를 쓴다)와 빈 목록 보호를 고정한다.
@MainActor
struct PlaceWatcherTests {

    final class 가짜_감시자: RegionMonitor {
        private(set) var 마지막_등록: [Place] = []
        private(set) var 등록_횟수 = 0
        private(set) var 한_점_부탁 = 0
        func replaceMonitoredRegions(_ places: [Place]) {
            마지막_등록 = places
            등록_횟수 += 1
        }
        func requestOneShotFix() { 한_점_부탁 += 1 }
    }

    /// 이벤트 쓰기가 실패하는 상황을 만든다 — 오프라인·권한 거부가 흔한 상태다.
    struct 쓰기실패: Error {}

    private static let 위도1도 = Double.pi / 180.0 * 6_371_000.0
    private func 북쪽(_ meters: Double) -> Double { 37.5665 + meters / Self.위도1도 }
    private func 점(_ meters: Double, accuracy: Double = 10, at: Int64 = 1_000_000) -> Fix {
        Fix(lat: 북쪽(meters), lng: 126.9780, accuracy: accuracy, at: at)
    }
    private func 장소들(_ count: Int) -> [PlaceDoc] {
        (0..<count).map { PlaceDoc(id: "id\($0)", name: "곳\($0)", lat: 37.5665, lng: 126.9780, radiusMeters: 100) }
    }

    final class 기록 {
        private(set) var docs: [EventDoc] = []
        func 더한다(_ doc: EventDoc) { docs.append(doc) }
    }

    private func 만든다(실패: Bool = false) -> (PlaceWatcher, 가짜_감시자, PlaceStateStore, 기록) {
        let store = PlaceStateStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let monitor = 가짜_감시자()
        let 적힌것 = 기록()
        let watcher = PlaceWatcher(stateStore: store, monitor: monitor) { _, doc in
            적힌것.더한다(doc)
            if 실패 { throw 쓰기실패() }
        }
        return (watcher, monitor, store, 적힌것)
    }

    @Test("장소를 받으면 이름순 20개만 OS 에 건다 (:154-175, GeofenceRegionSelection)")
    func 스물만_건다() {
        let (watcher, monitor, _, _) = 만든다()
        watcher.apply(placeDocs: 장소들(25))
        #expect(monitor.마지막_등록.count == 20)
        #expect(watcher.places.count == 25, "판정은 스물다섯 곳 전부로 한다 — OS 상한은 등록에만 걸린다")
    }

    @Test("장소를 한 번도 못 읽었으면 그대로 돌아간다 — 저장된 상태를 지우지 않는다 (:105-116)")
    func 빈_목록_보호() async throws {
        let (watcher, _, store, 적힌것) = 만든다()
        store.states = [PlaceState(placeId: "id0", inside: true, lastEventAt: 5)]
        _ = try await watcher.onFix(familyId: "f", childUid: "c", fix: 점(1_000))
        #expect(적힌것.docs.isEmpty)
        #expect(store.states.count == 1, "빈 목록으로 판정하면 아이가 이미 안에 있던 곳이 전부 '처음 보는 장소'가 된다")
    }

    @Test("도착하면 place_enter 를 쓴다 — at 은 점의 시각이고 childUid 는 지금 로그인한 uid 다 (:125-139)")
    func 도착_이벤트() async throws {
        let (watcher, _, store, 적힌것) = 만든다()
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        store.states = [PlaceState(placeId: "id0", inside: false, lastEventAt: 0)]
        let 쓴_개수 = try await watcher.onFix(familyId: "f", childUid: "아이uid", fix: 점(0, at: 777))
        #expect(쓴_개수 == 1, "부르는 쪽이 '사건이 있었다'를 알아야 §6.4-3 업로드 규칙을 켤 수 있다")
        #expect(적힌것.docs.count == 1)
        let doc = try #require(적힌것.docs.first)
        #expect(doc.type == EventType.placeEnter)
        #expect(doc.at == 777, "콜백이 온 순간이 아니라 위치가 잡힌 순간이다(PlaceGeofenceReceiver.kt:43-45)")
        #expect(doc.childUid == "아이uid")
        #expect(doc.placeName == "학교")
        #expect(doc.read == false, "규칙이 read == false 를 요구한다(firestore.rules:308)")
    }

    @Test("상태를 **먼저** 저장한다 — 이벤트 쓰기가 실패해도 '안에 있다'는 남는다 (:120-123)")
    func 상태가_먼저다() async {
        let (watcher, _, store, _) = 만든다(실패: true)
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        store.states = [PlaceState(placeId: "id0", inside: false, lastEventAt: 0)]
        await #expect(throws: 쓰기실패.self) {
            try await watcher.onFix(familyId: "f", childUid: "c", fix: 점(0))
        }
        #expect(store.states == [PlaceState(placeId: "id0", inside: true, lastEventAt: 1_000_000)],
                "반대 순서면 오프라인일 때 같은 도착이 점마다 다시 잡혀 연결이 돌아올 때 여러 번 올라간다")
    }

    @Test("못 믿는 점에서는 저장도 쓰기도 없다 (:78 의 앞단)")
    func 못_믿는_점() async throws {
        let (watcher, _, store, 적힌것) = 만든다()
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        store.states = [PlaceState(placeId: "id0", inside: false, lastEventAt: 0)]
        _ = try await watcher.onFix(familyId: "f", childUid: "c", fix: 점(0, accuracy: 150))
        #expect(적힌것.docs.isEmpty)
        #expect(store.states == [PlaceState(placeId: "id0", inside: false, lastEventAt: 0)])
    }

    @Test("한 점에서 사건이 둘 이상 나올 수 있다 — 둘 다 쓴다 (known-issues 21번)")
    func 두_사건() async throws {
        let (watcher, _, store, 적힌것) = 만든다()
        watcher.apply(placeDocs: [
            PlaceDoc(id: "집", name: "집", lat: 37.5665, lng: 126.9780, radiusMeters: 100),
            PlaceDoc(id: "놀이터", name: "놀이터", lat: 북쪽(50), lng: 126.9780, radiusMeters: 100),
        ])
        store.states = [PlaceState(placeId: "집", inside: false, lastEventAt: 0),
                        PlaceState(placeId: "놀이터", inside: false, lastEventAt: 0)]
        let 쓴_개수 = try await watcher.onFix(familyId: "f", childUid: "c", fix: 점(25))
        #expect(쓴_개수 == 2)
        #expect(적힌것.docs.count == 2)
    }

    @Test("모드 판정용 안/밖은 50m 게이트를 쓰고 이탈 여유를 그대로 적용한다 (:77-100)")
    func 아는_장소_안인가() {
        let (watcher, _, store, _) = 만든다()
        #expect(watcher.isInsideKnownPlace(점(0)) == false, "장소가 없으면 false 다 — 판단 보류(nil)가 아니다")
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        #expect(watcher.isInsideKnownPlace(점(0, accuracy: 50.5)) == nil, "평상시 문턱(50m)을 넘는 점에서는 판단을 보류한다")
        #expect(watcher.isInsideKnownPlace(점(0)) == true)
        #expect(watcher.isInsideKnownPlace(점(120)) == false)
        store.states = [PlaceState(placeId: "id0", inside: true, lastEventAt: 0)]
        #expect(watcher.isInsideKnownPlace(점(120)) == true, "이미 안이면 반경 + 여유 50m 까지 안으로 본다")
    }

    @Test("지역 경계 콜백은 이벤트를 안 쓰고 좌표 한 점만 부탁한다 (설계서 §7.1, PlaceGeofenceReceiver.kt:13-19)")
    func 지역_콜백은_신호일_뿐() {
        let (watcher, monitor, _, 적힌것) = 만든다()
        watcher.apply(placeDocs: 장소들(1))
        watcher.regionCrossed(placeId: "id0")
        #expect(적힌것.docs.isEmpty, "그 콜백에는 히스테리시스도 중복 억제도 정확도 문턱도 없다")
        #expect(monitor.한_점_부탁 == 1)
    }

    // MARK: 2단계 M3 — 목록이 실제로 바뀐 때만 다시 건다

    @Test("같은 목록이면 OS 에 다시 안 건다 — 앱이 뜨자마자 캐시본·서버본으로 두 번 도는 자리다 (2단계 M3)")
    func 같은_목록이면_다시_안_건다() {
        let (watcher, monitor, _, _) = 만든다()
        let 곳 = PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)
        watcher.apply(placeDocs: [곳])
        #expect(monitor.등록_횟수 == 1, "첫 apply 는 언제나 건다")

        watcher.apply(placeDocs: [곳])
        #expect(monitor.등록_횟수 == 1, "같은 원을 지웠다 다시 걸면 iOS 의 초기 상태 판정이 매번 처음부터 시작한다")

        // 이름과 알림 스위치는 OS 에 가는 값이 아니다 — 바뀌어도 원은 그대로다.
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학원", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        #expect(monitor.등록_횟수 == 1)
        #expect(watcher.places.first?.name == "학원", "건너뛰는 것은 OS 등록뿐이다 — places 는 언제나 갱신한다")
    }

    @Test("반경이 바뀌면 다시 건다 — 원이 실제로 달라졌다")
    func 반경이_바뀌면_다시_건다() {
        let (watcher, monitor, _, _) = 만든다()
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 250)])
        #expect(monitor.등록_횟수 == 2)
        #expect(monitor.마지막_등록.first?.radiusMeters == 250)

        // 장소가 통째로 사라지면 걸어 둔 원도 걷어야 한다 — 안 그러면 지운 장소의 알림이 계속 온다.
        watcher.apply(placeDocs: [])
        #expect(monitor.등록_횟수 == 3)
        #expect(monitor.마지막_등록.isEmpty)
    }
}
