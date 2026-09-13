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

    @Test("종류 값은 안드로이드 EventType 문자열 그대로(:437-458)")
    func 종류() {
        #expect([EventType.placeEnter, EventType.placeExit, EventType.lowBattery, EventType.permissionOff, EventType.signalLost, EventType.commandFailed]
                == ["place_enter", "place_exit", "low_battery", "permission_off", "signal_lost", "command_failed"])
    }
}
