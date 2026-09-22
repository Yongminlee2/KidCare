import Foundation

enum SegmentType: Equatable {
    case stay
    case move
}

/// 하루의 한 토막.
///
/// 정본은 안드로이드 `logic/SegmentBuilder.kt` 의 `Segment`·`SegmentType`(:3-34) 이다.
///
/// `.stay` 는 한 곳에 머문 구간이고 `lat`/`lng` 는 그 구간 점들의 평균 좌표다.
/// `.move` 는 이동한 구간이고 `lat`/`lng` 는 도착 지점, `distanceMeters` 는 실제
/// 이동 거리다.
struct Segment: Equatable {
    let type: SegmentType
    let startAt: Int64
    let endAt: Int64
    let lat: Double
    let lng: Double
    let distanceMeters: Double
    let pointCount: Int

    /// **이름을 물어볼 좌표.** 역지오코딩(2단계 `Child/PlaceNamer`)에만 쓴다. 정본은
    /// `SegmentBuilder.kt:32-33`·`staySegment`(:163-183).
    ///
    /// 보호자 앱만 있던 시절에는 **일부러 뺐다** — 서버 문서 `SegmentDoc`
    /// (`core/model/Documents.kt:179-189`)에는 이 필드가 없고(아이 폰은 계산의 **결과**인
    /// `placeName` 만 올린다) 보호자는 원본 점을 가진 적이 없어 채울 수도 다시 계산할 수도
    /// 없었다. 아이 역할이 `SegmentBuilder` 를 가져오면서 자리가 생겼다.
    ///
    /// `lat`/`lng` 와 따로 두는 이유는 코틀린 주석 그대로다: 저 둘은 지도에 찍고 선을 잇는
    /// 좌표라 의미를 바꾸면 화면·타임라인·경로선이 전부 따라 바뀐다. 이름은 좌표 하나를 건물
    /// 이름으로 바꾸는 일이라 **오차에 훨씬 민감하다** — 단순 평균은 도착 순간의 나쁜 fix 한
    /// 개를 그대로 끌어안아 머무름 전체가 옆 건물 이름을 달 수 있다. 그래서 이 좌표는 **오차로
    /// 가중한 평균**이다(가중치 = 1/오차²). `.move` 구간에서는 `lat`/`lng` 와 같은 값이다.
    let nameLat: Double
    let nameLng: Double

    /// `nameLat`/`nameLng` 를 **안 넘기면 `lat`/`lng` 가 된다.** 이 기본값 덕분에 보호자 쪽의
    /// 기존 `Segment(...)` 호출(타임라인 요약·미리보기)이 한 곳도 안 바뀐다 — memberwise
    /// 초기화는 기본값을 못 받으므로 명시적 init 이 필요하다(설계서 §3.2).
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
