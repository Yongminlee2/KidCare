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

        let 기대_문구 = String(format: String(localized: "map_live_active_status"), 15, 42)
        #expect(vm.실시간_상태_문구 == 기대_문구)
        #expect(vm.카메라를_다시_맞춰야_한다 == true)
        #expect(vm.상태?.battery == 42)
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
}
