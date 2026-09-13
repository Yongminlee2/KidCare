import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `Documents.kt:348-396` 과 `ScheduleRepository.kt:73-82`·`PlaceRepository.kt:60-67`.
struct RuleDocumentsTests {

    @Test("예약 문서는 안드로이드가 실제로 쓰는 일곱 필드 그대로다 — id 는 본문에 빈 값(판정 기록 6)")
    func 예약_필드() {
        let doc = ScheduleDoc(id: "r1", days: [1, 2, 3, 4, 5], startMinute: 1260, endMinute: 420,
                              mode: RingerMode.vibrate, enabled: false, priority: 3)
        let data = doc.firestoreData
        #expect(Set(data.keys) == ["id", "days", "startMinute", "endMinute", "mode", "enabled", "priority"])
        #expect(data["id"] as? String == "")
        #expect(data["days"] as? [Int] == [1, 2, 3, 4, 5])
        #expect(data["startMinute"] as? Int == 1260)
        #expect(data["enabled"] as? Bool == false)
        #expect(data["priority"] as? Int == 3)
    }

    @Test("필드가 빠진 예약 문서는 코틀린 기본값으로 읽는다 — enabled 는 true, 본문의 id 는 무시")
    func 예약_기본값() {
        let doc = ScheduleDoc(id: "r2", [
            "id": "",
            "days": [NSNumber(value: 7), NSNumber(value: 6)],
            "startMinute": NSNumber(value: 540),
        ])
        #expect(doc == ScheduleDoc(id: "r2", days: [7, 6], startMinute: 540, endMinute: 0, mode: "", enabled: true, priority: 0))
        #expect(doc.asRule == ScheduleRule(id: "r2", days: [6, 7], startMinute: 540, endMinute: 0, mode: "", enabled: true, priority: 0))
    }

    @Test("장소 문서 일곱 필드, 빠진 알림 스위치는 켜짐, 빠진 반경은 0(안 정해짐)")
    func 장소() {
        let doc = PlaceDoc(id: "p1", name: "학교", lat: 37.5, lng: 127.0, radiusMeters: 200, notifyEnter: true, notifyExit: false)
        let data = doc.firestoreData
        #expect(Set(data.keys) == ["id", "name", "lat", "lng", "radiusMeters", "notifyEnter", "notifyExit"])
        #expect(data["id"] as? String == "")
        #expect(data["radiusMeters"] as? Double == 200)
        #expect(data["notifyExit"] as? Bool == false)

        let 옛_문서 = PlaceDoc(id: "p2", ["name": "학원", "lat": NSNumber(value: 37), "lng": NSNumber(value: 127.25)])
        #expect(옛_문서 == PlaceDoc(id: "p2", name: "학원", lat: 37, lng: 127.25, radiusMeters: 0, notifyEnter: true, notifyExit: true))
    }

    @Test("sync_rules 명령 이름은 안드로이드와 같다(Documents.kt:222)")
    func 명령_이름() {
        #expect(CommandType.syncRules == "sync_rules")
    }
}
