package com.kidcare.family.child

import android.util.Log
import com.kidcare.family.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * 좌표를 사람이 읽는 주소로 바꾼다. 카카오 로컬 REST API 의 coord2address 를 쓴다.
 *
 * HttpURLConnection 을 쓰는 이유: 요청이 이 한 종류뿐이라 HTTP 라이브러리를 하나 더
 * 들이는 값이 안 맞는다.
 *
 * 결과를 메모리에 캐시한다. 아이는 같은 곳(집·학교·학원)에 반복해서 머무르므로
 * 캐시가 없으면 같은 좌표를 하루에 수십 번 물어보게 된다. 좌표는 소수점 4자리
 * (약 11m)로 뭉쳐서 키를 만든다 — 그보다 정밀하게 나눠봐야 같은 건물이다.
 *
 * 캐시는 일반 mutableMapOf 다. 잠금이 없어도 되는 이유: 이 클래스를 부르는 쪽
 * (SegmentUploader.rebuildToday)은 항상 Main 디스패처의 코루틴에서 시작하고,
 * cache 를 읽고 쓰는 두 지점(nameOf 의 시작과 끝)은 둘 다 그 Main 코루틴 위에서
 * 실행된다 — 네트워크 요청만 withContext(IO) 로 다른 스레드에 다녀올 뿐, IO
 * 스레드는 cache 를 건드리지 않는다. Main 디스패처는 한 번에 코루틴 하나만
 * 실행하므로(진짜 병렬이 아니라 협조적 교차 실행) 같은 좌표를 거의 동시에 두 번
 * 묻는 경우(호출이 겹치면) 네트워크 요청이 중복될 수는 있어도 맵 자체가 두 스레드에서
 * 동시에 쓰여 깨지는 일은 없다.
 */
class PlaceNamer {

    private val cache = mutableMapOf<String, String>()

    /** 이름을 못 얻으면 null. 키가 없거나 네트워크가 안 되면 조용히 null 이다. */
    suspend fun nameOf(lat: Double, lng: Double): String? {
        if (BuildConfig.KAKAO_REST_KEY.isEmpty()) return null

        val key = "%.4f,%.4f".format(lat, lng)
        cache[key]?.let { return it }

        val name = withContext(Dispatchers.IO) { request(lat, lng) } ?: return null
        cache[key] = name
        return name
    }

    private fun request(lat: Double, lng: Double): String? {
        var connection: HttpURLConnection? = null
        return try {
            val url = URL("$ENDPOINT?x=$lng&y=$lat")
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("Authorization", "KakaoAK ${BuildConfig.KAKAO_REST_KEY}")
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
     * 도로명 주소가 있으면 그쪽이 사람에게 더 익숙하고, 없으면 지번 주소를 쓴다.
     * 시·도까지 전부 붙이면 화면에서 잘리므로 읍면동 이하만 남긴다.
     */
    private fun parse(body: String): String? {
        val documents = JSONObject(body).optJSONArray("documents") ?: return null
        if (documents.length() == 0) return null
        val first = documents.optJSONObject(0) ?: return null

        first.optJSONObject("road_address")?.let { road ->
            val name = road.optString("building_name")
            if (name.isNotEmpty()) return name
            val region = road.optString("region_3depth_name")
            val main = road.optString("road_name")
            if (region.isNotEmpty() && main.isNotEmpty()) return "$region $main"
        }
        first.optJSONObject("address")?.let { address ->
            val region = address.optString("region_3depth_name")
            val bunji = address.optString("main_address_no")
            if (region.isNotEmpty()) return if (bunji.isNotEmpty()) "$region $bunji" else region
        }
        return null
    }

    private companion object {
        const val TAG = "PlaceNamer"
        const val ENDPOINT = "https://dapi.kakao.com/v2/local/geo/coord2address.json"
        const val TIMEOUT_MILLIS = 5000
    }
}
