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

    @Test("서버 시각의 음수 경과는 왕복 오차일 뿐이라 방금 전으로 본다")
    func 서버_시각의_음수_경과는_방금_전() {
        // serverNow 왕복 보정 오차(수백 밀리초)로 서버 시각이 "지금"보다 살짝 미래로
        // 보일 수 있다 — 이때는 실제로 방금 온 신호이므로 minutes(0)이 정직하다.
        // Fix round 1 리뷰 전에는 이 경우와 아래 기기 시각의 음수 경과를 구분하지
        // 않고 둘 다 minutes(0)으로 뭉갰는데, 그 뭉갬 자체는 이 갈래에서는 우연히
        // 맞는 답이었다 — 잘못된 답은 기기 시각 갈래(아래 테스트)에서 나왔다.
        let serverAtMillis: Int64 = 1_757_000_600_000
        let doc = status(
            lastSeenAt: 0,
            lastSeenServerAt: Timestamp(date: Date(timeIntervalSince1970: Double(serverAtMillis) / 1000))
        )
        #expect(StatusCard.lastSignal(status: doc, nowMillis: serverAtMillis - 300) == .minutes(0))
    }

    @Test("기기 시각의 음수 경과는 절대 시각을 그대로 넘긴다 — 방금 전이라고 하면 안 된다")
    func 기기_시각의_음수_경과는_skewed() {
        // 자녀 폰 시계가 30분 빠른 옛 기기가 lastSeenServerAt 없이 lastSeenAt 만
        // 남긴 경우를 흉내낸다. nowMillis - atMillis 가 음수라고 minutes(0)으로
        // 뭉개면, 실제로는 두 시간 전에 남긴 신호를 "방금 전"이라 보여줘 부모가
        // 낡은 위치를 현재로 믿게 된다(리뷰가 지적한 실제 실패 시나리오) — 그래서
        // 경과를 버리고 자녀 폰이 적어 보낸 절대 시각 그 자체를 돌려줘야 한다.
        let atMillis: Int64 = 1_757_000_600_000 // 자녀 폰 시계 기준 "지금 + 30분"
        let doc = status(lastSeenAt: atMillis, lastSeenServerAt: nil)
        let now = atMillis - 30 * 60_000 // 부모 폰이 보는 서버 시각(자녀 폰보다 30분 느림)
        #expect(StatusCard.lastSignal(status: doc, nowMillis: now) == .skewed(atMillis: atMillis))
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

    @Test("경과를 분·시간·일로 나누는 경계는 안드로이드 LastSignalText.elapsedText 와 같다")
    func 경과_경계() {
        #expect(StatusCard.elapsed(millis: 59_999) == .minutes(0))
        #expect(StatusCard.elapsed(millis: 60_000) == .minutes(1))
        #expect(StatusCard.elapsed(millis: 3_599_999) == .minutes(59))
        #expect(StatusCard.elapsed(millis: 3_600_000) == .hours(1))
        #expect(StatusCard.elapsed(millis: 86_399_999) == .hours(23))
        #expect(StatusCard.elapsed(millis: 86_400_000) == .days(1))
        // 음수의 뜻은 부르는 쪽이 정한다(:550) — 여기서는 0 으로 끌어올리기만 한다.
        #expect(StatusCard.elapsed(millis: -5_000) == .minutes(0))
    }

    @Test("signal 은 서버 시각을 먼저, 없으면 아이 폰 시각을, 둘 다 없으면 nil 을 준다")
    func 신호_출처() {
        let serverAt: Int64 = 1_757_000_000_000
        let 서버 = StatusCard.signal(status: status(
            lastSeenAt: serverAt - 3_600_000,
            lastSeenServerAt: Timestamp(date: Date(timeIntervalSince1970: Double(serverAt) / 1000))
        ))
        #expect(서버?.atMillis == serverAt)
        #expect(서버?.fromServerClock == true)
        let 기기 = StatusCard.signal(status: status(lastSeenAt: 42))
        #expect(기기?.atMillis == 42)
        #expect(기기?.fromServerClock == false)
        #expect(StatusCard.signal(status: status(lastSeenAt: 0)) == nil)
    }
}
