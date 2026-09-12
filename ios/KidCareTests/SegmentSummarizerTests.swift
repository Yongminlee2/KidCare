import Testing
@testable import KidCare
import Foundation

/// 정본은 안드로이드 `logic/SegmentSummarizerTest.kt` 다. 케이스 하나하나를 같은 뜻으로 옮긴다.
///
/// 한국어 문장을 기대하던 자리는 구조 값을 기대하도록 바꿨다 —
/// `"1시간 50분"` → `.hoursMinutes(1, 50)`, `"480m"` → `.meters(480)`,
/// `"1.2km"` → `.kilometers(1.2)`. 문장으로 바꾸는 일은 뷰 레이어의 몫이다.
///
/// 코틀린 테스트의 `text.length == 11` / `text[5] == '~'` 처럼 서식(자릿수 맞춤,
/// 구분자 위치)만 확인하던 단언은 옮기지 않는다 — `TimeRange`가 이미 구조로
/// 시·분을 나누어 담고 있어 그 모양 자체가 타입으로 보장된다. 그 서식(제로 패딩,
/// `~` 로 잇기)은 문구 카탈로그의 서식 문자열로 옮겨갔다.
struct SegmentSummarizerTests {

    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    private func segment(start: Int64, end: Int64) -> Segment {
        Segment(type: .stay, startAt: start, endAt: end, lat: 37.5, lng: 127.0, distanceMeters: 0.0, pointCount: 2)
    }

    // MARK: - timeRange

    @Test("시각 범위를 시분으로 보여준다")
    func 시각_범위를_시분으로_보여준다() {
        let start: Int64 = 1_786_000_200_000
        let end = start + 90 * 60_000

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = seoul
        let startComps = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: Double(start) / 1000))
        let endComps = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: Double(end) / 1000))
        let expected = TimeRange(
            startHour: startComps.hour!, startMinute: startComps.minute!,
            endHour: endComps.hour!, endMinute: endComps.minute!
        )

        #expect(SegmentSummarizer.timeRange(segment(start: start, end: end), zone: seoul) == expected)
    }

    @Test("자정을 넘는 구간도 시분만 보여준다")
    func 자정을_넘는_구간도_시분만_보여준다() {
        // 날짜별로 나눠 보여주는 화면이라 날짜는 헤더가 담당한다. 여기서는 시분만 —
        // 12시간을 더해도 endHour 가 24 를 넘기지 않고(다음 날의) 시각으로 감긴다.
        let start: Int64 = 1_786_000_200_000
        let end = start + 12 * 3_600_000

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = seoul
        let startComps = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: Double(start) / 1000))
        let endComps = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: Double(end) / 1000))
        let expected = TimeRange(
            startHour: startComps.hour!, startMinute: startComps.minute!,
            endHour: endComps.hour!, endMinute: endComps.minute!
        )

        let result = SegmentSummarizer.timeRange(segment(start: start, end: end), zone: seoul)
        #expect(result == expected)
        #expect((0...23).contains(result.endHour)) // 24 시간 표기가 아니라 그 날의 시각으로 감긴다.
    }

    @Test("시간대가 다르면 표시도 달라진다")
    func 시간대가_다르면_표시도_달라진다() {
        let start: Int64 = 1_786_000_200_000
        let seoulResult = SegmentSummarizer.timeRange(segment(start: start, end: start + 60_000), zone: seoul)
        let utcResult = SegmentSummarizer.timeRange(segment(start: start, end: start + 60_000), zone: TimeZone(identifier: "UTC")!)

        #expect(seoulResult != utcResult) // 서울과 UTC 는 9시간 차이라 같을 수 없다.
    }

    // MARK: - duration

    @Test("한 시간 이상이면 시간과 분을 함께 담는다")
    func 한_시간_이상이면_시간과_분을_함께_담는다() {
        #expect(SegmentSummarizer.duration(millis: 90 * 60_000) == .hoursMinutes(1, 30))
        #expect(SegmentSummarizer.duration(millis: 125 * 60_000) == .hoursMinutes(2, 5))
    }

    @Test("정각이면 분 없이 시간만 담는다")
    func 정각이면_분_없이_시간만_담는다() {
        #expect(SegmentSummarizer.duration(millis: 120 * 60_000) == .hours(2))
        #expect(SegmentSummarizer.duration(millis: 60 * 60_000) == .hours(1)) // 정확히 1시간 경계.
    }

    @Test("한 시간 미만이면 분만 담는다")
    func 한_시간_미만이면_분만_담는다() {
        #expect(SegmentSummarizer.duration(millis: 25 * 60_000) == .minutes(25))
    }

    @Test("1분 미만은 따로 표기한다")
    func 일분_미만은_따로_표기한다() {
        #expect(SegmentSummarizer.duration(millis: 30_000) == .underOneMinute)
        #expect(SegmentSummarizer.duration(millis: 0) == .underOneMinute)
    }

    @Test("59초와 60초가 1분 경계를 가른다")
    func 오십구초와_육십초가_일분_경계를_가른다() {
        #expect(SegmentSummarizer.duration(millis: 59_000) == .underOneMinute)
        #expect(SegmentSummarizer.duration(millis: 60_000) == .minutes(1))
    }

    // MARK: - distance

    @Test("1km 이상은 킬로미터로 소수 한 자리까지 담는다")
    func 일km_이상은_킬로미터로_소수_한_자리까지_담는다() {
        #expect(SegmentSummarizer.distance(meters: 1234.0) == .kilometers(1.2))
        #expect(SegmentSummarizer.distance(meters: 12_345.0) == .kilometers(12.3))
    }

    @Test("999m 와 1000m 가 미터·킬로미터 경계를 가른다")
    func 미터_999와_1000이_미터_킬로미터_경계를_가른다() {
        #expect(SegmentSummarizer.distance(meters: 999.0) == .meters(990)) // 999 는 아직 미터, 십 단위 내림.
        #expect(SegmentSummarizer.distance(meters: 1000.0) == .kilometers(1.0))
    }

    @Test("1km 미만은 미터로 십 단위까지 담는다")
    func 일km_미만은_미터로_십_단위까지_담는다() {
        // 아이 위치에 1m 단위 정밀도를 보여주는 것은 없는 정확도를 있는 척하는 것이다.
        #expect(SegmentSummarizer.distance(meters: 483.0) == .meters(480))
        #expect(SegmentSummarizer.distance(meters: 51.0) == .meters(50))
    }

    @Test("아주 짧은 거리는 0m 대신 10m 미만으로 담는다")
    func 아주_짧은_거리는_0m_대신_10m_미만으로_담는다() {
        #expect(SegmentSummarizer.distance(meters: 4.0) == .underTenMeters)
        #expect(SegmentSummarizer.distance(meters: 0.0) == .underTenMeters)
    }

    @Test("9m 와 10m 가 10m 미만 경계를 가른다")
    func 미터_9와_10이_10m_미만_경계를_가른다() {
        #expect(SegmentSummarizer.distance(meters: 9.0) == .underTenMeters)
        #expect(SegmentSummarizer.distance(meters: 10.0) == .meters(10))
    }
}
