import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `GuardianMainActivity.renderBanner`(:441-457)와 `bannerJob`(:395-404).
/// `RequestLog` 는 진짜 `Date()` 로 적으므로, "지금"만 가짜 시계로 앞으로 민다.
@MainActor
struct DisconnectBannerTests {

    private static let 분: Int64 = 60_000

    private func 기기_지금() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    @Test("한 번도 물어본 적이 없으면 뜨지 않는다")
    func 물어본_적_없으면_안_뜬다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { Int64(Date().timeIntervalSince1970 * 1000) + 2 * 60 * 60_000 })
        banner.다시_판정한다()
        #expect(banner.문구 == nil)
    }

    @Test("물어보고 31분 동안 대답이 없으면 뜨고, 문장에 '31분 전'이 들어간다")
    func 삼십일분_무응답이면_뜬다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { Int64(Date().timeIntervalSince1970 * 1000) + 31 * 60_000 })
        banner.다시_판정한다()
        let 기대 = String(format: String(localized: "guardian_disconnect_banner"), lastSignalText(.minutes(31)))
        #expect(banner.문구 == 기대)
        // 카탈로그에 키가 없으면 String(localized:) 가 키 이름을 그대로 돌려준다.
        #expect(banner.문구?.contains("guardian_disconnect_banner") == false)
    }

    @Test("29분이면 아직 뜨지 않는다 — 문턱은 DisconnectRule.thresholdMillis(30분)")
    func 이십구분이면_안_뜬다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { Int64(Date().timeIntervalSince1970 * 1000) + 29 * 60_000 })
        banner.다시_판정한다()
        #expect(banner.문구 == nil)
    }

    @Test("대답을 적고 다시 판정하면 곧바로 사라진다")
    func 대답이_오면_사라진다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let clock = TestClock(기기_지금() + 31 * Self.분)
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { clock.value })
        banner.다시_판정한다()
        #expect(banner.문구 != nil)
        log.recordAnswer("child")
        banner.다시_판정한다()
        #expect(banner.문구 == nil)
    }

    @Test("아이가 없으면 뜨지 않는다")
    func 아이가_없으면_안_뜬다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let banner = DisconnectBanner(childUid: nil, requestLog: log, deviceNow: { Int64(Date().timeIntervalSince1970 * 1000) + 60 * 60_000 })
        banner.다시_판정한다()
        #expect(banner.문구 == nil)
    }

    @Test("아무 스냅샷이 없어도 시간이 흐르는 것만으로 다시 판정한다(안드로이드 bannerJob 주석)")
    func 시간만_흘러도_뜬다() async {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let clock = TestClock(기기_지금())
        let 두번째_판정 = TestSignal()
        let 멈춤 = TestGate()
        let 횟수 = TestCounter()
        let banner = DisconnectBanner(
            childUid: "child", requestLog: log,
            deviceNow: { clock.value },
            sleep: { millis in
                #expect(millis == DisconnectBanner.recheckMillis)
                if await 횟수.next() == 1 {
                    clock.advance(31 * 60_000)
                } else {
                    await 두번째_판정.fire()
                    await 멈춤.wait()
                }
            }
        )
        let 반복 = Task { await banner.주기적으로_판정한다() }
        await 두번째_판정.wait()
        #expect(banner.문구 != nil)
        반복.cancel()
        await 멈춤.open()
        await 반복.value
    }
}
