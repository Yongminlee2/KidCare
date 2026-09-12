import Foundation

enum SegmentType: Equatable {
    case stay
    case move
}

/// 하루의 한 토막.
///
/// 정본은 안드로이드 `logic/SegmentBuilder.kt` 의 `Segment`·`SegmentType` 이다.
/// 이 두 타입을 만들어내는 `SegmentBuilder` 자체는 아이 폰(안드로이드) 전용이라
/// 옮기지 않는다 — 여기서는 값 모양만 가져온다.
///
/// `.stay` 는 한 곳에 머문 구간이고 `lat`/`lng` 는 그 구간 점들의 평균 좌표다.
/// `.move` 는 이동한 구간이고 `lat`/`lng` 는 도착 지점, `distanceMeters` 는 실제
/// 이동 거리다.
///
/// **코틀린의 `nameLat`/`nameLng` 는 일부러 안 옮겼다.** 그 둘은 아이 폰이
/// 역지오코딩(장소 이름 뽑기)에 물어볼 좌표일 뿐이고, `.stay` 에서는 단순 평균이
/// 아니라 오차로 가중한 평균이다(`SegmentBuilder.kt:163-183`, `staySegment`) — 점이
/// 2~3개뿐인 짧은 머무름에서 나쁜 점 하나가 이름을 망치는 것을 막으려는 계산이다.
/// 그런데 보호자가 실제로 읽는 서버 문서 `SegmentDoc`
/// (`app/src/main/java/com/kidcare/family/core/model/Documents.kt:179-189`)에는
/// `nameLat`/`nameLng` 필드 자체가 없다 — 아이 폰은 그 계산의 **결과**(`placeName`)
/// 만 올린다. 보호자 앱은 원본 점을 가진 적이 없으니 이 값을 가질 수도, 다시 계산할
/// 수도 없다. 필드를 남겨두면 채울 수 있는 값이 없는 자리가 생기고, 거기 채울 수
/// 있는 값은 지어낸 것뿐이다(`Fix.speedAccuracy` 를 뺀 것과 같은 이유).
struct Segment {
    let type: SegmentType
    let startAt: Int64
    let endAt: Int64
    let lat: Double
    let lng: Double
    let distanceMeters: Double
    let pointCount: Int
}
