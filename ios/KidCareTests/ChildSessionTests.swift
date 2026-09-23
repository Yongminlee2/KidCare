import Foundation
import Testing
@testable import KidCare

/// `ChildSession` 은 **진짜 Firestore 와 CoreLocation 을 건드린다** — 그래서 통째로 띄우지
/// 않는다. 띄우면 에뮬레이터에 쓰레기 문서가 쌓이고, 아직 구성되지 않은 `FirebaseApp` 을
/// 건드려 테스트 프로세스가 통째로 죽는다(`RouterView.swift` 의 `isRunningTests` 주석).
/// 지워진 `ChildSimHarnessTests.테스트에서는_꺼져있다` 가 지키던 그 규율을 이어받는다.
///
/// 그래서 셋만 본다: **테스트에서는 안 뜬다**, **역할이 아니면 안 뜬다**, 그리고
/// **세션이 만드는 코디네이터에는 시계가 달려 있다**(1단계 I1 의 재발 방지).
@MainActor
struct ChildSessionTests {

    private func 저장소(role: MemberRole?, familyId: String?) -> RoleStore {
        let store = RoleStore(defaults: UserDefaults(suiteName: "세션-\(UUID().uuidString)")!)
        store.role = role
        store.familyId = familyId
        return store
    }

    @Test("테스트 프로세스에서는 절대 안 뜬다 — 뜨면 에뮬레이터에 쓰레기 문서가 쌓인다")
    func 테스트에서는_꺼져있다() {
        let store = 저장소(role: .child, familyId: "FAM1")
        // 이 프로세스가 곧 테스트 프로세스다 — 진짜 문을 두드려도 열리면 안 된다.
        ChildSession.shared.startIfChild(store: store)
        #expect(ChildSession.shared.running == false)
        #expect(ChildSession.startTarget(store: store, isRunningTests: true) == nil,
                "판정 자체도 테스트 프로세스를 배제한다")
    }

    @Test("역할이 child 가 아니거나 가족이 없으면 아무것도 안 만든다")
    func 역할이_아니면() {
        #expect(ChildSession.startTarget(store: 저장소(role: .guardian, familyId: "FAM1"),
                                         isRunningTests: false) == nil, "보호자 폰은 수집하지 않는다")
        #expect(ChildSession.startTarget(store: 저장소(role: nil, familyId: "FAM1"),
                                         isRunningTests: false) == nil, "역할이 없으면 역할 선택 화면이다")
        #expect(ChildSession.startTarget(store: 저장소(role: .child, familyId: nil),
                                         isRunningTests: false) == nil, "가족이 없으면 쓸 곳이 없다")
        #expect(ChildSession.startTarget(store: 저장소(role: .child, familyId: "FAM1"),
                                         isRunningTests: false) == "FAM1",
                "저장된 역할이 child 면 화면과 무관하게 그 가족으로 시작한다")
    }

    @Test("테스트 차단은 startIfChild 가 아니라 start 에 있다 (통합 검토 M3)")
    func 문은_start_에_있다() {
        #expect(ChildSession.mayStart(isRunningTests: true, running: false) == false,
                "테스트 프로세스가 진짜 CLLocationManager 와 Firestore 파이프라인을 띄우면 안 된다")
        #expect(ChildSession.mayStart(isRunningTests: false, running: true) == false,
                "이미 뜬 세션을 두 번 띄우지 않는다")
        #expect(ChildSession.mayStart(isRunningTests: false, running: false) == true)
    }

    /// **통합 검토 I3.** 화면의 초기값이 `.sharing` 이던 시절에는, 세션이 아예 못 뜬 폰에서
    /// `refreshHome` 이 그대로 빠져나가 기본값 "공유 중"이 화면에 남았다. 지금 이 프로세스가
    /// 정확히 그 상태다 — 세션이 절대 안 뜨므로 수집기가 없다.
    @Test("세션이 안 뜬 폰의 화면은 '공유 중'이라고 말하지 않는다 (통합 검토 I3)")
    func 안_뜬_세션의_화면() {
        let session = ChildSession.shared
        session.refreshHome()
        #expect(session.running == false)
        #expect(session.home.state != .sharing, "수집기가 하나도 없는데 '공유 중'이면 거짓말이다")
        #expect(session.home.bodyKey != "child_sharing_on")
    }

    /// **이 테스트가 1단계 I1 의 재발을 막는 자리다.** 컴파일러가 `ticker:` 를 강제하지만
    /// "넘기되 `nil` 을 넘긴다"는 여전히 가능하다 — 그러면 좌표가 끊긴 폰이 `.moving` 에
    /// 갇혀 하루 종일 조용해진다. 그래서 세션이 파이프라인을 만드는 바로 그 함수를 부르되
    /// 진짜 매니저 대신 가짜 좌표원과 가짜 시계를 넣고, **좌표를 끊은 채 tick 만** 흘린다.
    @Test("세션이 만드는 코디네이터는 좌표 없이도 모드를 내린다 (시계가 달려 있다)")
    func 세션은_시계를_단다() {
        let 좌표원 = 가짜_좌표원()
        let 시계 = 가짜_시계()
        let c = ChildSession.makeCoordinator(
            familyId: "F1",
            uploader: 가짜_업로더(),
            store: TrailStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)),
            source: 좌표원,
            ticker: 시계
        )
        #expect(시계.시작됨, "세션이 만든 코디네이터가 시계를 켜야 한다")

        // 이동까지 올린다.
        c.handle(점(at: t0))
        c.handle(점(at: t0 + 5_000, meters: 10))
        c.handle(점(at: t0 + 10_000, meters: 20))
        #expect(c.mode == .moving)

        // 아이가 책상에 폰을 둔다 — 3m 거리 필터 때문에 좌표 콜백이 통째로 끊긴다.
        시계.친다(t0 + 10_000 + AdaptiveMovementDetector.stopConfirmMillis)
        #expect(c.mode == .slowProbe, "시계가 없으면 여기서 `.moving` 에 갇힌다")
        시계.친다(t0 + 70_000 + CollectionMode.stillEscalateMillis)
        #expect(c.mode == .still)
    }

    /// 2026-09-22 09:00 KST.
    private let t0: Int64 = 1_790_035_200_000
    private static let 위도1도미터 = LocationFilter.earthRadiusMeters * .pi / 180

    private func 점(at: Int64, meters: Double = 0) -> Fix {
        Fix(lat: 37.5 + meters / Self.위도1도미터, lng: 127.0, accuracy: 10, at: at)
    }

    /// **통합 검토 M2.** 가족에서 빠진 아이 폰이 스스로 정리하지 않았다 — `child_family_gone` 을
    /// 띄우기만 하고 장소 리스너 하나(하루 50 읽기 예산에서 새는 읽기)와 **OS 지역 스무 개**가
    /// 무기한 살아 있었다. `stop()` 의 유일한 호출자가 화면의 '다시 연결' 버튼이라, 아이가 앱을
    /// 안 열면 영영 안 멈춘다.
    ///
    /// 파이프라인을 띄울 수 없는 프로세스라 **판정만** 본다(`startTarget`·`mayStart` 와 같은 규율).
    @Test("서버가 '멤버가 아니다'라고 확답하면 화면만 바꾸는 것이 아니라 멈춘다 (통합 검토 M2)")
    func 가족에서_빠지면_멈춘다() {
        #expect(ChildSession.멤버_답을_읽는다(nil) == .그대로,
                "모름은 아무것도 안 바꾼다 — 오프라인 한 번에 정상이던 화면이 뒤집히면 안 된다")
        #expect(ChildSession.멤버_답을_읽는다(true) == .화면만)
        #expect(ChildSession.멤버_답을_읽는다(false) == .멈춘다,
                "장소 리스너와 OS 지역 스무 개를 여기서 걷지 않으면 걷을 사람이 없다")
    }
}
