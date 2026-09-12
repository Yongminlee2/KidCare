import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `logic/ScheduleResolverTest.kt` 다. 케이스 하나하나를 같은 뜻으로 옮긴다.
struct ScheduleResolverTests {

    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    /// 코틀린의 `LocalDateTime.of(...).atZone(seoul).toInstant().toEpochMilli()` 와 같은 값.
    /// 기기 로케일에 흔들리지 않도록 프로덕션과 같은 POSIX 그레고리력을 쓴다.
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = seoul
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = h
        comps.minute = min
        comps.second = 0
        let date = calendar.date(from: comps)!
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private func rule(
        id: String = "r", days: Set<Int> = [1, 2, 3, 4, 5],
        start: Int = 9 * 60, end: Int = 15 * 60,
        mode: String = "vibrate", enabled: Bool = true, priority: Int = 0
    ) -> ScheduleRule {
        ScheduleRule(id: id, days: days, startMinute: start, endMinute: end, mode: mode, enabled: enabled, priority: priority)
    }

    private func d(_ y: Int, _ m: Int, _ dd: Int) -> DateComponents {
        DateComponents(year: y, month: m, day: dd)
    }

    // ------------------------------------------------------------------ 공휴일

    /// 2026-03-02(월)은 삼일절 대체공휴일이다. 그 주 월요일 하나만 쉬는 날이 된다.
    private var substituteMonday: Set<DateComponents> { [d(2026, 3, 2)] }

    @Test("공휴일에는 평일 규칙이 시작하지 않는다")
    func 공휴일에는_평일_규칙이_시작하지_않는다() {
        let r = ScheduleResolver.resolveAt(
            rules: [rule()], atMillis: at(2026, 3, 2, 10, 0), zone: seoul, holidays: substituteMonday
        )
        #expect(r.mode == nil, "대체공휴일 낮인데 평일 규칙이 걸렸다")
    }

    @Test("공휴일 집합이 비면 예전처럼 요일만 본다")
    func 공휴일_집합이_비면_예전처럼_요일만_본다() {
        let r = ScheduleResolver.resolveAt(rules: [rule()], atMillis: at(2026, 3, 2, 10, 0), zone: seoul)
        #expect(r.mode == "vibrate")
    }

    @Test("공휴일 다음 날에는 다시 규칙이 돈다")
    func 공휴일_다음_날에는_다시_규칙이_돈다() {
        let r = ScheduleResolver.resolveAt(
            rules: [rule()], atMillis: at(2026, 3, 3, 10, 0), zone: seoul, holidays: substituteMonday
        )
        #expect(r.mode == "vibrate")
    }

    @Test("공휴일 전날 밤에 시작한 규칙은 그 아침까지 이어진다")
    func 공휴일_전날_밤에_시작한_규칙은_그_아침까지_이어진다() {
        // 평일 22:00~07:00 규칙이 일요일 밤에 시작할 리는 없으니 금요일 밤으로 본다.
        // 2026-02-27(금) 밤에 시작해 28일 새벽까지 가는 구간이다. 시작일 기준이라는
        // 규칙이 요일과 공휴일 양쪽에 똑같이 적용되는지 확인한다.
        let night = rule(start: 22 * 60, end: 7 * 60)
        let holidays: Set<DateComponents> = [d(2026, 2, 28)]
        let r = ScheduleResolver.resolveAt(rules: [night], atMillis: at(2026, 2, 28, 3, 0), zone: seoul, holidays: holidays)
        #expect(r.mode == "vibrate", "28일이 쉬는 날이어도 27일 밤에 시작한 구간은 이어져야 한다")
    }

    @Test("다음 경계도 공휴일을 건너뛴다")
    func 다음_경계도_공휴일을_건너뛴다() {
        // 월요일이 쉬는 날이면 다음 시작은 화요일 09:00 이어야 한다.
        let r = ScheduleResolver.resolveAt(
            rules: [rule()], atMillis: at(2026, 3, 2, 6, 0), zone: seoul, holidays: substituteMonday
        )
        #expect(r.nextBoundaryMillis == at(2026, 3, 3, 9, 0))
    }

    @Test("규칙이 없으면 강제하는 모드도 없다")
    func 규칙이_없으면_강제하는_모드도_없다() {
        let r = ScheduleResolver.resolveAt(rules: [], atMillis: at(2026, 8, 7, 10, 0), zone: seoul)
        #expect(r.mode == nil)
        #expect(r.nextBoundaryMillis == nil)
    }

    @Test("꺼진 규칙은 무시한다")
    func 꺼진_규칙은_무시한다() {
        let rules = [rule(enabled: false)]
        #expect(ScheduleResolver.resolveAt(rules: rules, atMillis: at(2026, 8, 7, 10, 0), zone: seoul).mode == nil)
    }

    @Test("평일 규칙이 금요일 낮에 적용된다")
    func 평일_규칙이_금요일_낮에_적용된다() {
        // 2026-08-07 은 금요일이다.
        let r = ScheduleResolver.resolveAt(rules: [rule()], atMillis: at(2026, 8, 7, 10, 0), zone: seoul)
        #expect(r.mode == "vibrate")
    }

    @Test("평일 규칙이 토요일에는 적용되지 않는다")
    func 평일_규칙이_토요일에는_적용되지_않는다() {
        // 2026-08-08 은 토요일이다.
        #expect(ScheduleResolver.resolveAt(rules: [rule()], atMillis: at(2026, 8, 8, 10, 0), zone: seoul).mode == nil)
    }

    @Test("시작 시각 정각에 이미 적용된다")
    func 시작_시각_정각에_이미_적용된다() {
        let r = ScheduleResolver.resolveAt(rules: [rule()], atMillis: at(2026, 8, 7, 9, 0), zone: seoul)
        #expect(r.mode == "vibrate")
    }

    @Test("끝 시각 정각에는 이미 풀린다")
    func 끝_시각_정각에는_이미_풀린다() {
        // 09:00~15:00 은 15:00 을 포함하지 않는다. 안 그러면 15:00 에 시작하는
        // 다음 규칙과 한 순간 겹친다.
        #expect(ScheduleResolver.resolveAt(rules: [rule()], atMillis: at(2026, 8, 7, 15, 0), zone: seoul).mode == nil)
    }

    @Test("자정을 넘는 규칙이 밤에 적용된다")
    func 자정을_넘는_규칙이_밤에_적용된다() {
        let night = rule(id: "n", days: [1, 2, 3, 4, 5, 6, 7], start: 22 * 60, end: 7 * 60, mode: "silent")
        #expect(ScheduleResolver.resolveAt(rules: [night], atMillis: at(2026, 8, 7, 23, 30), zone: seoul).mode == "silent")
    }

    @Test("자정을 넘는 규칙이 새벽에도 적용된다")
    func 자정을_넘는_규칙이_새벽에도_적용된다() {
        let night = rule(id: "n", days: [1, 2, 3, 4, 5, 6, 7], start: 22 * 60, end: 7 * 60, mode: "silent")
        #expect(ScheduleResolver.resolveAt(rules: [night], atMillis: at(2026, 8, 8, 3, 0), zone: seoul).mode == "silent")
    }

    @Test("자정을 넘는 규칙의 요일은 시작 시각 기준이다")
    func 자정을_넘는_규칙의_요일은_시작_시각_기준이다() {
        // "평일 22:00~07:00" 은 금요일 밤에 시작하므로 토요일 새벽까지 이어진다.
        // 2026-08-07(금) 23:00 시작 -> 2026-08-08(토) 03:00 까지 적용.
        let night = rule(id: "n", days: [1, 2, 3, 4, 5], start: 22 * 60, end: 7 * 60, mode: "silent")
        #expect(ScheduleResolver.resolveAt(rules: [night], atMillis: at(2026, 8, 8, 3, 0), zone: seoul).mode == "silent")
        // 반대로 토요일 밤 23:00 은 토요일이 요일 집합에 없으므로 적용되지 않는다.
        #expect(ScheduleResolver.resolveAt(rules: [night], atMillis: at(2026, 8, 8, 23, 0), zone: seoul).mode == nil)
    }

    @Test("겹치면 우선순위가 큰 쪽이 이긴다")
    func 겹치면_우선순위가_큰_쪽이_이긴다() {
        let a = rule(id: "a", mode: "vibrate", priority: 0)
        let b = rule(id: "b", mode: "silent", priority: 5)
        #expect(ScheduleResolver.resolveAt(rules: [a, b], atMillis: at(2026, 8, 7, 10, 0), zone: seoul).mode == "silent")
    }

    @Test("우선순위가 같으면 나중에 시작한 규칙이 이긴다")
    func 우선순위가_같으면_나중에_시작한_규칙이_이긴다() {
        let early = rule(id: "e", start: 9 * 60, end: 15 * 60, mode: "vibrate")
        let late = rule(id: "l", start: 10 * 60, end: 15 * 60, mode: "silent")
        #expect(ScheduleResolver.resolveAt(rules: [early, late], atMillis: at(2026, 8, 7, 11, 0), zone: seoul).mode == "silent")
    }

    @Test("다음 경계 시각을 알려준다")
    func 다음_경계_시각을_알려준다() {
        let r = ScheduleResolver.resolveAt(rules: [rule()], atMillis: at(2026, 8, 7, 10, 0), zone: seoul)
        #expect(r.nextBoundaryMillis == at(2026, 8, 7, 15, 0))
    }

    @Test("적용 중이 아닐 때는 다음 시작 시각이 경계다")
    func 적용_중이_아닐_때는_다음_시작_시각이_경계다() {
        let r = ScheduleResolver.resolveAt(rules: [rule()], atMillis: at(2026, 8, 7, 7, 0), zone: seoul)
        #expect(r.mode == nil)
        #expect(r.nextBoundaryMillis == at(2026, 8, 7, 9, 0))
    }

    @Test("겹치는 규칙을 찾아준다")
    func 겹치는_규칙을_찾아준다() {
        let existing = rule(id: "a", start: 9 * 60, end: 15 * 60)
        let candidate = rule(id: "b", start: 14 * 60, end: 18 * 60)
        let hits = ScheduleResolver.overlaps(rules: [existing], candidate: candidate)
        #expect(hits.map { $0.id } == ["a"])
    }

    @Test("자기 자신과는 겹친다고 하지 않는다")
    func 자기_자신과는_겹친다고_하지_않는다() {
        let a = rule(id: "a")
        #expect(ScheduleResolver.overlaps(rules: [a], candidate: a).isEmpty)
    }

    @Test("요일이 안 겹치면 시간이 겹쳐도 충돌이 아니다")
    func 요일이_안_겹치면_시간이_겹쳐도_충돌이_아니다() {
        let weekday = rule(id: "a", days: [1, 2, 3, 4, 5])
        let weekend = rule(id: "b", days: [6, 7])
        #expect(ScheduleResolver.overlaps(rules: [weekday], candidate: weekend).isEmpty)
    }
}
