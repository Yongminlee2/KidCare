package com.kidcare.family

import android.app.Application
import com.kakao.vectormap.KakaoMapSdk

/**
 * 앱 진입점.
 *
 * 카카오맵 SDK를 여기서 초기화한다. 앱키가 비어 있으면(개발기에 아직
 * local.properties.KAKAO_APP_KEY 를 안 넣은 경우) 초기화 자체를 건너뛴다 —
 * init() 을 빈 키로 부르면 SDK 내부에서 곧바로 오류를 내기 때문이다. 지도
 * 화면(MapTimelineFragment)이 같은 조건으로 안내 문구를 띄우고, 페어링·위치
 * 수집 등 지도와 무관한 기능은 이 초기화와 상관없이 그대로 동작한다.
 */
class KidCareApp : Application() {

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.KAKAO_APP_KEY.isNotEmpty()) {
            KakaoMapSdk.init(this, BuildConfig.KAKAO_APP_KEY)
        }
    }
}
