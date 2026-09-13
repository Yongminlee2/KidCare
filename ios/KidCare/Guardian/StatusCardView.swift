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

    @State private var 배터리_설명_표시 = false

    var body: some View {
        HStack(spacing: 10) {
            Text(childName)
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

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
                        .lineLimit(2)
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

    /// 상태 문서가 없거나(아직 확인한 적 없음) [StatusCard.lastSignal] 이 `.never`
    /// 면 배터리 줄 자체를 안 보여준다 — 안드로이드 `renderStatus` 가
    /// `status == null || signal == null` 일 때 `map_status_never` 하나만 보여주고
    /// `map_status_format`(배터리+경과)을 안 쓰는 것과 같다. 신호가 없는데 배터리
    /// 숫자만 있는 척하면 안 된다.
    private var 상태_문구: String {
        guard let status else { return String(localized: "map_status_never") }
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
    }
}
