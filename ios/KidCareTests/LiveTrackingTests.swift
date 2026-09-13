import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// Task 7 — '실시간 보기' 토글의 상태 기계. 정본은 안드로이드 `startLiveTracking`(:459)·
/// `trackLiveStart`(:508)·`beginLiveStatusSubscription`(:540)·`failLiveStart`(:584)·
/// `stopLiveTracking`(:593)·`stopLiveCommandTracking`(:635). `MapViewModelCommandGenerationTests`
/// 와 같은 발상으로 Firestore 를 전혀 타지 않는다 — `commandSend`·`commandObserve`·
/// `commandSleep`·`liveStatusObserve` 넷 다 가짜를 주입해 순서를 테스트가 직접 정한다.
///
/// **이 화면에서 유일하게 상시 구독이 옳은 자리다**(브리프) — 그래서 리스너 정리를
/// 모든 종료 경로(끄기·시작 실패·10분 만료·화면 사라짐)에서 각각 증명한다. 세대
/// 가드(`liveCommandGeneration`)도 늦은 시작-확인이 꺼진 추적을 다시 켜지 못한다는
/// 것을 실제로 증명한다.
@Suite(.serialized)
@MainActor
struct LiveTrackingTests {

    init() async { await EmulatorHarness.start() }

    /// [MapViewModelRaceTests.Gate] 와 같은 발상 — 테스트가 열어줄 때까지 매달려 있는 문.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    /// 딱 한 번만 발화하는 신호. `MapViewModelCommandGenerationTests.SingleSignal` 과 같다.
    private actor SingleSignal {
        private var fired = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if fired { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func fire() {
            guard !fired else { return }
            fired = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    /// 진짜 `ListenerRegistration` 을 흉내 낸다 — `remove()` 가 실제로 불렸는지 확인용.
    /// `MapViewModelCommandGenerationTests.FakeListenerRegistration` 과 같은 이유로
    /// `@unchecked Sendable`(테스트 전용)을 쓴다.
    final class FakeListenerRegistration: NSObject, ListenerRegistration, @unchecked Sendable {
        private let 잠금 = OSAllocatedUnfairLock(initialState: false)
        var removed: Bool { 잠금.withLock { $0 } }
        func remove() { 잠금.withLock { $0 = true } }
    }

    /// `commandObserve` 가 넘겨준 `onChange` 콜백을 나중에(늦게) 직접 다시 부르기
    /// 위한 상자. 세대 가드 테스트 전용 — 일반 `@Sendable` 클로저 캡처 변수로는
    /// Swift 6 가 "동시 실행 코드에서 캡처된 변수를 건드린다"며 컴파일을 막는다
    /// (`MapViewModelCommandGenerationTests.CallCounter` 주석과 같은 사정).
    final class CommandChangeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: ((CommandDoc) -> Void)?
        func set(_ handler: @escaping (CommandDoc) -> Void) {
            lock.lock(); defer { lock.unlock() }
            self.handler = handler
        }
        func call(_ doc: CommandDoc) {
            lock.lock()
            let h = handler
            lock.unlock()
            h?(doc)
        }
    }

    /// `liveStatusObserve` 가 넘겨준 `onChange` 를 나중에 테스트가 직접 부르기 위한 상자
    /// (`CommandChangeBox` 와 같은 사정).
    final class StatusChangeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: ((ChildStatusDoc?) -> Void)?
        func set(_ handler: @escaping (ChildStatusDoc?) -> Void) {
            lock.lock(); defer { lock.unlock() }
            self.handler = handler
        }
        func call(_ doc: ChildStatusDoc?) {
            lock.lock()
            let h = handler
            lock.unlock()
            h?(doc)
        }
    }

    private static let 빈_하루_읽기: @Sendable (String, String, String) async throws -> (status: ChildStatusDoc?, trail: TrailDoc?) = { _, _, _ in (nil, nil) }

    private func 격리된_요청_기록() -> RequestLog {
        RequestLog(defaults: UserDefaults(suiteName: "LiveTrackingTests-\(UUID())")!)
    }

    private nonisolated static func status(at: Int64, accuracy: Double = 12.0, battery: Int = 61) -> ChildStatusDoc {
        ChildStatusDoc([
            "lat": 37.0, "lng": 127.0, "accuracy": accuracy,
            "at": at, "battery": battery, "charging": false,
            "ringerMode": "normal", "lastSeenAt": at,
        ])!
    }

    /// 시작을 누르면 곧바로 `.starting` 이고, 연결 중 문구가 상태 줄에 뜬다.
    @Test("시작하면 곧바로 starting 이고 연결 중 문구가 뜬다")
    func 시작하면_연결중() async throws {
        let 문 = Gate()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in await 문.wait(); return "cmd" }, // 절대 안 끝난다(테스트가 나중에 연다)
            dayLoad: Self.빈_하루_읽기
        )
        let 태스크 = Task { await vm.실시간_추적을_시작한다() }
        // starting 으로 바뀔 시간을 준다 — commandSend 는 아직 안 끝났다.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.liveTrackingState == .starting)
        #expect(vm.실시간_상태_문구 == String(localized: "map_live_connecting"))
        #expect(vm.liveTrackingActiveOrTransitioning == true)
        await 문.open()
        _ = await 태스크.value
    }

    /// 발행(서버 확인)을 15초 안에 못 받으면 실패가 아니라 큐잉 문구다 — '지금
    /// 위치 확인'과 같은 규칙(브리프 규칙 2).
    @Test("발행이 15초 안에 확인되지 않으면 control_command_queued 로 끝난다")
    func 발행이_시간안에_못끝나면_큐잉() async throws {
        let sendTimeout: Int64 = 111
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in await Gate().wait(); return "never" }, // 영원히 안 끝난다
            commandSleep: { millis in
                guard millis == sendTimeout else { await Gate().wait(); return }
                // 발행 대기는 즉시 시간 초과되게 한다.
            },
            sendTimeoutMillis: sendTimeout,
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        #expect(vm.liveTrackingState == .off)
        #expect(vm.오류 == String(localized: "control_command_queued"))
        #expect(vm.liveTrackingActiveOrTransitioning == false)
    }

    /// 발행은 됐지만(=commandId 를 받음) 아이 폰의 시작-확인을 60초 안에 못
    /// 받으면 control_command_timeout 으로 끝난다.
    @Test("시작 확인이 60초 안에 없으면 control_command_timeout 으로 끝나고 ack 리스너를 뗀다")
    func 시작확인이_시간초과되면_실패() async throws {
        let answerTimeout: Int64 = 222
        let listener = FakeListenerRegistration()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, _, _ in listener }, // onChange 를 절대 안 부른다
            commandSleep: { millis in
                guard millis == answerTimeout else { await Gate().wait(); return }
            },
            answerTimeoutMillis: answerTimeout,
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 100_000_000) // 타이머 Task 가 돌 시간을 준다
        #expect(vm.liveTrackingState == .off)
        #expect(vm.오류 == String(localized: "control_command_timeout"))
        #expect(listener.removed)
    }

    /// 시작-확인(done)을 받으면 상태 구독을 시작하고 `.on` 이 된다 — 아직 실제
    /// 신호를 못 받았으니 대기 문구다.
    @Test("시작-확인(done)을 받으면 아이 상태를 구독하고 on 이 된다")
    func 시작확인_받으면_on() async throws {
        let ackListener = FakeListenerRegistration()
        let statusListener = FakeListenerRegistration()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return ackListener
            },
            commandSleep: { _ in await Gate().wait() },
            liveStatusObserve: { _, _, _, _ in statusListener },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 100_000_000) // onChange 가 Task 로 건너간다
        guard case .on = vm.liveTrackingState else {
            Issue.record("on 이 아니라 \(vm.liveTrackingState) 다")
            return
        }
        #expect(vm.실시간_상태_문구 == String(localized: "map_live_waiting")) // 아직 신호를 못 받았다
        #expect(ackListener.removed) // 확인 리스너는 상태 구독으로 넘어가며 뗀다
        #expect(!statusListener.removed)
    }

    /// 구독 직후 되돌아오는(구독을 붙이기 **전**) 캐시된 문서는 실시간 신호로
    /// 보여주지 않는다 — 대기 문구를 유지한다(브리프 "must not claim a fresher
    /// signal than the listener actually delivered").
    @Test("구독 직전보다 오래된 문서는 대기 문구를 유지한다")
    func 옛_문서는_대기_문구를_유지한다() async throws {
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            liveStatusObserve: { _, _, onChange, _ in
                onChange(Self.status(at: 500)) // baseline(1000)보다 오래된 캐시 문서
                return FakeListenerRegistration()
            },
            dayLoad: { _, _, _ in (Self.status(at: 1_000), nil) }
        )

        await vm.하루를_읽는다() // 상태의 baseline(at: 1000)을 채운다
        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 150_000_000)

        #expect(vm.실시간_상태_문구 == String(localized: "map_live_waiting"))
    }

    /// 실제로 새 신호를 받으면 정확도·배터리 문구가 뜨고, 마커가 따라가라는
    /// 신호(`카메라를_다시_맞춰야_한다`)가 서고, `상태` 가 갱신된다 — 세션이
    /// 끝난 뒤에도 평소 문구가 이 값을 반영하도록.
    @Test("새 신호를 받으면 active_status 문구가 뜨고 카메라 재조준 신호가 서고 상태가 갱신된다")
    func 새_신호를_받으면_활성_문구() async throws {
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            liveStatusObserve: { _, _, onChange, _ in
                onChange(Self.status(at: 999_999_999_999, accuracy: 14.6, battery: 42))
                return FakeListenerRegistration()
            },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 150_000_000) // done → 구독 시작 → 신호 처리, 두 단계 Task 를 흘려보낸다

        // 통합 검토 M6: 기대값을 같은 서식 키로 만들면 `%%` 가 `%` 로 망가져도(배터리
        // 뒤 "%" 가 사라져도) 양쪽이 똑같이 망가져 초록이다. 화면에 실제로 찍혀야 할
        // 글자를 리터럴로 못박는다.
        let 문구 = try #require(vm.실시간_상태_문구)
        #expect(문구.hasSuffix("42%"), "배터리 뒤 % 가 사라졌다: \(문구)")
        #expect(문구.contains("15m"), "정확도 반올림이 틀렸다: \(문구)")
        #expect(vm.카메라를_다시_맞춰야_한다 == true)
        #expect(vm.상태?.battery == 42)
    }

    /// 통합 검토 I2: 안드로이드 실시간 onChange(MapTimelineFragment.kt:548-566)는 `renderStatus`·
    /// `recordAnswer` 를 부르지 않는다. 물어본 **뒤** 쓰인 스냅샷이라도 배너 대답이 아니다.
    /// 에뮬레이터에 기대지 않고 서버 오프셋을 먼저 재 둔다 — 위치 확인의 60초가 즉시 지나
    /// `commandServerNow`(기기 시계)로 오프셋을 잰다. 재기 전에는 대답 규칙이 아예 판단하지
    /// 않아 이 테스트가 아무것도 지키지 못한다.
    @Test("I2: 실시간 상태 스냅샷은 배너 대답이 아니다 — 배너를 지우지도 대답을 적지도 않는다")
    func 실시간_스냅샷은_배너_대답이_아니다() async throws {
        let log = 격리된_요청_기록()
        let 상태_상자 = StatusChangeBox()
        let answerTimeout: Int64 = 222
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: log,
            commandSend: { _, _, type, _ in type }, // 명령 종류를 문서 id 로 돌려준다
            commandObserve: { _, _, commandId, onChange, _ in
                // 위치 확인은 대답하지 않고, 실시간 시작만 곧바로 확인한다.
                if commandId != CommandType.locateNow { onChange(CommandDoc(id: commandId, ["state": "done"])) }
                return FakeListenerRegistration()
            },
            commandSleep: { millis in
                guard millis == answerTimeout else { await Gate().wait(); return }
            },
            answerTimeoutMillis: answerTimeout,
            commandServerNow: { _, _ in Int64(Date().timeIntervalSince1970 * 1000) },
            liveStatusObserve: { _, _, onChange, _ in
                상태_상자.set(onChange)
                return FakeListenerRegistration()
            },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.지금_위치를_확인한다() // 물어봤다 + 60초 무응답 → 서버 오프셋을 잰다
        await eventually { if case .timedOut = vm.commandProgress { return true } else { return false } }
        let 물은_시각 = log.lastRequestAt(childUid: "child")
        #expect(물은_시각 > 0)

        let 한시간_뒤 = 물은_시각 + 60 * 60_000
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { 한시간_뒤 })
        var 불린_횟수 = 0
        vm.대답이_기록되면 = { 불린_횟수 += 1; banner.다시_판정한다() }
        banner.다시_판정한다()
        #expect(banner.문구 != nil)

        await vm.실시간_추적을_시작한다()
        await eventually { if case .on = vm.liveTrackingState { return true } else { return false } }
        // 물어본 뒤에 쓰인 신호 — 처음 읽기 경로라면 대답으로 쳤을 문서다.
        상태_상자.call(Self.status(at: 물은_시각 + 5_000, battery: 42))
        await eventually { vm.상태?.battery == 42 } // 스냅샷은 실제로 처리됐다
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(log.lastAnswerAt(childUid: "child") == 0)
        #expect(불린_횟수 == 0)
        #expect(banner.문구 != nil)
    }

    /// 10분(주입한 짧은 값) 뒤 자동으로 꺼지고 map_live_timeout 문구를 남기고
    /// 상태 리스너를 뗀다.
    @Test("10분 뒤 자동으로 꺼지고 map_live_timeout 문구를 남긴다")
    func 자동_만료() async throws {
        let sessionTimeout: Int64 = 333
        let statusListener = FakeListenerRegistration()
        let 세션_타이머_시작됨 = SingleSignal()
        let 세션_타이머_호출_순번 = OSAllocatedUnfairLock(initialState: 0)

        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { millis in
                guard millis == sessionTimeout else { await Gate().wait(); return }
                let n = 세션_타이머_호출_순번.withLock { $0 += 1; return $0 }
                if n == 1 { await 세션_타이머_시작됨.fire() }
            },
            liveStatusObserve: { _, _, _, _ in statusListener },
            liveSessionTimeoutMillis: sessionTimeout,
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        await 세션_타이머_시작됨.wait()
        try? await Task.sleep(nanoseconds: 100_000_000) // 타이머 콜백이 처리될 시간을 준다

        #expect(vm.liveTrackingState == .off)
        #expect(vm.오류 == String(localized: "map_live_timeout"))
        #expect(statusListener.removed)
    }

    /// 끄기 버튼(사용자 조작) — 즉시 꺼지고 map_live_stopped 문구를 남기고,
    /// **시작할 때 발급한 것과 같은 sessionId** 로 종료 명령을 보낸다(아이 폰이
    /// 옛 세션을 무시하는 규약, 브리프).
    @Test("끄기 버튼을 누르면 즉시 꺼지고, 시작 때와 같은 sessionId 로 종료 명령을 보낸다")
    func 끄기_버튼() async throws {
        let statusListener = FakeListenerRegistration()
        let 보낸_페이로드 = OSAllocatedUnfairLock(initialState: [[String: String]]())
        let 두번째_전송_신호 = SingleSignal()

        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, type, payload in
                let count = 보낸_페이로드.withLock { $0.append(payload); return $0.count }
                if type == CommandType.stopLiveTracking { await 두번째_전송_신호.fire() }
                return count == 1 ? "cmd" : "cmd-stop"
            },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            liveStatusObserve: { _, _, _, _ in statusListener },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard case .on = vm.liveTrackingState else {
            Issue.record("on 이 아니라 \(vm.liveTrackingState) 다 — 끄기 전에 이미 실패했다")
            return
        }

        vm.실시간_추적을_끈다()
        #expect(vm.liveTrackingState == .off) // 동기적으로 곧바로 꺼진다(안드로이드와 같다)
        #expect(vm.오류 == String(localized: "map_live_stopped"))
        #expect(statusListener.removed)

        await 두번째_전송_신호.wait() // 종료 명령이 실제로 나갈 때까지 기다린다
        let 페이로드들 = 보낸_페이로드.withLock { $0 }
        #expect(페이로드들.count == 2)
        let 시작_세션_id = 페이로드들[0][CommandType.payloadSessionId]
        let 종료_세션_id = 페이로드들[1][CommandType.payloadSessionId]
        #expect(시작_세션_id != nil)
        #expect(시작_세션_id == 종료_세션_id)
    }

    /// 화면이 사라질 때(`onDisappear`) 부르는 정리 경로도 리스너를 뗀다.
    @Test("화면이 사라지면(정리 함수) 상태 리스너를 뗀다")
    func 화면이_사라지면_리스너를_뗀다() async throws {
        let statusListener = FakeListenerRegistration()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            liveStatusObserve: { _, _, _, _ in statusListener },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(!statusListener.removed)

        vm.실시간_추적을_정리한다()
        #expect(statusListener.removed)
        #expect(vm.liveTrackingState == .off)
    }

    /// 아이 폰이 시작을 거부(failed)하면 세션을 정리하고 아이 폰이 적은 이유로
    /// 문구를 남긴다.
    @Test("아이 폰이 시작을 거부하면 실패 문구를 남기고 정리한다")
    func 시작_거부() async throws {
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "failed", "error": "무언가_다른_이유"]))
                return FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.liveTrackingState == .off)
        #expect(vm.오류 == String(localized: "control_error_child_failed"))
    }

    /// **세대 가드.** 추적을 껐는데(세대가 이미 올라갔는데) 낡은 세대의 시작-확인
    /// (done)이 뒤늦게 도착해도 추적을 다시 켜면 안 된다 — 이 가드를 지우면
    /// 이 테스트가 빨간불이 된다(직접 확인함).
    @Test("추적을 끈 뒤 낡은 세대의 늦은 시작-확인이 와도 다시 켜지지 않는다")
    func 낡은_세대의_늦은_확인은_다시_켜지_않는다() async throws {
        let box = CommandChangeBox()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                box.set(onChange) // 아직 부르지 않는다 — 늦게, 테스트가 직접 부른다
                return FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.liveTrackingState == .starting)

        vm.실시간_추적을_끈다() // 세대가 올라간다 — 이 시작 시도는 이제 낡았다
        #expect(vm.liveTrackingState == .off)

        box.call(CommandDoc(id: "cmd", ["state": "done"])) // 낡은 세대의 늦은 확인
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.liveTrackingState == .off) // 다시 켜지지 않았다
    }

    /// 인터락 — 켜져 있거나(on) 전환 중(starting)이면 '지금 위치 확인' 버튼이
    /// 막힌다. 정본은 안드로이드 `setLocateButtonEnabled`(:709) 세 번째 조건.
    @Test("실시간 추적이 켜져 있거나 전환 중이면 위치확인 버튼을 막는다")
    func 인터락() async throws {
        let 문 = Gate()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in await 문.wait(); return "cmd" },
            dayLoad: Self.빈_하루_읽기
        )
        #expect(vm.위치확인_버튼_활성화 == true)

        let 태스크 = Task { await vm.실시간_추적을_시작한다() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.liveTrackingState == .starting)
        #expect(vm.위치확인_버튼_활성화 == false) // starting 도 "전환 중"이다

        vm.실시간_추적을_끈다()
        #expect(vm.위치확인_버튼_활성화 == true)
        await 문.open()
        태스크.cancel()
    }

    // MARK: - 통합 검토 I1: 끝난 '지금 위치 확인' 결과가 실시간 문구를 가리지 않는다

    /// 발행 대기(.queued)로 끝난 위치 확인이 남아 있는 채로 실시간을 시작하면, 그
    /// 옛 결과를 거둔다 — 안 거두면 `StatusCardView` 가 명령 문구를 먼저 보여준다.
    @Test("I1: 끝난 위치 확인 결과는 실시간을 시작하면 상태 줄에서 거둔다")
    func 끝난_위치확인_결과는_실시간_시작에서_거둔다() async throws {
        let sendTimeout: Int64 = 111
        let 발행_시간초과_횟수 = OSAllocatedUnfairLock(initialState: 0)
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, type, _ in
                if type == CommandType.locateNow { await Gate().wait(); return "never" } // 발행이 영영 안 끝난다
                return "cmd-live"
            },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd-live", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { millis in
                // 첫 발행 대기(위치 확인)만 곧바로 시간 초과시킨다. 실시간 시작의 발행
                // 대기까지 즉시 끝내면 전송과 경주가 돼 결과가 흔들린다.
                if millis == sendTimeout, 발행_시간초과_횟수.withLock({ $0 += 1; return $0 }) == 1 { return }
                await Gate().wait()
            },
            sendTimeoutMillis: sendTimeout,
            liveStatusObserve: { _, _, _, _ in FakeListenerRegistration() },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.지금_위치를_확인한다()
        #expect(vm.명령_상태_문구 == String(localized: "control_command_queued"))

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard case .on = vm.liveTrackingState else {
            Issue.record("on 이 아니라 \(vm.liveTrackingState) 다")
            return
        }
        #expect(vm.명령_상태_문구 == nil)
        #expect(vm.상태_줄_덮어쓰기_문구 == String(localized: "map_live_waiting"))
    }

    /// 실시간 추적 도중에 끝난 위치 확인(.timedOut)이 10분 자동 종료 문구를 가리지
    /// 않는다 — 리뷰가 든 시나리오 그대로다(얼어붙은 "마지막 신호 N분 전" 대신
    /// `map_live_timeout` 이 보여야 한다).
    @Test("I1: 실시간이 끝나면 옛 무응답 문구가 map_live_timeout 을 가리지 않는다")
    func 실시간_종료는_옛_무응답_문구를_거둔다() async throws {
        let answerTimeout: Int64 = 222
        let sessionTimeout: Int64 = 333
        let 응답_문 = Gate()
        let 세션_문 = Gate()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, type, _ in type == CommandType.locateNow ? "cmd-locate" : "cmd-live" },
            commandObserve: { _, _, commandId, onChange, _ in
                if commandId == "cmd-live" { onChange(CommandDoc(id: "cmd-live", ["state": "done"])) }
                return FakeListenerRegistration() // 위치 확인에는 아이 폰이 끝내 대답하지 않는다
            },
            commandSleep: { millis in
                switch millis {
                case answerTimeout: await 응답_문.wait()
                case sessionTimeout: await 세션_문.wait()
                default: await Gate().wait() // 발행 대기·시계 — 전송이 먼저 이긴다
                }
            },
            answerTimeoutMillis: answerTimeout,
            commandServerNow: { _, _ in 1_000 },
            liveStatusObserve: { _, _, _, _ in FakeListenerRegistration() },
            liveSessionTimeoutMillis: sessionTimeout,
            dayLoad: Self.빈_하루_읽기
        )

        await vm.지금_위치를_확인한다()
        #expect(vm.commandProgress == .delivering)

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard case .on = vm.liveTrackingState else {
            Issue.record("on 이 아니라 \(vm.liveTrackingState) 다")
            return
        }
        #expect(vm.commandProgress == .delivering) // 진행 중인 왕복은 건드리지 않는다

        await 응답_문.open() // 실시간 도중에 위치 확인이 무응답으로 끝난다
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard case .timedOut = vm.commandProgress else {
            Issue.record("timedOut 이 아니라 \(vm.commandProgress) 다")
            return
        }

        await 세션_문.open() // 10분 자동 종료
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.liveTrackingState == .off)
        #expect(vm.오류 == String(localized: "map_live_timeout"))
        #expect(vm.명령_상태_문구 == nil)
        #expect(vm.상태_줄_덮어쓰기_문구 == nil) // 카드는 loadError(= map_live_timeout)로 물러난다
    }

    // MARK: - 통합 검토 I2: 실시간 중 오류가 보인다

    /// 상태 리스너 오류는 종결이다 — 세션을 멈추고(리스너 정리) 오류를 보여준다.
    @Test("I2: 실시간 상태 리스너가 오류를 내면 세션을 멈추고 오류를 보여준다")
    func 상태_리스너_오류는_세션을_멈춘다() async throws {
        struct 권한_오류: Error {}
        let statusListener = FakeListenerRegistration()
        let 보낸_종류 = OSAllocatedUnfairLock(initialState: [String]())
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, type, _ in
                보낸_종류.withLock { $0.append(type) }
                return "cmd"
            },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            liveStatusObserve: { _, _, _, onError in
                onError(권한_오류())
                return statusListener
            },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 150_000_000)

        #expect(vm.liveTrackingState == .off)
        #expect(statusListener.removed)
        #expect(vm.오류 == errorMessage(권한_오류()))
        #expect(vm.실시간_상태_문구 == nil) // "실시간 추적 중" 이 죽은 리스너 위에 남지 않는다
        #expect(vm.상태_줄_덮어쓰기_문구 == nil)
        try? await Task.sleep(nanoseconds: 50_000_000) // 종료 명령은 기다리지 않는 태스크로 나간다
        #expect(보낸_종류.withLock { $0 }.contains(CommandType.stopLiveTracking))
    }

    /// 실시간이 켜진 채로 하루 읽기가 실패하면 그 오류가 보인다 — 마지막으로 쓴 쪽이
    /// 이긴다. 그 뒤 새 실시간 신호가 오면 다시 실시간 문구가 이긴다(안드로이드
    /// statusBar 와 같은 순서).
    @Test("I2: 실시간 중 하루 읽기 실패가 보이고, 이후 새 신호가 다시 덮는다")
    func 실시간_중_하루읽기_실패는_마지막으로_쓴_쪽이_이긴다() async throws {
        struct 읽기_오류: Error {}
        let box = StatusChangeBox()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            liveStatusObserve: { _, _, onChange, _ in
                box.set(onChange)
                return FakeListenerRegistration()
            },
            dayLoad: { _, _, _ in throw 읽기_오류() }
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.상태_줄_덮어쓰기_문구 == String(localized: "map_live_waiting"))

        await vm.하루를_읽는다() // 실패한다
        let 오류_문구 = errorMessage(읽기_오류())
        #expect(vm.오류 == 오류_문구)
        #expect(vm.상태_줄_덮어쓰기_문구 == 오류_문구)
        #expect(vm.liveTrackingState != .off) // 읽기 실패는 실시간 세션을 끝내지 않는다

        box.call(Self.status(at: 999_999_999_999, accuracy: 8, battery: 69)) // 새 신호
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.상태_줄_덮어쓰기_문구?.hasSuffix("69%") == true)
    }

    // MARK: - 통합 검토 M8: 같은 세대의 두 번째 done 은 구독을 다시 걸지 않는다

    @Test("M8: 같은 세대의 done 이 두 번 와도 상태 구독·10분 타이머를 한 번만 건다")
    func 두번째_done_은_구독을_다시_걸지_않는다() async throws {
        let 구독_횟수 = OSAllocatedUnfairLock(initialState: 0)
        let sessionTimeout: Int64 = 333
        let 세션_타이머_횟수 = OSAllocatedUnfairLock(initialState: 0)
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                // 첫 스냅샷이 리스너를 떼기 전에 두 번째 스냅샷이 이미 줄을 섰다.
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return FakeListenerRegistration()
            },
            commandSleep: { millis in
                if millis == sessionTimeout { 세션_타이머_횟수.withLock { $0 += 1 } }
                await Gate().wait()
            },
            liveStatusObserve: { _, _, _, _ in
                구독_횟수.withLock { $0 += 1 }
                return FakeListenerRegistration()
            },
            liveSessionTimeoutMillis: sessionTimeout,
            dayLoad: Self.빈_하루_읽기
        )

        await vm.실시간_추적을_시작한다()
        try? await Task.sleep(nanoseconds: 150_000_000)

        guard case .on = vm.liveTrackingState else {
            Issue.record("on 이 아니라 \(vm.liveTrackingState) 다")
            return
        }
        #expect(구독_횟수.withLock { $0 } == 1)
        #expect(세션_타이머_횟수.withLock { $0 } == 1)
    }
}
