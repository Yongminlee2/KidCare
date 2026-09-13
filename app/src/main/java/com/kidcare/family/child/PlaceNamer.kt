package com.kidcare.family.child

import android.content.Context
import android.util.Log
import com.kidcare.family.logic.PlaceNameCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * 좌표를 사람이 읽는 주소로 바꾼다. OpenStreetMap Nominatim 의 reverse 엔드포인트를
 * 쓴다(2026-08-07, 카카오 로컬 REST API에서 교체 — 소유자가 REST 키를 발급받지 않아
 * 머무른 곳 이름이 항상 "머무른 곳"으로만 나왔다. Nominatim 은 키 등록 자체가 없다.
 * 근거·응답 예시는 `.superpowers/geocoder-swap-report.md` 참고).
 *
 * HttpURLConnection 을 쓰는 이유: 요청이 이 한 종류뿐이라 HTTP 라이브러리를 하나 더
 * 들이는 값이 안 맞는다.
 *
 * ## 캐시 (2026-09-13 바뀜)
 *
 * **이 캐시가 '지금 위치 확인'의 속도를 정한다.** 부모가 누를 때마다 자녀 폰은 그날의
 * 머무름 이름을 전부 다시 만드는데, 이름 하나를 인터넷에 물으면 초당 1건 제한에
 * 최대 수 초가 든다. 예전 캐시는 두 군데서 새고 있었다:
 *
 * - 열쇠가 좌표를 소수점 4자리로 반올림한 글자였다. 이름을 묻는 좌표는 머무름 점들의
 *   평균이라 점이 늘 때마다 몇 미터씩 움직여 열쇠가 계속 바뀌었다 → 거의 안 맞았다.
 *   이제 [PlaceNameCache] 가 **거리**로 찾는다.
 * - 메모리에만 있어서 서비스가 다시 뜨면(업데이트·재부팅·강제 종료) 전부 사라졌다.
 *   이제 [PREFS_NAME] 에 남긴다.
 *
 * 실패한 결과(null)는 캐시하지 않는다 — 한 번의 네트워크 오류가 그 자리를 하루 종일
 * 이름 없이 가두면 안 된다.
 *
 * 잠금이 없어도 되는 이유: 부르는 쪽(TrailUploader.upload)은 늘 Main 디스패처 코루틴에서
 * 시작하고, 캐시를 읽고 쓰는 곳은 전부 그 코루틴 위다 — 네트워크 요청만 withContext(IO)
 * 로 다녀올 뿐 IO 스레드는 캐시를 건드리지 않는다. upload 자체도 tryLock 으로 겹치지 않는다.
 *
 * Nominatim 은 공개 서버를 무료로 내주는 호의성 서비스라 사용 정책이 있다(초당
 * 최대 1건, 식별 가능한 User-Agent, 결과 캐싱, 요청 시 다른 서비스로 전환 가능해야
 * 함 — nominatim.org 사용 정책). [awaitRateLimit] 이 첫째를, [USER_AGENT] 가 둘째를,
 * [cache] 가 셋째를 만족한다. 넷째(전환 가능)를 위해 엔드포인트를 [ENDPOINT]
 * 상수 하나로만 몰아뒀다.
 */
class PlaceNamer(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val cache: PlaceNameCache =
        PlaceNameCache.decode(prefs.getString(KEY_ENTRIES, null).orEmpty())

    /** 네트워크 없이 이미 아는 이름만. 모르면 null. */
    fun cachedNameOf(lat: Double, lng: Double): String? = cache.find(lat, lng)

    /**
     * 이름을 못 얻으면 null. 네트워크가 안 되거나 응답이 비어 있으면 조용히 null 이다.
     *
     * [timeoutMillis] 는 연결·읽기 각각의 제한이다. 부르는 쪽이 남은 시간 예산을
     * 넘겨 준다 — 요청 자체가 블로킹 I/O 라 코루틴 취소로는 중간에 끊기지 않기 때문에,
     * 예산을 지키려면 소켓 제한시간으로 끊어야 한다.
     */
    suspend fun nameOf(lat: Double, lng: Double, timeoutMillis: Int = TIMEOUT_MILLIS): String? {
        cache.find(lat, lng)?.let { return it }

        awaitRateLimit()
        val name = withContext(Dispatchers.IO) { request(lat, lng, timeoutMillis) } ?: return null
        cache.put(lat, lng, name)
        prefs.edit().putString(KEY_ENTRIES, cache.encode()).apply()
        return name
    }

    /**
     * Nominatim 정책의 "초당 최대 1건"을 지킨다. [lastRequestAtMillis] 를 companion
     * (프로세스 전체 공유)에 둔 이유: 호출부가 나중에 동시 호출로 바뀌어도 실제 요청
     * 간격이 1초 밑으로 내려가지 않아야 한다. "시각을 읽고 비교하고 갱신"을
     * [throttleMutex] 로 통째로 묶는 이유: 두 코루틴이 서로의 갱신을 못 보고 둘 다 짧게
     * 기다린 뒤 거의 동시에 요청을 쏘는 경쟁을 막는다.
     */
    private suspend fun awaitRateLimit() {
        throttleMutex.withLock {
            val wait = MIN_INTERVAL_MILLIS - (System.currentTimeMillis() - lastRequestAtMillis)
            if (wait > 0) delay(wait)
            lastRequestAtMillis = System.currentTimeMillis()
        }
    }

    private fun request(lat: Double, lng: Double, timeoutMillis: Int): String? {
        var connection: HttpURLConnection? = null
        return try {
            val url = URL("$ENDPOINT?format=jsonv2&lat=$lat&lon=$lng&accept-language=ko&zoom=18")
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("User-Agent", USER_AGENT)
                connectTimeout = timeoutMillis
                readTimeout = timeoutMillis
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "역지오코딩 실패: HTTP ${connection.responseCode}")
                return null
            }
            parse(connection.inputStream.bufferedReader().use { it.readText() })
        } catch (e: Exception) {
            // 순수 블로킹 I/O 뿐이라 suspend 지점이 없다 — 코루틴 취소는 여기서 예외로
            // 나타날 수 없고, 호출부(nameOf)에서 CancellationException 으로 드러난다.
            // 즉 이 catch 는 취소를 삼키지 않는다.
            Log.w(TAG, "역지오코딩 요청 실패", e)
            null
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * 상호·건물명 같은 구체적 장소명이 있으면 그게 사람에게 가장 익숙하니 그대로
     * 쓴다. 없으면 동 단위 행정 구역명을 쓰고, 도로명이 있으면 덧붙인다.
     *
     * 실제 서울 좌표 4곳을 찍어보면(`.superpowers/geocoder-swap-report.md`) suburb
     * (행정동)가 quarter(법정동)보다 훨씬 자주 채워져 있었다. 그래서 suburb 를 먼저
     * 본다. 시·도까지 전부 붙이면 화면에서 잘리므로 그 아래만 남긴다.
     */
    private fun parse(body: String): String? {
        val address = JSONObject(body).optJSONObject("address") ?: return null

        listOf("amenity", "shop", "building")
            .firstNotNullOfOrNull { key -> address.optString(key).takeIf(String::isNotEmpty) }
            ?.let { return it }

        val region = listOf("suburb", "quarter", "neighbourhood", "city_district")
            .firstNotNullOfOrNull { key -> address.optString(key).takeIf(String::isNotEmpty) }
            ?: return null

        val road = address.optString("road").takeIf { it.isNotEmpty() && it != region }
        return if (road != null) "$region $road" else region
    }

    companion object {
        private const val TAG = "PlaceNamer"

        // Nominatim 사용 정책이 "다른 서비스로 언제든 전환 가능해야 한다"를 요구한다
        // — 그래서 엔드포인트를 이 상수 하나로만 몰아둔다.
        private const val ENDPOINT = "https://nominatim.openstreetmap.org/reverse"

        // 앱을 식별하는 값만 넣는다 — 이메일 등 개인정보는 제3자(OSM 재단) 서버로
        // 나가는 이 헤더에 넣지 않는다.
        private const val USER_AGENT = "KidCare/1.0 (com.kidcare.family)"

        const val TIMEOUT_MILLIS = 5000
        private const val MIN_INTERVAL_MILLIS = 1000L

        private const val PREFS_NAME = "kidcare_place_names"
        private const val KEY_ENTRIES = "entries"

        private val throttleMutex = Mutex()
        private var lastRequestAtMillis = 0L
    }
}
