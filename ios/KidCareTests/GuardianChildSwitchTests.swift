import FirebaseFirestore
import Foundation
import Testing
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
}
