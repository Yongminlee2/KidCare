import FirebaseFirestore
import Foundation
import os
import Testing
@testable import KidCare

/// 관리 탭이 부르는 Firestore 쪽 전부의 가짜. 테스트가 명령 문서를 자녀 폰처럼 옮긴다.
/// 명령을 보내는 경로는 **이 가짜로만** 검증한다 — 운영은 물론 에뮬레이터에도 명령을 안 쓴다.
///
/// **`@unchecked Sendable` 은 테스트 타깃에만 있다** — `@Sendable` 클로저 안에서 불리고
/// Firestore 콜백(비 Sendable 클로저)을 붙들어야 해서, 상태 전부를 잠금 하나로 직접 지킨다.
final class FakeControlBackend: @unchecked Sendable {

    struct Sent: Equatable {
        let type: String
        let payload: [String: String]
    }

    struct State {
        var sent: [Sent] = []
        var sendHangs = false
        var sendError: Error?
        var status: ChildStatusDoc?
        var lockHangs = false
        var lockError: Error?
        var locksSaved: [Bool] = []
        var commandCallbacks: [(CommandDoc) -> Void] = []
        var commandListeners: [TestListenerRegistration] = []
        var settingsCallback: ((RingerSettingsDoc) -> Void)?
    }

    private let lock = NSLock()
    private var state = State()
    /// 영영 안 열리는 문 — 오프라인 쓰기를 흉내 낸다.
    private let 멈춤 = TestGate()
    let settingsListener = TestListenerRegistration()

    func update(_ body: (inout State) -> Void) { lock.withLock { body(&state) } }
    var snapshot: State { lock.withLock { state } }

    func send(type: String, payload: [String: String]) async throws -> String {
        let (hangs, error, id) = lock.withLock { () -> (Bool, Error?, String) in
            state.sent.append(Sent(type: type, payload: payload))
            return (state.sendHangs, state.sendError, "cmd-\(state.sent.count)")
        }
        if hangs { await 멈춤.wait() }
        if let error { throw error }
        return id
    }

    func observe(onChange: @escaping (CommandDoc) -> Void) -> ListenerRegistration {
        let listener = TestListenerRegistration()
        lock.withLock {
            state.commandCallbacks.append(onChange)
            state.commandListeners.append(listener)
        }
        return listener
    }

    /// `index` 번째(0부터, 리스너가 붙은 순서) 명령 문서를 자녀 폰이 옮긴 것처럼 알린다.
    func 명령을_옮긴다(_ index: Int, to newState: String, error: String = "") {
        let callback = lock.withLock { state.commandCallbacks[index] }
        callback(CommandDoc(id: "cmd-\(index + 1)", ["state": newState, "error": error]))
    }

    func observeSettings(onChange: @escaping (RingerSettingsDoc) -> Void) -> ListenerRegistration {
        lock.withLock { state.settingsCallback = onChange }
        return settingsListener
    }

    func 설정이_바뀌었다(lockEnabled: Bool) {
        let callback = lock.withLock { state.settingsCallback }
        callback?(RingerSettingsDoc(["lockEnabled": lockEnabled]))
    }

    func saveLock(_ enabled: Bool) async throws {
        let (hangs, error) = lock.withLock { () -> (Bool, Error?) in
            state.locksSaved.append(enabled)
            return (state.lockHangs, state.lockError)
        }
        if hangs { await 멈춤.wait() }
        if let error { throw error }
    }
}

/// 15초·60초·5분을 실제로 기다리지 않게 하는 가짜 수면. 길이마다 문이 하나씩 있고,
/// 테스트가 열어야 그 길이의 수면이 끝난다. 문은 한 번 열리면 계속 열려 있다.
final class FakeSleep: Sendable {
    let 발행 = TestGate()
    let 응답 = TestGate()
    let 폰찾기 = TestGate()
    private let 멈춤 = TestGate()

    func sleep(_ millis: Int64) async {
        switch millis {
        case ControlViewModel.sendTimeoutMillis: await 발행.wait()
        case ControlViewModel.commandTimeoutMillis: await 응답.wait()
        case ControlViewModel.findAutoStopMillis: await 폰찾기.wait()
        default: await 멈춤.wait()
        }
    }
}

/// 정본은 안드로이드 `guardian/ControlFragment.kt`. 줄 번호는 각 테스트 이름에 적었다.
@MainActor
struct ControlViewModelTests {

    private let now: Int64 = 1_757_000_000_000
    private struct 가짜_오류: Error {}

    private func 만든다(
        childUid: String? = "child",
        backend: FakeControlBackend,
        sleep: FakeSleep = FakeSleep(),
        log: RequestLog? = nil,
        memo: AlarmMemoStore? = nil,
        clock: TestClock? = nil
    ) -> ControlViewModel {
        let clock = clock ?? TestClock(now)
        return ControlViewModel(
            familyId: "family",
            childUid: childUid,
            requestLog: log ?? RequestLog(defaults: TestDefaults.isolated("ControlViewModelTests")),
            alarmMemoStore: memo ?? AlarmMemoStore(defaults: TestDefaults.isolated("ControlViewModelTests-memo"), now: { clock.value }),
            commandSend: { _, _, type, payload in try await backend.send(type: type, payload: payload) },
            commandObserve: { _, _, _, onChange, _ in backend.observe(onChange: onChange) },
            statusFetch: { _, _ in backend.snapshot.status },
            settingsObserve: { _, _, onChange, _ in backend.observeSettings(onChange: onChange) },
            lockSave: { _, _, enabled in try await backend.saveLock(enabled) },
            serverNow: { _ in clock.value },
            deviceNow: { clock.value },
            commandSleep: { millis in await sleep.sleep(millis) }
        )
    }

    private func 상태(
        ringerMode: String = "normal", dnd: String = "", network: String = "", wifiOn: Bool? = nil, lastSeenAt: Int64
    ) -> ChildStatusDoc {
        var data: [String: Any] = [
            "lat": 37.0, "lng": 127.0, "battery": 50,
            "ringerMode": ringerMode, "dnd": dnd, "network": network, "lastSeenAt": lastSeenAt,
        ]
        if let wifiOn { data["wifiOn"] = wifiOn }
        return ChildStatusDoc(data)!
    }

    @Test("열면 상태를 한 번 읽고 소리 상태를 묻고 설정을 구독한다, 다시 열어도 반복하지 않는다(subscribe :270-311)")
    func 시작() async {
        let backend = FakeControlBackend()
        let s = 상태(ringerMode: "vibrate", network: NetworkKind.wifi, wifiOn: true, lastSeenAt: now)
        backend.update { $0.status = s }
        let vm = 만든다(backend: backend)

        await vm.시작한다().value

        #expect(backend.snapshot.sent == [.init(type: CommandType.queryRinger, payload: [:])])
        #expect(vm.ringerQueryInFlight)
        #expect(vm.소리_상태_문구 == String(localized: "control_ringer_status_loading"))
        #expect(vm.currentRingerMode == RingerMode.vibrate)
        #expect(vm.인터넷_문구 == String(localized: "control_network_wifi"))
        #expect(vm.와이파이_스위치_문구 == String(format: String(localized: "control_network_wifi_switch"), String(localized: "control_network_on")))
        #expect(backend.snapshot.settingsCallback != nil)

        await vm.시작한다().value
        #expect(backend.snapshot.sent.count == 1)
    }

    @Test("소리 모드는 mode 페이로드로 가고, done 이면 '현재 상태 · 진동'·대답 기록·배너 판정(:352-356, :622-628)")
    func 소리_모드_완료() async {
        let backend = FakeControlBackend()
        let s = 상태(lastSeenAt: now)
        backend.update { $0.status = s }
        let log = RequestLog(defaults: TestDefaults.isolated("ControlViewModelTests"))
        let vm = 만든다(backend: backend, log: log)
        var 판정 = 0
        vm.대답이_기록되면 = { 판정 += 1 }

        await vm.시작한다().value
        await vm.소리_모드를_보낸다(RingerMode.vibrate)

        #expect(backend.snapshot.sent.last == .init(type: CommandType.setRinger, payload: ["mode": "vibrate"]))
        #expect(vm.commandUi == .sending)
        #expect(vm.ringerQueryInFlight == false) // 조회 중 누른 다른 명령이 화면의 새 주인(:499-504)
        #expect(log.lastRequestAt(childUid: "child") > 0)

        backend.명령을_옮긴다(1, to: CommandState.done)
        await eventually { vm.commandUi == .done }
        #expect(vm.currentRingerMode == RingerMode.vibrate)
        #expect(vm.선택된_모드인가(RingerMode.vibrate))
        #expect(vm.소리_상태_문구 == String(format: String(localized: "control_ringer_status_applied"), String(localized: "control_mode_vibrate")))
        #expect(판정 == 1)
        #expect(log.lastAnswerAt(childUid: "child") > 0)
    }

    @Test("소리 상태 조회가 done 이면 상태를 다시 읽고 '현재 상태'로 확정한다(:629-634)")
    func 조회_완료() async {
        let backend = FakeControlBackend()
        let 처음 = 상태(ringerMode: "normal", lastSeenAt: now)
        backend.update { $0.status = 처음 }
        let vm = 만든다(backend: backend)
        await vm.시작한다().value

        let 나중 = 상태(ringerMode: "silent", lastSeenAt: now)
        backend.update { $0.status = 나중 }
        backend.명령을_옮긴다(0, to: CommandState.done)

        await eventually { vm.currentRingerMode == RingerMode.silent && !vm.상태_읽는_중 }
        #expect(vm.ringerAppliedInSession)
        #expect(vm.ringerQueryInFlight == false)
        #expect(vm.소리_상태_문구 == String(format: String(localized: "control_ringer_status_applied"), String(localized: "control_mode_silent")))
    }

    @Test("발행이 15초 안에 확인되지 않으면 실패가 아니라 queued, 폰찾기 버튼은 그대로(:533-547)")
    func 발행_큐잉() async {
        let backend = FakeControlBackend()
        backend.update { $0.sendHangs = true }
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)

        let 누름 = Task { await vm.폰찾기_버튼을_눌렀다() }
        await eventually { backend.snapshot.sent.count == 1 }
        #expect(vm.commandUi == .sending)
        await sleep.발행.open()
        await 누름.value

        #expect(vm.commandUi == .queued)
        #expect(vm.울리는_중이라고_믿는가 == false) // onSent 를 부르면 안 된다(:538-545)
        #expect(backend.snapshot.commandCallbacks.isEmpty)
    }

    @Test("폰찾기가 발행되면 5분 동안 울린다고 믿고, 그 사이 누르면 stop_find, 5분 뒤엔 되돌아간다(:369-386, :891-899, :933-940)")
    func 폰찾기() async {
        let backend = FakeControlBackend()
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)

        await vm.폰찾기_버튼을_눌렀다()
        #expect(backend.snapshot.sent.last?.type == CommandType.findPhone)
        #expect(vm.울리는_중이라고_믿는가)

        await vm.폰찾기_버튼을_눌렀다()
        #expect(backend.snapshot.sent.last?.type == CommandType.stopFind)
        #expect(vm.울리는_중이라고_믿는가 == false)

        await vm.폰찾기_버튼을_눌렀다()
        #expect(vm.울리는_중이라고_믿는가)
        await sleep.폰찾기.open()
        await eventually { vm.울리는_중이라고_믿는가 == false }
    }

    @Test("failed 는 자녀 폰의 오류 코드를 문장으로 옮기고, 실패도 대답으로 친다(:639-654, :756-767)")
    func 실패_번역() async {
        let backend = FakeControlBackend()
        let log = RequestLog(defaults: TestDefaults.isolated("ControlViewModelTests"))
        let vm = 만든다(backend: backend, log: log)
        let 사례: [(code: String, key: String.LocalizationValue)] = [
            (RingerMode.errorDenied, "control_error_ringer_denied"),
            (CommandType.errorNotificationOff, "control_error_message_notification_off"),
            (CommandType.errorAlarmExactDenied, "control_error_alarm_exact_denied"),
            ("모르는_코드", "control_error_child_failed"),
        ]
        for (index, 하나) in 사례.enumerated() {
            await vm.소리_모드를_보낸다(RingerMode.silent)
            backend.명령을_옮긴다(index, to: CommandState.failed, error: 하나.code)
            let 기대 = String(localized: 하나.key)
            await eventually { vm.commandUi == .failed(기대) }
        }
        #expect(log.lastAnswerAt(childUid: "child") > 0)
    }

    @Test("메시지: 발행되면 입력칸을 비우고, delivered 는 '아직 안 읽음'이며 60초 타이머를 끈다, done 은 '읽음'(:398-408, :635-669)")
    func 메시지() async {
        let backend = FakeControlBackend()
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)
        vm.메시지 = "  밥 먹었어?  "

        await vm.메시지를_보낸다()
        #expect(backend.snapshot.sent.last == .init(type: CommandType.message, payload: ["text": "밥 먹었어?"]))
        #expect(vm.메시지 == "")

        backend.명령을_옮긴다(0, to: CommandState.delivered)
        await eventually { vm.commandUi == .messageUnread }
        await sleep.응답.open()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.commandUi == .messageUnread) // 잘 전해진 메시지 위에 '응답하지 않아요'를 덮지 않는다

        backend.명령을_옮긴다(0, to: CommandState.done)
        await eventually { vm.commandUi == .messageRead }
    }

    @Test("빈 메시지는 보내지 않고 이유를 말한다(:400-404)")
    func 빈_메시지() async {
        let backend = FakeControlBackend()
        let vm = 만든다(backend: backend)
        vm.메시지 = "   "
        await vm.메시지를_보낸다()
        #expect(backend.snapshot.sent.isEmpty)
        #expect(vm.commandUi == .failed(String(localized: "control_message_empty")))
    }

    @Test("60초 무응답은 '응답하지 않아요'와 마지막 신호를 함께 말하고, 대답으로 치지 않는다(:684-744)")
    func 무응답() async {
        let backend = FakeControlBackend()
        let s = 상태(lastSeenAt: now - 10 * 60_000)
        backend.update { $0.status = s }
        let sleep = FakeSleep()
        let log = RequestLog(defaults: TestDefaults.isolated("ControlViewModelTests"))
        let vm = 만든다(backend: backend, sleep: sleep, log: log)

        await vm.시작한다().value
        await vm.소리_모드를_보낸다(RingerMode.silent)
        await sleep.응답.open()

        let 기대 = String(
            format: String(localized: "control_command_timeout_format"),
            String(format: String(localized: "control_last_seen_format"), lastSignalText(.minutes(10)))
        )
        await eventually { vm.commandUi == .failed(기대) }
        #expect(log.lastAnswerAt(childUid: "child") == 0)
    }

    @Test("신호가 한 번도 없던 폰의 무응답은 '아직 한 번도 신호가 없었어요'(:739)")
    func 무응답_신호_없음() async {
        let backend = FakeControlBackend()
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)
        await vm.소리_모드를_보낸다(RingerMode.silent)
        await sleep.응답.open()
        let 기대 = String(format: String(localized: "control_command_timeout_format"), String(localized: "control_last_seen_never"))
        await eventually { vm.commandUi == .failed(기대) }
    }

    @Test("새 명령을 누르면 앞 리스너를 떼고, 늦게 온 앞 명령의 done 은 화면을 못 바꾼다(:98-118)")
    func 세대() async {
        let backend = FakeControlBackend()
        let vm = 만든다(backend: backend)
        await vm.소리_모드를_보낸다(RingerMode.vibrate)
        await vm.소리_모드를_보낸다(RingerMode.silent)
        #expect(backend.snapshot.commandListeners[0].removed)

        backend.명령을_옮긴다(0, to: CommandState.done)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.commandUi == .sending)
        #expect(vm.currentRingerMode == nil)

        backend.명령을_옮긴다(1, to: CommandState.done)
        await eventually { vm.commandUi == .done }
        #expect(vm.currentRingerMode == RingerMode.silent)
    }

    @Test("알람: 발행되면 '보냈어요', done 이면 '맞춰져 있어요', failed 면 기억을 지운다(:444-459, :612-647, :912-931)")
    func 알람() async {
        let backend = FakeControlBackend()
        let vm = 만든다(backend: backend)
        vm.alarmMinute = 7 * 60 + 30
        vm.알람_이름 = " 학원 "

        await vm.알람을_맞춘다()
        #expect(backend.snapshot.sent.last == .init(type: CommandType.setAlarm, payload: ["atMinuteOfDay": "450", "label": "학원"]))
        let 시각 = String(format: String(localized: "schedule_time_format"), 7, 30)
        let 무엇 = String(format: String(localized: "control_alarm_state_labeled"), 시각, "학원")
        #expect(vm.알람_상태_문구 == String(format: String(localized: "control_alarm_state_pending"), 무엇))

        backend.명령을_옮긴다(0, to: CommandState.done)
        let 확정 = String(format: String(localized: "control_alarm_state_confirmed"), 무엇)
        await eventually { vm.알람_상태_문구 == 확정 }

        await vm.알람을_맞춘다()
        backend.명령을_옮긴다(1, to: CommandState.failed, error: CommandType.errorAlarmExactDenied)
        await eventually { vm.알람_상태_문구 == nil }
    }

    @Test("알람 끄기는 발행되는 순간 기억을 지운다(:461-473)")
    func 알람_끄기() async {
        let backend = FakeControlBackend()
        let clock = TestClock(now)
        let store = AlarmMemoStore(defaults: TestDefaults.isolated("ControlViewModelTests-memo"), now: { clock.value })
        store.recordSent(childUid: "child", minuteOfDay: 420, label: "")
        let vm = 만든다(backend: backend, memo: store, clock: clock)
        #expect(vm.알람_상태_문구 != nil)

        await vm.알람을_끈다()
        #expect(backend.snapshot.sent.last?.type == CommandType.cancelAlarm)
        #expect(vm.알람_상태_문구 == nil)
    }

    @Test("잠금 저장이 실패하면 스위치를 되돌리고 이유를 말한다(:862-869)")
    func 잠금_실패() async {
        let backend = FakeControlBackend()
        backend.update { $0.lockError = 가짜_오류() }
        let vm = 만든다(backend: backend)
        await vm.시작한다().value

        await vm.잠금을_바꾼다(true)
        #expect(backend.snapshot.locksSaved == [true])
        #expect(vm.lockEnabled == false)
        #expect(vm.commandUi == .failed(errorMessage(가짜_오류())))
    }

    @Test("잠금 저장이 15초 안에 확인되지 않으면 스위치는 그대로 두고 queued(:849-860)")
    func 잠금_큐잉() async {
        let backend = FakeControlBackend()
        backend.update { $0.lockHangs = true }
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)
        await vm.시작한다().value

        let 누름 = Task { await vm.잠금을_바꾼다(true) }
        await eventually { backend.snapshot.locksSaved == [true] }
        #expect(vm.lockEnabled)
        await sleep.발행.open()
        await 누름.value
        #expect(vm.commandUi == .queued)
        #expect(vm.lockEnabled)
    }

    @Test("부모가 방금 민 값과 다른 옛 스냅샷은 스위치를 되돌리지 못한다(:170-176, :820-826)")
    func 잠금_보류값() async {
        let backend = FakeControlBackend()
        backend.update { $0.lockHangs = true }
        let vm = 만든다(backend: backend)
        await vm.시작한다().value

        _ = Task { await vm.잠금을_바꾼다(true) }
        await eventually { vm.lockEnabled }

        backend.설정이_바뀌었다(lockEnabled: false) // 화면을 연 직후의 늦은 첫 읽기
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.lockEnabled)

        backend.설정이_바뀌었다(lockEnabled: true)  // 우리가 쓴 값이 돌아왔다 — 보류를 푼다
        backend.설정이_바뀌었다(lockEnabled: false) // 이제부터는 서버 값을 따른다
        await eventually { vm.lockEnabled == false }
    }

    @Test("아이가 없으면 명령을 못 보내고 map_no_child, 소리 상태가 로딩에 갇히지 않는다(판정 기록 5)")
    func 아이_없음() async {
        let backend = FakeControlBackend()
        let vm = 만든다(childUid: nil, backend: backend)
        await vm.시작한다().value

        #expect(vm.아이_안내 == String(localized: "map_no_child"))
        #expect(vm.버튼_활성화 == false)
        #expect(vm.소리_상태_문구 == String(localized: "control_ringer_status_unknown"))

        await vm.소리_모드를_보낸다(RingerMode.silent)
        #expect(backend.snapshot.sent.isEmpty)
        #expect(vm.commandUi == .failed(String(localized: "map_no_child")))
    }

    @Test("방해 금지가 켜져 있으면 모드 대신 '방해금지 모드'라 말하고 안내 줄을 보인다(:999-1015), 인터넷 없음(:794-818)")
    func 방해금지와_인터넷() async {
        let backend = FakeControlBackend()
        let s = 상태(ringerMode: "silent", dnd: "priority", network: NetworkKind.none, lastSeenAt: now)
        backend.update { $0.status = s }
        let vm = 만든다(backend: backend)
        await vm.시작한다().value
        backend.명령을_옮긴다(0, to: CommandState.done)
        await eventually { !vm.상태_읽는_중 && !vm.ringerQueryInFlight }

        #expect(vm.소리_상태_문구 == String(format: String(localized: "control_ringer_status_format"), String(localized: "control_ringer_dnd")))
        #expect(vm.방해금지_안내를_보이는가)
        #expect(vm.인터넷_문구 == String(localized: "control_network_none"))
        #expect(vm.와이파이_스위치_문구 == nil) // false(꺼짐)와 nil(모름)은 다른 말이다
    }

    @Test("정리하면 설정 리스너와 명령 리스너를 뗀다(onDestroyView :1094-1116)")
    func 정리() async {
        let backend = FakeControlBackend()
        let vm = 만든다(backend: backend)
        await vm.시작한다().value
        #expect(backend.settingsListener.removed == false)

        vm.정리한다()
        #expect(backend.settingsListener.removed)
        #expect(backend.snapshot.commandListeners[0].removed)
    }
}
