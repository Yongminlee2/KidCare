import Testing
@testable import KidCare

/// 정본은 안드로이드 `ScheduleSyncStore.kt`·`PlaceSyncStore.kt`.
struct RuleSyncStoreTests {

    @Test("깃발은 저장소에 남아 앱을 다시 켜도 그대로다 — 뒤로 가기를 넘기려고 프로세스 밖에 둔다(ScheduleSyncStore.kt:15-23)")
    func 남는다() {
        let defaults = TestDefaults.isolated("RuleSyncStoreTests")
        #expect(!RuleSyncStore(kind: .schedule, defaults: defaults).pendingSync(childUid: "c"))
        RuleSyncStore(kind: .schedule, defaults: defaults).setPendingSync(childUid: "c", true)
        #expect(RuleSyncStore(kind: .schedule, defaults: defaults).pendingSync(childUid: "c"))
        #expect(!RuleSyncStore(kind: .schedule, defaults: defaults).pendingSync(childUid: "other"))
    }

    @Test("예약 깃발과 장소 깃발은 서로를 지우지 않는다(PlaceSyncStore.kt:12-21)")
    func 따로다() {
        let defaults = TestDefaults.isolated("RuleSyncStoreTests-kind")
        let schedule = RuleSyncStore(kind: .schedule, defaults: defaults)
        let place = RuleSyncStore(kind: .place, defaults: defaults)
        schedule.setPendingSync(childUid: "c", true)
        place.setPendingSync(childUid: "c", true)
        schedule.setPendingSync(childUid: "c", false)
        #expect(place.pendingSync(childUid: "c"))
    }
}
