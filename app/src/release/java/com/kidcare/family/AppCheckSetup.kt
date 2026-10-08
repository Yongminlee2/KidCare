package com.kidcare.family

import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory

/**
 * 릴리스 빌드의 App Check — 구글 플레이 무결성 검사. **플레이 스토어로 받은 앱에서만
 * 통과한다.** 강제 적용을 켠 뒤에는 adb 로 직접 깐 릴리스 APK 가 서버에 못 닿으므로,
 * 개발자 가족 폰도 플레이(내부 테스트 트랙)로 받아야 한다(docs/setup.md "App Check").
 */
object AppCheckSetup {
    fun install() {
        FirebaseAppCheck.getInstance()
            .installAppCheckProviderFactory(PlayIntegrityAppCheckProviderFactory.getInstance())
    }
}
