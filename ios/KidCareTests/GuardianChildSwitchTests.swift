import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// 아이를 바꾸면 `GuardianHomeView` 가 안쪽 `GuardianRootView` 를 `.id(childUid)` 로 새로 만든다. 옛 뷰의
/// `onDisappear` 는 `GuardianRootView.탭을_모두_정리한다` 하나를 부른다. 이 테스트는 그 함수가 다섯 탭 뷰모델의
/// 리스너·명령 추적을 **모두** 떼는지 본다(안드로이드 `recreateTabsForSelectedChild` :288-300 이 프래그먼트를
/// remove 해 `onDestroyView` 를 부르는 자리). 하나라도 빠지면 옛 아이의 리스너가 새 아이 화면 뒤에서 계속 돈다.
@MainActor
struct GuardianChildSwitchTests {

    final class 등록들: Sendable {
        let 지도_명령 = TestListenerRegistration()
        let 관리_명령 = TestListenerRegistration()
        let 관리_설정 = TestListenerRegistration()
        let 예약_목록 = TestListenerRegistration()
        let 예약_설정 = TestListenerRegistration()
        let 장소_목록 = TestListenerRegistration()
        let 알림_목록 = TestListenerRegistration()
        let 보낸_명령 = TestCounter()

        var 전부: [(String, TestListenerRegistration)] {
            [("지도_명령", 지도_명령), ("관리_명령", 관리_명령), ("관리_설정", 관리_설정), ("예약_목록", 예약_목록),
             ("예약_설정", 예약_설정), ("장소_목록", 장소_목록), ("알림_목록", 알림_목록)]
        }
    }

    private static let 멈춘_잠: @Sendable (Int64) async -> Void = { _ in await TestGate().wait() }

    @Test("옛 아이의 다섯 탭을 정리하면 리스너 일곱이 모두 떨어지고, 정리 뒤로는 명령을 더 보내지 않는다")
    func 다섯_탭을_모두_정리한다() async {
        let r = 등록들()
        let childUid = "old-child"
        let d = { (name: String) in TestDefaults.isolated("GuardianChildSwitchTests-\(name)") }

        let map = MapViewModel(
            familyId: "fam", childUid: childUid,
            requestLog: RequestLog(defaults: d("map-log")),
            commandSend: { _, _, _, _ in await r.보낸_명령.next(); return "map-cmd" },
            commandObserve: { _, _, _, _, _ in r.지도_명령 },
            commandSleep: Self.멈춘_잠,
            commandServerNow: { _, _ in 1 },
            liveStatusObserve: { _, _, _, _ in TestListenerRegistration() },
            dayLoad: { _, _, _ in (nil, nil) }
        )
        let control = ControlViewModel(
            familyId: "fam", childUid: childUid,
            requestLog: RequestLog(defaults: d("control-log")),
            alarmMemoStore: AlarmMemoStore(defaults: d("control-memo")),
            commandSend: { _, _, _, _ in await r.보낸_명령.next(); return "control-cmd" },
            commandObserve: { _, _, _, _, _ in r.관리_명령 },
            statusFetch: { _, _ in nil },
            settingsObserve: { _, _, _, _ in r.관리_설정 },
            lockSave: { _, _, _ in },
            serverNow: { _ in 1 },
            deviceNow: { 1 },
            commandSleep: Self.멈춘_잠
        )
        let schedule = ScheduleViewModel(
            familyId: "fam", childUid: childUid,
            syncStore: RuleSyncStore(kind: .schedule, defaults: d("schedule")),
            schedulesObserve: { _, _, _, _ in r.예약_목록 },
            settingsObserve: { _, _, _, _ in r.예약_설정 },
            commandSend: { _, _, _, _ in await r.보낸_명령.next(); return "schedule-cmd" },
            writeSleep: Self.멈춘_잠
        )
        let place = PlaceViewModel(
            familyId: "fam", childUid: childUid,
            syncStore: RuleSyncStore(kind: .place, defaults: d("place")),
            placesObserve: { _, _, _, _ in r.장소_목록 },
            statusFetch: { _, _ in nil },
            commandSend: { _, _, _, _ in await r.보낸_명령.next(); return "place-cmd" },
            writeSleep: Self.멈춘_잠
        )
        let alert = AlertViewModel(
            familyId: "fam", childUid: childUid,
            observe: { _, _, _, _ in r.알림_목록 },
            markRead: { _, _ in }
        )

        // 사용자가 옛 아이로 탭 다섯을 모두 열고, 지도에서 위치를 물은 뒤 아이를 바꾼 상황.
        await map.지금_위치를_확인한다()
        await control.시작한다().value
        schedule.시작한다()
        place.시작한다()
        alert.시작한다()
        let 정리_전_명령 = await r.보낸_명령.value
        #expect(정리_전_명령 == 2)   // 지도 위치 확인 + 관리 탭 소리 조회
        #expect(r.전부.allSatisfy { !$0.1.removed })

        GuardianRootView.탭을_모두_정리한다(map: map, control: control, schedule: schedule, place: place, alert: alert)

        for (이름, 등록) in r.전부 {
            #expect(등록.removed, "\(이름) 리스너가 남았다")
        }
        // 정리 뒤 보임·재시도 신호가 와도(scenePhase 변화가 늦게 도착) 옛 아이로 명령을 새로 쓰지 않는다.
        alert.보임이_바뀌었다(true)
        schedule.다시_알린다()
        place.다시_알린다()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await r.보낸_명령.value == 정리_전_명령)
    }

    // MARK: - 실시간 추적 중 전환(통합 검토 M2)

    /// 보낸 명령을 "아이:종류" 로 적는다.
    final class 명령_기록: Sendable {
        private let 잠금 = OSAllocatedUnfairLock(initialState: [String]())
        var 목록: [String] { 잠금.withLock { $0 } }
        func 적는다(_ uid: String, _ type: String) { 잠금.withLock { $0.append("\(uid):\(type)") } }
    }

    /// 가짜 저장소가 내준 리스너 전부. 이름은 실패 메시지용이다.
    final class 등록_목록: Sendable {
        private let 잠금 = OSAllocatedUnfairLock(initialState: [(String, TestListenerRegistration)]())
        var 전부: [(String, TestListenerRegistration)] { 잠금.withLock { $0 } }
        func 새로(_ 이름: String) -> TestListenerRegistration {
            let 등록 = TestListenerRegistration()
            잠금.withLock { $0.append((이름, 등록)) }
            return 등록
        }
    }

    /// 옛 리스너에 늦게 도착하는 스냅샷을 테스트가 직접 흘리기 위한 콜백 상자.
    final class 늦은_콜백: Sendable {
        let 명령 = TestCallbackBox<(CommandDoc) -> Void>()
        let 상태 = TestCallbackBox<(ChildStatusDoc?) -> Void>()
    }

    /// 실시간 시작 명령은 곧바로 done 을 돌려준다. `시작_문` 을 주면 시작 명령 발행이 그 문에 매달린다.
    private func 실시간_지도(
        _ childUid: String, 명령: 명령_기록, 등록: 등록_목록, 콜백: 늦은_콜백,
        시작_문: TestGate? = nil, 시작_들어감: TestSignal? = nil
    ) -> MapViewModel {
        MapViewModel(
            familyId: "fam", childUid: childUid,
            requestLog: RequestLog(defaults: TestDefaults.isolated("GuardianChildSwitchTests-live-\(childUid)")),
            commandSend: { _, uid, type, _ in
                명령.적는다(uid, type)
                if type == CommandType.startLiveTracking, let 시작_문 {
                    await 시작_들어감?.fire()
                    await 시작_문.wait()
                }
                return "live-cmd"
            },
            commandObserve: { _, _, _, onChange, _ in
                콜백.명령.set(onChange)
                let 등록 = 등록.새로("지도_명령")
                onChange(CommandDoc(id: "live-cmd", ["state": "done"]))
                return 등록
            },
            commandSleep: Self.멈춘_잠,
            commandServerNow: { _, _ in 1 },
            liveStatusObserve: { _, _, onChange, _ in
                콜백.상태.set(onChange)
                return 등록.새로("실시간_상태")
            },
            dayLoad: { _, _, _ in (nil, nil) }
        )
    }

    private func 나머지_탭(
        _ childUid: String, 명령: 명령_기록, 등록: 등록_목록
    ) -> (ControlViewModel, ScheduleViewModel, PlaceViewModel, AlertViewModel) {
        let d = { (name: String) in TestDefaults.isolated("GuardianChildSwitchTests-live-\(name)") }
        let send: @Sendable (String, String, String, [String: String]) async throws -> String = { _, uid, type, _ in
            명령.적는다(uid, type)
            return "cmd"
        }
        let control = ControlViewModel(
            familyId: "fam", childUid: childUid,
            requestLog: RequestLog(defaults: d("control-log")),
            alarmMemoStore: AlarmMemoStore(defaults: d("control-memo")),
            commandSend: send,
            commandObserve: { _, _, _, _, _ in 등록.새로("관리_명령") },
            statusFetch: { _, _ in nil },
            settingsObserve: { _, _, _, _ in 등록.새로("관리_설정") },
            lockSave: { _, _, _ in },
            serverNow: { _ in 1 },
            deviceNow: { 1 },
            commandSleep: Self.멈춘_잠
        )
        let schedule = ScheduleViewModel(
            familyId: "fam", childUid: childUid,
            syncStore: RuleSyncStore(kind: .schedule, defaults: d("schedule")),
            schedulesObserve: { _, _, _, _ in 등록.새로("예약_목록") },
            settingsObserve: { _, _, _, _ in 등록.새로("예약_설정") },
            commandSend: send,
            writeSleep: Self.멈춘_잠
        )
        let place = PlaceViewModel(
            familyId: "fam", childUid: childUid,
            syncStore: RuleSyncStore(kind: .place, defaults: d("place")),
            placesObserve: { _, _, _, _ in 등록.새로("장소_목록") },
            statusFetch: { _, _ in nil },
            commandSend: send,
            writeSleep: Self.멈춘_잠
        )
        let alert = AlertViewModel(
            familyId: "fam", childUid: childUid,
            observe: { _, _, _, _ in 등록.새로("알림_목록") },
            markRead: { _, _ in }
        )
        return (control, schedule, place, alert)
    }

    @Test("실시간 보기가 켜진 채 아이를 바꾸면 실시간 상태 리스너까지 모두 떨어지고, 늦은 스냅샷에도 새 아이로 명령이 가지 않고 꺼진 채다(통합 검토 M2)")
    func 실시간_추적_중에_아이를_바꾼다() async {
        let 명령 = 명령_기록(), 등록 = 등록_목록(), 콜백 = 늦은_콜백()
        let map = 실시간_지도("old-child", 명령: 명령, 등록: 등록, 콜백: 콜백)
        let (control, schedule, place, alert) = 나머지_탭("old-child", 명령: 명령, 등록: 등록)

        // 옛 아이로 탭 다섯을 열고 지도에서 실시간 보기를 켰다.
        await control.시작한다().value
        schedule.시작한다()
        place.시작한다()
        alert.시작한다()
        await map.실시간_추적을_시작한다()
        await eventually { if case .on = map.liveTrackingState { return true } else { return false } }
        let 이름들 = Set(등록.전부.map(\.0))
        #expect(이름들 == ["지도_명령", "실시간_상태", "관리_명령", "관리_설정", "예약_목록", "예약_설정", "장소_목록", "알림_목록"])
        #expect(!(등록.전부.first { $0.0 == "실시간_상태" }?.1.removed ?? true))

        GuardianRootView.탭을_모두_정리한다(map: map, control: control, schedule: schedule, place: place, alert: alert)
        // 아이를 바꾸면 새 아이의 뷰모델이 새로 만들어진다 — 시작하지 않았으니 아무것도 보내지 않아야 한다.
        let 새_지도 = 실시간_지도("new-child", 명령: 명령, 등록: 등록, 콜백: 늦은_콜백())

        #expect(map.liveTrackingState == .off)
        for (이름, 리스너) in 등록.전부 {
            #expect(리스너.removed, "\(이름) 리스너가 남았다")
        }
        // 정리 직전에 줄 섰던 스냅샷이 늦게 도착한다.
        let 등록_수 = 등록.전부.count
        콜백.상태.value?(ChildStatusDoc([
            "lat": 37.0, "lng": 127.0, "accuracy": 8.0, "at": Int64(999_999_999_999), "battery": 50,
            "charging": false, "ringerMode": "normal", "lastSeenAt": Int64(999_999_999_999),
        ]))
        콜백.명령.value?(CommandDoc(id: "live-cmd", ["state": "done"]))
        await eventually { 명령.목록.contains("old-child:\(CommandType.stopLiveTracking)") }
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(map.liveTrackingState == .off)
        #expect(새_지도.liveTrackingState == .off)
        #expect(등록.전부.count == 등록_수, "정리 뒤에 리스너가 새로 붙었다")
        #expect(명령.목록.allSatisfy { $0.hasPrefix("old-child:") }, "\(명령.목록)")
        #expect(명령.목록.filter { $0.contains("live") } == [
            "old-child:\(CommandType.startLiveTracking)", "old-child:\(CommandType.stopLiveTracking)",
        ])
    }

    @Test("실시간 시작 명령이 매달린 채 아이를 바꾸면, 늦게 돌아온 시작은 리스너를 붙이지 않고 추적은 꺼진 채다(통합 검토 M2)")
    func 시작_명령이_매달린_채_아이를_바꾼다() async {
        let 명령 = 명령_기록(), 등록 = 등록_목록(), 콜백 = 늦은_콜백(), 문 = TestGate(), 들어감 = TestSignal()
        let map = 실시간_지도("old-child", 명령: 명령, 등록: 등록, 콜백: 콜백, 시작_문: 문, 시작_들어감: 들어감)
        let (control, schedule, place, alert) = 나머지_탭("old-child", 명령: 명령, 등록: 등록)

        let 시작 = Task { await map.실시간_추적을_시작한다() }
        await 들어감.wait()
        #expect(map.liveTrackingState == .starting)

        GuardianRootView.탭을_모두_정리한다(map: map, control: control, schedule: schedule, place: place, alert: alert)
        let 새_지도 = 실시간_지도("new-child", 명령: 명령, 등록: 등록, 콜백: 늦은_콜백())
        #expect(map.liveTrackingState == .off)

        // 매달렸던 발행이 이제 서버 확인을 받는다.
        await 문.open()
        await 시작.value
        await eventually { 명령.목록.contains("old-child:\(CommandType.stopLiveTracking)") }
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(등록.전부.isEmpty, "늦은 시작이 리스너를 붙였다: \(등록.전부.map(\.0))")
        #expect(map.liveTrackingState == .off)
        #expect(새_지도.liveTrackingState == .off)
        #expect(명령.목록 == ["old-child:\(CommandType.startLiveTracking)", "old-child:\(CommandType.stopLiveTracking)"])
    }
}
