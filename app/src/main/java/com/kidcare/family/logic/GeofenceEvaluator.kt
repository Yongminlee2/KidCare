package com.kidcare.family.logic

/** 부모가 정한 장소 하나. 안드로이드에 안 기대는 값 객체다. */
data class Place(
    val id: String,
    val name: String,
    val lat: Double,
    val lng: Double,
    val radiusMeters: Double,
    val notifyEnter: Boolean = true,
    val notifyExit: Boolean = true,
)

/**
 * 장소 하나에 대해 아이 폰이 기억하고 있는 것.
 *
 * [lastEventAt] 은 **부모에게 실제로 알린** 마지막 시각이다. 전환이 일어난 시각이
 * 아니다. 알리지 않기로 한 전환(알림 스위치가 꺼져 있거나 중복 억제에 걸린 것)이
 * 이 값을 밀면, 아무도 못 본 사건 때문에 5분 시계가 다시 돌아 **그다음 진짜 알림이
 * 조용히 사라진다.** 알린 적이 없으면 0 이다.
 */
data class PlaceState(
    val placeId: String,
    val inside: Boolean,
    val lastEventAt: Long,
)

/** 알릴 만한 일이 생겼다. */
data class GeofenceHit(
    val placeId: String,
    val placeName: String,
    val entering: Boolean,
    val at: Long,
)

/**
 * 위치 한 점으로 장소 도착·이탈을 판정한다.
 *
 * OS 의 GeofencingClient 를 쓰면서도 이 판정을 따로 두는 이유가 둘이다.
 * 하나, 삼성 기기는 절전 상태에서 지오펜스 전환을 몇 분씩 늦게 준다 — 이미 받고
 * 있는 위치 점으로 같은 판정을 한 번 더 하면 그 지연을 메운다. 둘, 히스테리시스와
 * 중복 억제는 안드로이드가 안 해 주는데 이게 없으면 경계에 앉은 아이 때문에
 * 부모 폰이 하루 종일 운다.
 *
 * 이 판정은 **본 것만 말한다.** 경계를 건너는 것을 본 적이 없으면(처음 보는 장소)
 * 아무 말도 하지 않는다. 설계서가 `power_off` 이벤트를 안 만들기로 한 것과 같은
 * 규율이다 — 관측하지 않은 사건을 지어내면 부모는 그 문장을 사실로 읽는다.
 */
object GeofenceEvaluator {

    /** 이탈로 인정하기 위해 반경에 더 얹는 여유(m). 경계에서 떨리는 것을 막는다. */
    const val EXIT_MARGIN_METERS: Double = 50.0

    /** 한 장소에 대해 알림을 다시 보내기까지 기다리는 시간. */
    const val DEDUPE_MILLIS: Long = 5 * 60 * 1000L

    /**
     * 이보다 오차가 크면 판정에 쓰지 않는다.
     *
     * 반경 200m 짜리 장소를 오차 300m 인 점으로 판정하면 도착·이탈이 아무 때나
     * 뒤집힌다. 못 믿는 점은 **상태도 건드리지 않는다** — 건드리면 다음 좋은 점이
     * 왔을 때 가짜 전환이 하나 만들어진다.
     *
     * 숫자를 따로 적지 않고 [LocationFilter.FALLBACK_MAX_ACCURACY_METERS] 를 그대로
     * 쓴다. 그 값은 "이보다 나쁜 점은 아무리 급해도 안 올린다"는 뜻이라, 애초에
     * 여기까지 올 수 있는 점의 상한이 그것이다. 두 숫자를 따로 두면 나중에 한쪽만
     * 바뀌었을 때 이 검사가 조용히 무의미해진다.
     */
    const val MAX_ACCURACY_METERS: Float = LocationFilter.FALLBACK_MAX_ACCURACY_METERS

    fun evaluate(
        places: List<Place>,
        states: List<PlaceState>,
        fix: Fix,
    ): Pair<List<GeofenceHit>, List<PlaceState>> {
        // 못 믿는 점에서는 아무 판단도 하지 않는다. 지워진 장소의 상태를 정리하는
        // 것도 판단이라 여기서 같이 미룬다 — 다음 좋은 점 하나면 사라진다.
        if (fix.accuracy > MAX_ACCURACY_METERS) return emptyList<GeofenceHit>() to states

        val byId = states.associateBy { it.placeId }
        val hits = mutableListOf<GeofenceHit>()
        // 지금 있는 장소만 남긴다 — 부모가 지운 장소의 상태를 계속 들고 있으면
        // 그 장소를 다시 만들었을 때 옛 판정이 되살아난다.
        val next = places.map { place ->
            val was = byId[place.id]
            // distanceMeters 는 두 점의 위경도만 읽는다. 정확도·시각 자리에 무엇을
            // 넣든 결과가 같아서 0 으로 채운다. 장소는 20개가 상한이고 이 함수는
            // 위치 점 하나에 한 번 도니, 임시 객체 스무 개는 값이 안 나가는 비용이다.
            val distance = LocationFilter.distanceMeters(Fix(place.lat, place.lng, 0f, 0L), fix)
            val nowInside = if (was?.inside == true) {
                // 안에 있던 아이는 반경 + 여유를 넘어야 나간 것으로 본다.
                distance <= place.radiusMeters + EXIT_MARGIN_METERS
            } else {
                distance <= place.radiusMeters
            }
            val notify = when {
                // 처음 보는 장소. 이미 안에 있어도 **알리지 않고 기억만 한다.**
                // 상태가 없다는 것은 대개 부모가 방금 그 장소를 만들었다는 뜻이고,
                // 그때 아이가 마침 집·학원 안에 있는 것은 아주 흔하다. 여기서
                // "도착했어요"를 보내면 일어나지도 않은 도착을, 그것도 지금 시각으로
                // 지어내는 것이 된다(아이는 세 시간 전부터 거기 있었다). 부모 화면은
                // 지도와 타임라인으로 "지금 어디 있는지"에 이미 답하고 있다.
                was == null -> false
                nowInside == was.inside -> false
                // 부모가 끈 방향은 알리지 않는다. 그래도 아래에서 inside 는 갱신한다 —
                // 안 바꾸면 반대 방향 알림까지 영영 못 나간다.
                !(if (nowInside) place.notifyEnter else place.notifyExit) -> false
                else -> {
                    val sinceLast = fix.at - was.lastEventAt
                    // 알린 적이 없으면(0) 억제할 것도 없다. 음수는 폰 시계가 뒤로
                    // 갔다는 뜻인데 그것을 '아직 5분이 안 지났다'로 읽으면 그 폰은
                    // 다시는 알림을 못 낸다 — 침묵이 이 앱에서 제일 나쁜 고장이다.
                    was.lastEventAt == 0L || sinceLast < 0L || sinceLast >= DEDUPE_MILLIS
                }
            }
            if (notify) hits += GeofenceHit(place.id, place.name, nowInside, fix.at)
            // 알리지 않기로 했어도 inside 는 바꾼다. 안 바꾸면 5분 뒤에 같은 전환이
            // 다시 잡혀 "늦게 온 도착"이 뜬다. 반대로 lastEventAt 은 **알렸을 때만**
            // 민다(PlaceState 주석 참고).
            PlaceState(place.id, nowInside, if (notify) fix.at else was?.lastEventAt ?: 0L)
        }
        return hits to next
    }
}
