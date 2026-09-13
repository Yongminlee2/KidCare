import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `guardian/AlarmMemoStore.kt`.
struct AlarmMemoStoreTests {

    private let 하루: Int64 = 24 * 60 * 60 * 1000

    private func 만든다(_ clock: TestClock) -> AlarmMemoStore {
        AlarmMemoStore(defaults: TestDefaults.isolated("AlarmMemoStoreTests"), now: { clock.value })
    }

    @Test("보낸 직후에는 아직 확정되지 않은 기억이다")
    func 보내면_대기() {
        let store = 만든다(TestClock(1_000))
        store.recordSent(childUid: "a", minuteOfDay: 450, label: "학원")
        #expect(store.memo(childUid: "a") == AlarmMemo(minuteOfDay: 450, label: "학원", confirmed: false))
    }

    @Test("done 이 오면 확정된다")
    func 확정() {
        let store = 만든다(TestClock(1_000))
        store.recordSent(childUid: "a", minuteOfDay: 420, label: "")
        store.recordConfirmed(childUid: "a")
        #expect(store.memo(childUid: "a")?.confirmed == true)
    }

    @Test("기록이 없으면 늦게 온 done 이 기억을 되살리지 않는다(:63-66)")
    func 없는_기억은_되살리지_않는다() {
        let store = 만든다(TestClock(1_000))
        store.recordConfirmed(childUid: "a")
        #expect(store.memo(childUid: "a") == nil)
    }

    @Test("24시간이 지나면 사라진다 — 원격 알람은 어느 시각을 골라도 24시간 안에 지난다(:25-32)")
    func 하루가_지나면_사라진다() {
        let clock = TestClock(1_000)
        let store = 만든다(clock)
        store.recordSent(childUid: "a", minuteOfDay: 420, label: "")
        clock.advance(하루 - 1)
        #expect(store.memo(childUid: "a") != nil)
        clock.advance(1)
        #expect(store.memo(childUid: "a") == nil)
    }

    @Test("지우면 사라지고, 아이마다 따로 기억한다")
    func 지우기와_아이별() {
        let store = 만든다(TestClock(1_000))
        store.recordSent(childUid: "a", minuteOfDay: 420, label: "")
        store.recordSent(childUid: "b", minuteOfDay: 480, label: "")
        store.clear(childUid: "a")
        #expect(store.memo(childUid: "a") == nil)
        #expect(store.memo(childUid: "b")?.minuteOfDay == 480)
    }
}
