package com.kidcare.family.child

import android.util.Log
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
 * 결과를 메모리에 캐시한다. 아이는 같은 곳(집·학교·학원)에 반복해서 머무르므로
 * 캐시가 없으면 같은 좌표를 하루에 수십 번 물어보게 된다. 좌표는 소수점 4자리
 * (약 11m)로 뭉쳐서 키를 만든다 — 그보다 정밀하게 나눠봐야 같은 건물이다. 실패한
 * 결과(null)는 캐시하지 않는다 — 한 번의 네트워크 오류가 그 좌표를 하루 종일
 * 이름 없이 가두면 안 된다.
 *
 * 캐시는 일반 mutableMapOf 다. 잠금이 없어도 되는 이유: 이 클래스를 부르는 쪽
 * (SegmentUploader.rebuildToday)은 항상 Main 디스패처의 코루틴에서 시작하고,
 * cache 를 읽고 쓰는 두 지점(nameOf 의 시작과 끝)은 둘 다 그 Main 코루틴 위에서
 * 실행된다 — 네트워크 요청만 withContext(IO) 로 다른 스레드에 다녀올 뿐, IO
 * 스레드는 cache 를 건드리지 않는다. Main 디스패처는 한 번에 코루틴 하나만
 * 실행하므로(진짜 병렬이 아니라 협조적 교차 실행) 같은 좌표를 거의 동시에 두 번
 * 묻는 경우(호출이 겹치면) 네트워크 요청이 중복될 수는 있어도 맵 자체가 두 스레드에서
 * 동시에 쓰여 깨지는 일은 없다.
 *
 * Nominatim 은 공개 서버를 무료로 내주는 호의성 서비스라 사용 정책이 있다(초당
 * 최대 1건, 식별 가능한 User-Agent, 결과 캐싱, 요청 시 다른 서비스로 전환 가능해야
 * 함 — nominatim.org 사용 정책). [awaitRateLimit] 이 첫째를, [USER_AGENT] 가 둘째를,
 * 위 [cache] 가 셋째를 만족한다. 넷째(전환 가능)를 위해 엔드포인트를 [ENDPOINT]
 * 상수 하나로만 몰아뒀다.
 */
class PlaceNamer {

    private val cache = mutableMapOf<String, String>()

    /** 이름을 못 얻으면 null. 네트워크가 안 되거나 응답이 비어 있으면 조용히 null 이다. */
    suspend fun nameOf(lat: Double, lng: Double): String? {
        val key = "%.4f,%.4f".format(lat, lng)
        cache[key]?.let { return it }

        awaitRateLimit()
        val name = withContext(Dispatchers.IO) { request(lat, lng) } ?: return null
        cache[key] = name
        return name
    }

    /**
     * Nominatim 정책의 "초당 최대 1건"을 지킨다. [lastRequestAtMillis] 를 인스턴스가
     * 아니라 companion(프로세스 전체 공유)에 둔 이유: 한 rebuildToday 안에서 캐시
     * 안 된 머무름 여러 개가 연달아 풀리는 경우(지금은 for 루프라 순차 호출이지만,
     * 호출부가 나중에 동시 호출로 바뀌어도) 실제 요청 간격이 1초 밑으로 내려가지
     * 않아야 한다. "시각을 읽고 비교하고 lastRequestAtMillis 를 갱신"하는 세 동작을
     * [throttleMutex] 로 통째로 묶는 이유: 두 코루틴이 동시에 "아직 안 지났으니
     * 이만큼만 기다리자"를 계산하면 그 계산이 서로의 갱신을 못 보고 둘 다 짧게
     * 기다린 뒤 거의 동시에 요청을 쏘는 경쟁이 생긴다. 요청 시각 갱신까지 락 안에서
     * 끝내면 다음 호출은 반드시 갱신된 값을 보고서야 자기 대기 시간을 계산한다.
     * delay() 를 쓰는 이유: Thread.sleep 은 그동안 스레드를 통째로 묶는데, 여기는
     * 코루틴이라 delay() 로 스레드를 놓아주고 재울 수 있다.
     */
    private suspend fun awaitRateLimit() {
        throttleMutex.withLock {
            val wait = MIN_INTERVAL_MILLIS - (System.currentTimeMillis() - lastRequestAtMillis)
            if (wait > 0) delay(wait)
            lastRequestAtMillis = System.currentTimeMillis()
        }
    }

    private fun request(lat: Double, lng: Double): String? {
        var connection: HttpURLConnection? = null
        return try {
            val url = URL("$ENDPOINT?format=jsonv2&lat=$lat&lon=$lng&accept-language=ko&zoom=18")
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("User-Agent", USER_AGENT)
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "역지오코딩 실패: HTTP ${connection.responseCode}")
                return null
            }
            parse(connection.inputStream.bufferedReader().use { it.readText() })
        } catch (e: Exception) {
            // 이 함수는 순수 블로킹 I/O 뿐이라 suspend 지점이 없다 — 코루틴 취소는
            // 여기서 예외로 나타날 수 없고, withContext(IO) 가 반환할 때가 돼서야
            // 호출부(nameOf)에서 CancellationException 으로 드러난다. 즉 이 catch 는
            // 취소를 삼키지 않는다.
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
     * (행정동, 예: "역삼1동")가 quarter(법정동, 예: "태평로1가")보다 훨씬 자주
     * 채워져 있었다 — 4곳 다 suburb 는 있었지만 quarter 는 2곳만 있었다. 그래서
     * neighbourhood/quarter/suburb/city_district 문서 순서 대신 suburb 를 먼저
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

    private companion object {
        const val TAG = "PlaceNamer"

        // Nominatim 사용 정책이 "다른 서비스로 언제든 전환 가능해야 한다"를 요구한다
        // — 그래서 엔드포인트를 이 상수 하나로만 몰아둔다. 옮길 때는 이 줄과
        // request()/parse() 의 파라미터·응답 파싱만 바꾸면 된다.
        const val ENDPOINT = "https://nominatim.openstreetmap.org/reverse"

        // 앱을 식별하는 값만 넣는다 — 이메일 등 개인정보는 제3자(OSM 재단) 서버로
        // 나가는 이 헤더에 넣지 않는다.
        const val USER_AGENT = "KidCare/1.0 (com.kidcare.family)"

        const val TIMEOUT_MILLIS = 5000
        const val MIN_INTERVAL_MILLIS = 1000L

        val throttleMutex = Mutex()
        var lastRequestAtMillis = 0L
    }
}
