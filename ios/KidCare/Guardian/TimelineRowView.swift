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

/// 타임라인 카드 한 장. 정본은 안드로이드 `item_timeline.xml`(`MaterialCardView`) +
/// `TimelineAdapter.Holder.bind`(:47-110). 안드로이드는 이 카드를 가로로 넘기는
/// 목록(`MapTimelineFragment` :198-199, `LinearLayoutManager.HORIZONTAL`)에 늘어놓는다 —
/// 폭 132, 높이는 콘텐츠를 채우고, 가운데 정렬한 세로 줄(아이콘 → 제목 → 시각·기간
/// 두 줄 → 이동이면 경로 표시 알약)이다. 바깥 여백(가로 5·세로 2)은 목록 쪽이 준다.
struct TimelineRowView: View {
    let row: TimelineRow

    /// `item_timeline.xml` 의 `layout_width="132dp"`.
    static let cardWidth: CGFloat = 132
    /// `ShapeAppearance.KidCare.Large`(`themes.xml:90-93`)의 `cornerSize` 24dp.
    static let cornerRadius: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            // 40×40 동그라미 바탕에 안쪽 여백 10 — 그림은 20×20 이다(`bg_route_icon` +
            // `android:padding="10dp"`). 바탕·그림 색은 bind 가 머무름/이동으로 고른다.
            Image(systemName: Self.그림_이름(row.icon))
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(row.icon == .stay ? KidCarePalette.apricot : KidCarePalette.berry)
                .frame(width: 40, height: 40)
                .background(row.icon == .stay ? KidCarePalette.apricotSoft : KidCarePalette.berrySoft, in: Circle())
                .accessibilityHidden(true) // 안드로이드 `importantForAccessibility="no"`

            // textAppearanceBodyMedium(15sp), 한 줄, 끝 줄임.
            Text(제목)
                .font(.subheadline)
                .foregroundStyle(KidCarePalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .padding(.top, 5)

            // textAppearanceBodySmall(13sp), 두 줄까지, 끝 줄임, colorOnSurfaceVariant(ink_soft).
            Text(Self.상세_문구(row))
                .font(.footnote)
                .foregroundStyle(KidCarePalette.inkSoft)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .padding(.top, 3)

            if let routeState = row.routeState {
                // 통합 검토 M2: 정본은 `route_state`(sky 글자, `bg_date_pill` 바탕 —
                // sky_soft, 반지름 22) — 이동 카드에만 붙는다.
                Text(String(localized: routeState == .hidden ? "timeline_route_hidden" : "timeline_route_visible"))
                    .font(.caption.weight(.medium)) // textAppearanceLabelSmall(12sp, medium)
                    .foregroundStyle(KidCarePalette.sky)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: Self.cardWidth)
        .frame(maxHeight: .infinity) // layout_height="match_parent", gravity="center"
        .background(
            KidCarePalette.paperCard,
            in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(KidCarePalette.lineSoft, lineWidth: 1)
        )
        // cardElevation 2dp 에 가까운 옅은 그림자.
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        // 숨긴 이동 카드는 흐리게 — 안드로이드 `binding.root.alpha = 0.62f` 와 같은 값.
        .opacity(row.routeState == .hidden ? 0.62 : 1)
        // 제목·시각·표시 상태를 한 덩어리로 읽어준다(안드로이드는 카드 전체가 하나의
        // 클릭 대상이라 TalkBack 이 그 안의 글자를 이어 읽는다).
        .accessibilityElement(children: .combine)
    }

    /// 머무름은 장소 탭과 같은 그림(`GuardianTab.place` 의 `mappin.and.ellipse` —
    /// 안드로이드 `ic_tab_place`), 이동은 안드로이드 `ic_route`(왼쪽 위 점에서 굽은 길을
    /// 따라 오른쪽 아래 점으로 가는 모양)와 가장 가까운 SF Symbol 이다.
    static func 그림_이름(_ icon: TimelineIcon) -> String {
        switch icon {
        case .stay: "mappin.and.ellipse"
        case .move: "point.topleft.down.to.point.bottomright.curvepath.fill"
        }
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

    /// 시각 범위를 첫 줄에, 기간을 둘째 줄에 둔다 — 안드로이드 이 화면 자신의 키
    /// `timeline_detail`("%1$s\n%2$s")을 그대로 쓴다. 한 줄 목록이던 때 만든 iOS 전용
    /// `timeline_detail_inline` 은 카드로 바꾸면서 쓸 곳이 없어져 지웠다.
    static func 상세_문구(_ row: TimelineRow) -> String {
        String(format: String(localized: "timeline_detail"), timeRangeText(row.detail), durationText(row.duration))
    }
}
