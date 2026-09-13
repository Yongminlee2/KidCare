import SwiftUI

/// 타임라인 한 줄의 아이콘. 정본은 안드로이드 `TimelineAdapter.Holder.bind` 가
/// `stay` 여부로 고르는 `ic_tab_place`/`ic_route`.
enum TimelineIcon: Equatable {
    case stay
    case move
}

/// 이동 구간의 선이 지금 지도에 보이는지. 정본은 안드로이드
/// `TimelineAdapter.Holder.bind`(:96-102)의 `routeState` 텍스트 —
/// 머무름에는 없고(`View.GONE`), 이동 행에만 "지도 표시 중"/"지도에서 숨김" 이 붙는다.
enum RouteState: Equatable {
    case visible
    case hidden
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
    /// Task 8: 이 행을 낸 `SegmentDoc.startAt`. 경로 숨김(`MapViewModel
    /// .hiddenRouteStarts`)이 이 값으로 `RouteSection` 과 짝을 맞춘다 — 인덱스가
    /// 아니다(`RouteSection.startAt` 주석과 같은 이유).
    let startAt: Int64
    /// Task 8: 행을 탭했을 때 그 구간에 그릴 선이 없으면(머무름, 또는 근사에도
    /// 실패한 이동) 이 좌표로 카메라를 포커스한다. 정본은 안드로이드 `toggleRoute`/
    /// `focusOn`(:1039, :1089).
    let lat: Double
    let lng: Double
    /// 통합 검토 M2: 이동 행의 경로 표시 상태. 머무름은 `nil` 이다(안드로이드가
    /// 머무름에서 `routeState` 를 `GONE` 으로 숨기는 것과 같다).
    let routeState: RouteState?
}

/// `SegmentDoc` 목록을 화면 행으로 바꾼다. 정본은 안드로이드
/// `TimelineAdapter.Holder.bind` 와 `MapTimelineFragment.renderTimeline`(:1011).
enum Timeline {
    /// `hiddenMoveStarts` 는 `MapViewModel.hiddenRouteStarts` — 숨김은 인덱스가 아니라
    /// `startAt` 으로 짝을 맞춘다(안드로이드 `doc.startAt in hiddenMoveStarts`).
    static func timelineRows(from docs: [SegmentDoc], zone: TimeZone, hiddenMoveStarts: Set<Int64> = []) -> [TimelineRow] {
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
                segmentIndex: index,
                startAt: doc.startAt,
                lat: doc.lat,
                lng: doc.lng,
                routeState: stay ? nil : (hiddenMoveStarts.contains(doc.startAt) ? .hidden : .visible)
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
                if let routeState = row.routeState {
                    // 통합 검토 M2: 정본은 안드로이드 `item_timeline.xml` 의
                    // `route_state`(하늘색 글자, 알약 배경) — 이동 행에만 붙는다.
                    Text(String(localized: routeState == .hidden ? "timeline_route_hidden" : "timeline_route_visible"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        // 숨긴 이동 행은 흐리게 — 안드로이드 `binding.root.alpha = 0.62f` 와 같은 값.
        .opacity(row.routeState == .hidden ? 0.62 : 1)
        // 제목·시각·표시 상태를 한 덩어리로 읽어준다(안드로이드는 행 전체가 하나의
        // 클릭 대상이라 TalkBack 이 그 안의 글자를 이어 읽는다).
        .accessibilityElement(children: .combine)
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

    /// 시각 범위와 기간을 한 줄로 잇는다. 두 값 다 문구 카탈로그의 서식 문자열로
    /// 만든 뒤에도 잇는 가운뎃점(" · ")을 Swift 문자열 보간으로 박아 넣었던 것을
    /// Fix round 1 에서 안드로이드 알림 탭(`AlertAdapter.kt`)·시스템 알림
    /// (`AlertService.kt`) 전용 서식 키로 바꿨었는데, 그건 또 다른 잘못이었다
    /// (Fix round 2 리뷰): 문구가 우연히 같다고 다른 화면 전용 키를 빌려 쓰면,
    /// 알림 탭 문구를 고칠 때 이 타임라인 줄까지 말없이 따라 바뀐다 — Phase 1
    /// 최종 리뷰가 확인 버튼 문구를 다른 화면 전용 키로 돌려썼다가 되돌린 것과
    /// 같은 실수다. 안드로이드의 두 줄짜리 서식으로 바꾸면 이미 화면으로 확인한
    /// 한 줄 레이아웃이 깨지므로, 그 대신 이 화면 전용 새 키
    /// `timeline_detail_inline`("%1$s · %2$s")을 만들어 `i18n/ko.json`·`en.json`·
    /// `Localizable.xcstrings`에 넣었다.
    private var 상세: String {
        String(format: String(localized: "timeline_detail_inline"), timeRangeText(row.detail), durationText(row.duration))
    }
}
