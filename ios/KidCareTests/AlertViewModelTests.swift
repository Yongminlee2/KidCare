import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// 정본은 `AlertFragment.kt`. 줄 번호는 테스트 이름에 적는다.
@MainActor
struct AlertViewModelTests {

    /// 가짜 구독. 콜백을 꺼내 두고 테스트가 스냅샷을 직접 흘린다.
    final class 가짜_구독: Sendable {
        let onChange = TestCallbackBox<([EventDoc], Bool) -> Void>()
        let onError = TestCallbackBox<(Error) -> Void>()
        let registration = TestListenerRegistration()
        private let 횟수_잠금 = OSAllocatedUnfairLock(initialState: 0)
        var 횟수: Int { 횟수_잠금.withLock { $0 } }
        func 불렸다() { 횟수_잠금.withLock { $0 += 1 } }

        func 보낸다(_ docs: [EventDoc], fromCache: Bool = false) { onChange.value?(docs, fromCache) }
    }

    actor 읽음_기록 {
        private(set) var 호출: [[String]] = []
        func 기록(_ ids: [String]) { 호출.append(ids) }
    }

    private func 만든다(
        childUid: String? = "c1",
        구독: 가짜_구독,
        기록: 읽음_기록,
        문: TestGate? = nil,
        실패: Bool = false
    ) -> AlertViewModel {
        AlertViewModel(
            familyId: "fam",
            childUid: childUid,
            observe: { _, _, onChange, onError in
                구독.onChange.set(onChange)
                구독.onError.set(onError)
                구독.불렸다()
                return 구독.registration
            },
            markRead: { _, ids in
                await 기록.기록(ids)
                if let 문 { await 문.wait() }
                if 실패 { throw URLError(.notConnectedToInternet) }
            }
        )
    }

    private func 사건(_ id: String, read: Bool = false) -> EventDoc {
        EventDoc(id: id, type: EventType.placeEnter, at: 1, childUid: "c1", placeName: "학교", read: read)
    }

    private func 잠깐() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    /// 읽음 쓰기가 몇 번 불렸는지로 기다린다. `events` 는 앞 스냅샷과 같은 값일 수 있어 기다림 조건이 못 된다.
    private func 기록을_기다린다(_ 기록: 읽음_기록, 개수: Int) async {
        for _ in 0..<400 {
            if await 기록.호출.count >= 개수 { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("읽음 쓰기가 \(개수)번 불리지 않았다")
    }

    @Test("캐시본은 '불러오는 중', 서버본이어야 '없어요'(:152-158)")
    func 캐시본은_단언하지_않는다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([], fromCache: true)
        await eventually { vm.listLoad == .loading }
        #expect(vm.빈_목록_문구 == String(localized: "list_loading"))
        구독.보낸다([], fromCache: false)
        await eventually { vm.listLoad == .loaded }
        #expect(vm.빈_목록_문구 == String(localized: "alert_empty"))
    }

    @Test("보이는 순간 안 읽은 것만 읽음으로 쓰고, 읽음이 도착해도 살구빛은 남는다(:204-228, 클래스 주석 :34-39)")
    func 살구빛은_연_순간을_붙든다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([사건("a"), 사건("b", read: true)])
        await eventually { vm.events.count == 2 }
        vm.보임이_바뀌었다(true)
        #expect(vm.강조 == ["a"])
        await eventually { !vm.읽음_쓰는_중 }
        #expect(await 기록.호출 == [["a"]])
        구독.보낸다([사건("a", read: true), 사건("b", read: true)])
        await eventually { vm.events.allSatisfy(\.read) }
        #expect(vm.강조 == ["a"])
    }

    @Test("안 보이는 동안에는 쓰지 않는다 — 부모가 본 적 없는 것을 읽었다고 적지 않는다")
    func 숨어_있으면_안_쓴다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([사건("a")])
        await eventually { vm.events.count == 1 }
        await 잠깐()
        #expect(await 기록.호출.isEmpty)
        #expect(vm.강조.isEmpty)
    }

    @Test("떠나면 강조를 비우고, 다음에 열 때는 그 사이 새로 온 것만 살구빛(:197-200, 클래스 주석 :38-39)")
    func 다음엔_새것만() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([사건("a")])
        await eventually { vm.events.count == 1 }
        vm.보임이_바뀌었다(true)
        await eventually { !vm.읽음_쓰는_중 }
        구독.보낸다([사건("a", read: true)])
        await eventually { vm.events.first?.read == true }
        vm.보임이_바뀌었다(false)
        #expect(vm.강조.isEmpty)
        구독.보낸다([사건("c"), 사건("a", read: true)])
        await eventually { vm.events.count == 2 }
        vm.보임이_바뀌었다(true)
        #expect(vm.강조 == ["c"])
        await eventually { !vm.읽음_쓰는_중 }
        #expect(await 기록.호출 == [["a"], ["c"]])
    }

    @Test("보는 동안 새로 온 것도 그 자리에서 읽음이 된다(:159-161)")
    func 보는_동안_온_것() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        vm.보임이_바뀌었다(true)
        구독.보낸다([사건("a")])
        await eventually { vm.강조 == ["a"] && !vm.읽음_쓰는_중 }
        구독.보낸다([사건("n"), 사건("a", read: true)])
        await eventually { vm.강조 == ["a", "n"] && !vm.읽음_쓰는_중 }
        #expect(await 기록.호출 == [["a"], ["n"]])
    }

    @Test("읽음 쓰기가 도는 동안에는 겹쳐 보내지 않고, 끝난 뒤 다음 스냅샷에서 남은 것을 보낸다(:216 markJob?.isActive)")
    func 겹쳐_쓰지_않는다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록(), 문 = TestGate()
        let vm = 만든다(구독: 구독, 기록: 기록, 문: 문)
        vm.시작한다()
        vm.보임이_바뀌었다(true)
        구독.보낸다([사건("a")])
        await eventually { vm.읽음_쓰는_중 }
        구독.보낸다([사건("b"), 사건("a")])
        await eventually { vm.강조 == ["a", "b"] }
        await 잠깐()
        #expect(await 기록.호출 == [["a"]])
        await 문.open()
        await eventually { !vm.읽음_쓰는_중 }
        구독.보낸다([사건("b"), 사건("a", read: true)])
        await 기록을_기다린다(기록, 개수: 2)
        await eventually { !vm.읽음_쓰는_중 }
        #expect(await 기록.호출 == [["a"], ["b"]])
    }

    @Test("읽음 쓰기 실패는 화면에 아무 말도 하지 않는다 — 부모가 한 일이 아니다(:204-210)")
    func 읽음_실패는_조용하다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록, 실패: true)
        vm.시작한다()
        vm.보임이_바뀌었다(true)
        구독.보낸다([사건("a")])
        await eventually { vm.강조 == ["a"] && !vm.읽음_쓰는_중 }
        #expect(await 기록.호출.count == 1)
        #expect(vm.상태_줄 == nil)
        #expect(vm.listLoad == .loaded)
    }

    @Test("구독 오류는 실패 상태와 alert_error_format 한 줄, 빈 자리는 비운다(:142-148)")
    func 구독_오류() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        구독.onError.value?(error)
        await eventually { vm.listLoad == .failed }
        #expect(vm.상태_줄 == String(format: String(localized: "alert_error_format"), errorMessage(error)))
        #expect(vm.빈_목록_문구 == nil)
    }

    @Test("아이가 없으면 구독하지 않고 map_no_child, '불러오는 중'에 갇히지 않는다(:131-137)")
    func 아이가_없으면() {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(childUid: nil, 구독: 구독, 기록: 기록)
        vm.시작한다()
        #expect(구독.횟수 == 0)
        #expect(vm.listLoad == .loaded)
        #expect(vm.상태_줄 == String(localized: "map_no_child"))
        #expect(vm.빈_목록_문구 == String(localized: "alert_empty"))
    }

    @Test("두 번 시작해도 구독은 하나, 정리하면 리스너를 떼고 늦은 스냅샷·다시 시작을 무시한다(:286-297)")
    func 정리() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        vm.시작한다()
        #expect(구독.횟수 == 1)
        vm.보임이_바뀌었다(true)
        vm.정리한다()
        #expect(구독.registration.removed)
        구독.보낸다([사건("a")])
        await 잠깐()
        #expect(vm.events.isEmpty)
        #expect(await 기록.호출.isEmpty)
        vm.시작한다()
        #expect(구독.횟수 == 1)
    }

    // MARK: - 정리 뒤 늦은 콜백·보임 (5단계 통합 검토 M2 와 같은 규율 — 갈래마다 따로 지킨다)

    @Test("정리 뒤 늦게 온 구독 오류는 상태를 바꾸지 않는다 — remove() 직전에 대기열에 오른 콜백")
    func 정리_뒤_늦은_오류() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([], fromCache: false)
        await eventually { vm.listLoad == .loaded }
        vm.정리한다()
        구독.onError.value?(NSError(domain: "test", code: 2))
        await 메인_대기열을_비운다()
        await 잠깐()
        #expect(vm.listLoad == .loaded)
        #expect(vm.상태_줄 == nil)
    }

    @Test("정리 뒤에 보임이 참으로 와도(탭 뷰가 사라진 뒤의 scenePhase 변화) 읽음을 쓰지 않는다")
    func 정리_뒤_보임() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([사건("a")])
        await eventually { vm.events.count == 1 }
        vm.정리한다()
        vm.보임이_바뀌었다(true)
        await 잠깐()
        #expect(await 기록.호출.isEmpty)
        #expect(vm.강조.isEmpty)
        #expect(!vm.읽음_쓰는_중)
    }

    @Test("읽음 쓰기가 매달린 채 정리되면, 늦게 끝나도 새 쓰기도 강조도 만들지 않는다")
    func 정리_뒤_늦은_읽음() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록(), 문 = TestGate()
        let vm = 만든다(구독: 구독, 기록: 기록, 문: 문)
        vm.시작한다()
        vm.보임이_바뀌었다(true)
        구독.보낸다([사건("a")])
        await eventually { vm.읽음_쓰는_중 }
        vm.정리한다()
        구독.보낸다([사건("b"), 사건("a")])
        await 문.open()
        await 잠깐()
        #expect(await 기록.호출 == [["a"]])
        #expect(vm.강조.isEmpty)
        #expect(!vm.읽음_쓰는_중)
        #expect(vm.events.map(\.id) == ["a"])
    }
}
