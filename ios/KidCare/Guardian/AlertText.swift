import Foundation
import SwiftUI

/// 알림 줄 하나의 그림과 색. 정본은 `AlertText.color`·`icon`(AlertAdapter.kt:125-144).
struct AlertLook: Equatable {
    let systemImage: String
    let strong: Color
    let soft: Color
}

/// 사건 문서를 부모가 읽는 한 줄로 옮긴다. 정본은 `AlertAdapter.kt:91-165` 의 `AlertText`.
enum AlertText {

    /// `🏫 학교에 도착했어요 · 오후 3시 12분` (:100-102)
    static func line(_ doc: EventDoc, nowMillis: Int64, zone: TimeZone = .current, locale: Locale = 패턴_로캘) -> String {
        String(format: String(localized: "alert_row"), title(doc), timeText(atMillis: doc.at, nowMillis: nowMillis, zone: zone, locale: locale))
    }

    /// 규칙이 type 을 잠그지 않으므로 모르는 값이 올 수 있다. 줄을 버리지 않는다 — 뜻은 몰라도 "무슨 일이 언제
    /// 있었다"는 사실은 남기 때문이다(:111-114).
    static func title(_ doc: EventDoc) -> String {
        switch doc.type {
        case EventType.placeEnter: String(format: String(localized: "alert_place_enter"), placeName(doc))
        case EventType.placeExit: String(format: String(localized: "alert_place_exit"), placeName(doc))
        case EventType.lowBattery: String(localized: "alert_low_battery")
        case EventType.permissionOff: String(localized: "alert_permission_off")
        case EventType.signalLost: String(localized: "alert_signal_lost")
        case EventType.commandFailed: String(localized: "alert_command_failed")
        default: String(localized: "alert_unknown")
        }
    }

    /// 오늘이면 시각만, 아니면 날짜까지(:146-160). 자정을 막 넘긴 새벽에 어제 저녁 사건을 볼 때 시각만 보이면
    /// 방금 일어난 일로 읽힌다. 패턴은 키에 담는다(판정 기록 5, 3단계 `control_last_seen_clock_format` 선례).
    /// 달력은 그레고리력으로 고정한다(태국어 기기의 기본 달력은 불교력이다). 오전/오후 글자는 패턴을 꺼낸 언어로 찍는다.
    static func timeText(atMillis: Int64, nowMillis: Int64, zone: TimeZone = .current, locale: Locale = 패턴_로캘) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let at = Date(timeIntervalSince1970: Double(atMillis) / 1000)
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1000)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = locale
        formatter.dateFormat = calendar.isDate(at, inSameDayAs: now)
            ? String(localized: "alert_time_today_format")
            : String(localized: "alert_time_date_format")
        return formatter.string(from: at)
    }

    /// 지금 앱이 고른 언어. 패턴(`alert_time_*_format`)을 꺼낸 언어와 오전/오후 글자의 언어를 맞춘다.
    static var 패턴_로캘: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "ko")
    }

    /// 종류별 색은 뜻에 맞춘다: 도착 풀빛(좋은 일), 나섬 살구빛(움직임), 나머지 넷은 살펴볼 일(:117-133).
    /// 그림은 판정 기록 12.
    static func look(_ doc: EventDoc) -> AlertLook {
        switch doc.type {
        case EventType.placeEnter:
            AlertLook(systemImage: GuardianTab.place.systemImage, strong: KidCarePalette.grass, soft: KidCarePalette.grassSoft)
        case EventType.placeExit:
            AlertLook(systemImage: "point.topleft.down.to.point.bottomright.curvepath", strong: KidCarePalette.apricot, soft: KidCarePalette.apricotSoft)
        case EventType.lowBattery:
            AlertLook(systemImage: "battery.25", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft)
        case EventType.permissionOff:
            AlertLook(systemImage: "exclamationmark.shield", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft)
        case EventType.signalLost:
            AlertLook(systemImage: "antenna.radiowaves.left.and.right.slash", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft)
        case EventType.commandFailed:
            AlertLook(systemImage: "exclamationmark.circle", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft)
        default:
            AlertLook(systemImage: GuardianTab.alert.systemImage, strong: KidCarePalette.sky, soft: KidCarePalette.skySoft)
        }
    }

    /// 장소 이름이 비어 있는 옛 문서를 위한 물러섬. 타임라인과 문구를 맞춘다(:162-164, 코틀린 `ifBlank`).
    private static func placeName(_ doc: EventDoc) -> String {
        doc.placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "timeline_unknown_place")
            : doc.placeName
    }
}
