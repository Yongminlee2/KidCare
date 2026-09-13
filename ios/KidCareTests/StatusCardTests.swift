import Testing
@testable import KidCare
import FirebaseFirestore
import Foundation

/// 정본은 안드로이드 `GuardianMainActivity.kt` 의 `ChildStatusDoc.lastSignal()` 과
/// `LastSignalText`. 케이스 하나하나를 같은 뜻으로 옮긴다 — 특히 서버 시각 우선,
/// 없으면 기기 시각으로 물러나는 갈래.
struct StatusCardTests {

    private func status(
        lastSeenAt: Int64 = 0,
        lastSeenServerAt: Timestamp? = nil
    ) -> ChildStatusDoc {
        var data: [String: Any] = [
            "lat": 37.5, "lng": 127.0, "accuracy": 12.0,
            "at": Int64(1_757_000_000_000), "battery": 80, "charging": false,
            "ringerMode": "normal", "lastSeenAt": lastSeenAt,
        ]
        if let lastSeenServerAt { data["lastSeenServerAt"] = lastSeenServerAt }
        return ChildStatusDoc(data)!
    }

    @Test("신호가 한 번도 없으면 never 다")
    func 신호가_없으면_never() {
        let doc = status(lastSeenAt: 0)
        #expect(StatusCard.lastSignal(status: doc, nowMillis: 1_757_000_600_000) == .never)
    }

    @Test("서버 시각이 있으면 그것을 우선으로 쓴다")
    func 서버_시각을_우선한다() {
        // 서버 시각은 5분 전, 기기 시각(lastSeenAt)은 실수로 1시간 전으로 남아 있어도
        // 서버 값만 봐야 한다.
        let serverAtMillis: Int64 = 1_757_000_000_000
        let doc = status(
            lastSeenAt: serverAtMillis - 3_600_000,
            lastSeenServerAt: Timestamp(date: Date(timeIntervalSince1970: Double(serverAtMillis) / 1000))
        )
        let now = serverAtMillis + 5 * 60_000
        #expect(StatusCard.lastSignal(status: doc, nowMillis: now) == .minutes(5))
    }

    @Test("서버 시각이 없으면 아이 폰 시계로 물러난다")
    func 서버_시각이_없으면_기기_시각으로_물러난다() {
        let atMillis: Int64 = 1_757_000_000_000
        let doc = status(lastSeenAt: atMillis, lastSeenServerAt: nil)
        let now = atMillis + 90 * 60_000
        #expect(StatusCard.lastSignal(status: doc, nowMillis: now) == .hours(1))
    }

    @Test("1분 미만은 minutes(0) 이다")
    func 일분_미만은_minutes_0() {
        let atMillis: Int64 = 1_757_000_000_000
        let doc = status(lastSeenAt: atMillis)
        #expect(StatusCard.lastSignal(status: doc, nowMillis: atMillis + 30_000) == .minutes(0))
    }

    @Test("한 시간 미만은 분 단위다")
    func 한시간_미만은_분_단위() {
        let atMillis: Int64 = 1_757_000_000_000
        let doc = status(lastSeenAt: atMillis)
        #expect(StatusCard.lastSignal(status: doc, nowMillis: atMillis + 25 * 60_000) == .minutes(25))
    }

    @Test("하루 이상이면 일 단위다")
    func 하루_이상이면_일_단위() {
        let atMillis: Int64 = 1_757_000_000_000
        let doc = status(lastSeenAt: atMillis)
        #expect(StatusCard.lastSignal(status: doc, nowMillis: atMillis + 3 * 86_400_000) == .days(3))
    }

    @Test("기기 시계가 앞서 경과가 음수가 나와도 0 이상으로 잘린다")
    func 음수_경과는_0으로_잘린다() {
        // 아이 폰 시계가 부모 폰보다 앞서 있으면 nowMillis - atMillis 가 음수다.
        // LastSignal 은 절대 시각을 담을 케이스가 없으므로 안전한 값(minutes(0))으로
        // 수렴한다 — Documents.swift 의 StatusCard.lastSignal 주석 참고.
        let atMillis: Int64 = 1_757_000_600_000
        let doc = status(lastSeenAt: atMillis)
        #expect(StatusCard.lastSignal(status: doc, nowMillis: atMillis - 180_000) == .minutes(0))
    }

    @Test("서버 시각이 0 이면 있어도 없는 값으로 보고 기기 시각으로 물러난다")
    func 서버_시각이_0이면_기기_시각으로_물러난다() {
        let atMillis: Int64 = 1_757_000_000_000
        let doc = status(
            lastSeenAt: atMillis,
            lastSeenServerAt: Timestamp(date: Date(timeIntervalSince1970: 0))
        )
        #expect(StatusCard.lastSignal(status: doc, nowMillis: atMillis + 60_000) == .minutes(1))
    }
}
