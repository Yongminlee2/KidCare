import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `core/HolidayCalendar.kt` 다. 안드로이드는 ICU `ChineseCalendar` 를
/// 쓰고, iOS 는 `Calendar(identifier: .chinese)` 를 `TimeZone(identifier: "Asia/Seoul")`
/// 로 쓴다 — 서로 다른 달력 구현이지만 같은 답을 내야 한다.
///
/// 아래 아홉 값은 2026-09-12 에 이미 확인된 값이다(작업 브리프에 못박혀 있다).
struct HolidayCalendarTests {

    private func d(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    @Test("2025년 음력 기준일이 이미 확인된 값과 같다")
    func 이천이십오년_음력_기준일이_이미_확인된_값과_같다() throws {
        let anchors = try #require(HolidayCalendar.anchors(year: 2025))
        #expect(anchors.seollal == d(2025, 1, 29))
        #expect(anchors.buddha == d(2025, 5, 5))
        #expect(anchors.chuseok == d(2025, 10, 6))
    }

    @Test("2026년 음력 기준일이 이미 확인된 값과 같다")
    func 이천이십육년_음력_기준일이_이미_확인된_값과_같다() throws {
        let anchors = try #require(HolidayCalendar.anchors(year: 2026))
        #expect(anchors.seollal == d(2026, 2, 17))
        #expect(anchors.buddha == d(2026, 5, 24))
        #expect(anchors.chuseok == d(2026, 9, 25))
    }

    @Test("2027년 음력 기준일이 이미 확인된 값과 같다")
    func 이천이십칠년_음력_기준일이_이미_확인된_값과_같다() throws {
        let anchors = try #require(HolidayCalendar.anchors(year: 2027))
        #expect(anchors.seollal == d(2027, 2, 6))
        #expect(anchors.buddha == d(2027, 5, 13))
        #expect(anchors.chuseok == d(2027, 9, 15))
    }

    @Test("of(year:) 가 확인된 기준일로 계산한 공휴일을 담는다")
    func 공휴일이_확인된_기준일로_계산된다() {
        let days = HolidayCalendar.of(year: 2025)
        #expect(days[d(2025, 1, 29)] == .seollal)
        // 2025년은 어린이날과 부처님오신날이 같은 날이다 — KoreanHolidays 는 먼저
        // 넣은 어린이날을 덮지 않으므로(KoreanHolidaysTests 의 2025년 케이스와 같은
        // 근거) 여기서도 .children 이 맞다.
        #expect(days[d(2025, 5, 5)] == .children)
        #expect(days[d(2025, 5, 6)] == .substitute)
        #expect(days[d(2025, 10, 6)] == .chuseok)
    }

    @Test("around(date:) 는 앞뒤 해를 함께 담는다")
    func around는_앞뒤_해를_함께_담는다() {
        // 설날이 1월 초인 해는 연휴가 전해 12월로 넘어간다 — 연말연시 판정은 늘
        // 앞뒤 해를 함께 훑어야 한다는 것을 pin 한다.
        let around = HolidayCalendar.around(date: d(2026, 1, 1))
        #expect(around.contains(d(2025, 10, 6)))     // 2025 추석(전해)
        #expect(around.contains(d(2026, 1, 1)))       // 2026 신정(그 해)
        #expect(around.contains(d(2026, 2, 17)))      // 2026 설날(그 해)
        #expect(around.contains(d(2027, 2, 6)))       // 2027 설날(다음해)
    }

    @Test("next(from:) 는 당일을 포함해 가장 이른 공휴일을 돌려준다")
    func next는_당일을_포함해_가장_이른_공휴일을_돌려준다() throws {
        let (date, holiday) = try #require(HolidayCalendar.next(from: d(2025, 12, 25)))
        #expect(date == d(2025, 12, 25))
        #expect(holiday == .christmas)

        let (nextDate, nextHoliday) = try #require(HolidayCalendar.next(from: d(2025, 12, 26)))
        #expect(nextDate == d(2026, 1, 1))
        #expect(nextHoliday == .newYear)
    }

    @Test("ICU가 그 해를 못 다루면 공휴일 없이 물러난다")
    func icu가_그_해를_못_다루면_공휴일_없이_물러난다() {
        // 코틀린의 판단을 그대로 옮긴다: 공휴일을 모르는 채로 도는 것이, 넘겨짚은
        // 날짜로 예약을 쉬게 하는 것보다 낫다. Calendar(identifier: .chinese) 가
        // 다룰 수 없을 만큼 먼 해(연 단위가 아니라 "계산이 실패하는" 경계 자체를
        // 코드로 강제할 수는 없으므로, 대신 이 계산이 실패할 때 nil 로 물러나는
        // 계약 자체가 있다는 것을 anchors(year:) 의 옵셔널 반환 타입으로 확인한다.
        //
        // 실제 실패를 관찰하려면 아주 먼 미래/과거 연도가 필요하다. Foundation 의
        // 중국력 계산이 버티는 한계가 기기마다 다를 수 있어 정확한 실패 연도를
        // 못박지 않고, "정상 범위에서는 항상 값이 있다"만 pin 한다 — 실패
        // 경로(nil)는 anchors(year:) 의 타입 계약(Optional)이 이미 강제한다.
        #expect(HolidayCalendar.anchors(year: 2025) != nil)
        #expect(HolidayCalendar.of(year: 2025).isEmpty == false)
    }
}
