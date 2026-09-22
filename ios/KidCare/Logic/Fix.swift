import Foundation

/// 위치 한 점. 안드로이드 Location 에 의존하지 않는 값 객체다.
///
/// 정본은 안드로이드 `logic/LocationFilter.kt` 의 `Fix`(:10-29) 다. `accuracy`·`speed`·
/// `speedAccuracy` 는 코틀린의 `Float` 대신 스위프트 쪽 표준인 `Double` 로 넓힌다 —
/// 설계서 §4.1 이 "넓히는 것이 두 언어의 유일한 차이"라고 못박았고, `Float` 상수가
/// 실제로 담고 있는 값과 어긋나지 않는지는 골든 파일의 `constants` 가 기계로 지킨다.
struct Fix {
    let lat: Double
    let lng: Double
    let accuracy: Double
    let at: Int64
    /// m/s. 기기가 속도를 못 주면 0 이다.
    ///
    /// 기본값을 둔 이유: 이 필드가 없던 시절에 저장된 points 문서는 speed 가 0 으로
    /// 읽히는데, 그걸 "정지"로 오해하면 안 된다. 속도는 참고용이고 구간 판정은
    /// 좌표와 시각으로만 한다.
    ///
    /// **반드시 설정 가능해야 하는 이유**: 안드로이드 `TrailPoint`
    /// (`Documents.kt:167`) 는 실제로 speed 를 담아 보내고, `RoutePathRefiner.kt:137`
    /// 이 그 값으로 평활 필터의 과정 잡음(process noise)을 키운다 — 빠르게 이동
    /// 중일수록 필터가 더 즉각적으로 따라가게 하려는 계산이다. `let speed: Double = 0`
    /// 처럼 선언부에서 기본값을 주면 스위프트가 그 프로퍼티를 memberwise 초기화
    /// 목록에서 통째로 빼버려(`let` + 리터럴 기본값은 오버라이드 불가) 모든 `Fix` 가
    /// 영원히 speed=0 으로 굳어버린다 — 그러면 `RoutePathRefiner` 가 실제 속도를
    /// 절대 못 받아 두 플랫폼이 같은 데이터로 다른 경로선을 그리게 된다. 그래서
    /// 기본값은 이 아래 `init` 의 매개변수 기본값으로 옮겼다: 옛 문서(값 없음)는
    /// 여전히 0 을 받고, 실제 속도가 있는 문서는 그 값을 그대로 넣을 수 있다.
    let speed: Double

    /// 기기가 보고한 속도 오차(1-sigma, m/s). 정본은 코틀린 `Fix.speedAccuracy`(`LocationFilter.kt:28`).
    ///
    /// 보호자 앱만 있던 시절에는 **일부러 뺐다** — 이 값을 읽는 로직(`AdaptiveMovementDetector`,
    /// `MovementTrailFilter`)이 아이 폰에만 있었고, 채울 수 없는 자리를 남기면 거기 들어가는 값은
    /// 지어낸 것뿐이기 때문이다. 아이 역할이 그 두 로직을 가져오면서 자리가 생겼다.
    ///
    /// 기본값이 `.infinity`("모른다")인 이유는 코틀린과 같다 — 0 으로 두면 `speed - speedAccuracy`
    /// 가 곧 `speed` 라, 실내에서 정지한 폰이 2~5m/s 로 잘못 보고하는 실기기 사례가 전부
    /// "확실한 보행"으로 통과한다(`MovementTrailFilter.kt:124-132`).
    ///
    /// **`init` 의 마지막 기본값 매개변수**로 두는 것이 중요하다. `let speedAccuracy: Double = .infinity`
    /// 처럼 선언부에 기본값을 주면 Swift 가 그 프로퍼티를 memberwise 초기화 목록에서 빼버려
    /// 영원히 무한대로 굳는다 — `speed` 에서 이미 한 번 겪은 사고다(그 프로퍼티 주석).
    let speedAccuracy: Double

    init(lat: Double, lng: Double, accuracy: Double, at: Int64, speed: Double = 0, speedAccuracy: Double = .infinity) {
        self.lat = lat
        self.lng = lng
        self.accuracy = accuracy
        self.at = at
        self.speed = speed
        self.speedAccuracy = speedAccuracy
    }
}
