package com.kidcare.family.logic

/**
 * 역지오코딩으로 얻은 장소 이름을 좌표 **근처**로 찾는 캐시.
 *
 * **왜 있나 — '지금 위치 확인'이 느리던 주범이었다.** 예전 캐시는 좌표를 소수점
 * 4자리로 반올림한 문자열을 열쇠로 썼다. 그런데 이름을 묻는 좌표
 * ([SegmentBuilder] 의 nameLat/nameLng)는 머무름 안의 점들을 오차로 가중한
 * **평균**이라, 같은 집에 앉아 있어도 점이 하나 늘 때마다 몇 미터씩 움직인다.
 * 반올림한 열쇠가 그때마다 달라져 캐시가 거의 안 맞았고, 부모가 누를 때마다 그날의
 * 머무름을 전부 다시 인터넷에 물었다. 한 곳에 초당 1건 제한 + 최대 5초라, 머무름이
 * 열 곳이면 수십 초 동안 부모 화면이 "확인하는 중"에 멈춰 있었다.
 *
 * 그래서 열쇠를 버리고 **거리**로 찾는다. [MATCH_RADIUS_METERS] 안에 아는 이름이
 * 있으면 그것을 쓴다.
 *
 * 안드로이드를 모른다. 디스크에 남기는 일은 [encode]/[decode] 로 글자만 주고받고,
 * 실제 저장은 부르는 쪽(child/PlaceNamer)이 한다 — JVM 단위 테스트 대상이다.
 */
class PlaceNameCache(
    private val matchRadiusMeters: Double = MATCH_RADIUS_METERS,
    private val maxEntries: Int = MAX_ENTRIES,
) {

    data class Entry(val lat: Double, val lng: Double, val name: String)

    /** 뒤로 갈수록 최근에 넣은 것. 상한을 넘으면 앞(오래된 것)부터 버린다. */
    private val entries = ArrayDeque<Entry>()

    val size: Int get() = entries.size

    /** 반경 안에서 가장 가까운 이름. 없으면 null. */
    fun find(lat: Double, lng: Double): String? {
        var best: Entry? = null
        var bestDistance = Double.MAX_VALUE
        for (entry in entries) {
            val distance = distanceMeters(lat, lng, entry.lat, entry.lng)
            if (distance <= matchRadiusMeters && distance < bestDistance) {
                best = entry
                bestDistance = distance
            }
        }
        return best?.name
    }

    /**
     * 이름을 넣는다. 같은 자리(반경 안)에 이미 있던 것은 **바꿔 끼운다** — 안 그러면
     * 집처럼 매일 가는 곳이 흔들린 좌표마다 한 칸씩 늘어 상한을 금방 채운다.
     */
    fun put(lat: Double, lng: Double, name: String) {
        val clean = name.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ').trim()
        if (clean.isEmpty()) return
        entries.removeAll { distanceMeters(lat, lng, it.lat, it.lng) <= matchRadiusMeters }
        entries.addLast(Entry(lat, lng, clean))
        while (entries.size > maxEntries) entries.removeFirst()
    }

    /** 한 줄에 한 곳: `위도,경도<탭>이름`. */
    fun encode(): String = entries.joinToString("\n") { "${it.lat},${it.lng}\t${it.name}" }

    companion object {
        /**
         * 같은 곳으로 볼 거리. 머무름 반경([SegmentBuilder.STAY_RADIUS_METERS], 40m)보다
         * 조금 작게 잡는다 — 한 머무름 안에서 이름 좌표가 흔들리는 폭은 그 반경 안에
         * 들고, 서로 다른 머무름은 대개 그보다 멀리 떨어져 있다.
         */
        const val MATCH_RADIUS_METERS = 30.0

        /** 아이가 다니는 곳은 많아야 수십 곳이다. 넉넉히 두되 끝없이 늘지는 않게. */
        const val MAX_ENTRIES = 300

        /** 망가진 줄은 조용히 건너뛴다 — 캐시 한 줄 때문에 이름 전체를 잃으면 안 된다. */
        fun decode(
            text: String,
            matchRadiusMeters: Double = MATCH_RADIUS_METERS,
            maxEntries: Int = MAX_ENTRIES,
        ): PlaceNameCache {
            val cache = PlaceNameCache(matchRadiusMeters, maxEntries)
            for (line in text.lineSequence()) {
                val tab = line.indexOf('\t')
                if (tab <= 0) continue
                val coordinates = line.substring(0, tab).split(',')
                if (coordinates.size != 2) continue
                val lat = coordinates[0].toDoubleOrNull() ?: continue
                val lng = coordinates[1].toDoubleOrNull() ?: continue
                cache.put(lat, lng, line.substring(tab + 1))
            }
            return cache
        }

        private fun distanceMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double =
            LocationFilter.distanceMeters(Fix(lat1, lng1, 0f, 0L), Fix(lat2, lng2, 0f, 0L))
    }
}
