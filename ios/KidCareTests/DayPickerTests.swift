import Testing
@testable import KidCare
import Foundation

/// 정본은 안드로이드 `logic/DayPickerTest.kt` 다. 케이스 하나하나를 같은 뜻으로 옮긴다.
///
/// 한국어 문장을 기대하던 자리(`"오늘"`, `"8월 5일 (수)"`)는 `DayHeader` 값
/// (`.today`, `.date(month: 8, day: 5, weekday: 3)`)을 기대하도록 바꿨다 —
/// 문구로 바꾸는 일은 이제 뷰 레이어의 몫이다.
struct DayPickerTests {

    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    /// 2026-08-07 14:00 KST
    private var now: Int64 {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 7; comps.hour = 14; comps.minute = 0; comps.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let date = calendar.date(from: comps)!
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    @Test("오늘 키는 기기 시간대 기준이다")
    func 오늘_키는_기기_시간대_기준이다() {
        #expect(DayPicker.todayKey(zone: seoul, nowMillis: now) == "2026-08-07")
    }

    @Test("시간대가 다르면 날짜가 달라질 수 있다")
    func 시간대가_다르면_날짜가_달라질_수_있다() {
        // 서울 8월 7일 14:00 은 UTC 로 8월 7일 05:00 — 같은 날이지만,
        // 서울 8월 7일 08:00 은 UTC 로 8월 6일 23:00 이다.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 7; comps.hour = 8; comps.minute = 0; comps.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let earlyMorningDate = calendar.date(from: comps)!
        let earlyMorning = Int64((earlyMorningDate.timeIntervalSince1970 * 1000).rounded())

        #expect(DayPicker.todayKey(zone: seoul, nowMillis: earlyMorning) == "2026-08-07")
        #expect(DayPicker.todayKey(zone: TimeZone(identifier: "UTC")!, nowMillis: earlyMorning) == "2026-08-06")
    }

    @Test("하루 앞뒤로 옮긴다")
    func 하루_앞뒤로_옮긴다() {
        #expect(DayPicker.shift(dayKey: "2026-08-07", days: -1) == "2026-08-06")
        #expect(DayPicker.shift(dayKey: "2026-08-07", days: 1) == "2026-08-08")
    }

    @Test("월과 해의 경계를 넘는다")
    func 월과_해의_경계를_넘는다() {
        #expect(DayPicker.shift(dayKey: "2026-08-01", days: -1) == "2026-07-31")
        #expect(DayPicker.shift(dayKey: "2026-12-31", days: 1) == "2027-01-01")
    }

    @Test("윤년 2월을 정확히 넘는다")
    func 윤년_2월을_정확히_넘는다() {
        // 2028년은 윤년이다.
        #expect(DayPicker.shift(dayKey: "2028-02-28", days: 1) == "2028-02-29")
        #expect(DayPicker.shift(dayKey: "2028-02-29", days: 1) == "2028-03-01")
    }

    @Test("내일은 미래다")
    func 내일은_미래다() {
        #expect(DayPicker.isFuture(dayKey: "2026-08-08", zone: seoul, nowMillis: now))
        #expect(!DayPicker.isFuture(dayKey: "2026-08-07", zone: seoul, nowMillis: now))
        #expect(!DayPicker.isFuture(dayKey: "2026-08-06", zone: seoul, nowMillis: now))
    }

    @Test("오늘과 어제는 이름으로 부른다")
    func 오늘과_어제는_이름으로_부른다() {
        #expect(DayPicker.header(dayKey: "2026-08-07", zone: seoul, nowMillis: now) == .today)
        #expect(DayPicker.header(dayKey: "2026-08-06", zone: seoul, nowMillis: now) == .yesterday)
    }

    @Test("그 이전은 달·일·요일 값으로 담는다")
    func 그_이전은_달_일_요일_값으로_담는다() {
        // 2026-08-05 는 수요일이다 (코틀린 DayOfWeek.value: 월=1…일=7 이므로 수=3).
        #expect(DayPicker.header(dayKey: "2026-08-05", zone: seoul, nowMillis: now) == .date(month: 8, day: 5, weekday: 3))
    }

    @Test("그 날의 시작은 포함, 다음 날 시작은 제외한다")
    func 그_날의_시작은_포함_다음_날_시작은_제외한다() {
        let range = DayPicker.range(dayKey: "2026-08-07", zone: seoul)
        #expect(range.upperBound - range.lowerBound == 86_400_000) // 서울은 서머타임이 없어 하루가 정확히 24시간이다.
        #expect(range.contains(now))
        #expect(!range.contains(range.upperBound))

        let previousDayRange = DayPicker.range(dayKey: "2026-08-06", zone: seoul)
        #expect(previousDayRange.upperBound == range.lowerBound) // 하루 끝이 다음 하루 시작과 맞물린다.
        #expect(!previousDayRange.contains(now))
    }

    @Test("시간대가 다르면 같은 dayKey 라도 경계 밀리초가 다르다")
    func 시간대가_다르면_같은_dayKey_라도_경계_밀리초가_다르다() {
        let seoulRange = DayPicker.range(dayKey: "2026-08-07", zone: seoul)
        let utcRange = DayPicker.range(dayKey: "2026-08-07", zone: TimeZone(identifier: "UTC")!)
        #expect(seoulRange.lowerBound != utcRange.lowerBound)
    }
}
