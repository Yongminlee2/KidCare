import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `logic/KoreanHolidaysTest.kt` 다. 케이스 하나하나를 같은 뜻으로 옮긴다.
///
/// 2025년을 고른 이유(코틀린 주석 그대로): 그 해는 대체공휴일 세 개가 서로 다른
/// 이유로 생겼다 — 삼일절이 토요일(주말 겹침), 어린이날이 부처님오신날과 같은 날
/// (공휴일 겹침), 추석 연휴가 일요일을 물었다(연휴 규칙). 규칙 세 갈래를 한 해로
/// 전부 확인할 수 있다.
struct KoreanHolidaysTests {

    private func d(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private func anchors2025() -> LunarAnchors {
        LunarAnchors(seollal: d(2025, 1, 29), chuseok: d(2025, 10, 6), buddha: d(2025, 5, 5))
    }

    private func anchors2026() -> LunarAnchors {
        LunarAnchors(seollal: d(2026, 2, 17), chuseok: d(2026, 9, 25), buddha: d(2026, 5, 24))
    }

    /// 기기 로케일과 무관하게 코틀린의 `LocalDate.dayOfWeek` 와 같은 답을 내야 하므로,
    /// 프로덕션과 똑같이 UTC 로 고정한 그레고리력으로 직접 잰다(이 테스트만의 확인용).
    private func isSaturday(_ date: DateComponents) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.component(.weekday, from: calendar.date(from: date)!) == 7
    }

    @Test("2025년 공휴일이 실제와 같다")
    func 이천이십오년_공휴일이_실제와_같다() {
        let days = Set(KoreanHolidays.of(year: 2025, anchors: anchors2025()).keys)
        let expected: Set<DateComponents> = [
            d(2025, 1, 1),
            d(2025, 1, 28), d(2025, 1, 29), d(2025, 1, 30),   // 설 연휴 (화·수·목 — 대체 없음)
            d(2025, 3, 1), d(2025, 3, 3),                      // 삼일절 토요일 → 월요일 대체
            d(2025, 5, 5), d(2025, 5, 6),                      // 어린이날 = 부처님오신날 → 대체
            d(2025, 6, 6),
            d(2025, 8, 15),
            d(2025, 10, 3),
            d(2025, 10, 5), d(2025, 10, 6), d(2025, 10, 7),    // 추석 연휴 (일·월·화)
            d(2025, 10, 8),                                    // 연휴가 일요일을 물어 대체
            d(2025, 10, 9),
            d(2025, 12, 25),
        ]
        #expect(days == expected)
    }

    @Test("2026년 공휴일이 실제와 같다")
    func 이천이십육년_공휴일이_실제와_같다() {
        let days = Set(KoreanHolidays.of(year: 2026, anchors: anchors2026()).keys)
        let expected: Set<DateComponents> = [
            d(2026, 1, 1),
            d(2026, 2, 16), d(2026, 2, 17), d(2026, 2, 18),    // 설 연휴 (월·화·수)
            d(2026, 3, 1), d(2026, 3, 2),                      // 삼일절 일요일 → 대체
            d(2026, 5, 5),
            d(2026, 5, 24), d(2026, 5, 25),                    // 부처님오신날 일요일 → 대체
            d(2026, 6, 6),                                     // 현충일 토요일 — 대체 없음
            d(2026, 8, 15), d(2026, 8, 17),                    // 광복절 토요일 → 월요일 대체
            d(2026, 9, 24), d(2026, 9, 25), d(2026, 9, 26),    // 추석 연휴 (목·금·토)
            d(2026, 10, 3), d(2026, 10, 5),                    // 개천절 토요일 → 일요일 건너뛰고 월요일
            d(2026, 10, 9),
            d(2026, 12, 25),
        ]
        #expect(days == expected)
    }

    @Test("현충일과 신정은 주말에 걸려도 대체공휴일이 없다")
    func 현충일과_신정은_주말에_걸려도_대체공휴일이_없다() {
        // 2026년 현충일은 토요일이다. 규정상 대체 대상이 아니다.
        let y2026 = KoreanHolidays.of(year: 2026, anchors: anchors2026())
        #expect(isSaturday(d(2026, 6, 6)))
        #expect(y2026[d(2026, 6, 8)] == nil, "현충일 다음 월요일이 쉬는 날이 됐다")
    }

    @Test("설 연휴가 토요일만 물면 대체공휴일이 없다")
    func 설_연휴가_토요일만_물면_대체공휴일이_없다() {
        // 연휴 규칙은 일요일만 본다. 2026년 추석(목·금·토)이 그 경우다.
        let days = KoreanHolidays.of(year: 2026, anchors: anchors2026())
        #expect(isSaturday(d(2026, 9, 26)))
        #expect(days[d(2026, 9, 28)] == nil, "토요일만 물었는데 대체공휴일이 생겼다")
    }

    @Test("대체공휴일은 주말에 앉히지 않는다")
    func 대체공휴일은_주말에_앉히지_않는다() {
        // 2026년 개천절은 토요일이고 그 다음 날은 일요일이다. 대체는 월요일이어야 한다.
        let days = KoreanHolidays.of(year: 2026, anchors: anchors2026())
        #expect(days[d(2026, 10, 5)] == .substitute)
        #expect(days[d(2026, 10, 4)] == nil)
    }

    @Test("연휴 이름은 대체공휴일과 구분된다")
    func 연휴_이름은_대체공휴일과_구분된다() {
        let days = KoreanHolidays.of(year: 2026, anchors: anchors2026())
        #expect(days[d(2026, 2, 16)] == .seollal)
        #expect(days[d(2026, 9, 25)] == .chuseok)
        #expect(days[d(2026, 3, 2)] == .substitute)
    }
}
