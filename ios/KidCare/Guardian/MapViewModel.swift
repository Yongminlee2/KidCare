import FirebaseFirestore
import Foundation
import Observation
import os

/// 지도 화면이 그릴 상태와, 그 상태를 만드는 읽기·날짜 이동을 소유한다. Task 4
/// 첫 커밋이 `ChildMapView` 의 `@State`(`상태`·`하루기록`·`오류`·`아이_이름`·
/// `서버기준_지금`, `하루를_읽는다()`)를 동작 변화 없이 옮겼고, 이 커밋이 날짜
/// 이동(`dayKey`, `이전_날로()`/`다음_날로()`)을 더했다. 정본은 안드로이드
/// `MapTimelineFragment` 의 `load`(:304)/`reload`(:341)/`changeDay`(:848).
///
/// 옮긴 진짜 이유는 이 화면 자체가 아니라 다음 두 Task 다: Task 5(명령 왕복 —
/// 발행 15초·응답 60초 제한시간, 세대 카운터)와 Task 7(10분 실시간 세션)은 상태
/// 기계라, `ChildMapView` 의 `@State` 안에 남겨두면 UI(시뮬레이터) 없이는 검증할
/// 방법이 없다. `@Observable` 타입으로 분리해 두면 이 타입만 인스턴스화해서
/// 로직을 테스트할 수 있다 — 날짜 이동도 같은 이유로, "다시 읽기"를 이 한 곳에
/// 모아 뒀다.
///
/// **Fix round 1(리뷰)이 두 가지를 고쳤다**: (1) 날짜를 넘기면 상태 카드도
/// 함께 다시 읽는다 — 아이 상태는 날짜와 무관하다는 첫 설계가 "부모가 며칠을
/// 넘기는 동안 배터리가 화면 첫 진입 값에 멈춰 있는" 실패를 낳았다(2단계
/// "방금 전" 버그와 같은 뿌리). (2) `loadGeneration` 으로 빠른 연속 탭의
/// 늦은 응답을 무시한다 — 아래 그 프로퍼티 주석 참고.
/// '지금 위치 확인' 왕복이 지금 어디에 있는지. 정본은 안드로이드 `ControlFragment`
/// 의 `CommandUi` 와 같은 발상이지만, `MapTimelineFragment.locateNow`/`track` 이
/// 실제로 구분하는 갈래(발행 대기·큐잉·응답 대기·완료·실패·시간 초과)만 옮긴다.
///
/// `.queued` 와 `.timedOut` 은 서로 다른 실패다 — 헷갈리면 안 된다. `.queued` 는
/// **발행**(Firestore 서버 확인) 자체를 15초 안에 못 받은 것이고(브리프 규칙 2,
/// 오프라인 쓰기는 로컬 큐에 남아 나중에 나간다 — 이건 실패가 아니다), `.timedOut`
/// 은 명령이 실제로 나간 뒤 아이 폰의 **응답**을 60초 안에 못 받은 것이다(규칙 3).
enum CommandProgress: Equatable {
    case idle
    /// 발행(서버 확인)을 기다리는 중 — 안드로이드 `renderLocating(true)` 가 곧바로
    /// 세팅하는 `map_locating` 문구 자리.
    case sending
    /// 발행이 15초 안에 서버 확인을 못 받았다. 실패가 아니다(브리프 규칙 2).
    case queued
    /// 명령 문서 하나에 리스너를 붙이고 아이 폰의 응답(`done`/`failed`)을 기다리는 중.
    case delivering
    /// 아이 폰이 `done` 이라고 적었다는 것 하나만 뜻한다 — 실제로 위치가 갱신됐는지,
    /// 그 값이 정확한지는 이 값이 보장하지 않는다(코틀린 코멘트의 경고를 그대로 옮긴다).
    case done
    /// 이미 `childErrorText` 로 번역된 문구.
    case failed(String)
    /// 60초 안에 응답이 없었다. `lastSeen` 은 `StatusCard.lastSignal` 한 곳을 거쳐
    /// 나온 값이어야 한다(브리프 규칙 3 — 이 화면의 "마지막 신호"는 항상 이 함수
    /// 하나만 지나간다는 `Documents.swift` 의 규율과 같다).
    case timedOut(lastSeen: LastSignal)

    /// 진행 중이라 버튼을 다시 눌러도 소용없는 상태인가. 안드로이드
    /// `renderLocating(busy)` 의 `busy` 와 같다 — `.queued`/`.timedOut`/`.failed`/
    /// `.done` 은 이미 `renderLocating(false)` 를 지나온 자리라 다시 눌러도 된다.
    var isInFlight: Bool {
        switch self {
        case .sending, .delivering: return true
        case .idle, .queued, .done, .failed, .timedOut: return false
        }
    }
}

/// Task 7: '실시간 보기' 토글이 지금 어디에 있는지. 정본은 안드로이드
/// `liveTrackingActive`/`liveTrackingBusy` 두 불리언(`MapTimelineFragment.kt`)을
/// 이 열거형 하나로 합친 것 — `CommandProgress` 가 '지금 위치 확인' 왕복의 갈래를
/// 하나의 타입으로 묶는 것과 같은 이유다.
///
/// `.on(until:)` 의 `until` 은 10분 세션이 자동 종료되는 예상 시각(기기 시계
/// 기준의 추정값)이다 — 지금은 화면에 이 값을 보여주는 자리가 없다(카운트다운은
/// Phase 4 몫), 상태 기계가 "언제 꺼지는지"를 스스로 알고 있게만 해 둔다.
enum LiveTrackingState: Equatable {
    case off
    case starting
    case on(until: Int64)
    // 통합 검토 M5: 예전엔 `stopping` 갈래가 있었지만 `stopLiveTrackingCore` 가 같은
    // 동기 턴 안에서 설정하고 곧바로 `.off` 로 되돌려 어떤 관찰자도 볼 수 없었다.
    // 안드로이드 `stopLiveTracking` 도 정리가 완전히 동기라 그런 상태가 없다 — 지웠다.
}

/// Task 8: 타임라인 행을 탭했을 때(경로선이 없는 구간, 또는 머무름) 지도가 옮겨가야
/// 할 자리. 정본은 안드로이드 `focusOn`(:1039). `NaverMapView` 가 한 번 소비한 뒤
/// `MapViewModel.포커스_요청을_마쳤다()` 로 스스로 지운다 — `카메라를_다시_맞춰야_한다`
/// 와 같은 일회성 신호 규율이다.
struct MapFocusRequest: Equatable {
    let lat: Double
    let lng: Double
    let zoom: Double
}

@Observable
@MainActor
final class MapViewModel {

    let familyId: String
    let childUid: String?

    private(set) var 상태: ChildStatusDoc?
    private(set) var 하루기록: TrailDoc?
    /// 상태 줄에 남길 오류·결과 문구. 값을 쓸 때마다 [오류_순번] 이 올라간다 —
    /// [상태_줄_덮어쓰기_문구] 가 "마지막으로 쓴 쪽이 이긴다"를 판정하는 재료다.
    private(set) var 오류: String? {
        didSet { if 오류 != nil { 오류_순번 = 상태줄_다음_순번() } }
    }
    /// 통합 검토 I2: 상태 줄에 무언가를 쓴 순서. 정본인 안드로이드 `statusBar` 는
    /// 텍스트뷰 하나라 나중에 쓴 쪽이 그냥 덮어쓴다 — iOS 는 문구 출처가 여럿으로
    /// 나뉘어 있어 이 순번으로 같은 결과를 흉내 낸다.
    private var 상태줄_순번 = 0
    private var 오류_순번 = 0
    private var 실시간_문구_순번 = 0
    /// 상태 카드에 쓸 아이 이름. 못 읽었으면(또는 아직 읽는 중이면) 안드로이드
    /// `selectedChildLabelText()` 의 기본값과 같은 자리로 물러난다.
    private(set) var 아이_이름 = String(localized: "child_default_name")
    /// [FamilyRepository.serverNow] 로 잰 "지금". 상태 카드의 "N분 전" 계산 기준이다
    /// — 기기 시계를 쓰면 부모 폰이 뒤처진 만큼 음수 경과가 나온다(brief 경고).
    /// 아직 못 쟀으면 기기 시계로 시작한다 — 상태 카드가 첫 프레임에 값 없이 뜨는
    /// 것보다 오차 있는 값이라도 있는 편이 낫다.
    ///
    /// **Fix round 2(리뷰) C1-b: 이 값을 화면이 뜬 채로 그냥 두면 거짓말이 된다.**
    /// 예전엔 `하루를_읽는다()`(진입·완료 뒤 재읽기)때만 갱신했는데, 그 사이 화면을
    /// 몇 분 동안 열어 두면 "방금 전"이 그대로 몇 분째 찍혀 있었다(리뷰 shot5).
    /// `시계를_돈다()` 가 60초마다 [서버_오프셋] 에 기기 시계를 더해 이 값을 다시
    /// 계산한다 — Firestore 를 새로 타지 않는다.
    private(set) var 서버기준_지금 = Int64(Date().timeIntervalSince1970 * 1000)
    /// 서버 시각 − 기기 시각. 서버 시각을 실제로 잴 때마다(`하루를_읽는다()`,
    /// `handleCommandTimeout`) 갱신한다. `시계를_돈다()` 는 이 오프셋에 그 순간의
    /// 기기 시계를 더하기만 해서 [서버기준_지금] 을 만든다 — 매번 다시 재지 않는다.
    private var 서버_오프셋: Int64 = 0
    /// 지금 보고 있는 날. 정본은 안드로이드 `MapTimelineFragment.dayKey` — 처음엔
    /// 오늘로 시작한다(`changeDay` 가 불리기 전 기본값과 같다).
    private(set) var dayKey: String

    /// 이 화면이 쓰는 시간대. 게스트(보호자) 폰의 `TimeZone.current` 다 — 자녀 폰
    /// 시간대와 다를 수 있다는 기존 한계(Task 1 보고서)를 그대로 물려받는다.
    private let zone: TimeZone

    /// `dayKey` 하루치(상태+경로)를 실제로 읽는 방법. 기본값은 프로덕션이 그대로
    /// 쓰는 `FamilyRepository.fetchChildStatus`/`TrailRepository.fetch` 다.
    /// **주입 가능하게 열어 둔 이유**는 `FamilyRepository.measureWithTimeout` 의
    /// `measure` 주입과 같다 — 실제 Firestore 왕복 순서로 "느린 응답이 늦게
    /// 도착하는" 경합을 재현하는 테스트는 이 환경에서 결정적일 수 없으므로,
    /// 테스트가 완료 순서를 직접 정할 수 있는 자리를 남긴다
    /// (`MapViewModelTests.swift` 의 "빠른 연속 탭" 테스트가 이 자리를 쓴다).
    private let dayLoad: @Sendable (
        _ familyId: String, _ childUid: String, _ dayKey: String
    ) async throws -> (status: ChildStatusDoc?, trail: TrailDoc?)

    /// 날짜를 넘길 때(또는 화면 진입 시 첫 로드)마다 하나씩 올라가는 세대 번호.
    ///
    /// **"취소"가 아니라 "무시"인 이유**: Firestore 비동기 읽기는 실제로 취소되지
    /// 않는다(1단계 확인 — SDK 에 `withTaskCancellationHandler` 로 진행 중인
    /// 읽기 자체를 끊는 경로가 없다, `FamilyRepository.measureWithTimeout` 주석
    /// 참고). 그래서 "이전 요청을 취소한다" 대신 "이전 요청의 결과가 와도 이미
    /// 낡았으면 버린다" 로 막는다: 빠르게 두 번 넘기면(◀◀) 이전 날짜(N-1)의
    /// 응답이 최신 날짜(N-2) 응답보다 늦게 도착할 수 있는데, 세대 번호가 다르면
    /// 그 결과를 화면에 반영하지 않는다(Fix round 1 Important 2).
    ///
    /// **Task 5 도 같은 원리를 쓴다**: 안드로이드 `commandGeneration`
    /// (`ControlFragment.kt` — 발행 15초·응답 60초 뒤 늦게 온 콜백을 무시한다)
    /// 과 정확히 같은 방어다. 다만 그건 "명령 왕복"이라는 다른 상태 기계의
    /// 세대라 이 `loadGeneration`(날짜 읽기 전용)과 변수를 공유하지 않는다 —
    /// 원리(세대 번호를 올리고, 캡처해 두고, 응답이 왔을 때 최신인지 다시
    /// 확인한다)만 재사용한다.
    private var loadGeneration = 0

    /// '지금 위치 확인' 왕복이 지금 어디에 있는지. `ChildMapView`/`StatusCardView`
    /// 가 이 값을 읽어 버튼·상태 줄을 그린다.
    private(set) var commandProgress: CommandProgress = .idle

    /// 명령 왕복 전용 세대 번호. `loadGeneration`(날짜 읽기)과 원리는 같지만
    /// (세대를 올리고, 캡처해 두고, 응답이 왔을 때 최신인지 다시 확인한다) 변수를
    /// 공유하지 않는다 — 서로 다른 상태 기계라 날짜를 넘긴다고 명령 왕복이,
    /// 명령을 다시 누른다고 날짜 읽기가 무효화될 이유가 없다. 정본은 안드로이드
    /// `ControlFragment`/`MapTimelineFragment` 의 `commandGeneration`(각 파일
    /// :374, :409, :444 세 곳에서 검사한다) — 이게 없으면 두 번째 요청 도중에
    /// 첫 요청의 "응답 없음"이 뜬다.
    private var commandGeneration = 0
    /// 지금 추적 중인 명령 문서의 리스너. 완료·실패·시간 초과·새 요청·화면
    /// 사라짐 네 자리 모두에서 반드시 뗀다(브리프 "Testability") — 남겨두면
    /// Spark 무료 읽기 한도를 계속 갉아먹는다.
    private var commandListener: ListenerRegistration?
    /// 60초 무응답 타이머. 리스너와 항상 같이 정리한다.
    private var commandTimeoutTask: Task<Void, Never>?

    /// "언제 물어봤고 언제 대답을 받았나" — `DisconnectRule`(무응답 배너)의 재료.
    /// 배너는 `GuardianRootView` 의 `DisconnectBanner` 가 판정한다.
    private let requestLog: RequestLog

    /// 명령을 실제로 보내는 방법. 기본값은 프로덕션이 그대로 쓰는
    /// `CommandRepository.send` 다. `dayLoad` 와 같은 이유로 주입 가능하게 열어
    /// 뒀다 — 세대·시간 초과 순서를 결정적으로 재현하려면 진짜 Firestore 왕복이
    /// 아니라 테스트가 완료 시점을 직접 정할 수 있는 자리가 필요하다.
    private let commandSend: @Sendable (
        _ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]
    ) async throws -> String
    /// 명령 문서 하나를 구독하는 방법. 기본값은 `CommandRepository.observeOne`.
    private let commandObserve: @Sendable (
        _ familyId: String, _ childUid: String, _ commandId: String,
        _ onChange: @escaping (CommandDoc) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
    /// 15초·60초 제한시간을 **실제로 기다리는** 방법. 테스트는 이 자리에 즉시
    /// 끝나거나(또는 `MapViewModelRaceTests.Gate` 처럼 테스트가 여는 문으로) 도는
    /// 가짜를 꽂아 60초를 실제로 기다리지 않는다(브리프 "Testability").
    private let commandSleep: @Sendable (_ millis: Int64) async -> Void
    /// 안드로이드 `MapTimelineFragment.SEND_TIMEOUT_MILLIS`(:1319)와 정확히 같은 값.
    private let sendTimeoutMillis: Int64
    /// 안드로이드 `MapTimelineFragment.COMMAND_TIMEOUT_MILLIS`(:1316)와 정확히 같은
    /// 값 — 관리 탭(`ControlFragment`)의 무응답 표시와 같은 기준이다(설계서 §5).
    private let answerTimeoutMillis: Int64
    /// C1(리뷰): 시간 초과가 실제로 벌어진 **그 순간** 서버 시각을 새로 잰다. 기본값은
    /// `FamilyRepository.serverNow` — `하루를_읽는다()` 가 캐시해 둔 [서버기준_지금]
    /// 을 그대로 쓰면 화면이 오래 떠 있을수록 "방금 전"이 거짓말이 된다(리뷰 shot6,
    /// 안드로이드 `ControlFragment.onTimedOut` 이 매번 새로 재는 것과 같은 이유).
    /// 주입 가능하게 연 이유는 `dayLoad`와 같다 — 이 await 를 테스트가 정확히
    /// 원하는 순간에 걸어 두 번째 요청과의 경합을 결정적으로 재현한다.
    private let commandServerNow: @Sendable (_ familyId: String, _ uid: String?) async throws -> Int64
    /// [시계를_돈다()] 가 다시 잴 주기. 기본 60,000ms — 테스트는 짧은 값을 주거나
    /// (동작 자체는 `commandSleep` 가짜가 정하므로) 값 자체보다 `commandSleep` 이
    /// 이 값을 받았는지로 send/answer 시간 제한과 구분한다.
    private let tickIntervalMillis: Int64

    /// Task 7(10분 실시간 추적)이 켜져 있거나 켜지는/꺼지는 중이면 이 버튼도 막는다는
    /// 안드로이드 `setLocateButtonEnabled`(:709)의 세 번째 조건 자리다.
    var liveTrackingActiveOrTransitioning: Bool { liveTrackingState != .off }

    // MARK: - Task 7: 실시간 추적 상태

    private(set) var liveTrackingState: LiveTrackingState = .off
    /// Task 7 전용 세대 번호. 시작 왕복(발행 확인 15초·응답 60초)과 그 뒤 상태
    /// 구독·10분 만료 타이머까지 **전부 이 하나**로 지킨다 — 정본인 안드로이드
    /// `liveCommandGeneration` 이 `trackLiveStart`/`beginLiveStatusSubscription`/
    /// 만료 타이머 세 곳 모두에서 같은 변수를 검사하는 것과 같다. `loadGeneration`·
    /// `commandGeneration`(지금 위치 확인)과는 다른 상태 기계라 변수를 공유하지
    /// 않는다 — 원리(세대를 올리고, 캡처해 두고, 응답이 왔을 때 최신인지 다시
    /// 확인한다)만 재사용한다. **낡은 세대의 시작-완료 확인이 늦게 와도 이 세대가
    /// 이미 다르면 추적을 다시 켜지 않는다** — `LiveTrackingTests` 가 이 가드를
    /// 실제로 지워서 증명한다.
    private var liveCommandGeneration = 0
    private var liveSessionId: String?
    /// 시작 명령 확인(ack)을 기다리는 리스너 — 안드로이드 `trackLiveStart`(:508) 자리.
    private var liveCommandListener: ListenerRegistration?
    private var liveCommandTimeoutTask: Task<Void, Never>?
    /// 켜진 뒤 아이 상태를 구독하는 리스너 — **이 화면에서 유일하게 상시 구독이
    /// 옳은 자리**(브리프). 끄기·만료·시작 실패·화면 사라짐 네 곳 모두에서 반드시
    /// 뗀다 — 남겨두면 Spark 무료 읽기 한도를 몇 초마다 갉아먹는다.
    private var liveStatusListener: ListenerRegistration?
    private var liveSessionTimeoutTask: Task<Void, Never>?
    /// 구독을 붙이기 **직전**의 마지막 신호 시각. 정본은 안드로이드 `liveBaselineAt`
    /// — 구독이 처음 돌려주는(구독 이전에 이미 있던) 캐시된 문서를 실시간 신호로
    /// 착각해 "정확도 Nm · 배터리 N%" 를 성급하게 보여주지 않게 막는다.
    private var liveBaselineAt: Int64 = .min
    /// `.on` 상태에서 실제로 새 신호를 받았을 때만 채워지는 상태 줄 문구
    /// (`map_live_active_status`). `nil` 이면(구독 직후, 또는 캐시된 옛 문서만
    /// 왔을 때) [실시간_상태_문구] 가 `map_live_waiting` 으로 물러난다 — 브리프
    /// "받은 만큼만 보여준다" 규칙, 실제로 리스너가 배달한 신호보다 화면이 더
    /// 신선한 척하지 않는다.
    private var 실시간_최근_문구: String?

    /// Task 7 이 켜져 있는 동안 아이 상태 구독을 붙이는 방법. 기본값은 프로덕션이
    /// 쓰는 `FamilyRepository.observeChildStatus` 다. `commandObserve` 와 같은
    /// 이유로 주입 가능하게 열어 뒀다 — 테스트가 실제 Firestore 없이 신호 도착
    /// 순서를 직접 정한다.
    private let liveStatusObserve: @Sendable (
        _ familyId: String, _ childUid: String,
        _ onChange: @escaping (ChildStatusDoc?) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
    /// 10분 세션이 자동 종료되기까지 기다리는 시간(ms). 안드로이드
    /// `LIVE_SESSION_DURATION_SECONDS`(600초)와 같은 값 — `commandSleep` 을 통해
    /// **실제로 기다리는** 시간이라, 테스트는 이 값을 짧게 주입하거나 `commandSleep`
    /// 가짜로 즉시 지나가게 한다.
    private let liveSessionTimeoutMillis: Int64
    /// 시작 명령의 `durationSeconds` 페이로드에 적을 값(초). 정본은 안드로이드
    /// `LIVE_SESSION_DURATION_SECONDS`.
    static let liveSessionDurationSeconds: Int64 = 600
    /// 정본은 안드로이드 `CHILD_FOCUS_ZOOM`(:1330) — 타임라인 행 포커스·(향후)
    /// 다른 단일 지점 포커스가 공유하는 줌 레벨이다.
    static let childFocusZoom = 18.0

    // MARK: - Task 8: 구간별 경로 보이기

    /// 지금 숨긴 이동 구간들의 `startAt`. **인덱스가 아니라 이 값으로 키를
    /// 삼는다** — `RouteSection.startAt` 주석 참고.
    private(set) var hiddenRouteStarts: Set<Int64> = []
    /// Task 8: 타임라인 행을 탭해 지도를 포커스해야 할 좌표. `NaverMapView` 가
    /// 소비한 뒤 [포커스_요청을_마쳤다] 로 스스로 지운다.
    private(set) var 포커스_요청: MapFocusRequest?
    /// Task 8: 지금 켜진 그 날 경로 전체가 보이게 카메라를 다시 맞춰야 한다는
    /// 신호. **불리언이 아니라 카운터다** — 같은 순간에 "펼쳐진 채로 다시
    /// 펼쳐짐"처럼 값이 동일한 요청이 연달아 나도 `NaverMapView` 가 "바뀌었다"로
    /// 알아채야 하기 때문이다(코디네이터가 마지막으로 처리한 값과 비교한다).
    /// 정본은 안드로이드 `fitWholeRoute` 호출 네 자리(:245, :889, :981, :1070) —
    /// **일반 갱신(`updateUIView` 재호출)마다 움직이지 않는다**(Task 1 규율:
    /// 부모가 옮긴 지도를 빼앗지 않는다), 이 신호가 설 때만 움직인다.
    private(set) var 경로_전체_보기_요청 = 0

    /// M3(리뷰): `done` 직후 카메라가 아이의 새 위치로 다시 움직여야 한다는 신호.
    /// 정본은 안드로이드 `focusChildOnNextLoad`(:157, :420, :807) — 마커가 이미
    /// 있어도(`카메라를_한번_맞췄나` 가 이미 true 라도) 이 값이 true 인 동안은
    /// `NaverMapView` 가 카메라를 강제로 다시 옮긴다. 옮긴 뒤 [카메라_재조준을_마쳤다]
    /// 로 스스로 꺼야 한다 — 안드로이드도 `renderMapStatus()` 끝에서 곧장 false 로
    /// 되돌린다(계속 true 로 두면 부모가 지도를 옮겨볼 때마다 다시 아이 위치로
    /// 끌려온다).
    private(set) var 카메라를_다시_맞춰야_한다 = false

    /// Task 6: 타임라인 패널이 지금 펼쳐져 있는가. `TimelinePanelView` 가 드래그를
    /// 놓거나 토글 버튼을 누른 뒤 [타임라인_패널_상태를_갱신한다] 로 이 값을 올린다.
    private(set) var 타임라인_펼쳐짐 = false
    /// Task 6: 타임라인 패널의 지금 콘텐츠 높이(포인트) — 접혔으면 0.
    private(set) var 타임라인_콘텐츠_높이: CGFloat = 0

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "MapViewModel")

    init(
        familyId: String,
        childUid: String?,
        zone: TimeZone = .current,
        requestLog: RequestLog = RequestLog(),
        commandSend: @escaping @Sendable (
            _ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]
        ) async throws -> String = CommandRepository.send,
        commandObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String, _ commandId: String,
            _ onChange: @escaping (CommandDoc) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = CommandRepository.observeOne,
        commandSleep: @escaping @Sendable (_ millis: Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        },
        sendTimeoutMillis: Int64 = 15_000,
        answerTimeoutMillis: Int64 = 60_000,
        commandServerNow: @escaping @Sendable (
            _ familyId: String, _ uid: String?
        ) async throws -> Int64 = { familyId, uid in try await FamilyRepository.serverNow(familyId: familyId, uid: uid) },
        tickIntervalMillis: Int64 = 60_000,
        liveStatusObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping (ChildStatusDoc?) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = FamilyRepository.observeChildStatus,
        liveSessionTimeoutMillis: Int64 = 600_000,
        dayLoad: @escaping @Sendable (
            _ familyId: String, _ childUid: String, _ dayKey: String
        ) async throws -> (status: ChildStatusDoc?, trail: TrailDoc?) = MapViewModel.기본_하루_읽기
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.zone = zone
        self.requestLog = requestLog
        self.commandSend = commandSend
        self.commandObserve = commandObserve
        self.commandSleep = commandSleep
        self.sendTimeoutMillis = sendTimeoutMillis
        self.answerTimeoutMillis = answerTimeoutMillis
        self.commandServerNow = commandServerNow
        self.tickIntervalMillis = tickIntervalMillis
        self.liveStatusObserve = liveStatusObserve
        self.liveSessionTimeoutMillis = liveSessionTimeoutMillis
        self.dayLoad = dayLoad
        dayKey = DayPicker.todayKey(zone: zone, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
    }

    /// `dayLoad` 의 기본 구현. 정본은 안드로이드 `MapTimelineFragment.load`(:304)
    /// — 상태 먼저, 경로 다음(둘 다 성공해야 화면을 갱신한다).
    private static func 기본_하루_읽기(
        familyId: String, childUid: String, dayKey: String
    ) async throws -> (status: ChildStatusDoc?, trail: TrailDoc?) {
        let status = try await FamilyRepository.fetchChildStatus(familyId: familyId, childUid: childUid)
        let trail = try await TrailRepository.fetch(familyId: familyId, childUid: childUid, dayKey: dayKey)
        return (status, trail)
    }

    /// `RouteOverlay.sections` 는 순수 계산이라 `하루기록` 이 바뀔 때마다 다시
    /// 구하면 그만이다 — 따로 저장할 상태가 아니다.
    var 경로_구간: [RouteSection] {
        guard let 하루기록 else { return [] }
        return RouteOverlay.sections(points: 하루기록.points, segments: 하루기록.segments)
    }

    /// Task 8: 지금 지도에 실제로 그려야 할 구간 — 숨긴 것(`hiddenRouteStarts`)을
    /// 뺀다. `NaverMapView` 가 그릴 선도, `fitWholeRoute` 가 맞출 범위도 **이
    /// 값 하나**를 지나간다 — 정본인 안드로이드 `renderRouteOverlay` 의
    /// `lastRouteLegs`/`lastRoutePositions` 가 숨긴 구간을 뺀 뒤에야 그리기와
    /// fitBounds 양쪽에 쓰는 것과 같다.
    var 표시할_경로_구간: [RouteSection] {
        경로_구간.filter { !hiddenRouteStarts.contains($0.startAt) }
    }

    /// 그 날을 머무름·이동으로 요약한 목록. `Timeline.timelineRows` 와 마찬가지로
    /// 순수 계산이라 `하루기록` 이 바뀔 때마다 다시 구한다.
    var 타임라인_행: [TimelineRow] {
        guard let 하루기록 else { return [] }
        return Timeline.timelineRows(from: 하루기록.segments, zone: .current, hiddenMoveStarts: hiddenRouteStarts)
    }

    /// 다음 날로 넘어갈 수 있는가. 정본은 안드로이드 `renderDayHeader` 의
    /// `binding.nextDayButton.isEnabled` 계산 — **미래로는 못 간다.** 버튼을
    /// 눌러도 못 넘어가면 고장으로 보이므로, 이 값으로 아예 눌리지 않게 비활성화
    /// 한다(brief 경고: 비활성화하지 않고 눌렸을 때만 막으면, 빈 미래 날짜가
    /// 잠깐이라도 화면에 보일 여지가 생긴다).
    var 다음_날로_갈_수_있는가: Bool {
        !DayPicker.isFuture(
            dayKey: DayPicker.shift(dayKey: dayKey, days: 1),
            zone: zone,
            nowMillis: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    /// 지금 보고 있는 날의 헤더 문구("오늘"/"어제"/"8월 5일 (수)"). `DayPicker.header`
    /// 가 돌려주는 구조를 문구로 바꾸는 일은 화면 레이어의 몫이라(`DayHeader` 타입
    /// 주석), 그 변환을 아래 `dayHeaderText(_:)` 자유 함수에 맡긴다.
    var 날짜_헤더_문구: String {
        dayHeaderText(DayPicker.header(
            dayKey: dayKey, zone: zone, nowMillis: Int64(Date().timeIntervalSince1970 * 1000)
        ))
    }

    /// "이전 날" 버튼. 정본은 안드로이드 `MapTimelineFragment.changeDay(-1)`.
    func 이전_날로() async { await 날짜를_바꾼다(-1) }

    /// "다음 날" 버튼. 오늘에서는 `다음_날로_갈_수_있는가` 가 이미 버튼을 막아
    /// 두지만, 비활성화 직전의 경합 등에 대비해 여기서도 다시 한 번 막는다
    /// (안드로이드 `changeDay` 주석과 같은 이중 방어).
    func 다음_날로() async { await 날짜를_바꾼다(1) }

    /// 날짜를 바꾸고 상태·그 날 경로를 함께 다시 읽는다(Fix round 1 Important 1).
    ///
    /// **왜 상태 카드도 다시 읽는가.** 처음엔 "상태 카드는 선택한 날짜와 무관하니
    /// 다시 읽지 않는다"로 짰지만, 그러면 부모가 며칠을 넘겨보는 몇 분 동안
    /// 배터리·마지막 신호가 화면을 처음 열었을 때 값에 멈춰 있으면서도 화면은
    /// 여전히 "지금 이 순간의 상태"인 척한다 — 2단계에서 고친 "방금 전" 버그와
    /// 뿌리가 같은 실패다. 정본인 안드로이드 `changeDay`(:848) → `reload()`(:341)
    /// → `load()`(:304) 도 매번 상태·경로를 함께 읽는다 — 여기서도 그대로 따른다.
    /// 읽기 비용은 하루 이동당 문서 1개(상태) 뿐이다.
    private func 날짜를_바꾼다(_ 일수: Int) async {
        let candidate = DayPicker.shift(dayKey: dayKey, days: 일수)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard !DayPicker.isFuture(dayKey: candidate, zone: zone, nowMillis: now) else { return }
        dayKey = candidate
        // Fix 6(안드로이드 changeDay 주석과 같은 이유): 새로 읽기 전에 화면을 먼저
        // 빈 상태로 되돌린다. 안 그러면 읽기가 실패했을 때(또는 그 날 기록이
        // 없을 때) 이전 날의 경로선·타임라인이 새 헤더 아래 그대로 남아, 부모가
        // 아이 위치를 잘못된 날짜로 읽는 상태가 된다.
        하루기록 = nil
        오류 = nil
        loadGeneration += 1
        await 상태와_그날_경로를_읽는다(generation: loadGeneration)
    }

    /// 상태와 그 날 경로를 함께 읽는다. 초기 진입(`하루를_읽는다()`)과 날짜
    /// 이동(`날짜를_바꾼다`)이 이 함수를 공유한다 — 정본은 안드로이드
    /// `MapTimelineFragment.load`(:304), 실패하면 하나의 오류 문구로 합쳐
    /// 보여준다(읽기 2회를 넘지 않는다).
    ///
    /// `generation` 은 이 요청을 시작할 때의 `loadGeneration` 스냅샷이다. 응답이
    /// 왔을 때 `loadGeneration` 이 이미 더 올라가 있으면(그사이 다른 날짜로
    /// 넘어갔으면) 그 결과를 버린다 — 빠른 연속 탭에서 늦게 온 옛 날짜의 응답이
    /// 방금 넘어간 새 날짜 화면을 덮어쓰는 것을 막는다(타입 주석의
    /// `loadGeneration` 설명 참고).
    private func 상태와_그날_경로를_읽는다(generation: Int) async {
        guard let childUid else { return }
        do {
            let 읽은_것 = try await dayLoad(familyId, childUid, dayKey)
            guard generation == loadGeneration else { return } // 이미 낡은 응답 — 무시
            상태 = 읽은_것.status
            상태가_물음보다_새로우면_대답으로_친다()
            하루기록 = 읽은_것.trail
            // Task 8: 정본은 안드로이드 drawRoute 의 `hiddenRouteStarts.retainAll(validKeys)`
            // — 날짜를 넘기면(또는 다시 읽으면) 새 하루의 구간과 겹치지 않는
            // 숨김 키는 자연히 걸러진다. 날짜가 다르면 startAt(밀리초)이 우연히
            // 같을 일이 사실상 없으므로, 이 교집합이 "날짜를 넘기면 숨김을
            // 지운다"와 같은 결과를 낸다 — 다만 같은 날을 다시 읽었을 때(예:
            // '지금 위치 확인' 완료 뒤 재읽기)는 부모가 방금 숨긴 구간을 그대로
            // 지켜준다.
            hiddenRouteStarts.formIntersection(Set(경로_구간.map(\.startAt)))
            // 이전 시도가 남긴 오류가 있었다면, 이번에 성공했으니 지운다 — 안
            // 지우면 그 옛 오류 문구가 화면에 계속 남아 방금 받은 정상 상태를
            // 가린다(3차 리뷰 Important).
            오류 = nil
            // Task 8: 정본은 안드로이드 `drawRoute`(:1070)의
            // `if (timelineExpanded) fitWholeRoute()` — 패널이 펼쳐진 채로 날짜를
            // 넘기면(또는 다시 읽으면) 새 경로 전체가 보이게 카메라를 다시
            // 맞춘다. 접혀 있으면 건드리지 않는다(Task 1 규율 — 부모의 팬을
            // 빼앗지 않는다).
            if 타임라인_펼쳐짐 { 경로_전체_보기를_요청한다() }
        } catch is CancellationError {
            // 화면이 사라지며 정상 취소된 것이다 — 오류로 취급하지 않는다.
            return
        } catch is TrailRepositoryError {
            guard generation == loadGeneration else { return }
            // 오프라인이라 그 날 기록을 못 읽었다 — "이 날은 기록이 없어요"로
            // 잘못 보여주면 안 된다(TrailRepository.fetch 주석). 안드로이드가
            // IOException 을 pairing_offline 문구로 옮기는 것과 같은 재사용이다.
            Self.logger.error("하루 기록 읽기 실패(오프라인)")
            오류 = String(localized: "pairing_offline")
        } catch {
            guard generation == loadGeneration else { return }
            // Firestore/네트워크 원문은 영어라 그대로 보여주면 로캘라이즈 규칙을
            // 어긴다(JoinFamilyView 와 같은 규율). `errorMessage` 가 코드별로 이미
            // 있는 문구(서버 설정 미완료, 오프라인, 재로그인)로 좁혀주므로 여기서는
            // 그 결과만 화면에 보여주고, 실제 원인은 로그로만 남긴다.
            Self.logger.error("하루 읽기 실패: \(String(describing: error), privacy: .public)")
            오류 = errorMessage(error)
        }
    }

    /// 첫 읽기 작업. `nil` 이면 아직 한 번도 시작하지 않았다.
    private var 처음_읽기: Task<Void, Never>?

    /// 화면이 보일 때마다 불러도 되는 첫 읽기. 정본은 안드로이드 `MapTimelineFragment.load`
    /// 가 `onViewCreated` 에서 한 번만 도는 것 — 탭은 show/hide 라 다시 보여도 다시 읽지
    /// 않는다(`GuardianMainActivity.kt:329-353`).
    ///
    /// **`.task` 가 아니라 뷰모델이 소유한 비구조적 Task 인 이유:** `TabView` 는 탭을 옮길
    /// 때마다 `.task` 를 취소한다. 첫 읽기 도중 부모가 관리 탭을 누르면 `serverNow` 가
    /// 취소를 받아 아이 이름·서버 시각을 못 채운 채 끝나고, 한 번만 읽는다는 규칙 때문에
    /// 다시 기회가 없다. 뷰의 수명과 떼어 둔다.
    @discardableResult
    func 처음이면_읽는다() -> Task<Void, Never> {
        if let 처음_읽기 { return 처음_읽기 }
        let 작업 = Task { await self.하루를_읽는다() }
        처음_읽기 = 작업
        return 작업
    }

    /// 상태와 그 날 경로를 순서대로 한 번씩 읽는다(화면 진입 시 한 번).
    func 하루를_읽는다() async {
        guard let childUid else { return }
        loadGeneration += 1
        let generation = loadGeneration
        await 상태와_그날_경로를_읽는다(generation: generation)

        // 상태 카드는 하루 기록과 실패를 공유하지 않는다 — 이름 하나, 서버 시각
        // 하나를 못 구했다고 지도·타임라인까지 오류로 덮으면 그 실패와 무관한
        // 정보까지 숨는다. 각자 실패해도 카드가 물러날 기본값(아이_이름 초기값,
        // 기기 시계로 시작한 서버기준_지금)을 이미 갖고 있어 조용히 넘어간다.
        //
        // 이 부분은 날짜 이동(`날짜를_바꾼다`)이 공유하지 않는다 — 아이 이름·
        // 서버 시각은 화면 진입 시 한 번만 구하면 되는 값이라, 안드로이드
        // `load()` 도 매 호출마다 다시 구하지 않는다.
        async let 멤버_작업 = try? FamilyRepository.fetchMember(familyId: familyId, uid: childUid)
        async let 서버시각_작업 = try? FamilyRepository.serverNow(familyId: familyId, uid: AuthGateway.currentUid())
        let 멤버 = await 멤버_작업
        let 서버시각 = await 서버시각_작업
        let 이_시각의_기기시계 = Int64(Date().timeIntervalSince1970 * 1000)
        guard generation == loadGeneration else { return } // 그사이 날짜가 바뀌었으면 이 값도 버린다
        if let name = 멤버?.displayName, !name.isEmpty { 아이_이름 = name }
        if let 서버시각 {
            서버기준_지금 = 서버시각
            // C1-b: 오프셋을 갱신해 둬야 `시계를_돈다()` 가 이후 60초마다 Firestore
            // 없이 이 기준으로 "지금"을 다시 계산할 수 있다.
            서버_오프셋 = 서버시각 - 이_시각의_기기시계
            서버_오프셋을_쟀나 = true
        }
        // 첫 상태는 오프셋을 재기 전에 읽혀 위(`상태와_그날_경로를_읽는다`)에서는 판단을
        // 건너뛰었다 — 오프셋이 생긴 지금 한 번 더 본다.
        상태가_물음보다_새로우면_대답으로_친다()
    }

    /// 화면이 떠 있는 동안 [서버기준_지금] 을 주기적으로 다시 잰다(리뷰 C1-b).
    ///
    /// **Firestore 를 새로 타지 않는다** — 캐시해 둔 [서버_오프셋] 에 그 순간의
    /// 기기 시계를 더할 뿐이다. 정본은 없다: 안드로이드 지도 탭은 주기적으로 다시
    /// 그리지 않는다(`MapTimelineFragment` 에 그런 핸들러가 없다 — Task 5 report
    /// 참고) — 화면을 오래 열어 둘수록 "방금 전"이 거짓말이 되는 실패를 막으려는
    /// iOS 전용 판단이다.
    ///
    /// `ChildMapView` 가 `.task` 로 부른다 — 화면이 사라지면 그 태스크가 스스로
    /// 취소되므로 별도로 걷어낼 리스너가 없다(`Task.isCancelled` 로 직접 검사).
    func 시계를_돈다() async {
        while !Task.isCancelled {
            await commandSleep(tickIntervalMillis)
            guard !Task.isCancelled else { return }
            서버기준_지금 = Int64(Date().timeIntervalSince1970 * 1000) + 서버_오프셋
        }
    }

    // MARK: - 지금 위치 확인

    /// 지금 위치 확인 버튼을 눌러도 되는가. 정본은 안드로이드
    /// `setLocateButtonEnabled`(:709) — 진행 중이거나, 아이가 없거나, 실시간
    /// 추적이 켜져 있거나 전환 중이면 막는다.
    var 위치확인_버튼_활성화: Bool {
        childUid != nil && !commandProgress.isInFlight && !liveTrackingActiveOrTransitioning
    }

    /// 상태 카드가 평소의 배터리·마지막 신호 문구 대신 보여줄 문구. `nil` 이면
    /// 평소 문구로 돌아간다. 정본은 안드로이드 `status_bar` 가 `renderLocating`/
    /// `showError` 로 임시로 덮었다가, `reload()` 가 다시 부르는 `renderStatus()`
    /// 가 평소 문구로 되돌리는 것과 같은 자리 — `commandProgress` 를 `.idle` 로
    /// 되돌리는 지점들이 그 "되돌림"을 대신한다.
    var 명령_상태_문구: String? {
        switch commandProgress {
        case .idle:
            return nil
        case .sending:
            return String(localized: "map_locating")
        case .queued:
            return String(localized: "control_command_queued")
        case .delivering:
            return String(localized: "control_command_sending")
        case .done:
            return String(localized: "control_command_done")
        case .failed(let text):
            return text
        case .timedOut(let lastSeen):
            // 브리프 규칙 3: 무응답 문구와 마지막 신호 시각을 함께 보여준다.
            // `lastSeen` 은 이미 `StatusCard.lastSignal` 한 곳을 거쳐 나온 값이다
            // (`handleCommandTimeout` 참고) — 여기서는 문구로만 바꾼다.
            //
            // M1(리뷰): 안드로이드 `lastSeenPhrase` 가 `control_last_seen_format`
            // ("마지막 신호 %1$s")로 한 번 더 감싼 뒤에야 `control_command_timeout_format`
            // 에 끼워 넣는다 — 여기서도 그 이중 감싸기를 그대로 따른다(둘 다 이미
            // 있는 키다, 새로 만들지 않는다).
            let 마지막_신호_문구 = String(format: String(localized: "control_last_seen_format"), lastSignalText(lastSeen))
            return String(format: String(localized: "control_command_timeout_format"), 마지막_신호_문구)
        }
    }

    /// '지금 위치 확인' 버튼. 정본은 안드로이드 `MapTimelineFragment.locateNow`(:363)
    /// 와 `track`(:406). **`완료` 가 뜻하는 것은 아이 폰이 done 이라고 적었다는
    /// 것 하나뿐이다** — 실제로 위치가 갱신됐는지, 그 값이 정확한지는 이 함수가
    /// 보장하지 않는다(코틀린 코멘트의 경고를 그대로 옮긴다).
    func 지금_위치를_확인한다() async {
        guard let childUid else {
            오류 = String(localized: "map_no_child")
            return
        }
        stopCommandTracking()
        // 부모가 버튼을 또 누를 수 있다. 지금 세대를 붙잡아 두고, 왕복이 끝난
        // 뒤 그 값이 아직 최신인지로 판단한다(`commandGeneration` 타입 주석 참고).
        commandGeneration += 1
        let generation = commandGeneration
        requestLog.recordRequest(childUid)
        오류 = nil
        commandProgress = .sending

        // 클로저가 `self` 대신 이 지역 상수만 붙잡게 한다 — `firstToFinish` 안의
        // 비구조적 태스크는 `self`(MainActor 격리)를 안전하게 건널 방법이 없다.
        let familyId = self.familyId
        let send = commandSend
        let sleep = commandSleep
        let sendTimeout = sendTimeoutMillis

        do {
            // 발행(서버 확인)을 15초 기다리다 못 받으면 실패가 아니라 큐잉이다 —
            // 오프라인 Firestore 쓰기는 로컬 큐에 들어가 나중에 나간다(브리프
            // 규칙 2). 시간 초과 쪽이 이겨도 진 쪽(대개 오프라인으로 계속 도는
            // 실제 쓰기)을 강제로 멈추지 않고 결과만 버려둔 채 계속 돌게 둔다
            // (`FamilyRepository.measureWithTimeout` 주석과 같은 근거).
            let commandId = try await Self.firstToFinish(timeoutMillis: sendTimeout, sleep: sleep) {
                try await send(familyId, childUid, CommandType.locateNow, [:])
            }
            guard generation == commandGeneration else { return } // 그새 다른 요청이 시작됐다
            guard let commandId else {
                commandProgress = .queued
                return
            }
            beginTrackingCommand(childUid: childUid, commandId: commandId, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == commandGeneration else { return }
            commandProgress = .idle
            오류 = errorMessage(error)
        }
    }

    /// 명령 문서 하나에 리스너를 붙이고 60초 무응답 타이머를 건다. 정본은
    /// 안드로이드 `track`(:406). 리스너는 `done`/`failed` 에서 곧바로 뗀다 — 답이
    /// 온 뒤에도 남겨두면 상시 구독을 없앤 의미가 사라진다.
    private func beginTrackingCommand(childUid: String, commandId: String, generation: Int) {
        commandProgress = .delivering
        let familyId = self.familyId
        let observe = commandObserve

        // Firestore 리스너 콜백은 격리되지 않은 자리에서 불린다 — `NewFamilySession
        // .듣기를_시작한다()` 의 `onJoined`/`onError` 와 같은 이유로 `Task { @MainActor
        // in ... }` 로 명시적으로 건너간다.
        commandListener = observe(familyId, childUid, commandId, { [weak self] doc in
            Task { @MainActor in self?.handleCommandChange(doc, generation: generation) }
        }, { [weak self] error in
            Task { @MainActor in self?.handleCommandError(error, generation: generation) }
        })

        let sleep = commandSleep
        let answerTimeout = answerTimeoutMillis
        // `sleep` 자체는 MainActor 와 무관한 순수 함수라 굳이 이 태스크를 여기서
        // MainActor 로 격리할 필요는 없지만, 상태를 실제로 건드리는 마지막 줄이
        // MainActor 로 건너가야 하므로 위 리스너 콜백과 같은 방식(`Task { @MainActor
        // in ... }`)으로 통일해 둔다 — 상속에 기대지 않는다.
        commandTimeoutTask = Task { @MainActor [weak self] in
            await sleep(answerTimeout)
            guard !Task.isCancelled else { return } // stopCommandTracking() 이 취소했다
            await self?.handleCommandTimeout(generation: generation)
        }
    }

    private func handleCommandChange(_ doc: CommandDoc, generation: Int) {
        guard generation == commandGeneration else { return } // 이미 낡은 응답 — 새 요청이 시작됐다
        switch doc.state {
        case CommandState.done:
            stopCommandTracking()
            recordAnswer()
            commandProgress = .done
            // M3(리뷰): 안드로이드 `focusChildOnNextLoad = true` 와 같다 — 마커가
            // 이미 있어도 방금 답한 새 위치로 카메라가 다시 움직여야 한다.
            카메라를_다시_맞춰야_한다 = true
            // 안드로이드 `reload()`(마커가 새 위치로 움직이도록 상태를 다시
            // 읽는다)와 같다 — 새 상태 기계를 만들지 않고 이미 있는 하루 읽기
            // 경로를 그대로 재사용한다(브리프 "After DONE").
            Task { @MainActor [weak self] in
                await self?.하루를_읽는다()
                guard let self, generation == self.commandGeneration else { return }
                // 다시 읽었으니 평소의 배터리·마지막 신호 문구로 돌려놓는다 —
                // "완료"를 계속 띄워두면 다음 명령 전까지 정상 정보를 가린다
                // (안드로이드 `reload()`→`renderStatus()` 가 statusBar 를
                // 되돌리는 것과 같은 효과).
                self.commandProgress = .idle
            }
        case CommandState.failed:
            stopCommandTracking()
            // 실패도 대답이다 — 아이 폰이 살아 있으니 error 를 적을 수 있었다
            // (브리프 규칙 5, README "아이가 앱을 강제 종료하면" 절).
            recordAnswer()
            commandProgress = .failed(childErrorText(doc.error))
        default:
            break // pending/delivered — 아직 기다린다.
        }
    }

    private func handleCommandError(_ error: Error, generation: Int) {
        guard generation == commandGeneration else { return }
        stopCommandTracking()
        commandProgress = .idle
        오류 = errorMessage(error)
    }

    /// 60초 무응답. 정본은 안드로이드 `track`(:443-446). 여기서는 `RequestLog`
    /// 에 응답을 적지 않는다 — 그래야 `DisconnectRule` 이 이 무응답을 근거로 배너를
    /// 띄울 수 있다. 배너는 `GuardianRootView` 의 `DisconnectBanner` 가 판정한다.
    ///
    /// **C1(리뷰): 서버 시각을 이 순간 새로 잰다.** 캐시된 [서버기준_지금] 을 그대로
    /// 쓰면 화면이 오래 떠 있을수록 "방금 전"이 거짓말이 된다(리뷰 shot6 —
    /// 4분 지난 무응답이 "방금 전"으로 찍혔다). 안드로이드 `ControlFragment
    /// .onTimedOut` 이 매번 `FamilyRepository.serverNow` 를 새로 부르는 것과 같다.
    ///
    /// 이 `await` 가 진짜 정지점이라 세대 재확인이 장식이 아니게 된다 — 이 함수에
    /// 들어온 뒤에도 그새 새 요청이 시작될 수 있다(`MapViewModelCommandGenerationTests
    /// .시간초과가_늦게_와도_세대가_다르면_화면을_안_건드린다` 가 그 경합을 증명한다).
    private func handleCommandTimeout(generation: Int) async {
        let 잰_시각: Int64
        let 이_시각의_기기시계 = Int64(Date().timeIntervalSince1970 * 1000)
        if let 새로_잰_시각 = try? await commandServerNow(familyId, AuthGateway.currentUid()) {
            잰_시각 = 새로_잰_시각
        } else {
            잰_시각 = 이_시각의_기기시계 // 취소·실패 — 기기 시계로 물러난다(FamilyRepository.serverNow 와 같은 태도)
        }
        guard generation == commandGeneration else { return } // await 뒤 다시 확인 — 그새 새 요청이 시작됐을 수 있다
        stopCommandTracking()
        // 방금 잰 시각을 카드 전체의 기준으로도 남긴다 — 이후 `시계를_돈다()` 가
        // 이 오프셋을 그대로 이어받는다.
        서버기준_지금 = 잰_시각
        서버_오프셋 = 잰_시각 - 이_시각의_기기시계
        서버_오프셋을_쟀나 = true
        // "마지막 신호"는 항상 이 함수 하나만 거친다(`Documents.swift` 의 규율).
        let signal: LastSignal = 상태.map { StatusCard.lastSignal(status: $0, nowMillis: 잰_시각) } ?? .never
        commandProgress = .timedOut(lastSeen: signal)
    }

    /// `NaverMapView` 가 카메라를 다시 옮긴 뒤 부른다 — 안드로이드
    /// `focusChildOnNextLoad = false` 와 같은 자리(M3).
    func 카메라_재조준을_마쳤다() {
        카메라를_다시_맞춰야_한다 = false
    }

    /// Task 6: `TimelinePanelView` 가 드래그를 안착시키거나 토글 버튼을 누른 뒤
    /// (또는 저장된 값을 복원한 직후) 이 값들을 올린다.
    ///
    /// **Task 8**: 펼쳐진 채로 끝날 때마다(정본은 안드로이드 `renderTimelinePanel`
    /// :889·`settleTimelineDrag` :981의 `if (timelineExpanded) fitWholeRoute()`)
    /// 경로 전체 보기를 요청한다 — 접힐 때는 건드리지 않는다(부모의 팬을 지킨다).
    func 타임라인_패널_상태를_갱신한다(펼쳐짐: Bool, 콘텐츠_높이: CGFloat) {
        타임라인_펼쳐짐 = 펼쳐짐
        타임라인_콘텐츠_높이 = 콘텐츠_높이
        if 펼쳐짐 { 경로_전체_보기를_요청한다() }
    }

    /// 통합 검토 M3: 손잡이를 끄는 **도중**의 콘텐츠 높이. 정본은 안드로이드
    /// `bindTimelineDragHandle` 의 `ACTION_MOVE`(:945-947)가 부르는
    /// `updateMapControls(basePanelHeight + currentContentHeight)` — 지도 버튼과 네이버
    /// 로고 여백이 매 이동마다 손가락을 따라간다. 펼침 여부는 바꾸지 않고 경로 전체
    /// 보기도 요청하지 않는다 — 그 둘은 손을 뗀 뒤 [타임라인_패널_상태를_갱신한다] 의
    /// 몫이다(안드로이드 `settleTimelineDrag`).
    func 타임라인_패널을_끄는_중이다(콘텐츠_높이: CGFloat) {
        타임라인_콘텐츠_높이 = 콘텐츠_높이
    }

    /// 패널 상단의 경로 요약 문구("오늘 480m" 류). 정본은 안드로이드 `renderTimeline`
    /// (:1011)의 `docs.sumOf { it.distanceMeters }` → `SegmentSummarizer.distanceText`
    /// → `timeline_summary_*` 분기(오늘/다른 날/빈 날), 그 위에 Task 8 이
    /// `renderRouteVisibilityState`(:1111)의 숨김 개수 분기를 한 번 더 얹는다.
    /// 순수 계산이라 `하루기록`·`dayKey`·`hiddenRouteStarts` 가 바뀔 때마다 다시
    /// 구하면 그만이다 — [경로_구간]·[타임라인_행] 과 같은 이유로 따로 저장하지
    /// 않는다.
    var 경로_요약_문구: String {
        let 기본_문구 = 경로_요약_기본_문구
        let 키_목록 = Set(경로_구간.map(\.startAt))
        guard !키_목록.isEmpty else { return 기본_문구 }
        let 숨긴_개수 = 키_목록.intersection(hiddenRouteStarts).count
        if 숨긴_개수 == 0 { return 기본_문구 }
        if 숨긴_개수 == 키_목록.count {
            return String(format: String(localized: "timeline_summary_routes_hidden"), 기본_문구)
        }
        return String(format: String(localized: "timeline_summary_routes_partial"), 기본_문구)
    }

    private var 경로_요약_기본_문구: String {
        guard let 하루기록, !하루기록.segments.isEmpty else {
            return String(localized: "timeline_summary_empty")
        }
        let 총_거리 = 하루기록.segments.reduce(0.0) { $0 + $1.distanceMeters }
        let 거리_문구 = distanceText(SegmentSummarizer.distance(meters: 총_거리))
        let 오늘 = DayPicker.todayKey(zone: zone, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
        return dayKey == 오늘
            ? String(format: String(localized: "timeline_summary_today"), 거리_문구)
            : String(format: String(localized: "timeline_summary_day"), 거리_문구)
    }

    // MARK: - Task 8: 구간별 경로 보이기 — 동작

    /// 전체 경로 숨김/보임 버튼이 눌릴 수 있는가. 정본은 안드로이드
    /// `routeVisibilityButton.isEnabled`(:1121) — 구간이 하나도 없으면(그 날
    /// 이동 기록이 없으면) 막는다. 화면(`TimelinePanelView`)이 이 값을 보고
    /// alpha 0.38 로 낮춘다(브리프).
    var 경로_숨김_버튼_활성화: Bool { !경로_구간.isEmpty }

    /// 지금 모든 구간이 보이는 상태인가 — 버튼 아이콘·접근성 문구가 이 값으로
    /// 갈린다. 정본은 안드로이드 `renderRouteVisibilityState` 의 `allVisible`.
    var 경로_전체_보임: Bool {
        let 키_목록 = Set(경로_구간.map(\.startAt))
        return !키_목록.isEmpty && 키_목록.isDisjoint(with: hiddenRouteStarts)
    }

    /// 전체 숨김/보임 버튼의 접근성 문구. 기존 안드로이드 키를 그대로 쓴다(브리프
    /// "All four keys already exist").
    var 경로_숨김_버튼_접근성_문구: String {
        String(localized: 경로_전체_보임 ? "timeline_hide_all_routes" : "timeline_show_all_routes")
    }

    /// 타임라인 행 하나를 탭했을 때. 정본은 안드로이드 어댑터의 탭 처리(:894-896)
    /// + `toggleRoute`(:1089) — 그릴 선이 있는 이동 구간이면 켜고 끄고, 그렇지
    /// 않으면(머무름, 또는 근사에도 실패한 이동) 그 좌표로 카메라를 포커스한다.
    func 타임라인_행을_탭한다(_ row: TimelineRow) {
        guard row.icon == .move, 경로_구간.contains(where: { $0.startAt == row.startAt }) else {
            포커스_요청 = MapFocusRequest(lat: row.lat, lng: row.lng, zoom: Self.childFocusZoom)
            return
        }
        if hiddenRouteStarts.contains(row.startAt) {
            hiddenRouteStarts.remove(row.startAt)
        } else {
            hiddenRouteStarts.insert(row.startAt)
        }
    }

    /// 전체 숨김/보임 버튼. 정본은 안드로이드 `toggleAllRoutes`(:1101) — 모두
    /// 보이는 중이면 전부 숨기고, 하나라도 숨겨져 있으면 전부 다시 보인다.
    func 전체_경로를_토글한다() {
        let 키_목록 = Set(경로_구간.map(\.startAt))
        guard !키_목록.isEmpty else { return }
        if 경로_전체_보임 {
            hiddenRouteStarts.formUnion(키_목록)
        } else {
            hiddenRouteStarts.subtract(키_목록)
        }
    }

    /// `NaverMapView` 가 [포커스_요청] 을 소비한 뒤 부른다 — `카메라_재조준을_마쳤다`
    /// 와 같은 일회성 신호 규율.
    func 포커스_요청을_마쳤다() {
        포커스_요청 = nil
    }

    /// [경로_전체_보기_요청] 을 하나 올린다 — 카운터를 쓰는 이유는 그 프로퍼티
    /// 주석 참고. `NaverMapView` 의 코디네이터가 "마지막으로 처리한 값"을 직접
    /// 기억하므로(요청 값 자체가 소비 여부를 겸한다), `카메라_재조준을_마쳤다`
    /// 와 달리 소비를 알리는 별도 함수가 필요 없다.
    private func 경로_전체_보기를_요청한다() {
        경로_전체_보기_요청 += 1
    }

    /// 대답을 적은 직후 부른다. 정본은 안드로이드 `recordAnswer` 가
    /// `GuardianMainActivity.refreshBanner()` 를 함께 부르는 것(MapTimelineFragment.kt:682-685).
    /// `GuardianRootView` 가 채운다 — 비어 있어도 배너의 1분 주기 판정이 결국 따라잡는다.
    var 대답이_기록되면: (@MainActor () -> Void)?

    /// 아이 폰이 대답했다는 사실을 남기고 배너를 즉시 다시 판정하게 한다.
    /// 배너는 `GuardianRootView` 의 `DisconnectBanner` 가 판정한다.
    private func recordAnswer() {
        guard let childUid else { return }
        requestLog.recordAnswer(childUid)
        대답이_기록되면?()
    }

    /// 서버 오프셋을 한 번이라도 쟀는가. 재기 전에는 아래 비교에 서버 시각과 기기 시각이
    /// 섞여 들어가므로 판단하지 않는다.
    private var 서버_오프셋을_쟀나 = false

    /// 부모가 마지막으로 물어본 **뒤에** 쓰인 상태 문서라면 그 자체가 "애기폰이 살아 있다"는
    /// 대답이다(늦게 살아난 폰의 안전 업로드일 수도 있다). 정본은 안드로이드
    /// `renderStatus`(MapTimelineFragment.kt:750-757) — 두 시계를 직접 비교하지 않고, 서버
    /// 기준 경과를 기기 시계로 되돌려 `RequestLog`(기기 시계)와 비교한다.
    private func 상태가_물음보다_새로우면_대답으로_친다() {
        guard 서버_오프셋을_쟀나, let childUid, let 상태, let 신호 = StatusCard.signal(status: 상태) else { return }
        let 기기시계 = Int64(Date().timeIntervalSince1970 * 1000)
        let 경과 = (기기시계 + 서버_오프셋) - 신호.atMillis
        if 기기시계 - 경과 > requestLog.lastRequestAt(childUid: childUid) {
            recordAnswer()
        }
    }

    /// 자녀 폰이 `error` 필드에 남긴 값은 사람이 읽는 문장이 아니라 코드다. 정본은
    /// 안드로이드 `childErrorText`(:691).
    private func childErrorText(_ raw: String) -> String {
        switch raw {
        case CommandType.errorNoFix: return String(localized: "map_locate_no_fix")
        default: return String(localized: "control_error_child_failed")
        }
    }

    private func stopCommandTracking() {
        commandListener?.remove()
        commandListener = nil
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil
    }

    /// 화면이 사라질 때 부른다. 정본은 안드로이드 `onDestroyView` 의
    /// `stopTracking()` 호출과 같은 정리이지만, `_binding` 같은 널 가능한 뷰
    /// 바인딩이 없는 SwiftUI 에서는 세대를 올려 이미 대기열에 오른 콜백까지
    /// 무해하게 만든다 — 코틀린의 `_binding ?: return` 을 세대 번호가 대신한다.
    func 명령_추적을_정리한다() {
        stopCommandTracking()
        commandGeneration += 1
    }

    // MARK: - Task 7: 실시간 추적 — 동작

    /// 실시간 버튼의 문구. 정본은 안드로이드 `renderLiveTrackingState`(:642) —
    /// 색·아이콘까지는 옮기지 않는다(이 앱의 버튼은 시스템 스타일을 쓴다),
    /// 문구·접근성 세 갈래만 옮긴다.
    var 실시간_버튼_문구: String {
        switch liveTrackingState {
        case .starting: return String(localized: "map_live_button_connecting")
        case .on: return String(localized: "map_live_stop")
        case .off: return String(localized: "map_live_start")
        }
    }

    var 실시간_버튼_접근성_문구: String {
        switch liveTrackingState {
        case .starting: return String(localized: "map_live_cancel_description")
        case .on: return String(localized: "map_live_stop_description")
        case .off: return String(localized: "map_live_start_description")
        }
    }

    /// 실시간 추적의 상태 줄 문구. `명령_상태_문구`(지금 위치 확인)와 같은
    /// "single status line" 규율을 따르되, 켜져 있는 동안(off 가 아닌 동안)에는
    /// 이 문구가 우선한다 — 위치확인 버튼이 실시간 추적 중엔 이미 막혀 있어
    /// (`위치확인_버튼_활성화`) 두 문구가 동시에 보여줄 실제 경합이 없다.
    var 실시간_상태_문구: String? {
        switch liveTrackingState {
        case .off: return nil
        case .starting: return String(localized: "map_live_connecting")
        case .on: return 실시간_최근_문구 ?? String(localized: "map_live_waiting")
        }
    }

    /// 상태 카드가 평소 문구(그리고 `오류`)보다 먼저 보여줄 문구. `ChildMapView` 가
    /// `StatusCardView.commandStatusText` 로 넘긴다.
    ///
    /// **통합 검토 I2 — 마지막으로 쓴 쪽이 이긴다.** 정본은 안드로이드 `statusBar`
    /// 텍스트뷰 하나다: 실시간 추적 중에 `load()` 가 실패하면 `showError` 가 그 줄을
    /// 덮어쓰고(:333, :715), 다음 실시간 신호가 오면 다시 덮어쓴다(:561). 예전 iOS 는
    /// `실시간_상태_문구 ?? 명령_상태_문구` 라 실시간이 켜져 있는 동안 날짜 읽기 실패가
    /// 아예 안 보였다. 이제는 실시간 문구보다 나중에 쓴 `오류` 가 있으면 그 오류가
    /// 이긴다.
    var 상태_줄_덮어쓰기_문구: String? {
        if let 실시간 = 실시간_상태_문구 {
            if let 오류, 오류_순번 > 실시간_문구_순번 { return 오류 }
            return 실시간
        }
        return 명령_상태_문구
    }

    private func 상태줄_다음_순번() -> Int {
        상태줄_순번 += 1
        return 상태줄_순번
    }

    /// 실시간 문구(연결 중·대기·활성)를 방금 새로 썼다고 적어 둔다.
    private func 실시간_문구를_썼다() {
        실시간_문구_순번 = 상태줄_다음_순번()
    }

    /// 통합 검토 I1: 끝난 '지금 위치 확인' 결과(`.queued`/`.done`/`.failed`/`.timedOut`)를
    /// 상태 줄에서 거둔다. 실시간 추적을 시작하거나 끝낼 때 부른다 — 안 거두면
    /// `StatusCardView` 가 명령 문구를 `오류` 보다 먼저 보여줘서, 실시간이 남긴
    /// `map_live_timeout`/`map_live_stopped`/시작 실패 문구가 옛 "응답 없음"(얼어붙은
    /// 마지막 신호 시각)에 가려진다. 안드로이드는 statusBar 하나라 나중에 쓴 실시간
    /// 문구가 그냥 이긴다. **아직 진행 중인 왕복은 건드리지 않는다** — 그 결과는 곧
    /// 새로 쓰일 문구다.
    private func 끝난_명령_문구를_거둔다() {
        guard !commandProgress.isInFlight else { return }
        commandProgress = .idle
    }

    /// 실시간 버튼. 정본은 안드로이드 `liveTrackingButton.setOnClickListener`(:906) —
    /// 켜져 있거나 전환 중이면 끄고, 아니면 켠다.
    func 실시간_추적을_토글한다() async {
        if liveTrackingState == .off {
            await 실시간_추적을_시작한다()
        } else {
            실시간_추적을_끈다()
        }
    }

    /// 실시간 추적 시작. 정본은 안드로이드 `startLiveTracking`(:459). 세션마다
    /// 새 `sessionId` 를 발급해 아이 폰이 옛 세션의 명령을 무시하게 한다(브리프).
    func 실시간_추적을_시작한다() async {
        guard let childUid else {
            오류 = String(localized: "map_no_child")
            return
        }
        stopLiveCommandTracking()
        liveCommandGeneration += 1
        let generation = liveCommandGeneration
        let sessionId = UUID().uuidString
        liveSessionId = sessionId
        liveBaselineAt = 상태?.at ?? .min
        실시간_최근_문구 = nil
        오류 = nil
        끝난_명령_문구를_거둔다()
        liveTrackingState = .starting
        실시간_문구를_썼다()

        let familyId = self.familyId
        let send = commandSend
        let sleep = commandSleep
        let sendTimeout = sendTimeoutMillis
        let durationSeconds = Self.liveSessionDurationSeconds

        do {
            // 발행(서버 확인)을 15초 기다리다 못 받으면 큐잉이다(브리프 규칙 —
            // '지금 위치 확인'과 같은 15초 규칙).
            let commandId = try await Self.firstToFinish(timeoutMillis: sendTimeout, sleep: sleep) {
                try await send(familyId, childUid, CommandType.startLiveTracking, [
                    CommandType.payloadDurationSeconds: String(durationSeconds),
                    CommandType.payloadSessionId: sessionId,
                ])
            }
            guard generation == liveCommandGeneration else { return } // 그새 다른 요청이 시작됐다
            guard let commandId else {
                failLiveStart(String(localized: "control_command_queued"), generation: generation)
                return
            }
            trackLiveStart(childUid: childUid, commandId: commandId, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == liveCommandGeneration else { return }
            failLiveStart(errorMessage(error), generation: generation)
        }
    }

    /// 시작 명령 문서 하나에 리스너를 붙이고 60초 무응답 타이머를 건다. 정본은
    /// 안드로이드 `trackLiveStart`(:508).
    private func trackLiveStart(childUid: String, commandId: String, generation: Int) {
        stopLiveCommandTracking()
        let familyId = self.familyId
        let observe = commandObserve
        liveCommandListener = observe(familyId, childUid, commandId, { [weak self] doc in
            Task { @MainActor in self?.handleLiveCommandChange(doc, childUid: childUid, generation: generation) }
        }, { [weak self] error in
            Task { @MainActor in self?.failLiveStart(errorMessage(error), generation: generation) }
        })

        let sleep = commandSleep
        let answerTimeout = answerTimeoutMillis
        liveCommandTimeoutTask = Task { @MainActor [weak self] in
            await sleep(answerTimeout)
            guard !Task.isCancelled else { return } // stopLiveCommandTracking() 이 취소했다
            self?.failLiveStart(String(localized: "control_command_timeout"), generation: generation)
        }
    }

    private func handleLiveCommandChange(_ doc: CommandDoc, childUid: String, generation: Int) {
        guard generation == liveCommandGeneration else { return } // 이미 낡은 응답 — 새 요청이 시작됐다
        // 통합 검토 M8: 같은 세대의 `done` 스냅샷이 두 번 오면(첫 번째가 리스너를
        // `remove()` 하기 전에 두 번째가 이미 `Task { @MainActor }` 로 줄을 섰으면)
        // 구독과 10분 타이머를 처음부터 다시 걸게 된다. 시작 확인은 `.starting` 에서만
        // 의미가 있다 — 안드로이드는 콜백이 메인 스레드에서 곧바로 돌아 이런 틈이 없다.
        guard case .starting = liveTrackingState else { return }
        switch doc.state {
        case CommandState.done:
            beginLiveStatusSubscription(childUid: childUid, generation: generation)
        case CommandState.failed:
            failLiveStart(childErrorText(doc.error), generation: generation)
        default:
            break // pending/delivered — 아직 기다린다.
        }
    }

    /// 시작 확인을 받은 뒤 아이 상태를 구독한다. 정본은 안드로이드
    /// `beginLiveStatusSubscription`(:540) — **이 화면에서 유일하게 상시 구독이
    /// 옳은 자리다**(브리프). 켜진 뒤 10분 자동 종료 타이머도 여기서 건다.
    private func beginLiveStatusSubscription(childUid: String, generation: Int) {
        stopLiveCommandTracking()
        실시간_최근_문구 = nil
        liveTrackingState = .on(until: 서버기준_지금 + liveSessionTimeoutMillis)
        실시간_문구를_썼다()

        let familyId = self.familyId
        let observe = liveStatusObserve
        liveStatusListener?.remove()
        liveStatusListener = observe(familyId, childUid, { [weak self] status in
            Task { @MainActor in self?.handleLiveStatusChange(status, generation: generation) }
        }, { [weak self] error in
            Task { @MainActor in self?.handleLiveStatusError(error, generation: generation) }
        })

        let sleep = commandSleep
        let duration = liveSessionTimeoutMillis
        liveSessionTimeoutTask?.cancel()
        liveSessionTimeoutTask = Task { @MainActor [weak self] in
            await sleep(duration)
            guard !Task.isCancelled else { return }
            self?.handleLiveSessionTimeout(generation: generation)
        }
    }

    /// 정본은 안드로이드 `beginLiveStatusSubscription` 의 `onChange` 갈래(:551-563).
    ///
    /// **상태 줄이 리스너가 실제로 배달한 신호보다 신선한 척하지 않는다**(브리프).
    /// 구독 직후 되돌아오는, 구독을 붙이기 **전** 캐시된 문서([liveBaselineAt] 이하)는
    /// 실시간 신호로 보여주지 않고 대기 문구로 물러난다. 실제로 새 신호를 받으면
    /// [상태] 를 갱신해 둔다 — 그래야 이 세션이 끝난 뒤에도 평소 배터리·마지막
    /// 신호 문구(`StatusCard.lastSignal` 한 곳)가 이 세션이 받은 값을 반영한다.
    private func handleLiveStatusChange(_ status: ChildStatusDoc?, generation: Int) {
        guard generation == liveCommandGeneration, case .on = liveTrackingState else { return }
        guard let status, status.at > liveBaselineAt else {
            실시간_최근_문구 = nil // 대기 문구로 되돌아간다
            실시간_문구를_썼다()
            return
        }
        상태 = status
        // 실시간 스냅샷도 안드로이드에서는 같은 `renderStatus`(:750-757)를 지나 대답으로 친다.
        상태가_물음보다_새로우면_대답으로_친다()
        // M3 와 같은 신호 — 마커가 새 위치로 따라가야 한다(브리프 "the marker follows").
        카메라를_다시_맞춰야_한다 = true
        let 정확도 = max(Int(status.accuracy.rounded()), 0)
        실시간_최근_문구 = String(format: String(localized: "map_live_active_status"), 정확도, status.battery)
        실시간_문구를_썼다()
    }

    /// 통합 검토 I2(판정): 스냅샷 리스너 오류는 종결이다(예: 가족 멤버십이 취소돼
    /// 규칙이 읽기를 막음) — Firestore 는 오류를 낸 리스너를 다시 살리지 않는다.
    /// 예전엔 `오류` 만 적고 `.on` 을 유지해, 죽은 리스너 위로 최대 10분 동안
    /// "실시간 추적 중 · 정확도 약 8m" 가 그대로 떠 있었다. 이제는 세션을 멈추고
    /// (리스너·타이머 정리, 아이 폰에도 종료 명령) 오류를 보여준다. 정본인
    /// 안드로이드는 `showError` 만 부르지만(:571-575) 그 뒤 죽은 리스너가 줄을 다시
    /// 덮지 않으니 "오류가 보인다"는 결과는 같다.
    private func handleLiveStatusError(_ error: Error, generation: Int) {
        guard generation == liveCommandGeneration, case .on = liveTrackingState else { return }
        stopLiveTrackingCore(sendCommand: true)
        오류 = errorMessage(error)
    }

    /// 10분 자동 종료. 정본은 안드로이드 `beginLiveStatusSubscription` 의 타이머
    /// 갈래(:565-570).
    private func handleLiveSessionTimeout(generation: Int) {
        guard generation == liveCommandGeneration, case .on = liveTrackingState else { return }
        stopLiveTrackingCore(sendCommand: true)
        오류 = String(localized: "map_live_timeout")
    }

    /// 시작 왕복이 실패했을 때(큐잉·응답 시간 초과·아이 폰 거부·전송 오류) 전체
    /// 세션을 정리하고 문구를 남긴다. 정본은 안드로이드 `failLiveStart`(:584) —
    /// `stopLiveTracking()` 을 그대로 부른 뒤 자신의 메시지로 문구를 덮어쓴다.
    private func failLiveStart(_ message: String, generation: Int) {
        guard generation == liveCommandGeneration else { return } // 이미 다른 요청이 시작됐다 — 이 실패는 낡았다
        stopLiveTrackingCore(sendCommand: true)
        오류 = message
    }

    /// 실시간 버튼(끄기). 정본은 안드로이드 `stopLiveTracking()` 이 버튼에서
    /// 불렸을 때의 경로 — 세션을 정리하고 `map_live_stopped` 를 남긴다.
    func 실시간_추적을_끈다() {
        let wasRunning = liveTrackingState != .off
        stopLiveTrackingCore(sendCommand: true)
        if wasRunning { 오류 = String(localized: "map_live_stopped") }
    }

    /// 실시간 세션을 실제로 접는다 — 리스너·타이머를 떼고(브리프 "Remove it on
    /// stop, on session expiry, on failure, and when the screen disappears"의
    /// 네 자리 전부가 이 함수 하나를 지나간다), 세대를 올려 늦게 오는 콜백을
    /// 무해하게 만들고, 아이 폰에도 같은 `sessionId` 로 종료 명령을 쏜다(아이
    /// 폰이 못 받아도 자체 10분 제한으로 돌아간다 — 안드로이드 `stopLiveTracking`
    /// 주석과 같은 안전망).
    ///
    /// 안드로이드처럼 이 정리 자체는 동기다 — 종료 명령 전송은 결과를 기다리지
    /// 않는 별도 태스크로 쏘아 보낸다(오프라인이어도 부모 쪽 상태는 곧바로
    /// 정리된다, `stopLiveTracking` 의 `lifecycleScope.launch` 와 같다).
    private func stopLiveTrackingCore(sendCommand: Bool) {
        guard liveTrackingState != .off else { return }
        끝난_명령_문구를_거둔다()
        let sessionId = liveSessionId
        let targetUid = childUid
        liveSessionId = nil
        liveCommandGeneration += 1
        stopLiveCommandTracking()
        liveStatusListener?.remove()
        liveStatusListener = nil
        liveSessionTimeoutTask?.cancel()
        liveSessionTimeoutTask = nil
        실시간_최근_문구 = nil
        liveTrackingState = .off

        guard sendCommand, let targetUid else { return }
        let familyId = self.familyId
        let send = commandSend
        let sleep = commandSleep
        let sendTimeout = sendTimeoutMillis
        let payload: [String: String] = sessionId.map { [CommandType.payloadSessionId: $0] } ?? [:]
        Task {
            _ = try? await Self.firstToFinish(timeoutMillis: sendTimeout, sleep: sleep) {
                try await send(familyId, targetUid, CommandType.stopLiveTracking, payload)
            }
        }
    }

    private func stopLiveCommandTracking() {
        liveCommandListener?.remove()
        liveCommandListener = nil
        liveCommandTimeoutTask?.cancel()
        liveCommandTimeoutTask = nil
    }

    /// 화면이 사라질 때 부른다(`명령_추적을_정리한다` 와 같은 자리, `ChildMapView
    /// .onDisappear`). 정본은 안드로이드 `onDestroyView` 의 `stopLiveTracking()`
    /// 호출 — 화면을 벗어나며 세션이 켜져 있었다면 아이 폰에도 종료를 알린다.
    func 실시간_추적을_정리한다() {
        stopLiveTrackingCore(sendCommand: true)
    }

    /// `withTimeoutOrNull` 같은 것. Firestore 쓰기는 취소에 응하지 않으므로
    /// (`FamilyRepository.measureWithTimeout` 주석과 같은 근거) 시간 초과 쪽이
    /// 이겨도 진 태스크(대개 오프라인 상태로 계속 도는 실제 쓰기)를 강제로 멈추지
    /// 않고 결과만 버려둔 채 계속 돌게 둔다. `withThrowingTaskGroup` 을 쓰지 않는
    /// 이유도 같은 문서가 설명한 것과 같다 — 스코프를 빠져나갈 때 취소된 태스크가
    /// 실제로 끝나기를 기다려 버리면(오프라인이면 영원히) 시간 제한이 장식으로
    /// 전락한다.
    private static func firstToFinish<T: Sendable>(
        timeoutMillis: Int64,
        sleep: @escaping @Sendable (Int64) async -> Void,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        try Task.checkCancellation()
        let race = CommandRace<T>()
        Task {
            do {
                let value = try await operation()
                await race.resolve(.success(value))
            } catch {
                await race.resolve(.failure(error))
            }
        }
        Task {
            await sleep(timeoutMillis)
            await race.resolve(.success(nil))
        }
        return try await race.outcome()
    }
}

/// [MapViewModel.firstToFinish] 전용 "누가 먼저 끝나는지" 심판. 두 번째부터의
/// `resolve` 호출은 조용히 버린다 — 이긴 쪽만 결과를 낸다. actor 로 묶어 두
/// 태스크가 동시에 `resolve` 를 불러도 경합이 없다.
private actor CommandRace<T: Sendable> {
    private var result: Result<T?, Error>?
    private var waiters: [CheckedContinuation<T?, Error>] = []

    func resolve(_ newResult: Result<T?, Error>) {
        guard result == nil else { return }
        result = newResult
        for waiter in waiters { waiter.resume(with: newResult) }
        waiters.removeAll()
    }

    func outcome() async throws -> T? {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }
}

/// [DayHeader] 를 사람이 읽는 문구로 바꾼다. 정본은 안드로이드 `DayPicker.headerText`
/// (`logic/DayPicker.kt`) — 다만 그 함수는 "오늘"·"어제"·"8월 5일 (수)" 문장을
/// 코드 안에 직접 짓는다. `DayPicker.header` 가 구조만 돌려주기로 한 이유(그 타입
/// 주석 참고)대로, 문구로 바꾸는 일은 화면 레이어인 여기서 문구 카탈로그로 한다.
///
/// `StatusCardView.swift` 의 `lastSignalText(_:)` 와 같은 자리다 — 오직 이 함수만
/// 이 변환을 한다.
func dayHeaderText(_ header: DayHeader) -> String {
    switch header {
    case .today:
        return String(localized: "day_header_today")
    case .yesterday:
        return String(localized: "day_header_yesterday")
    case .date(let month, let day, let weekday):
        return String(format: String(localized: "day_header_date"), month, day, weekdayName(weekday))
    }
}

/// 코틀린 `DayOfWeek.value`·`DayPicker` 와 같은 규칙(월=1…일=7)의 요일 번호를
/// `schedule_day_mon`…`schedule_day_sun` 문구로 바꾼다 — 2단계에서 이 키들을
/// 요일 이름에 재사용하기로 정한 대로다(brief).
private func weekdayName(_ weekday: Int) -> String {
    let key: String.LocalizationValue = switch weekday {
    case 1: "schedule_day_mon"
    case 2: "schedule_day_tue"
    case 3: "schedule_day_wed"
    case 4: "schedule_day_thu"
    case 5: "schedule_day_fri"
    case 6: "schedule_day_sat"
    default: "schedule_day_sun"
    }
    return String(localized: key)
}
