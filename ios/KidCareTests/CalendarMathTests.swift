import Testing
@testable import KidCare
import Foundation

/// `CalendarMath` 가 모든 `Logic/` 파일이 공유하는 유일한 구현이 된 뒤, 그 중에서도
/// 가장 틀리기 쉬운 값 하나 — Foundation weekday(일=1…토=7) → 코틀린
/// `DayOfWeek.value`(월=1…일=7) 변환 — 을 7일 전부에 대해 못박는다.
///
/// 이 테스트가 없던 것 자체가 위험 요인이었다: `DayPicker`와 `ScheduleResolver`가 같은
/// 변환을 각자 베껴 갖고 있었는데, 한쪽만 고치는 실수를 잡아줄 것이 아무것도 없었다
/// (지도 헤더는 화요일이라는데 예약은 월요일 규칙으로 도는 사고). 지금은 구현이 하나뿐이라
/// 이 테스트 하나로 두 소비자(`DayPicker.header`, `ScheduleResolver`)가 함께 보호된다.
struct CalendarMathTests {

    private let utc = TimeZone(identifier: "UTC")!

    /// 2026-08-03(월) ~ 2026-08-09(일) — 코틀린 DayOfWeek.value 그대로 월=1…일=7.
    private let expectedWeekdays: [(ymd: (Int, Int, Int), kotlinWeekday: Int)] = [
        ((2026, 8, 3), 1), // 월
        ((2026, 8, 4), 2), // 화
        ((2026, 8, 5), 3), // 수
        ((2026, 8, 6), 4), // 목
        ((2026, 8, 7), 5), // 금
        ((2026, 8, 8), 6), // 토
        ((2026, 8, 9), 7), // 일
    ]

    @Test("요일 변환이 월요일부터 일요일까지 코틀린 DayOfWeek.value 와 정확히 같다")
    func 요일_변환이_월요일부터_일요일까지_코틀린_규칙과_같다() {
        for case_ in expectedWeekdays {
            let value = CalendarMath.YMD(year: case_.ymd.0, month: case_.ymd.1, day: case_.ymd.2)
            #expect(
                CalendarMath.weekday(value, zone: utc) == case_.kotlinWeekday,
                "\(case_.ymd) 는 코틀린 요일 \(case_.kotlinWeekday) 이어야 한다"
            )
        }
    }

    @Test("Foundation 원시 weekday(일=1…토=7) 변환 공식 자체도 7일 전부에서 맞다")
    func foundation_원시_weekday_변환도_7일_전부에서_맞다() {
        // Foundation: 일=1, 월=2, 화=3, 수=4, 목=5, 금=6, 토=7.
        let foundationToKotlin: [(foundation: Int, kotlin: Int)] = [
            (1, 7), // 일
            (2, 1), // 월
            (3, 2), // 화
            (4, 3), // 수
            (5, 4), // 목
            (6, 5), // 금
            (7, 6), // 토
        ]
        for pair in foundationToKotlin {
            #expect(CalendarMath.kotlinWeekday(foundationWeekday: pair.foundation) == pair.kotlin)
        }
    }

    @Test("시간대가 달라도 같은 날짜(YMD)면 같은 요일이다")
    func 시간대가_달라도_같은_날짜면_같은_요일이다() {
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        let value = CalendarMath.YMD(year: 2026, month: 8, day: 5) // 수요일
        #expect(CalendarMath.weekday(value, zone: utc) == 3)
        #expect(CalendarMath.weekday(value, zone: seoul) == 3)
    }
}
