import Foundation

/// 시간대 규칙 하나. 정본은 안드로이드 `logic/ScheduleResolver.kt` 의 `ScheduleRule` 이다.
///
/// [days] 는 요일 집합이다. 코틀린 `DayOfWeek.value` 와 같은 규칙으로
/// 1=월 ~ 7=일 (`DayPicker` 의 요일 인덱싱과 동일 — Foundation 의 `weekday`
/// 컴포넌트는 일=1…토=7 이라 그대로 쓰면 안 된다).
/// [startMinute]/[endMinute] 은 자정부터 잰 분(0..1439). `endMinute <= startMinute`
/// 이면 자정을 넘는 규칙이다(예: 22:00~07:00 은 1320..420).
///
/// 이 파일은 입력을 검증하지 않는다 — 규칙 편집 화면이 이미 막아 둔 것을 여기서
/// 다시 막지 않는다(코틀린과 같은 판단).
struct ScheduleRule: Equatable {
    let id: String
    let days: Set<Int>
    let startMinute: Int
    let endMinute: Int
    let mode: String
    let enabled: Bool
    let priority: Int
}

/// 어떤 순간의 판정 결과.
///
/// [mode] 는 그 순간 강제되는 벨소리 모드(없으면 nil).
/// [nextBoundaryMillis] 는 이 판정이 바뀌는 다음 시각(시작 또는 끝). 영원히 안 바뀌면 nil.
struct Resolution: Equatable {
    let mode: String?
    let nextBoundaryMillis: Int64?
}

/// 시간대 규칙을 "지금 이 순간" 에 대해 해석한다.
///
/// 분 단위(0..1439) 를 직접 비교하지 않는다. 자정을 넘는 규칙(22:00~07:00 같은)을 분으로
/// 비교하려 하면 경계마다 조건이 늘어나고, 요일까지 얽히면(자정 넘어 다음날로 이어지는데
/// 요일은 어제 기준) 실수하기 딱 좋다.
///
/// 대신 규칙을 후보 날짜들에 대해 구체적인 [시작, 끝) 밀리초 구간으로 펼친 뒤, 그
/// 구간에 지금 시각이 들어있는지만 본다. 자정 넘김은 "끝을 다음 날로 넘긴다"는 한
/// 줄로 끝나고, 요일 판정은 "그 구간이 시작하는 날의 요일"이라는 정의를 그대로 코드로
/// 옮기면 된다.
///
/// `Logic/` 규칙대로 Foundation 만 임포트한다 — zone 과 시각(밀리초)은 항상 인자로
/// 받고 `TimeZone.current`/`Date()` 는 쓰지 않는다.
enum ScheduleResolver {

    /// [nextBoundaryMillis] 를 찾으려고 앞으로 훑는 최대 일수. 규칙은 최대 7일 주기(요일)
    /// 이므로 이론상 8일 안에 반드시 다음 시작이나 끝을 만난다. 여유를 둬서 10일로 잡는다.
    /// 이 안에 못 찾으면(=활성 규칙이 전혀 없으면) nil 을 돌려준다.
    private static let searchHorizonDays = 10

    private static let minutesPerDay = 24 * 60
    private static let minuteMillis: Int64 = 60_000

    /// 날짜 계산 자체(그레고리력·고정 로케일·YMD·자정 변환)는 `CalendarMath` 가 맡는다
    /// (`DayPicker` 와 같은 이유로 로케일을 고정한다 — 기기가 일본 연호력·불기력이어도
    /// 답은 같아야 한다) — 여러 `Logic/` 파일이 각자 복사해 갖고 있던 것을 한 곳으로 모은 것이다.
    private typealias YMD = CalendarMath.YMD

    private static func calendar(zone: TimeZone) -> Calendar {
        CalendarMath.calendar(zone: zone)
    }

    /// 규칙 하나가 특정 날짜에 시작할 때 만드는 [시작, 끝) 구간. 자정을 넘으면 끝이 다음 날.
    private struct Interval {
        let rule: ScheduleRule
        let startAt: Int64
        let endAt: Int64
    }

    private static func ymd(of date: Date, zone: TimeZone) -> YMD {
        CalendarMath.ymd(of: date, zone: zone)
    }

    private static func dateAtMidnight(_ value: YMD, zone: TimeZone) -> Date {
        CalendarMath.dateAtMidnight(value, zone: zone)
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func addDays(_ from: YMD, _ delta: Int, zone: TimeZone) -> YMD {
        let midnight = dateAtMidnight(from, zone: zone)
        let shifted = calendar(zone: zone).date(byAdding: .day, value: delta, to: midnight)!
        return ymd(of: shifted, zone: zone)
    }

    /// Foundation 의 weekday 컴포넌트는 일=1…토=7 이라, 코틀린 DayOfWeek.value(월=1…일=7)
    /// 로 바꾼다(`CalendarMath.weekday` — `DayPicker.header` 와 같은 변환을 한 곳에서 쓴다).
    private static func weekday(_ value: YMD, zone: TimeZone) -> Int {
        CalendarMath.weekday(value, zone: zone)
    }

    /// 연·월·일만 담은 "맨몸" DateComponents — `KoreanHolidays`/`HolidayCalendar` 가
    /// 만드는 공휴일 집합의 키와 같은 모양이어야 Set 비교가 맞는다(calendar/timeZone
    /// 필드가 실려 있으면 같은 날짜인데도 다르게 취급된다).
    private static func bareComponents(_ value: YMD) -> DateComponents {
        DateComponents(year: value.year, month: value.month, day: value.day)
    }

    /// [rule] 이 [anchor] 에 시작한다고 볼 때의 구간. 그 날 요일이 days 에 없으면 nil.
    ///
    /// [holidays] 에 든 날에는 어떤 규칙도 **시작하지 않는다**. 판정을 시작일 기준으로만
    /// 하는 것은 요일과 똑같은 규칙이다 — "평일 22:00~07:00" 이 금요일 밤에 시작해
    /// 토요일 새벽까지 이어지듯, 목요일 밤에 시작한 규칙은 금요일이 공휴일이어도 그
    /// 아침까지는 이어진다. 부모가 정한 것은 "언제 시작하는가"이므로 그 기준을 한 곳에 둔다.
    private static func intervalStartingOn(
        rule: ScheduleRule, anchor: YMD, zone: TimeZone, holidays: Set<DateComponents>
    ) -> Interval? {
        let weekdayValue = weekday(anchor, zone: zone) // 1=월 ~ 7=일, days 와 같은 규칙
        guard rule.days.contains(weekdayValue) else { return nil }
        guard !holidays.contains(bareComponents(anchor)) else { return nil }
        let dayStart = millis(dateAtMidnight(anchor, zone: zone))
        let startAt = dayStart + Int64(rule.startMinute) * minuteMillis
        // 자정을 넘는 규칙: 끝이 시작보다 이르거나 같으면 다음 날로 넘긴다.
        // startMinute == endMinute 인 경우도 이 분기를 탄다 — 그러면 [시작, 끝) 이
        // 정확히 24시간짜리 구간이 되어 "항상 적용" 이 된다. 이는 의도된 동작이다:
        // "00:00~00:00 무음" 처럼 부모가 하루 종일을 뜻하려고 같은 시각을 넣는 것은
        // 말이 되는 입력이다. 부모가 실수로 같은 시각을 두 칸에 눌러도 똑같이 하루
        // 종일이 되지만, 그 구분은 이 파일이 아니라 화면(저장 전 확인 문구)이 한다.
        let endMinuteAbsolute = rule.endMinute <= rule.startMinute ? rule.endMinute + minutesPerDay : rule.endMinute
        let endAt = dayStart + Int64(endMinuteAbsolute) * minuteMillis
        return Interval(rule: rule, startAt: startAt, endAt: endAt)
    }

    /// [rule] 이 만들어낼 수 있는 모든 구간을, [center] 를 기준으로 [daysBefore]~[daysAfter]
    /// 범위의 시작 날짜들에 대해 펼친다. enabled == false 규칙은 아예 펼치지 않는다.
    private static func expand(
        rule: ScheduleRule, zone: TimeZone, center: YMD,
        daysBefore: Int, daysAfter: Int, holidays: Set<DateComponents>
    ) -> [Interval] {
        guard rule.enabled else { return [] }
        var result: [Interval] = []
        var d = -daysBefore
        while d <= daysAfter {
            let anchor = addDays(center, d, zone: zone)
            if let interval = intervalStartingOn(rule: rule, anchor: anchor, zone: zone, holidays: holidays) {
                result.append(interval)
            }
            d += 1
        }
        return result
    }

    /// [holidays] 에 든 날은 예약이 통째로 쉰다. 빈 집합이면 예전과 똑같이 요일만 본다.
    ///
    /// 공휴일을 요일처럼 규칙 안에 넣지 않고 밖에서 받는 이유: 공휴일은 해마다 자리를
    /// 옮기고(설날·추석·부처님오신날이 음력이다) 대체공휴일은 그 해 요일 배치에 따라
    /// 생겼다 없어진다. 부모가 미리 찍어 둘 수 있는 값이 아니라 그때그때 계산해야 하는
    /// 값이라, 규칙(부모가 정한 것)과 달력(해마다 달라지는 것)을 섞지 않는다.
    static func resolveAt(
        rules: [ScheduleRule], atMillis: Int64, zone: TimeZone, holidays: Set<DateComponents> = []
    ) -> Resolution {
        let today = ymd(of: Date(timeIntervalSince1970: Double(atMillis) / 1000), zone: zone)

        // 지금 시각을 포함하는 구간 후보: 오늘과 어제 시작한 것만 보면 충분하다.
        // 자정 넘김 규칙이라도 길이는 최대 24시간(시작==끝이면 정확히 24시간, 그 외엔
        // 그보다 짧다)을 넘지 않으므로, 그저께 시작한 구간이 오늘까지 이어질 수는 없다.
        let activeCandidates = rules
            .flatMap { expand(rule: $0, zone: zone, center: today, daysBefore: 1, daysAfter: 0, holidays: holidays) }
            .filter { atMillis >= $0.startAt && atMillis < $0.endAt }

        // 겹치면 우선순위가 큰 쪽이 이긴다. 우선순위가 같으면 나중에 시작한(startAt 이
        // 더 큰) 규칙이 이긴다 — 코틀린의 compareByDescending(priority).thenByDescending
        // (startAt) 을 그대로 옮긴 순서다.
        let winner = activeCandidates.max { a, b in
            if a.rule.priority != b.rule.priority { return a.rule.priority < b.rule.priority }
            return a.startAt < b.startAt
        }

        // 다음 경계: 활성/비활성 규칙 모두의 시작·끝 중, 지금보다 뒤에 있는 가장 이른 것.
        // 앞으로 searchHorizonDays 일치를 펼쳐서 찾는다 — 요일 주기가 7일이라 그 안에
        // 반드시 다음 시작을 만나거나, 활성 규칙이 없으면 끝까지 못 찾고 nil 이 된다.
        let allNearby = rules.flatMap {
            expand(rule: $0, zone: zone, center: today, daysBefore: 1, daysAfter: searchHorizonDays, holidays: holidays)
        }
        let nextBoundary = allNearby
            .flatMap { [$0.startAt, $0.endAt] }
            .filter { $0 > atMillis }
            .min()

        return Resolution(mode: winner?.rule.mode, nextBoundaryMillis: nextBoundary)
    }

    static func overlaps(rules: [ScheduleRule], candidate: ScheduleRule) -> [ScheduleRule] {
        // 한 주(요일 주기)를 통째로 펼쳐서 비교한다. 기준일은 아무 날이나 상관없다 —
        // 7일 전부를 시작일 후보로 훑으면 요일 조합에 관계없이 모든 겹침을 잡아낸다.
        let anchor = YMD(year: 2000, month: 1, day: 3) // 임의의 월요일. 요일만 맞으면 어떤 주여도 된다.
        let zone = TimeZone(identifier: "UTC")! // 겹침 판정은 규칙끼리의 상대 위치만 보므로 시간대는 무관하다.

        // candidate 는 자기 자신의 enabled 값과 무관하게 항상 켜진 것으로 취급한다.
        // 이건 "저장 전 겹침 경고" 용도라서 그렇다 — 부모가 지금 꺼 둔 규칙을 편집하는
        // 중이어도, 나중에 켰을 때 다른 규칙과 부딪힐지는 미리 알고 싶어한다. 반대로
        // 비교 대상인 other 쪽은 아래에서 enabled 를 그대로 걸러낸다: 이미 꺼져 있는
        // 다른 규칙과는 지금 겹쳐도 경고할 대상이 아니다. 겹침 경고는 요일 조합만
        // 본다 — 공휴일에 둘 다 안 도는 것은 경고할 일이 아니다.
        let alwaysOnCandidate = ScheduleRule(
            id: candidate.id, days: candidate.days, startMinute: candidate.startMinute,
            endMinute: candidate.endMinute, mode: candidate.mode, enabled: true, priority: candidate.priority
        )
        let candidateIntervals = expand(
            rule: alwaysOnCandidate, zone: zone, center: anchor, daysBefore: 0, daysAfter: 6, holidays: []
        )
        guard !candidateIntervals.isEmpty else { return [] }

        return rules.filter { other in
            guard other.id != candidate.id, other.enabled else { return false }
            let otherIntervals = expand(rule: other, zone: zone, center: anchor, daysBefore: 0, daysAfter: 6, holidays: [])
            return otherIntervals.contains { o in candidateIntervals.contains { c in intervalsOverlap(o, c) } }
        }
    }

    private static func intervalsOverlap(_ a: Interval, _ b: Interval) -> Bool {
        a.startAt < b.endAt && b.startAt < a.endAt
    }
}
