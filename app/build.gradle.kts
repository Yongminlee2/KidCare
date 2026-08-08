import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.google.services)
}

// 서명 정보는 local.properties 에서만 읽는다. 이 파일은 .gitignore 에 있고
// 키스토어(*.jks)도 마찬가지라, 저장소에는 비밀번호도 키도 남지 않는다.
// 없으면 릴리스가 **실패**해야 한다 — 아래 packageRelease 검사 참고.
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val releaseStoreFile = localProps.getProperty("releaseStoreFile")
val hasReleaseSigning = releaseStoreFile != null &&
    rootProject.file(releaseStoreFile).exists() &&
    localProps.getProperty("releaseStorePassword") != null &&
    localProps.getProperty("releaseKeyAlias") != null &&
    localProps.getProperty("releaseKeyPassword") != null

android {
    namespace = "com.kidcare.family"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.kidcare.family"
        minSdk = 26
        targetSdk = 36
        // 1~5단계가 전부 들어 있고 6단계를 마무리하는 중이다. 0.1 은 뼈대만
        // 있던 1단계 값이라 지금 상태를 완전히 잘못 말한다. 단계 번호를 그대로
        // 버전으로 쓴다 — 이 앱은 "몇 단계까지 들어간 빌드인가"가 개발일지와
        // 계획서의 유일한 좌표라, 따로 만든 번호 체계를 하나 더 두면 둘이
        // 어긋나는 날이 온다.
        versionCode = 6
        versionName = "0.6"
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    signingConfigs {
        // 값이 하나라도 없으면 이 설정 자체를 만들지 않는다. 여기서 조용히
        // 디버그 키로 물러나면 "누가 서명했는지 아무도 모르는" APK 가 나온다.
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = localProps.getProperty("releaseStorePassword")
                keyAlias = localProps.getProperty("releaseKeyAlias")
                keyPassword = localProps.getProperty("releaseKeyPassword")
            }
        }
    }

    buildTypes {
        release {
            // R8 은 이 앱에서 크래시가 아니라 **빈 화면**을 만든다.
            // 무엇을 왜 지켜야 하는지는 proguard-rules.pro 에 규칙마다 적었다.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// 서명 정보가 없으면 릴리스 패키징 직전에 크게 실패시킨다.
//
// 설정 단계에서 던지지 않는 이유: 그러면 assembleDebug 와 테스트까지 같이 죽어서
// 키스토어가 없는 기계에서는 아무것도 못 만든다. 반대로 아무 검사도 안 두면
// AGP 는 서명 없이 app-release-unsigned.apk 를 조용히 뱉는다 — 아무 폰에도 안
// 깔리는 파일이 build/outputs 에 놓여 있고, 빌드는 BUILD SUCCESSFUL 이다.
// 실패시켜야 하는 자리는 정확히 "릴리스를 실제로 만드는 순간" 하나뿐이다.
//
// run { } 으로 한 번 감싼 이유는 문법 취향이 아니다. 구성 캐시(configuration cache)는
// 태스크 액션을 직렬화해 저장하는데, 람다가 스크립트 최상위 프로퍼티를 그대로 읽으면
// 빌드 스크립트 객체까지 붙잡혀 "cannot serialize Gradle script object references" 로
// 빌드가 죽는다. 지역 변수로 한 번 옮겨 담으면 람다가 값만 들고 간다.
run {
    val signingConfigured = hasReleaseSigning
    tasks.configureEach {
        if (name == "packageRelease") {
            doFirst {
                check(signingConfigured) {
                    """
                    릴리스 서명 정보가 없다. local.properties 에 아래 네 줄을 넣고 다시 돌린다.
                      releaseStoreFile=kidcare-dev.jks
                      releaseStorePassword=...
                      releaseKeyAlias=...
                      releaseKeyPassword=...
                    키스토어 만드는 법은 docs/setup.md 의 '릴리스 서명' 절에 있다.
                    디버그 키로 대신 서명하지 않는다 — 그렇게 나온 APK 는 누가 만든
                    것인지 확인할 방법이 없다.
                    """.trimIndent()
                }
            }
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.recyclerview)
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
    implementation(libs.osmdroid.android)
    testImplementation(libs.junit)
}
