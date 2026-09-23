import FirebaseFirestore
import Foundation
import Observation
import UIKit
import os

/// 아이 역할의 파이프라인을 **앱이 사는 동안** 소유한다. 앱당 하나다.
///
/// ## 왜 뷰가 아닌가 (2단계 통합 검토 I1, 1단계 M6)
///
/// 2단계까지 수집기를 만드는 유일한 코드가 `ChildSimView` 의 `.task` 안이었다 — `#if DEBUG`
/// 안이라 **출시 빌드에는 그 자리가 아예 없었다.** 지역 경계를 넘어 iOS 가 앱을 되살려도 배달할
/// 곳이 없었다는 뜻이다. 그런데 화면으로 옮기는 것만으로는 부족하다: iOS 가 앱을 **백그라운드에**
/// 되살릴 때(지역 전환·중요 위치 변경) `WindowGroup` 의 body 가 평가된다는 보장이 없다 —
/// 그릴 화면이 없으니 그릴 이유도 없다. 그래서 시작은 `KidCareApp.init()` 이 부르고,
/// `ChildRootView` 는 이 세션을 **읽기만** 한다.
///
/// ## 되살아나는 길과, 되살아나지 않는 길
///
/// 중요 위치 변경(`LocationCollector.start()`)과 지역 감시(`PlaceWatcher`)가 앱을 다시 띄운다.
/// **강제 종료(앱 전환기에서 위로 밀기) 뒤에는 둘 다 오지 않는다** — 아래 `logNoRevivalAfterForceQuit`
/// 가 그것을 로그에 적고, 아이 화면이 `ios_child_force_quit_notice` 로 아이에게 말한다.
@MainActor
@Observable
final class ChildSession {

    static let shared = ChildSession()

    private(set) var running = false
    private(set) var childUid = ""
    private(set) var familyId = ""
    let home = ChildHomeModel()

    private var collector: LocationCollector?
    private var coordinator: TrackingCoordinator?
    private var ticker: TrackingTicker?
    private var placeWatcher: PlaceWatcher?
    private var conditionWatcher: ConditionWatcher?
    private var placesListener: ListenerRegistration?
    private var device: DeviceState?
    private var powerObserver: NSObjectProtocol?
    /// 마지막으로 **서버가 확답한** 멤버 여부. `nil`(모름)은 화면의 어떤 문장도 바꾸지 않으므로
    /// 덮어쓰지 않는다 — 한 번 "아니다"를 받은 화면이 오프라인 한 번에 정상으로 돌아가면 안 된다.
    private var stillMember: Bool?
    private var memberCheck: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.kidcare.family", category: "ChildSession")

    /// 테스트 프로세스에서는 절대 안 뜬다. `RouterView.swift` 의 `isRunningTests` 와 **같은 기준**
    /// 이다 — 테스트가 아이 파이프라인을 띄우면 에뮬레이터에 쓰레기 문서가 쌓이고, 아직 구성되지
    /// 않은 `FirebaseApp` 을 건드려 프로세스가 통째로 죽는다.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 시작할 가족, 또는 시작하지 않을 이유(`nil`). **순수 판정이라 테스트가 부른다** —
    /// 진짜 `startIfChild` 는 테스트 프로세스에서 언제나 문을 닫으므로 그것만으로는
    /// "보호자 폰에서는 안 뜬다"를 확인할 수 없다.
    static func startTarget(store: RoleStore, isRunningTests: Bool) -> String? {
        guard !isRunningTests else { return nil }
        guard store.role == .child, let familyId = store.familyId, !familyId.isEmpty else { return nil }
        return familyId
    }

    /// `KidCareApp.init()` 이 부른다. **저장된 역할이 child 일 때만** 뜬다.
    /// 아이로 막 페어링을 끝낸 순간에도 같은 문을 두드린다(`RouterView` 의 `onChildReady`) —
    /// 조립하는 자리가 둘이 되지 않게 하려는 것이다.
    func startIfChild(store: RoleStore = .shared) {
        guard let familyId = Self.startTarget(store: store, isRunningTests: Self.isRunningTests) else { return }
        start(familyId: familyId)
    }

    func start(familyId: String, battery: Int? = ChildSession.injectedBattery) {
        guard !running else { return }
        running = true
        self.familyId = familyId
        logNoRevivalAfterForceQuit()
        Task { await build(familyId: familyId, battery: battery) }
    }

    /// **강제 종료 뒤에는 되살아나지 않는다**(설계서 §5.3·§15-2). 코드 주석과 아이 화면 문구만으로는
    /// 현장에서 이 사실이 안 보인다 — 로그가 그 셋째 자리다(3단계 판정 기록 9).
    private func logNoRevivalAfterForceQuit() {
        logger.notice("""
            강제 종료(앱 전환기에서 위로 밀기) 뒤에는 iOS 가 이 앱을 되살리지 않는다 — \
            중요 위치 변경도, 지역 감시도 오지 않는다. 아이가 앱을 다시 열거나 폰을 껐다 켤 때까지 \
            기록이 통째로 없다(설계서 §5.3·§15-2). 되살리기가 도는 것은 메모리 압박으로 OS 가 \
            종료했을 때와 재부팅 뒤뿐이다.
            """)
    }

    /// 파이프라인을 만드는 **유일한 함수**다. 순서는 2단계까지 `ChildSimView.start()` 에 있던
    /// 그대로이고(설계서 §6.1 의 10단계가 그 순서에 기댄다), 달라진 것은 소유자(뷰 → 세션)와
    /// `onCondition` 을 잇는 것 둘뿐이다.
    private func build(familyId: String, battery: Int?) async {
        let uid: String
        do {
            uid = try await AuthGateway.uid()
        } catch {
            // 화면은 아무 말도 바꾸지 않는다 — 모르는 것으로 아이를 겁주지 않는다.
            running = false
            logger.error("로그인 실패로 아이 세션을 못 띄웠다: \(String(describing: error), privacy: .public)")
            return
        }
        childUid = uid

        let collector = LocationCollector()
        // 시뮬레이터는 배터리를 안 준다 — 값을 넣어 주면 상태 문서에 실제 숫자가 실린다(판정 기록 3).
        let device = battery.map { value in
            DeviceState(battery: { (Float(value) / 100, .unplugged) })
        } ?? DeviceState()
        // **빼면 안 된다.** 좌표가 끊긴 폰이 `.moving` 에 갇혀 하루 종일 조용해진다
        // (`TrackingTicker` 머리 주석). 이제 기본값이 없어 컴파일러가 대신 지킨다.
        let ticker = TrackingTicker()
        let coordinator = Self.makeCoordinator(
            familyId: familyId,
            uploader: TrailUploader(device: device),
            source: collector,
            ticker: ticker
        )
        // 되살아난 직후 오늘 걸어온 길을 되찾는다. 복구한 점은 상태 문서로 안 나간다.
        coordinator.restore()

        let conditionWatcher = ConditionWatcher()
        // 1번 단계. 좌표가 들어올 때(`handle`)와 60초 시계(`tick`) **둘 다**에서 불린다 —
        // 좌표가 안 오는 것이 바로 증상이므로 좌표에만 묶으면 아무 말도 못 한다(판정 기록 8).
        // `TrackingCoordinator` 가 1분에 한 번으로 이미 솎는다(`TrackingService.kt:399-401`).
        coordinator.onCondition = { [weak self] now in self?.checkConditions(now: now) }
        // 설계서 §8.1 — 권한 상태를 한 번 받고 끝내지 않고 계속 본다. 아이가 설정에서 무엇을
        // 껐다면 그 순간이 바로 부모에게 알려야 하는 순간이다.
        collector.onAuthorizationChange = { [weak self] _, _ in
            self?.checkConditions(now: Int64(Date().timeIntervalSince1970 * 1000))
        }

        // 2단계 배선. 장소 판정은 `LocationCollector` 를 지역 감시자로 쓰고(매니저가 하나여야 한다),
        // 지역 전환 콜백은 그 수집기가 다시 `PlaceWatcher` 로 돌려준다.
        let placeWatcher = PlaceWatcher(stateStore: PlaceStateStore(), monitor: collector)
        collector.placeWatcher = placeWatcher
        // 3번 단계. 안/밖/모름 셋을 그대로 넘긴다 — `Bool` 로 좁히면 "모른다" 갈래가 사라진다.
        coordinator.updateKnownPlace = { [weak placeWatcher] fix in placeWatcher?.isInsideKnownPlace(fix) }
        // 8번 단계. 쓰기는 비동기라 `handle` 이 기다리지 않고, 끝난 뒤 `eventWritten` 으로 돌아와
        // 설계서 §6.4-3(사건 직후 업로드)을 켠다.
        let childUid = uid
        coordinator.onPlaceFix = { [weak self, weak coordinator, weak placeWatcher] fix in
            Task { @MainActor in
                guard let placeWatcher else { return }
                do {
                    let written = try await placeWatcher.onFix(familyId: familyId, childUid: childUid, fix: fix)
                    if written > 0 { coordinator?.eventWritten(at: fix.at) }
                } catch is CancellationError {
                    // 취소는 실패가 아니다(1단계 `uploadNow` 와 같은 규율).
                } catch {
                    // 이벤트 하나를 못 쓴 것 때문에 위치 수집이 멈추면 안 된다(`PlaceWatcher.kt:110-112`).
                    self?.logger.warning("장소 이벤트 쓰기 실패 — 다음 점에서 다시 한다: \(String(describing: error), privacy: .public)")
                }
            }
        }
        // 부모가 장소를 고친 것을 알 다른 길이 없다 — `sync_rules` 를 못 받기 때문이다(설계서 §7.3).
        // 이 구독이 없으면 지운 장소의 알림이 영영 계속 울린다. 첫 스냅샷이 안드로이드의 `refresh`
        // 자리(= 지역 등록)이고, 그 뒤의 스냅샷이 `sync_rules` 자리다.
        placesListener = PlaceRepository.observePlaces(
            familyId: familyId, childUid: childUid,
            onChange: { docs, _ in
                Task { @MainActor in placeWatcher.apply(placeDocs: docs) }
            },
            onError: { [weak self] error in
                self?.logger.warning("장소 구독 실패: \(String(describing: error), privacy: .public)")
            })

        self.collector = collector
        self.coordinator = coordinator
        self.ticker = ticker
        self.placeWatcher = placeWatcher
        self.conditionWatcher = conditionWatcher
        self.device = device

        // 저전력 모드가 바뀌면 화면 한 줄만 다시 그린다 — **이벤트를 만들지 않는다**(설계서 §8.3).
        // 알림 블록은 `@Sendable` 이라 `self`(비-Sendable)를 가둘 수 없다. 앱당 하나뿐인 세션이라
        // 주 액터 안에서 `shared` 를 읽는 쪽이 `MainActor.assumeIsolated` 보다 안전하다.
        powerObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: nil
        ) { _ in
            Task { @MainActor in ChildSession.shared.refreshHome() }
        }

        collector.requestAuthorization()
        collector.start()
        refreshHome(checkMembership: true)
    }

    /// `ticker:` 를 **글자로 적는 유일한 자리**다. 테스트가 이 함수를 그대로 불러 "좌표 없이도
    /// 모드가 내려가는가"를 본다(`ChildSessionTests.세션은_시계를_단다`).
    static func makeCoordinator(
        familyId: String,
        uploader: ChildUploading,
        store: TrailStore = TrailStore(),
        source: LocationSource?,
        ticker: Ticking?
    ) -> TrackingCoordinator {
        TrackingCoordinator(
            familyId: familyId,
            store: store,
            uploader: uploader,
            source: source,
            ticker: ticker
        )
    }

    /// 배터리·권한이 나빠진 순간을 부모에게 한 번 알린다. 좌표(`handle`)와 60초 시계(`tick`)
    /// **둘 다**가 이 자리로 온다.
    private func checkConditions(now: Int64) {
        guard let collector, let conditionWatcher, !familyId.isEmpty, !childUid.isEmpty else { return }
        let permissions = collector.permissions
        let battery = device?.snapshot().batteryPercent ?? -1
        let familyId = familyId
        let childUid = childUid
        Task { @MainActor [weak self] in
            do {
                try await conditionWatcher.check(
                    familyId: familyId, childUid: childUid,
                    batteryPercent: battery, permissions: permissions, now: now)
            } catch is CancellationError {
                // 취소는 실패가 아니다(1단계 `uploadNow` 와 같은 규율).
            } catch {
                // 이벤트 하나를 못 쓴 것 때문에 위치 수집이 멈추면 안 된다(`ConditionWatcher.kt:149-150`).
                self?.logger.warning("상태 이벤트 쓰기 실패: \(String(describing: error), privacy: .public)")
            }
            self?.refreshHome()
        }
    }

    /// 화면이 무엇을 말할지 다시 정한다. **권한과 저전력 모드는 공짜**라 언제든 읽지만,
    /// 멤버 확인은 읽기가 하나 드는 일이라 화면이 앞으로 나올 때와 세션이 뜰 때만 한다
    /// (`ChildHomeActivity.checkStillInFamily` 가 `onResume` 에서만 도는 것과 같다).
    func refreshHome(checkMembership: Bool = false) {
        guard let collector else { return }
        home.apply(permissions: collector.permissions,
                   stillMember: stillMember,
                   lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        guard checkMembership, !familyId.isEmpty, !childUid.isEmpty else { return }

        // 안드로이드 `memberCheckJob`(`ChildHomeActivity.kt:84-90`)의 자리다 — 늦게 끝난 읽기가
        // 새 읽기를 덮지 않게 앞의 것을 먼저 끊는다.
        memberCheck?.cancel()
        let familyId = familyId
        let childUid = childUid
        memberCheck = Task { @MainActor [weak self] in
            let answer = await FamilyRepository.isStillMember(familyId: familyId, uid: childUid)
            // `isStillMember` 는 취소에도 `nil`(모름)로 답한다 — 부르는 쪽이 한 번 더 봐야 한다.
            guard !Task.isCancelled, let self else { return }
            // 모름은 아무것도 안 바꾼다(`ChildHomeActivity.kt:146-147`).
            guard let answer else { return }
            self.stillMember = answer
            self.refreshHome()
        }
    }

    /// 두 걸음짜리 위치 권한 요청(설계서 §8.1). 두 걸음을 화면이 다시 적지 않는다.
    func requestAuthorization() { collector?.requestAuthorization() }

    /// 부르는 곳은 '다시 연결' 버튼 하나다(판정 기록 13). 리스너·시계·수집기를 전부 뗀다 —
    /// 떼는 길이 없으면 역할을 지운 뒤에도 폰이 계속 좌표를 올린다.
    func stop() {
        memberCheck?.cancel()
        memberCheck = nil
        placesListener?.remove()
        placesListener = nil
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
            self.powerObserver = nil
        }
        collector?.stop()
        ticker?.stop()
        collector = nil
        coordinator = nil
        ticker = nil
        placeWatcher = nil
        conditionWatcher = nil
        device = nil
        stillMember = nil
        familyId = ""
        childUid = ""
        running = false
    }
}

#if DEBUG
extension ChildSession {
    /// 시뮬레이터는 배터리를 안 준다(`DeviceState.swift` 의 `init` 주석) — 값을 안 넣으면 상태
    /// 문서가 늘 `battery: -1` 이고 `ConditionWatcher` 의 15% 갈래를 **시뮬레이터에서 확인할 길이
    /// 없다**(`ConditionWatcher.kt:98` 이 1..100 밖을 그냥 돌려보낸다). 파이프라인을 따로 만들지
    /// 않고 값 하나를 주입할 뿐이라 "조립하는 코드가 두 벌"이 되지 않는다(3단계 판정 기록 3).
    /// `-childBattery <0~100>`.
    static var injectedBattery: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-childBattery"), i + 1 < args.count,
              let value = Int(args[i + 1]), (0...100).contains(value) else { return nil }
        return value
    }
}
#else
extension ChildSession {
    /// 출시 빌드에는 주입 문이 없다 — 문자열조차 남지 않는다.
    static var injectedBattery: Int? { nil }
}
#endif
