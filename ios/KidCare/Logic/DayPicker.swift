import Foundation

/// 타임라인 화면의 "며칠치를 보고 있는가"를 다룬다.
///
/// 날짜를 밀리초가 아니라 "2026-08-07" 문자열로 다루는 이유: Firestore 의 segments
/// 문서가 같은 형식의 dayKey 필드를 갖고 있어 그대로 쿼리 조건이 되고, 자정 경계를
/// 밀리초로 계산하다 시간대·서머타임에 어긋나는 실수를 피할 수 있다.
///
/// 정본은 안드로이드 `logic/DayPicker.kt` 다.
///
/// **`headerText`가 아니라 `header`가 구조를 돌려주는 이유:** 코틀린은 "오늘"·"어제"·
/// "8월 5일 (수)" 같은 한국어 문장을 코드 안에서 직접 만들어 돌려준다. 그대로 옮기면
/// `Logic/`에 한국어 리터럴이 박혀 이 프로젝트의 규칙("문구는 오직 문구 카탈로그에만")을
/// 어기고, 6단계에서 `i18n/*.json`으로 문구 카탈로그를 다시 만들 때 그 문자열만 조용히
/// 빠져 영어 기기 사용자에게 한국어가 보이는 사고가 난다. 그래서 여기서는 "오늘인가,
/// 어제인가, 아니면 몇월 며칠 무슨 요일인가"라는 값만 돌려주고, 문구로 바꾸는 일은
/// 화면(뷰 레이어)이 문구 카탈로그의 서식 문자열로 한다. 안드로이드에도 같은 문제가
/// 있지만 이번 작업에서는 고치지 않기로 했다(README 개발일지 참고) — iOS 는 처음부터
/// 구조로 간다.
enum DayHeader: Equatable {
    case today
    case yesterday
    /// weekday: 월=1 … 일=7 (코틀린 `DayOfWeek.value`와 같은 규칙).
    case date(month: Int, day: Int, weekday: Int)
}

enum DayPicker {

    private static let utc = TimeZone(identifier: "UTC")!

    /// 날짜 계산 자체(그레고리력·고정 로케일·YMD·자정 변환)는 `CalendarMath` 가 맡는다
    /// — 여러 `Logic/` 파일이 각자 복사해 갖고 있던 것을 한 곳으로 모은 것이다.
    private typealias YMD = CalendarMath.YMD

    private static func calendar(zone: TimeZone) -> Calendar {
        CalendarMath.calendar(zone: zone)
    }

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    private static func format(_ ymd: YMD) -> String {
        "\(pad(ymd.year, 4))-\(pad(ymd.month, 2))-\(pad(ymd.day, 2))"
    }

    private static func parse(_ dayKey: String) -> YMD {
        let parts = dayKey.split(separator: "-")
        return YMD(year: Int(parts[0])!, month: Int(parts[1])!, day: Int(parts[2])!)
    }

    private static func dateAtMidnight(_ ymd: YMD, zone: TimeZone) -> Date {
        CalendarMath.dateAtMidnight(ymd, zone: zone)
    }

    private static func ymd(of date: Date, zone: TimeZone) -> YMD {
        CalendarMath.ymd(of: date, zone: zone)
    }

    static func todayKey(zone: TimeZone, nowMillis: Int64) -> String {
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1000)
        return format(ymd(of: now, zone: zone))
    }

    /// 날짜 문자열끼리만 다룬다 — 코틀린의 `LocalDate.plusDays`처럼 시간대와 무관한
    /// 순수 달력 계산이라 시그니처에도 `zone`이 없다. 내부적으로는 UTC 자정을 빌려
    /// 계산할 뿐, 그 값 자체가 어떤 실제 시간대를 뜻하지는 않는다.
    static func shift(dayKey: String, days: Int) -> String {
        let start = dateAtMidnight(parse(dayKey), zone: utc)
        let shifted = calendar(zone: utc).date(byAdding: .day, value: days, to: start)!
        return format(ymd(of: shifted, zone: utc))
    }

    static func isFuture(dayKey: String, zone: TimeZone, nowMillis: Int64) -> Bool {
        let target = parse(dayKey)
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1000)
        let today = ymd(of: now, zone: zone)
        if target.year != today.year { return target.year > today.year }
        if target.month != today.month { return target.month > today.month }
        return target.day > today.day
    }

    /// "오늘" / "어제" / "8월 5일 (수)"에 해당하는 값. 최근 이틀은 날짜보다 이름이
    /// 빨리 읽힌다.
    static func header(dayKey: String, zone: TimeZone, nowMillis: Int64) -> DayHeader {
        let target = parse(dayKey)
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1000)
        let today = ymd(of: now, zone: zone)
        if target == today { return .today }
        let yesterday = ymd(of: calendar(zone: zone).date(byAdding: .day, value: -1, to: dateAtMidnight(today, zone: zone))!, zone: zone)
        if target == yesterday { return .yesterday }
        // Foundation 의 weekday 컴포넌트는 일=1…토=7 이라 코틀린 DayOfWeek.value(월=1…일=7)로 바꾼다
        // (`CalendarMath.weekday` — 이 변환 자체는 `CalendarMathTests` 가 7일 전부를 못박는다).
        let weekday = CalendarMath.weekday(target, zone: zone)
        return .date(month: target.month, day: target.day, weekday: weekday)
    }

    /// 그 날의 시작(포함)과 끝(제외) 밀리초. 지도가 그 날의 점만 그릴 때 쓴다.
    static func range(dayKey: String, zone: TimeZone) -> Range<Int64> {
        let target = parse(dayKey)
        let start = dateAtMidnight(target, zone: zone)
        let end = calendar(zone: zone).date(byAdding: .day, value: 1, to: start)!
        let startMillis = Int64((start.timeIntervalSince1970 * 1000).rounded())
        let endMillis = Int64((end.timeIntervalSince1970 * 1000).rounded())
        return startMillis..<endMillis
    }
}
