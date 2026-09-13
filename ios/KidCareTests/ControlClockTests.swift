import Foundation
import Testing
@testable import KidCare

/// 관리 탭 화면의 순수 도우미. 알람 시각은 하루 안의 분(0~1439)으로만 오간다 —
/// 절대 시각을 만들지 않는다(ControlFragment.kt:160-164).
struct ControlClockTests {

    private var 달력: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    @Test("하루 안의 분 → 시각 → 분 이 그대로 돌아온다")
    func 분_왕복() {
        for minute in [0, 7 * 60, 7 * 60 + 30, 23 * 60 + 59] {
            let date = ControlInput.date(minuteOfDay: minute, calendar: 달력)
            #expect(ControlInput.minuteOfDay(date, calendar: 달력) == minute)
        }
    }

    @Test("입력 길이는 안드로이드 maxLength 에서 멈춘다 — 메시지 100, 알람 이름 20")
    func 길이_제한() {
        #expect(ControlInput.clamp(String(repeating: "가", count: 101), max: ControlViewModel.messageMaxLength).count == 100)
        #expect(ControlInput.clamp(String(repeating: "a", count: 21), max: ControlViewModel.alarmLabelMaxLength).count == 20)
        #expect(ControlInput.clamp("학원", max: 20) == "학원")
    }
}
