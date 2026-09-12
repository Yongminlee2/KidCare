import Foundation

/// 그 해 공휴일을 계산해 준다. 음력 환산은 iOS 가 들고 있는 `Calendar(identifier:
/// .chinese)` 를 쓴다.
///
/// **표를 안 쓴 이유가 이 파일의 요점이다.** 설날·추석·부처님오신날은 음력이라
/// 해마다 옮겨 다니는데, 몇 해치를 코드에 적어 두면 그 해가 지나는 순간 앱이 조용히
/// 틀린다 — 부모는 공휴일에 쉬는 줄 알고 있는데 아이 폰만 평일처럼 무음이 된다.
/// `Calendar(identifier: .chinese)` 는 기기 OS 에 들어 있고 천문 계산으로 음력을
/// 뽑으므로 표를 갱신할 일이 없다. 안드로이드는 같은 이유로 ICU `ChineseCalendar` 를
/// 쓴다 — 구현은 다르지만 두 플랫폼이 같은 답을 내야 한다(`HolidayCalendarTests` 가
/// 이미 확인된 아홉 값으로 그걸 못박는다).
///
/// 정본은 안드로이드 `core/HolidayCalendar.kt` 다.
///
/// ## 음력 연도를 어떻게 찾는가
///
/// `Calendar(identifier: .chinese)` 의 `year`/`era` 컴포넌트는 양력 연도가 아니라
/// 60년 주기(갑자)와 그 안에서의 해다. 그래서 "2025년의 음력 설날"을 바로 만들 수
/// 없고, 먼저 그 양력 해 **안에 반드시 걸리는** 기준 날짜(7월 1일)를 중국력으로
/// 환산해 그 해의 (era, year) 를 얻은 다음, 같은 (era, year) 에 원하는 음력 월·일을
/// 넣어 되돌린다. 7월 1일을 고른 이유: 설날은 그 양력 해의 1~2월에 오고 다음 설날
/// (=다음 음력 해의 시작)은 그 다음해 1~2월에야 오므로, 7월이면 두 경계 모두에서
/// 충분히 떨어져 있어 절대 옆 음력 해로 잘못 걸릴 일이 없다.
///
/// ## 한계 하나는 알고 쓴다
///
/// 우리 음력은 한국 시각(UTC+9) 기준인데, `Calendar(identifier: .chinese)` 자체는
/// 표준시를 모르고 우리가 지정한 시간대로만 날짜 경계를 정한다. 그래서 이 파일은
/// 모든 계산에 `TimeZone(identifier: "Asia/Seoul")` 을 명시한다 — 기기 시간대가
/// 다르면(예: 유학 중인 부모 폰) 삭(달의 위상)이 자정 언저리에 걸리는 드문 해에
/// 하루가 어긋날 수 있기 때문이다.
enum HolidayCalendar {

    private static let seoul = TimeZone(identifier: "Asia/Seoul")!

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        return calendar
    }

    private static var chinese: Calendar {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = seoul
        return calendar
    }

    /// [캐시를 두지 않는 이유] 코틀린 쪽은 해마다 한 번만 계산하면 되는 값이라
    /// `@Synchronized` 캐시를 들고 있는다. 스위프트 6 의 엄격한 동시성 규칙에서는
    /// 전역 가변 상태를 안전하게 캐시하려면 액터가 필요한데, 그러면 이 함수들이
    /// 전부 `async` 가 돼 버려 아래 인터페이스(동기 함수)와 맞지 않는다.
    /// `nonisolated(unsafe)` 나 `@unchecked Sendable` 로 우회하는 대신, 계산 자체가
    /// 가벼우니(달력 변환 세 번과 딕셔너리 몇 줄) 매번 다시 계산하는 쪽을 택했다.
    static func of(year: Int) -> [DateComponents: Holiday] {
        guard let anchors = anchors(year: year) else { return [:] }
        return KoreanHolidays.of(year: year, anchors: anchors)
    }

    /// [date] 언저리의 공휴일. 앞뒤 해까지 함께 주는 이유는 연말연시다 — 설날이 1월 초면
    /// 연휴가 전해 12월로 넘어가고, 예약 판정은 늘 며칠 앞뒤를 함께 훑는다.
    static func around(date: DateComponents) -> Set<DateComponents> {
        guard let year = date.year else { return [] }
        return Set(of(year: year - 1).keys)
            .union(of(year: year).keys)
            .union(of(year: year + 1).keys)
    }

    /// [from] 이후(당일 포함) 가장 이른 공휴일. 없으면 nil — 화면이 다음 쉬는 날을 알려줄 때 쓴다.
    static func next(from: DateComponents) -> (DateComponents, Holiday)? {
        guard let year = from.year else { return nil }
        let candidates = of(year: year).merging(of(year: year + 1)) { current, _ in current }
        return candidates
            .filter { !isBefore($0.key, from) }
            .min { isBefore($0.key, $1.key) }
            .map { ($0.key, $0.value) }
    }

    /// 그 해 음력 세 기준일(설날·추석·부처님오신날)을 양력으로 환산한다. `Calendar
    /// (identifier: .chinese)` 가 이 해를 못 다루면(기기가 지원하지 않는 먼 미래/과거
    /// 등) nil 을 돌려준다 — 공휴일을 모르는 채로 도는 것이 맞지, 넘겨짚은 날짜로
    /// 예약을 쉬게 하면 안 된다(코틀린의 판단을 그대로 옮긴다).
    static func anchors(year: Int) -> LunarAnchors? {
        guard
            let seollal = solar(forGregorianYear: year, lunarMonth: 1, lunarDay: 1),
            let chuseok = solar(forGregorianYear: year, lunarMonth: 8, lunarDay: 15),
            let buddha = solar(forGregorianYear: year, lunarMonth: 4, lunarDay: 8)
        else { return nil }
        return LunarAnchors(seollal: seollal, chuseok: chuseok, buddha: buddha)
    }

    /// 음력 [lunarMonth]월 [lunarDay]일(윤달 아님)이 [year]년(양력) 음력 해에서 가리키는
    /// 양력 날짜.
    private static func solar(forGregorianYear year: Int, lunarMonth: Int, lunarDay: Int) -> DateComponents? {
        let gregorian = self.gregorian
        let chinese = self.chinese

        // 그 양력 해의 7월 1일이 속한 음력 해의 (era, year) 를 얻는다 — 위 타입
        // 문서의 "음력 연도를 어떻게 찾는가" 참고.
        guard
            let midYear = gregorian.date(from: DateComponents(year: year, month: 7, day: 1))
        else { return nil }
        let lunarYear = chinese.dateComponents([.era, .year], from: midYear)
        guard let era = lunarYear.era, let cycleYear = lunarYear.year else { return nil }

        var target = DateComponents()
        target.era = era
        target.year = cycleYear
        target.month = lunarMonth
        target.day = lunarDay
        target.isLeapMonth = false
        guard let date = chinese.date(from: target) else { return nil }

        let solar = gregorian.dateComponents([.year, .month, .day], from: date)
        guard solar.year != nil, solar.month != nil, solar.day != nil else { return nil }
        // Calendar.dateComponents(_:from:) 의 결과에는 calendar/timeZone 필드가 함께
        // 실려 있어, 연·월·일만 담은 DateComponents 와 비교하면(Dictionary 키로 쓸 때)
        // 같은 날짜인데도 다르게 취급될 수 있다. 연·월·일만 남긴 값으로 다시 감싼다.
        return DateComponents(year: solar.year, month: solar.month, day: solar.day)
    }

    private static func isBefore(_ a: DateComponents, _ b: DateComponents) -> Bool {
        guard let ay = a.year, let am = a.month, let ad = a.day,
              let by = b.year, let bm = b.month, let bd = b.day
        else { return false }
        return (ay, am, ad) < (by, bm, bd)
    }
}
