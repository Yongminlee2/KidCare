import Foundation

/// 위치 한 점. 안드로이드 Location 에 의존하지 않는 값 객체다.
///
/// 정본은 안드로이드 `logic/LocationFilter.kt` 의 `Fix` 다. 이 타입을 담는
/// `LocationFilter`·`SegmentBuilder` 자체는 아이 폰(안드로이드) 전용이라 옮기지
/// 않는다 — 여기서는 두 로직이 주고받는 값 모양만 가져온다. 그래서 `accuracy` 는
/// 코틀린의 `Float` 대신 스위프트 쪽 표준인 `Double` 로 넓힌다. `speedAccuracy` 는
/// 아예 없다 — `LocationFilter` 의 판정 로직에서만 쓰이는데 그 로직이 여기 없어서다.
/// `accuracy` 는 사정이 다르다: `RoutePathRefiner.swift` 가 50m 게이트(:111)·12m
/// 종점 게이트(:133)·칼만 측정 분산(:171, 제곱해서 쓴다) 세 곳에서 그대로 쓰므로
/// 여기 있어야 한다 — 다만 그 계산들도 `Float` 정밀도로 갈릴 값이 아니라서 `Double`
/// 로 넓혀도 안전하다.
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

    init(lat: Double, lng: Double, accuracy: Double, at: Int64, speed: Double = 0) {
        self.lat = lat
        self.lng = lng
        self.accuracy = accuracy
        self.at = at
        self.speed = speed
    }
}
