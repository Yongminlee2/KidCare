package com.kidcare.family

import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory

/**
 * 디버그 빌드의 App Check. 기기에서 처음 켜면 logcat 에 디버그 토큰이 한 줄 찍힌다
 * (`DebugAppCheckProvider` 태그). 콘솔에 그 토큰을 등록해야 강제 적용 뒤에도 이 빌드가
 * 서버에 닿는다. 디버그 공급자는 릴리스 APK 에 들어가면 안 되므로 빌드별 소스에 둔다.
 */
object AppCheckSetup {
    fun install() {
        FirebaseAppCheck.getInstance()
            .installAppCheckProviderFactory(DebugAppCheckProviderFactory.getInstance())
    }
}
