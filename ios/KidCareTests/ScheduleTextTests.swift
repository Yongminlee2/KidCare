import Testing
@testable import KidCare

/// 정본은 안드로이드 `ScheduleText`(ScheduleAdapter.kt:146-250)와 `bindRibbon`(:89-126).
struct ScheduleTextTests {

    @Test("자주 쓰는 요일 조합은 이름으로, 나머지는 '·'로 잇는다 — 범위 밖 값은 버린다(:174-184)")
    func 요일() {
        #expect(ScheduleText.daysText([1, 2, 3, 4, 5]) == "평일")
        #expect(ScheduleText.daysText([7, 6]) == "주말")
        #expect(ScheduleText.daysText(Array(1...7)) == "매일")
        #expect(ScheduleText.daysText([]) == "요일 없음")
        #expect(ScheduleText.daysText([5, 1, 3, 9]) == "월·수·금")
    }

    @Test("시간대는 세 가지로 다르게 읽힌다 — 같은 날, 자정 넘김, 하루 종일(:189-213)")
    func 시간대() {
        #expect(ScheduleText.rangeText(start: 540, end: 900) == "09:00 ~ 15:00")
        #expect(ScheduleText.rangeText(start: 1260, end: 420) == "21:00 ~ 다음 날 07:00")
        #expect(ScheduleText.rangeText(start: 0, end: 0) == "하루 종일 (00:00부터 24시간)")
    }

    @Test("줄의 둘째 줄은 꺼둔 규칙에만 '(꺼둠)'이 붙고, 요약은 요일·시간대·모드다(:48-55, :243-249)")
    func 줄과_요약() {
        let 규칙 = ScheduleDoc(id: "a", days: [1, 2, 3, 4, 5], startMinute: 1260, endMinute: 420, mode: RingerMode.vibrate, enabled: false, priority: 1)
        #expect(ScheduleText.rowDetail(규칙) == "21:00 ~ 다음 날 07:00 (꺼둠)")
        #expect(ScheduleText.summary(규칙) == "평일 · 21:00 ~ 다음 날 07:00 · 진동")
        #expect(ScheduleText.modeText("loud") == "loud")
        #expect(ScheduleText.holidayName(.foundation) == "개천절")
    }

    @Test("하루 띠: 낮 규칙은 가운데, 밤 규칙은 양 끝, 하루 종일은 통째로 찬다(:97-126)")
    func 하루_띠() {
        typealias P = DayRibbon.Piece
        #expect(DayRibbon.pieces(start: 540, end: 900) == [P(weight: 540, filled: false), P(weight: 360, filled: true), P(weight: 540, filled: false)])
        #expect(DayRibbon.pieces(start: 1260, end: 420) == [P(weight: 420, filled: true), P(weight: 840, filled: false), P(weight: 180, filled: true)])
        #expect(DayRibbon.pieces(start: 0, end: 0) == [P(weight: 0, filled: false), P(weight: 1, filled: true), P(weight: 0, filled: false)])
        #expect(DayRibbon.pieces(start: -5, end: 2000) == [P(weight: 0, filled: false), P(weight: 1440, filled: true), P(weight: 0, filled: false)])
    }
}
