import Foundation
import Testing
@testable import KidCare

/// 정본은 `AlertAdapter.kt:91-165` 의 `AlertText`.
struct AlertTextTests {

    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private let ko = Locale(identifier: "ko")
    /// 2026-09-13 15:12 KST
    private let 오후_세시 = Int64(1_789_279_920_000)

    private func 사건(_ type: String, place: String = "", at: Int64 = 0) -> EventDoc {
        EventDoc(id: "e", type: type, at: at, childUid: "c", placeName: place)
    }

    @Test("종류마다 안드로이드와 같은 제목, 모르는 종류도 줄을 버리지 않는다(:104-115)")
    func 제목() {
        #expect(AlertText.title(사건(EventType.placeEnter, place: "학교")) == "학교에 도착했어요")
        #expect(AlertText.title(사건(EventType.placeExit, place: "학원")) == "학원에서 나섰어요")
        #expect(AlertText.title(사건(EventType.lowBattery)) == "애기폰 배터리가 얼마 안 남았어요")
        #expect(AlertText.title(사건(EventType.permissionOff)) == "애기폰에서 권한이 꺼졌어요")
        #expect(AlertText.title(사건(EventType.signalLost)) == "애기폰이 한동안 대답하지 않았어요")
        #expect(AlertText.title(사건(EventType.commandFailed)) == "애기폰에 보낸 요청이 실패했어요")
        #expect(AlertText.title(사건("geofence_v2")) == "새로운 소식이 있어요")
    }

    @Test("장소 이름이 비었거나 공백뿐이면 타임라인과 같은 '머무른 곳'(:162-164, 코틀린 ifBlank)")
    func 이름_없음() {
        #expect(AlertText.title(사건(EventType.placeEnter, place: " \n")) == "머무른 곳에 도착했어요")
    }

    /// 기대값이 안드로이드 바이트와 **일부러 다르다**: 시각 조각 안의 공백은 U+00A0 이다(6단계 판정 A1).
    /// 아이폰에서 한 줄이 "오후 10시 / 1분" 처럼 어구 중간에서 접히지 않게 하려는 표시층 처리다. 그래서 공백을
    /// 되돌리면 안드로이드 패턴의 결과와 글자까지 같다는 비교를 함께 남긴다 — 패턴이나 로캘이 어긋나면 그쪽이 깨진다.
    @Test("오늘이면 시각만, 아니면 날짜까지 — 조각 안 공백은 U+00A0, 되돌리면 안드로이드와 글자까지 같다(:95-98, :151-160)")
    func 시각() {
        let 오늘 = AlertText.timeText(atMillis: 오후_세시, nowMillis: 오후_세시 + 60_000, zone: seoul, locale: ko)
        #expect(오늘 == "오후\u{00A0}3시\u{00A0}12분")
        #expect(오늘.replacingOccurrences(of: "\u{00A0}", with: " ") == "오후 3시 12분")
        // 자정을 막 넘긴 새벽에 어제 저녁 사건을 본다(2026-09-12 23:05 KST, 지금 09-13 00:30)
        let 어제 = AlertText.timeText(atMillis: 1_789_221_900_000, nowMillis: 1_789_227_000_000, zone: seoul, locale: ko)
        #expect(어제 == "9월\u{00A0}12일\u{00A0}오후\u{00A0}11시\u{00A0}5분")
        #expect(어제.replacingOccurrences(of: "\u{00A0}", with: " ") == "9월 12일 오후 11시 5분")
        #expect(!오늘.contains(" ") && !어제.contains(" "))
    }

    @Test("영어 시각 조각도 U+0020 은 남지 않고, AM/PM 앞 U+202F 는 그대로다")
    func 영어_시각() {
        let en = AlertText.timeText(atMillis: 오후_세시, nowMillis: 오후_세시 - 86_400_000 * 3, zone: seoul, locale: Locale(identifier: "en"))
        #expect(!en.contains(" "), "\(en.unicodeScalars.map { String($0.value, radix: 16) })")
    }

    @Test("한 줄은 alert_row 로 제목과 시각을 잇는다 — 구분자 ' · ' 의 공백은 그대로라 줄은 거기서 접힌다(:100-102)")
    func 한_줄() {
        let doc = 사건(EventType.placeEnter, place: "학교", at: 오후_세시)
        #expect(AlertText.line(doc, nowMillis: 오후_세시, zone: seoul, locale: ko) == "학교에 도착했어요 · 오후\u{00A0}3시\u{00A0}12분")
    }

    @Test("그림과 색: 도착 풀빛, 나섬 살구빛, 배터리·권한·신호·명령 실패 자두빛, 모르는 것 하늘빛(:125-144)")
    func 모양() {
        #expect(AlertText.look(사건(EventType.placeEnter)) == AlertLook(systemImage: GuardianTab.place.systemImage, strong: KidCarePalette.grass, soft: KidCarePalette.grassSoft))
        #expect(AlertText.look(사건(EventType.placeExit)) == AlertLook(systemImage: "point.topleft.down.to.point.bottomright.curvepath", strong: KidCarePalette.apricot, soft: KidCarePalette.apricotSoft))
        #expect(AlertText.look(사건(EventType.lowBattery)) == AlertLook(systemImage: "battery.25", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft))
        #expect(AlertText.look(사건(EventType.permissionOff)).systemImage == "exclamationmark.shield")
        #expect(AlertText.look(사건(EventType.signalLost)).systemImage == "antenna.radiowaves.left.and.right.slash")
        #expect(AlertText.look(사건(EventType.commandFailed)) == AlertLook(systemImage: "exclamationmark.circle", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft))
        #expect(AlertText.look(사건("x")) == AlertLook(systemImage: GuardianTab.alert.systemImage, strong: KidCarePalette.sky, soft: KidCarePalette.skySoft))
    }
}
