import Foundation
import Testing
@testable import KidCare

/// 정본은 `Documents.kt:420-458`. 아이 폰(안드로이드)이 Long 으로 쓴 at 이 NSNumber 로 온다.
struct EventDocumentsTests {

    @Test("일곱 필드를 읽고, 문서 ID 는 본문이 아니라 인자로 받는다")
    func 읽기() {
        let doc = EventDoc(id: "e1", [
            "id": "", "type": "place_enter", "at": NSNumber(value: Int64(1_789_279_920_000)),
            "childUid": "c1", "placeName": "학교", "detail": "", "read": false,
        ])
        #expect(doc == EventDoc(id: "e1", type: EventType.placeEnter, at: 1_789_279_920_000, childUid: "c1", placeName: "학교", detail: "", read: false))
    }

    @Test("빠진 필드는 코틀린 기본값(빈 문자열·0·false)으로 읽는다")
    func 기본값() {
        #expect(EventDoc(id: "e2", [:]) == EventDoc(id: "e2", type: "", at: 0))
    }

    @Test("아이가 싣는 본문은 규칙이 요구하는 모양이다 — read 는 doc 값과 무관하게 항상 false(판정 기록 14)")
    func 아이가_싣는_본문() {
        let doc = EventDoc(id: "무시된다", type: EventType.placeExit, at: 1_700_000_000_000,
                           childUid: "아이uid", placeName: "학교", detail: "", read: true)
        let data = doc.firestoreData
        #expect(data["id"] as? String == "")
        #expect(data["type"] as? String == "place_exit")
        #expect(data["at"] as? Int64 == 1_700_000_000_000, "밀리초 정수여야 한다 — Timestamp 로 쓰면 규칙이 막는다")
        #expect(data["childUid"] as? String == "아이uid")
        #expect(data["placeName"] as? String == "학교")
        #expect(data["read"] as? Bool == false, "read: true 인 doc 을 넘겨도 false 로 나가야 한다")
        #expect(Set(data.keys) == ["id", "type", "at", "childUid", "placeName", "detail", "read"])
    }

    @Test("종류 값은 안드로이드 EventType 문자열 그대로(:437-458)")
    func 종류() {
        #expect([EventType.placeEnter, EventType.placeExit, EventType.lowBattery, EventType.permissionOff, EventType.signalLost, EventType.commandFailed]
                == ["place_enter", "place_exit", "low_battery", "permission_off", "signal_lost", "command_failed"])
    }
}
