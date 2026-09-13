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

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "MapViewModel")

    init(familyId: String, childUid: String?, zone: TimeZone = .current) {
        self.familyId = familyId
        self.childUid = childUid
        self.zone = zone
        dayKey = DayPicker.todayKey(zone: zone, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
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

    /// 날짜를 바꾸고 그 날의 경로·타임라인만 다시 읽는다. **상태 카드는 다시
    /// 읽지 않는다** — 아이의 "지금" 상태는 어느 날을 보고 있는지와 무관하다
    /// (brief "상태 카드는 선택한 날짜에 의존하지 않는다"). 안드로이드
    /// `changeDay` 는 `reload()` 하나로 상태·경로를 같이 다시 읽지만, 그건 두
    /// 일을 한 함수로 묶어 둔 안드로이드 쪽 구조 때문일 뿐 상태가 날짜에 실제로
    /// 의존해서가 아니다 — 여기서는 그 결합을 풀었다.
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
        await 그날_경로를_다시_읽는다()
    }

    /// `dayKey` 가 가리키는 날의 경로만 다시 읽는다(상태 카드는 손대지 않는다).
    private func 그날_경로를_다시_읽는다() async {
        guard let childUid else { return }
        do {
            하루기록 = try await TrailRepository.fetch(familyId: familyId, childUid: childUid, dayKey: dayKey)
            오류 = nil
        } catch is CancellationError {
            return
        } catch is TrailRepositoryError {
            Self.logger.error("하루 기록 읽기 실패(오프라인)")
            오류 = String(localized: "pairing_offline")
        } catch {
            Self.logger.error("하루 읽기 실패: \(String(describing: error), privacy: .public)")
            오류 = errorMessage(error)
        }
    }

    /// 상태와 그 날 경로를 순서대로 한 번씩 읽는다. 정본은 안드로이드
    /// `MapTimelineFragment.load` — 상태 먼저, 경로 다음(둘 다 성공해야 화면을
    /// 갱신한다), 실패하면 하나의 오류 문구로 합쳐 보여준다(읽기 2회를 넘지 않는다).
    func 하루를_읽는다() async {
        guard let childUid else { return }
        do {
            let status = try await FamilyRepository.fetchChildStatus(familyId: familyId, childUid: childUid)
            let trail = try await TrailRepository.fetch(familyId: familyId, childUid: childUid, dayKey: dayKey)
            상태 = status
            하루기록 = trail
            // 이전 시도가 남긴 오류가 있었다면, 이번에 성공했으니 지운다 — 안
            // 지우면 그 옛 오류 문구가 화면에 계속 남아 방금 받은 정상 상태를
            // 가린다(3차 리뷰 Important).
            오류 = nil
        } catch is CancellationError {
            // 화면이 사라지며 정상 취소된 것이다 — 오류로 취급하지 않는다.
            return
        } catch is TrailRepositoryError {
            // 오프라인이라 그 날 기록을 못 읽었다 — "이 날은 기록이 없어요"로
            // 잘못 보여주면 안 된다(TrailRepository.fetch 주석). 안드로이드가
            // IOException 을 pairing_offline 문구로 옮기는 것과 같은 재사용이다.
            Self.logger.error("하루 기록 읽기 실패(오프라인)")
            오류 = String(localized: "pairing_offline")
        } catch {
            // Firestore/네트워크 원문은 영어라 그대로 보여주면 로캘라이즈 규칙을
            // 어긴다(JoinFamilyView 와 같은 규율). `errorMessage` 가 코드별로 이미
            // 있는 문구(서버 설정 미완료, 오프라인, 재로그인)로 좁혀주므로 여기서는
            // 그 결과만 화면에 보여주고, 실제 원인은 로그로만 남긴다.
            Self.logger.error("하루 읽기 실패: \(String(describing: error), privacy: .public)")
            오류 = errorMessage(error)
        }

        // 상태 카드는 하루 기록과 실패를 공유하지 않는다 — 이름 하나, 서버 시각
        // 하나를 못 구했다고 지도·타임라인까지 오류로 덮으면 그 실패와 무관한
        // 정보까지 숨는다. 각자 실패해도 카드가 물러날 기본값(아이_이름 초기값,
        // 기기 시계로 시작한 서버기준_지금)을 이미 갖고 있어 조용히 넘어간다.
        async let 멤버_작업 = try? FamilyRepository.fetchMember(familyId: familyId, uid: childUid)
        async let 서버시각_작업 = try? FamilyRepository.serverNow(familyId: familyId, uid: AuthGateway.currentUid())
        let 멤버 = await 멤버_작업
        let 서버시각 = await 서버시각_작업
        if let name = 멤버?.displayName, !name.isEmpty { 아이_이름 = name }
        if let 서버시각 { 서버기준_지금 = 서버시각 }
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
