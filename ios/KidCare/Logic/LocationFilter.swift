import Foundation

/// [LocationFilter.decide] 의 답. `rawValue` 는 **코틀린 enum 이름 그대로**다 —
/// 골든 파일이 그 이름을 싣고 스위프트가 `Decision(rawValue:)` 로 되돌린다. Swift case 이름을
/// 기계로 변환하면(`String(describing:).uppercased()`) `uploadStaleFallback` 이
/// `UPLOADSTALEFALLBACK` 이 되어 손으로 매핑표를 들고 다녀야 한다(6단계가 `Holiday` 에서 겪었다).
/// 정본은 `LocationFilter.kt:31-61`.
enum Decision: String, Equatable {
    /// Firestore 에 올린다.
    case upload = "UPLOAD"

    /// 올리긴 하는데, 평소 기준이면 버렸을 점이다. 오차가 [LocationFilter.maxAccuracyMeters] 를
    /// 넘지만 마지막 업로드로부터 [LocationFilter.staleFallbackMillis] 가 지나 **아무것도 못 올리고
    /// 있는 상태**라 완화 기준까지 받아들였다는 뜻이다. [upload] 와 따로 두는 이유는 코틀린 주석
    /// (`LocationFilter.kt:35-52`) 그대로 로그와 테스트다 — 완화 승인이 정상 승인과 똑같이 조용하면
    /// "신호가 계속 나쁜 채로 간신히 버티는 중"과 "다 정상"을 구분할 방법이 없다.
    case uploadStaleFallback = "UPLOAD_STALE_FALLBACK"

    /// 거의 안 움직였다. 배터리·통신량을 아끼려고 건너뛴다.
    case skipTooClose = "SKIP_TOO_CLOSE"
    /// 오차가 너무 커서 못 믿는다.
    case rejectInaccurate = "REJECT_INACCURATE"
    /// 물리적으로 불가능한 이동. GPS 오류다.
    case rejectImpossible = "REJECT_IMPOSSIBLE"
}

/// 받은 위치를 올릴지 말지 판정한다. 정본은 안드로이드 `logic/LocationFilter.kt` 다.
///
/// 순서가 중요하다: 못 믿을 점(정확도·순간이동)을 먼저 버리고, 남은 것 중에서 안 움직인 것을
/// 건너뛴다. 반대 순서면 튄 좌표가 '많이 움직였다'로 통과해 버린다.
///
/// 코틀린이 `Float` 로 든 값(`accuracy`)을 여기서는 `Double` 로 넓힌다 — 설계서 §4.1. 넓히면서
/// **문턱 숫자가 미세하게 달라지지 않는지**는 골든 파일의 `constants` 가 기계로 지킨다
/// (`GoldenComparisonTests.위치필터_상수가_같다`).
enum LocationFilter {

    /// 평소 오차 문턱. 이보다 크면 버린다. `LocationFilter.kt:78` (`50f`).
    ///
    /// 100m 에서 50m 로 내렸다(2026-08-07). 90m 짜리 점도 지도에서는 확신에 찬 점 하나로 그려지는데,
    /// 그 점이 장소 이름까지 만들어내면 "옆 건물 이름"이 그대로 부모 화면에 박힌다.
    static let maxAccuracyMeters: Double = 50

    /// 오래 아무것도 못 올렸을 때만 쓰는 완화 문턱(= 옛 [maxAccuracyMeters] 값). `:88` (`100f`).
    /// 굶는 것보다 거친 점을 택한다 — 부모가 묻는 것은 "지금 어디 있냐"이고 침묵은 답이 안 된다.
    static let fallbackMaxAccuracyMeters: Double = 100

    /// 마지막 업로드로부터 이만큼 지나면 완화 문턱을 연다. `:97` (15분).
    /// [heartbeatMillis](10분)보다 **길어야 한다** — 같거나 짧으면 정상 동작 중에도 완화가 상시로 열린다.
    static let staleFallbackMillis: Int64 = 15 * 60 * 1000

    /// 이만큼 안 움직였으면 안 올린다. `:107` (25.0, 코틀린도 `Double`).
    static let minMoveMeters: Double = 25.0

    /// 시속 200km. 이보다 빠르면 GPS 오류로 본다. `:110` (55.6, 코틀린도 `Double`).
    static let maxSpeedMps: Double = 55.6

    /// 안 움직여도 이 시간이 지나면 살아있다는 뜻으로 한 번 올린다. `:113` (10분).
    static let heartbeatMillis: Int64 = 10 * 60 * 1000

    /// `:115`. 코틀린에서는 private 이지만 여기서는 `RoutePathRefiner` 가 같은 값을 쓰므로 내부 공개다 —
    /// 사본을 두면 한쪽만 바뀌는 날이 온다(1단계 판정 기록 4).
    static let earthRadiusMeters: Double = 6_371_000.0

    /// `:117-143`.
    static func decide(previous: Fix?, candidate: Fix) -> Decision {
        // 올린 게 하나도 없다 = 부모 화면이 통째로 비어 있다. "오래 못 올렸다"의 가장 극단이므로
        // 완화 문턱을 그대로 적용한다(`:118-122`).
        guard let previous else { return acceptByAccuracy(candidate, stale: true) }

        let elapsed = candidate.at - previous.at
        if elapsed <= 0 { return .rejectImpossible }

        let stale = elapsed >= staleFallbackMillis
        let accuracyVerdict = acceptByAccuracy(candidate, stale: stale)
        if accuracyVerdict == .rejectInaccurate { return accuracyVerdict }

        let distance = distanceMeters(previous, candidate)
        if distance / (Double(elapsed) / 1000.0) > maxSpeedMps { return .rejectImpossible }

        // 완화로 통과한 점은 여기서 확정한다 — 순간이동 검사를 **지난 뒤**여야 한다(`:134-138`).
        // 거리·하트비트 검사를 건너뛰는 것은 판단이 아니라 산술이다: stale 이면 이미 15분이 지났고
        // 그러면 하트비트(10분)도 반드시 지났다.
        if accuracyVerdict == .uploadStaleFallback { return accuracyVerdict }

        if distance >= minMoveMeters { return .upload }
        if elapsed >= heartbeatMillis { return .upload }
        return .skipTooClose
    }

    /// 오차만 보고 내리는 1차 판정. 문턱은 `stale` 여부로 갈린다. `:146-150`.
    /// NaN 은 두 비교가 모두 거짓이라 자동으로 거절된다 — 코틀린도 같다.
    private static func acceptByAccuracy(_ candidate: Fix, stale: Bool) -> Decision {
        if candidate.accuracy <= maxAccuracyMeters { return .upload }
        if stale, candidate.accuracy <= fallbackMaxAccuracyMeters { return .uploadStaleFallback }
        return .rejectInaccurate
    }

    /// 하버사인 거리(m). `:153-159`.
    ///
    /// 라디안 변환은 `x * .pi / 180` 이고 자바 `Math.toRadians` 는 `x / 180.0 * PI` 라 마지막 비트가
    /// 다를 수 있다. 그대로 두는 이유는 판정 기록 5 — 두 식의 차이는 적도에서 0.1mm 아래이고,
    /// 골든 대조는 1e-9 허용치를 쓰며, 생성기는 문턱에 정확히 앉는 거리를 만들지 않는다.
    static func distanceMeters(_ a: Fix, _ b: Fix) -> Double {
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let h = pow(sin(dLat / 2), 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * pow(sin(dLng / 2), 2)
        return 2 * earthRadiusMeters * asin(sqrt(h))
    }
}
