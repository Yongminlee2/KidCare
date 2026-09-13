import Foundation

/// 장소를 사람이 읽는 문장으로. 정본은 안드로이드 `PlaceText`(PlaceAdapter.kt:96-120)와 스티커(:58-88).
/// 목록 줄과 삭제 확인이 같은 이름으로 장소를 가리켜야 해서 조립은 여기 한 곳이다.
enum PlaceText {

    /// 반경은 문서에 실수로 있지만 화면에는 정수로만(:102-107). 반올림은 `Math.round`(판정 기록 10).
    static func radiusMeters(_ doc: PlaceDoc) -> Int {
        KotlinMath.roundToInt(doc.radiusMeters)
    }

    /// `도착·이탈 알림` / `도착 알림만` / `이탈 알림만` / `알림 꺼둠`(:109-115).
    static func notifyText(_ doc: PlaceDoc) -> String {
        switch (doc.notifyEnter, doc.notifyExit) {
        case (true, true): return String(localized: "place_notify_both")
        case (true, false): return String(localized: "place_notify_enter")
        case (false, true): return String(localized: "place_notify_exit")
        case (false, false): return String(localized: "place_notify_none")
        }
    }

    /// 목록 줄의 둘째 줄(PlaceAdapter.kt:43-47).
    static func rowDetail(_ doc: PlaceDoc) -> String {
        String(format: String(localized: "place_row_detail"), notifyText(doc), radiusMeters(doc))
    }

    /// 대화상자에서 장소 하나를 가리키는 한 줄(:117-119).
    static func summary(_ doc: PlaceDoc) -> String {
        String(format: String(localized: "place_summary"), doc.name, radiusMeters(doc))
    }

    /// 스티커 글자 — 이름의 첫 **글자**(판정 기록 11). 코틀린은 `name.trim().firstOrNull()`(:68).
    static func stickerLetter(_ doc: PlaceDoc) -> String {
        doc.name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? ""
    }

    /// 스티커 색 번호 0..<4. 색은 **문서 ID** 로 정한다 — 자리로 정하면 하나를 지울 때 아래 색이 전부
    /// 밀린다(:58-72). 자바 `hashCode` 와 `floorMod` 그대로라 안드로이드 폰과 같은 색이 나온다.
    static func stickerIndex(_ doc: PlaceDoc) -> Int {
        let key = doc.id.isEmpty ? doc.name : doc.id
        return KotlinMath.floorMod(KotlinMath.javaHashCode(key), 4)
    }
}
