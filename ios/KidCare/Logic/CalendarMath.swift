import Foundation

/// `Logic/` 여러 파일이 저마다 만들어 쓰던 "로케일 무관 그레고리력" 계산을 한 곳에 모은다.
///
/// 왜 한 곳으로 모으는가: `DayPicker`·`ScheduleResolver` 가 각자 `calendar(zone:)`·`YMD`·
/// `ymd(of:zone:)`·`dateAtMidnight(_:zone:)` 를 토씨 하나 안 틀리고 복사해 갖고 있었고,
/// Foundation→코틀린 요일 변환(`foundationWeekday == 1 ? 7 : foundationWeekday - 1`)도
/// 두 파일에 그대로 반복돼 있었다. 복사본이 여럿이면 한쪽만 고치는 실수가 나기 쉽다
/// (지도 헤더는 화요일인데 예약은 월요일 규칙으로 도는 식) — 그런데 그 어긋남을 잡아줄
/// 테스트가 지금까지 없었다. 이 파일이 유일한 구현이 되고, `CalendarMathTests` 가 요일
/// 변환을 7일 전부에 대해 못박아 둔다.
///
/// `Logic/` 규칙대로 Foundation 만 임포트한다.
enum CalendarMath {

    /// 로케일에 따라 날짜 계산이 흔들리지 않도록(자릿수 표기·달력 종류 등) 항상
    /// 그레고리력 + 고정 로케일로 계산한다. `DateFormatter`를 쓰지 않는 것도 같은
    /// 이유다 — 코틀린이 `LocalDate`로 얻는 "로케일 무관" 성질을 여기서는 이렇게 지킨다.
    static func calendar(zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = zone
        return calendar
    }

    struct YMD: Equatable {
        let year: Int
        let month: Int
        let day: Int
    }

    static func ymd(of date: Date, zone: TimeZone) -> YMD {
        let comps = calendar(zone: zone).dateComponents([.year, .month, .day], from: date)
        return YMD(year: comps.year!, month: comps.month!, day: comps.day!)
    }

    static func dateAtMidnight(_ value: YMD, zone: TimeZone) -> Date {
        var comps = DateComponents()
        comps.year = value.year
        comps.month = value.month
        comps.day = value.day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return calendar(zone: zone).date(from: comps)!
    }

    /// Foundation 의 weekday 컴포넌트(일=1…토=7)를 코틀린 `DayOfWeek.value`(월=1…일=7)
    /// 로 바꾼다. `DayPicker.header`·`ScheduleResolver.weekday` 가 쓰던 변환과 같다.
    static func kotlinWeekday(foundationWeekday: Int) -> Int {
        foundationWeekday == 1 ? 7 : foundationWeekday - 1
    }

    /// [value] 가 속한 날의 요일을 코틀린 규칙(월=1…일=7)으로 돌려준다.
    static func weekday(_ value: YMD, zone: TimeZone) -> Int {
        let foundationWeekday = calendar(zone: zone).component(.weekday, from: dateAtMidnight(value, zone: zone))
        return kotlinWeekday(foundationWeekday: foundationWeekday)
    }
}
