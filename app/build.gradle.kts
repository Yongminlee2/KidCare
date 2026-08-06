import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.google.services)
}

// 카카오 앱키는 기계마다 다르고 git 에 올리면 안 되므로 local.properties 에서 읽는다.
// 없으면 빈 문자열로 두고, 지도 화면이 "키 설정 필요" 안내를 띄운다. 빌드는 막지 않는다.
val localProps = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
val kakaoAppKey: String = localProps.getProperty("KAKAO_APP_KEY") ?: ""
// REST 키는 앱키와 다른 키다(용도가 다르다) — 좌표를 주소로 바꾸는 coord2address 호출에만
// 쓴다. 마찬가지로 없으면 빈 문자열이고, 이 경우 PlaceNamer 가 네트워크 호출 없이 null 을
// 돌려줘서 머무른 곳이 이름 없이 표시될 뿐 빌드나 실행이 막히지 않는다.
val kakaoRestKey: String = localProps.getProperty("KAKAO_REST_KEY") ?: ""

android {
    namespace = "com.kidcare.family"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.kidcare.family"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        buildConfigField("String", "KAKAO_APP_KEY", "\"$kakaoAppKey\"")
        buildConfigField("String", "KAKAO_REST_KEY", "\"$kakaoRestKey\"")
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.activity.ktx)
    implementation(libs.androidx.fragment.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.kotlinx.coroutines.android)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.firestore)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.play.services.location)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.kakao.map)
    testImplementation(libs.junit)
}
