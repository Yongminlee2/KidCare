import Testing
@testable import KidCare
import Foundation

/// 정본은 안드로이드 `TimelineAdapter.Holder.bind` 와
/// `MapTimelineFragment.renderTimeline`(:1011). 머무름/이동 아이콘, 이름 없는
/// 머무름, 거리 표시 유무를 브리프가 그대로 못 박았다.
struct TimelineRowTests {

    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    private func stayDoc(startAt: Int64, endAt: Int64, placeName: String) -> SegmentDoc {
        SegmentDoc([
            "type": "STAY", "startAt": startAt, "endAt": endAt,
            "lat": 37.5, "lng": 127.0, "distanceMeters": 0.0, "pointCount": 3,
            "placeName": placeName,
        ])!
    }

    private func moveDoc(startAt: Int64, endAt: Int64, distanceMeters: Double) -> SegmentDoc {
        SegmentDoc([
            "type": "MOVE", "startAt": startAt, "endAt": endAt,
            "lat": 37.5, "lng": 127.0, "distanceMeters": distanceMeters, "pointCount": 5,
            "placeName": "",
        ])!
    }

    @Test("머무름은 stay 아이콘과 장소 이름을 담는다")
    func 머무름은_stay_아이콘() {
        let docs = [stayDoc(startAt: 1_757_000_000_000, endAt: 1_757_000_000_000 + 3_600_000, placeName: "△△초등학교")]
        let rows = Timeline.timelineRows(from: docs, zone: seoul)

        #expect(rows.count == 1)
        #expect(rows[0].icon == .stay)
        #expect(rows[0].title == "△△초등학교")
        #expect(rows[0].distance == nil) // 머무름은 거리를 안 보여준다.
        #expect(rows[0].segmentIndex == 0)
        // Task 8: 탭-포커스·경로 숨김이 쓰는 값들 — SegmentDoc 의 값을 그대로 옮긴다.
        #expect(rows[0].startAt == 1_757_000_000_000)
        #expect(rows[0].lat == 37.5)
        #expect(rows[0].lng == 127.0)
    }

    @Test("이름 없는 머무름은 '머무른 곳'으로 대체한다")
    func 이름_없는_머무름은_대체_문구() {
        let docs = [stayDoc(startAt: 1_757_000_000_000, endAt: 1_757_000_000_000 + 600_000, placeName: "")]
        let rows = Timeline.timelineRows(from: docs, zone: seoul)

        #expect(rows[0].title == String(localized: "timeline_unknown_place"))
    }

    @Test("이동은 move 아이콘과 거리를 담는다")
    func 이동은_move_아이콘과_거리() {
        let docs = [moveDoc(startAt: 1_757_000_000_000, endAt: 1_757_000_000_000 + 600_000, distanceMeters: 480.0)]
        let rows = Timeline.timelineRows(from: docs, zone: seoul)

        #expect(rows[0].icon == .move)
        #expect(rows[0].distance == .meters(480))
    }

    @Test("시각·기간은 SegmentSummarizer 값을 그대로 옮긴다")
    func 시각_기간을_그대로_옮긴다() {
        let start: Int64 = 1_757_000_000_000
        let end = start + 90 * 60_000
        let docs = [moveDoc(startAt: start, endAt: end, distanceMeters: 1_200.0)]
        let rows = Timeline.timelineRows(from: docs, zone: seoul)

        let expectedSegment = Segment(type: .move, startAt: start, endAt: end, lat: 37.5, lng: 127.0, distanceMeters: 1_200.0, pointCount: 5)
        #expect(rows[0].detail == SegmentSummarizer.timeRange(expectedSegment, zone: seoul))
        #expect(rows[0].duration == .hoursMinutes(1, 30))
        #expect(rows[0].distance == .kilometers(1.2))
    }

    @Test("여러 구간이 순서대로 segmentIndex 를 받는다")
    func 여러_구간의_인덱스() {
        let docs = [
            stayDoc(startAt: 0, endAt: 600_000, placeName: "집"),
            moveDoc(startAt: 600_000, endAt: 1_200_000, distanceMeters: 300.0),
            stayDoc(startAt: 1_200_000, endAt: 2_400_000, placeName: "학교"),
        ]
        let rows = Timeline.timelineRows(from: docs, zone: seoul)

        #expect(rows.map(\.segmentIndex) == [0, 1, 2])
        #expect(rows.map(\.icon) == [.stay, .move, .stay])
    }

    @Test("빈 하루는 빈 목록이다")
    func 빈_하루는_빈_목록() {
        #expect(Timeline.timelineRows(from: [], zone: seoul).isEmpty)
    }

    @Test("M2: 이동 행만 경로 표시 상태를 갖고, startAt 이 숨김 목록에 있으면 hidden 이다")
    func 이동_행의_경로_표시_상태() {
        let docs = [
            stayDoc(startAt: 0, endAt: 600_000, placeName: ""),
            moveDoc(startAt: 600_000, endAt: 1_200_000, distanceMeters: 300.0),
            moveDoc(startAt: 1_200_000, endAt: 1_800_000, distanceMeters: 500.0),
        ]
        let rows = Timeline.timelineRows(from: docs, zone: seoul, hiddenMoveStarts: [1_200_000])

        #expect(rows[0].routeState == nil) // 머무름에는 표시가 없다(안드로이드 GONE)
        #expect(rows[1].routeState == .visible)
        #expect(rows[2].routeState == .hidden)
    }

    @Test("카드 상세는 안드로이드 키 timeline_detail 로 시각 범위와 기간을 두 줄에 나눈다")
    func 카드_상세는_timeline_detail_두_줄() {
        let start: Int64 = 1_757_000_000_000
        let docs = [stayDoc(startAt: start, endAt: start + 90 * 60_000, placeName: "")]
        let row = Timeline.timelineRows(from: docs, zone: seoul)[0]

        let detail = TimelineRowView.상세_문구(row)
        #expect(detail == String(format: String(localized: "timeline_detail"), timeRangeText(row.detail), durationText(row.duration)))
        let lines = detail.components(separatedBy: "\n")
        #expect(lines == [timeRangeText(row.detail), durationText(row.duration)])
    }
}
