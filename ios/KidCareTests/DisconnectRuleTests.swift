import Testing
@testable import KidCare

/// 정본은 안드로이드 `logic/DisconnectRuleTest.kt` 다. 케이스 하나하나를 같은 뜻으로 옮긴다.
struct DisconnectRuleTests {

    private let threshold = DisconnectRule.thresholdMillis
    private let now: Int64 = 1_754_500_000_000

    @Test("한 번도 안 물어본 폰은 절대 고발하지 않는다")
    func 한_번도_안_물어본_폰은_절대_고발하지_않는다() {
        // 페어링만 끝내고 '지금 위치 확인'을 한 번도 안 누른 부모. 아무리 시간이
        // 흘러도 배너가 뜨면 안 된다 — 대답하지 않은 게 아니라 물어본 적이 없다.
        #expect(!DisconnectRule.isDisconnected(lastRequestAt: 0, lastAnswerAt: 0, nowMillis: now))
        #expect(!DisconnectRule.isDisconnected(lastRequestAt: 0, lastAnswerAt: 0, nowMillis: now + 10 * threshold))
    }

    @Test("물어본 뒤 문턱을 넘게 대답이 없으면 띄운다")
    func 물어본_뒤_문턱을_넘게_대답이_없으면_띄운다() {
        let asked = now - threshold
        #expect(DisconnectRule.isDisconnected(lastRequestAt: asked, lastAnswerAt: 0, nowMillis: now))
    }

    @Test("문턱 직전에는 아직 안 띄운다")
    func 문턱_직전에는_아직_안_띄운다() {
        // 한 번의 무응답(터널·Doze 창)으로 헛경보를 내면 부모가 이 문구를 안 읽게 된다.
        let asked = now - threshold + 1
        #expect(!DisconnectRule.isDisconnected(lastRequestAt: asked, lastAnswerAt: 0, nowMillis: now))
    }

    @Test("마지막 물음에 대답이 왔으면 안 띄운다")
    func 마지막_물음에_대답이_왔으면_안_띄운다() {
        let asked = now - 5 * threshold
        let answered = asked + 1000
        #expect(!DisconnectRule.isDisconnected(lastRequestAt: asked, lastAnswerAt: answered, nowMillis: now))
    }

    @Test("옛 대답만 있고 최근 물음에 답이 없으면 띄운다")
    func 옛_대답만_있고_최근_물음에_답이_없으면_띄운다() {
        // 어제는 잘 대답하던 폰이 오늘 아침부터 죽어 있는 경우다.
        let answered = now - 10 * threshold
        let asked = now - 2 * threshold
        #expect(DisconnectRule.isDisconnected(lastRequestAt: asked, lastAnswerAt: answered, nowMillis: now))
    }

    @Test("대답 시각이 물음과 같으면 대답한 것으로 본다")
    func 대답_시각이_물음과_같으면_대답한_것으로_본다() {
        // 같은 밀리초에 물음과 대답이 적히는 것은 실제로 일어날 수 있다(캐시 응답).
        // 그때 배너를 띄우면 대답을 받아 놓고 못 받았다고 말하는 셈이다.
        let asked = now - 2 * threshold
        #expect(!DisconnectRule.isDisconnected(lastRequestAt: asked, lastAnswerAt: asked, nowMillis: now))
    }

    @Test("방금 물어본 직후에는 안 띄운다")
    func 방금_물어본_직후에는_안_띄운다() {
        #expect(!DisconnectRule.isDisconnected(lastRequestAt: now, lastAnswerAt: 0, nowMillis: now))
    }
}
