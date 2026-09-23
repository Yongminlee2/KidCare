import FirebaseFirestore
import Foundation
import Observation

/// 예약 탭의 두뇌. 정본은 안드로이드 `guardian/ScheduleFragment.kt` — 줄 번호는 각 주석에 적었다.
///
/// ## 규칙이 바뀌면 반드시 아이 폰에 알린다(:43-65)
/// 저장·켬끔·삭제·기본 모드·공휴일, 다섯 갈래 모두 쓰기 뒤에 `sync_rules` 를 보낸다
/// (`아이에게_알린다`). 못 보냈으면 깃발(`RuleSyncStore`)을 남기고 목록 위에 그렇게 적는다.
///
/// ## 낙관적으로 그리지 않는다(:67-73)
/// 목록은 오직 스냅샷으로만 그린다. 편집기는 쓰기가 끝날 때까지 열려 있고, 실패하면 그 자리에서
/// 이유를 말하며 입력값을 지킨다. 기본 모드·공휴일만 누른 즉시 바뀌어 보이고, 거부되면 되돌린다.
///
/// ## 세대 번호(:99-113)
/// 쓰기는 왕복이 있어 늦게 돌아온다. 쓰기를 시작하거나 편집을 접을 때마다 세대를 올리고, 화면을
/// 만지기 직전에 확인한다. 명령 발행은 세대와 무관하게 늘 한다 — 규칙이 바뀐 사실은 없어지지 않는다.
@Observable
@MainActor
final class ScheduleViewModel {

    // MARK: - 상수 (ScheduleFragment.kt:1179-1190)

    nonisolated static let writeTimeoutMillis: Int64 = 15_000
    /// 새 규칙 기본값: 평일 21:00~07:00 진동 — "밤에는 조용히"에 가장 가깝다(:1180).
    nonisolated static let defaultDays: Set<Int> = [1, 2, 3, 4, 5]
    nonisolated static let defaultStartMinute = 21 * 60
    nonisolated static let defaultEndMinute = 7 * 60

    /// 떠 있는 확인 대화상자. 안드로이드는 `activeDialog` 하나만 둔다(:188-189, :1149-1156).
    enum 확인: Equatable {
        case 하루_종일(message: String)
        case 겹침(message: String)
        case 삭제(ScheduleDoc, message: String)

        var message: String {
            switch self {
            case .하루_종일(let message), .겹침(let message), .삭제(_, let message): return message
            }
        }
    }

    // MARK: - 목록 판

    let familyId: String
    let childUid: String?
    private(set) var rules: [ScheduleDoc] = []
    private(set) var listLoad: ListLoad = .loading
    /// 목록 위 한 줄(`showState`). nil 이면 감춘다.
    private(set) var 상태_줄: String?
    private(set) var pendingSync = false
    private(set) var holidayOff = false
    /// 빈 값은 "그대로 두기".
    private(set) var defaultMode = ""
    /// 설정 문서를 못 읽었다 — 목록 안내를 덮지 않고 스위치만 잠근다(:382-388).
    private(set) var 설정_잠김 = false
    var 확인창: 확인?

    // MARK: - 편집 판 (:142-184) — 편집 중인 값은 전부 여기가 정답이다

    private(set) var 편집_중 = false
    private(set) var editorRuleId: String?
    /// 새 규칙의 문서 ID 는 편집을 열 때 한 번 정한다 — 저장이 두 번 나가도 규칙이 하나다(:151-160).
    private(set) var editorNewDocId: String?
    private(set) var 요일: Set<Int> = ScheduleViewModel.defaultDays
    var 시작분 = ScheduleViewModel.defaultStartMinute
    var 끝분 = ScheduleViewModel.defaultEndMinute
    private(set) var 모드 = RingerMode.vibrate
    private(set) var 저장_중 = false
    private(set) var 편집_줄: String?
    private(set) var 요일_경고 = false

    @ObservationIgnored private var editorEnabled = true
    @ObservationIgnored private var editorPriority = 0
    @ObservationIgnored private var writeGeneration = 0
    /// 뒤로 가기로 떠난 저장의 세대(판정 기록 3).
    @ObservationIgnored private var 떠난_저장_세대: Int?
    /// 이 화면이 방금 부여한 가장 큰 우선순위(:171-181).
    @ObservationIgnored private var lastAssignedPriority = 0
    @ObservationIgnored private var 시작함 = false
    /// `정리한다()` 뒤에는 새 구독도 새 명령도 만들지 않는다(4단계 통합 검토 M1).
    @ObservationIgnored private var 닫힘 = false
    @ObservationIgnored private var scheduleListener: ListenerRegistration?
    @ObservationIgnored private var settingsListener: ListenerRegistration?
    @ObservationIgnored private var syncRetryTask: Task<Void, Never>?

    private let syncStore: RuleSyncStore
    /// 예약 탭은 아이 상태 문서를 안 읽는 **유일한 탭**이라 여기만 기억에 기댄다(판정 기록 3).
    private let platforms: ChildPlatformStore
    private let schedulesObserve: @Sendable (String, String, @escaping ([ScheduleDoc], Bool) -> Void, @escaping (Error) -> Void) -> ListenerRegistration
    private let settingsObserve: @Sendable (String, String, @escaping (RingerSettingsDoc) -> Void, @escaping (Error) -> Void) -> ListenerRegistration
    private let scheduleSave: @Sendable (String, String, ScheduleDoc) async throws -> String
    private let scheduleDelete: @Sendable (String, String, String) async throws -> Void
    private let defaultModeSave: @Sendable (String, String, String) async throws -> Void
    private let holidayOffSave: @Sendable (String, String, Bool) async throws -> Void
    private let commandSend: @Sendable (String, String, String, [String: String]) async throws -> String
    private let writeSleep: @Sendable (Int64) async -> Void
    private let today: () -> DateComponents
    private let holidayNext: (DateComponents) -> (DateComponents, Holiday)?
    private let newId: () -> String

    init(
        familyId: String,
        childUid: String?,
        syncStore: RuleSyncStore = RuleSyncStore(kind: .schedule),
        platforms: ChildPlatformStore = ChildPlatformStore(),
        schedulesObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping ([ScheduleDoc], Bool) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = ScheduleRepository.observeSchedules,
        settingsObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping (RingerSettingsDoc) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = ScheduleRepository.observeRingerSettings,
        scheduleSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ doc: ScheduleDoc) async throws -> String = ScheduleRepository.saveSchedule,
        scheduleDelete: @escaping @Sendable (_ familyId: String, _ childUid: String, _ id: String) async throws -> Void = ScheduleRepository.deleteSchedule,
        defaultModeSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ mode: String) async throws -> Void = ScheduleRepository.setDefaultMode,
        holidayOffSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ enabled: Bool) async throws -> Void = ScheduleRepository.setHolidayOff,
        commandSend: @escaping @Sendable (_ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]) async throws -> String = CommandRepository.send,
        writeSleep: @escaping @Sendable (_ millis: Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        },
        today: @escaping () -> DateComponents = ScheduleViewModel.오늘,
        holidayNext: @escaping (DateComponents) -> (DateComponents, Holiday)? = { HolidayCalendar.next(from: $0) },
        newId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.syncStore = syncStore
        self.platforms = platforms
        self.schedulesObserve = schedulesObserve
        self.settingsObserve = settingsObserve
        self.scheduleSave = scheduleSave
        self.scheduleDelete = scheduleDelete
        self.defaultModeSave = defaultModeSave
        self.holidayOffSave = holidayOffSave
        self.commandSend = commandSend
        self.writeSleep = writeSleep
        self.today = today
        self.holidayNext = holidayNext
        self.newId = newId
    }

    /// 안드로이드 `LocalDate.now()`(:824) — 기기 시간대의 오늘.
    nonisolated static func 오늘() -> DateComponents {
        let ymd = CalendarMath.ymd(of: Date(), zone: .current)
        return DateComponents(year: ymd.year, month: ymd.month, day: ymd.day)
    }

    // MARK: - 구독 (:334-422)

    /// 탭을 처음 보일 때 한 번. 두 번째부터는 아무것도 안 한다(관리 탭 `시작한다` 와 같은 규율).
    func 시작한다() {
        guard !시작함, !닫힘 else { return }
        시작함 = true
        guard let childUid else {
            listLoad = .loaded
            상태_줄 = String(localized: "map_no_child")
            return
        }
        pendingSync = syncStore.pendingSync(childUid: childUid)
        // 구독은 await 없이 곧바로 붙인다 — 붙이기 전에 `정리한다()` 가 끼어들 틈이 없다(4단계 M1 의 경주가 없다).
        // 콜백 넷 모두 첫 줄에서 닫힘을 본다 — `remove()` 직전에 대기열에 오른 콜백이 정리 뒤에 돌 수 있다(5단계 통합 검토 M2).
        scheduleListener = schedulesObserve(familyId, childUid, { [weak self] docs, fromCache in
            Task { @MainActor in self?.규칙이_바뀌었다(docs, fromCache: fromCache) }
        }, { [weak self] error in
            Task { @MainActor in self?.목록을_못_읽었다(error) }
        })
        settingsListener = settingsObserve(familyId, childUid, { [weak self] doc in
            Task { @MainActor in
                guard let self, !self.닫힘 else { return }
                self.holidayOff = doc.holidayOff
                self.defaultMode = doc.defaultMode
            }
        }, { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.닫힘 else { return }
                self.설정_잠김 = true
            }
        })
    }

    /// 보호자 화면이 통째로 사라질 때(`onDestroyView` :1158-1177).
    func 정리한다() {
        닫힘 = true
        scheduleListener?.remove()
        scheduleListener = nil
        settingsListener?.remove()
        settingsListener = nil
        syncRetryTask?.cancel()
        syncRetryTask = nil
        writeGeneration += 1
    }

    private func 규칙이_바뀌었다(_ docs: [ScheduleDoc], fromCache: Bool) {
        guard !닫힘 else { return }
        rules = docs.sorted(by: Self.목록_순서)
        listLoad = ListLoad.after(fromCache: fromCache)
    }

    /// 이른 시각이 위로. priority 는 화면에 안 쓰므로 정렬에도 안 쓴다(:411-416). ID 는 코틀린
    /// `String.compareTo` 와 같은 UTF-16 순서(판정 기록 10).
    nonisolated static func 목록_순서(_ a: ScheduleDoc, _ b: ScheduleDoc) -> Bool {
        if a.startMinute != b.startMinute { return a.startMinute < b.startMinute }
        if a.endMinute != b.endMinute { return a.endMinute < b.endMinute }
        return KotlinMath.precedes(a.id, b.id)
    }

    private func 목록을_못_읽었다(_ error: Error) {
        guard !닫힘 else { return }
        listLoad = .failed
        상태_줄 = String(format: String(localized: "schedule_error_format"), errorMessage(error))
    }

    // MARK: - 편집 판 (:424-561)

    func 편집을_연다(_ doc: ScheduleDoc?) {
        editorRuleId = doc?.id
        editorNewDocId = doc == nil ? newId() : nil
        요일 = doc.map { d in Set(d.days.filter { (1...7).contains($0) }) } ?? Self.defaultDays
        시작분 = doc?.startMinute ?? Self.defaultStartMinute
        끝분 = doc?.endMinute ?? Self.defaultEndMinute
        모드 = doc?.mode ?? RingerMode.vibrate
        editorEnabled = doc?.enabled ?? true
        editorPriority = doc?.priority ?? 0
        저장_중 = false
        편집_줄 = nil
        요일_경고 = false
        상태_줄 = nil
        편집_중 = true
    }

    /// 편집 판의 '취소' 버튼. 쓰기가 도는 동안은 막는다(:443-460).
    func 취소를_눌렀다() {
        guard !저장_중 else { return }
        writeGeneration += 1
        편집기를_닫는다()
    }

    /// 시스템 뒤로 버튼·밀어서 뒤로 가기. 막을 수 없으므로 막지 않는다. 도는 중이던 쓰기의 결과는 목록 줄이
    /// 이어받고, 새로 연 편집기는 절대 만지지 않는다(판정 기록 3). 코드가 `편집_중` 을 먼저 내린 뒤
    /// SwiftUI 가 바인딩에 false 를 한 번 더 쓰는 경우에도 아무 일이 없게 첫 줄에서 거른다.
    func 뒤로_갔다() {
        guard 편집_중 else { return }
        if 저장_중 { 떠난_저장_세대 = writeGeneration }
        writeGeneration += 1
        편집기를_닫는다()
    }

    private func 편집기를_닫는다() {
        편집_중 = false
        저장_중 = false
        editorRuleId = nil
        editorNewDocId = nil
        편집_줄 = nil
    }

    func 요일을_누른다(_ day: Int) {
        if 요일.contains(day) { 요일.remove(day) } else { 요일.insert(day) }
        // 하나라도 고르는 순간 경고를 거둔다 — 고쳤는데 빨간 글씨가 남으면 아직 틀린 줄 안다(:251-253).
        if !요일.isEmpty { 요일_경고 = false }
    }

    func 모드를_고른다(_ mode: String) {
        모드 = mode
    }

    var 편집기_제목: String {
        editorRuleId == nil
            ? String(localized: "schedule_editor_title_new")
            : String(localized: "schedule_editor_title_edit")
    }

    /// 시각 두 칸만으로는 알 수 없는 "다음 날까지"·"하루 종일"을 미리 말한다(:1064-1070).
    var 범위_안내: String? {
        끝분 <= 시작분 ? ScheduleText.rangeText(start: 시작분, end: 끝분) : nil
    }

    /// 저장 버튼. 요일 → 하루 종일 → 겹침, 세 관문을 순서대로 지난다(:471-501).
    func 저장을_눌렀다() async {
        guard !저장_중 else { return }
        guard !요일.isEmpty else {
            요일_경고 = true
            return
        }
        요일_경고 = false
        if 시작분 == 끝분 {
            확인창 = .하루_종일(message: String(format: String(localized: "schedule_allday_message"),
                                              ScheduleText.timeText(시작분), ScheduleText.modeText(모드)))
            return
        }
        await 겹침을_확인하고_저장한다()
    }

    func 하루_종일을_확인했다() async {
        await 겹침을_확인하고_저장한다()
    }

    func 겹쳐도_저장한다() async {
        await 규칙을_저장한다()
    }

    /// 후보는 늘 켜진 것으로 보고, 비교 대상 중 꺼진 것은 뺀다 — `ScheduleResolver.overlaps` 주석(:520-561).
    private func 겹침을_확인하고_저장한다() async {
        let candidate = ScheduleRule(id: editorRuleId ?? "", days: 요일, startMinute: 시작분, endMinute: 끝분,
                                     mode: 모드, enabled: editorEnabled, priority: editorPriority)
        let hits = ScheduleResolver.overlaps(rules: rules.map(\.asRule), candidate: candidate)
        guard let first = hits.first, let firstDoc = rules.first(where: { $0.id == first.id }) else {
            await 규칙을_저장한다()
            return
        }
        let name = ScheduleText.summary(firstDoc)
        let message = hits.count == 1
            ? String(format: String(localized: "schedule_overlap_message"), name)
            : String(format: String(localized: "schedule_overlap_message_more"), name, hits.count - 1)
        확인창 = .겹침(message: message)
    }

    // MARK: - 쓰기

    /// 만들기와 고치기가 같은 경로다. 쓰기가 끝날 때까지 편집기를 닫지 않는다(:565-629).
    private func 규칙을_저장한다() async {
        guard let childUid else {
            편집_줄 = String(localized: "schedule_no_family")
            return
        }
        // 새 규칙은 지금 있는 것보다 하나 크게, 고치기는 원래 값 그대로(:582-588).
        let priority = editorRuleId == nil ? 다음_우선순위() : editorPriority
        if editorRuleId == nil { lastAssignedPriority = priority }
        let doc = ScheduleDoc(id: editorRuleId ?? editorNewDocId ?? newId(), days: 요일.sorted(),
                              startMinute: 시작분, endMinute: 끝분, mode: 모드,
                              enabled: editorEnabled, priority: priority)
        writeGeneration += 1
        let generation = writeGeneration
        저장_중 = true
        편집_줄 = String(localized: "schedule_saving")
        // 쓰기보다 **먼저** 세운다 — 반대 순서의 사고(쓰기는 됐는데 깃발이 없음)는 조용한 고장이다(:603-606).
        깃발을_바꾼다(true)

        let (fid, save) = (familyId, scheduleSave)
        do {
            let savedId = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await save(fid, childUid, doc)
            }
            // 기다리는 동안 정리됐으면 사라진 화면을 만지지도 명령을 보내지도 않는다 — 깃발은 남아 다음 세션이 보낸다(4단계 통합 검토 M1).
            guard !닫힘 else { return }
            if generation == writeGeneration {
                편집기를_닫는다()
                상태_줄 = savedId == nil ? String(localized: "schedule_save_slow") : nil
            } else if 목록이_이어받았나(generation), savedId == nil {
                상태_줄 = String(localized: "schedule_save_slow")
            }
            await 아이에게_알린다(generation)
        } catch {
            guard !닫힘 else { return }
            if generation == writeGeneration {
                저장_중 = false
                편집_줄 = errorMessage(error)
            } else if 목록이_이어받았나(generation) {
                상태_줄 = errorMessage(error)
            }
        }
    }

    /// 켬/끔. 보이는 값은 스냅샷이 정하므로 직접 되돌리지 않고, 왜 돌아갔는지만 말한다(:631-666).
    func 켬끔을_바꾼다(_ doc: ScheduleDoc, enabled: Bool) async {
        guard let childUid else {
            상태_줄 = String(localized: "schedule_no_family")
            return
        }
        writeGeneration += 1
        let generation = writeGeneration
        상태_줄 = nil
        깃발을_바꾼다(true)
        var copy = doc
        copy.enabled = enabled
        let (fid, save, changed) = (familyId, scheduleSave, copy)
        do {
            let savedId = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await save(fid, childUid, changed)
            }
            // 기다리는 동안 정리됐으면 사라진 화면을 만지지도 명령을 보내지도 않는다 — 깃발은 남아 다음 세션이 보낸다(4단계 통합 검토 M1).
            guard !닫힘 else { return }
            if savedId == nil, generation == writeGeneration {
                상태_줄 = String(localized: "schedule_save_slow")
            }
            await 아이에게_알린다(generation)
        } catch {
            guard !닫힘 else { return }
            if generation == writeGeneration { 상태_줄 = errorMessage(error) }
        }
    }

    func 삭제를_눌렀다(_ doc: ScheduleDoc) {
        확인창 = .삭제(doc, message: String(format: String(localized: "schedule_delete_message"), ScheduleText.summary(doc)))
    }

    /// :863-892.
    func 삭제를_확인했다(_ doc: ScheduleDoc) async {
        guard let childUid else {
            상태_줄 = String(localized: "schedule_no_family")
            return
        }
        writeGeneration += 1
        let generation = writeGeneration
        상태_줄 = String(localized: "schedule_deleting")
        깃발을_바꾼다(true)
        let (fid, delete, id) = (familyId, scheduleDelete, doc.id)
        do {
            let done: Void? = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await delete(fid, childUid, id)
            }
            // 기다리는 동안 정리됐으면 사라진 화면을 만지지도 명령을 보내지도 않는다 — 깃발은 남아 다음 세션이 보낸다(4단계 통합 검토 M1).
            guard !닫힘 else { return }
            if generation == writeGeneration {
                상태_줄 = done == nil ? String(localized: "schedule_save_slow") : nil
            }
            await 아이에게_알린다(generation)
        } catch {
            guard !닫힘 else { return }
            if generation == writeGeneration { 상태_줄 = errorMessage(error) }
        }
    }

    /// 예약이 없는 시간의 기본 모드. 거부되면 되돌린다(:676-729).
    func 기본_모드를_고른다(_ mode: String) async {
        guard let childUid else {
            상태_줄 = String(localized: "schedule_no_family")
            return
        }
        let previous = defaultMode
        writeGeneration += 1
        let generation = writeGeneration
        defaultMode = mode
        상태_줄 = nil
        깃발을_바꾼다(true)
        let (fid, save) = (familyId, defaultModeSave)
        do {
            let done: Void? = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await save(fid, childUid, mode)
            }
            // 기다리는 동안 정리됐으면 사라진 화면을 만지지도 명령을 보내지도 않는다 — 깃발은 남아 다음 세션이 보낸다(4단계 통합 검토 M1).
            guard !닫힘 else { return }
            if generation == writeGeneration {
                if done == nil {
                    상태_줄 = String(localized: "schedule_save_slow")
                } else if mode.isEmpty {
                    상태_줄 = String(localized: "schedule_default_cleared")
                } else {
                    상태_줄 = String(format: String(localized: "schedule_default_saved"), ScheduleText.modeText(mode))
                }
            }
            await 아이에게_알린다(generation)
        } catch {
            guard !닫힘 else { return }
            guard generation == writeGeneration else { return }
            defaultMode = previous
            상태_줄 = errorMessage(error)
        }
    }

    /// 공휴일 스위치. 거부되면 되돌린다(:760-808).
    func 공휴일을_바꾼다(_ enabled: Bool) async {
        guard let childUid else {
            상태_줄 = String(localized: "schedule_no_family")
            return
        }
        writeGeneration += 1
        let generation = writeGeneration
        holidayOff = enabled
        상태_줄 = nil
        깃발을_바꾼다(true)
        let (fid, save) = (familyId, holidayOffSave)
        do {
            let done: Void? = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await save(fid, childUid, enabled)
            }
            // 기다리는 동안 정리됐으면 사라진 화면을 만지지도 명령을 보내지도 않는다 — 깃발은 남아 다음 세션이 보낸다(4단계 통합 검토 M1).
            guard !닫힘 else { return }
            if generation == writeGeneration {
                if done == nil {
                    상태_줄 = String(localized: "schedule_save_slow")
                } else if enabled {
                    상태_줄 = String(localized: "schedule_holiday_saved")
                } else {
                    상태_줄 = String(localized: "schedule_holiday_cleared")
                }
            }
            await 아이에게_알린다(generation)
        } catch {
            guard !닫힘 else { return }
            guard generation == writeGeneration else { return }
            holidayOff = !enabled
            상태_줄 = errorMessage(error)
        }
    }

    /// 켜져 있을 때만 다음 쉬는 날을 적는다 — 음력 환산이 틀렸는지 부모가 달력과 맞춰볼 유일한 검산이다(:810-835).
    var 공휴일_안내: String {
        guard holidayOff else { return String(localized: "schedule_holiday_subtitle") }
        guard let next = holidayNext(today()) else { return String(localized: "schedule_holiday_unknown") }
        let 날짜 = String(format: String(localized: "schedule_holiday_date"), next.0.month ?? 0, next.0.day ?? 0)
        return String(format: String(localized: "schedule_holiday_next"), 날짜, ScheduleText.holidayName(next.1))
    }

    // MARK: - 아이 폰에 알리기 (:894-969)

    /// 예약 탭은 아이 상태 문서를 안 읽는 **유일한 탭**이다. 그래서 여기만 기억에 기댄다
    /// (판정 기록 3). 기억이 없으면 `.unknown` 이고 `.unknown` 은 아무것도 안 잠근다 —
    /// 못 맞혔을 때의 대가가 "지금 동작 그대로"라서 되는 설계다.
    var 플랫폼: ChildPlatform {
        guard let childUid else { return .unknown }
        return platforms.platform(childUid: childUid)
    }

    /// 탭 맨 위의 한 줄을 띄울까. **규칙 저장·수정·삭제·기본 모드·공휴일은 하나도 안 막는다**
    /// (설계서 §10.2) — 그 아이가 나중에 안드로이드 폰으로 바뀌면 그대로 동작해야 한다.
    /// 막는 것은 `sync_rules` 명령 하나다.
    var 아이폰이라_규칙이_안_걸린다: Bool { 플랫폼.못_한다고_말할까 }

    /// 세대는 **글자를 쓸지만** 가른다. 명령은 늘 보낸다(:894-901).
    ///
    /// 닫힘 확인은 겹쳐 둔다(5단계 통합 검토 M1):
    /// - 다섯 쓰기 갈래의 await 뒤 guard 와 여기 입구 guard 는 **서로를 가린다.** 정리가 세대를 올려 글자 쓰기는
    ///   이미 막히므로 둘 중 하나만 지우면 동작이 같고, 어느 테스트도 빨개지지 않는다. 둘 다 지우면
    ///   `정리_뒤_늦은_저장`·`정리_뒤_늦은_켬끔`·`정리_뒤_늦은_삭제` 가 빨개진다.
    /// - 명령 await 뒤 guard 는 따로 드러난다(`정리_뒤_늦은_알림` — 깃발이 남는가).
    /// 겹친 guard 를 "중복"으로 지우지 않는다. 한 겹이 사라지면 남은 한 겹이 유일한 방어가 된다.
    private func 아이에게_알린다(_ generation: Int) async {
        guard !닫힘 else { return }
        guard let childUid else {
            // 보낼 곳이 없다. 아이 폰이 연결되면 저절로 규칙을 읽으므로 깃발을 내린다(:905-912).
            깃발을_바꾼다(false)
            if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "schedule_sync_no_child") }
            return
        }
        // 아이폰 아이는 `commands/` 를 구독하지 않는다(설계서 §1). 여기서 보내면 그 문서는 쓰기
        // 하나를 태우고 아무도 안 읽는 자리에 영원히 남고, 깃발이 영영 안 내려가 '아이 폰에
        // 알리기' 바가 "아직 못 알렸어요"를 계속 띄운다 — 부모는 그것을 **일시적인 실패**로 읽고
        // 계속 다시 누른다. 알릴 것이 없다는 사실은 버튼이 아니라 탭 맨 위의 문장이 말한다
        // (판정 기록 5).
        //
        // **규칙 자체는 이미 저장됐고 그대로 둔다** — 그 아이가 나중에 안드로이드 폰으로 바뀌면
        // 그 폰이 읽어 간다(설계서 §10.2).
        //
        // `상태_줄` 은 **안 건드린다.** 방금 저장에 성공한 일을 "못 알렸어요"류로 덮으면 된 일이
        // 실패처럼 읽힌다. `깃발을_바꾼다(false)` 는 옛 버전이 올려 둔 깃발까지 여기서 치운다.
        guard 플랫폼.명령을_받을_수_있나 else {
            깃발을_바꾼다(false)
            return
        }
        let (fid, send) = (familyId, commandSend)
        do {
            let commandId = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await send(fid, childUid, CommandType.syncRules, [:])
            }
            // 기다리는 동안 정리됐으면 사라진 화면을 만지지도 명령을 보내지도 않는다 — 깃발은 남아 다음 세션이 보낸다(4단계 통합 검토 M1).
            guard !닫힘 else { return }
            guard commandId != nil else {
                // 오프라인이면 명령도 로컬 큐에서 연결을 기다린다. 그래도 깃발은 내리지 않는다(:917-923).
                if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "schedule_sync_slow") }
                return
            }
            깃발을_바꾼다(false)
        } catch {
            guard !닫힘 else { return }
            if 글자를_쓸_수_있나(generation) {
                상태_줄 = String(format: String(localized: "schedule_sync_failed_format"), errorMessage(error))
            }
        }
    }

    /// 못 보낸 알림을 한 번 더 보낸다. 부르는 곳은 탭을 보일 때, 앱으로 돌아왔을 때, '다시 알리기'다
    /// (판정 기록 7). 테스트가 기다릴 수 있게 작업을 돌려준다.
    @discardableResult
    func 다시_알린다() -> Task<Void, Never>? {
        // 아이 uid 를 모르면 "연결되면 저절로"로 깃발을 내려버리므로 부르지 않는다(:951-955).
        guard pendingSync, childUid != nil, syncRetryTask == nil, !닫힘 else { return nil }
        let generation = writeGeneration
        let task = Task { [weak self] in
            await self?.아이에게_알린다(generation)
            self?.syncRetryTask = nil
        }
        syncRetryTask = task
        return task
    }

    // MARK: - 도우미

    private func 깃발을_바꾼다(_ value: Bool) {
        guard let childUid else { return }
        // 아이폰 아이에게는 깃발을 **애초에 안 올린다**(판정 기록 5). 다섯 쓰기 갈래가 쓰기
        // **전에** 여기로 올리는데, 그중 쓰기가 실패한 갈래는 `아이에게_알린다` 까지 가지도
        // 못한다(catch 로 빠진다) — 입구 guard 하나만으로는 그 갈래에서 깃발이 남는다.
        // **내리는 것은 언제나 한다** — 옛 버전이 올려 둔 깃발을 치워야 하기 때문이다.
        if value, !플랫폼.명령을_받을_수_있나 { return }
        syncStore.setPendingSync(childUid: childUid, value)
        pendingSync = value
    }

    private func 다음_우선순위() -> Int {
        max(rules.map(\.priority).max() ?? 0, lastAssignedPriority) + 1
    }

    /// 뒤로 가기로 떠난 저장이고, 그 뒤로 다른 쓰기가 시작되지 않았는가(판정 기록 3).
    private func 목록이_이어받았나(_ generation: Int) -> Bool {
        떠난_저장_세대 == generation && writeGeneration == generation + 1
    }

    private func 글자를_쓸_수_있나(_ generation: Int) -> Bool {
        generation == writeGeneration || 목록이_이어받았나(generation)
    }
}
