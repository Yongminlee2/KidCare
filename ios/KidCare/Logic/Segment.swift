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
struct Segment {
    let type: SegmentType
    let startAt: Int64
    let endAt: Int64
    let lat: Double
    let lng: Double
    let distanceMeters: Double
    let pointCount: Int
    /// **이름을 물어볼 좌표.** 역지오코딩(PlaceNamer, 아이 폰 전용)에만 쓴다.
    ///
    /// `lat`/`lng` 와 따로 두는 이유: 저 둘은 지도에 찍고 선을 잇는 좌표라 의미를
    /// 바꾸면 화면·타임라인·경로선이 전부 따라 바뀐다(그 계약은 건드리지 않는다).
    /// 반면 이름은 좌표 하나를 건물 이름으로 바꾸는 일이라 오차에 훨씬 민감하다.
    /// `.move` 구간에서는 `lat`/`lng` 와 같은 값이다 — 이동 구간에는 애초에 이름을
    /// 안 붙인다.
    let nameLat: Double
    let nameLng: Double

    /// `nameLat`/`nameLng` 를 생략하면 `lat`/`lng` 를 그대로 쓴다 — `.move` 구간의
    /// 코틀린 원본 동작(`SegmentBuilder.addMove`) 그대로다. 코틀린 `Segment` 는 이
    /// 두 필드에 기본값이 없지만(항상 계산해서 채운다), 여기서는 로직(`SegmentBuilder`)
    /// 을 옮기지 않으므로 값을 만드는 쪽이 매번 계산해 넣거나, 이동 구간처럼
    /// `lat`/`lng` 와 같다면 생략할 수 있게 편의를 둔다.
    init(
        type: SegmentType,
        startAt: Int64,
        endAt: Int64,
        lat: Double,
        lng: Double,
        distanceMeters: Double,
        pointCount: Int,
        nameLat: Double? = nil,
        nameLng: Double? = nil
    ) {
        self.type = type
        self.startAt = startAt
        self.endAt = endAt
        self.lat = lat
        self.lng = lng
        self.distanceMeters = distanceMeters
        self.pointCount = pointCount
        self.nameLat = nameLat ?? lat
        self.nameLng = nameLng ?? lng
    }
}
