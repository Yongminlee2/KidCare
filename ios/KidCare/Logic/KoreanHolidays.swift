import Foundation

/// 그 해 음력에서 오는 세 기준일. 양력으로 옮긴 값이다.
///
/// 이 셋만 밖에서 받는 이유: 나머지 공휴일은 전부 날짜가 고정이고 대체공휴일은 규칙으로
/// 계산되는데, 음력 환산만은 천문 계산이라 순수 Foundation 만으로 못 한다(고정된 표로
/// 대신하면 해가 지나는 순간 조용히 틀린다). iOS 쪽 변환기는 `Core/HolidayCalendar.swift`
/// 에 있다 — 이 파일이 `Calendar(identifier: .chinese)` 를 안 보게 잘라 둔 경계다
/// (Logic/ 은 Foundation 만 임포트하는 규칙과는 별개로, 순수 계산과 플랫폼 달력 환산을
/// 나누는 것 자체가 이 경계의 목적이다).
struct LunarAnchors {
    /// 음력 1월 1일 (설날). 연·월·일만 쓴다.
    let seollal: DateComponents
    /// 음력 8월 15일 (추석).
    let chuseok: DateComponents
    /// 음력 4월 8일 (부처님오신날).
    let buddha: DateComponents
}

/// 공휴일 이름. 화면 문구는 문구 카탈로그에 있으므로 여기서는 무슨 날인지만 말한다.
enum Holiday: CaseIterable {
    case newYear, seollal, independence, buddha, children, memorial
    case liberation, chuseok, foundation, hangul, christmas, substitute
}

/// 한 해의 관공서 공휴일을 대체공휴일까지 포함해 만든다.
///
/// 요일은 매년 같은 자리에 오지만 공휴일은 아니다 — 설날·추석·부처님오신날은 음력이라
/// 해마다 옮겨 다니고, 대체공휴일은 그 해 요일 배치에 따라 생겼다 없어진다. 그래서
/// 부모가 "공휴일엔 예약을 쉬어요"를 요일로는 절대 표현할 수 없고, 앱이 대신 계산해야
/// 한다. 이 파일이 그 계산이다.
///
/// 정본은 안드로이드 `logic/KoreanHolidays.kt` 다.
///
/// 대체공휴일 규칙(관공서의 공휴일에 관한 규정 제3조, 2023년 개정 기준):
/// - 설날·추석 연휴: 사흘 중 하나라도 **일요일**과 겹치면 하루 더 쉰다. 토요일은 아니다.
/// - 어린이날: 토요일·일요일 또는 **다른 공휴일**과 겹치면 하루 더 쉰다.
/// - 삼일절·광복절·개천절·한글날·부처님오신날·성탄절: 토요일이나 일요일과 겹치면 하루 더.
/// - 신정(1/1)과 현충일(6/6)은 대체공휴일이 없다.
///
/// 대체공휴일 자리는 "그 다음의 첫 번째 비공휴일"인데, 여기서는 주말도 함께 건너뛴다.
/// 법문만 보면 토요일도 비공휴일이라 후보가 되지만, 대체공휴일은 쉬는 날을 채워주려고
/// 있는 제도라 실제 지정은 늘 평일이었다. 이 앱에서 하루가 어긋나면 "쉬는 날인데 폰이
/// 무음으로 바뀐다"가 되므로 실제 운영과 같게 맞춘다.
enum KoreanHolidays {

    private static let newYear = (month: 1, day: 1)
    private static let independence = (month: 3, day: 1)
    private static let children = (month: 5, day: 5)
    private static let memorial = (month: 6, day: 6)
    private static let liberation = (month: 8, day: 15)
    private static let foundation = (month: 10, day: 3)
    private static let hangul = (month: 10, day: 9)
    private static let christmas = (month: 12, day: 25)

    static func of(year: Int, anchors: LunarAnchors) -> [DateComponents: Holiday] {
        func at(_ monthDay: (month: Int, day: Int)) -> DateComponents {
            DateComponents(year: year, month: monthDay.month, day: monthDay.day)
        }

        var days: [DateComponents: Holiday] = [:]
        days[at(newYear)] = .newYear
        days[at(independence)] = .independence
        days[at(children)] = .children
        days[at(memorial)] = .memorial
        days[at(liberation)] = .liberation
        days[at(foundation)] = .foundation
        days[at(hangul)] = .hangul
        days[at(christmas)] = .christmas

        // 설날·추석은 전날·당일·다음날 사흘이다. 부처님오신날은 하루.
        let seolRange = threeDays(around: anchors.seollal)
        let chuseokRange = threeDays(around: anchors.chuseok)
        for date in seolRange { days[date] = .seollal }
        for date in chuseokRange { days[date] = .chuseok }
        // 어린이날과 겹치는 해가 있다(2025년이 그랬다). 먼저 넣은 어린이날을 덮지 않는다 —
        // 겹침은 아래 대체공휴일 판정이 따로 본다.
        if days[anchors.buddha] == nil {
            days[anchors.buddha] = .buddha
        }

        var substitutes = Set<DateComponents>()

        // 설·추석 연휴: 일요일과 겹칠 때만.
        for range in [seolRange, chuseokRange] {
            if range.contains(where: isSunday) {
                substitutes.insert(nextWorkday(after: range.last!, taken: Set(days.keys).union(substitutes)))
            }
        }

        // 어린이날: 주말 또는 다른 공휴일과 겹칠 때.
        let childrensDay = at(children)
        if isWeekend(childrensDay) || childrensDay == anchors.buddha {
            substitutes.insert(nextWorkday(after: childrensDay, taken: Set(days.keys).union(substitutes)))
        }

        // 나머지 대체 대상: 주말과 겹칠 때만.
        let rest = [at(independence), at(liberation), at(foundation), at(hangul), at(christmas), anchors.buddha]
        for date in rest {
            // 부처님오신날이 어린이날과 같은 날이면 위에서 이미 하루를 넣었다. 두 번 넣지 않는다.
            if date == childrensDay { continue }
            if isWeekend(date) {
                substitutes.insert(nextWorkday(after: date, taken: Set(days.keys).union(substitutes)))
            }
        }

        for date in substitutes { days[date] = .substitute }
        return days
    }

    private static func threeDays(around center: DateComponents) -> [DateComponents] {
        [addDays(center, -1), center, addDays(center, 1)]
    }

    /// `from` 다음날부터 훑어 공휴일도 주말도 아닌 첫 날.
    private static func nextWorkday(after from: DateComponents, taken: Set<DateComponents>) -> DateComponents {
        var date = addDays(from, 1)
        while taken.contains(date) || isWeekend(date) {
            date = addDays(date, 1)
        }
        return date
    }

    // MARK: - 순수 날짜 산술
    //
    // 왜 UTC 로 고정하는가: 여기서 하는 계산은 전부 "연·월·일" 만으로 끝나는 순수
    // 날짜 산술(요일 구하기, 하루 더하기/빼기)이라 실제 시각이 필요 없다. 기기의
    // 시간대·달력 설정에 이 계산이 흔들리면(예: 자정 언저리에서 날짜가 밀림) 부모
    // 기기와 아이 기기가 서로 다른 날을 공휴일로 판정할 수 있다 — 그래서 어떤 기기에서
    // 돌든 같은 답이 나오도록 UTC 그레고리력을 직접 골라 쓴다.

    // 그레고리력 팩토리는 `CalendarMath` 가 맡는다(`DayPicker`·`ScheduleResolver`·
    // `SegmentSummarizer` 와 같은 구현을 공유한다) — 로케일을 추가로 고정하는 점은
    // 다르지만(en_US_POSIX), 그레고리력에서 연·월·일·요일 계산은 로케일과 무관해
    // 이 파일이 전에 기대하던 동작과 같다.
    private static let calendar: Calendar = CalendarMath.calendar(zone: TimeZone(identifier: "UTC")!)

    private static func isSunday(_ date: DateComponents) -> Bool {
        weekday(of: date) == 1
    }

    private static func isWeekend(_ date: DateComponents) -> Bool {
        let day = weekday(of: date)
        return day == 1 || day == 7
    }

    /// Foundation 의 그레고리력 `weekday` 는 항상 1=일요일 ... 7=토요일이다(기기의
    /// `firstWeekday` 설정과 무관하다).
    private static func weekday(of date: DateComponents) -> Int {
        calendar.component(.weekday, from: calendar.date(from: date)!)
    }

    private static func addDays(_ date: DateComponents, _ delta: Int) -> DateComponents {
        let shifted = calendar.date(byAdding: .day, value: delta, to: calendar.date(from: date)!)!
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        // Calendar.dateComponents(_:from:) 가 돌려주는 값에는 calendar/timeZone 필드가
        // 함께 실려 있어, 연·월·일만 새로 골라 담은 DateComponents 와 이후 비교했을 때
        // (Dictionary 키·Set 원소로 쓸 때) 같은 날짜인데도 다른 값으로 취급될 수 있다.
        // 그래서 연·월·일만 남긴 "맨몸" DateComponents 로 다시 감싼다.
        return DateComponents(year: components.year, month: components.month, day: components.day)
    }
}
