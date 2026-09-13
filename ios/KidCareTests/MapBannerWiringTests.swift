import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 지도 탭이 대답을 적은 순간 배너가 다시 판정되는지, 그리고 물은 뒤 쓰인 상태 문서를
/// 대답으로 치는지(안드로이드 `MapTimelineFragment.kt:750-757`) 본다. `하루를_읽는다()` 가
/// 진짜 `FamilyRepository.serverNow` 를 부르므로 에뮬레이터를 쓴다.
@Suite(.serialized)
@MainActor
struct MapBannerWiringTests {

    init() async { await EmulatorHarness.start() }

    nonisolated private static func 상태(lastSeenAt: Int64) -> ChildStatusDoc {
        ChildStatusDoc(["lat": 37.0, "lng": 127.0, "battery": 50, "lastSeenAt": lastSeenAt])!
    }

    @Test("명령이 failed 로 끝나면(실패도 대답이다) 대답을 적고 배너 판정을 곧바로 부른다")
    func 실패_대답이_배너를_부른다() async {
        let log = RequestLog(defaults: TestDefaults.isolated("MapBannerWiringTests"))
        let 콜백 = TestCallbackBox<(CommandDoc) -> Void>()
        let vm = MapViewModel(
            familyId: "family", childUid: "child", requestLog: log,
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in 콜백.set(onChange); return TestListenerRegistration() },
            commandSleep: { _ in await TestGate().wait() },
            dayLoad: { _, _, _ in (nil, nil) }
        )
        var 불린_횟수 = 0
        vm.대답이_기록되면 = { 불린_횟수 += 1 }

        await vm.지금_위치를_확인한다()
        콜백.value?(CommandDoc(id: "cmd", ["state": CommandState.failed, "error": "x"]))
        await eventually { 불린_횟수 == 1 }
        #expect(log.lastAnswerAt(childUid: "child") >= log.lastRequestAt(childUid: "child"))
    }

    @Test("물어본 뒤에 쓰인 상태 문서는 대답으로 친다")
    func 물은_뒤_상태는_대답이다() async {
        let log = RequestLog(defaults: TestDefaults.isolated("MapBannerWiringTests"))
        log.recordRequest("child")
        let 물은_시각 = log.lastRequestAt(childUid: "child")
        let vm = MapViewModel(
            familyId: "family", childUid: "child", requestLog: log,
            dayLoad: { _, _, _ in (Self.상태(lastSeenAt: 물은_시각 + 5_000), nil) }
        )
        var 불린_횟수 = 0
        vm.대답이_기록되면 = { 불린_횟수 += 1 }
        await vm.하루를_읽는다()
        #expect(log.lastAnswerAt(childUid: "child") >= 물은_시각)
        #expect(불린_횟수 >= 1)
    }

    @Test("물어보기 전에 쓰인 상태 문서는 대답이 아니다")
    func 물기_전_상태는_대답이_아니다() async {
        let log = RequestLog(defaults: TestDefaults.isolated("MapBannerWiringTests"))
        log.recordRequest("child")
        let 물은_시각 = log.lastRequestAt(childUid: "child")
        let vm = MapViewModel(
            familyId: "family", childUid: "child", requestLog: log,
            dayLoad: { _, _, _ in (Self.상태(lastSeenAt: 물은_시각 - 60_000), nil) }
        )
        var 불린_횟수 = 0
        vm.대답이_기록되면 = { 불린_횟수 += 1 }
        await vm.하루를_읽는다()
        #expect(log.lastAnswerAt(childUid: "child") == 0)
        #expect(불린_횟수 == 0)
    }
}
