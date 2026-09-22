import CoreLocation
import Foundation
import Testing
import UIKit
@testable import KidCare

/// 정본 `child/ConditionWatcher.kt`. 문턱 둘(:173 15 / :176 20)과 "한 번만"(:100-107·:123-142),
/// 그리고 **아무것도 안 달라졌으면 Firestore 를 한 번도 안 건드린다**(:71-74)를 고정한다.
@MainActor
struct ConditionWatcherTests {

    private func 새_저장소() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "조건감시-\(UUID().uuidString)")!
        return defaults
    }

    /// 쓴 이벤트를 모으는 가짜. 2단계 `PlaceWatcherTests` 의 가짜와 같은 모양이다.
    ///
    /// 넘길 때 `기록부.add` 같은 **메서드 참조를 쓰지 않는다** — 부분 적용된 메서드는 인스턴스를
    /// 함께 들고 나가려 해서 Swift 6 이 "non-Sendable 이 주 액터 밖으로 못 나간다"고 막는다.
    /// 그 자리에서 만든 클로저는 주 액터 안에 남으므로 2단계 가짜와 같은 모양으로 적는다.
    private final class 기록 {
        var docs: [EventDoc] = []
    }

    private let 정상 = ChildPermissions.Snapshot(
        authorization: .authorizedAlways, accuracy: .fullAccuracy, backgroundRefresh: .available)

    @Test("배터리 15% 아래로 처음 내려가면 한 번 (:173)")
    func 배터리_한_번() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: { _, doc in 기록부.docs.append(doc) })
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 1_000)
        #expect(기록부.docs.count == 1)
        #expect(기록부.docs[0].type == EventType.lowBattery)
        #expect(기록부.docs[0].at == 1_000)
        #expect(기록부.docs[0].childUid == "C")
        // 같은 상태가 이어지면 아무것도 안 나간다 — 쓰기도 읽기도 0.
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 12, permissions: 정상, now: 2_000)
        #expect(기록부.docs.count == 1)
    }

    @Test("20% 위로 충전되면 다시 한 번 알릴 수 있게 풀린다 (:176, 히스테리시스)")
    func 배터리_풀림() async throws {
        let 기록부 = 기록()
        let defaults = 새_저장소()
        let watcher = ConditionWatcher(defaults: defaults, addEvent: { _, doc in 기록부.docs.append(doc) })
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 1)
        // 19% 는 아직 안 풀린다 — 14↔15 를 오가는 폰이 경고를 계속 올리는 것을 막는 그 간격이다.
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 19, permissions: 정상, now: 2)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 3)
        #expect(기록부.docs.count == 1)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 20, permissions: 정상, now: 4)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 5)
        #expect(기록부.docs.count == 2)
    }

    @Test("배터리를 못 읽으면(-1) 아무 판단도 안 한다 (:96-98)")
    func 배터리_모름() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: { _, doc in 기록부.docs.append(doc) })
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: -1, permissions: 정상, now: 1)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 0, permissions: 정상, now: 2)
        #expect(기록부.docs.isEmpty)
    }

    @Test("권한이 꺼지면 permission_off 하나. 새 EventType 을 만들지 않는다 (판정 기록 7)")
    func 권한_한_번() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: { _, doc in 기록부.docs.append(doc) })
        var 꺼짐 = 정상
        꺼짐.authorization = .authorizedWhenInUse
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 10)
        #expect(기록부.docs.count == 1)
        #expect(기록부.docs[0].type == EventType.permissionOff)
        // detail 은 `event_detail_permission`(%1$s 에 권한 이름)이다 — 부모 화면이 이미 읽는 키다.
        #expect(기록부.docs[0].detail.contains(String(localized: "ios_child_perm_always_title")))
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 20)
        #expect(기록부.docs.count == 1)
    }

    @Test("여럿이 한꺼번에 꺼져도 문서는 하나다 (:119-121)")
    func 여럿이_하나() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: { _, doc in 기록부.docs.append(doc) })
        var 꺼짐 = 정상
        꺼짐.authorization = .denied
        꺼짐.accuracy = .reducedAccuracy
        꺼짐.backgroundRefresh = .denied
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 10)
        #expect(기록부.docs.count == 1)
    }

    @Test("다시 켠 것은 기억만 갱신하고 알리지 않는다 — 소음이 아니라 정상 복귀다 (:115-117)")
    func 다시_켜면_조용() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: { _, doc in 기록부.docs.append(doc) })
        var 꺼짐 = 정상
        꺼짐.backgroundRefresh = .denied
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 10)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 정상, now: 20)
        #expect(기록부.docs.count == 1)
        // 다시 꺼지면 그때는 또 알린다(집합이 다시 늘어난 순간이다).
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 30)
        #expect(기록부.docs.count == 2)
    }

    @Test("프로세스가 죽어도 '이미 알렸다'가 남는다 — 같은 저장소로 새로 만들어 본다 (:50-56)")
    func 프로세스_밖() async throws {
        let defaults = 새_저장소()
        let 첫번째 = 기록()
        try await ConditionWatcher(defaults: defaults, addEvent: { _, doc in 첫번째.docs.append(doc) })
            .check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 1)
        #expect(첫번째.docs.count == 1)
        let 두번째 = 기록()
        try await ConditionWatcher(defaults: defaults, addEvent: { _, doc in 두번째.docs.append(doc) })
            .check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 2)
        #expect(두번째.docs.isEmpty, "재시작할 때마다 같은 경고가 새로 올라가면 안 된다")
    }

    @Test("표시를 쓰기보다 먼저 한다 — 쓰기가 실패해도 같은 경고가 큐에 쌓이지 않는다 (:58-62)")
    func 쓰기_실패() async throws {
        struct 터짐: Error {}
        let defaults = 새_저장소()
        final class 횟수 { var 값 = 0 }
        let 시도 = 횟수()
        let watcher = ConditionWatcher(defaults: defaults, addEvent: { _, _ in 시도.값 += 1; throw 터짐() })
        await #expect(throws: (any Error).self) {
            try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 1)
        }
        // 두 번째 검사는 이미 "알렸다"로 기억돼 있어 쓰기를 다시 시도하지 않는다.
        try? await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 2)
        #expect(시도.값 == 1)
    }

    @Test("저전력 모드는 이벤트를 만들지 않는다 (§8.3 — BATTERY_UNRESTRICTED 를 뺀 것과 같은 판단)")
    func 저전력은_조용() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: { _, doc in 기록부.docs.append(doc) })
        // 감시 목록에 아예 없다는 것을 타입으로 고정한다.
        #expect(!ChildPermissions.Item.allCases.map(\.rawValue).contains("lowPower"))
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 정상, now: 1)
        #expect(기록부.docs.isEmpty)
    }
}
