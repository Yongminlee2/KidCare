import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// 순수 날짜 이동 로직만 본다 — `childUid` 가 `nil` 이라 네트워크를 전혀 타지 않는다
/// (`이전_날로`/`다음_날로` 내부의 `guard let childUid else { return }` 가 곧바로
/// 물러난다). 정본은 안드로이드 `MapTimelineFragment.changeDay`(:848) 다.
///
/// **UI 없이 돈다** — Task 5(명령 왕복)·7(실시간 세션)이 상태 기계를 뷰 밖으로
/// 옮기는 이유가 바로 이것이다(Task 4 브리프 "계획서 표류 정리"): 시뮬레이터를
/// 띄우지 않고도 `MapViewModel` 하나만 만들어 날짜 이동을 검증할 수 있다.
@MainActor
struct MapViewModelDayNavigationTests {

    @Test("오늘로 시작하고, 오늘에서는 다음 날로 갈 수 없다")
    func 오늘에서_시작한다() {
        let vm = MapViewModel(familyId: "family", childUid: nil)
        let 오늘 = DayPicker.todayKey(zone: .current, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
        #expect(vm.dayKey == 오늘)
        #expect(vm.다음_날로_갈_수_있는가 == false)
    }

    @Test("오늘에서 다음 날을 여러 번 눌러도 미래로는 못 간다")
    func 미래로_못_간다() async {
        let vm = MapViewModel(familyId: "family", childUid: nil)
        let 오늘 = vm.dayKey
        await vm.다음_날로()
        #expect(vm.dayKey == 오늘)
        // 한 번만 막고 그다음은 안 막는 버그(예: 플래그를 한 번만 검사)를 잡는다.
        await vm.다음_날로()
        await vm.다음_날로()
        #expect(vm.dayKey == 오늘)
    }

    @Test("이전 날로 갔다가 다음 날로 돌아오면 오늘이고, 다음 날 버튼이 다시 막힌다")
    func 이전_다음_왕복() async {
        let vm = MapViewModel(familyId: "family", childUid: nil)
        let 오늘 = vm.dayKey

        await vm.이전_날로()
        #expect(vm.dayKey == DayPicker.shift(dayKey: 오늘, days: -1))
        #expect(vm.다음_날로_갈_수_있는가 == true)

        await vm.다음_날로()
        #expect(vm.dayKey == 오늘)
        #expect(vm.다음_날로_갈_수_있는가 == false)
    }

    @Test("이틀 전까지도 물러날 수 있다 — 하루만 막혀 있는 게 아니다")
    func 이틀_전으로_물러난다() async {
        let vm = MapViewModel(familyId: "family", childUid: nil)
        let 오늘 = vm.dayKey
        await vm.이전_날로()
        await vm.이전_날로()
        #expect(vm.dayKey == DayPicker.shift(dayKey: 오늘, days: -2))
        #expect(vm.다음_날로_갈_수_있는가 == true)
    }
}

/// 날짜를 바꾸면 실제로 그 날의 경로·타임라인이 바뀌는지, **상태 카드도 함께
/// 다시 읽히는지**(Fix round 1 Important 1)를 에뮬레이터로 확인한다(보안
/// 규칙까지 실제로 태운다). 정본은 안드로이드
/// `MapTimelineFragment.load`(:304)/`changeDay`(:848).
@Suite(.serialized)
struct MapViewModelReloadTests {

    init() async { await EmulatorHarness.start() }

    private func trailData(dayKey: String, placeName: String, at: Int64) -> [String: Any] {
        [
            "dayKey": dayKey,
            "points": [],
            "segments": [[
                "type": "STAY", "startAt": at, "endAt": at,
                "lat": 37.0, "lng": 127.0, "distanceMeters": 0.0,
                "pointCount": 1, "placeName": placeName,
            ]],
            "updatedAt": at,
        ]
    }

    @Test("날짜를 바꾸면 그 날의 경로·타임라인이 갈아끼워지고, 상태 카드(배터리)도 함께 다시 읽힌다")
    @MainActor
    func 날짜를_바꾸면_경로도_상태도_바뀐다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)

        let child = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(
            code: invite.code, uid: child, expectedRole: .child, displayName: "아이"
        )

        let db = Firestore.firestore()
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let childRef = db.collection("families").document(familyId).collection("children").document(child)
        try await childRef.setData([
            "lat": 37.0, "lng": 127.0, "accuracy": 10.0,
            "at": nowMillis, "battery": 55, "charging": false,
            "ringerMode": "normal", "lastSeenAt": nowMillis,
        ])

        let vm = MapViewModel(familyId: familyId, childUid: child)
        let todayKey = vm.dayKey
        let yesterdayKey = DayPicker.shift(dayKey: todayKey, days: -1)
        // 그제는 일부러 문서를 두지 않는다 — "기록 없는 날"로 넘어갔을 때
        // 어제 기록이 눌어붙어 있지 않은지도 같이 본다.

        try await childRef.collection("trails").document(todayKey)
            .setData(trailData(dayKey: todayKey, placeName: "오늘장소", at: nowMillis))
        try await childRef.collection("trails").document(yesterdayKey)
            .setData(trailData(dayKey: yesterdayKey, placeName: "어제장소", at: nowMillis))

        await vm.하루를_읽는다()
        #expect(vm.하루기록?.segments.first?.placeName == "오늘장소")
        #expect(vm.상태?.battery == 55)

        // Fix round 1 Important 1: 날짜 이동도 상태 카드를 다시 읽어야 한다.
        // 서버 값을 실제로 바꿔서 증명한다 — 다시 안 읽었다면 이 값이 안 보였을 것이다.
        try await childRef.updateData(["battery": 77])

        await vm.이전_날로()
        #expect(vm.dayKey == yesterdayKey)
        #expect(vm.하루기록?.segments.first?.placeName == "어제장소")
        #expect(vm.상태?.battery == 77)

        // 기록 없는 그제로 한 번 더 물러난다 — 어제 기록이 그대로 남아 있으면 안
        // 되고, 상태 카드는 이번에도 다시 읽혀야 한다(경로 유무와 무관하다).
        try await childRef.updateData(["battery": 88])
        await vm.이전_날로()
        #expect(vm.하루기록 == nil)
        #expect(vm.타임라인_행.isEmpty)
        #expect(vm.경로_구간.isEmpty)
        #expect(vm.상태?.battery == 88)

        await vm.다음_날로()
        await vm.다음_날로()
        #expect(vm.dayKey == todayKey)
        #expect(vm.하루기록?.segments.first?.placeName == "오늘장소")
        #expect(vm.상태?.battery == 88) // 되돌아와도 다시 읽으므로 마지막에 쓴 값 그대로다
    }
}

/// 빠른 연속 탭에서 늦게 도착한 옛 날짜의 응답이 최신 화면을 덮어쓰지 않는지
/// 본다(Fix round 1 Important 2). Firestore 는 실제로 취소되지 않으므로(1단계
/// 확인), 실제 네트워크로 이 순서를 재현하는 것은 이 환경에서 결정적일 수 없다
/// — `MapViewModel.dayLoad` 에 가짜 구현을 주입해 완료 순서를 직접 정한다.
/// `childUid` 를 실제 값으로 줘도(주입한 `dayLoad` 가 진짜 Firestore 를 대신
/// 하므로) 네트워크를 타지 않는다 — UI 없이, 에뮬레이터 없이 돈다.
@MainActor
struct MapViewModelRaceTests {

    /// 응답이 도착하는 시점을 테스트가 직접 여는 문. `open()` 이 불리기 전까지
    /// `wait()` 는 계속 매달려 있는다.
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

    @Test("어제로 갔다가 곧바로 그제로 넘겨도, 어제 응답이 늦게 와서 그제 화면을 덮어쓰지 않는다")
    func 늦게_온_이전_날짜_응답을_무시한다() async throws {
        let 오늘 = DayPicker.todayKey(zone: .current, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
        let 어제 = DayPicker.shift(dayKey: 오늘, days: -1)
        let 그제 = DayPicker.shift(dayKey: 오늘, days: -2)

        let 어제_문: Gate = Gate()
        let 그제_문: Gate = Gate()

        let vm = MapViewModel(familyId: "family", childUid: "child", dayLoad: { _, _, dayKey in
            switch dayKey {
            case 어제:
                await 어제_문.wait() // 테스트가 열어줄 때까지 응답을 미룬다
                return (Self.status(battery: 11), nil)
            case 그제:
                await 그제_문.wait()
                return (Self.status(battery: 22), nil)
            default:
                return (nil, nil)
            }
        })

        // ◀ 를 빠르게 두 번 누른 것과 같다 — 첫 호출이 어제의 응답을 기다리는
        // 동안(아직 안 열었다) 두 번째 호출이 시작돼 그제로 넘어간다.
        let 첫_탭 = Task { await vm.이전_날로() }
        // 첫 탭이 `await dayLoad(...)` 에서 멈출 시간을 준다 — 그래야 dayKey 가
        // "어제"로 바뀐 뒤에 두 번째 탭이 "그제"를 계산한다.
        await Task.yield()
        let 두번째_탭 = Task { await vm.이전_날로() }
        await Task.yield()

        // 늦게 눌린(그제) 쪽을 먼저 **완전히 끝내고**, 그다음에야 먼저 눌린
        // (어제) 쪽을 푼다 — "이전 요청의 응답이 나중에 도착한다"를 스케줄러
        // 타이밍에 기대지 않고 `await ...value` 로 순서를 확정한다.
        await 그제_문.open()
        await 두번째_탭.value
        await 어제_문.open()
        await 첫_탭.value

        #expect(vm.dayKey == 그제)
        #expect(vm.상태?.battery == 22) // 어제(11)의 늦은 응답이 그제(22)를 덮어쓰지 않았다
    }

    /// Task 4 가 남긴 테스트 구멍을 닫는다. `상태와_그날_경로를_읽는다(generation:)`
    /// 의 두 `catch` 갈래(TrailRepositoryError·일반 오류) 모두 `guard generation
    /// == loadGeneration` 으로 낡은 응답을 버리는데, **성공 경로만** 테스트돼
    /// 있어서 리뷰어가 두 `catch` 갈래의 가드만 지웠을 때도 168개 테스트가 전부
    /// 통과했다 — 실패 경로에 늦게 도착하는 응답을 아무도 테스트하지 않았기
    /// 때문이다. 이 테스트는 그 반대(❮제거→빨강, 복원→초록❯를 실제로 확인했다)를
    /// 증명한다: **낡은 요청이 늦게 실패**해도(최신 요청이 이미 성공한 뒤에)
    /// 오류가 뜨면 안 되고 최신 상태가 그대로 남아야 한다.
    @Test("늦게 실패하는 옛 요청이 최신 성공 결과를 오류로 덮지 않는다 (일반 오류)")
    func 늦게_실패하는_이전_요청은_최신_상태를_오류로_덮지_않는다_일반_오류() async throws {
        let 오늘 = DayPicker.todayKey(zone: .current, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
        let 어제 = DayPicker.shift(dayKey: 오늘, days: -1)
        let 그제 = DayPicker.shift(dayKey: 오늘, days: -2)

        let 어제_문 = Gate()
        struct 가짜_오류: Error {}

        let vm = MapViewModel(familyId: "family", childUid: "child", dayLoad: { _, _, dayKey in
            switch dayKey {
            case 어제:
                await 어제_문.wait() // 그제가 이미 성공한 뒤에야 실패한다
                throw 가짜_오류()
            case 그제:
                return (Self.status(battery: 22), nil)
            default:
                return (nil, nil)
            }
        })

        let 첫_탭 = Task { await vm.이전_날로() } // 어제로 — commandSend 가 아니라 dayLoad 가 걸린다
        await Task.yield()
        let 두번째_탭 = Task { await vm.이전_날로() } // 그제로 — 이 요청이 최신이다
        await 두번째_탭.value // 그제 성공을 먼저 완전히 반영시킨다
        #expect(vm.오류 == nil)
        #expect(vm.상태?.battery == 22)

        await 어제_문.open() // 이제야 낡은(어제) 요청이 실패한다
        await 첫_탭.value

        #expect(vm.dayKey == 그제)
        #expect(vm.오류 == nil) // 낡은 실패가 최신 성공을 오류로 덮으면 안 된다
        #expect(vm.상태?.battery == 22) // 최신 상태도 그대로 남아야 한다
    }

    /// 위와 같은 구멍을 `TrailRepositoryError`(오프라인) 갈래에서도 확인한다 —
    /// `상태와_그날_경로를_읽는다` 의 두 `catch` 는 서로 다른 가드 인스턴스라, 하나만
    /// 지워져도 다른 하나가 지워졌을 때를 대신 잡아주지 않는다.
    @Test("늦게 실패하는 옛 요청이 최신 성공 결과를 오류로 덮지 않는다 (오프라인 오류)")
    func 늦게_실패하는_이전_요청은_최신_상태를_오류로_덮지_않는다_오프라인_오류() async throws {
        let 오늘 = DayPicker.todayKey(zone: .current, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
        let 어제 = DayPicker.shift(dayKey: 오늘, days: -1)
        let 그제 = DayPicker.shift(dayKey: 오늘, days: -2)

        let 어제_문 = Gate()

        let vm = MapViewModel(familyId: "family", childUid: "child", dayLoad: { _, _, dayKey in
            switch dayKey {
            case 어제:
                await 어제_문.wait()
                throw TrailRepositoryError.offline(dayKey: 어제)
            case 그제:
                return (Self.status(battery: 33), nil)
            default:
                return (nil, nil)
            }
        })

        let 첫_탭 = Task { await vm.이전_날로() }
        await Task.yield()
        let 두번째_탭 = Task { await vm.이전_날로() }
        await 두번째_탭.value
        #expect(vm.오류 == nil)
        #expect(vm.상태?.battery == 33)

        await 어제_문.open()
        await 첫_탭.value

        #expect(vm.dayKey == 그제)
        #expect(vm.오류 == nil) // "오프라인"이라는 낡은 실패가 최신 성공을 덮으면 안 된다
        #expect(vm.상태?.battery == 33)
    }

    nonisolated private static func status(battery: Int) -> ChildStatusDoc {
        ChildStatusDoc([
            "lat": 37.0, "lng": 127.0, "accuracy": 0.0,
            "at": Int64(0), "battery": battery, "charging": false,
            "ringerMode": "normal", "lastSeenAt": Int64(0),
        ])!
    }
}

/// '지금 위치 확인' 의 `commandGeneration` 이 늦게 도착하는 콜백·타이머를 실제로
/// 무시하는지, 리스너가 다섯 자리 모두에서 떨어지는지, 대답 기록이 옳은 자리에서만
/// 남는지를 본다. 정본은 안드로이드 `commandGeneration`(`MapTimelineFragment.kt`
/// :374, :409, :444). Firestore 를 전혀 타지 않는다 — `commandSend`·`commandObserve`
/// ·`commandSleep`·`commandServerNow` 넷 다 가짜를 주입해 순서를 테스트가 직접
/// 정한다. `EmulatorHarness.start()` 는 그래도 부른다 — DONE 뒤 재읽기가 실제
/// `FamilyRepository`/`AuthGateway` 호출을 타는데, `FirebaseApp` 이 구성돼 있지
/// 않으면 그 호출 자체가(캐치할 수 없는 Objective-C 예외로) 죽는다(리뷰 I4 와
/// 같은 함정 — 여기서는 이 스위트가 그 함정에 걸리지 않도록 미리 구성해 둔다).
@Suite(.serialized)
@MainActor
struct MapViewModelCommandGenerationTests {

    init() async { await EmulatorHarness.start() }

    /// [MapViewModelRaceTests.Gate] 와 같은 발상 — 테스트가 열어줄 때까지 매달려
    /// 있는 문. 구조체 밖(다른 스위트)에서도 쓰므로 여기서는 파일 스코프로 둔다.
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

    /// 딱 한 번만 발화하는 신호 — "이 지점을 실제로 지났다"를 테스트에 알린다.
    ///
    /// **I2(리뷰)가 지운 것: `Task.yield()` 횟수로 순서를 가정하던 자리.** 두
    /// 프레스를 동시에 굴리면서 "먼저 만든 태스크가 먼저 `commandSend` 에 닿겠지"
    /// 라고 가정했는데, 스케줄러 타이밍에 따라 두 번째 프레스가 먼저 닿을 수
    /// 있다(리뷰가 `-test-iterations 30` 으로 재현) — 그러면 첫 프레스가 "두
    /// 번째 프레스 몫"으로 준비해 둔, 영원히 안 열리는 문에 매달려 스위트 전체가
    /// 멈춘다. 이 신호는 "첫 프레스의 `commandSend` 가 실제로 들어왔다"를 직접
    /// 확인시켜 준다 — 그 신호를 볼 때까지 두 번째 프레스를 아예 만들지 않으므로,
    /// 도착 순서를 가정할 필요가 없어진다.
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

    /// `CommandRepository.observeOne` 이 돌려주는 진짜 `ListenerRegistration` 을
    /// 흉내 낸다. `remove()` 가 실제로 불렸는지도 테스트가 확인할 수 있다(I3 —
    /// 리스너 정리 확인용).
    ///
    /// **`@unchecked Sendable` 을 쓰는 유일한 자리(테스트 전용).** `ListenerRegistration`
    /// 이 `NSObjectProtocol` 을 요구해 반드시 클래스여야 하고(actor 를 못 쓴다),
    /// `remove()` 는 프로토콜이 강제하는 **동기** 함수라(actor 격리로 못 막는다)
    /// 잠금으로 직접 지키는 수밖에 없다 — `FamilyRepository.serverOffsetLock` 과
    /// 같은 `OSAllocatedUnfairLock` 로 실제로 막아 둔 뒤에만 이 한 곳에서
    /// 예외적으로 쓴다(프로덕션 `MapViewModel` 은 여전히 하나도 안 쓴다).
    final class FakeListenerRegistration: NSObject, ListenerRegistration, @unchecked Sendable {
        private let 잠금 = OSAllocatedUnfairLock(initialState: false)
        var removed: Bool { 잠금.withLock { $0 } }
        func remove() { 잠금.withLock { $0 = true } }
    }

    /// 몇 번째 호출인지 센다 — 같은 가짜 클로저가 여러 번 불릴 때 "이번이 몇
    /// 번째냐"로 동작을 갈라야 하는 자리에 쓴다. actor 로 묶은 이유는 `@Sendable`
    /// 클로저 안에서 평범한 지역 `var` 를 세면 Swift 6 가 "동시 실행 코드에서
    /// 캡처된 변수를 건드린다"며 컴파일을 막기 때문이다 — 실제로는(`SingleSignal`
    /// 로 순서를 보장하므로) 동시에 불릴 일이 없지만, 컴파일러는 그걸 모른다.
    private actor CallCounter {
        private var count = 0
        func next() -> Int {
            count += 1
            return count
        }
    }

    /// 하루 읽기는 이 스위트의 관심사가 아니다 — 항상 빈 값으로 즉시 끝낸다(진짜
    /// `FamilyRepository`/`TrailRepository` 호출을 만들지 않는다).
    private static let 빈_하루_읽기: @Sendable (String, String, String) async throws -> (status: ChildStatusDoc?, trail: TrailDoc?) = { _, _, _ in (nil, nil) }

    /// M2(리뷰): `MapViewModel(requestLog:)` 의 기본값(`UserDefaults.standard`)을
    /// 그대로 두면 이 스위트가 시뮬레이터의 **진짜** 앱 컨테이너에
    /// `last_request_at_child` 같은 값을 남긴다 — 리뷰가 실제로 그 흔적을
    /// 찾아냈다. 이 테스트가 `requestLog` 자체를 검사하지 않는 자리에서도 항상
    /// 격리된 `UserDefaults` 스위트를 주입한다.
    private func 격리된_요청_기록() -> RequestLog {
        RequestLog(defaults: UserDefaults(suiteName: "MapViewModelCommandGenerationTests-\(UUID())")!)
    }

    @Test("발행이 늦게 실패해도, 그새 새 요청이 시작됐으면 그 실패가 화면을 건드리지 않는다")
    func 발행이_늦게_실패해도_새_요청이_시작됐으면_무시된다() async throws {
        let 첫_요청_시작됨 = SingleSignal()
        let 첫_요청_문 = Gate()
        struct 가짜_전송_오류: Error {}

        let 호출_순번 = CallCounter()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in
                let n = await 호출_순번.next()
                if n == 1 {
                    await 첫_요청_시작됨.fire()
                    await 첫_요청_문.wait() // 두 번째 요청이 이미 끝난 뒤에야 실패한다
                    throw 가짜_전송_오류()
                }
                return "cmd-2"
            },
            commandObserve: { _, _, _, _, _ in FakeListenerRegistration() },
            // 발행 대기(15초)·응답 대기(60초) 둘 다 이 테스트에서는 승패에
            // 끼어들 필요가 없다 — 실제 전송(commandSend)이 항상 먼저 끝나거나
            // 던지므로, 시간 제한 쪽은 영원히 안 열리는 문에 매달아 둔다.
            commandSleep: { _ in await Gate().wait() },
            dayLoad: Self.빈_하루_읽기
        )

        let 첫_탭 = Task { await vm.지금_위치를_확인한다() }
        // I2(리뷰): 도착 순서를 가정하지 않는다 — 첫 프레스의 commandSend 가
        // 실제로 시작됐다는 신호를 직접 기다린 뒤에야 두 번째 프레스를 만든다.
        await 첫_요청_시작됨.wait()
        let 두번째_탭 = Task { await vm.지금_위치를_확인한다() }
        await 두번째_탭.value // 두 번째 요청은 곧바로 성공해 delivering 이 된다

        #expect(vm.commandProgress == .delivering)
        #expect(vm.오류 == nil)

        await 첫_요청_문.open() // 이제야 낡은(첫) 요청이 실패한다
        await 첫_탭.value

        // 세대가 이미 낡아 첫 요청의 실패가 화면에 아무 영향도 못 준다 — 두 번째
        // 요청의 결과(delivering)가 그대로 남아 있어야 한다.
        #expect(vm.commandProgress == .delivering)
        #expect(vm.오류 == nil)
    }

    @Test("응답을 기다리는 중 새 요청이 시작되면, 먼저 눌렀던 요청의 60초 무응답 타이머는 화면을 건드리지 않는다")
    func 응답_대기_중_새_요청이_시작되면_이전_타이머는_무시된다() async throws {
        let 첫_요청_타이머_시작됨 = SingleSignal()
        let 두번째_타이머_시작됨 = SingleSignal()
        let 첫_요청_타이머_문 = Gate()
        let sendTimeout: Int64 = 111
        let answerTimeout: Int64 = 222

        let 타이머_호출_순번 = CallCounter()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, _, _ in FakeListenerRegistration() },
            commandSleep: { millis in
                guard millis == answerTimeout else {
                    // 발행 대기(sendTimeout) 쪽은 절대 이기면 안 된다 — commandSend
                    // 가 늘 즉시 끝나므로, 이 문을 매번 새로 만들어 영원히 열지
                    // 않는다.
                    await Gate().wait()
                    return
                }
                let n = await 타이머_호출_순번.next()
                if n == 1 {
                    await 첫_요청_타이머_시작됨.fire()
                    await 첫_요청_타이머_문.wait()
                } else {
                    await 두번째_타이머_시작됨.fire()
                    await Gate().wait() // 두 번째 요청의 타이머는 이 테스트 동안 울리지 않는다
                }
            },
            sendTimeoutMillis: sendTimeout,
            answerTimeoutMillis: answerTimeout,
            commandServerNow: { _, _ in 0 },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.지금_위치를_확인한다() // 첫 요청 — delivering 이 되고 60초 타이머가 걸린다
        await 첫_요청_타이머_시작됨.wait() // 타이머 태스크가 실제로 sleep(...) 안에서 멈출 때까지 기다린다
        #expect(vm.commandProgress == .delivering)

        await vm.지금_위치를_확인한다() // 다시 누른다 — 세대가 올라가고 새 타이머가 걸린다
        await 두번째_타이머_시작됨.wait()
        #expect(vm.commandProgress == .delivering)

        await 첫_요청_타이머_문.open() // 첫 요청의 시간 초과를 이제 발생시킨다
        // handleCommandTimeout 이 이제 async 다(C1) — commandServerNow 를 기다린 뒤
        // 세대를 다시 확인하는 나머지 부분이 실행될 시간을 준다.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 낡은 세대의 시간 초과가 두 번째 요청의 화면(delivering)을 덮으면 안 된다.
        #expect(vm.commandProgress == .delivering)
    }

    /// **C1(리뷰).** `handleCommandTimeout` 이 이제 시간 초과가 벌어진 순간 서버
    /// 시각을 새로 잰다 — 그 `await` 가 진짜 정지점이라, 응답을 기다리는 도중이
    /// 아니라 **시간 초과 처리 자체가 진행되는 도중에도** 새 요청이 끼어들 수
    /// 있다. 세대 재확인이 그 자리를 막는다는 것을 실제로 지워서 증명한다.
    @Test("시간 초과가 서버 시각을 재는 동안 새 요청이 시작되면, 그 시간 초과는 화면을 건드리지 않는다 (C1)")
    func 시간초과가_서버시각을_재는_동안_새_요청이_시작되면_무시된다() async throws {
        let 서버시각_시작됨 = SingleSignal()
        let 서버시각_문 = Gate()

        let 타이머_호출_순번 = CallCounter()
        let answerTimeout: Int64 = 222

        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, _, _ in FakeListenerRegistration() },
            commandSleep: { millis in
                guard millis == answerTimeout else { await Gate().wait(); return }
                let n = await 타이머_호출_순번.next()
                if n == 1 { return } // 첫 요청의 60초는 즉시 지나간다 — 경합의 핵심은 그 다음(서버 시각) 단계다
                await Gate().wait() // 두 번째 요청의 타이머는 이 테스트 동안 울리지 않는다
            },
            answerTimeoutMillis: answerTimeout,
            commandServerNow: { _, _ in
                await 서버시각_시작됨.fire()
                await 서버시각_문.wait()
                return 555
            },
            dayLoad: Self.빈_하루_읽기
        )

        await vm.지금_위치를_확인한다() // 첫 요청 — 60초가 즉시 지나 서버 시각을 재는 중이다
        await 서버시각_시작됨.wait()
        #expect(vm.commandProgress == .delivering) // 아직 응답 전이다

        await vm.지금_위치를_확인한다() // 다시 누른다 — 세대가 올라간다
        #expect(vm.commandProgress == .delivering)

        await 서버시각_문.open() // 이제야 첫 요청의 시간 초과가 서버 시각을 받는다
        // handleCommandTimeout 이 서버 시각을 받은 뒤 세대를 다시 확인하는 나머지가
        // 실행될 시간을 준다.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 세대가 이미 낡아 첫 요청의 시간 초과가 두 번째 요청의 화면(delivering)을
        // 덮지 않는다 — 이 `guard` 를 지우면 이 자리에서 빨간불이 된다(직접 확인함).
        #expect(vm.commandProgress == .delivering)
    }

    @Test(".queued — 발행이 15초 안에 서버 확인을 못 받으면 실패가 아니라 대기다")
    func 발행이_시간_안에_못_끝나면_queued_다() async throws {
        let sendTimeout: Int64 = 111
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in await Gate().wait(); return "never" }, // 영원히 안 끝난다
            commandObserve: { _, _, _, _, _ in FakeListenerRegistration() },
            commandSleep: { millis in
                guard millis == sendTimeout else { await Gate().wait(); return }
                // 발행 대기는 즉시 시간 초과되게 한다.
            },
            sendTimeoutMillis: sendTimeout,
            dayLoad: Self.빈_하루_읽기
        )

        await vm.지금_위치를_확인한다()
        #expect(vm.commandProgress == .queued)
        #expect(vm.명령_상태_문구 == String(localized: "control_command_queued"))
    }

    @Test("FAILED 는 error 필드로 문구가 갈린다 — locate_no_fix 만 다른 문구고 나머지는 공통 실패 문구다")
    func failed_문구가_에러코드로_갈린다() async throws {
        for (rawError, expectedKey) in [
            (CommandType.errorNoFix, "map_locate_no_fix"),
            ("무언가_다른_이유", "control_error_child_failed"),
            ("", "control_error_child_failed"),
        ] {
            let vm = MapViewModel(
                familyId: "family", childUid: "child",
                requestLog: 격리된_요청_기록(),
                commandSend: { _, _, _, _ in "cmd" },
                commandObserve: { _, _, _, onChange, _ in
                    onChange(CommandDoc(id: "cmd", ["state": "failed", "error": rawError]))
                    return FakeListenerRegistration()
                },
                commandSleep: { _ in await Gate().wait() },
                dayLoad: Self.빈_하루_읽기
            )
            await vm.지금_위치를_확인한다()
            // onChange 가 handleCommandChange 를 Task { @MainActor in ... } 로
            // 건너가 부르므로(리스너 콜백은 격리되지 않은 자리에서 불린다) 한 턴
            // 흘려보내야 반영된다.
            try? await Task.sleep(nanoseconds: 100_000_000)
            #expect(
                vm.commandProgress == .failed(String(localized: String.LocalizationValue(expectedKey))),
                "error=\(rawError) 일 때 \(expectedKey) 를 기대했다"
            )
        }
    }

    @Test("무응답 문구는 마지막 신호 문구를 포함한다 — 이게 없었다면 C1 을 못 잡았다")
    func 무응답_문구는_마지막_신호를_포함한다() async throws {
        let answerTimeout: Int64 = 111
        // 상태 문서가 있는 채로 시작해야 StatusCard.lastSignal 이 .never 가 아닌
        // 실제 경과를 계산한다 — 서버 시각(commandServerNow)을 신호보다 5분
        // 뒤로 줘서 "5분 전"이 나오게 한다.
        let 신호_시각: Int64 = 1_800_000_000_000
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, _, _ in FakeListenerRegistration() },
            commandSleep: { millis in
                // 발행 대기(15초 기본값) 쪽은 절대 이기면 안 된다 — 안 그러면
                // commandSend("cmd")와 진짜 경합이 되어 이 테스트가 흔들린다.
                guard millis == answerTimeout else { await Gate().wait(); return }
            },
            answerTimeoutMillis: answerTimeout,
            commandServerNow: { _, _ in 신호_시각 + 5 * 60_000 },
            dayLoad: { _, _, _ in
                (ChildStatusDoc([
                    "lat": 37.0, "lng": 127.0, "accuracy": 0.0,
                    "at": Int64(0), "battery": 50, "charging": false,
                    "ringerMode": "normal", "lastSeenAt": 신호_시각,
                ])!, nil)
            }
        )

        await vm.하루를_읽는다() // 상태 문서를 채워 둔다(실제 화면 진입과 같은 순서)
        await vm.지금_위치를_확인한다()
        try? await Task.sleep(nanoseconds: 100_000_000) // commandSleep({})이 즉시 끝나고, 뒤이은 serverNow 도 즉시 끝난다 — 한 턴 정도만 흘려보내면 된다

        guard case .timedOut(let lastSeen) = vm.commandProgress else {
            Issue.record("timedOut 이 아니라 \(String(describing: vm.commandProgress)) 다")
            return
        }
        let 신호_문구 = String(format: String(localized: "control_last_seen_format"), lastSignalText(lastSeen))
        let 기대_문구 = String(format: String(localized: "control_command_timeout_format"), 신호_문구)
        #expect(vm.명령_상태_문구 == 기대_문구)
        #expect(vm.명령_상태_문구?.contains(lastSignalText(lastSeen)) == true)
    }

    @Test("아이 폰의 대답은 done·failed 에서만 기록되고, 시간 초과에서는 기록되지 않는다")
    func 대답_기록은_done_failed에서만_시간초과에서는_안된다() async throws {
        func freshLog() -> RequestLog {
            RequestLog(defaults: UserDefaults(suiteName: "MapViewModelCommandGenerationTests-\(UUID())")!)
        }

        // done
        do {
            let log = freshLog()
            let vm = MapViewModel(
                familyId: "family", childUid: "child", requestLog: log,
                commandSend: { _, _, _, _ in "cmd" },
                commandObserve: { _, _, _, onChange, _ in
                    onChange(CommandDoc(id: "cmd", ["state": "done"]))
                    return FakeListenerRegistration()
                },
                commandSleep: { _ in await Gate().wait() },
                dayLoad: Self.빈_하루_읽기
            )
            await vm.지금_위치를_확인한다()
            try? await Task.sleep(nanoseconds: 100_000_000) // handleCommandChange 가 Task 로 건너간다
            #expect(log.lastAnswerAt(childUid: "child") > 0)
        }

        // failed
        do {
            let log = freshLog()
            let vm = MapViewModel(
                familyId: "family", childUid: "child", requestLog: log,
                commandSend: { _, _, _, _ in "cmd" },
                commandObserve: { _, _, _, onChange, _ in
                    onChange(CommandDoc(id: "cmd", ["state": "failed", "error": "locate_no_fix"]))
                    return FakeListenerRegistration()
                },
                commandSleep: { _ in await Gate().wait() },
                dayLoad: Self.빈_하루_읽기
            )
            await vm.지금_위치를_확인한다()
            try? await Task.sleep(nanoseconds: 100_000_000) // handleCommandChange 가 Task 로 건너간다
            #expect(log.lastAnswerAt(childUid: "child") > 0)
        }

        // 시간 초과 — 절대 기록되면 안 된다(브리프 규칙 5, DisconnectRule 이 이 값에 기댄다)
        do {
            let log = freshLog()
            let vm = MapViewModel(
                familyId: "family", childUid: "child", requestLog: log,
                commandSend: { _, _, _, _ in "cmd" },
                commandObserve: { _, _, _, _, _ in FakeListenerRegistration() },
                commandSleep: { millis in
                    guard millis == 111 else { await Gate().wait(); return } // 발행 대기 쪽은 절대 이기지 않는다
                },
                answerTimeoutMillis: 111,
                commandServerNow: { _, _ in 0 },
                dayLoad: Self.빈_하루_읽기
            )
            await vm.지금_위치를_확인한다()
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard case .timedOut = vm.commandProgress else {
                Issue.record("timedOut 이 아니라 \(String(describing: vm.commandProgress)) 다")
                return
            }
            #expect(log.lastAnswerAt(childUid: "child") == 0)
        }
    }

    @Test("리스너는 완료에서 뗀다")
    func 리스너는_완료에서_뗀다() async throws {
        let listener = FakeListenerRegistration()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "done"]))
                return listener
            },
            commandSleep: { _ in await Gate().wait() },
            dayLoad: Self.빈_하루_읽기
        )
        await vm.지금_위치를_확인한다()
        try? await Task.sleep(nanoseconds: 100_000_000) // handleCommandChange 가 Task 로 건너간다
        #expect(listener.removed)
    }

    @Test("리스너는 실패에서 뗀다")
    func 리스너는_실패에서_뗀다() async throws {
        let listener = FakeListenerRegistration()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in
                onChange(CommandDoc(id: "cmd", ["state": "failed", "error": "locate_no_fix"]))
                return listener
            },
            commandSleep: { _ in await Gate().wait() },
            dayLoad: Self.빈_하루_읽기
        )
        await vm.지금_위치를_확인한다()
        try? await Task.sleep(nanoseconds: 100_000_000) // handleCommandChange 가 Task 로 건너간다
        #expect(listener.removed)
    }

    @Test("리스너는 시간 초과에서 뗀다")
    func 리스너는_시간초과에서_뗀다() async throws {
        let listener = FakeListenerRegistration()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, _, _ in listener },
            commandSleep: { millis in
                guard millis == 111 else { await Gate().wait(); return } // 발행 대기 쪽은 절대 이기지 않는다
            },
            answerTimeoutMillis: 111,
            commandServerNow: { _, _ in 0 },
            dayLoad: Self.빈_하루_읽기
        )
        await vm.지금_위치를_확인한다()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(listener.removed)
    }

    @Test("리스너는 새 요청이 시작되면 이전 것을 뗀다")
    func 리스너는_새_요청에서_이전_것을_뗀다() async throws {
        let 첫_리스너 = FakeListenerRegistration()
        // `commandObserve` 는(진짜 `CommandRepository.observeOne` 처럼) 동기 함수라
        // 액터 기반 `CallCounter` 를 못 쓴다 — 잠금으로 직접 센다.
        let 호출_수 = OSAllocatedUnfairLock(initialState: 0)
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, _, _ in
                let n = 호출_수.withLock { $0 += 1; return $0 }
                return n == 1 ? 첫_리스너 : FakeListenerRegistration()
            },
            commandSleep: { _ in await Gate().wait() },
            dayLoad: Self.빈_하루_읽기
        )
        await vm.지금_위치를_확인한다()
        #expect(!첫_리스너.removed)
        await vm.지금_위치를_확인한다() // 다시 누른다
        #expect(첫_리스너.removed)
    }

    @Test("리스너는 화면이 사라지면 뗀다")
    func 리스너는_화면이_사라지면_뗀다() async throws {
        let listener = FakeListenerRegistration()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: 격리된_요청_기록(),
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, _, _ in listener },
            commandSleep: { _ in await Gate().wait() },
            dayLoad: Self.빈_하루_읽기
        )
        await vm.지금_위치를_확인한다()
        #expect(!listener.removed)
        vm.명령_추적을_정리한다()
        #expect(listener.removed)
    }
}
