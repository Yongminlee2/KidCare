import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// 설계서 §10.2. **이 파일이 지키는 계약은 "버튼이 흐리다"가 아니라
/// "`commands/` 문서가 하나도 안 생긴다"다.** 흐린 버튼을 우회하는 길(스크린 리더, 키보드,
/// 다음 사람이 뷰를 고치는 것)은 눈에 안 보이기 때문이다(판정 기록 4).
///
/// **안드로이드 갈래를 먼저 본다.** 보호자 앱은 안드로이드 아이에게 지금과 한 글자도 다르게
/// 굴면 안 된다(주인 판정) — 잘못 잠근 안드로이드 아이는 멀쩡히 되던 기능이 이유 없이
/// 사라지는 일이고, 그쪽이 훨씬 나쁜 틀림이다.
@MainActor
struct GuardianPlatformGateTests {

    private func 저장소(_ 값: [String: ChildPlatform]) -> ChildPlatformStore {
        let s = ChildPlatformStore(defaults: UserDefaults(suiteName: "GuardianPlatformGateTests-\(UUID())")!)
        for (uid, p) in 값 { s.remember(childUid: uid, platform: p) }
        return s
    }

    private func 격리된_요청_기록() -> RequestLog {
        RequestLog(defaults: UserDefaults(suiteName: "GuardianPlatformGateTests-log-\(UUID())")!)
    }

    private func 격리된_알람_기억() -> AlarmMemoStore {
        AlarmMemoStore(defaults: UserDefaults(suiteName: "GuardianPlatformGateTests-memo-\(UUID())")!)
    }

    /// 보낸 명령을 세는 가짜. **한 번도 안 불리는 것**이 합격이다.
    /// Swift 6 가 `@Sendable` 클로저 안의 캡처 변수를 막으므로 잠금을 쓴다
    /// (`LiveTrackingTests.CommandChangeBox` 와 같은 사정).
    final class 보낸_것: @unchecked Sendable {
        private let 잠금 = OSAllocatedUnfairLock(initialState: [String]())
        func 적는다(_ type: String) { 잠금.withLock { $0.append(type) } }
        var types: [String] { 잠금.withLock { $0 } }
    }

    /// `remove()` 만 되면 되는 가짜 리스너.
    final class 가짜_리스너: NSObject, ListenerRegistration, @unchecked Sendable {
        func remove() {}
    }

    private static let 빈_하루_읽기: @Sendable (String, String, String) async throws -> (status: ChildStatusDoc?, trail: TrailDoc?) = { _, _, _ in (nil, nil) }

    private func 관리_뷰모델(
        _ 플랫폼: [String: ChildPlatform],
         기록: 보낸_것,
        statusFetch: (@Sendable (String, String) async throws -> ChildStatusDoc?)? = nil,
        platforms: ChildPlatformStore? = nil,
        잠금: 보낸_것 = 보낸_것()
    ) -> ControlViewModel {
        ControlViewModel(
            familyId: "f1",
            childUid: "c1",
            requestLog: 격리된_요청_기록(),
            alarmMemoStore: 격리된_알람_기억(),
            platforms: platforms ?? 저장소(플랫폼),
            commandSend: { _, _, type, _ in 기록.적는다(type); return "cmd" },
            commandObserve: { _, _, _, _, _ in 가짜_리스너() },
            statusFetch: statusFetch ?? { _, _ in nil },
            settingsObserve: { _, _, _, _ in 가짜_리스너() },
            lockSave: { _, _, enabled in 잠금.적는다("lock:\(enabled)") },
            serverNow: { _ in 0 },
            deviceNow: { 0 },
            commandSleep: { _ in }
        )
    }

    private func 지도_뷰모델(_ 플랫폼: [String: ChildPlatform], 기록: 보낸_것) -> MapViewModel {
        MapViewModel(
            familyId: "f1",
            childUid: "c1",
            requestLog: 격리된_요청_기록(),
            platforms: 저장소(플랫폼),
            commandSend: { _, _, type, _ in 기록.적는다(type); return "cmd" },
            commandObserve: { _, _, _, _, _ in 가짜_리스너() },
            dayLoad: Self.빈_하루_읽기
        )
    }

    // MARK: - 관리 탭

    @Test("아이폰 아이면 관리 탭의 일곱 동작이 명령 문서를 하나도 안 만든다")
    func 아이폰이면_관리_탭_명령이_하나도_안_나간다() async {
        let 기록 = 보낸_것()
        let vm = 관리_뷰모델(["c1": .iOS], 기록: 기록)

        await vm.소리_모드를_보낸다(RingerMode.silent)
        await vm.소리_상태를_묻는다()
        await vm.폰찾기_버튼을_눌렀다()
        await vm.소리를_끈다()
        vm.메시지 = "밥 먹었니"
        await vm.메시지를_보낸다()
        vm.알람_이름 = "학원"
        await vm.알람을_맞춘다()
        await vm.알람을_끈다()

        #expect(기록.types.isEmpty)
        #expect(vm.버튼_활성화 == false)
        #expect(vm.새로_확인_활성화 == false)
        #expect(vm.아이폰이라_못_한다고_말할까 == true)
        // 조용히 물러나지 않는다 — 화면을 우회해 들어왔으면 참말을 적어야 한다.
        #expect(vm.commandUi == .failed(String(localized: "ios_child_no_remote_control")))
    }

    /// **이쪽이 더 중요하다.** 안드로이드 아이에게 지금과 한 글자도 다르면 안 된다(주인 판정).
    @Test("안드로이드 아이면 관리 탭은 지금과 똑같다")
    func 안드로이드면_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = 관리_뷰모델(["c1": .android], 기록: 기록)

        await vm.소리_모드를_보낸다(RingerMode.silent)

        #expect(기록.types == [CommandType.setRinger])
        #expect(vm.버튼_활성화 == true)
        #expect(vm.아이폰이라_못_한다고_말할까 == false)
        #expect(vm.플랫폼 == .android)
    }

    /// 아이를 모를 때도 지금과 똑같다. **문구도 안 뜬다**(판정 기록 2).
    @Test("기종을 모르면 아무것도 안 잠그고 문구도 안 띄운다")
    func 모르면_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = 관리_뷰모델([:], 기록: 기록)

        await vm.소리_모드를_보낸다(RingerMode.normal)

        #expect(기록.types == [CommandType.setRinger])
        #expect(vm.버튼_활성화 == true)
        #expect(vm.아이폰이라_못_한다고_말할까 == false)
        #expect(vm.플랫폼 == .unknown)
    }

    /// 상태 문서를 읽으면 기억보다 그쪽이 이긴다 — 아이가 폰을 갈아탄 날의 정답이다.
    @Test("읽은 상태 문서가 기억을 이기고, 읽은 김에 기억까지 갱신된다")
    func 읽은_문서가_기억을_이긴다() async {
        let 기록 = 보낸_것()
        let s = 저장소(["c1": .android])
        let vm = 관리_뷰모델(
            [:], 기록: 기록,
            statusFetch: { _, _ in ChildStatusDoc(["lat": 37.5, "lng": 127.0, "platform": "ios"]) },
            platforms: s
        )

        await vm.시작한다().value

        #expect(vm.플랫폼 == .iOS)
        #expect(s.platform(childUid: "c1") == .iOS)
        // 구독이 곧바로 부르는 소리 상태 조회도 이 한 번으로 막혔다.
        #expect(기록.types.isEmpty)
    }

    /// 반대 방향 — 아이폰이라 기억해 뒀는데 안드로이드 문서가 오면 잠금이 풀린다.
    @Test("안드로이드 상태 문서가 오면 아이폰이라던 기억이 덮인다")
    func 안드로이드_문서가_기억을_덮는다() async {
        let 기록 = 보낸_것()
        let s = 저장소(["c1": .iOS])
        let vm = 관리_뷰모델(
            [:], 기록: 기록,
            statusFetch: { _, _ in ChildStatusDoc(["lat": 37.5, "lng": 127.0]) },
            platforms: s
        )

        await vm.시작한다().value

        #expect(vm.플랫폼 == .android)
        #expect(s.platform(childUid: "c1") == .android)
        #expect(기록.types == [CommandType.queryRinger])
    }

    // MARK: - 지도 탭

    @Test("아이폰 아이면 지도 탭의 '지금 위치 확인'과 '실시간 보기'가 명령을 안 만든다")
    func 아이폰이면_지도_탭_명령이_하나도_안_나간다() async {
        let 기록 = 보낸_것()
        let vm = 지도_뷰모델(["c1": .iOS], 기록: 기록)

        await vm.지금_위치를_확인한다()
        await vm.실시간_추적을_토글한다()

        #expect(기록.types.isEmpty)
        #expect(vm.위치확인_버튼_활성화 == false)
        #expect(vm.실시간_버튼_활성화 == false)
        #expect(vm.liveTrackingState == .off)
        #expect(vm.아이폰이라_못_한다고_말할까 == true)
    }

    @Test("안드로이드 아이면 지도 탭도 지금과 똑같다")
    func 지도_탭도_안드로이드면_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = 지도_뷰모델(["c1": .android], 기록: 기록)

        await vm.지금_위치를_확인한다()

        #expect(기록.types == [CommandType.locateNow])
        #expect(vm.아이폰이라_못_한다고_말할까 == false)
    }

    @Test("기종을 모르면 지도 탭도 지금과 똑같다")
    func 지도_탭도_모르면_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = 지도_뷰모델([:], 기록: 기록)

        #expect(vm.위치확인_버튼_활성화 == true)
        #expect(vm.실시간_버튼_활성화 == true)
        await vm.지금_위치를_확인한다()

        #expect(기록.types == [CommandType.locateNow])
        #expect(vm.아이폰이라_못_한다고_말할까 == false)
    }

    /// 통합 검토 L3 와 같은 결. 배터리 팝업은 **안 잠근다** — 아이폰 아이도 배터리 값을
    /// 실제로 올린다. 설명 한 줄만 참말로 바꾼다. 안드로이드 아이가 읽는 문장은
    /// **한 글자도 안 바뀐다**.
    @Test("배터리 설명이 아이폰 아이에게 안드로이드를 말하지 않는다")
    func 배터리_설명이_기종을_안_속인다() async {
        let 기록 = 보낸_것()
        #expect(지도_뷰모델(["c1": .iOS], 기록: 기록).배터리_설명_키 == "ios_child_battery_info_message")
        #expect(지도_뷰모델(["c1": .android], 기록: 기록).배터리_설명_키 == "map_battery_info_message")
        #expect(지도_뷰모델([:], 기록: 기록).배터리_설명_키 == "map_battery_info_message")
    }

    /// **끄기는 안 막는다**(판정 기록 4). 켠 적이 없으면 불릴 일이 없지만, 어쩌다 켜져
    /// 있었다면 끄는 것은 반드시 되어야 한다.
    @Test("아이폰 아이라도 실시간 끄기는 막지 않는다")
    func 아이폰이라도_끄기는_된다() async {
        let 기록 = 보낸_것()
        let vm = 지도_뷰모델(["c1": .iOS], 기록: 기록)

        vm.실시간_추적을_끈다()

        #expect(vm.liveTrackingState == .off)
    }

    // MARK: - 예약 탭

    /// 절대 안 열리는 문 — 제한시간 쪽이 이기지 않게 해서 진짜 쓰기·보내기가 늘 이기게 한다
    /// (`LiveTrackingTests.Gate` 와 같은 발상).
    private actor 영원한_문 {
        func wait() async { await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in } }
    }

    private func 예약_뷰모델(
        _ 플랫폼: [String: ChildPlatform],
        기록: 보낸_것,
        저장된: 보낸_것 = 보낸_것(),
        syncStore: RuleSyncStore? = nil
    ) -> ScheduleViewModel {
        ScheduleViewModel(
            familyId: "f1",
            childUid: "c1",
            syncStore: syncStore ?? RuleSyncStore(kind: .schedule,
                                                  defaults: UserDefaults(suiteName: "GuardianPlatformGateTests-sync-\(UUID())")!),
            platforms: 저장소(플랫폼),
            schedulesObserve: { _, _, _, _ in 가짜_리스너() },
            settingsObserve: { _, _, _, _ in 가짜_리스너() },
            scheduleSave: { _, _, doc in 저장된.적는다("save:\(doc.mode)"); return doc.id },
            scheduleDelete: { _, _, id in 저장된.적는다("delete:\(id)") },
            defaultModeSave: { _, _, mode in 저장된.적는다("default:\(mode)") },
            holidayOffSave: { _, _, enabled in 저장된.적는다("holiday:\(enabled)") },
            commandSend: { _, _, type, _ in 기록.적는다(type); return "cmd" },
            writeSleep: { _ in await 영원한_문().wait() }
        )
    }

    /// **저장은 되고 알림만 안 간다.** 이 두 줄이 같은 테스트에 있어야 한 쪽만 고치는 사고가
    /// 잡힌다. 그리고 **다섯 쓰기 갈래를 다 돌려야** 한 갈래만 우회하는 사고가 잡힌다 —
    /// 다섯이 각자 `아이에게_알린다` 를 부른다.
    @Test("아이폰 아이면 다섯 쓰기 갈래가 전부 저장되고 sync_rules 는 한 번도 안 나간다")
    func 아이폰이면_규칙은_저장되고_알림만_안_간다() async {
        let 기록 = 보낸_것()
        let 저장된 = 보낸_것()
        let vm = 예약_뷰모델(["c1": .iOS], 기록: 기록, 저장된: 저장된)
        let 규칙 = ScheduleDoc(id: "r1", days: [1], startMinute: 540, endMinute: 600,
                             mode: RingerMode.silent, enabled: true, priority: 1)

        vm.편집을_연다(nil)
        await vm.겹쳐도_저장한다()
        await vm.켬끔을_바꾼다(규칙, enabled: false)
        await vm.삭제를_확인했다(규칙)
        await vm.기본_모드를_고른다(RingerMode.silent)
        await vm.공휴일을_바꾼다(true)

        #expect(기록.types.isEmpty)                      // sync_rules 가 한 번도 안 나갔다
        #expect(저장된.types.count == 5)                  // 다섯 갈래가 전부 진짜로 저장됐다
        #expect(저장된.types.contains("delete:r1"))
        #expect(저장된.types.contains("default:\(RingerMode.silent)"))
        #expect(저장된.types.contains("holiday:true"))
        #expect(vm.pendingSync == false)                  // 깃발이 애초에 안 올라갔다
        #expect(vm.아이폰이라_규칙이_안_걸린다 == true)
    }

    @Test("안드로이드 아이면 예약 탭도 지금과 똑같다 — 다섯 갈래가 전부 sync_rules 를 보낸다")
    func 안드로이드면_예약_탭도_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = 예약_뷰모델(["c1": .android], 기록: 기록)
        let 규칙 = ScheduleDoc(id: "r1", days: [1], startMinute: 540, endMinute: 600,
                             mode: RingerMode.silent, enabled: true, priority: 1)

        vm.편집을_연다(nil)
        await vm.겹쳐도_저장한다()
        await vm.켬끔을_바꾼다(규칙, enabled: false)
        await vm.삭제를_확인했다(규칙)
        await vm.기본_모드를_고른다(RingerMode.silent)
        await vm.공휴일을_바꾼다(true)

        #expect(기록.types == Array(repeating: CommandType.syncRules, count: 5))
        #expect(vm.아이폰이라_규칙이_안_걸린다 == false)
    }

    /// 기종을 모르면 예약 탭도 지금 그대로다 — 예약 탭은 상태 문서를 안 읽는 유일한 탭이라
    /// 기억이 비는 일이 실제로 흔하다(판정 기록 3).
    @Test("기종을 모르면 예약 탭도 지금과 똑같다")
    func 모르면_예약_탭도_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = 예약_뷰모델([:], 기록: 기록)

        await vm.기본_모드를_고른다(RingerMode.silent)

        #expect(기록.types == [CommandType.syncRules])
        #expect(vm.아이폰이라_규칙이_안_걸린다 == false)
        #expect(vm.플랫폼 == .unknown)
    }

    /// 옛 버전이 올려 둔 깃발이 남아 있어도 아이폰 아이에게는 명령이 안 나가고 깃발이 내려간다.
    @Test("남아 있던 깃발도 내려가고 sync_rules 는 안 나간다")
    func 남아_있던_깃발도_내려간다() async {
        let 기록 = 보낸_것()
        let store = RuleSyncStore(kind: .schedule,
                                  defaults: UserDefaults(suiteName: "GuardianPlatformGateTests-stale-\(UUID())")!)
        store.setPendingSync(childUid: "c1", true)
        let vm = 예약_뷰모델(["c1": .iOS], 기록: 기록, syncStore: store)

        vm.시작한다()
        #expect(vm.pendingSync == true)   // 옛 깃발을 읽어 왔다
        await vm.다시_알린다()?.value

        #expect(기록.types.isEmpty)
        #expect(vm.pendingSync == false)
        #expect(store.pendingSync(childUid: "c1") == false)
    }

    /// 통합 검토 M1. 잠금 스위치는 **뷰에만** 막혀 있었다 — 이 저장소가 다른 모든 보내기에
    /// 적용한 "두 겹"(`ControlViewModel.swift:441-445`)에서 혼자 벗어나 있었다.
    @Test("아이폰 아이면 소리 잠금이 저장까지 가지 않고, 스위치를 아예 안 보인다")
    func 아이폰이면_소리_잠금이_저장까지_안_간다() async {
        let 기록 = 보낸_것()
        let 잠금 = 보낸_것()
        let vm = 관리_뷰모델(["c1": .iOS], 기록: 기록, 잠금: 잠금)

        await vm.잠금을_바꾼다(true)

        #expect(잠금.types.isEmpty)          // `schedules/settings` 쓰기가 안 나갔다
        #expect(vm.lockEnabled == false)     // 스위치가 켜진 모양으로 남지 않는다
        #expect(vm.잠금_스위치를_보일까 == false)
        #expect(vm.commandUi == .failed(String(localized: "ios_child_no_remote_control")))
    }

    @Test("안드로이드 아이면 소리 잠금은 지금과 똑같다")
    func 안드로이드면_소리_잠금이_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let 잠금 = 보낸_것()
        let vm = 관리_뷰모델(["c1": .android], 기록: 기록, 잠금: 잠금)

        await vm.잠금을_바꾼다(true)

        #expect(잠금.types == ["lock:true"])
        #expect(vm.lockEnabled == true)
        #expect(vm.잠금_스위치를_보일까 == true)
    }

    /// 통합 검토 L3. 인터넷 카드는 **안 잠근다**(아이폰도 `network` 를 실제로 올린다).
    /// 설명 한 줄만 참말로 바꾼다. 안드로이드 아이가 읽는 문장은 **한 글자도 안 바뀐다**.
    @Test("인터넷 카드 설명이 아이폰 아이에게 안드로이드를 말하지 않는다")
    func 인터넷_설명이_기종을_안_속인다() async {
        let 기록 = 보낸_것()
        #expect(관리_뷰모델(["c1": .iOS], 기록: 기록).인터넷_설명_키 == "ios_child_network_readonly")
        #expect(관리_뷰모델(["c1": .android], 기록: 기록).인터넷_설명_키 == "control_network_readonly")
        #expect(관리_뷰모델([:], 기록: 기록).인터넷_설명_키 == "control_network_readonly")
    }

    // MARK: - 장소 탭

    /// 장소 탭은 **아무 버튼도 안 잠근다** — 아이폰 아이도 장소를 상시 구독으로 실제로 받는다
    /// (`Child/ChildSession.swift:198-204`). 막는 것은 `sync_rules` 명령 하나뿐이다.
    private func 장소_뷰모델(
        _ 플랫폼: [String: ChildPlatform],
        기록: 보낸_것,
        저장된: 보낸_것 = 보낸_것(),
        syncStore: RuleSyncStore? = nil
    ) -> PlaceViewModel {
        PlaceViewModel(
            familyId: "f1",
            childUid: "c1",
            syncStore: syncStore ?? RuleSyncStore(kind: .place,
                                                  defaults: UserDefaults(suiteName: "GuardianPlatformGateTests-place-\(UUID())")!),
            platforms: 저장소(플랫폼),
            placesObserve: { _, _, _, _ in 가짜_리스너() },
            placeSave: { _, _, doc in 저장된.적는다("save:\(doc.name)"); return doc.id },
            placeDelete: { _, _, id in 저장된.적는다("delete:\(id)") },
            statusFetch: { _, _ in nil },
            commandSend: { _, _, type, _ in 기록.적는다(type); return "cmd" },
            writeSleep: { _ in await 영원한_문().wait() },
            newId: { "new-1" }
        )
    }

    private func 장소를_하나_저장한다(_ vm: PlaceViewModel) async {
        vm.편집을_연다(nil)
        vm.지도를_만졌다(centerLat: 37.5, centerLng: 127.0)
        vm.이름을_바꾼다("학교")
        await vm.저장을_눌렀다()
    }

    private static let 지울_장소 = PlaceDoc(id: "p1", name: "학원", lat: 37.5, lng: 127.0,
                                        radiusMeters: 200, notifyEnter: true, notifyExit: true)

    /// **저장·삭제는 되고 알림만 안 간다.** 검토는 저장만 눌러 봤는데 `쓰고_알린다` 를 지나는 갈래는
    /// 둘이다 — 한 갈래만 막는 사고를 잡으려면 둘 다 눌러야 한다(통합 검토 H1).
    @Test("아이폰 아이면 장소 저장과 삭제가 sync_rules 를 하나도 안 만든다")
    func 아이폰이면_장소_탭_명령이_하나도_안_나간다() async {
        let 기록 = 보낸_것()
        let 저장된 = 보낸_것()
        let vm = 장소_뷰모델(["c1": .iOS], 기록: 기록, 저장된: 저장된)

        await 장소를_하나_저장한다(vm)
        await vm.삭제를_확인했다(Self.지울_장소)

        #expect(기록.types.isEmpty)                       // sync_rules 가 한 번도 안 나갔다
        #expect(저장된.types == ["save:학교", "delete:p1"]) // 두 갈래가 전부 진짜로 저장·삭제됐다
        #expect(vm.pendingSync == false)                   // 깃발이 애초에 안 올라갔다
        #expect(vm.아이폰이라_알릴_것이_없다 == true)
    }

    /// H2. 깃발이 서면 `PlaceView` 가 "애기폰은 지금도 예전 장소대로 알려요"를 띄우는데,
    /// 아이폰 아이에게 그 문장은 **사실과 반대**다 — 장소는 이미 가 있다.
    @Test("아이폰 아이에게는 '못 보낸 알림' 바가 안 뜨고 다시 알리기도 명령을 안 만든다")
    func 아이폰이면_못_보낸_알림_바가_안_뜬다() async {
        let 기록 = 보낸_것()
        let store = RuleSyncStore(kind: .place,
                                  defaults: UserDefaults(suiteName: "GuardianPlatformGateTests-place-stale-\(UUID())")!)
        store.setPendingSync(childUid: "c1", true)   // 옛 버전이 올려 둔 깃발
        let vm = 장소_뷰모델(["c1": .iOS], 기록: 기록, syncStore: store)

        vm.시작한다()
        #expect(vm.pendingSync == true)              // 옛 깃발을 읽어 왔다
        await vm.다시_알린다()?.value

        #expect(기록.types.isEmpty)
        #expect(vm.pendingSync == false)             // 내리는 것은 언제나 한다
        #expect(store.pendingSync(childUid: "c1") == false)
    }

    @Test("안드로이드 아이면 장소 탭도 지금과 똑같다 — 두 갈래가 전부 sync_rules 를 보낸다")
    func 안드로이드면_장소_탭도_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = 장소_뷰모델(["c1": .android], 기록: 기록)

        await 장소를_하나_저장한다(vm)
        await vm.삭제를_확인했다(Self.지울_장소)

        #expect(기록.types == Array(repeating: CommandType.syncRules, count: 2))
        #expect(vm.아이폰이라_알릴_것이_없다 == false)
    }

    @Test("기종을 모르면 장소 탭도 지금과 똑같다")
    func 모르면_장소_탭도_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = 장소_뷰모델([:], 기록: 기록)

        await vm.삭제를_확인했다(Self.지울_장소)

        #expect(기록.types == [CommandType.syncRules])
        #expect(vm.아이폰이라_알릴_것이_없다 == false)
        #expect(vm.플랫폼 == .unknown)
    }
}
