import Testing
@testable import KidCare

/// `dayHeaderText(_:)` — `DayHeader` 를 화면 문구로 바꾸는 자리. 정본은 안드로이드
/// `DayPicker.headerText`(문장을 코드 안에서 직접 짓는다)와 같은 뜻이지만, 여기서는
/// `DayPicker.header` 가 돌려준 구조를 문구 카탈로그로 바꾼다(`DayHeader` 타입 주석).
///
/// 개발 언어(ko)가 소스 언어라 `String(localized:)` 는 항상 `Localizable.xcstrings`
/// 의 ko 값을 돌려준다 — 그래서 기대값을 한국어 리터럴로 그대로 적는다(리팩터 전
/// `DayPickerTests` 가 하던 것과 같다).
struct DayHeaderTextTests {

    @Test("오늘은 '오늘' 이다")
    func 오늘_문구() {
        #expect(dayHeaderText(.today) == "오늘")
    }

    @Test("어제는 '어제' 다")
    func 어제_문구() {
        #expect(dayHeaderText(.yesterday) == "어제")
    }

    @Test("월요일부터 일요일까지 요일 이름이 schedule_day_* 키를 쓴다")
    func 요일_이름이_스케줄_요일_키를_쓴다() {
        // 코틀린 DayOfWeek.value 와 같은 규칙(월=1…일=7) — 2단계에서 이 스케줄
        // 화면용 요일 키를 여기서도 재사용하기로 정했다(brief).
        let 기대값: [Int: String] = [
            1: "월", 2: "화", 3: "수", 4: "목", 5: "금", 6: "토", 7: "일",
        ]
        for weekday in 1...7 {
            let header = DayHeader.date(month: 8, day: 5, weekday: weekday)
            #expect(dayHeaderText(header) == "8월 5일 (\(기대값[weekday]!))")
        }
    }

    @Test("월·일이 문구에 그대로 실린다")
    func 월일이_그대로_실린다() {
        #expect(dayHeaderText(.date(month: 12, day: 31, weekday: 4)) == "12월 31일 (목)")
    }
}
