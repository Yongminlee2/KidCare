package com.kidcare.family.child

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager

/**
 * 아이 폰이 지금 무엇으로 인터넷에 붙어 있는지, 와이파이 스위치가 켜져 있는지.
 *
 * **끄고 켜는 기능은 없다.** 안드로이드 10부터 `WifiManager.setWifiEnabled` 는
 * 서드파티 앱에 항상 실패를 돌려주고, 모바일 데이터는 그보다 더 오래전부터 막혀
 * 있다. 유일한 우회로인 기기 소유자(Device Owner) 등록은 **아이 폰을 초기화해야**
 * 하는데 사용자가 그러지 않기로 정했다(6단계 계획서 "다루지 않는 것"). 그래서
 * 이 파일은 읽기만 한다 — 읽는 것은 막혀 있지 않다.
 *
 * 두 값을 따로 올리는 이유: 둘이 다른 것을 말한다. 와이파이 스위치가 켜져 있어도
 * 공유기가 인터넷에 못 나가면 [current] 는 [NONE] 이다. 부모가 "왜 위치가 안 와요"를
 * 풀 때 필요한 것은 그 구분이다.
 */
object NetworkState {

    const val WIFI = "wifi"
    const val CELL = "cell"
    const val NONE = "none"
    /** 읽지 못했다. 값을 넘겨짚느니 모른다고 말한다. */
    const val UNKNOWN = ""

    fun current(context: Context): String = try {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val capabilities = manager?.activeNetwork?.let { manager.getNetworkCapabilities(it) }
        when {
            capabilities == null -> NONE
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> WIFI
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> CELL
            else -> NONE
        }
    } catch (e: Exception) {
        UNKNOWN
    }

    /** 와이파이 스위치 상태. 못 읽으면 null — 화면은 그때 "확인 못 했어요"라고 말한다. */
    fun wifiEnabled(context: Context): Boolean? = try {
        // applicationContext 로 얻는다. WifiManager 는 액티비티 컨텍스트로 얻으면
        // 그 액티비티가 죽을 때까지 참조가 남는다(구글이 명시한 사용법이다).
        context.applicationContext.getSystemService(WifiManager::class.java)?.isWifiEnabled
    } catch (e: Exception) {
        null
    }
}
