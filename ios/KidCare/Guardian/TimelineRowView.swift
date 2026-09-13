import SwiftUI

/// 타임라인 한 줄의 아이콘. 정본은 안드로이드 `TimelineAdapter.Holder.bind` 가
/// `stay` 여부로 고르는 `ic_tab_place`/`ic_route`.
enum TimelineIcon: Equatable {
    case stay
    case move
}

/// 타임라인 한 줄이 화면에 필요한 값. `SegmentSummarizer` 처럼 문장이 아니라 값을
/// 담는다 — 서식은 `TimelineRowView` 가 문구 카탈로그로 조립한다.
///
/// `title` 은 예외다: 머무름의 이름은 `SegmentDoc.placeName` 을 그대로 옮기거나
/// (또는 비어 있을 때 `timeline_unknown_place` 로) 대체한 것일 뿐 숫자 서식이
/// 필요 없어서, 여기서 미리 정해도 "문구는 화면이 짓는다" 원칙을 어기지 않는다.
/// 이동 구간은 이름이 없으므로 빈 문자열이다 — `TimelineRowView` 가 `icon` 으로
/// 갈래를 나눠 `distance` 로 제목을 짓는다.
struct TimelineRow: Equatable {
    let icon: TimelineIcon
    let title: String
    let detail: TimeRange
    let duration: Duration
    let distance: Distance?
    let segmentIndex: Int
}

/// `SegmentDoc` 목록을 화면 행으로 바꾼다. 정본은 안드로이드
/// `TimelineAdapter.Holder.bind` 와 `MapTimelineFragment.renderTimeline`(:1011).
enum Timeline {
    static func timelineRows(from docs: [SegmentDoc], zone: TimeZone) -> [TimelineRow] {
        docs.enumerated().map { index, doc in
            let stay = doc.type == "STAY"
            let segment = Segment(
                type: stay ? .stay : .move,
                startAt: doc.startAt, endAt: doc.endAt,
                lat: doc.lat, lng: doc.lng,
                distanceMeters: doc.distanceMeters, pointCount: doc.pointCount
            )
            // 머무름의 이름이 비어 있으면 "머무른 곳"으로 보여준다 —
            // SegmentDoc.placeName 주석이 정한 대체 문구다.
            let title = stay
                ? (doc.placeName.isEmpty ? String(localized: "timeline_unknown_place") : doc.placeName)
                : ""
            return TimelineRow(
                icon: stay ? .stay : .move,
                title: title,
                detail: SegmentSummarizer.timeRange(segment, zone: zone),
                duration: SegmentSummarizer.duration(millis: doc.endAt - doc.startAt),
                distance: stay ? nil : SegmentSummarizer.distance(meters: doc.distanceMeters),
                segmentIndex: index
            )
        }
    }
}

/// [TimeRange] 를 "08:20~10:10" 으로 조립한다. 정본은 안드로이드
/// `strings.xml` 의 `timeline_detail`이 아니라 그 값을 만드는 `SegmentSummarizer.timeRange`
/// 호출부의 서식 — 이 앱은 `segment_time_range_format` 하나로 합쳤다.
func timeRangeText(_ range: TimeRange) -> String {
    String(
        format: String(localized: "segment_time_range_format"),
        range.startHour, range.startMinute, range.endHour, range.endMinute
    )
}

/// [Duration] 을 "1시간 50분" 류 문장으로 조립한다.
func durationText(_ duration: Duration) -> String {
    switch duration {
    case .underOneMinute:
        return String(localized: "segment_duration_under_minute")
    case .minutes(let minutes):
        return String(format: String(localized: "segment_duration_minutes"), minutes)
    case .hours(let hours):
        return String(format: String(localized: "segment_duration_hours"), hours)
    case .hoursMinutes(let hours, let minutes):
        return String(format: String(localized: "segment_duration_hours_minutes"), hours, minutes)
    }
}

/// [Distance] 를 "480m"/"1.2km" 류 문장으로 조립한다.
func distanceText(_ distance: Distance) -> String {
    switch distance {
    case .underTenMeters:
        return String(localized: "segment_distance_under_ten_meters")
    case .meters(let meters):
        return String(format: String(localized: "segment_distance_meters"), meters)
    case .kilometers(let kilometers):
        return String(format: String(localized: "segment_distance_kilometers"), kilometers)
    }
}

/// 타임라인 한 줄. 정본은 안드로이드 `item_timeline.xml` + `TimelineAdapter.Holder.bind`.
struct TimelineRowView: View {
    let row: TimelineRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.icon == .stay ? "mappin.circle.fill" : "arrow.triangle.swap")
                .font(.title3)
                .foregroundStyle(row.icon == .stay ? .orange : .pink)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(제목)
                    .font(.subheadline.weight(.semibold))
                Text(상세)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    /// 머무름은 장소 이름을, 이동은 거리로 지은 제목을 보여준다 — 안드로이드
    /// `timeline_move_title`("이동 %1$s")과 같은 뜻이다.
    private var 제목: String {
        switch row.icon {
        case .stay:
            return row.title
        case .move:
            let text = row.distance.map(distanceText) ?? ""
            return String(format: String(localized: "timeline_move_title"), text)
        }
    }

    private var 상세: String {
        "\(timeRangeText(row.detail)) · \(durationText(row.duration))"
    }
}
