import FirebaseFirestore
import Foundation
import Observation

/// 장소 탭의 두뇌. 정본은 안드로이드 `guardian/PlaceFragment.kt` — 줄 번호는 각 주석에 적었다.
///
/// ## 좌표는 숫자로 넣게 하지 않는다(:40-51)
/// 지도 **한가운데가 좌표다.** 지도는 아이의 마지막 확인 위치에서 열린다. 그 위치를 모르면 한반도 전체로
/// 열고 그 사실을 적는다 — 그럴듯한 기본 좌표를 찍어두면 부모가 그 자리를 "확인된 어딘가"로 읽는다.
///
/// ## 장소가 바뀌면 반드시 아이 폰에 알린다(:53-66)
/// 쓰기 갈래는 저장(만들기·고치기 공용)과 삭제 **둘뿐**이고, 둘 다 `쓰고_알린다` 한 곳을 지난다.
/// 특히 위험한 것은 삭제다 — 아이 폰이 모르면 지운 장소의 지오펜스가 계속 운다.
///
/// 세대 번호·뒤로 가기·깃발 규율은 `ScheduleViewModel` 과 같다(:98).
@Observable
@MainActor
final class PlaceViewModel {

    // MARK: - 상수 (PlaceFragment.kt:921-953, fragment_place.xml:187)

    /// 자녀 `PlaceWatcher.MAX_GEOFENCES`(child/PlaceWatcher.kt:217)와 같아야 한다.
    nonisolated static let maxPlaces = 20
    nonisolated static let minRadiusMeters = 100.0
    nonisolated static let maxRadiusMeters = 1000.0
    nonisolated static let radiusStepMeters = 50.0
    /// 학교·학원 한 채와 그 앞마당(:935-936).
    nonisolated static let defaultRadiusMeters = 200.0
    nonisolated static let placeZoom = 16.0
    nonisolated static let countryZoom = 6.0
    nonisolated static let countryLat = 36.5
    nonisolated static let countryLng = 127.8
    nonisolated static let writeTimeoutMillis: Int64 = 15_000
    nonisolated static let nameMaxLength = 20

    struct 좌표: Equatable {
        let lat: Double
        let lng: Double
    }

    /// 지도에게 보내는 카메라 요청. [번호] 가 바뀔 때만 지도가 움직인다 — 같은 요청을 그리기마다 다시
    /// 적용하면 부모가 옮겨 둔 지도를 도로 빼앗는다.
    struct 카메라: Equatable {
        let lat: Double
        let lng: Double
        let zoom: Double
        let 번호: Int
    }

    struct 반경_원: Equatable {
        let lat: Double
        let lng: Double
        let radiusMeters: Double
    }

    // MARK: - 목록 판

    let familyId: String
    let childUid: String?
    private(set) var places: [PlaceDoc] = []
    private(set) var listLoad: ListLoad = .loading
    private(set) var 상태_줄: String?
    private(set) var pendingSync = false
    /// 아이의 마지막 확인 위치. 한 번만 읽는다 — "그 동네"만 필요하다(:91-96).
    private(set) var 아이_위치: 좌표?
    var 삭제_확인: PlaceDoc?

    // MARK: - 편집 판 (:111-146)

    private(set) var 편집_중 = false
    private(set) var editorPlaceId: String?
    private(set) var editorNewDocId: String?
    private(set) var 이름 = ""
    private(set) var editorLat = 0.0
    private(set) var editorLng = 0.0
    var 반경 = PlaceViewModel.defaultRadiusMeters
    var 도착_알림 = true
    var 나섬_알림 = true
    /// 지금 좌표가 **뜻이 있는 값인가**(:130-144). (0,0)인지로 판단하지 않는다.
    private(set) var 좌표를_골랐나 = false
    private(set) var 저장_중 = false
    private(set) var 편집_줄: String?
    private(set) var 이름_경고 = false
    private(set) var 카메라_요청: 카메라?

    /// 테스트가 기다릴 수 있게 둔다.
    @ObservationIgnored private(set) var 아이_위치_읽기: Task<Void, Never>?
    @ObservationIgnored private var 카메라_번호 = 0
    @ObservationIgnored private var writeGeneration = 0
    @ObservationIgnored private var 떠난_저장_세대: Int?
    @ObservationIgnored private var 시작함 = false
    /// `정리한다()` 뒤에는 새 구독·새 명령·늦은 카메라 이동을 만들지 않는다(4단계 통합 검토 M1).
    @ObservationIgnored private var 닫힘 = false
    @ObservationIgnored private var placeListener: ListenerRegistration?
    @ObservationIgnored private var syncRetryTask: Task<Void, Never>?

    private let syncStore: RuleSyncStore
    private let placesObserve: @Sendable (String, String, @escaping ([PlaceDoc], Bool) -> Void, @escaping (Error) -> Void) -> ListenerRegistration
    private let placeSave: @Sendable (String, String, PlaceDoc) async throws -> String
    private let placeDelete: @Sendable (String, String, String) async throws -> Void
    private let statusFetch: @Sendable (String, String) async throws -> ChildStatusDoc?
    private let commandSend: @Sendable (String, String, String, [String: String]) async throws -> String
    private let writeSleep: @Sendable (Int64) async -> Void
    private let newId: () -> String

    init(
        familyId: String,
        childUid: String?,
        syncStore: RuleSyncStore = RuleSyncStore(kind: .place),
        placesObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping ([PlaceDoc], Bool) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = PlaceRepository.observePlaces,
        placeSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ doc: PlaceDoc) async throws -> String = PlaceRepository.savePlace,
        placeDelete: @escaping @Sendable (_ familyId: String, _ childUid: String, _ id: String) async throws -> Void = PlaceRepository.deletePlace,
        statusFetch: @escaping @Sendable (_ familyId: String, _ childUid: String) async throws -> ChildStatusDoc? = FamilyRepository.fetchChildStatus,
        commandSend: @escaping @Sendable (_ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]) async throws -> String = CommandRepository.send,
        writeSleep: @escaping @Sendable (_ millis: Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        },
        newId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.syncStore = syncStore
        self.placesObserve = placesObserve
        self.placeSave = placeSave
        self.placeDelete = placeDelete
        self.statusFetch = statusFetch
        self.commandSend = commandSend
        self.writeSleep = writeSleep
        self.newId = newId
    }

    // MARK: - 구독 (:357-455)

    func 시작한다() {
        guard !시작함, !닫힘 else { return }
        시작함 = true
        guard let childUid else {
            listLoad = .loaded
            상태_줄 = String(localized: "map_no_child")
            return
        }
        pendingSync = syncStore.pendingSync(childUid: childUid)
        아이_위치_읽기 = Task { [weak self] in await self?.아이_위치를_읽는다(childUid) }
        placeListener = placesObserve(familyId, childUid, { [weak self] docs, fromCache in
            Task { @MainActor in self?.장소가_바뀌었다(docs, fromCache: fromCache) }
        }, { [weak self] error in
            Task { @MainActor in
                self?.listLoad = .failed
                self?.상태_줄 = String(format: String(localized: "place_error_format"), errorMessage(error))
            }
        })
    }

    func 정리한다() {
        닫힘 = true
        placeListener?.remove()
        placeListener = nil
        syncRetryTask?.cancel()
        syncRetryTask = nil
        아이_위치_읽기?.cancel()
        writeGeneration += 1
    }

    /// 편의를 위한 한 번 읽기다. 실패해도 아무 말도 하지 않는다(:410-444).
    private func 아이_위치를_읽는다(_ childUid: String) async {
        guard let status = try? await statusFetch(familyId, childUid) else { return }
        // await 사이에 정리됐으면 아무것도 바꾸지 않는다(4단계 통합 검토 M1).
        guard !닫힘, !Task.isCancelled else { return }
        guard Self.고른_좌표로_쓸_수_있나(status.lat, status.lng) else { return }
        아이_위치 = 좌표(lat: status.lat, lng: status.lng)
        // 편집을 연 채 기다리고 있었고 부모가 아직 지도를 안 만졌을 때만 옮긴다 — 정해 둔 자리를 뒤늦게
        // 뺏으면 안 된다(:428-436).
        if 편집_중 && !좌표를_골랐나 {
            editorLat = status.lat
            editorLng = status.lng
            좌표를_골랐나 = true
            지도를_편집_좌표로_옮긴다()
        }
    }

    /// 이름순 — 자녀 폰이 지오펜스 20개를 자르는 기준도 이름순이라 두 화면이 같은 순서를 본다(:447-450).
    private func 장소가_바뀌었다(_ docs: [PlaceDoc], fromCache: Bool) {
        places = docs.sorted { a, b in
            a.name == b.name ? KotlinMath.precedes(a.id, b.id) : KotlinMath.precedes(a.name, b.name)
        }
        listLoad = ListLoad.after(fromCache: fromCache)
    }

    var 추가할_수_있나: Bool { places.count < Self.maxPlaces }

    /// 추가 버튼을 잠그면서 이유를 안 적으면 부모는 고장인 줄 안다(:70-71, :798-803).
    var 상한_안내: String? {
        추가할_수_있나 ? nil : String(format: String(localized: "place_limit_notice"), Self.maxPlaces)
    }

    // MARK: - 편집 판 (:457-616)

    func 편집을_연다(_ doc: PlaceDoc?) {
        if doc == nil && !추가할_수_있나 { return }
        editorPlaceId = doc?.id
        editorNewDocId = doc == nil ? newId() : nil
        이름 = doc?.name ?? ""
        editorLat = doc?.lat ?? 아이_위치?.lat ?? 0
        editorLng = doc?.lng ?? 아이_위치?.lng ?? 0
        // (0,0)으로 저장된 옛 문서(안드로이드가 끌지 않고 톡 건드린 뒤 저장했을 수 있다 — 판정 기록 8)는
        // 고른 좌표로 치지 않고 한반도로 연다. 그대로 두면 부모가 안 만진 채 (0,0)을 다시 저장한다.
        좌표를_골랐나 = (doc != nil || 아이_위치 != nil) && Self.고른_좌표로_쓸_수_있나(editorLat, editorLng)
        let 문서_반경 = doc?.radiusMeters ?? 0
        반경 = Self.반경을_눈금에(문서_반경 > 0 ? 문서_반경 : Self.defaultRadiusMeters)
        도착_알림 = doc?.notifyEnter ?? true
        나섬_알림 = doc?.notifyExit ?? true
        저장_중 = false
        편집_줄 = nil
        이름_경고 = false
        상태_줄 = nil
        편집_중 = true
        지도를_편집_좌표로_옮긴다()
    }

    func 취소를_눌렀다() {
        guard !저장_중 else { return }
        writeGeneration += 1
        편집기를_닫는다()
    }

    /// 시스템 뒤로 가기(판정 기록 3). `ScheduleViewModel.뒤로_갔다` 와 같다.
    func 뒤로_갔다() {
        guard 편집_중 else { return }
        if 저장_중 { 떠난_저장_세대 = writeGeneration }
        writeGeneration += 1
        편집기를_닫는다()
    }

    private func 편집기를_닫는다() {
        편집_중 = false
        저장_중 = false
        editorPlaceId = nil
        editorNewDocId = nil
        편집_줄 = nil
    }

    func 이름을_바꾼다(_ text: String) {
        이름 = String(text.prefix(Self.nameMaxLength))
    }

    var 편집기_제목: String {
        editorPlaceId == nil
            ? String(localized: "place_editor_title_new")
            : String(localized: "place_editor_title_edit")
    }

    var 반경_문구: String {
        String(format: String(localized: "place_editor_radius_value"), Int(반경))
    }

    /// 둘 다 끄면 이 장소로는 알림이 안 온다는 안내(:846-850).
    var 알림_없음_안내가_보이나: Bool { !도착_알림 && !나섬_알림 }

    /// 아이 위치를 몰라 넓게 열었다는 안내. 지도를 만지면 사라진다(:852-856).
    var 지도_안내가_보이나: Bool { !좌표를_골랐나 }

    /// 지도에 그릴 반경 원. 편집 중이고 좌표를 골랐을 때만(:560-568).
    var 원: 반경_원? {
        guard 편집_중, 좌표를_골랐나, Self.고른_좌표로_쓸_수_있나(editorLat, editorLng) else { return nil }
        return 반경_원(lat: editorLat, lng: editorLng, radiusMeters: 반경)
    }

    /// 사람이 지도에 손을 댔다(:245-252). 그 순간의 가운데를 곧바로 좌표로 삼는다(판정 기록 8).
    func 지도를_만졌다(centerLat: Double, centerLng: Double) {
        guard 편집_중, !좌표를_골랐나, Self.고른_좌표로_쓸_수_있나(centerLat, centerLng) else { return }
        editorLat = centerLat
        editorLng = centerLng
        좌표를_골랐나 = true
    }

    /// 카메라가 멈췄다. 사람이 옮긴 멈춤만 좌표로 받는다(:274-283, 판정 기록 8).
    func 지도가_멈췄다(centerLat: Double, centerLng: Double, 사람이_옮겼나: Bool) {
        guard 사람이_옮겼나, 편집_중, Self.고른_좌표로_쓸_수_있나(centerLat, centerLng) else { return }
        editorLat = centerLat
        editorLng = centerLng
    }

    /// 편집 좌표로, 모르면 한반도 전체로(:504-536). 카메라는 가운데와 배율만 정하므로 지도 크기와 무관하다 —
    /// 안드로이드가 레이아웃을 기다린 것(:510-512)은 GONE 이던 `MapView` 사정이라 여기에는 없다.
    private func 지도를_편집_좌표로_옮긴다() {
        if 좌표를_골랐나 && !Self.고른_좌표로_쓸_수_있나(editorLat, editorLng) { 좌표를_골랐나 = false }
        카메라_번호 += 1
        카메라_요청 = 좌표를_골랐나
            ? 카메라(lat: editorLat, lng: editorLng, zoom: Self.placeZoom, 번호: 카메라_번호)
            : 카메라(lat: Self.countryLat, lng: Self.countryLng, zoom: Self.countryZoom, 번호: 카메라_번호)
    }

    /// 50m 눈금에 맞추고 범위로 자른다(:538-549). 콘솔에서 손으로 고친 문서도 화면을 못 열게 만들면 안 된다.
    nonisolated static func 반경을_눈금에(_ meters: Double) -> Double {
        let steps = KotlinMath.roundToInt((meters - minRadiusMeters) / radiusStepMeters)
        return min(max(minRadiusMeters + Double(steps) * radiusStepMeters, minRadiusMeters), maxRadiusMeters)
    }

    nonisolated static func 유효한_좌표(_ lat: Double, _ lng: Double) -> Bool {
        lat.isFinite && lng.isFinite && (-90.0...90.0).contains(lat) && (-180.0...180.0).contains(lng)
    }

    /// 장소 좌표로 받아도 되는가. 범위 안이어도 (0,0)은 "한 번도 안 정해짐"(PlaceDoc 기본값)과 구별되지
    /// 않으므로 **절대 좌표로 받지도, 저장하지도 않는다**(주인 판정 — 안드로이드는 (0,0)을 저장할 수 있다).
    nonisolated static func 고른_좌표로_쓸_수_있나(_ lat: Double, _ lng: Double) -> Bool {
        유효한_좌표(lat, lng) && !(lat == 0 && lng == 0)
    }

    /// 관문 둘 — 이름이 비면 막고, 좌표를 한 번도 안 골랐으면 막는다(:588-616).
    func 저장을_눌렀다() async {
        guard !저장_중 else { return }
        let 다듬은_이름 = 이름.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !다듬은_이름.isEmpty else {
            이름_경고 = true
            return
        }
        이름_경고 = false
        guard 좌표를_골랐나, Self.고른_좌표로_쓸_수_있나(editorLat, editorLng) else {
            편집_줄 = String(localized: "place_editor_no_child_location")
            return
        }
        await 장소를_저장한다(이름: 다듬은_이름)
    }

    // MARK: - 쓰기 (:618-721)

    private func 장소를_저장한다(이름 name: String) async {
        guard let childUid else {
            편집_줄 = String(localized: "place_no_family")
            return
        }
        let doc = PlaceDoc(id: editorPlaceId ?? editorNewDocId ?? newId(), name: name,
                           lat: editorLat, lng: editorLng, radiusMeters: 반경,
                           notifyEnter: 도착_알림, notifyExit: 나섬_알림)
        저장_중 = true
        let (fid, save) = (familyId, placeSave)
        await 쓰고_알린다(
            바쁨_문구: String(localized: "place_saving"),
            쓰기: { _ = try await save(fid, childUid, doc) },
            끝나면: { 늦음 in
                편집기를_닫는다()
                상태_줄 = 늦음 ? String(localized: "place_save_slow") : nil
            },
            실패하면: { 이유 in
                저장_중 = false
                편집_줄 = 이유
            }
        )
    }

    func 삭제를_눌렀다(_ doc: PlaceDoc) {
        삭제_확인 = doc
    }

    var 삭제_확인_문구: String {
        guard let 삭제_확인 else { return "" }
        return String(format: String(localized: "place_delete_message"), PlaceText.summary(삭제_확인))
    }

    func 삭제를_확인했다(_ doc: PlaceDoc) async {
        guard let childUid else {
            상태_줄 = String(localized: "place_no_family")
            return
        }
        상태_줄 = String(localized: "place_deleting")
        let (fid, delete, id) = (familyId, placeDelete, doc.id)
        await 쓰고_알린다(
            바쁨_문구: nil,
            쓰기: { try await delete(fid, childUid, id) },
            끝나면: { 늦음 in 상태_줄 = 늦음 ? String(localized: "place_save_slow") : nil },
            실패하면: { 이유 in 상태_줄 = 이유 }
        )
    }

    /// 장소를 쓰는 **유일한 두 갈래**가 지나는 자리(:620-656). 쓰기 뒤에 반드시 `sync_rules` 를 보낸다.
    private func 쓰고_알린다(
        바쁨_문구: String?,
        쓰기: @escaping @Sendable () async throws -> Void,
        끝나면: (_ 늦음: Bool) -> Void,
        실패하면: (_ 이유: String) -> Void
    ) async {
        writeGeneration += 1
        let generation = writeGeneration
        if let 바쁨_문구 { 편집_줄 = 바쁨_문구 }
        깃발을_바꾼다(true)
        do {
            let done: Void? = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep, operation: 쓰기)
            if generation == writeGeneration {
                끝나면(done == nil)
            } else if 목록이_이어받았나(generation), done == nil {
                상태_줄 = String(localized: "place_save_slow")
            }
            await 아이에게_알린다(generation)
        } catch {
            if generation == writeGeneration {
                실패하면(errorMessage(error))
            } else if 목록이_이어받았나(generation) {
                상태_줄 = errorMessage(error)
            }
        }
    }

    // MARK: - 아이 폰에 알리기 (:723-787)

    /// 예약 규칙과 **같은** 명령을 쓴다 — 자녀 쪽이 그 하나로 둘 다 다시 읽는다(:727-730).
    private func 아이에게_알린다(_ generation: Int) async {
        guard let childUid else {
            깃발을_바꾼다(false)
            if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "place_sync_no_child") }
            return
        }
        let (fid, send) = (familyId, commandSend)
        do {
            let commandId = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await send(fid, childUid, CommandType.syncRules, [:])
            }
            guard commandId != nil else {
                if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "place_sync_slow") }
                return
            }
            깃발을_바꾼다(false)
        } catch {
            if 글자를_쓸_수_있나(generation) {
                상태_줄 = String(format: String(localized: "place_sync_failed_format"), errorMessage(error))
            }
        }
    }

    @discardableResult
    func 다시_알린다() -> Task<Void, Never>? {
        guard pendingSync, childUid != nil, syncRetryTask == nil, !닫힘 else { return nil }
        let generation = writeGeneration
        let task = Task { [weak self] in
            await self?.아이에게_알린다(generation)
            self?.syncRetryTask = nil
        }
        syncRetryTask = task
        return task
    }

    private func 깃발을_바꾼다(_ value: Bool) {
        guard let childUid else { return }
        syncStore.setPendingSync(childUid: childUid, value)
        pendingSync = value
    }

    private func 목록이_이어받았나(_ generation: Int) -> Bool {
        떠난_저장_세대 == generation && writeGeneration == generation + 1
    }

    private func 글자를_쓸_수_있나(_ generation: Int) -> Bool {
        generation == writeGeneration || 목록이_이어받았나(generation)
    }
}
