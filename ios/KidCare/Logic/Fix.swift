import Foundation

/// 위치 한 점. 안드로이드 Location 에 의존하지 않는 값 객체다.
///
/// 정본은 안드로이드 `logic/LocationFilter.kt` 의 `Fix` 다. 이 타입을 담는
/// `LocationFilter`·`SegmentBuilder` 자체는 아이 폰(안드로이드) 전용이라 옮기지
/// 않는다 — 여기서는 두 로직이 주고받는 값 모양만 가져온다. 그래서 `accuracy` 는
/// 코틀린의 `Float` 대신 스위프트 쪽 표준인 `Double` 로, `speedAccuracy` 는 아예
/// 없다 — 둘 다 `LocationFilter` 의 판정 로직에서만 쓰이는데 그 로직이 여기 없다.
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
    let speed: Double = 0
}
