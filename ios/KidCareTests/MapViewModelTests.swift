import FirebaseFirestore
import Foundation
import Testing
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

        let vm = MapViewModel(familyId: "family", childUid: "child") { _, _, dayKey in
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
        }

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

    nonisolated private static func status(battery: Int) -> ChildStatusDoc {
        ChildStatusDoc([
            "lat": 37.0, "lng": 127.0, "accuracy": 0.0,
            "at": Int64(0), "battery": battery, "charging": false,
            "ringerMode": "normal", "lastSeenAt": Int64(0),
        ])!
    }
}
