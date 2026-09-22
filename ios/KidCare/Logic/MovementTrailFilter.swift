import Foundation

/// 이동 경로 파일에 남길 점을 고른다. 정본은 안드로이드 `logic/MovementTrailFilter.kt`.
///
/// 상태 보고에 쓰는 [LocationFilter] 와 분리한 이유는 목적이 다르기 때문이다 — 상태는 25m/10분이면
/// 충분하지만 경로는 모퉁이를 남기려면 이동 중 5초 점이 필요하다.
///
/// **아이폰에서는 [minIntervalMillis] 가 밀도를 지키는 유일한 장치다.** `CLLocationManager` 에는
/// "5초마다 하나"를 요청하는 손잡이가 없어서(설계서 §5.1) 안드로이드의 요청 주기와 이 필터가 만들던
/// 이중 방어 중 이쪽만 남는다. `Child/CollectionMode` 의 소프트웨어 간격이 같은 5초를 한 번 더 건다.
enum MovementTrailFilter {

    /// `:19`.
    static let minIntervalMillis: Int64 = 5_000

    /// 경로점으로 받는 정확도 상한. `:30` (`50f`). 상태 업로드와 같은 50m 다 — 30m 로 조였더니
    /// 버스·번화가·실내 구간(오차 30~50m 가 정상)이 통째로 비었다.
    static let maxAccuracyMeters: Double = 50

    /// 정지 주기 사이에 이만큼 옮겨졌으면 **좌표 자체가 이동의 증거**다. `:42` (코틀린도 `Double`).
    static let displacementEvidenceMeters: Double = 50.0

    /// 변위를 증거로 인정할 때 오차에 곱하는 배수. `:55`. 문턱은 `max(50m, hypot × 1.5)` 다 —
    /// 오차 40m 두 점의 변위 잡음은 표준편차가 약 57m 라 가만히 있어도 50m 는 예사로 벌어진다.
    static let displacementEvidenceNoiseMultiplier: Double = 1.5

    /// 정확도가 좋은 야외에서 보행으로 볼 수 있는 최소 GNSS 속도. `:58` 의 `0.7f` 다.
    /// **`0.7` 이라고 적으면 안 된다** — 코틀린 `Float` 0.7f 는 실제로 이 값이고, 십진 0.7 을 적으면
    /// 문턱이 미세하게 높아져 경계에서 두 폰이 갈린다(1단계 판정 기록 2). 골든의 `constants` 가 지킨다.
    static let movingSpeedMps: Double = 0.699999988079071

    /// 경로점으로 인정하는 최소 변위. `:76`. **오차에 비례해 키우지 않는다** — 예전 `max(5m, hypot)`
    /// 은 걷는 아이를 통째로 지웠다(5초에 6m 를 걷는데 오차 20m 면 28m 를 요구했다). 3m 는 완전히
    /// 같은 좌표가 반복해 들어오는 것만 걸러낸다.
    static let minDisplacementMeters: Double = 3.0

    /// 이 이하 오차의 GNSS 속도만 보행 판정의 보조 근거로 신뢰한다. `:79` (`15f`).
    static let speedTrustMaxAccuracyMeters: Double = 15

    /// 속도 오차를 뺀 뒤에도 이 값 이상이어야 실제 이동 속도로 본다. `:82` 의 `0.35f` 확장값.
    static let minConfidentSpeedMps: Double = 0.3499999940395355

    /// 속도값 하나만 튀어도 같은 좌표를 계속 기록하지 않도록 요구하는 최소 변위. `:85`.
    static let minSpeedEvidenceDisplacementMeters: Double = 3.0

    /// 활동 인식이 정지라고 하는데 좌표가 크게 옮겨졌는가. `:95-109`.
    /// true 면 호출자([Child.TrackingCoordinator])가 이동 확인을 시작한다.
    static func isDisplacementEvidence(previous: Fix?, candidate: Fix) -> Bool {
        guard let previous else { return false }
        guard candidate.accuracy.isFinite, candidate.accuracy <= LocationFilter.maxAccuracyMeters else { return false }
        guard previous.accuracy.isFinite, previous.accuracy <= LocationFilter.maxAccuracyMeters else { return false }
        let elapsed = candidate.at - previous.at
        if elapsed <= 0 { return false }
        let distance = LocationFilter.distanceMeters(previous, candidate)
        if distance / (Double(elapsed) / 1_000.0) > LocationFilter.maxSpeedMps { return false }
        let threshold = max(
            displacementEvidenceMeters,
            hypot(previous.accuracy, candidate.accuracy) * displacementEvidenceNoiseMultiplier
        )
        return distance >= threshold
    }

    /// `:111-144`.
    static func shouldRecord(previous: Fix?, candidate: Fix, reportedMoving: Bool) -> Bool {
        if !reportedMoving { return false }
        if candidate.accuracy > maxAccuracyMeters { return false }
        if candidate.speed > LocationFilter.maxSpeedMps { return false }
        guard let previous else { return true }

        let elapsed = candidate.at - previous.at
        if elapsed < minIntervalMillis { return false }

        let distance = LocationFilter.distanceMeters(previous, candidate)
        let impliedSpeed = distance / (Double(elapsed) / 1_000.0)
        if impliedSpeed > LocationFilter.maxSpeedMps { return false }

        // 정확도가 좋은 야외의 GNSS speed 만 보조 근거로 쓴다. 실내에서는 정지한 폰도 2~5m/s 라고
        // 잘못 보고하는 실기기 사례가 있어 오차가 큰 speed 를 믿으면 안 된다(`:124-125`).
        let speedEvidence: Bool
        if candidate.speedAccuracy.isFinite {
            speedEvidence = candidate.speed - candidate.speedAccuracy >= minConfidentSpeedMps
        } else {
            // 예전 기기/공급자가 속도 정확도를 안 줄 때는 기존 속도 문턱을 쓰되, 아래 실제 변위
            // 조건까지 함께 만족해야 한다(`:129-131`).
            speedEvidence = candidate.speed >= movingSpeedMps
        }
        if previous.accuracy <= speedTrustMaxAccuracyMeters,
           candidate.accuracy <= speedTrustMaxAccuracyMeters,
           speedEvidence,
           distance >= minSpeedEvidenceDisplacementMeters {
            return true
        }

        // 예전에는 여기서 오차에 비례한 반경(hypot)을 요구했다. 그 판정이 걷는 아이를 통째로 지웠다
        // (`minDisplacementMeters` 주석). 이제는 같은 좌표의 반복만 걸러내고 흔들림 판단은 그리는
        // 쪽(`RoutePathRefiner`)으로 넘긴다.
        return distance >= minDisplacementMeters
    }
}
