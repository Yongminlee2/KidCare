import Foundation

/// 부모가 정한 장소 하나. 정본 `logic/GeofenceEvaluator.kt:4-12`.
/// `Core/Documents.swift` 의 `PlaceDoc`(Firestore 문서 표현)과 나뉜 이유는 그 문서 주석과 같다 —
/// 판정은 Firestore 를 몰라야 골든 대조가 가능하다.
struct Place: Equatable, Sendable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let radiusMeters: Double
    let notifyEnter: Bool
    let notifyExit: Bool

    init(id: String, name: String, lat: Double, lng: Double, radiusMeters: Double,
         notifyEnter: Bool = true, notifyExit: Bool = true) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lng = lng
        self.radiusMeters = radiusMeters
        self.notifyEnter = notifyEnter
        self.notifyExit = notifyExit
    }
}

/// 장소 하나에 대해 아이 폰이 기억하고 있는 것. 정본 `:14-26`.
///
/// `lastEventAt` 은 **부모에게 실제로 알린** 마지막 시각이다. 전환이 일어난 시각이 아니다.
/// 알리지 않기로 한 전환이 이 값을 밀면, 아무도 못 본 사건 때문에 5분 시계가 다시 돌아
/// **그다음 진짜 알림이 조용히 사라진다.** 알린 적이 없으면 0 이다.
struct PlaceState: Equatable, Sendable {
    let placeId: String
    let inside: Bool
    let lastEventAt: Int64
}

/// 알릴 만한 일이 생겼다. 정본 `:28-34`.
struct GeofenceHit: Equatable, Sendable {
    let placeId: String
    let placeName: String
    let entering: Bool
    let at: Int64
}

/// 위치 한 점으로 장소 도착·이탈을 판정한다. 정본 `logic/GeofenceEvaluator.kt:49-124`.
///
/// OS 지역 감시를 쓰면서도 이 판정을 따로 두는 이유는 안드로이드와 같다 — 그 콜백에는
/// 히스테리시스도, 5분 중복 억제도, 정확도 문턱도 없다. 경계에 앉은 아이 하나 때문에 부모
/// 폰이 하루 종일 운다. 아이폰에서는 이유가 하나 더 붙는다: iOS 의 지역 콜백은 좌표를 아예
/// 안 준다(설계서 §7.1).
///
/// 이 판정은 **본 것만 말한다.** 경계를 건너는 것을 본 적이 없으면 아무 말도 하지 않는다.
enum GeofenceEvaluator {

    /// 이탈로 인정하기 위해 반경에 더 얹는 여유(m). 경계에서 떨리는 것을 막는다(`:52`).
    static let exitMarginMeters: Double = 50.0

    /// 한 장소에 대해 알림을 다시 보내기까지 기다리는 시간(`:55`).
    static let dedupeMillis: Int64 = 5 * 60 * 1000

    /// 이보다 오차가 크면 판정에 쓰지 않는다.
    ///
    /// **숫자를 따로 적지 않는다**(`:57-69`). `fallbackMaxAccuracyMeters` 는 "이보다 나쁜 점은
    /// 아무리 급해도 안 올린다"는 뜻이라, 애초에 여기까지 올 수 있는 점의 상한이 그것이다.
    /// 두 숫자를 따로 두면 나중에 한쪽만 바뀌었을 때 이 검사가 조용히 무의미해진다.
    static let maxAccuracyMeters: Double = LocationFilter.fallbackMaxAccuracyMeters

    static func evaluate(places: [Place], states: [PlaceState], fix: Fix) -> (hits: [GeofenceHit], states: [PlaceState]) {
        // 못 믿는 점에서는 아무 판단도 하지 않는다. 지워진 장소의 상태를 정리하는 것도 판단이라
        // 여기서 같이 미룬다 — 다음 좋은 점 하나면 사라진다(`:76-78`).
        if fix.accuracy > maxAccuracyMeters { return ([], states) }

        // 코틀린 associateBy 는 키가 겹치면 **뒤엣것**을 남긴다. 같은 규칙을 명시한다.
        let byId = Dictionary(states.map { ($0.placeId, $0) }, uniquingKeysWith: { _, last in last })
        var hits: [GeofenceHit] = []
        var next: [PlaceState] = []
        next.reserveCapacity(places.count)

        // 지금 있는 장소만 남긴다 — 부모가 지운 장소의 상태를 계속 들고 있으면 그 장소를 다시
        // 만들었을 때 옛 판정이 되살아난다(`:82-84`).
        for place in places {
            let was = byId[place.id]
            // distanceMeters 는 두 점의 위경도만 읽는다. 정확도·시각 자리는 0 으로 채운다(`:86-89`).
            let distance = LocationFilter.distanceMeters(
                Fix(lat: place.lat, lng: place.lng, accuracy: 0, at: 0), fix)
            let nowInside: Bool = if was?.inside == true {
                // 안에 있던 아이는 반경 + 여유를 넘어야 나간 것으로 본다.
                distance <= place.radiusMeters + exitMarginMeters
            } else {
                distance <= place.radiusMeters
            }

            let notify: Bool
            if let was {
                if nowInside == was.inside {
                    notify = false
                } else if !(nowInside ? place.notifyEnter : place.notifyExit) {
                    // 부모가 끈 방향은 알리지 않는다. 그래도 아래에서 inside 는 갱신한다(`:105-107`).
                    notify = false
                } else {
                    let sinceLast = fix.at - was.lastEventAt
                    // 알린 적이 없으면(0) 억제할 것도 없다. 음수는 폰 시계가 뒤로 갔다는 뜻인데
                    // 그것을 '아직 5분이 안 지났다'로 읽으면 그 폰은 다시는 알림을 못 낸다 —
                    // 침묵이 이 앱에서 제일 나쁜 고장이다(`:109-114`).
                    notify = was.lastEventAt == 0 || sinceLast < 0 || sinceLast >= dedupeMillis
                }
            } else {
                // 처음 보는 장소. 이미 안에 있어도 **알리지 않고 기억만 한다**(`:97-103`).
                // 상태가 없다는 것은 대개 부모가 방금 그 장소를 만들었다는 뜻이고, 그때 아이가
                // 마침 집·학원 안에 있는 것은 아주 흔하다. 여기서 "도착했어요"를 보내면 일어나지도
                // 않은 도착을, 그것도 지금 시각으로 지어내는 것이 된다.
                notify = false
            }

            if notify {
                hits.append(GeofenceHit(placeId: place.id, placeName: place.name, entering: nowInside, at: fix.at))
            }
            // 알리지 않기로 했어도 inside 는 바꾼다. 안 바꾸면 5분 뒤에 같은 전환이 다시 잡혀
            // "늦게 온 도착"이 뜬다. 반대로 lastEventAt 은 **알렸을 때만** 민다(`:117-120`).
            next.append(PlaceState(placeId: place.id, inside: nowInside,
                                   lastEventAt: notify ? fix.at : (was?.lastEventAt ?? 0)))
        }
        return (hits, next)
    }
}
