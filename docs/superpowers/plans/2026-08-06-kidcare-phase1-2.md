# KidCare 1~2단계 구현 계획 (뼈대·페어링·위치 수집·지도)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 부모 폰과 자녀 폰을 초대 코드로 연결하고, 자녀 폰이 위치를 주기적으로 올리면 부모 폰 카카오맵에 현재 위치가 보이는 데까지 만든다.

**Architecture:** APK 하나에 보호자/자녀 두 역할이 들어간다. 첫 실행 때 역할을 고르고 6자리 코드로 페어링하면 역할이 잠긴다. 자녀 폰은 상시 포그라운드 서비스가 FusedLocationProvider로 위치를 받아 Firestore의 `status` 문서와 `points` 컬렉션에 쓰고, 보호자 폰은 `status`를 실시간 구독해 카카오맵에 마커를 찍는다. 순수 계산(초대 코드, 위치 필터)은 안드로이드 API에 의존하지 않는 `logic/` 패키지에 두고 JUnit으로 먼저 테스트를 쓴다.

**Tech Stack:** Kotlin (AGP 9 내장), Views + ViewBinding, Material3, Firebase(Auth 익명 / Firestore), play-services-location, 카카오맵 SDK v2, JUnit4

**설계서:** `docs/superpowers/specs/2026-08-06-kidcare-design.md`

## Global Constraints

- 프로젝트 루트는 `C:\workAndroid\KidCare`. HomeCam(`C:\workAndroid\app`)과 무관한 독립 Gradle 루트다.
- AGP `9.2.1` / Gradle `9.4.1` / compileSdk `37` / minSdk `26` / targetSdk `36`
  (compileSdk 는 원래 36 으로 잡았으나 `core-ktx 1.19.0` 이 37 을 요구해 AGP 가 빌드를 거부한다.
  Task 1 에서 37 로 올렸다. targetSdk 는 36 그대로다.)
- applicationId·namespace 는 `com.kidcare.family`. 앱 표시명은 `우리아이 지킴이`.
- UI는 Views + ViewBinding + Material3. **Compose를 쓰지 않는다.**
- AGP 9는 Kotlin 지원이 내장이다. `kotlin-android` 플러그인을 따로 적용하지 않는다.
- `logic/` 패키지는 **안드로이드 API를 import 하지 않는다.** 순수 코틀린만 둔다. JVM 단위 테스트가 여기에 걸린다.
- 비밀값은 git에 올리지 않는다: `local.properties`(카카오 앱키), `app/google-services.json`, `keystore.properties`, `*.jks`
- 모든 시각은 UTC 밀리초(`System.currentTimeMillis()`)로 저장한다. 표시할 때만 기기 시간대로 바꾼다.
- 사용자 대상 문자열은 전부 한국어이며 `res/values/strings.xml`에 둔다. 코드에 하드코딩하지 않는다.
- 커밋 메시지는 한국어. **AI/Claude 관련 표기(Co-Authored-By 포함)를 넣지 않는다.**
- git 저자는 `Yongminlee2 <dydals5678@gmail.com>`. 이 저장소에는 전역 git identity가 없으므로 `git -c user.name=... -c user.email=...` 형태로 커밋하거나 `git config user.name/user.email`을 저장소에 설정한다.
- 브랜치를 나누지 않고 `main`에 직접 커밋한다.

## 사용자 준비물 (코드로 대신할 수 없음)

작업을 막지 않도록 **Task 1~2는 준비물 없이 진행 가능**하게 짰다. 아래 두 가지는 Task 3 전까지만 준비되면 된다.

| 준비물 | 필요한 시점 | 없으면 |
|---|---|---|
| `app/google-services.json` | **Task 3** | google-services 플러그인이 빌드를 실패시킨다 |
| 카카오 네이티브 앱키 (`local.properties`) | **Task 10** | 지도 대신 "지도 키 설정이 필요합니다" 화면이 뜬다 (빌드는 됨) |

발급 절차는 `docs/setup.md`에 Task 3과 Task 10에서 각각 기록한다.

## File Structure

```
KidCare/
├─ settings.gradle.kts            리포지터리 선언(google, mavenCentral, 카카오)
├─ build.gradle.kts               루트 — 플러그인 apply false
├─ gradle.properties              JVM 인자, AndroidX, 한글 홈 대응 인코딩
├─ gradle/libs.versions.toml      모든 버전을 여기 한 곳에
├─ gradle/wrapper/                WordChain 것을 복사
├─ gradlew, gradlew.bat
├─ local.properties               sdk.dir + KAKAO_APP_KEY  (gitignore)
├─ docs/setup.md                  카카오·Firebase 설정 절차 기록
└─ app/
   ├─ build.gradle.kts
   ├─ google-services.json        (gitignore)
   └─ src/
      ├─ main/
      │  ├─ AndroidManifest.xml
      │  ├─ java/com/kidcare/family/
      │  │  ├─ KidCareApp.kt              Application. 카카오 SDK 초기화
      │  │  ├─ RouterActivity.kt          런처. 저장된 역할에 따라 분기
      │  │  ├─ logic/                     ★순수 코틀린. 안드로이드 import 금지
      │  │  │  ├─ InviteCode.kt           6자리 코드 생성·검증
      │  │  │  └─ LocationFilter.kt       업로드할 위치인지 판정
      │  │  ├─ core/
      │  │  │  ├─ Role.kt                 역할 enum + SharedPreferences 저장
      │  │  │  ├─ AuthGateway.kt          Firebase 익명 로그인
      │  │  │  ├─ FamilyRepository.kt     가족 생성/참여/구독
      │  │  │  └─ model/Documents.kt      Firestore 문서와 1:1 데이터 클래스
      │  │  ├─ onboarding/
      │  │  │  ├─ RoleSelectActivity.kt
      │  │  │  ├─ GuardianPairingActivity.kt
      │  │  │  ├─ ChildPairingActivity.kt
      │  │  │  └─ PermissionActivity.kt   자녀 권한 온보딩
      │  │  ├─ child/
      │  │  │  ├─ ChildHomeActivity.kt    아이가 보는 상태 화면
      │  │  │  ├─ TrackingService.kt      상시 포그라운드 서비스
      │  │  │  ├─ LocationCollector.kt    FusedLocation 래퍼
      │  │  │  ├─ StatusReporter.kt       status/points 쓰기
      │  │  │  └─ BootReceiver.kt         재부팅 시 서비스 재시작
      │  │  └─ guardian/
      │  │     ├─ GuardianMainActivity.kt 프래그먼트 컨테이너
      │  │     └─ MapTimelineFragment.kt  카카오맵 + 상태줄
      │  └─ res/
      │     ├─ layout/…  values/strings.xml  values/themes.xml  drawable/…
      └─ test/java/com/kidcare/family/logic/
         ├─ InviteCodeTest.kt
         └─ LocationFilterTest.kt
```

**책임 경계:** `logic/`은 계산만, `core/`는 Firebase 접근만, `child/`·`guardian/`·`onboarding/`은 화면과 안드로이드 서비스만 담당한다. `child/`와 `guardian/`은 서로를 import 하지 않는다 — 둘 다 `core/`를 통해서만 대화한다.

---

### Task 1: Gradle 뼈대와 첫 빌드

기존 프로젝트(WordChain)와 같은 빌드 환경을 세우고, **빈 앱이 폰에 설치되는 것**까지 확인한다. Firebase와 카카오는 아직 붙이지 않는다 — 준비물 없이 여기까지는 갈 수 있어야 한다.

**Files:**
- Create: `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`
- Create: `gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties` (WordChain에서 복사)
- Create: `app/build.gradle.kts`, `app/src/main/AndroidManifest.xml`
- Create: `app/src/main/java/com/kidcare/family/RouterActivity.kt`
- Create: `app/src/main/res/layout/activity_router.xml`, `res/values/strings.xml`, `res/values/themes.xml`
- Create: `app/src/test/java/com/kidcare/family/logic/SmokeTest.kt`
- Modify: `.gitignore` (이미 있음 — `docs/`는 추적, `local.properties` 제외 확인)

**Interfaces:**
- Consumes: 없음 (첫 작업)
- Produces: `com.kidcare.family.RouterActivity` — 런처 액티비티. 이후 Task 4에서 역할 분기 로직이 들어간다.

- [ ] **Step 1: Gradle 래퍼를 WordChain에서 복사한다**

```bash
cp /c/workAndroid/WordChain/gradlew /c/workAndroid/KidCare/gradlew
cp /c/workAndroid/WordChain/gradlew.bat /c/workAndroid/KidCare/gradlew.bat
mkdir -p /c/workAndroid/KidCare/gradle/wrapper
cp /c/workAndroid/WordChain/gradle/wrapper/gradle-wrapper.jar /c/workAndroid/KidCare/gradle/wrapper/
cp /c/workAndroid/WordChain/gradle/wrapper/gradle-wrapper.properties /c/workAndroid/KidCare/gradle/wrapper/
```

- [ ] **Step 2: `gradle/libs.versions.toml` 을 쓴다**

버전은 2026-08-06에 Google Maven / Maven Central에서 확인한 최신 안정판이다. RC·beta는 넣지 않았다.

```toml
[versions]
agp = "9.2.1"
googleServices = "4.5.0"
firebaseBom = "34.17.0"
playServicesLocation = "21.4.0"
kakaoMap = "2.14.1"
coroutines = "1.11.0"
coreKtx = "1.19.0"
appcompat = "1.7.1"
material = "1.14.0"
constraintlayout = "2.2.2"
activityKtx = "1.13.0"
fragmentKtx = "1.8.9"
lifecycle = "2.11.0"
junit = "4.13.2"

[libraries]
androidx-core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "coreKtx" }
androidx-appcompat = { group = "androidx.appcompat", name = "appcompat", version.ref = "appcompat" }
material = { group = "com.google.android.material", name = "material", version.ref = "material" }
androidx-constraintlayout = { group = "androidx.constraintlayout", name = "constraintlayout", version.ref = "constraintlayout" }
androidx-activity-ktx = { group = "androidx.activity", name = "activity-ktx", version.ref = "activityKtx" }
androidx-fragment-ktx = { group = "androidx.fragment", name = "fragment-ktx", version.ref = "fragmentKtx" }
androidx-lifecycle-runtime-ktx = { group = "androidx.lifecycle", name = "lifecycle-runtime-ktx", version.ref = "lifecycle" }
androidx-lifecycle-service = { group = "androidx.lifecycle", name = "lifecycle-service", version.ref = "lifecycle" }
kotlinx-coroutines-android = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-android", version.ref = "coroutines" }
kotlinx-coroutines-play-services = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-play-services", version.ref = "coroutines" }
firebase-bom = { group = "com.google.firebase", name = "firebase-bom", version.ref = "firebaseBom" }
firebase-auth = { group = "com.google.firebase", name = "firebase-auth" }
firebase-firestore = { group = "com.google.firebase", name = "firebase-firestore" }
play-services-location = { group = "com.google.android.gms", name = "play-services-location", version.ref = "playServicesLocation" }
kakao-map = { group = "com.kakao.maps.open", name = "android", version.ref = "kakaoMap" }
junit = { group = "junit", name = "junit", version.ref = "junit" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
google-services = { id = "com.google.gms.google-services", version.ref = "googleServices" }
```

- [ ] **Step 3: `settings.gradle.kts` 를 쓴다**

카카오 리포지터리를 여기서 선언한다. `RepositoriesMode.FAIL_ON_PROJECT_REPOS`를 쓰므로 모듈에서 따로 못 넣는다.

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://devrepo.kakao.com/nexus/repository/kakaomap-releases/") }
    }
}

rootProject.name = "KidCare"
include(":app")
```

- [ ] **Step 4: `build.gradle.kts`(루트)와 `gradle.properties` 를 쓴다**

`build.gradle.kts`:

```kotlin
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.google.services) apply false
}
```

`gradle.properties`:

```properties
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=MS949
org.gradle.configuration-cache=true
android.useAndroidX=true
kotlin.code.style=official

# file.encoding 이 MS949 인 이유:
# 이 PC 의 사용자 홈이 C:\Users\사용자 (한글) 이라서, Gradle 이 테스트 워커의
# 클래스패스를 argfile 에 UTF-8 로 쓰면 java 런처가 그 파일을 네이티브 인코딩(MS949)
# 으로 읽어 한글이 든 jar 경로가 깨진다. 워커가 ClassNotFoundException 으로 죽는다.
# Kotlin 컴파일러는 소스를 항상 UTF-8 로 읽으므로 한글 주석·문자열에는 영향이 없다.
#
# JDK 경로(org.gradle.java.home)는 여기 적지 않는다. 기계마다 다르므로
# <GRADLE_USER_HOME>/gradle.properties 에 두거나 JAVA_HOME(JDK 17+)에 맡긴다.
```

- [ ] **Step 5: `app/build.gradle.kts` 를 쓴다**

카카오 앱키를 `local.properties`에서 읽어 `BuildConfig`로 넘긴다. 키가 없어도 빌드는 되어야 한다(빈 문자열).

```kotlin
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
}

// 카카오 앱키는 기계마다 다르고 git 에 올리면 안 되므로 local.properties 에서 읽는다.
// 없으면 빈 문자열로 두고, 지도 화면이 "키 설정 필요" 안내를 띄운다. 빌드는 막지 않는다.
val localProps = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
val kakaoAppKey: String = localProps.getProperty("KAKAO_APP_KEY") ?: ""

android {
    namespace = "com.kidcare.family"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.kidcare.family"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        buildConfigField("String", "KAKAO_APP_KEY", "\"$kakaoAppKey\"")
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
    testImplementation(libs.junit)
}
```

- [ ] **Step 6: 매니페스트와 최소 화면을 쓴다**

`app/src/main/AndroidManifest.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.KidCare">

        <activity
            android:name=".RouterActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

> `allowBackup="false"` 인 이유: 구글 자동 백업이 `files/`를 복원하면 앱을 지웠다 깔아도
> 이전 페어링 정보가 되살아나 역할이 꼬인다. 재설치는 깨끗한 상태여야 한다.

`app/src/main/res/values/strings.xml`:

```xml
<resources>
    <string name="app_name">우리아이 지킴이</string>
</resources>
```

`app/src/main/res/values/themes.xml`:

```xml
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.KidCare" parent="Theme.Material3.DayNight.NoActionBar">
        <item name="android:statusBarColor" tools:targetApi="l">?attr/colorSurface</item>
    </style>
</resources>
```

`app/src/main/res/layout/activity_router.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <TextView
        android:id="@+id/status_text"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textAppearance="?attr/textAppearanceHeadlineSmall"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />
</androidx.constraintlayout.widget.ConstraintLayout>
```

`app/src/main/java/com/kidcare/family/RouterActivity.kt`:

```kotlin
package com.kidcare.family

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.databinding.ActivityRouterBinding

/**
 * 런처 액티비티. 저장된 역할에 따라 보호자/자녀 화면으로 보내는 갈림길이다.
 * Task 4 에서 분기 로직이 들어간다. 지금은 뼈대가 도는지만 확인한다.
 */
class RouterActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRouterBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRouterBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.statusText.text = getString(R.string.app_name)
    }
}
```

런처 아이콘은 아직 없으므로 Android Studio 기본 `ic_launcher`를 만들거나, 임시로 매니페스트의 `android:icon` 줄을 지운다. 아이콘 디자인은 7단계에서 한다.

- [ ] **Step 7: 실패하는 스모크 테스트를 쓴다**

한글 홈 환경에서 JVM 테스트 워커가 도는지 **먼저** 확인해야 한다. 여기서 안 돌면 이후 모든 TDD가 막힌다.

`app/src/test/java/com/kidcare/family/logic/SmokeTest.kt`:

```kotlin
package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Test

class SmokeTest {
    @Test
    fun `테스트 워커가 한글 경로에서 살아있다`() {
        assertEquals(4, 2 + 2)
    }
}
```

- [ ] **Step 8: 빌드와 테스트를 돌린다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

기대: 둘 다 `BUILD SUCCESSFUL`.

`ClassNotFoundException: GradleWorkerMain` 이 나면 한글 홈 문제다. **이 순서로** 시도한다:

1. `gradle.properties`의 `-Dfile.encoding=MS949`가 실제로 적용됐는지 확인 (`./gradlew.bat --stop` 후 재시도 — 데몬이 옛 설정으로 살아있을 수 있다)
2. 그래도 죽으면 ASCII Gradle 홈으로:
   ```bash
   GRADLE_USER_HOME=C:/gradle-home ./gradlew.bat :app:testDebugUnitTest
   ```
3. `C:/workAndroid/gradle-user-ascii` 는 **쓰지 않는다.** 한글 홈으로 가는 정션이라 효과가 없다.

어느 방법이 통했는지 `docs/setup.md`에 기록한다:

```markdown
# 개발 환경 메모

## 단위 테스트 실행법
(여기에 Task 1 Step 8 에서 실제로 통한 명령을 적는다)
```

- [ ] **Step 9: 폰에 설치해 확인한다**

```bash
adb install -r /c/workAndroid/KidCare/app/build/outputs/apk/debug/app-debug.apk
```

기대: 앱이 켜지고 가운데에 "우리아이 지킴이"가 보인다.

- [ ] **Step 10: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "뼈대: Gradle 프로젝트 구성과 빈 앱 빌드

AGP 9.2.1 / compileSdk 36 / minSdk 26. Views+ViewBinding.
한글 홈 환경에서 JVM 테스트 워커가 도는 것까지 확인했다."
```

---

### Task 2: 초대 코드 로직 (TDD)

페어링에 쓸 6자리 코드를 만든다. **화면도 Firebase도 없이 순수 계산만** 한다.

혼동하기 쉬운 글자(`0`/`O`, `1`/`I`/`L`)를 뺀 알파벳을 쓴다. 아이가 부모 폰 화면을 보고 손으로 옮겨 적는 코드라 잘못 읽히면 페어링이 실패하고 원인도 안 보인다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/logic/InviteCode.kt`
- Create: `app/src/test/java/com/kidcare/family/logic/InviteCodeTest.kt`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `InviteCode.ALPHABET: String` — 코드에 쓰이는 문자 집합
  - `InviteCode.LENGTH: Int` = 6
  - `InviteCode.generate(random: kotlin.random.Random = Random.Default): String`
  - `InviteCode.normalize(raw: String): String` — 대문자화 + 공백/하이픈 제거 + 헷갈리는 글자 교정
  - `InviteCode.isValid(raw: String): Boolean`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/src/test/java/com/kidcare/family/logic/InviteCodeTest.kt`:

```kotlin
package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class InviteCodeTest {

    @Test
    fun `코드는 6자리다`() {
        assertEquals(6, InviteCode.generate(Random(1)).length)
    }

    @Test
    fun `코드는 헷갈리는 글자를 쓰지 않는다`() {
        // 0/O, 1/I/L 은 손으로 옮겨 적을 때 잘못 읽힌다.
        repeat(500) { seed ->
            val code = InviteCode.generate(Random(seed))
            for (c in code) {
                assertFalse("생성된 코드에 $c 가 들어있다: $code", c in "01OIL")
            }
        }
    }

    @Test
    fun `생성된 코드는 항상 유효하다`() {
        repeat(500) { seed ->
            assertTrue(InviteCode.isValid(InviteCode.generate(Random(seed))))
        }
    }

    @Test
    fun `같은 시드는 같은 코드를 만든다`() {
        assertEquals(InviteCode.generate(Random(42)), InviteCode.generate(Random(42)))
    }

    @Test
    fun `소문자와 공백과 하이픈을 받아준다`() {
        assertEquals("ABC234", InviteCode.normalize(" abc-234 "))
    }

    @Test
    fun `헷갈리는 글자를 교정한다`() {
        // 사용자가 O 를 입력하면 0 이 아니라 알파벳에 있는 글자로 바꿔야 한다.
        // 0 과 O 는 O -> 0 이 아니라 둘 다 알파벳 밖이므로, 가까운 대체를 정해둔다.
        assertEquals("A0BCDE".replace('0', 'Q'), InviteCode.normalize("aObcde"))
        assertEquals("Q23456", InviteCode.normalize("023456"))
        assertEquals("J23456", InviteCode.normalize("I23456"))
        assertEquals("J23456", InviteCode.normalize("l23456"))
    }

    @Test
    fun `길이가 다르면 무효다`() {
        assertFalse(InviteCode.isValid("ABC23"))
        assertFalse(InviteCode.isValid("ABC2345"))
        assertFalse(InviteCode.isValid(""))
    }

    @Test
    fun `알파벳에 없는 글자가 남으면 무효다`() {
        assertFalse(InviteCode.isValid("가나다라마바"))
        assertFalse(InviteCode.isValid("ABC@34"))
    }
}
```

> 여섯 번째 테스트의 `"A0BCDE".replace('0','Q')` 는 기대값이 `"AQBCDE"` 라는 뜻이다.
> 교정 규칙은 `O`/`0` → `Q`, `I`/`L`/`l`/`1` → `J` 로 정한다. 알파벳 안에 있는 글자로
> 보내야 정규화 결과가 항상 유효해진다.

- [ ] **Step 2: 테스트를 돌려 실패를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*InviteCodeTest*"
```

기대: 컴파일 실패 — `Unresolved reference: InviteCode`

- [ ] **Step 3: 최소 구현을 쓴다**

`app/src/main/java/com/kidcare/family/logic/InviteCode.kt`:

```kotlin
package com.kidcare.family.logic

import kotlin.random.Random

/**
 * 페어링용 6자리 초대 코드.
 *
 * 부모 폰 화면에 뜬 코드를 아이가 눈으로 읽어 자기 폰에 옮겨 적는다.
 * 그래서 0/O, 1/I/L 처럼 손글씨·화면에서 헷갈리는 글자를 알파벳에서 빼고,
 * 사용자가 그런 글자를 입력하면 조용히 교정한다.
 *
 * 안드로이드 API 에 의존하지 않는다. JVM 단위 테스트 대상.
 */
object InviteCode {

    /** 0, 1, O, I, L 을 뺀 31글자. */
    const val ALPHABET: String = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

    const val LENGTH: Int = 6

    /** 사용자가 잘못 입력하기 쉬운 글자 → 알파벳 안의 대체 글자. */
    private val CORRECTIONS: Map<Char, Char> = mapOf(
        '0' to 'Q', 'O' to 'Q',
        '1' to 'J', 'I' to 'J', 'L' to 'J',
    )

    fun generate(random: Random = Random.Default): String =
        buildString(LENGTH) {
            repeat(LENGTH) { append(ALPHABET[random.nextInt(ALPHABET.length)]) }
        }

    /** 대문자화 → 공백·하이픈 제거 → 헷갈리는 글자 교정. */
    fun normalize(raw: String): String =
        raw.uppercase()
            .filterNot { it.isWhitespace() || it == '-' }
            .map { CORRECTIONS[it] ?: it }
            .joinToString("")

    fun isValid(raw: String): Boolean {
        val code = normalize(raw)
        return code.length == LENGTH && code.all { it in ALPHABET }
    }
}
```

- [ ] **Step 4: 테스트를 돌려 통과를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*InviteCodeTest*"
```

기대: `BUILD SUCCESSFUL`, 8개 테스트 통과.

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "초대 코드: 6자리 생성·정규화·검증

아이가 눈으로 읽어 옮겨 적는 코드라 0/O, 1/I/L 을 알파벳에서 빼고
입력 시에는 교정한다. 단위 테스트 8개."
```

---

### Task 3: Firebase 익명 로그인

Firebase를 붙이고 **계정 없이** 기기마다 고유 uid를 받는다. 화면에 uid를 찍어 눈으로 확인한다.

**이 작업 전에 `app/google-services.json` 이 있어야 한다.** Step 1에서 발급 절차를 먼저 안내하고 기록한다.

**Files:**
- Create: `docs/setup.md` (Firebase 절 추가 — Task 1에서 만들었으면 이어 쓴다)
- Create: `app/src/main/java/com/kidcare/family/core/AuthGateway.kt`
- Create: `app/src/main/java/com/kidcare/family/KidCareApp.kt`
- Modify: `app/build.gradle.kts` (google-services 플러그인 + Firebase 의존성)
- Modify: `app/src/main/AndroidManifest.xml` (`android:name=".KidCareApp"`)
- Modify: `app/src/main/java/com/kidcare/family/RouterActivity.kt`

**Interfaces:**
- Consumes: `RouterActivity` (Task 1)
- Produces:
  - `AuthGateway.signIn(): String` — suspend. 익명 로그인 후 uid 반환. 이미 로그인돼 있으면 기존 uid.
  - `AuthGateway.currentUid(): String?` — 로그인 안 됐으면 null

- [ ] **Step 1: Firebase 프로젝트를 만들고 절차를 기록한다**

사용자에게 아래를 그대로 안내하고, `docs/setup.md`에 남긴다.

```markdown
## Firebase 설정

1. https://console.firebase.google.com 접속 → `프로젝트 만들기`
2. 프로젝트 이름 `KidCare` → Google 애널리틱스는 `사용 안 함` → 만들기
3. 프로젝트 개요 화면에서 안드로이드 아이콘 클릭
   - Android 패키지 이름: `com.kidcare.family`   ← 정확히 이대로
   - 앱 닉네임: 우리아이 지킴이
   - 디버그 서명 인증서 SHA-1: 지금은 비워둔다 (익명 로그인에는 불필요)
4. `google-services.json` 다운로드 → `C:\workAndroid\KidCare\app\google-services.json` 에 저장
5. 왼쪽 메뉴 `빌드 > Authentication` → `시작하기` → `Sign-in method` 탭
   → `익명` 선택 → `사용 설정` → 저장
6. 왼쪽 메뉴 `빌드 > Firestore Database` → `데이터베이스 만들기`
   - 위치: `asia-northeast3 (서울)`
   - 모드: `프로덕션 모드에서 시작`  (규칙은 Task 6 에서 넣는다)
7. 왼쪽 아래 톱니바퀴 → `사용량 및 결제` → `요금제 수정` → `Blaze` 선택 → 카드 등록
8. 같은 화면에서 `예산 알림 설정` → 1,000원 → 알림 이메일 등록
```

- [ ] **Step 2: Gradle에 Firebase를 붙인다**

`app/build.gradle.kts` 의 `plugins` 블록에 한 줄 추가:

```kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.google.services)
}
```

`dependencies` 블록에 추가:

```kotlin
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.firestore)
    implementation(libs.kotlinx.coroutines.play.services)
```

- [ ] **Step 3: `AuthGateway` 를 쓴다**

`app/src/main/java/com/kidcare/family/core/AuthGateway.kt`:

```kotlin
package com.kidcare.family.core

import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.tasks.await

/**
 * Firebase 익명 로그인 창구.
 *
 * 부모도 아이도 계정을 만들지 않는다. 기기마다 익명 uid 를 하나 받아서
 * 그걸 가족 문서의 멤버 식별자로 쓴다. 앱을 지웠다 깔면 uid 가 바뀌므로
 * 페어링을 다시 해야 한다 — 이건 의도한 동작이다.
 */
object AuthGateway {

    private val auth: FirebaseAuth get() = FirebaseAuth.getInstance()

    fun currentUid(): String? = auth.currentUser?.uid

    /** 이미 로그인돼 있으면 그 uid 를, 아니면 익명 로그인 후 새 uid 를 준다. */
    suspend fun signIn(): String {
        auth.currentUser?.uid?.let { return it }
        val result = auth.signInAnonymously().await()
        return requireNotNull(result.user?.uid) { "익명 로그인은 성공했는데 uid 가 없다" }
    }
}
```

- [ ] **Step 4: Application 클래스와 매니페스트를 잇는다**

`app/src/main/java/com/kidcare/family/KidCareApp.kt`:

```kotlin
package com.kidcare.family

import android.app.Application

/**
 * 앱 진입점. 지금은 비어 있지만 Task 10 에서 카카오 지도 SDK 초기화가 들어간다.
 */
class KidCareApp : Application()
```

`AndroidManifest.xml` 의 `<application>` 여는 태그에 추가:

```xml
        android:name=".KidCareApp"
```

- [ ] **Step 5: `RouterActivity` 에서 로그인하고 uid를 보여준다**

```kotlin
package com.kidcare.family

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.databinding.ActivityRouterBinding
import kotlinx.coroutines.launch

class RouterActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRouterBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRouterBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.statusText.text = getString(R.string.connecting)
        lifecycleScope.launch {
            binding.statusText.text = try {
                getString(R.string.uid_format, AuthGateway.signIn())
            } catch (e: Exception) {
                getString(R.string.connect_failed, e.message ?: "")
            }
        }
    }
}
```

`res/values/strings.xml` 에 추가:

```xml
    <string name="connecting">연결 중…</string>
    <string name="uid_format">내 기기 ID\n%1$s</string>
    <string name="connect_failed">연결 실패\n%1$s</string>
```

- [ ] **Step 6: 폰에서 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk
```

기대: 앱을 켜면 "연결 중…" 이 잠깐 뜨고 `내 기기 ID` 아래에 28자 정도의 문자열이 나온다.
"연결 실패"가 뜨면 `adb logcat -s FirebaseAuth:* KidCare:*` 로 원인을 본다.
Firebase 콘솔의 `Authentication > Users` 에 익명 사용자 1명이 생겼는지도 확인한다.

- [ ] **Step 7: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "Firebase: 익명 로그인 연결

계정 생성 없이 기기마다 uid 를 하나 받는다. google-services.json 은 커밋하지 않는다.
설정 절차는 docs/setup.md 에 기록."
```

---

### Task 4: 역할 선택과 진입 분기

첫 실행 때 보호자/자녀를 고르고, 그 선택을 기기에 저장한다. 다음 실행부터는 `RouterActivity`가 저장된 역할을 보고 알맞은 화면으로 보낸다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/core/Role.kt`
- Create: `app/src/main/java/com/kidcare/family/onboarding/RoleSelectActivity.kt`
- Create: `app/src/main/res/layout/activity_role_select.xml`
- Create: `app/src/main/java/com/kidcare/family/guardian/GuardianMainActivity.kt` (자리만)
- Create: `app/src/main/java/com/kidcare/family/child/ChildHomeActivity.kt` (자리만)
- Create: `app/src/main/res/layout/activity_guardian_main.xml`, `activity_child_home.xml`
- Modify: `RouterActivity.kt`, `AndroidManifest.xml`, `strings.xml`

**Interfaces:**
- Consumes: `AuthGateway.signIn()` (Task 3)
- Produces:
  - `enum class Role { GUARDIAN, CHILD }`
  - `RoleStore(context: Context)` — `var role: Role?`, `var familyId: String?`, `fun clear()`
  - `GuardianMainActivity`, `ChildHomeActivity` — 이후 Task 5·7이 여기서 이어받는다

- [ ] **Step 1: `Role.kt` 를 쓴다**

```kotlin
package com.kidcare.family.core

import android.content.Context

enum class Role { GUARDIAN, CHILD }

/**
 * 이 기기가 보호자인지 자녀인지, 어느 가족에 속하는지를 기기에 저장한다.
 *
 * 페어링이 끝나면 role 과 familyId 가 함께 채워진다. 둘 중 하나라도 비어 있으면
 * 아직 페어링이 안 끝난 것으로 보고 온보딩으로 되돌린다.
 */
class RoleStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare", Context.MODE_PRIVATE)

    var role: Role?
        get() = prefs.getString(KEY_ROLE, null)?.let { runCatching { Role.valueOf(it) }.getOrNull() }
        set(value) = prefs.edit().putString(KEY_ROLE, value?.name).apply()

    var familyId: String?
        get() = prefs.getString(KEY_FAMILY, null)
        set(value) = prefs.edit().putString(KEY_FAMILY, value).apply()

    /** 페어링이 완전히 끝났는가. */
    val isPaired: Boolean get() = role != null && familyId != null

    fun clear() = prefs.edit().clear().apply()

    private companion object {
        const val KEY_ROLE = "role"
        const val KEY_FAMILY = "family_id"
    }
}
```

- [ ] **Step 2: 역할 선택 화면을 쓴다**

`res/layout/activity_role_select.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="32dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginBottom="8dp"
        android:text="@string/role_title"
        android:textAppearance="?attr/textAppearanceHeadlineSmall" />

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginBottom="40dp"
        android:gravity="center"
        android:text="@string/role_subtitle"
        android:textAppearance="?attr/textAppearanceBodyMedium" />

    <com.google.android.material.button.MaterialButton
        android:id="@+id/guardian_button"
        android:layout_width="match_parent"
        android:layout_height="72dp"
        android:layout_marginBottom="16dp"
        android:text="@string/role_guardian" />

    <com.google.android.material.button.MaterialButton
        android:id="@+id/child_button"
        style="@style/Widget.Material3.Button.OutlinedButton"
        android:layout_width="match_parent"
        android:layout_height="72dp"
        android:text="@string/role_child" />
</LinearLayout>
```

`onboarding/RoleSelectActivity.kt`:

```kotlin
package com.kidcare.family.onboarding

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityRoleSelectBinding

/**
 * 첫 실행 화면. 한 번 고르면 페어링이 끝나는 즉시 잠긴다.
 * 바꾸려면 앱 데이터를 지우고 다시 페어링해야 한다.
 */
class RoleSelectActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val binding = ActivityRoleSelectBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val store = RoleStore(this)
        binding.guardianButton.setOnClickListener { choose(store, Role.GUARDIAN) }
        binding.childButton.setOnClickListener { choose(store, Role.CHILD) }
    }

    private fun choose(store: RoleStore, role: Role) {
        store.role = role
        val next = when (role) {
            Role.GUARDIAN -> GuardianPairingActivity::class.java
            Role.CHILD -> ChildPairingActivity::class.java
        }
        startActivity(Intent(this, next))
        finish()
    }
}
```

> `GuardianPairingActivity`·`ChildPairingActivity` 는 Task 5·6에서 만든다.
> 이 Task 안에서는 컴파일을 위해 **빈 액티비티로 먼저 만들어 둔다** (아래 Step 3).

- [ ] **Step 3: 뒤 작업들이 채울 화면의 껍데기를 만든다**

네 개 파일을 만든다. 내용은 모두 같은 꼴이라 하나만 보이고 나머지는 클래스명·레이아웃명만 바꾼다.

`onboarding/GuardianPairingActivity.kt`:

```kotlin
package com.kidcare.family.onboarding

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

/** Task 5 에서 채운다. */
class GuardianPairingActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}
```

같은 방식으로 만든다:
- `onboarding/ChildPairingActivity.kt` — Task 6 에서 채운다
- `guardian/GuardianMainActivity.kt` — Task 10 에서 채운다
- `child/ChildHomeActivity.kt` — Task 7 에서 채운다

- [ ] **Step 4: `RouterActivity` 를 갈림길로 바꾼다**

```kotlin
package com.kidcare.family

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.child.ChildHomeActivity
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityRouterBinding
import com.kidcare.family.guardian.GuardianMainActivity
import com.kidcare.family.onboarding.ChildPairingActivity
import com.kidcare.family.onboarding.GuardianPairingActivity
import com.kidcare.family.onboarding.RoleSelectActivity
import kotlinx.coroutines.launch

/**
 * 런처. 익명 로그인을 끝낸 뒤 저장된 상태에 따라 갈라 보낸다.
 *
 *   역할 없음        → 역할 선택
 *   역할만 있음      → 그 역할의 페어링 화면
 *   역할 + 가족 있음 → 그 역할의 본 화면
 */
class RouterActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val binding = ActivityRouterBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.statusText.text = getString(R.string.connecting)

        lifecycleScope.launch {
            try {
                AuthGateway.signIn()
            } catch (e: Exception) {
                binding.statusText.text = getString(R.string.connect_failed, e.message ?: "")
                return@launch
            }
            startActivity(Intent(this@RouterActivity, destination()))
            finish()
        }
    }

    private fun destination(): Class<*> {
        val store = RoleStore(this)
        return when (store.role) {
            null -> RoleSelectActivity::class.java
            Role.GUARDIAN -> if (store.isPaired) GuardianMainActivity::class.java
                             else GuardianPairingActivity::class.java
            Role.CHILD -> if (store.isPaired) ChildHomeActivity::class.java
                          else ChildPairingActivity::class.java
        }
    }
}
```

- [ ] **Step 5: 매니페스트에 액티비티 5개를 등록한다**

`<application>` 안, `RouterActivity` 뒤에 넣는다.

```xml
        <activity android:name=".onboarding.RoleSelectActivity" android:exported="false" />
        <activity android:name=".onboarding.GuardianPairingActivity" android:exported="false" />
        <activity android:name=".onboarding.ChildPairingActivity" android:exported="false" />
        <activity android:name=".guardian.GuardianMainActivity" android:exported="false" />
        <activity android:name=".child.ChildHomeActivity" android:exported="false" />
```

`strings.xml` 에 추가:

```xml
    <string name="role_title">누구의 폰인가요?</string>
    <string name="role_subtitle">한 번 고르면 연결이 끝난 뒤에는 바꿀 수 없습니다.</string>
    <string name="role_guardian">보호자 (엄마·아빠)</string>
    <string name="role_child">아이</string>
```

- [ ] **Step 6: 폰에서 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk
```

확인 순서:
1. 앱을 켜면 역할 선택 화면이 뜬다
2. `보호자` 를 누르면 빈 화면으로 넘어간다 (Task 5에서 채운다)
3. 앱을 껐다 켜면 **역할 선택을 건너뛰고** 다시 그 빈 화면으로 간다
4. `adb shell pm clear com.kidcare.family` 후 다시 켜면 역할 선택이 다시 나온다

- [ ] **Step 7: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "역할: 보호자/자녀 선택과 진입 분기

RoleStore 가 역할과 가족 ID 를 기기에 저장하고, RouterActivity 가
페어링 여부까지 보고 알맞은 화면으로 보낸다."
```

---

### Task 5: 보호자 페어링 — 가족 만들기와 코드 표시

보호자 폰이 가족 문서를 만들고 6자리 코드를 화면에 띄운다. 아이가 연결되면 화면이 자동으로 넘어간다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/core/model/Documents.kt`
- Create: `app/src/main/java/com/kidcare/family/core/FamilyRepository.kt`
- Modify: `app/src/main/java/com/kidcare/family/onboarding/GuardianPairingActivity.kt`
- Create: `app/src/main/res/layout/activity_guardian_pairing.xml`
- Modify: `strings.xml`

**Interfaces:**
- Consumes: `InviteCode.generate()` (Task 2), `AuthGateway.currentUid()` (Task 3), `RoleStore` (Task 4)
- Produces:
  - `FamilyRepository.createFamily(guardianUid: String): String` — suspend. 가족 문서를 만들고 familyId 반환
  - `FamilyRepository.observeChildJoined(familyId: String, onJoined: (String) -> Unit): ListenerRegistration`
  - `FamilyRepository.inviteCodeOf(familyId: String): String` — suspend
  - 데이터 클래스 `FamilyDoc`, `MemberDoc`, `ChildStatusDoc`, `PointDoc`

- [ ] **Step 1: Firestore 문서 모델을 쓴다**

`core/model/Documents.kt`:

```kotlin
package com.kidcare.family.core.model

/**
 * Firestore 문서와 1:1 로 대응하는 데이터 클래스들.
 *
 * Firestore 의 toObject() 는 인자 없는 생성자를 요구하므로 모든 필드에 기본값을 준다.
 * 시각은 전부 UTC 밀리초다 (설계서 Global Constraints).
 */

data class FamilyDoc(
    val name: String = "",
    val createdAt: Long = 0L,
    val inviteCode: String = "",
    val inviteExpiresAt: Long = 0L,
)

data class MemberDoc(
    val role: String = "",          // "guardian" | "child"
    val displayName: String = "",
    val fcmToken: String = "",
    val appVersion: String = "",
    val updatedAt: Long = 0L,
)

data class ChildStatusDoc(
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val accuracy: Float = 0f,
    val at: Long = 0L,
    val battery: Int = -1,
    val charging: Boolean = false,
    val ringerMode: String = "normal",
    val lastSeenAt: Long = 0L,
)

data class PointDoc(
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val accuracy: Float = 0f,
    val speed: Float = 0f,
    val at: Long = 0L,
    val battery: Int = -1,
)
```

- [ ] **Step 2: `FamilyRepository` 의 보호자 쪽을 쓴다**

`core/FamilyRepository.kt`:

```kotlin
package com.kidcare.family.core

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.core.model.FamilyDoc
import com.kidcare.family.core.model.MemberDoc
import com.kidcare.family.logic.InviteCode
import kotlinx.coroutines.tasks.await

/**
 * 가족 문서 하나가 이 앱의 모든 데이터의 뿌리다.
 *
 *   families/{familyId}
 *     ├ inviteCode, inviteExpiresAt
 *     └ members/{uid}  role = guardian | child
 *
 * 초대 코드는 10분 뒤 만료된다. 아이가 연결되는 즉시 무효화한다.
 */
object FamilyRepository {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private const val INVITE_TTL_MILLIS = 10 * 60 * 1000L

    /** 가족 문서를 만들고 보호자를 첫 멤버로 넣는다. familyId 를 돌려준다. */
    suspend fun createFamily(guardianUid: String): String {
        val now = System.currentTimeMillis()
        val familyRef = db.collection("families").document()
        familyRef.set(
            FamilyDoc(
                name = "우리 가족",
                createdAt = now,
                inviteCode = InviteCode.generate(),
                inviteExpiresAt = now + INVITE_TTL_MILLIS,
            )
        ).await()
        familyRef.collection("members").document(guardianUid).set(
            MemberDoc(role = "guardian", displayName = "보호자", updatedAt = now)
        ).await()
        return familyRef.id
    }

    /** 코드가 만료됐으면 새로 발급하고, 아니면 현재 코드를 준다. */
    suspend fun inviteCodeOf(familyId: String): String {
        val ref = db.collection("families").document(familyId)
        val doc = ref.get().await().toObject(FamilyDoc::class.java)
            ?: error("가족 문서가 없다: $familyId")
        if (doc.inviteExpiresAt > System.currentTimeMillis() && doc.inviteCode.isNotEmpty()) {
            return doc.inviteCode
        }
        val fresh = InviteCode.generate()
        ref.update(
            mapOf(
                "inviteCode" to fresh,
                "inviteExpiresAt" to System.currentTimeMillis() + INVITE_TTL_MILLIS,
            )
        ).await()
        return fresh
    }

    /** 자녀가 members 에 들어오는 순간을 감시한다. 붙인 리스너는 화면이 사라질 때 remove 해야 한다. */
    fun observeChildJoined(familyId: String, onJoined: (childUid: String) -> Unit): ListenerRegistration =
        db.collection("families").document(familyId).collection("members")
            .whereEqualTo("role", "child")
            .addSnapshotListener { snapshot, _ ->
                val childUid = snapshot?.documents?.firstOrNull()?.id ?: return@addSnapshotListener
                onJoined(childUid)
            }
}
```

- [ ] **Step 3: 보호자 페어링 화면을 쓴다**

`res/layout/activity_guardian_pairing.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="32dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/pairing_guardian_title"
        android:textAppearance="?attr/textAppearanceTitleMedium" />

    <TextView
        android:id="@+id/code_text"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="24dp"
        android:letterSpacing="0.3"
        android:textAppearance="?attr/textAppearanceDisplayMedium"
        android:textStyle="bold"
        tools:text="A2C4K9"
        xmlns:tools="http://schemas.android.com/tools" />

    <TextView
        android:id="@+id/hint_text"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="24dp"
        android:gravity="center"
        android:text="@string/pairing_guardian_hint"
        android:textAppearance="?attr/textAppearanceBodyMedium" />

    <ProgressBar
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="32dp" />
</LinearLayout>
```

`onboarding/GuardianPairingActivity.kt`:

```kotlin
package com.kidcare.family.onboarding

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityGuardianPairingBinding
import com.kidcare.family.guardian.GuardianMainActivity
import kotlinx.coroutines.launch

/**
 * 보호자 쪽 페어링. 가족을 만들고 코드를 띄운 뒤, 아이가 들어올 때까지 기다린다.
 *
 * 이미 가족을 만든 뒤 앱을 껐다 켠 경우에는 새로 만들지 않고 기존 가족의 코드를 다시 띄운다.
 * (RoleStore.familyId 가 남아 있으면 그것을 쓴다)
 */
class GuardianPairingActivity : AppCompatActivity() {

    private lateinit var binding: ActivityGuardianPairingBinding
    private var listener: ListenerRegistration? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityGuardianPairingBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val store = RoleStore(this)
        lifecycleScope.launch {
            try {
                val uid = AuthGateway.signIn()
                val familyId = store.familyId ?: FamilyRepository.createFamily(uid).also {
                    store.familyId = it
                }
                binding.codeText.text = FamilyRepository.inviteCodeOf(familyId)
                listener = FamilyRepository.observeChildJoined(familyId) { goToMain() }
            } catch (e: Exception) {
                binding.hintText.text = getString(R.string.pairing_failed, e.message ?: "")
            }
        }
    }

    private fun goToMain() {
        listener?.remove()
        listener = null
        startActivity(Intent(this, GuardianMainActivity::class.java))
        finish()
    }

    override fun onDestroy() {
        listener?.remove()
        super.onDestroy()
    }
}
```

`strings.xml` 에 추가:

```xml
    <string name="pairing_guardian_title">아이 폰에 이 번호를 입력하세요</string>
    <string name="pairing_guardian_hint">아이 폰에서 앱을 켜고\n\'아이\'를 고른 뒤 이 번호를 넣으면 연결됩니다.</string>
    <string name="pairing_failed">연결 실패\n%1$s</string>
```

- [ ] **Step 4: 임시로 규칙을 열고 확인한다**

Firestore 보안 규칙은 Task 6에서 제대로 넣는다. 지금은 **테스트 모드**로 잠깐 열어 동작만 본다.
Firebase 콘솔 `Firestore Database > 규칙` 에 붙여넣고 `게시`:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 임시. Task 6 에서 반드시 교체한다.
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

- [ ] **Step 5: 폰에서 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk
```

확인:
1. `adb shell pm clear com.kidcare.family` 후 앱 실행 → 역할 선택 → `보호자`
2. 6자리 코드가 크게 뜬다. `0`, `1`, `O`, `I`, `L` 이 없는지 눈으로 본다
3. Firebase 콘솔 `Firestore Database` 에 `families/{임의ID}` 문서와 `members/{uid}` 하위 문서가 보인다
4. 앱을 껐다 켜면 **같은 코드**가 다시 뜬다 (10분 안이면)

- [ ] **Step 6: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "페어링(보호자): 가족 생성과 초대 코드 표시

가족 문서를 만들고 10분짜리 코드를 띄운 뒤 자녀가 들어오는 것을 구독한다.
앱을 껐다 켜도 같은 가족을 이어받는다."
```

---

### Task 6: 자녀 페어링 — 코드 입력과 보안 규칙

아이 폰이 코드를 입력해 가족에 들어간다. 그리고 **임시로 열어둔 보안 규칙을 제대로 잠근다.**

**Files:**
- Modify: `app/src/main/java/com/kidcare/family/core/FamilyRepository.kt` (`joinFamily` 추가)
- Modify: `app/src/main/java/com/kidcare/family/onboarding/ChildPairingActivity.kt`
- Create: `app/src/main/res/layout/activity_child_pairing.xml`
- Create: `firestore.rules` (저장소에 규칙 원본을 보관 — 콘솔에 붙여넣기용)
- Modify: `strings.xml`, `docs/setup.md`

**Interfaces:**
- Consumes: `InviteCode.normalize/isValid` (Task 2), `FamilyRepository.createFamily` (Task 5), `RoleStore` (Task 4)
- Produces:
  - `FamilyRepository.joinFamily(code: String, childUid: String): String` — suspend. 성공 시 familyId, 실패 시 `PairingException`
  - `class PairingException(val reason: Reason) : Exception()` with `Reason { NOT_FOUND, EXPIRED, ALREADY_FULL }`

- [ ] **Step 1: `joinFamily` 를 `FamilyRepository` 에 추가한다**

`FamilyRepository.kt` 의 `observeChildJoined` 아래에 붙인다.

```kotlin
    /**
     * 코드로 가족을 찾아 자녀로 들어간다.
     *
     * 코드는 families 컬렉션 전체에서 찾는다. 6자리 31진수라 충돌 확률이 낮고,
     * 만료된 코드는 걸러내므로 같은 코드가 동시에 두 가족에 살아있을 일은 사실상 없다.
     * 그래도 여러 개가 나오면 만료가 가장 늦은 것을 고른다.
     */
    suspend fun joinFamily(code: String, childUid: String): String {
        val normalized = InviteCode.normalize(code)
        val now = System.currentTimeMillis()

        val matches = db.collection("families")
            .whereEqualTo("inviteCode", normalized)
            .get().await()

        if (matches.isEmpty) throw PairingException(PairingException.Reason.NOT_FOUND)

        val alive = matches.documents
            .filter { (it.getLong("inviteExpiresAt") ?: 0L) > now }
            .maxByOrNull { it.getLong("inviteExpiresAt") ?: 0L }
            ?: throw PairingException(PairingException.Reason.EXPIRED)

        val familyRef = alive.reference
        val existingChildren = familyRef.collection("members")
            .whereEqualTo("role", "child").get().await()
        if (existingChildren.documents.any { it.id != childUid }) {
            throw PairingException(PairingException.Reason.ALREADY_FULL)
        }

        familyRef.collection("members").document(childUid).set(
            MemberDoc(role = "child", displayName = "아이", updatedAt = now)
        ).await()

        // 코드를 즉시 무효화한다. 한 번 쓴 코드가 계속 살아 있으면 안 된다.
        familyRef.update("inviteExpiresAt", 0L).await()

        return familyRef.id
    }
```

`FamilyRepository.kt` 파일 맨 아래(object 밖)에 예외 클래스를 둔다:

```kotlin
class PairingException(val reason: Reason) : Exception(reason.name) {
    enum class Reason { NOT_FOUND, EXPIRED, ALREADY_FULL }
}
```

`import com.kidcare.family.logic.InviteCode` 는 이미 있다.

- [ ] **Step 2: 자녀 페어링 화면을 쓴다**

`res/layout/activity_child_pairing.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="32dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginBottom="24dp"
        android:gravity="center"
        android:text="@string/pairing_child_title"
        android:textAppearance="?attr/textAppearanceTitleMedium" />

    <com.google.android.material.textfield.TextInputLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content">

        <com.google.android.material.textfield.TextInputEditText
            android:id="@+id/code_input"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="@string/pairing_child_hint"
            android:inputType="textCapCharacters"
            android:maxLength="8"
            android:letterSpacing="0.2"
            android:textAppearance="?attr/textAppearanceHeadlineMedium" />
    </com.google.android.material.textfield.TextInputLayout>

    <TextView
        android:id="@+id/error_text"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="12dp"
        android:gravity="center"
        android:textColor="?attr/colorError"
        android:visibility="gone" />

    <com.google.android.material.button.MaterialButton
        android:id="@+id/join_button"
        android:layout_width="match_parent"
        android:layout_height="64dp"
        android:layout_marginTop="24dp"
        android:enabled="false"
        android:text="@string/pairing_child_join" />
</LinearLayout>
```

`onboarding/ChildPairingActivity.kt`:

```kotlin
package com.kidcare.family.onboarding

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.PairingException
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityChildPairingBinding
import com.kidcare.family.logic.InviteCode
import kotlinx.coroutines.launch

/**
 * 아이 쪽 페어링. 코드가 6자리로 유효해질 때만 버튼이 켜진다.
 * 성공하면 권한 온보딩으로 넘어간다 (Task 7 에서 PermissionActivity 로 바꾼다).
 */
class ChildPairingActivity : AppCompatActivity() {

    private lateinit var binding: ActivityChildPairingBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityChildPairingBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.codeInput.doAfterTextChanged { text ->
            binding.joinButton.isEnabled = InviteCode.isValid(text?.toString().orEmpty())
            binding.errorText.visibility = View.GONE
        }
        binding.joinButton.setOnClickListener { join() }
    }

    private fun join() {
        val code = binding.codeInput.text?.toString().orEmpty()
        binding.joinButton.isEnabled = false
        lifecycleScope.launch {
            try {
                val uid = AuthGateway.signIn()
                val familyId = FamilyRepository.joinFamily(code, uid)
                RoleStore(this@ChildPairingActivity).familyId = familyId
                startActivity(Intent(this@ChildPairingActivity, PermissionActivity::class.java))
                finish()
            } catch (e: PairingException) {
                showError(
                    when (e.reason) {
                        PairingException.Reason.NOT_FOUND -> getString(R.string.pairing_not_found)
                        PairingException.Reason.EXPIRED -> getString(R.string.pairing_expired)
                        PairingException.Reason.ALREADY_FULL -> getString(R.string.pairing_full)
                    }
                )
            } catch (e: Exception) {
                showError(getString(R.string.pairing_failed, e.message ?: ""))
            }
        }
    }

    private fun showError(message: String) {
        binding.errorText.text = message
        binding.errorText.visibility = View.VISIBLE
        binding.joinButton.isEnabled = true
    }
}
```

> `PermissionActivity` 는 Task 7에서 만든다. 이 Task에서는 컴파일을 위해
> `onboarding/PermissionActivity.kt` 를 Task 4 Step 3과 같은 빈 액티비티 꼴로 만들고
> 매니페스트에 `<activity android:name=".onboarding.PermissionActivity" android:exported="false" />` 를 등록한다.

`strings.xml` 에 추가:

```xml
    <string name="pairing_child_title">엄마 폰에 뜬\n6자리 번호를 넣어주세요</string>
    <string name="pairing_child_hint">번호 6자리</string>
    <string name="pairing_child_join">연결하기</string>
    <string name="pairing_not_found">그런 번호가 없어요. 다시 확인해 주세요.</string>
    <string name="pairing_expired">번호가 만료됐어요. 엄마 폰에서 새 번호를 받아주세요.</string>
    <string name="pairing_full">이미 다른 폰이 연결돼 있어요.</string>
```

- [ ] **Step 3: 보안 규칙을 제대로 쓴다**

`firestore.rules` (저장소에 원본을 둬서 나중에 뭘 올렸는지 알 수 있게 한다):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    // 이 사용자가 해당 가족의 멤버인가
    function memberOf(familyId) {
      return signedIn() && exists(
        /databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)
      );
    }

    function roleIn(familyId) {
      return get(
        /databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)
      ).data.role;
    }

    match /families/{familyId} {
      // 페어링 전에는 멤버가 아니므로 코드로 찾는 조회를 허용해야 한다.
      // 대신 문서 전체가 아니라 목록 조회만 열고, 쓰기는 멤버로 제한한다.
      allow read: if signedIn();
      allow create: if signedIn();
      allow update: if memberOf(familyId);
      allow delete: if false;

      match /members/{uid} {
        // 자기 자신의 멤버 문서는 만들 수 있다 (= 페어링).
        allow read: if memberOf(familyId);
        allow create: if signedIn() && request.auth.uid == uid;
        allow update: if signedIn() && request.auth.uid == uid;
        allow delete: if memberOf(familyId) && roleIn(familyId) == 'guardian';
      }

      match /children/{childUid}/{document=**} {
        allow read: if memberOf(familyId);
        // 아이는 자기 아래에만 쓴다.
        allow write: if memberOf(familyId) && request.auth.uid == childUid;
      }

      match /places/{id} {
        allow read: if memberOf(familyId);
        allow write: if memberOf(familyId) && roleIn(familyId) == 'guardian';
      }

      match /schedules/{id} {
        allow read: if memberOf(familyId);
        allow write: if memberOf(familyId) && roleIn(familyId) == 'guardian';
      }

      match /events/{id} {
        allow read: if memberOf(familyId);
        allow create: if memberOf(familyId);
        allow update, delete: if memberOf(familyId) && roleIn(familyId) == 'guardian';
      }
    }
  }
}
```

> **여기서 명령(`commands/`)은 `children/{childUid}/**` 규칙에 걸려 자녀만 쓰게 된다.**
> 보호자가 명령을 쓸 수 있어야 하므로 4단계(즉시 변경·폰찾기)에서 `commands` 전용 규칙을
> 따로 파서 이 규칙을 고쳐야 한다. 4단계 계획에 이 항목을 반드시 넣는다.

Firebase 콘솔 `Firestore Database > 규칙` 에 이 내용을 붙여넣고 `게시`한다.
`docs/setup.md` 에 "규칙 원본은 저장소의 `firestore.rules` 다. 콘솔에 붙여넣어 게시한다"고 적는다.

- [ ] **Step 4: 폰 두 대로 확인한다** (이 계획에서 가장 중요한 확인 지점)

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug
adb devices    # 두 대가 다 보이는지 확인
adb -s <엄마폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

확인 순서:
1. 두 폰 다 `adb -s <시리얼> shell pm clear com.kidcare.family`
2. 엄마폰: 앱 실행 → `보호자` → 코드 확인
3. 아이폰: 앱 실행 → `아이` → 그 코드 입력 → `연결하기`
4. **엄마폰 화면이 자동으로 넘어간다** (빈 GuardianMainActivity)
5. 아이폰은 빈 PermissionActivity로 간다
6. Firebase 콘솔에서 `families/{id}/members` 에 문서 2개(guardian, child)를 확인
7. 아이폰에서 앱을 껐다 켜면 페어링 화면을 건너뛴다

실패 케이스도 본다:
8. 아이폰 `pm clear` 후 없는 코드 `ZZZZZZ` 입력 → "그런 번호가 없어요"
9. 엄마폰에서 방금 쓴 코드를 다시 입력 → "번호가 만료됐어요" (한 번 쓴 코드는 무효)

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "페어링(자녀)과 Firestore 보안 규칙

코드 입력으로 가족에 들어가고, 쓴 코드는 즉시 무효화한다.
규칙은 같은 가족 멤버만 접근하도록 잠갔다. 규칙 원본은 firestore.rules."
```

---

### Task 7: 자녀 권한 온보딩

위치 수집에 필요한 권한을 한 장씩 설명하고 받는다. **위치 수집보다 먼저** 만드는 이유는, 권한 없이 서비스를 띄우면 조용히 아무 데이터도 안 올라오는데 원인이 안 보이기 때문이다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/onboarding/PermissionStep.kt`
- Modify: `app/src/main/java/com/kidcare/family/onboarding/PermissionActivity.kt`
- Create: `app/src/main/res/layout/activity_permission.xml`, `res/layout/item_permission.xml`
- Modify: `app/src/main/java/com/kidcare/family/child/ChildHomeActivity.kt`
- Create: `app/src/main/res/layout/activity_child_home.xml`
- Modify: `AndroidManifest.xml`, `strings.xml`

**Interfaces:**
- Consumes: `RoleStore` (Task 4)
- Produces:
  - `enum class PermissionStep` — `LOCATION_FINE`, `LOCATION_BACKGROUND`, `NOTIFICATION`, `BATTERY_UNRESTRICTED`
  - `PermissionStep.isGranted(context: Context): Boolean`
  - `PermissionStep.titleRes: Int`, `PermissionStep.reasonRes: Int`
  - `PermissionActivity` — 모든 단계가 끝나면 `ChildHomeActivity` 로 보낸다

> 방해금지 접근(DND)과 정확한 알람은 4·5단계에서 필요해질 때 추가한다. 지금 다 받으면
> 아이가 이유를 모르는 권한 창을 연달아 만나고, 하나 거부하면 온보딩이 막힌다.

- [ ] **Step 1: 매니페스트에 권한을 선언한다**

`<manifest>` 바로 아래, 기존 `INTERNET` 옆에 추가:

```xml
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

- [ ] **Step 2: `PermissionStep` 을 쓴다**

`onboarding/PermissionStep.kt`:

```kotlin
package com.kidcare.family.onboarding

import android.Manifest
import android.content.Context
import android.os.Build
import android.os.PowerManager
import androidx.core.content.ContextCompat
import com.kidcare.family.R

/**
 * 자녀 폰이 받아야 하는 권한들. 순서가 중요하다.
 *
 * 안드로이드 11 부터 '항상 허용'은 앱에서 바로 못 받는다. 먼저 '앱 사용 중 허용'을
 * 받은 뒤에야 시스템 설정으로 보낼 수 있다. 그래서 FINE 이 BACKGROUND 보다 앞에 있다.
 */
enum class PermissionStep(val titleRes: Int, val reasonRes: Int) {

    LOCATION_FINE(R.string.perm_location_title, R.string.perm_location_reason) {
        override fun isGranted(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
    },

    LOCATION_BACKGROUND(R.string.perm_background_title, R.string.perm_background_reason) {
        override fun isGranted(context: Context): Boolean =
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) true
            else ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    },

    NOTIFICATION(R.string.perm_notification_title, R.string.perm_notification_reason) {
        override fun isGranted(context: Context): Boolean =
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) true
            else ContextCompat.checkSelfPermission(
                context, Manifest.permission.POST_NOTIFICATIONS
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    },

    BATTERY_UNRESTRICTED(R.string.perm_battery_title, R.string.perm_battery_reason) {
        override fun isGranted(context: Context): Boolean {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(context.packageName)
        }
    };

    abstract fun isGranted(context: Context): Boolean

    companion object {
        /** 아직 안 받은 첫 번째 단계. 전부 받았으면 null. */
        fun firstMissing(context: Context): PermissionStep? =
            entries.firstOrNull { !it.isGranted(context) }
    }
}
```

`strings.xml` 에 추가:

```xml
    <string name="perm_title">몇 가지만 켜주세요</string>
    <string name="perm_location_title">위치 권한</string>
    <string name="perm_location_reason">지금 어디 있는지 부모님께 알려주기 위해 필요해요.</string>
    <string name="perm_background_title">위치 \'항상 허용\'</string>
    <string name="perm_background_reason">앱을 안 보고 있을 때도 위치를 보내려면 \'항상 허용\'이어야 해요. 설정 화면에서 \'항상 허용\'을 골라주세요.</string>
    <string name="perm_notification_title">알림</string>
    <string name="perm_notification_reason">부모님이 보낸 메시지를 받고, 위치 공유 중이라는 표시를 띄우기 위해 필요해요.</string>
    <string name="perm_battery_title">배터리 최적화 제외</string>
    <string name="perm_battery_reason">이걸 안 켜면 폰이 앱을 잠재워서 위치가 끊겨요. 설정 화면에서 \'허용\'을 골라주세요.</string>
    <string name="perm_grant">켜기</string>
    <string name="perm_done">모두 켜졌어요. 시작할게요!</string>
    <string name="perm_start">시작하기</string>
</resources>
```

- [ ] **Step 3: 권한 화면을 쓴다**

`res/layout/activity_permission.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="32dp">

    <TextView
        android:id="@+id/step_title"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textAppearance="?attr/textAppearanceHeadlineSmall" />

    <TextView
        android:id="@+id/step_reason"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:gravity="center"
        android:textAppearance="?attr/textAppearanceBodyLarge" />

    <com.google.android.material.button.MaterialButton
        android:id="@+id/grant_button"
        android:layout_width="match_parent"
        android:layout_height="64dp"
        android:layout_marginTop="40dp"
        android:text="@string/perm_grant" />
</LinearLayout>
```

`onboarding/PermissionActivity.kt`:

```kotlin
package com.kidcare.family.onboarding

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.R
import com.kidcare.family.child.ChildHomeActivity
import com.kidcare.family.databinding.ActivityPermissionBinding

/**
 * 자녀 폰 권한 온보딩. 한 번에 하나씩만 보여주고, 받을 때까지 다음으로 안 넘어간다.
 *
 * 화면에 돌아올 때마다(onResume) 다시 검사하므로, 설정 앱에 다녀오면 자동으로 다음 단계가 뜬다.
 */
class PermissionActivity : AppCompatActivity() {

    private lateinit var binding: ActivityPermissionBinding

    private val requestPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { render() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPermissionBinding.inflate(layoutInflater)
        setContentView(binding.root)
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    private fun render() {
        val step = PermissionStep.firstMissing(this)
        if (step == null) {
            startActivity(Intent(this, ChildHomeActivity::class.java))
            finish()
            return
        }
        binding.stepTitle.setText(step.titleRes)
        binding.stepReason.setText(step.reasonRes)
        binding.grantButton.setOnClickListener { ask(step) }
    }

    private fun ask(step: PermissionStep) {
        when (step) {
            PermissionStep.LOCATION_FINE ->
                requestPermission.launch(Manifest.permission.ACCESS_FINE_LOCATION)

            PermissionStep.LOCATION_BACKGROUND ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // 안드로이드 11+ 는 시스템 설정에서만 '항상 허용'을 고를 수 있다.
                    openAppSettings()
                } else {
                    requestPermission.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                }

            PermissionStep.NOTIFICATION ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    requestPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                }

            PermissionStep.BATTERY_UNRESTRICTED ->
                startActivity(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                )
        }
    }

    private fun openAppSettings() {
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null)
            )
        )
    }
}
```

> `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 대신 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`
> (목록 화면)을 쓴다. 전자는 구글 플레이 정책상 특정 앱만 쓸 수 있고 심사에서 문제가 되는데,
> 사이드로드라도 동작이 기기마다 다르다. 목록 화면은 어디서나 열린다.

- [ ] **Step 4: 아이가 보는 홈 화면을 만든다**

`res/layout/activity_child_home.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="32dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/child_home_title"
        android:textAppearance="?attr/textAppearanceHeadlineSmall" />

    <TextView
        android:id="@+id/child_status"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="24dp"
        android:gravity="center"
        android:textAppearance="?attr/textAppearanceBodyMedium" />
</LinearLayout>
```

`child/ChildHomeActivity.kt`:

```kotlin
package com.kidcare.family.child

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.databinding.ActivityChildHomeBinding
import com.kidcare.family.onboarding.PermissionStep

/**
 * 아이가 보는 화면. 몰래 감시하지 않는다는 원칙에 따라
 * "지금 위치를 부모님과 공유 중"이라는 사실을 숨기지 않고 보여준다.
 *
 * Task 9 에서 여기서 TrackingService 를 시작한다.
 */
class ChildHomeActivity : AppCompatActivity() {

    private lateinit var binding: ActivityChildHomeBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityChildHomeBinding.inflate(layoutInflater)
        setContentView(binding.root)
    }

    override fun onResume() {
        super.onResume()
        val missing = PermissionStep.firstMissing(this)
        binding.childStatus.text = if (missing == null) {
            getString(R.string.child_sharing_on)
        } else {
            getString(R.string.child_permission_missing, getString(missing.titleRes))
        }
    }
}
```

`strings.xml` 에 추가:

```xml
    <string name="child_home_title">위치 공유 중</string>
    <string name="child_sharing_on">지금 내 위치가 부모님께 공유되고 있어요.</string>
    <string name="child_permission_missing">%1$s 이(가) 꺼져 있어요.\n켜야 위치가 전달됩니다.</string>
```

`ChildHomeActivity.kt` 에 `import com.kidcare.family.R` 을 추가한다.

- [ ] **Step 5: 아이폰에서 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug && adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

확인:
1. `pm clear` 후 아이 역할로 페어링 → 권한 화면이 나온다
2. `위치 권한` → 켜기 → 시스템 창에서 허용 → 화면이 `위치 '항상 허용'` 로 바뀐다
3. `켜기` → 설정 앱이 열림 → 권한 > 위치 > `항상 허용` 선택 → 뒤로 → 화면이 `알림` 으로 바뀐다
4. 알림 허용 → `배터리 최적화 제외` → 목록에서 `우리아이 지킴이` 를 `제한 없음`으로
5. 뒤로 오면 "위치 공유 중" 화면이 뜬다
6. 앱을 껐다 켜면 바로 "위치 공유 중" 화면으로 간다

**삼성 기기라면** 추가로 `설정 > 배터리 > 백그라운드 사용 제한 > 절전 앱`에서 제외한다.
이건 표준 API로 확인할 수 없으므로 `docs/setup.md` 에 수동 절차로 적는다.

- [ ] **Step 6: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "자녀 권한 온보딩

위치·항상허용·알림·배터리최적화를 한 장씩 이유와 함께 안내한다.
안드로이드 11+ 는 '항상 허용'을 앱에서 못 받으므로 설정으로 보낸다."
```

---

### Task 8: 위치 필터 로직 (TDD)

받은 위치를 올릴지 말지 판정하는 순수 계산. **서비스를 만들기 전에** 여기부터 테스트로 고정한다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/logic/LocationFilter.kt`
- Create: `app/src/test/java/com/kidcare/family/logic/LocationFilterTest.kt`

**Interfaces:**
- Consumes: 없음 (순수 로직)
- Produces:
  - `data class Fix(val lat: Double, val lng: Double, val accuracy: Float, val at: Long)`
  - `LocationFilter.MAX_ACCURACY_METERS = 100f`
  - `LocationFilter.MIN_MOVE_METERS = 50.0`
  - `LocationFilter.MAX_SPEED_MPS = 55.6` (시속 200km)
  - `LocationFilter.HEARTBEAT_MILLIS = 10 * 60 * 1000L`
  - `LocationFilter.decide(previous: Fix?, candidate: Fix): Decision`
  - `enum class Decision { UPLOAD, SKIP_TOO_CLOSE, REJECT_INACCURATE, REJECT_IMPOSSIBLE }`
  - `LocationFilter.distanceMeters(a: Fix, b: Fix): Double` — 하버사인

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/src/test/java/com/kidcare/family/logic/LocationFilterTest.kt`:

```kotlin
package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocationFilterTest {

    private val seoulCityHall = Fix(37.5665, 126.9780, accuracy = 10f, at = 1_000_000L)

    private fun near(meters: Double, afterMillis: Long, accuracy: Float = 10f): Fix {
        // 위도 1도 = 약 111,320m. 북쪽으로 meters 만큼 옮긴다.
        return Fix(
            lat = seoulCityHall.lat + meters / 111_320.0,
            lng = seoulCityHall.lng,
            accuracy = accuracy,
            at = seoulCityHall.at + afterMillis,
        )
    }

    @Test
    fun `첫 위치는 무조건 올린다`() {
        assertEquals(Decision.UPLOAD, LocationFilter.decide(null, seoulCityHall))
    }

    @Test
    fun `정확도가 나쁘면 버린다`() {
        val bad = seoulCityHall.copy(accuracy = 150f)
        assertEquals(Decision.REJECT_INACCURATE, LocationFilter.decide(null, bad))
    }

    @Test
    fun `정확도 100m 는 경계값으로 받아들인다`() {
        val edge = seoulCityHall.copy(accuracy = 100f)
        assertEquals(Decision.UPLOAD, LocationFilter.decide(null, edge))
    }

    @Test
    fun `50m 안 움직였으면 건너뛴다`() {
        val barelyMoved = near(meters = 30.0, afterMillis = 60_000L)
        assertEquals(Decision.SKIP_TOO_CLOSE, LocationFilter.decide(seoulCityHall, barelyMoved))
    }

    @Test
    fun `50m 넘게 움직이면 올린다`() {
        val moved = near(meters = 80.0, afterMillis = 60_000L)
        assertEquals(Decision.UPLOAD, LocationFilter.decide(seoulCityHall, moved))
    }

    @Test
    fun `안 움직여도 10분이 지나면 살아있다고 한 번 올린다`() {
        val stillThere = near(meters = 5.0, afterMillis = 10 * 60 * 1000L)
        assertEquals(Decision.UPLOAD, LocationFilter.decide(seoulCityHall, stillThere))
    }

    @Test
    fun `시속 200km 를 넘는 이동은 GPS 오류로 보고 버린다`() {
        // 1초 만에 1km 이동 = 시속 3600km
        val teleport = near(meters = 1000.0, afterMillis = 1000L)
        assertEquals(Decision.REJECT_IMPOSSIBLE, LocationFilter.decide(seoulCityHall, teleport))
    }

    @Test
    fun `시간이 거꾸로 간 위치는 버린다`() {
        val past = near(meters = 500.0, afterMillis = -60_000L)
        assertEquals(Decision.REJECT_IMPOSSIBLE, LocationFilter.decide(seoulCityHall, past))
    }

    @Test
    fun `하버사인 거리가 실제와 비슷하다`() {
        // 서울시청 → 광화문, 약 800m
        val gwanghwamun = Fix(37.5759, 126.9769, 10f, 2_000_000L)
        val d = LocationFilter.distanceMeters(seoulCityHall, gwanghwamun)
        assertTrue("계산된 거리가 $d m 로 예상 범위(900~1100m)를 벗어났다", d in 900.0..1100.0)
    }
}
```

- [ ] **Step 2: 테스트를 돌려 실패를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*LocationFilterTest*"
```

기대: 컴파일 실패 — `Unresolved reference: Fix`, `LocationFilter`, `Decision`

- [ ] **Step 3: 최소 구현을 쓴다**

`app/src/main/java/com/kidcare/family/logic/LocationFilter.kt`:

```kotlin
package com.kidcare.family.logic

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** 위치 한 점. 안드로이드 Location 에 의존하지 않는 값 객체다. */
data class Fix(
    val lat: Double,
    val lng: Double,
    val accuracy: Float,
    val at: Long,
)

enum class Decision {
    /** Firestore 에 올린다. */
    UPLOAD,
    /** 거의 안 움직였다. 배터리·통신량을 아끼려고 건너뛴다. */
    SKIP_TOO_CLOSE,
    /** 오차가 너무 커서 못 믿는다. */
    REJECT_INACCURATE,
    /** 물리적으로 불가능한 이동. GPS 오류다. */
    REJECT_IMPOSSIBLE,
}

/**
 * 받은 위치를 올릴지 말지 판정한다.
 *
 * 순서가 중요하다: 못 믿을 점(정확도·순간이동)을 먼저 버리고, 남은 것 중에서
 * 안 움직인 것을 건너뛴다. 반대 순서면 튄 좌표가 '많이 움직였다'로 통과해 버린다.
 */
object LocationFilter {

    /** 이보다 오차가 크면 버린다. 설계서 4.1 */
    const val MAX_ACCURACY_METERS: Float = 100f

    /** 이만큼 안 움직였으면 안 올린다. 설계서 4.1 */
    const val MIN_MOVE_METERS: Double = 50.0

    /** 시속 200km. 이보다 빠르면 GPS 오류로 본다. */
    const val MAX_SPEED_MPS: Double = 55.6

    /** 안 움직여도 이 시간이 지나면 살아있다는 뜻으로 한 번 올린다. */
    const val HEARTBEAT_MILLIS: Long = 10 * 60 * 1000L

    private const val EARTH_RADIUS_METERS = 6_371_000.0

    fun decide(previous: Fix?, candidate: Fix): Decision {
        if (candidate.accuracy > MAX_ACCURACY_METERS) return Decision.REJECT_INACCURATE
        if (previous == null) return Decision.UPLOAD

        val elapsed = candidate.at - previous.at
        if (elapsed <= 0L) return Decision.REJECT_IMPOSSIBLE

        val distance = distanceMeters(previous, candidate)
        if (distance / (elapsed / 1000.0) > MAX_SPEED_MPS) return Decision.REJECT_IMPOSSIBLE

        if (distance >= MIN_MOVE_METERS) return Decision.UPLOAD
        if (elapsed >= HEARTBEAT_MILLIS) return Decision.UPLOAD
        return Decision.SKIP_TOO_CLOSE
    }

    /** 하버사인 거리(m). */
    fun distanceMeters(a: Fix, b: Fix): Double {
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLng = Math.toRadians(b.lng - a.lng)
        val h = sin(dLat / 2).pow(2) +
            cos(Math.toRadians(a.lat)) * cos(Math.toRadians(b.lat)) * sin(dLng / 2).pow(2)
        return 2 * EARTH_RADIUS_METERS * asin(sqrt(h))
    }
}
```

- [ ] **Step 4: 테스트를 돌려 통과를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*LocationFilterTest*"
```

기대: `BUILD SUCCESSFUL`, 9개 테스트 통과.

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "위치 필터: 올릴 위치인지 판정하는 순수 로직

정확도 100m 초과·시속 200km 초과·시간 역행을 먼저 버리고,
남은 것 중 50m 미만 이동을 건너뛴다. 10분마다는 무조건 한 번 올린다.
단위 테스트 9개."
```

---

### Task 9: 위치 수집 포그라운드 서비스

아이 폰에서 상시 도는 서비스를 만들어 위치를 Firestore에 올린다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/child/LocationCollector.kt`
- Create: `app/src/main/java/com/kidcare/family/child/StatusReporter.kt`
- Create: `app/src/main/java/com/kidcare/family/child/TrackingService.kt`
- Create: `app/src/main/java/com/kidcare/family/child/BootReceiver.kt`
- Modify: `app/build.gradle.kts` (play-services-location, lifecycle-service)
- Modify: `AndroidManifest.xml`, `strings.xml`
- Modify: `app/src/main/java/com/kidcare/family/child/ChildHomeActivity.kt`

**Interfaces:**
- Consumes: `LocationFilter.decide`, `Fix`, `Decision` (Task 8), `RoleStore` (Task 4), `PointDoc`/`ChildStatusDoc` (Task 5)
- Produces:
  - `TrackingService.start(context: Context)` — companion. 서비스를 포그라운드로 띄운다
  - `StatusReporter.report(familyId: String, childUid: String, fix: Fix, battery: Int, charging: Boolean)` — suspend

- [ ] **Step 1: 의존성을 추가한다**

`app/build.gradle.kts` 의 `dependencies` 에 추가:

```kotlin
    implementation(libs.play.services.location)
    implementation(libs.androidx.lifecycle.service)
```

- [ ] **Step 2: `LocationCollector` 를 쓴다**

```kotlin
package com.kidcare.family.child

import android.annotation.SuppressLint
import android.content.Context
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.kidcare.family.logic.Fix

/**
 * FusedLocationProvider 래퍼.
 *
 * 1단계에서는 고정 주기(1분, 고정밀)로만 받는다. 설계서 4.1 의 '정지/이동에 따른
 * 주기 전환'은 ActivityRecognition 이 필요한데, 그건 위치가 제대로 올라오는 것을
 * 확인한 뒤 3단계에서 붙인다. 지금 둘을 같이 넣으면 위치가 안 올라올 때
 * 원인이 수집 주기인지 업로드인지 가려내기 어렵다.
 */
class LocationCollector(private val context: Context) {

    private val client = LocationServices.getFusedLocationProviderClient(context)
    private var callback: LocationCallback? = null

    /** 권한은 호출 전에 확인돼 있어야 한다. PermissionActivity 가 보장한다. */
    @SuppressLint("MissingPermission")
    fun start(onFix: (Fix) -> Unit) {
        stop()
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, INTERVAL_MILLIS)
            .setMinUpdateIntervalMillis(INTERVAL_MILLIS / 2)
            .build()

        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                onFix(Fix(loc.latitude, loc.longitude, loc.accuracy, loc.time))
            }
        }
        callback = cb
        client.requestLocationUpdates(request, cb, context.mainLooper)
    }

    fun stop() {
        callback?.let { client.removeLocationUpdates(it) }
        callback = null
    }

    private companion object {
        const val INTERVAL_MILLIS = 60_000L
    }
}
```

- [ ] **Step 3: `StatusReporter` 를 쓴다**

```kotlin
package com.kidcare.family.child

import com.google.firebase.firestore.FirebaseFirestore
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.core.model.PointDoc
import com.kidcare.family.logic.Fix
import kotlinx.coroutines.tasks.await

/**
 * 위치 한 점을 Firestore 두 곳에 쓴다.
 *
 *   status  — 항상 덮어쓴다. 보호자 화면의 '지금 위치'가 이걸 구독한다.
 *   points  — 계속 쌓는다. 3단계에서 구간 요약의 재료가 된다.
 */
class StatusReporter {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    suspend fun report(
        familyId: String,
        childUid: String,
        fix: Fix,
        battery: Int,
        charging: Boolean,
    ) {
        val childRef = db.collection("families").document(familyId)
            .collection("children").document(childUid)

        childRef.set(
            ChildStatusDoc(
                lat = fix.lat,
                lng = fix.lng,
                accuracy = fix.accuracy,
                at = fix.at,
                battery = battery,
                charging = charging,
                lastSeenAt = System.currentTimeMillis(),
            )
        ).await()

        childRef.collection("points").add(
            PointDoc(
                lat = fix.lat,
                lng = fix.lng,
                accuracy = fix.accuracy,
                at = fix.at,
                battery = battery,
            )
        ).await()
    }
}
```

> 설계서에는 `children/{childUid}/status` 가 하위 문서로 그려져 있지만, Firestore 는
> 문서 아래에 바로 필드를 둘 수 있으므로 `children/{childUid}` 문서 자체를 status 로 쓴다.
> 문서 하나를 아끼고 읽기도 한 번 줄어든다. **설계서의 이 표기를 이 구현에 맞춰 고친다.**

- [ ] **Step 4: `TrackingService` 를 쓴다**

```kotlin
package com.kidcare.family.child

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.BatteryManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.RoleStore
import com.kidcare.family.logic.Decision
import com.kidcare.family.logic.Fix
import com.kidcare.family.logic.LocationFilter
import kotlinx.coroutines.launch

/**
 * 아이 폰에서 상시 도는 서비스.
 *
 * 알림줄에 아이콘이 계속 뜬다. 안드로이드가 요구하는 것이기도 하고,
 * '몰래 감시하지 않는다'는 이 앱의 원칙에도 맞는다.
 */
class TrackingService : LifecycleService() {

    private val collector by lazy { LocationCollector(this) }
    private val reporter = StatusReporter()
    private var lastUploaded: Fix? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(
            NOTIFICATION_ID,
            buildNotification(),
        )
    }

    private fun startForeground(id: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            super.startForeground(id, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)

        val store = RoleStore(this)
        val familyId = store.familyId
        if (familyId == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        collector.start { fix -> handle(familyId, fix) }
        return START_STICKY
    }

    private fun handle(familyId: String, fix: Fix) {
        when (LocationFilter.decide(lastUploaded, fix)) {
            Decision.UPLOAD -> Unit
            Decision.SKIP_TOO_CLOSE,
            Decision.REJECT_INACCURATE,
            Decision.REJECT_IMPOSSIBLE -> return
        }

        lifecycleScope.launch {
            val childUid = AuthGateway.currentUid() ?: AuthGateway.signIn()
            runCatching {
                reporter.report(familyId, childUid, fix, batteryPercent(), isCharging())
            }.onSuccess {
                lastUploaded = fix
            }
        }
    }

    private fun batteryPercent(): Int {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    private fun isCharging(): Boolean {
        val status = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.channel_tracking),
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.tracking_notification_title))
            .setContentText(getString(R.string.tracking_notification_text))
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        collector.stop()
        super.onDestroy()
    }

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "tracking"

        fun start(context: Context) {
            context.startForegroundService(Intent(context, TrackingService::class.java))
        }
    }
}
```

`BootReceiver.kt`:

```kotlin
package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore

/** 재부팅 후 자녀 폰이면 위치 서비스를 다시 띄운다. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val store = RoleStore(context)
        if (store.role == Role.CHILD && store.isPaired) {
            TrackingService.start(context)
        }
    }
}
```

- [ ] **Step 5: 매니페스트에 등록하고 홈에서 서비스를 켠다**

`<application>` 안에 추가:

```xml
        <service
            android:name=".child.TrackingService"
            android:exported="false"
            android:foregroundServiceType="location" />

        <receiver
            android:name=".child.BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
```

`ChildHomeActivity.onResume()` 의 `if (missing == null)` 가지 안에 한 줄 추가:

```kotlin
        binding.childStatus.text = if (missing == null) {
            TrackingService.start(this)
            getString(R.string.child_sharing_on)
        } else {
```

`strings.xml` 에 추가:

```xml
    <string name="channel_tracking">위치 공유</string>
    <string name="tracking_notification_title">위치 공유 중</string>
    <string name="tracking_notification_text">부모님께 내 위치를 알려주고 있어요</string>
```

- [ ] **Step 6: 아이폰에서 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug && adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

확인:
1. 아이폰에서 앱 실행 → 알림줄에 "위치 공유 중" 이 뜬다
2. **1~2분 기다린다** (첫 위치 fix 가 오는 데 시간이 걸린다. 실내면 더 걸린다)
3. Firebase 콘솔 `Firestore Database` → `families/{id}/children/{childUid}` 문서에
   `lat`, `lng`, `battery`, `lastSeenAt` 이 채워진다
4. 같은 문서의 `points` 하위 컬렉션에 문서가 하나 생긴다
5. 폰을 들고 100m 이상 걸어간 뒤 `points` 가 하나 더 늘어나는지 본다
6. 제자리에 있으면 10분에 한 번만 늘어난다 (LocationFilter 의 heartbeat)
7. 앱을 최근 앱에서 밀어 없애도 알림이 남아 있고 위치가 계속 올라온다
8. 폰을 재부팅하고 몇 분 뒤 `lastSeenAt` 이 갱신되는지 본다 (BootReceiver)

안 올라오면 이 순서로 본다:
```bash
adb -s <아이폰시리얼> logcat -s TrackingService:* AndroidRuntime:E FirebaseFirestore:*
```

- [ ] **Step 7: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "위치 수집: 상시 포그라운드 서비스

FusedLocationProvider 로 1분마다 받아 LocationFilter 를 통과한 것만
status 문서와 points 컬렉션에 올린다. 재부팅 시 자동 재시작.
정지/이동에 따른 주기 전환은 3단계에서 붙인다."
```

---

### Task 10: 카카오맵에 현재 위치 표시

보호자 폰에서 지도를 띄우고 아이의 현재 위치에 마커를 찍는다. **1~2단계의 마지막 조각**이다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/guardian/MapTimelineFragment.kt`
- Modify: `app/src/main/java/com/kidcare/family/guardian/GuardianMainActivity.kt`
- Create: `app/src/main/res/layout/activity_guardian_main.xml`, `res/layout/fragment_map_timeline.xml`
- Create: `app/src/main/res/drawable/marker_child.xml`
- Modify: `app/build.gradle.kts` (카카오 의존성), `KidCareApp.kt`, `strings.xml`, `docs/setup.md`
- Modify: `app/src/main/java/com/kidcare/family/core/FamilyRepository.kt` (`observeChildStatus` 추가)

**Interfaces:**
- Consumes: `RoleStore` (Task 4), `ChildStatusDoc` (Task 5), `BuildConfig.KAKAO_APP_KEY` (Task 1)
- Produces:
  - `FamilyRepository.observeChildStatus(familyId, childUid, onChange: (ChildStatusDoc) -> Unit): ListenerRegistration`
  - `FamilyRepository.findChildUid(familyId: String): String?` — suspend
  - `MapTimelineFragment` — 3단계에서 타임라인이 여기 붙는다

- [ ] **Step 1: 카카오 앱키를 발급받고 절차를 기록한다**

`docs/setup.md` 에 추가:

```markdown
## 카카오 지도 앱키 설정

1. https://developers.kakao.com 로그인 → `내 애플리케이션` → `애플리케이션 추가하기`
   - 앱 이름: 우리아이 지킴이 / 회사명: 개인
2. 만든 앱 클릭 → 왼쪽 `앱 설정 > 플랫폼` → `Android 등록`
   - 패키지명: `com.kidcare.family`
   - 마켓 URL: 비워둠
   - 키 해시: 아래 명령으로 얻는다
     ```bash
     keytool -exportcert -alias androiddebugkey \
       -keystore "$USERPROFILE/.android/debug.keystore" \
       -storepass android -keypass android | openssl sha1 -binary | openssl base64
     ```
     (keytool 은 JDK 안에 있다. 예: `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`)
3. 왼쪽 `앱 설정 > 앱 키` → **네이티브 앱 키**를 복사
4. `C:\workAndroid\KidCare\local.properties` 에 한 줄 추가 (이 파일은 git 에 안 올라간다):
   ```properties
   KAKAO_APP_KEY=여기에_네이티브_앱_키
   ```
5. 릴리스 APK를 만들 때는 릴리스 키스토어의 키 해시도 같은 자리에 **추가로** 등록해야 한다.
   디버그 키 해시만 등록하면 릴리스 빌드에서 지도가 안 뜬다.
```

- [ ] **Step 2: 카카오 SDK를 붙이고 초기화한다**

`app/build.gradle.kts` 의 `dependencies` 에 추가:

```kotlin
    implementation(libs.kakao.map)
```

`KidCareApp.kt`:

```kotlin
package com.kidcare.family

import android.app.Application
import com.kakao.vectormap.KakaoMapSdk

class KidCareApp : Application() {

    override fun onCreate() {
        super.onCreate()
        // 앱키가 비어 있으면 SDK 초기화를 건너뛴다. 지도 화면이 안내를 띄우고,
        // 나머지 기능(페어링·위치 수집)은 그대로 돌아간다.
        if (BuildConfig.KAKAO_APP_KEY.isNotEmpty()) {
            KakaoMapSdk.init(this, BuildConfig.KAKAO_APP_KEY)
        }
    }
}
```

- [ ] **Step 3: `FamilyRepository` 에 자녀 상태 구독을 추가한다**

`FamilyRepository.kt` 안에 붙인다. `import com.kidcare.family.core.model.ChildStatusDoc` 를 추가한다.

```kotlin
    /** 가족의 자녀 uid 를 찾는다. 자녀가 없으면 null. */
    suspend fun findChildUid(familyId: String): String? =
        db.collection("families").document(familyId).collection("members")
            .whereEqualTo("role", "child").get().await()
            .documents.firstOrNull()?.id

    /** 자녀의 현재 상태를 실시간 구독한다. 화면이 사라질 때 remove 해야 한다. */
    fun observeChildStatus(
        familyId: String,
        childUid: String,
        onChange: (ChildStatusDoc) -> Unit,
    ): ListenerRegistration =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .addSnapshotListener { snapshot, _ ->
                snapshot?.toObject(ChildStatusDoc::class.java)?.let(onChange)
            }
```

- [ ] **Step 4: 마커 드로어블과 레이아웃을 만든다**

`res/drawable/marker_child.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="36dp"
    android:height="36dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FF3D6DF5"
        android:pathData="M12,2C8.13,2 5,5.13 5,9c0,5.25 7,13 7,13s7,-7.75 7,-13c0,-3.87 -3.13,-7 -7,-7zM12,11.5c-1.38,0 -2.5,-1.12 -2.5,-2.5s1.12,-2.5 2.5,-2.5 2.5,1.12 2.5,2.5 -1.12,2.5 -2.5,2.5z" />
</vector>
```

`res/layout/activity_guardian_main.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/fragment_container"
    android:layout_width="match_parent"
    android:layout_height="match_parent" />
```

> 하단 탭 4개(지도·관리·예약·알림)는 설계서에 있지만, 지금 탭이 하나뿐이라
> 넣지 않는다. 두 번째 탭이 생기는 4단계에서 `BottomNavigationView` 를 붙인다.

`res/layout/fragment_map_timeline.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <com.kakao.vectormap.MapView
        android:id="@+id/map_view"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />

    <com.google.android.material.card.MaterialCardView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_gravity="top"
        android:layout_margin="12dp"
        app:cardCornerRadius="16dp"
        xmlns:app="http://schemas.android.com/apk/res-auto">

        <TextView
            android:id="@+id/status_bar"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:padding="16dp"
            android:textAppearance="?attr/textAppearanceBodyLarge" />
    </com.google.android.material.card.MaterialCardView>

    <TextView
        android:id="@+id/no_key_notice"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:background="?attr/colorSurface"
        android:gravity="center"
        android:padding="32dp"
        android:text="@string/map_no_key"
        android:visibility="gone" />
</FrameLayout>
```

- [ ] **Step 5: 지도 프래그먼트를 쓴다**

`guardian/MapTimelineFragment.kt`:

```kotlin
package com.kidcare.family.guardian

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.google.firebase.firestore.ListenerRegistration
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.camera.CameraUpdateFactory
import com.kakao.vectormap.label.Label
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelStyles
import com.kidcare.family.BuildConfig
import com.kidcare.family.R
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.databinding.FragmentMapTimelineBinding
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * 보호자 메인. 카카오맵 위에 아이의 현재 위치를 찍는다.
 *
 * 3단계에서 하루 경로 폴리라인과 아래쪽 타임라인 목록이 여기 붙는다.
 */
class MapTimelineFragment : Fragment() {

    private var _binding: FragmentMapTimelineBinding? = null
    private val binding get() = _binding!!

    private var kakaoMap: KakaoMap? = null
    private var childLabel: Label? = null
    private var statusListener: ListenerRegistration? = null
    private var pendingStatus: ChildStatusDoc? = null

    private val timeFormat = SimpleDateFormat("HH:mm", Locale.KOREA)

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        _binding = FragmentMapTimelineBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        if (BuildConfig.KAKAO_APP_KEY.isEmpty()) {
            binding.noKeyNotice.visibility = View.VISIBLE
            return
        }

        binding.mapView.start(
            object : MapLifeCycleCallback() {
                override fun onMapDestroy() = Unit
                override fun onMapError(error: Exception) {
                    binding.statusBar.text = getString(R.string.map_error, error.message ?: "")
                }
            },
            object : KakaoMapReadyCallback() {
                override fun onMapReady(map: KakaoMap) {
                    kakaoMap = map
                    // 지도가 준비되기 전에 도착한 상태가 있으면 지금 그린다.
                    pendingStatus?.let { render(it) }
                }
            },
        )

        subscribe()
    }

    private fun subscribe() {
        val store = RoleStore(requireContext())
        val familyId = store.familyId ?: return
        viewLifecycleOwner.lifecycleScope.launch {
            val childUid = FamilyRepository.findChildUid(familyId)
            if (childUid == null) {
                binding.statusBar.text = getString(R.string.map_no_child)
                return@launch
            }
            statusListener = FamilyRepository.observeChildStatus(familyId, childUid) { status ->
                render(status)
            }
        }
    }

    private fun render(status: ChildStatusDoc) {
        _binding ?: return
        binding.statusBar.text = getString(
            R.string.map_status_format,
            status.battery,
            timeFormat.format(status.at),
        )

        val map = kakaoMap
        if (map == null) {
            pendingStatus = status
            return
        }
        pendingStatus = null

        val position = LatLng.from(status.lat, status.lng)
        val label = childLabel
        if (label == null) {
            val styles = LabelStyles.from(
                "child",
                LabelStyle.from(R.drawable.marker_child).setAnchorPoint(0.5f, 1.0f),
            )
            childLabel = map.labelManager?.layer?.addLabel(
                LabelOptions.from("child", position).setStyles(styles)
            )
            map.moveCamera(CameraUpdateFactory.newCenterPosition(position, 16))
        } else {
            label.moveTo(position)
        }
    }

    override fun onResume() {
        super.onResume()
        if (BuildConfig.KAKAO_APP_KEY.isNotEmpty()) binding.mapView.resume()
    }

    override fun onPause() {
        if (BuildConfig.KAKAO_APP_KEY.isNotEmpty()) binding.mapView.pause()
        super.onPause()
    }

    override fun onDestroyView() {
        statusListener?.remove()
        statusListener = null
        kakaoMap = null
        childLabel = null
        _binding = null
        super.onDestroyView()
    }
}
```

`guardian/GuardianMainActivity.kt`:

```kotlin
package com.kidcare.family.guardian

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.R

/**
 * 보호자 메인 컨테이너. 지금은 지도 하나뿐이다.
 * 4단계에서 하단 탭(지도·관리·예약·알림)이 붙는다.
 */
class GuardianMainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_guardian_main)

        if (savedInstanceState == null) {
            supportFragmentManager.beginTransaction()
                .replace(R.id.fragment_container, MapTimelineFragment())
                .commit()
        }
    }
}
```

`strings.xml` 에 추가:

```xml
    <string name="map_no_key">지도 키가 설정되지 않았습니다.\n개발자에게 문의하세요.</string>
    <string name="map_no_child">아직 아이 폰이 연결되지 않았어요.</string>
    <string name="map_error">지도를 불러오지 못했어요\n%1$s</string>
    <string name="map_status_format">🔋 %1$d%%   ·   %2$s 기준</string>
</resources>
```

- [ ] **Step 6: 두 폰으로 확인한다** (1~2단계 최종 확인)

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug
adb -s <엄마폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

확인:
1. 두 폰 `pm clear` → 페어링 → 아이폰 권한 전부 켜기
2. 아이폰을 창가에 두고 1~2분 기다린다
3. **엄마폰에 카카오 지도가 뜨고, 아이 위치에 파란 마커가 찍힌다**
4. 위쪽 카드에 `🔋 78% · 15:42 기준` 이 보인다
5. 아이폰을 들고 100m 이상 이동하면 **엄마폰 마커가 앱을 만지지 않아도 따라 움직인다**
6. 엄마폰 앱을 껐다 켜도 마지막 위치가 그대로 보인다
7. `local.properties` 의 `KAKAO_APP_KEY` 를 지우고 빌드하면 "지도 키가 설정되지 않았습니다" 가 뜨고 앱이 죽지 않는다 (확인 후 키를 되돌린다)

- [ ] **Step 7: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "지도: 카카오맵에 아이 현재 위치 표시

status 문서를 실시간 구독해 마커를 옮긴다. 앱키가 없으면 안내 화면을 띄우고
나머지 기능은 그대로 돈다. 1~2단계 완료."
```

- [ ] **Step 8: 설계서의 어긋난 부분을 고친다**

Task 9 Step 3에서 정한 대로, 설계서의 Firestore 구조에서
`children/{childUid}/status (문서 1개)` 를 `children/{childUid}` 문서 자체가 status 라고 고친다.

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "설계서: status 를 별도 문서가 아니라 children 문서 자체로 정정"
```

---

## Self-Review

**1. 스펙 커버리지 (1~2단계 범위)**

| 스펙 항목 | 담당 Task |
|---|---|
| 프로젝트 구성·빌드 환경 (§2) | Task 1 |
| 단일 APK + 역할 선택 (§3 앱 구성) | Task 4 |
| 페어링, 초대 코드 10분 만료 (§3) | Task 2, 5, 6 |
| Firestore 문서 구조 (§3) | Task 5 (모델), 9 (쓰기), 10 (읽기) |
| 보안 규칙 (§3) | Task 6 |
| 위치 수집 주기 (§4.1) | Task 9 — **1분 고정만.** 정지/이동 전환은 3단계로 미룸 (Task 9 Step 2 주석에 명시) |
| 50m·100m·200km/h 필터 (§4.1) | Task 8 |
| 권한 온보딩 (§2 자녀폰 ⑥) | Task 7 — **위치·알림·배터리만.** DND·정확한알람은 4·5단계 |
| 지도 현재 위치 (§구현순서 2단계) | Task 10 |
| 오프라인 버퍼 (§5) | **7단계.** 이 계획 범위 밖 |
| 구간 요약·타임라인 (§4.2) | **3단계.** 이 계획 범위 밖 |

의도적으로 미룬 항목은 전부 계획 안에 이유와 함께 적어뒀다. 누락은 없다.

**2. 플레이스홀더 점검** — "TBD", "적절히 처리", "위와 비슷하게" 없음. Task 4 Step 3의 빈 액티비티는 껍데기임을 명시하고 어느 Task가 채우는지 적었다. 모든 코드 단계에 실제 코드가 들어 있다.

**3. 타입 일관성**

- `Fix`(Task 8) → `LocationCollector.start`, `StatusReporter.report`, `TrackingService.handle`(Task 9) 에서 같은 시그니처로 쓰인다 ✓
- `ChildStatusDoc`(Task 5) → `StatusReporter`(Task 9) 가 쓰고 `MapTimelineFragment`(Task 10) 가 읽는다 ✓
- `RoleStore.familyId`(Task 4) → Task 5·6·9·10 에서 모두 같은 이름 ✓
- `FamilyRepository` 는 Task 5에서 만들고 Task 6·10에서 메서드를 더한다. `db`, `INVITE_TTL_MILLIS` 를 공유한다 ✓
- `InviteCode.normalize`(Task 2) → `joinFamily`(Task 6), `ChildPairingActivity`(Task 6) ✓
- `PermissionStep.firstMissing`(Task 7) → `PermissionActivity`, `ChildHomeActivity`(Task 7) ✓

**4. 발견해서 계획에 반영한 것**

- Task 6의 보안 규칙이 `children/{childUid}/**` 를 자녀 전용 쓰기로 잠근다. **4단계에서 보호자가 `commands/` 를 써야 하므로 규칙을 반드시 고쳐야 한다** — Task 6 Step 3에 경고로 남겼고, 4단계 계획의 필수 항목이다.
- 설계서의 `children/{childUid}/status` 표기를 구현이 바꾼다 — Task 10 Step 8에서 설계서를 정정한다.
