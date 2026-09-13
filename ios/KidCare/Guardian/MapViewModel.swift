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

@Observable
@MainActor
final class MapViewModel {

    let familyId: String
    let childUid: String?

    private(set) var 상태: ChildStatusDoc?
    private(set) var 하루기록: TrailDoc?
    private(set) var 오류: String?
    /// 상태 카드에 쓸 아이 이름. 못 읽었으면(또는 아직 읽는 중이면) 안드로이드
    /// `selectedChildLabelText()` 의 기본값과 같은 자리로 물러난다.
    private(set) var 아이_이름 = String(localized: "child_default_name")
    /// [FamilyRepository.serverNow] 로 잰 "지금". 상태 카드의 "N분 전" 계산 기준이다
    /// — 기기 시계를 쓰면 부모 폰이 뒤처진 만큼 음수 경과가 나온다(brief 경고).
    /// 아직 못 쟀으면 기기 시계로 시작한다 — 상태 카드가 첫 프레임에 값 없이 뜨는
    /// 것보다 오차 있는 값이라도 있는 편이 낫다.
    private(set) var 서버기준_지금 = Int64(Date().timeIntervalSince1970 * 1000)
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
    /// 배너 UI 자체는 Phase 4 의 몫이라 여기서는 기록만 한다(브리프 규칙 5).
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

    /// Task 7(10분 실시간 추적)이 켜져 있거나 켜지는/꺼지는 중이면 이 버튼도 막는다는
    /// 안드로이드 `setLocateButtonEnabled`(:709)의 세 번째 조건 자리다. 그 기능
    /// 자체가 아직 없어 항상 false — Task 7 이 이 프로퍼티를 실제 상태로 바꿔 낀다.
    private(set) var liveTrackingActiveOrTransitioning = false

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

    /// 그 날을 머무름·이동으로 요약한 목록. `Timeline.timelineRows` 와 마찬가지로
    /// 순수 계산이라 `하루기록` 이 바뀔 때마다 다시 구한다.
    var 타임라인_행: [TimelineRow] {
        guard let 하루기록 else { return [] }
        return Timeline.timelineRows(from: 하루기록.segments, zone: .current)
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
            하루기록 = 읽은_것.trail
            // 이전 시도가 남긴 오류가 있었다면, 이번에 성공했으니 지운다 — 안
            // 지우면 그 옛 오류 문구가 화면에 계속 남아 방금 받은 정상 상태를
            // 가린다(3차 리뷰 Important).
            오류 = nil
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
        guard generation == loadGeneration else { return } // 그사이 날짜가 바뀌었으면 이 값도 버린다
        if let name = 멤버?.displayName, !name.isEmpty { 아이_이름 = name }
        if let 서버시각 { 서버기준_지금 = 서버시각 }
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
            return String(format: String(localized: "control_command_timeout_format"), lastSignalText(lastSeen))
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
            self?.handleCommandTimeout(generation: generation)
        }
    }

    private func handleCommandChange(_ doc: CommandDoc, generation: Int) {
        guard generation == commandGeneration else { return } // 이미 낡은 응답 — 새 요청이 시작됐다
        switch doc.state {
        case CommandState.done:
            stopCommandTracking()
            recordAnswer()
            commandProgress = .done
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
    /// 에 응답을 적지 않는다 — 그래야 `DisconnectRule`(무응답 배너, Phase 4)이
    /// 이 무응답을 근거로 배너를 띄울 수 있다(브리프 규칙 5).
    private func handleCommandTimeout(generation: Int) {
        guard generation == commandGeneration else { return }
        stopCommandTracking()
        // "마지막 신호"는 항상 이 함수 하나만 거친다(`Documents.swift` 의 규율).
        let signal: LastSignal = 상태.map { StatusCard.lastSignal(status: $0, nowMillis: 서버기준_지금) } ?? .never
        commandProgress = .timedOut(lastSeen: signal)
    }

    /// 아이 폰이 대답했다는 사실을 남긴다. 정본은 안드로이드 `recordAnswer`(:682) —
    /// 다만 배너 화면(`GuardianMainActivity.refreshBanner`) 자체는 Phase 4 의 몫이라
    /// 여기서는 기록만 한다(브리프 "Port the recording; the banner UI itself is
    /// Phase 4").
    private func recordAnswer() {
        guard let childUid else { return }
        requestLog.recordAnswer(childUid)
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
