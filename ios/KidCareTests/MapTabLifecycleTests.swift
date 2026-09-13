import Foundation
import Testing
@testable import KidCare

/// 탭을 옮겼다 돌아와도 지도 화면이 처음 읽기를 반복하지 않는지 본다. 정본은 안드로이드
/// `GuardianMainActivity.showTab`(:329-353) — show/hide 라 `MapTimelineFragment.load` 는
/// 화면이 처음 만들어질 때 한 번뿐이다.
///
/// `하루를_읽는다()` 가 아이 이름·서버 시각을 진짜 `FamilyRepository` 로 읽으므로(주입
/// 안 됨) Firebase 가 구성돼 있어야 한다 — 에뮬레이터를 쓴다(운영에 안 닿는다).
@Suite(.serialized)
@MainActor
struct MapTabLifecycleTests {

    init() async { await EmulatorHarness.start() }

    nonisolated private static func 상태(battery: Int) -> ChildStatusDoc {
        ChildStatusDoc(["lat": 37.0, "lng": 127.0, "battery": battery, "lastSeenAt": Int64(1)])!
    }

    @Test("onAppear 가 여러 번 불려도(탭을 오갈 때마다) 하루 읽기는 한 번뿐이다")
    func 처음_한_번만_읽는다() async {
        let 횟수 = TestCounter()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: RequestLog(defaults: TestDefaults.isolated("MapTabLifecycleTests")),
            dayLoad: { _, _, _ in await 횟수.next(); return (nil, nil) }
        )
        let 첫번째 = vm.처음이면_읽는다()
        let 두번째 = vm.처음이면_읽는다()
        await 첫번째.value
        await 두번째.value
        await vm.처음이면_읽는다().value
        #expect(await 횟수.value == 1)
    }

    @Test("부른 쪽이 취소돼도(탭 전환으로 .task 가 취소되는 경우) 첫 읽기는 끝까지 간다")
    func 부른_쪽이_취소돼도_끝난다() async {
        let 문 = TestGate()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: RequestLog(defaults: TestDefaults.isolated("MapTabLifecycleTests")),
            dayLoad: { _, _, _ in await 문.wait(); return (Self.상태(battery: 42), nil) }
        )
        let 부른_쪽 = Task { @MainActor in await vm.처음이면_읽는다().value }
        부른_쪽.cancel()
        await 문.open()
        await vm.처음이면_읽는다().value
        #expect(vm.상태?.battery == 42)
    }
}
