import Foundation

/// "14:10~15:40" 같은 시각 범위. 날짜는 화면의 날짜 헤더가 담당하므로 시분만 갖는다.
struct TimeRange: Equatable {
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
}

/// 구간의 길이. 케이스마다 다른 문장이 필요해서(1분 미만 / 분만 / 시간만 / 시간+분)
/// 문장이 아니라 케이스로 나눠 돌려준다 — 문장을 고르는 일은 화면이 한다.
enum Duration: Equatable {
    case underOneMinute
    case minutes(Int)
    case hours(Int)
    case hoursMinutes(Int, Int)
}

/// 이동 거리.
///
/// 1km 이상은 킬로미터로 소수 첫째 자리까지, 미만은 미터로 **십 단위 내림**한다.
/// 미터를 1 단위까지 보여주면 GPS 오차(최대 100m 까지 받아들인다)보다 정밀해 보여
/// 없는 정확도를 있는 척하게 된다.
enum Distance: Equatable {
    case underTenMeters
    case meters(Int)
    case kilometers(Double)
}

/// 구간을 화면에 쓸 조각으로 바꾼다.
///
/// 문장 전체를 여기서 조립하지 않는다. 장소 이름과 합친 최종 문구는 문구 카탈로그의
/// 서식 문자열이 담당해야 문구를 한 곳에서 고칠 수 있다. 여기서 만드는 것은 거기에
/// 꽂아 넣을 시각·기간·거리 값뿐이다.
///
/// **코틀린 원본과 반환 타입이 다른 이유:** 코틀린 `SegmentSummarizer`는 "14:10~15:40",
/// "1시간 50분", "480m" 같은 한국어 문장을 코드 안에서 직접 만들어 돌려준다. 그대로
/// 옮기면 `Logic/`에 한국어 리터럴이 박혀 "문구는 오직 문구 카탈로그에만" 규칙을
/// 어기고, 6단계에서 `i18n/*.json`으로 문구 카탈로그를 다시 만들 때 그 문자열만
/// 조용히 빠져 영어 기기 사용자에게 한국어가 보이는 사고로 이어진다(안드로이드가 실제로
/// 이 문제를 안고 있다 — README 개발일지 참고, 이번 작업에서는 고치지 않는다). 그래서
/// 여기서는 시각·기간·거리 "값"만 돌려주고, 문장으로 바꾸는 일은 화면(뷰 레이어)이
/// 문구 카탈로그의 서식 문자열로 한다.
///
/// 정본은 안드로이드 `logic/SegmentSummarizer.kt` 다.
enum SegmentSummarizer {

    /// 시각 범위의 시·분만 담는다. 날짜는 화면의 날짜 헤더가 담당한다.
    static func timeRange(_ segment: Segment, zone: TimeZone) -> TimeRange {
        // 로케일 고정 그레고리력은 `CalendarMath` 가 맡는다(`DayPicker`·`ScheduleResolver`
        // 와 같은 이유·같은 구현을 공유한다).
        let calendar = CalendarMath.calendar(zone: zone)

        let start = calendar.dateComponents(
            [.hour, .minute],
            from: Date(timeIntervalSince1970: Double(segment.startAt) / 1000)
        )
        let end = calendar.dateComponents(
            [.hour, .minute],
            from: Date(timeIntervalSince1970: Double(segment.endAt) / 1000)
        )
        return TimeRange(startHour: start.hour!, startMinute: start.minute!, endHour: end.hour!, endMinute: end.minute!)
    }

    static func duration(millis: Int64) -> Duration {
        let totalMinutes = millis / 60_000
        if totalMinutes < 1 { return .underOneMinute }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return .minutes(Int(minutes)) }
        if minutes == 0 { return .hours(Int(hours)) }
        return .hoursMinutes(Int(hours), Int(minutes))
    }

    /// 1km 이상은 소수 첫째 자리까지 반올림한 킬로미터, 미만은 십 단위로 내림한 미터.
    /// 미터를 1 단위까지 보여주면 GPS 오차보다 정밀해 보여 없는 정확도를 있는 척하게 된다.
    static func distance(meters: Double) -> Distance {
        if meters >= 1000.0 {
            // 소수 첫째 자리로 반올림해 값 자체를 이미 표시할 정밀도로 담아 둔다
            // (코틀린은 String.format 시점에 반올림하지만, 여기서는 문장이 아니라
            // 값을 돌려주므로 값을 만드는 시점에 반올림한다).
            let km = ((meters / 1000.0) * 10).rounded() / 10
            return .kilometers(km)
        }
        let tens = Int(meters / 10) * 10
        if tens < 10 { return .underTenMeters }
        return .meters(tens)
    }
}
