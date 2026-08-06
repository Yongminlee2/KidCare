# 개발 환경 메모

## 단위 테스트 실행법

이 PC의 사용자 홈이 `C:\Users\사용자` (한글)이라, 기본 상태로는 Gradle JVM 테스트
워커가 `ClassNotFoundException: GradleWorkerMain`으로 죽는다. `gradle.properties`에
이미 넣어둔 `-Dfile.encoding=MS949` 만으로 해결됐다 — 추가 조치(`GRADLE_USER_HOME`
변경 등)는 필요 없었다.

통한 명령 (JDK 21, Android Studio 내장 JBR):

```bash
cd /c/workAndroid/KidCare
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

결과: `BUILD SUCCESSFUL` — 44 actionable tasks. `SmokeTest`(테스트명에 한글 포함)가
`app/build/test-results/testDebugUnitTest/TEST-com.kidcare.family.logic.SmokeTest.xml`에
`tests="1" failures="0" errors="0"`로 기록됨.

`./gradlew.bat --stop`으로 데몬을 내리고 `app/build`를 지운 뒤 처음부터 다시
돌려도 같은 결과가 재현됐다 — 옛 데몬 설정이 남아있어서 우연히 통과한 게 아니다.

### 시도했지만 필요 없었던 것
- `GRADLE_USER_HOME=C:/gradle-home` — MS949 인코딩만으로 충분했으므로 안 씀.
- `C:/workAndroid/gradle-user-ascii` — 이건 애초에 한글 홈으로 가는 정션이라
  효과가 없다는 걸 알고 있었으므로 시도하지 않음.

### JDK 경로
`org.gradle.java.home`은 프로젝트 `gradle.properties`에 넣지 않는다(기계마다
다르므로). 이 기계에서는 빌드 명령 앞에 `JAVA_HOME`을 지정해서 돌렸다:
`C:\Program Files\Android\Android Studio\jbr` (JDK 21).

## local.properties의 sdk.dir — 한글 사용자 홈 함정

`sdk.dir=C:\Users\사용자\...`처럼 원문 한글을 그대로 적으면(UTF-8 바이트로 저장되면)
AGP의 `SdkLocator`가 `local.properties`를 Java `Properties` 규격(ISO-8859-1)으로 읽다가
한글 바이트가 깨져 제어문자가 섞인 경로 문자열이 되고, 결국
`java.io.IOException: Invalid file path`로 `:app:compileDebugJavaWithJavac`의
의존성 계산 단계에서 빌드가 죽는다.

해결: `local.properties`의 한글 부분을 Java Properties의 `\uXXXX` 유니코드 이스케이프로
적는다 (Android Studio가 원래 생성하는 방식과 동일):

```properties
sdk.dir=C\:\\Users\\\uC0AC\uC6A9\uC790\\AppData\\Local\\Android\\Sdk
```

(`\uC0AC\uC6A9\uC790` = "사용자". 콜론과 백슬래시도 Properties 값 규칙대로 이스케이프.)

이 파일은 `.gitignore`에 있어 커밋되지 않는다 — 기계마다 새로 만들어야 한다.

## compileSdk 37로 올린 이유 (브리프의 36에서 편차)

브리프가 지정한 `androidx.core-ktx:1.19.0`은 `compileSdk 37` 이상을 요구한다
(`:app:checkDebugAarMetadata`가 명시적으로 이를 검사해 실패시킨다). 브리프의
`compileSdk = 36`과 `coreKtx = "1.19.0"`이 서로 맞지 않는 조합이었다.

이 기계에는 `android-37.0` 플랫폼이 이미 설치돼 있어서, 추가 다운로드 없이
`app/build.gradle.kts`의 `compileSdk`만 37로 올려서 해결했다. `targetSdk`는
브리프대로 36을 유지했다 — AGP 에러 메시지 자체가 compileSdk와 targetSdk를
독립적으로 올릴 수 있다고 안내한다.

### 새 기계에서 준비할 것: Android SDK Platform 37

`compileSdk = 37`은 **Android SDK Platform 37**이 로컬에 설치되어 있어야 빌드된다.
이 기계는 우연히 이미 설치돼 있어서 빌드가 바로 통과했지만, 새로 이 프로젝트를
받는 기계에는 없을 수 있다 — 그 경우 `compileSdk 37` 관련 리소스/플랫폼을 찾지
못한다는 불친절한 에러로 실패한다. 다음 중 하나로 미리 설치해 둔다:

- Android Studio의 SDK Manager에서 "Android 15 (API 37... 표기는 릴리스에 따라
  다름)" 플랫폼 체크박스 설치, 또는
- 커맨드라인: `sdkmanager "platforms;android-37"`

원인은 위에서 적은 대로 `core-ktx 1.19.0`이 `compileSdk 37`을 요구하기 때문이다.
