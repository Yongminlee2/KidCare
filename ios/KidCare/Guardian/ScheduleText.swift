import Foundation

/// 규칙을 사람이 읽는 문장으로. 정본은 안드로이드 `ScheduleText`(ScheduleAdapter.kt:146-250).
///
/// 목록 줄, 확인 대화상자, 편집 판의 범위 안내가 **같은 말**로 규칙을 가리켜야 해서(:20-23) 조립은
/// 여기 한 곳이다.
enum ScheduleText {

    /// 1=월 … 7=일(:158-168).
    static func dayName(_ day: Int) -> String {
        switch day {
        case 1: return String(localized: "schedule_day_mon")
        case 2: return String(localized: "schedule_day_tue")
        case 3: return String(localized: "schedule_day_wed")
        case 4: return String(localized: "schedule_day_thu")
        case 5: return String(localized: "schedule_day_fri")
        case 6: return String(localized: "schedule_day_sat")
        case 7: return String(localized: "schedule_day_sun")
        default: return ""
        }
    }

    /// "평일" / "주말" / "매일" / "월·수·금"(:174-184).
    static func daysText(_ days: [Int]) -> String {
        let set = Set(days.filter { (1...7).contains($0) })
        if set.isEmpty { return String(localized: "schedule_days_none") }
        if set == Set(1...7) { return String(localized: "schedule_days_everyday") }
        if set == Set(1...5) { return String(localized: "schedule_days_weekday") }
        if set == [6, 7] { return String(localized: "schedule_days_weekend") }
        return set.sorted().map(dayName).joined(separator: "·")
    }

    static func timeText(_ minuteOfDay: Int) -> String {
        String(format: String(localized: "schedule_time_format"), minuteOfDay / 60, minuteOfDay % 60)
    }

    /// 같은 날·자정 넘김·하루 종일이 서로 다르게 읽혀야 한다(:189-213). "22:00 ~ 07:00" 이라고만 쓰면
    /// 끝이 시작보다 앞이라 잘못 넣은 값처럼 보인다.
    static func rangeText(start: Int, end: Int) -> String {
        if start == end {
            return String(format: String(localized: "schedule_range_allday"), timeText(start))
        }
        if end < start {
            return String(format: String(localized: "schedule_range_overnight"), timeText(start), timeText(end))
        }
        return String(format: String(localized: "schedule_range"), timeText(start), timeText(end))
    }

    /// 모르는 값이면 셋 중 하나로 넘겨짚지 않고 저장된 값을 그대로 보인다(:237-241).
    static func modeText(_ mode: String) -> String {
        switch mode {
        case RingerMode.normal: return String(localized: "schedule_mode_normal")
        case RingerMode.vibrate: return String(localized: "schedule_mode_vibrate")
        case RingerMode.silent: return String(localized: "schedule_mode_silent")
        default: return mode
        }
    }

    /// 대화상자에서 규칙 하나를 가리키는 한 줄(:243-249).
    static func summary(_ doc: ScheduleDoc) -> String {
        String(format: String(localized: "schedule_summary"),
               daysText(doc.days), rangeText(start: doc.startMinute, end: doc.endMinute), modeText(doc.mode))
    }

    /// 목록 줄의 둘째 줄. 모드 이름은 스티커가 말하므로 쓰지 않는다(ScheduleAdapter.kt:46-55).
    static func rowDetail(_ doc: ScheduleDoc) -> String {
        let range = rangeText(start: doc.startMinute, end: doc.endMinute)
        return doc.enabled ? range : String(format: String(localized: "schedule_row_off"), range)
    }

    /// ScheduleFragment.kt:837-850.
    static func holidayName(_ holiday: Holiday) -> String {
        switch holiday {
        case .newYear: return String(localized: "holiday_new_year")
        case .seollal: return String(localized: "holiday_seollal")
        case .independence: return String(localized: "holiday_independence")
        case .buddha: return String(localized: "holiday_buddha")
        case .children: return String(localized: "holiday_children")
        case .memorial: return String(localized: "holiday_memorial")
        case .liberation: return String(localized: "holiday_liberation")
        case .chuseok: return String(localized: "holiday_chuseok")
        case .foundation: return String(localized: "holiday_foundation")
        case .hangul: return String(localized: "holiday_hangul")
        case .christmas: return String(localized: "holiday_christmas")
        case .substitute: return String(localized: "holiday_substitute")
        }
    }
}

/// 하루 띠의 세 조각. 정본은 `ScheduleAdapter.bindRibbon`(:89-126).
///
/// 조각이 셋인 이유는 자정 넘김이다. 낮 규칙은 가운데만 차고 밤 규칙은 **양 끝**이 찬다.
/// 시작 == 끝(하루 종일)은 가운데 하나가 통째로 찬다.
enum DayRibbon {

    struct Piece: Equatable {
        let weight: Int
        let filled: Bool
    }

    static let minutesPerDay = 24 * 60

    static func pieces(start: Int, end: Int) -> [Piece] {
        let s = min(max(start, 0), minutesPerDay)
        let e = min(max(end, 0), minutesPerDay)
        if s == e {
            return [Piece(weight: 0, filled: false), Piece(weight: 1, filled: true), Piece(weight: 0, filled: false)]
        }
        if e < s {
            return [Piece(weight: e, filled: true), Piece(weight: s - e, filled: false), Piece(weight: minutesPerDay - s, filled: true)]
        }
        return [Piece(weight: s, filled: false), Piece(weight: e - s, filled: true), Piece(weight: minutesPerDay - e, filled: false)]
    }
}
