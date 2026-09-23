import FirebaseFirestore
import Foundation
import Observation
import os

/// 관리 탭 맨 아래 명령 상태 한 줄. 정본은 `ControlFragment.CommandUi`(:944-975)와
/// `renderCommand`(:977-991) — 스피너와 문구를 이 한 값에서만 만든다. 실패 문구 아래에서
/// 스피너가 계속 도는 화면(3단계 실기기 결함)을 구조적으로 막는다(:942-943).
enum ControlCommandUi: Equatable {
    case idle
    case sending
    case done
    /// 메시지가 아이 폰에 닿았지만 아직 '확인했어요'가 안 눌렸다. 기다리는 것이 네트워크가
    /// 아니라 **사람**이라 스피너를 안 돌린다(:949-956).
    case messageUnread
    /// 아이가 '확인했어요'를 눌렀다.
    case messageRead
    /// 이 폰의 큐에만 들어갔다. **실패가 아니다** — 연결되면 그대로 나가 아이 폰이 그때
    /// 실행한다. 그래서 오히려 말해줘야 한다(:961-972).
    case queued
    case failed(String)

    var isSpinning: Bool { self == .sending }

    var text: String? {
        switch self {
        case .idle: return nil
        case .sending: return String(localized: "control_command_sending")
        case .done: return String(localized: "control_command_done")
        case .messageUnread: return String(localized: "control_message_unread")
        case .messageRead: return String(localized: "control_message_read")
        case .queued: return String(localized: "control_command_queued")
        case .failed(let message): return message
        }
    }
}

/// 관리 탭. 부모가 버튼을 누르면 아이 폰이 바뀐다. 정본은 안드로이드 `guardian/ControlFragment.kt`.
///
/// 이 화면의 원칙은 **"정직한 표시"**다(:40-48). 명령을 보낸 뒤 그 문서 하나를 따라가며
/// `전달 중…` → `완료` 를 보여주고, 60초 안에 대답이 없으면 "애기폰이 응답하지 않아요"와
/// 마지막 신호 시각을 함께 띄운다. **"완료"가 뜻하는 것은 아이 폰이 done 이라고 적었다는
/// 것 하나뿐이다** — 실제로 실행했는지는 규칙으로 막을 수 없다(firestore.rules commands
/// update 주석). 그 이상을 뜻하는 문구를 쓰지 않는다.
///
/// 버튼은 일부러 잠그지 않는다(:478-482). 응답이 60초까지 걸리는데 그동안 버튼이 죽어
/// 있으면 고장으로 보인다. 대신 **세대 번호**로 화면의 주인을 하나로 못박는다(:98-118).
///
/// Firestore 쪽은 전부 주입받는다 — `MapViewModel` 과 같은 이유로, 세대·제한시간 순서를
/// 테스트가 결정적으로 재현하려면 진짜 왕복이 아니라 완료 시점을 정할 수 있는 자리가 필요하다.
@Observable
@MainActor
final class ControlViewModel {

    // MARK: - 상수 (ControlFragment.kt:1118-1153, fragment_control.xml)

    /// 아이 폰이 대답하기까지(:1132). 지도 탭과 같은 값이어야 한다(MapTimelineFragment.kt:1315-1316).
    nonisolated static let commandTimeoutMillis: Int64 = 60_000
    /// 이 쓰기가 서버에 닿기까지(:1134-1141). 오프라인이면 서버 확인이 영영 안 온다.
    nonisolated static let sendTimeoutMillis: Int64 = 15_000
    /// 자녀 폰 `FindPhoneController` 의 5분 자동 정지와 같은 값(:1143-1144).
    nonisolated static let findAutoStopMillis: Int64 = 5 * 60 * 1000
    /// 아침 7시 — "아침에 깨워줘"에 가장 가깝다(:1148-1149).
    nonisolated static let defaultAlarmMinute = 7 * 60
    /// `fragment_control.xml:359,366` — 넘치면 입력이 멈추고 카운터가 이유를 보여준다.
    nonisolated static let messageMaxLength = 100
    /// `fragment_control.xml:447` — 아이 폰 알림 제목 한 줄.
    nonisolated static let alarmLabelMaxLength = 20

    let familyId: String
    let childUid: String?

    // MARK: - 화면이 읽는 상태

    private(set) var commandUi: ControlCommandUi = .idle
    /// 아이 폰이 아직 안 붙었거나 설정을 못 읽을 때만 보이는 한 줄(`child_state`, xml :24-32).
    private(set) var 아이_안내: String?
    /// 마지막으로 읽은 아이 상태 문서. 화면을 열 때 한 번, 소리 조회 done 뒤 한 번 읽는다(:313-321).
    private(set) var 상태: ChildStatusDoc?
    /// `renderRingerState(loading = true)`(:243, :328) 자리. 처음엔 읽는 중이다.
    private(set) var 상태_읽는_중 = true
    /// 확인된 소리 모드. status 에서 읽었거나 이 화면에서 완료 응답을 받은 값(:131-133).
    private(set) var currentRingerMode: String?
    private(set) var ringerAppliedInSession = false
    /// 자녀 폰에 실제 소리 상태를 묻고 응답을 기다리는 동안 true(:135-136).
    private(set) var ringerQueryInFlight = false
    private(set) var lockEnabled = false
    /// 이 화면에서 폰찾기를 시작시킨 시각(부모 폰 시계). 0 이면 우리가 울린 적 없다(:178-182).
    private(set) var findStartedAt: Int64 = 0
    private(set) var 알람_기억: AlarmMemo?

    var alarmMinute = ControlViewModel.defaultAlarmMinute
    var 메시지 = ""
    var 알람_이름 = ""

    /// 대답을 적은 직후 부른다 — `GuardianRootView` 가 배너 판정으로 잇는다(:746-750).
    var 대답이_기록되면: (@MainActor () -> Void)?

    // MARK: - 주입

    private let requestLog: RequestLog
    private let alarmMemoStore: AlarmMemoStore
    /// 다섯 탭이 같이 보는 기억. 이 탭은 상태 문서를 읽으므로 **쓰는 쪽**이다(판정 기록 3).
    private let platforms: ChildPlatformStore
    private let commandSend: @Sendable (_ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]) async throws -> String
    private let commandObserve: @Sendable (
        _ familyId: String, _ childUid: String, _ commandId: String,
        _ onChange: @escaping (CommandDoc) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
    private let statusFetch: @Sendable (_ familyId: String, _ childUid: String) async throws -> ChildStatusDoc?
    private let settingsObserve: @Sendable (
        _ familyId: String, _ childUid: String,
        _ onChange: @escaping (RingerSettingsDoc) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
    private let lockSave: @Sendable (_ familyId: String, _ childUid: String, _ enabled: Bool) async throws -> Void
    private let serverNow: @Sendable (_ familyId: String) async throws -> Int64
    private let deviceNow: @Sendable () -> Int64
    private let commandSleep: @Sendable (_ millis: Int64) async -> Void

    // MARK: - 내부 상태

    /// 지금 화면이 따라가는 명령의 세대(:98-118). 발행 **전에** 붙잡고, 왕복 뒤·콜백 안·
    /// 제한시간 안에서 아직 최신인지 확인한다.
    private var commandGeneration = 0
    /// 따라가는 명령의 종류. `done` 하나가 명령마다 다른 일을 해야 해서 들고 있다(:120-129).
    private var trackingType: String?
    private var trackingRingerMode: String?
    /// 60초가 지나 "응답 없음"을 이미 띄웠는가. 늦은 pending/delivered 가 실패 문구를
    /// "전달 중…"으로 되돌리지 못하게 한다(:94-96).
    private var timedOut = false
    private var commandListener: ListenerRegistration?
    private var timeoutTask: Task<Void, Never>?
    private var settingsListener: ListenerRegistration?
    /// 부모가 방금 스위치로 만든 값. 아직 서버 스냅샷으로 되돌아오지 않았다(:170-176).
    private var pendingLockValue: Bool?
    private var findResetTask: Task<Void, Never>?
    /// 안드로이드 `statusJob?.cancel()`(:323)·`lockSaveJob?.cancel()`(:846) 대신 — Firestore
    /// 읽기·쓰기는 취소되지 않으므로 늦은 결과를 세대로 버린다.
    private var statusGeneration = 0
    private var lockGeneration = 0
    private var 시작_작업: Task<Void, Never>?
    /// `정리한다()` 가 불렸다. 시작 작업은 await 마다 이 값을 다시 본다 — 취소만으로는
    /// 모자라다(Firestore 읽기는 취소를 모른다). 정리 뒤에 리스너를 붙이거나 자녀 폰에
    /// `query_ringer` 를 새로 쓰면 아무도 떼지 못한다(통합 검토 M1).
    private var 닫혔다 = false

    /// 메시지만 `delivered` 의 뜻이 다르다(:138-156). 필드를 따로 두지 않고 종류에서 파생한다.
    private var trackingMessage: Bool { trackingType == CommandType.message }

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "ControlViewModel")

    init(
        familyId: String,
        childUid: String?,
        requestLog: RequestLog = RequestLog(),
        alarmMemoStore: AlarmMemoStore = AlarmMemoStore(),
        platforms: ChildPlatformStore = ChildPlatformStore(),
        commandSend: @escaping @Sendable (_ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]) async throws -> String = CommandRepository.send,
        commandObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String, _ commandId: String,
            _ onChange: @escaping (CommandDoc) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = CommandRepository.observeOne,
        statusFetch: @escaping @Sendable (_ familyId: String, _ childUid: String) async throws -> ChildStatusDoc? = FamilyRepository.fetchChildStatus,
        settingsObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping (RingerSettingsDoc) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = ScheduleRepository.observeRingerSettings,
        lockSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ enabled: Bool) async throws -> Void = ScheduleRepository.setRingerLock,
        serverNow: @escaping @Sendable (_ familyId: String) async throws -> Int64 = { familyId in
            try await FamilyRepository.serverNow(familyId: familyId, uid: AuthGateway.currentUid())
        },
        deviceNow: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        commandSleep: @escaping @Sendable (_ millis: Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        }
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.requestLog = requestLog
        self.alarmMemoStore = alarmMemoStore
        self.platforms = platforms
        self.commandSend = commandSend
        self.commandObserve = commandObserve
        self.statusFetch = statusFetch
        self.settingsObserve = settingsObserve
        self.lockSave = lockSave
        self.serverNow = serverNow
        self.deviceNow = deviceNow
        self.commandSleep = commandSleep
        알람_기억 = childUid.flatMap { alarmMemoStore.memo(childUid: $0) }
    }

    // MARK: - 화면이 그리는 값

    /// 고른 아이의 폰 종류. 상태 문서를 이미 읽었으면 그 값이고, 아직이면 기억해 둔 값이다.
    /// 둘 다 없으면 `.unknown` — **아무것도 안 잠근다**(판정 기록 2).
    var 플랫폼: ChildPlatform {
        if let 상태 { return ChildPlatform.of(platform: 상태.platform) }
        guard let childUid else { return .unknown }
        return platforms.platform(childUid: childUid)
    }

    /// 설계서 §10.2. 아이폰 아이는 `commands/` 를 구독하지 않으므로 이 탭의 모든 버튼이
    /// "영원히 전달 중"이 된다.
    var 명령을_보낼_수_있나: Bool { 플랫폼.명령을_받을_수_있나 }

    /// `.unknown` 에서는 **안 적는다** — 모르는 아이에게 "이 아이는 아이폰이에요"라고 말하는
    /// 것은 버튼을 끄는 것보다 더 나쁜 거짓말이다(판정 기록 2).
    var 아이폰이라_못_한다고_말할까: Bool { 플랫폼.못_한다고_말할까 }

    /// 아이 폰이 없으면 보낼 곳이 없다(:1074-1092). 아이폰 아이면 보낼 곳이 **듣지를 않는다**
    /// (설계서 §10.2). 4단계부터는 입력칸·시각 고르기도 이 값으로 같이 막는다 — 보내기만
    /// 끄고 입력칸을 열어 두면 부모가 한 글자씩 써 놓고 못 보내게 된다(판정 기록 7).
    var 버튼_활성화: Bool { childUid != nil && 명령을_보낼_수_있나 }

    /// '새로 확인' 버튼(:1027, :1080). 아이폰 아이에게는 카드째 숨기지만(판정 기록 7), 값은
    /// 여기서도 막아 둔다 — 화면을 우회하는 길이 있어도 명령이 안 나가야 한다.
    var 새로_확인_활성화: Bool { childUid != nil && 명령을_보낼_수_있나 && !상태_읽는_중 && !ringerQueryInFlight }

    /// 소리 잠금 스위치를 보일까. **아이 폰은 `lockEnabled` 를 읽지 않는다**
    /// (`grep -rn lockEnabled ios/KidCare/Child` → 0건). 켜도 아무 일이 안 일어나는 스위치라,
    /// 값이 없는 칸과 답이 없는 질문을 흐리게 남겨 두느니 지운다 — 소리 상태 카드를 숨긴 것과
    /// **같은 이유, 같은 판단**이다(판정 기록 7, 통합 검토 M1). 흐리게 두면 부모는 "지금은 안
    /// 되지만 언젠가 되는 것"으로 읽는다.
    var 잠금_스위치를_보일까: Bool { 플랫폼 != .iOS }

    /// 인터넷 카드 아래 한 줄. **카드 자체는 안 잠근다** — 아이폰 아이도 `network` 를 실제로
    /// 올린다(통합 검토 L3). 다만 "끄고 켜는 것은 **안드로이드가** 허용하지 않아요"는 아이폰
    /// 아이를 고른 부모에게 틀린 문장이다. 안드로이드 아이가 읽는 문장은 **한 글자도 안 바꾼다**
    /// (주인 판정) — 그래서 문구를 고치지 않고 아이폰 전용 키를 하나 더 둔다.
    var 인터넷_설명_키: String.LocalizationValue {
        플랫폼 == .iOS ? "ios_child_network_readonly" : "control_network_readonly"
    }

    /// 아이 폰이 지금 울리고 있는지는 **알 방법이 없다** — 우리가 울린 지 5분이 안 됐으면
    /// 울린다고 믿는다(:875-899).
    var 울리는_중이라고_믿는가: Bool {
        findStartedAt != 0 && deviceNow() - findStartedAt < Self.findAutoStopMillis
    }

    func 선택된_모드인가(_ mode: String) -> Bool { currentRingerMode == mode }

    /// 소리 상태 줄(:994-1019). 방해 금지가 켜져 있으면 안드로이드가 모드를 무조건 '무음'으로
    /// 보고하므로, 그 값을 그대로 적지 않고 무슨 상태인지 있는 그대로 말한다.
    var 소리_상태_문구: String {
        if 상태_읽는_중 || ringerQueryInFlight { return String(localized: "control_ringer_status_loading") }
        if Dnd.isOn(상태?.dnd) {
            return String(format: String(localized: "control_ringer_status_format"), String(localized: "control_ringer_dnd"))
        }
        guard let 이름 = Self.소리_모드_이름(currentRingerMode) else {
            return String(localized: "control_ringer_status_unknown")
        }
        return ringerAppliedInSession
            ? String(format: String(localized: "control_ringer_status_applied"), 이름)
            : String(format: String(localized: "control_ringer_status_format"), 이름)
    }

    /// 안드로이드 `ic_volume_up`/`ic_vibration`/`ic_volume_off`(:1020-1026) 에 가장 가까운 그림.
    var 소리_상태_아이콘: String {
        switch currentRingerMode {
        case RingerMode.vibrate: return "iphone.radiowaves.left.and.right"
        case RingerMode.silent: return "speaker.slash.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    /// 방해 금지 안내 줄(:1003).
    var 방해금지_안내를_보이는가: Bool { Dnd.isOn(상태?.dnd) && !(상태_읽는_중 || ringerQueryInFlight) }

    /// 인터넷 상태 첫 줄(:797-805). null 은 옛 문서·아직 안 올림, 빈 값은 못 읽음 — 둘 다 "모른다".
    var 인터넷_문구: String {
        switch 상태?.network {
        case NetworkKind.wifi: return String(localized: "control_network_wifi")
        case NetworkKind.cell: return String(localized: "control_network_cell")
        case NetworkKind.none: return String(localized: "control_network_none")
        default: return String(localized: "control_network_unknown")
        }
    }

    var 인터넷_아이콘: String {
        switch 상태?.network {
        case NetworkKind.cell: return "antenna.radiowaves.left.and.right"
        case NetworkKind.none: return "wifi.slash"
        default: return "wifi"
        }
    }

    /// 와이파이 스위치 줄(:807-817). `wifiOn == nil` 이면 줄을 감춘다 — false(꺼짐)와 다르다.
    var 와이파이_스위치_문구: String? {
        guard let on = 상태?.wifiOn else { return nil }
        return String(
            format: String(localized: "control_network_wifi_switch"),
            on ? String(localized: "control_network_on") : String(localized: "control_network_off")
        )
    }

    /// 지금 걸려 있는 알람 한 줄(:912-931). 없으면 nil — 빈 줄로 자리를 잡지 않는다.
    var 알람_상태_문구: String? {
        guard let memo = 알람_기억 else { return nil }
        let time = Self.시각_문구(memo.minuteOfDay)
        let what = memo.label.isEmpty
            ? time
            : String(format: String(localized: "control_alarm_state_labeled"), time, memo.label)
        let format = memo.confirmed
            ? String(localized: "control_alarm_state_confirmed")
            : String(localized: "control_alarm_state_pending")
        return String(format: format, what)
    }

    // MARK: - 시작과 정리

    /// 화면이 보일 때마다 불러도 된다 — 처음 한 번만 구독한다(안드로이드는 프래그먼트가
    /// 처음 만들어질 때 `subscribe` 한 번, show/hide 로는 다시 안 부른다). 뷰의 `.task` 가
    /// 아니라 뷰모델이 소유한 Task 인 이유는 `MapViewModel.처음이면_읽는다` 와 같다.
    @discardableResult
    func 시작한다() -> Task<Void, Never> {
        // 정리된 뷰모델은 다시 살리지 않는다 — 가족·아이가 바뀌면 `RouterView` 의 `.id` 가
        // 뷰모델을 새로 만든다.
        if 닫혔다 { return Task {} }
        if let 시작_작업 { return 시작_작업 }
        let 작업 = Task { await self.구독을_시작한다() }
        시작_작업 = 작업
        return 작업
    }

    /// `subscribe`(:270-311). 안드로이드는 상태 읽기와 소리 조회를 나란히 띄우지만 여기서는
    /// 상태를 먼저 읽고 조회한다 — 문서 한 개 읽기만큼 조회가 늦어지는 대신 순서가 결정적이다.
    private func 구독을_시작한다() async {
        // Task 본문이 돌기 전에 정리가 먼저 올 수 있다.
        guard !닫혔다, !Task.isCancelled else { return }
        guard let childUid else {
            아이_안내 = String(localized: "map_no_child")
            // 안드로이드는 여기서 로딩 표시가 영영 남는다(판정 기록 5). iOS 는 끈다.
            상태_읽는_중 = false
            return
        }
        아이_안내 = nil
        settingsListener = settingsObserve(familyId, childUid, { [weak self] doc in
            Task { @MainActor in self?.잠금을_반영한다(doc.lockEnabled) }
        }, { [weak self] error in
            Task { @MainActor in self?.아이_안내 = errorMessage(error) }
        })
        await 상태를_읽는다(childUid: childUid, confirmedNow: false)
        // 상태를 읽는 동안 정리됐으면 조회 명령을 쓰지 않는다 — 쓰면 리스너까지 새로 붙는다.
        guard !닫혔다, !Task.isCancelled else { return }
        await 소리_상태를_묻는다()
    }

    /// 보호자 화면이 통째로 사라질 때(`GuardianRootView.onDisappear`). `onDestroyView`(:1094-1116).
    /// 세대를 올려 이미 대기열에 오른 콜백까지 무해하게 만든다.
    func 정리한다() {
        닫혔다 = true
        시작_작업?.cancel()
        시작_작업 = nil
        settingsListener?.remove()
        settingsListener = nil
        stopTracking()
        commandGeneration += 1
        statusGeneration += 1
        lockGeneration += 1
        findResetTask?.cancel()
        findResetTask = nil
        ringerQueryInFlight = false
    }

    // MARK: - 명령

    func 소리_모드를_보낸다(_ mode: String) async {
        // 페이로드 키 "mode" 는 child/CommandHandler 가 읽는 키다(:353-355).
        await send(CommandType.setRinger, payload: [RingerMode.payloadKey: mode])
    }

    /// 서버에 남은 옛 값 대신 자녀 폰에 지금 모드를 묻는다(:358-367).
    func 소리_상태를_묻는다() async {
        guard childUid != nil, !ringerQueryInFlight else { return }
        ringerQueryInFlight = true
        await send(CommandType.queryRinger)
    }

    /// 큰 버튼(:209-211) — 울린다고 믿으면 끄고, 아니면 울린다.
    func 폰찾기_버튼을_눌렀다() async {
        if 울리는_중이라고_믿는가 { await 소리를_끈다() } else { await 폰을_찾는다() }
    }

    /// 명령이 실제로 만들어진 뒤에만 '소리 끄기'로 바꾼다 — 발행이 실패했는데 바꿔 두면
    /// 울리지도 않는 폰을 끄라고 하게 된다(:369-377).
    private func 폰을_찾는다() async {
        await send(CommandType.findPhone) { [weak self] in
            guard let self else { return }
            self.findStartedAt = self.deviceNow()
            self.폰찾기_되돌리기를_건다(after: Self.findAutoStopMillis)
        }
    }

    /// '이미 울리고 있다면 소리 끄기'도 이 함수를 쓴다(:212, :379-386). 울리지 않을 때 와도
    /// 아이 폰에서 아무 일 없이 지나간다.
    func 소리를_끈다() async {
        await send(CommandType.stopFind) { [weak self] in
            guard let self else { return }
            self.findStartedAt = 0
            self.findResetTask?.cancel()
            self.findResetTask = nil
        }
    }

    /// 입력칸은 발행이 **성공한 뒤** 비운다 — 오프라인에서 실패하면 방금 쓴 문장이 남아야
    /// 한다. 길이는 입력칸이 이미 막으므로 여기서 다시 자르지 않는다(:388-408).
    func 메시지를_보낸다() async {
        let text = 메시지.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            commandUi = .failed(String(localized: "control_message_empty"))
            return
        }
        await send(CommandType.message, payload: [CommandType.payloadText: text]) { [weak self] in
            self?.메시지 = ""
        }
    }

    /// 보내는 것은 하루 안의 분과 이름뿐이다 — 절대 시각을 여기서 계산하면 두 폰의 시간대·
    /// 시계 차이가 그대로 어긋남이 된다. 기억은 발행 성공에서 적고 done 에서 굳힌다(:435-459).
    func 알람을_맞춘다() async {
        guard let childUid else { return }
        let label = 알람_이름.trimmingCharacters(in: .whitespacesAndNewlines)
        let minute = alarmMinute
        await send(
            CommandType.setAlarm,
            payload: [CommandType.payloadAtMinuteOfDay: String(minute), CommandType.payloadLabel: label]
        ) { [weak self] in
            guard let self else { return }
            self.alarmMemoStore.recordSent(childUid: childUid, minuteOfDay: minute, label: label)
            self.알람_기억을_다시_읽는다()
        }
    }

    /// 기억은 발행이 성공한 순간 지운다 — 남겨 두면 '알람 끄기'를 누른 화면에 "맞춰져
    /// 있어요"가 남아 부모가 한 번 더 누른다(:461-473).
    func 알람을_끈다() async {
        guard let childUid else { return }
        await send(CommandType.cancelAlarm) { [weak self] in
            guard let self else { return }
            self.alarmMemoStore.clear(childUid: childUid)
            self.알람_기억을_다시_읽는다()
        }
    }

    /// 명령을 발행하고 그 문서 하나를 따라간다(:475-570).
    private func send(
        _ type: String,
        payload: [String: String] = [:],
        onSent: @escaping @MainActor () -> Void = {}
    ) async {
        guard let childUid else {
            commandUi = .failed(String(localized: "map_no_child"))
            return
        }
        // 아이폰 아이에게 보낸 명령은 아무도 안 읽어 영원히 "전달 중"에 머문다(설계서 §1·§10.2).
        // 화면이 버튼을 껐지만 **계약은 여기다** — `commands/` 문서를 하나도 안 만든다.
        // 조용히 되돌아가지 않고 `.failed` 로 적는 이유: 이 자리에 오는 길이 남아 있다면 그것은
        // 화면의 버그이고, 그때 부모가 보는 문장은 참말이어야 한다.
        guard 명령을_보낼_수_있나 else {
            commandUi = .failed(String(localized: "ios_child_no_remote_control"))
            return
        }
        // 조회 중 다른 명령을 누르면 그 명령이 화면의 새 주인이다(:499-504).
        if trackingType == CommandType.queryRinger && type != CommandType.queryRinger {
            ringerQueryInFlight = false
        }
        stopTracking()
        timedOut = false
        trackingType = type
        trackingRingerMode = type == CommandType.setRinger ? payload[RingerMode.payloadKey] : nil
        commandGeneration += 1
        let generation = commandGeneration
        // 명령 종류와 상관없이 "물어봤다"로 친다 — 강제 종료된 폰은 무엇에도 대답이 없다(:516-519).
        requestLog.recordRequest(childUid)
        commandUi = .sending

        let familyId = self.familyId
        let sendCommand = commandSend
        do {
            let commandId = try await firstToFinish(timeoutMillis: Self.sendTimeoutMillis, sleep: commandSleep) {
                try await sendCommand(familyId, childUid, type, payload)
            }
            guard let commandId else {
                // 큐에 들어간 것은 나간 것이 아니다 — onSent 를 부르면 안 된다(:537-547).
                guard generation == commandGeneration else { return }
                ringerQueryFinishedIfCurrent(type)
                commandUi = .queued
                return
            }
            // onSent 는 세대와 상관없이 부른다 — "명령이 실제로 발행됐다"는 사실이다(:548-552).
            onSent()
            guard generation == commandGeneration else { return }
            track(childUid: childUid, commandId: commandId, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == commandGeneration else { return }
            ringerQueryFinishedIfCurrent(type)
            commandUi = .failed(errorMessage(error))
        }
    }

    /// 명령 문서 하나를 따라간다(:572-606). 리스너 콜백도 제한시간도 세대가 최신일 때만
    /// 화면을 만진다 — `remove()` 는 이미 큐에 오른 콜백까지 되돌리지 않는다.
    private func track(childUid: String, commandId: String, generation: Int) {
        stopTracking()
        commandListener = commandObserve(familyId, childUid, commandId, { [weak self] doc in
            Task { @MainActor in
                guard let self, generation == self.commandGeneration else { return }
                self.명령이_바뀌었다(doc)
            }
        }, { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.commandGeneration else { return }
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.ringerQueryFinishedIfCurrent(self.trackingType)
                self.commandUi = .failed(errorMessage(error))
            }
        })
        let sleep = commandSleep
        let timeout = Self.commandTimeoutMillis
        timeoutTask = Task { @MainActor [weak self] in
            await sleep(timeout)
            guard !Task.isCancelled, let self, generation == self.commandGeneration else { return }
            await self.시간이_지났다(generation: generation)
        }
    }

    /// `onCommandChanged`(:608-676). 리스너는 done 뒤에도 떼지 않는다 — 안드로이드와 같다.
    /// 끝난 문서는 더 안 바뀌고, 메시지는 delivered 에서 몇 시간 뒤 done 이 될 수 있다.
    private func 명령이_바뀌었다(_ doc: CommandDoc) {
        switch doc.state {
        case CommandState.done:
            timeoutTask?.cancel()
            timeoutTask = nil
            timedOut = false
            대답을_기록한다()
            if trackingType == CommandType.setAlarm, let childUid {
                alarmMemoStore.recordConfirmed(childUid: childUid)
                알람_기억을_다시_읽는다()
            }
            if trackingType == CommandType.setRinger, let mode = trackingRingerMode, RingerMode.isKnown(mode) {
                currentRingerMode = mode
                ringerAppliedInSession = true
            }
            if trackingType == CommandType.queryRinger {
                ringerQueryInFlight = false
                if let childUid {
                    Task { await self.상태를_읽는다(childUid: childUid, confirmedNow: true) }
                }
            }
            // 메시지의 done 은 "아이가 확인했어요를 눌렀다" — '완료'라고 적으면 다른 말이 된다(:635-637).
            commandUi = trackingMessage ? .messageRead : .done
        case CommandState.failed:
            timeoutTask?.cancel()
            timeoutTask = nil
            timedOut = false
            // 알람이 안 걸렸는데 "맞춰져 있어요"가 남으면 이 기능에서 제일 나쁜 거짓말이다(:642-647).
            if trackingType == CommandType.setAlarm, let childUid {
                alarmMemoStore.clear(childUid: childUid)
                알람_기억을_다시_읽는다()
            }
            ringerQueryFinishedIfCurrent(trackingType)
            // 실패도 대답이다 — 아이 폰이 살아 있으니 error 를 적을 수 있었다(:649-652).
            대답을_기록한다()
            commandUi = .failed(아이_오류_문구(doc.error))
        case CommandState.pending, CommandState.delivered:
            if trackingMessage && doc.state == CommandState.delivered {
                // 메시지는 여기가 종착역일 수 있다 — 60초 타이머를 끄고, delivered 자체를
                // 대답으로 친다(:658-669).
                timeoutTask?.cancel()
                timeoutTask = nil
                timedOut = false
                대답을_기록한다()
                commandUi = .messageUnread
            } else if !timedOut {
                commandUi = .sending
            }
        default:
            break
        }
    }

    /// 60초 무응답(:678-708). "실패했다"가 아니라 "대답이 없다" — 리스너는 떼지 않아 늦게라도
    /// done 이 오면 "완료"로 고쳐진다. 문구를 먼저 확정하고, 서버 시각을 잰 뒤 마지막 신호를
    /// 채운다. await 뒤에는 세대를 다시 본다(:697-701).
    ///
    /// 세대만으로는 모자라다(통합 검토 I1): 서버 시각을 재는 사이 done·failed·메시지
    /// delivered 가 오면 같은 세대인 채 `.done` 이 적히고 이 Task 가 취소된다. 그런데
    /// `try?` 가 취소를 삼켜 기기 시계로 물러나므로, 취소와 "아직 대답을 기다리는가"
    /// (`timedOut` — 대답이 온 경로가 푼다)를 함께 봐야 늦은 무응답 문구가 완료를 덮지
    /// 않는다. 안드로이드는 `timeoutJob?.cancel()` 이 `serverNow` 정지점에서 멈춰 같은 결과다.
    private func 시간이_지났다(generation: Int) async {
        timedOut = true
        ringerQueryFinishedIfCurrent(trackingType)
        commandUi = .failed(String(localized: "control_command_timeout"))

        let 신호_문구: String
        if let 상태, StatusCard.signal(status: 상태) != nil {
            // 서버 시각으로 뺀다 — 부모 폰 시계가 뒤처져 있으면 "-3분 전"이 찍힌다(:717-719).
            let now = (try? await serverNow(familyId)) ?? deviceNow()
            guard 아직_무응답인가(generation) else { return }
            신호_문구 = String(
                format: String(localized: "control_last_seen_format"),
                lastSignalText(StatusCard.lastSignal(status: 상태, nowMillis: now))
            )
        } else {
            신호_문구 = String(localized: "control_last_seen_never")
        }
        guard 아직_무응답인가(generation) else { return }
        commandUi = .failed(String(format: String(localized: "control_command_timeout_format"), 신호_문구))
    }

    private func 아직_무응답인가(_ generation: Int) -> Bool {
        !Task.isCancelled && timedOut && generation == commandGeneration
    }

    // MARK: - 잠금 스위치

    /// 스위치를 민 값을 저장한다(:828-871). 오프라인에서도 Firestore 가 로컬 쓰기를 즉시
    /// 되돌려주므로 화면은 저장된 것처럼 보인다 — 서버 확인이 15초 안에 안 오면 그 사실만
    /// 말하고 스위치는 되돌리지 않는다(쓰기는 큐에 살아 있다). 진짜 실패면 되돌리고 이유를 말한다.
    func 잠금을_바꾼다(_ enabled: Bool) async {
        guard let childUid else {
            commandUi = .failed(String(localized: "map_no_child"))
            return
        }
        // 이 저장소는 모든 보내기를 **두 겹**으로 막는다 — 뷰와 보내는 자리(`send:441-445`).
        // 잠금만 뷰 한 겹이었다(통합 검토 M1). 명령 문서를 만들지는 않지만
        // (`ScheduleRepository.setRingerLock` → `schedules/settings` 쓰기) 도달하면 `:626` 이
        // `.queued` 로 "인터넷이 연결되면 그때 애기폰으로 가서 실행돼요"를 띄운다 — 아이폰
        // 아이에게 거짓말이다. 게다가 아이 폰은 그 값을 **읽지도 않는다**.
        guard 명령을_보낼_수_있나 else {
            commandUi = .failed(String(localized: "ios_child_no_remote_control"))
            return
        }
        lockEnabled = enabled
        pendingLockValue = enabled
        lockGeneration += 1
        let generation = lockGeneration
        let familyId = self.familyId
        let save = lockSave
        do {
            let saved: Void? = try await firstToFinish(timeoutMillis: Self.sendTimeoutMillis, sleep: commandSleep) {
                try await save(familyId, childUid, enabled)
            }
            guard generation == lockGeneration else { return }
            if saved == nil { commandUi = .queued }
        } catch is CancellationError {
            return
        } catch {
            guard generation == lockGeneration else { return }
            pendingLockValue = nil
            lockEnabled = !enabled
            commandUi = .failed(errorMessage(error))
        }
    }

    /// 서버 값을 반영한다(:776-785, :820-826). 부모가 방금 만진 값이 아직 안 돌아왔으면
    /// 그대로 둔다 — 늦게 온 첫 읽기가 방금 켠 스위치를 도로 끄지 않게.
    private func 잠금을_반영한다(_ enabled: Bool) {
        if let pending = pendingLockValue, pending != enabled { return }
        pendingLockValue = nil
        lockEnabled = enabled
    }

    // MARK: - 도우미

    /// `loadStatus`(:313-348). 못 읽어도 화면 전체를 오류로 덮지 않는다 — 이 값은 무응답
    /// 문구의 보조 정보다.
    private func 상태를_읽는다(childUid: String, confirmedNow: Bool) async {
        statusGeneration += 1
        let generation = statusGeneration
        if !confirmedNow {
            currentRingerMode = nil
            ringerAppliedInSession = false
        }
        상태_읽는_중 = true
        do {
            let status = try await statusFetch(familyId, childUid)
            guard generation == statusGeneration else { return }
            상태 = status
            // 읽기를 하나도 더 안 사고 플랫폼을 안다 — 이 함수가 이미 읽고 있다(판정 기록 3).
            platforms.remember(childUid: childUid, status: status)
            currentRingerMode = status.map(\.ringerMode).flatMap { RingerMode.isKnown($0) ? $0 : nil }
            ringerAppliedInSession = confirmedNow
            상태_읽는_중 = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == statusGeneration else { return }
            Self.logger.error("아이 상태를 못 읽었다: \(String(describing: error), privacy: .public)")
            상태_읽는_중 = false
        }
    }

    private func 폰찾기_되돌리기를_건다(after millis: Int64) {
        findResetTask?.cancel()
        let sleep = commandSleep
        findResetTask = Task { @MainActor [weak self] in
            await sleep(max(millis, 0))
            guard !Task.isCancelled, let self else { return }
            self.findStartedAt = 0
        }
    }

    private func stopTracking() {
        commandListener?.remove()
        commandListener = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// 따라가던 것이 소리 조회일 때만 조회 중 표시를 끝낸다(:1053-1058).
    private func ringerQueryFinishedIfCurrent(_ type: String?) {
        guard type == CommandType.queryRinger else { return }
        ringerQueryInFlight = false
    }

    private func 대답을_기록한다() {
        guard let childUid else { return }
        requestLog.recordAnswer(childUid)
        대답이_기록되면?()
    }

    private func 알람_기억을_다시_읽는다() {
        알람_기억 = childUid.flatMap { alarmMemoStore.memo(childUid: $0) }
    }

    /// 자녀 폰이 `error` 에 남긴 코드를 문장으로(:752-767). 부모가 할 수 있는 일이 분명한
    /// 코드는 그 일까지 문장에 담는다.
    private func 아이_오류_문구(_ raw: String) -> String {
        switch raw {
        case RingerMode.errorDenied: return String(localized: "control_error_ringer_denied")
        case CommandType.errorNotificationOff: return String(localized: "control_error_message_notification_off")
        case CommandType.errorAlarmExactDenied: return String(localized: "control_error_alarm_exact_denied")
        default: return String(localized: "control_error_child_failed")
        }
    }

    private static func 소리_모드_이름(_ mode: String?) -> String? {
        switch mode {
        case RingerMode.normal: return String(localized: "control_mode_normal")
        case RingerMode.vibrate: return String(localized: "control_mode_vibrate")
        case RingerMode.silent: return String(localized: "control_mode_silent")
        default: return nil
        }
    }

    /// `ScheduleText.timeText`(ScheduleAdapter.kt:186-187) — 판정 기록 4 로 허용된 유일한 빌린 키.
    static func 시각_문구(_ minuteOfDay: Int) -> String {
        String(format: String(localized: "schedule_time_format"), minuteOfDay / 60, minuteOfDay % 60)
    }
}
