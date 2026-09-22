import Foundation

/// 좌표와 **무관하게** 도는 시계. `TrackingCoordinator` 가 이것 하나로 "좌표가 안 오는 동안"을
/// 알아챈다(설계서 §5.1 의 대가를 갚는 자리).
///
/// 테스트는 가짜를 넣어 `onTick` 을 직접 부른다 — 벽시계를 기다리는 테스트를 하나도 만들지 않는다.
@MainActor
protocol Ticking: AnyObject {
    /// 한 주기가 지났다. 인자는 **지금 시각**(epoch millis)이다.
    var onTick: ((Int64) -> Void)? { get set }
    func start()
    func stop()
}

/// 60초마다 한 번 깨어나는 진짜 시계.
///
/// ## 왜 이것이 필요한가 (아이폰에만 있는 구멍이다)
///
/// 안드로이드에는 좌표와 **무관하게** 오는 입력이 하나 더 있다 — 활동 인식의 STILL 전환이다.
/// 그 전환이 `onActivityMovingChanged(false)`(`TrackingService.kt:473-477`)로 들어와 판정기를
/// 되돌리고 거리 필터를 푼다. 아이폰은 v1 에서 CoreMotion 을 안 쓰기로 했으므로(설계서 §17-5)
/// 그 문이 없고, `CLLocationManager.distanceFilter` 는 **시간 보장이 없다** — 이동 확정(3m 필터)
/// 중에 아이가 완전히 멈추면 콜백이 끊기고, 콜백이 없으면 `handle()` 이 안 돌아 정지 확인 60초가
/// 영영 안 지난다. 자기를 가두는 고리다(`known-issues.md` 11번이 아이폰에서 다시 열린 것).
///
/// ## 주기가 왜 60초인가
///
/// 안드로이드의 `STOP_CONFIRM_MILLIS`(`AdaptiveMovementDetector.kt:177`, 60초)와 같은 값이다.
/// 이 시계가 하는 일이 정확히 "정지 확인이 좌표 없이도 끝나게 하는 것"이라 확인 창보다 촘촘할
/// 이유가 없고(더 자주 깨워 봐야 60초가 안 지났으면 아무것도 안 한다), 더 성글면 그만큼 늦는다.
/// 같은 값이 `TrackingService.CONDITION_CHECK_INTERVAL_MILLIS`(`:913`, 60초)와 정지 수집 주기
/// `STILL_INTERVAL_MILLIS`(`LocationCollector.kt:230`, 60초)이기도 하다 — 세 자리가 한 값이다.
///
/// ## 앱이 잠들면 (suspend/resume)
///
/// iOS 는 잠든 앱에 **실행 시간을 주지 않는다.** 아래 `Task.sleep` 은 그 동안 그냥 멈춰 있다 —
/// 깨어나면 밀린 주기를 **몰아서 때리지 않고 한 번만** 이어서 돈다(`while` 한 바퀴가 곧 한 번의
/// 깨어남이다). 그리고 이 시계가 넘기는 것은 "몇 번째 주기"가 아니라 **지금 시각**이라,
/// `TrackingCoordinator` 의 판정은 전부 절대 시각 차이로 이뤄진다 — 세 시간을 자고 깨면 그
/// 한 번의 tick 이 "세 시간 동안 좌표가 없었다"를 그대로 본다. 건너뛴 주기가 없어지는 것이 아니라
/// **한 번에 정산된다.**
@MainActor
final class TrackingTicker: Ticking {

    /// `AdaptiveMovementDetector.stopConfirmMillis` 와 **같은 값이어야 한다**(위 주석).
    /// 상수를 따로 적지 않고 그 값을 그대로 쓴다 — 코틀린에서 60초가 바뀌면 여기도 함께 바뀐다.
    static var periodMillis: Int64 { AdaptiveMovementDetector.stopConfirmMillis }

    var onTick: ((Int64) -> Void)?

    private var loop: Task<Void, Never>?
    private let now: @MainActor () -> Int64

    init(now: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.now = now
    }

    func start() {
        guard loop == nil else { return }
        // `Swift.` 를 붙이는 이유: 이 모듈에 `SegmentSummarizer.Duration`(구간 길이 표시)이 있다.
        let period = Swift.Duration.milliseconds(Self.periodMillis)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // 앱이 잠들어 있는 동안은 이 줄에서 멈춘다. 깨어나면 한 번만 이어 돈다.
                do { try await Task.sleep(for: period, tolerance: .seconds(5)) } catch { return }
                guard let self else { return }
                self.onTick?(self.now())
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}
