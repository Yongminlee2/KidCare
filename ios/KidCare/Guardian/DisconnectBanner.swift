import Foundation
import Observation
import SwiftUI

/// "애기폰이 대답하지 않아요" 배너를 띄울지 판정한다. 정본은 안드로이드
/// `GuardianMainActivity.renderBanner`(:441-457)와 `bannerJob`(:113-121).
///
/// **탭마다 두지 않고 `GuardianRootView` 한 곳에 둔다**(:53-56) — 지도만 보는 부모도 봐야
/// 하고, 두 곳에서 판정하면 한쪽만 뜨는 어긋남이 생긴다.
///
/// **서버를 한 번도 안 건드린다.** 재료는 부모 폰 안의 `RequestLog` 뿐이고(:433-435),
/// 비교 시각도 기기 시계다 — 두 값을 적은 것도 이 폰 시계라 같은 시계끼리 빼는 쪽이
/// 정확하다(:437-439). 그래서 1분마다 다시 판정해도 통신 비용이 0 이다(:480-482).
@Observable
@MainActor
final class DisconnectBanner {

    /// 안드로이드 `BANNER_RECHECK_MILLIS = 60 * 1000L`(:483).
    nonisolated static let recheckMillis: Int64 = 60 * 1000

    /// `nil` 이면 배너를 감춘다.
    private(set) var 문구: String?

    private let childUid: String?
    private let requestLog: RequestLog
    private let deviceNow: @Sendable () -> Int64
    private let sleep: @Sendable (Int64) async -> Void

    init(
        childUid: String?,
        requestLog: RequestLog = RequestLog(),
        deviceNow: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        sleep: @escaping @Sendable (Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        }
    ) {
        self.childUid = childUid
        self.requestLog = requestLog
        self.deviceNow = deviceNow
        self.sleep = sleep
    }

    /// 지금 판정한다. 대답을 적은 직후에도 부른다 — 1분 주기만 믿으면 대답이 온 뒤에도
    /// 배너가 최대 1분 남아 부모 눈에는 고장이다(`refreshBanner` 주석 :388-389).
    func 다시_판정한다() {
        let lastRequestAt = requestLog.lastRequestAt(childUid: childUid)
        let now = deviceNow()
        let 끊겼다 = DisconnectRule.isDisconnected(
            lastRequestAt: lastRequestAt,
            lastAnswerAt: requestLog.lastAnswerAt(childUid: childUid),
            nowMillis: now
        )
        guard 끊겼다 else {
            문구 = nil
            return
        }
        문구 = String(
            format: String(localized: "guardian_disconnect_banner"),
            lastSignalText(StatusCard.elapsed(millis: now - lastRequestAt))
        )
    }

    /// 화면이 보이는 동안 1분마다 다시 판정한다. 이게 없으면 **완전히 멎어 아무 스냅샷도
    /// 안 오는 폰**에서 배너가 영영 안 뜬다(:116-119). 부르는 쪽이 앱이 활성일 때만
    /// 돌리고(`onStart`/`onStop` :395-421), 취소하면 멈춘다.
    func 주기적으로_판정한다() async {
        while !Task.isCancelled {
            다시_판정한다()
            await sleep(Self.recheckMillis)
        }
    }
}

/// 배너 한 줄. 정본은 `activity_guardian_main.xml:74-83` — 오류 컨테이너 색, 가로 16·세로 14.
struct DisconnectBannerView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(KidCarePalette.onBerrySoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            // 바탕은 상태바 뒤까지 채운다 — 안드로이드가 배너가 떠 있을 때만 상태바 높이를
            // 배너 여백에 더하는 것(applyTopInset :366-377)과 같은 모양.
            .background(KidCarePalette.berrySoft, ignoresSafeAreaEdges: .top)
    }
}
