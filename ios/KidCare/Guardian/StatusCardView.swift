import Foundation
import SwiftUI

/// 지도 위 상태 카드 — 아이 이름·배터리·마지막 신호. 정본은 안드로이드
/// `fragment_map_timeline.xml` 의 `status_card`와 `MapTimelineFragment.renderStatus`
/// (:729)·`renderMapStatus`(:770)·`showBatteryInfo`(:254).
///
/// **배터리 % 만 보여주고 "어떤 앱이 썼는지"는 안 보여준다.** 탭하면 뜨는 안내
/// (`map_battery_info_message`)가 그 이유를 직접 말한다 — 안드로이드 보안 정책상
/// 원격으로는 앱별 사용량을 읽을 수 없다. 그 이유를 안 보여주면 "왜 이것만
/// 보여주나" 하는 문의로 되돌아온다(안드로이드 `showBatteryInfo` 주석).
struct StatusCardView: View {
    /// 자녀 표시 이름. 비어 있으면 `child_default_name` 으로 물러나는 것은
    /// 부르는 쪽(`ChildMapView`)의 몫이다 — 이 뷰는 이미 정해진 이름만 그린다.
    let childName: String
    let status: ChildStatusDoc?
    /// [FamilyRepository.serverNow] 로 잰 값. 기기 시계를 넘기면 부모 폰이 뒤처진
    /// 만큼 "마지막 신호 -3분 전" 이 뜬다 — brief·`StatusCard.lastSignal` 주석 참고.
    let nowMillis: Int64
    /// 아이가 아직 선택되지 않았는가. 정본은 안드로이드 `onCreateView` 가
    /// `statusBar.text = map_no_child` 를 상태 카드 **안에** 적어 두는 것(:222) —
    /// 이 화면 전체를 가리는 별도 배너가 아니라 이 한 줄이 그 자리를 대신한다.
    let hasChild: Bool
    /// `MapViewModel.오류`(하루 읽기 실패). 정본은 안드로이드 `load()` 의 catch가
    /// `showError(...)` 로 **같은 statusBar** 에 적는 것(:333) — 별도 배너가 아니다.
    let loadError: String?
    /// `MapViewModel.명령_상태_문구` — '지금 위치 확인' 이 진행 중이거나 방금
    /// 끝났으면 아래 배터리·마지막 신호 문구 대신 이 문구를 보여준다. 정본은
    /// 안드로이드 `status_bar` 가 `renderLocating`/`showError` 로 같은 텍스트뷰를
    /// 잠깐 덮어썼다가, `reload()` 가 다시 부르는 `renderStatus()` 로 되돌리는
    /// 것과 같은 자리 — `nil` 이면 평소 문구로 돌아간다.
    var commandStatusText: String? = nil
    /// 명령 발행·응답을 기다리는 동안 `true`. 안드로이드 `locate_progress`
    /// (`ProgressBar`)와 같은 자리 — 배터리 아이콘 옆에 작은 스피너를 돌린다.
    var isCommandBusy: Bool = false

    /// 본 화면의 선택기. 있으면 아이 이름이 선택 메뉴가 된다(MapTimelineFragment.kt:211-213). 미리보기처럼
    /// 선택기가 없는 곳에서는 넘겨받은 이름만 그린다.
    @Environment(ChildSelectorModel.self) private var selector: ChildSelectorModel?

    @State private var 배터리_설명_표시 = false

    var body: some View {
        HStack(spacing: 10) {
            if let selector {
                // fragment_map_timeline.xml:41-69 — 이름 뒤에 하늘색 화살표, 누르면 선택기 줄과 같은 메뉴.
                ChildMenu(model: selector) {
                    HStack(spacing: 2) {
                        Text(selector.지도_이름)
                            .font(.headline)
                            .foregroundStyle(KidCarePalette.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KidCarePalette.sky)
                            .frame(width: 20, height: 20)
                    }
                }
            } else {
                Text(childName)
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Divider().frame(height: 26)

            Button {
                배터리_설명_표시 = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "battery.100")
                        .foregroundStyle(.green)
                    Text(상태_문구)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        // Task 6 커밋 1(b): 시뮬레이터로 실제 화면을 찍어 보니
                        // `.lineLimit(2)` 가 무응답 문구(`control_command_timeout_format`
                        // 이 `control_last_seen_format` 을 한 번 더 감싼 두 줄짜리
                        // 문장, 그중 둘째 줄 자체가 이 카드 너비에서 또 한 번
                        // 줄바꿈된다)를 세 번째 줄에서 "…"로 잘랐다 — 코드만 읽고는
                        // 안 보이던 문제다. 이 카드는 이미 배터리 아이콘·구분선·
                        // 아이 이름까지 한 줄에 욱여넣어 안드로이드 `status_bar`
                        // 보다 텍스트 폭이 좁으므로, 줄 수를 고정하지 않고 필요한
                        // 만큼 감싸게 둔다(14개 언어 문구 길이가 다 다르다는 점도
                        // 같은 이유로 고정 줄 수와 상성이 나쁘다).
                    if isCommandBusy {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .alert(String(localized: "map_battery_info_title"), isPresented: $배터리_설명_표시) {
            Button(String(localized: "map_battery_info_confirm")) {}
        } message: {
            Text(String(localized: "map_battery_info_message"))
        }
    }

    /// 상태 줄 전체가 이 계산 프로퍼티 하나를 거친다(I1, 리뷰). 정본은 안드로이드
    /// `status_bar` — `renderLocating`/`showError`/`renderStatus` 가 전부 같은
    /// `TextView.text` 하나를 덮어쓰지, 서로 다른 뷰를 겹쳐 쌓지 않는다. `ChildMapView`
    /// 가 `오류`·`map_no_child`·`map_waiting_first_signal` 을 지도 위에 따로 띄우는
    /// 배너로 겹쳐 그리자, 대기 문구는 완전히 가려지고(`shot0`) "전달 중…"은 안
    /// 보이고(`shot1`) 실패 문구는 한 줄만 삐져나왔다(`shot2`) — 이 카드가 하나만
    /// 그리게 합쳐 그 문제를 없앤다.
    ///
    /// 우선순위(안드로이드가 실제로 겹쳐 쓰는 순서를 흉내 낸다 — 명령이 최근에
    /// 벌어진 일이라 가장 먼저 이긴다):
    /// 1. 명령 진행·결과(`commandStatusText`) — `renderLocating`/`track` 이
    ///    `showError` 로 statusBar 를 덮어쓰는 것과 같다.
    /// 2. 하루 읽기 실패(`loadError`) — `load()` 의 catch 가 `showError` 를
    ///    부르는 것과 같다(:333).
    /// 3. 아이 미선택(`hasChild == false`) — `onCreateView` 의 기본값(:222).
    /// 4. 상태 문서가 아직 없음(`status == nil`) — Task 4 가 이 키를 위해 이미
    ///    쓰고 있었다(`map_waiting_first_signal`, 안드로이드엔 대응하는 분기가
    ///    없다 — 이 화면만의 "아직 한 번도 못 읽었다" 갈래).
    /// 5. 평소 배터리·마지막 신호(`map_status_never`/`map_status_format`).
    private var 상태_문구: String {
        if let commandStatusText { return commandStatusText }
        if let loadError { return loadError }
        guard hasChild else { return String(localized: "map_no_child") }
        guard let status else { return String(localized: "map_waiting_first_signal") }
        let signal = StatusCard.lastSignal(status: status, nowMillis: nowMillis)
        if case .never = signal { return String(localized: "map_status_never") }
        return String(format: String(localized: "map_status_format"), status.battery, lastSignalText(signal))
    }
}

/// [LastSignal] 을 사람이 읽는 문구로 바꾼다. 정본은 안드로이드 `LastSignalText.elapsedText`.
/// **오직 이 함수만 이 변환을 한다** — [StatusCard.lastSignal] 이 "언제"를 한 곳에
/// 모으는 것과 같은 이유로, "어떻게 보여줄지"도 한 곳에 모은다.
func lastSignalText(_ signal: LastSignal) -> String {
    switch signal {
    case .never:
        return String(localized: "control_last_seen_never")
    case .minutes(let minutes) where minutes < 1:
        return String(localized: "control_last_seen_now")
    case .minutes(let minutes):
        return String(format: String(localized: "control_last_seen_minutes"), minutes)
    case .hours(let hours):
        return String(format: String(localized: "control_last_seen_hours"), hours)
    case .days(let days):
        return String(format: String(localized: "control_last_seen_days"), days)
    case .skewed(let atMillis):
        // 상대 표현을 못 쓰는 자리다(`StatusCard.lastSignal` 주석) — 절대 시각을
        // "부정확할 수 있다"는 안내와 함께 보여준다. 안드로이드
        // `LastSignalText.relativeText` 가 `clockText(atMillis)` 를 같은 문구에
        // 끼워 넣는 것과 같다.
        return String(format: String(localized: "control_last_seen_skewed_value"), clockText(atMillis))
    }
}

/// [LastSignal.skewed] 가 들고 있는 절대 시각을 "9월 13일 14:32" 류 문구로 바꾼다.
/// 정본은 안드로이드 `LastSignalText.clockText` — 다만 코틀린은 `Locale.KOREA`
/// 서식을 하드코딩해 14개 언어 중 한국어로만 정확하다. 이 앱은 문구 카탈로그로
/// 14개 언어를 옮기는 것이 규칙이라, 서식 **패턴 자체**를 `control_last_seen_clock_format`
/// 키에 담아 두고 언어별로 다른 패턴을 넣을 수 있게 했다(지금은 ko/en 두 벌).
///
/// 패턴의 숫자는 항상 아라비아 숫자·그레고리력으로 나와야 한다 — 기기가 다른
/// 달력(예: 불교력)이나 다른 숫자 체계로 설정돼 있어도 "9월 13일" 같은 리터럴
/// 글자는 그대로인데 숫자만 다른 체계로 나오면 그 자체가 또 다른 혼란이다.
/// `CalendarMath.calendar(zone:)` 가 같은 이유로 그레고리력 + `en_US_POSIX` 를
/// 쓰는 것과 같은 판단이지만, 이 함수는 `Logic/` 이 아니라 화면 문구를 만들 뿐이라
/// 그 헬퍼를 그대로 재사용하지 않고 `DateFormatter` 에 같은 설정을 직접 준다.
private func clockText(_ atMillis: Int64) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = String(localized: "control_last_seen_clock_format")
    return formatter.string(from: Date(timeIntervalSince1970: Double(atMillis) / 1000))
}
