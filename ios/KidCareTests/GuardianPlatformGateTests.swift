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
        platforms: ChildPlatformStore? = nil
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
            lockSave: { _, _, _ in },
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

    /// **끄기는 안 막는다**(판정 기록 4). 켠 적이 없으면 불릴 일이 없지만, 어쩌다 켜져
    /// 있었다면 끄는 것은 반드시 되어야 한다.
    @Test("아이폰 아이라도 실시간 끄기는 막지 않는다")
    func 아이폰이라도_끄기는_된다() async {
        let 기록 = 보낸_것()
        let vm = 지도_뷰모델(["c1": .iOS], 기록: 기록)

        vm.실시간_추적을_끈다()

        #expect(vm.liveTrackingState == .off)
    }
}
