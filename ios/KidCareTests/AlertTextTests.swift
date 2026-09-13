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

    @Test("오늘이면 시각만, 아니면 날짜까지 — 한국어는 안드로이드 패턴과 글자까지 같다(:95-98, :151-160)")
    func 시각() {
        #expect(AlertText.timeText(atMillis: 오후_세시, nowMillis: 오후_세시 + 60_000, zone: seoul, locale: ko) == "오후 3시 12분")
        // 자정을 막 넘긴 새벽에 어제 저녁 사건을 본다(2026-09-12 23:05 KST, 지금 09-13 00:30)
        #expect(AlertText.timeText(atMillis: 1_789_221_900_000, nowMillis: 1_789_227_000_000, zone: seoul, locale: ko) == "9월 12일 오후 11시 5분")
    }

    @Test("한 줄은 alert_row 로 제목과 시각을 잇는다(:100-102)")
    func 한_줄() {
        let doc = 사건(EventType.placeEnter, place: "학교", at: 오후_세시)
        #expect(AlertText.line(doc, nowMillis: 오후_세시, zone: seoul, locale: ko) == "학교에 도착했어요 · 오후 3시 12분")
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
