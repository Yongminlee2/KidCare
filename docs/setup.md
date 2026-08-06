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

이 프로젝트(`kidcare-17fe5`)는 위 절차로 이미 만들어졌고 `app/google-services.json`도
받아져 있다 (Task 3 작업 시작 시점 기준). 이 파일은 `.gitignore`에 있어 커밋되지
않으므로, 새 기계에서 이어받으면 위 절차를 다시 밟아 직접 받아야 한다.

## Firestore 보안 규칙 게시 (Task 6)

규칙 원본은 저장소의 `firestore.rules` 다. 콘솔에 붙여넣어 게시한다:

1. https://console.firebase.google.com → `kidcare-17fe5` 프로젝트 → 왼쪽 메뉴
   `빌드 > Firestore Database` → 상단 탭 `규칙`
2. 저장소의 `firestore.rules` 내용 전체를 복사해 편집기에 붙여넣기 (기존 내용을
   덮어쓴다 — 지금 콘솔에는 프로덕션 모드의 기본값, 즉 전부 막힌 규칙이 들어있다)
3. `게시` 클릭

이 작업은 Claude 가 대신 할 수 없다 — 콘솔 게시 버튼은 사람이 직접 눌러야 한다.
Task 6 작업 시점 기준으로 익명 인증은 이미 사용 설정돼 있고 Firestore 도
프로덕션 모드로 만들어져 있었지만, 규칙은 아직 게시 전이었다(임시로 열어둔 기본
규칙 상태). 이 규칙을 게시하기 전에는 페어링을 포함한 모든 Firestore 읽기/쓰기가
막혀 있거나(프로덕션 모드 기본값은 전면 거부) 반대로 완전히 열려 있을 수 있으니,
두 폰 확인(Step 4)은 반드시 게시 이후에 진행한다.

**주의 (4단계에서 반드시 먼저 처리할 것):** `firestore.rules` 의
`children/{childUid}/{document=**}` 규칙은 그 아래 전부를 아이 본인만 쓸 수 있게
막는다. 원격 명령(`commands/`)은 보호자가 써야 하는데, 이 프로젝트는 Cloud
Functions 없이 Spark 무료 요금제로 가기 위해 FCM 푸시 대신 **Firestore 스냅샷
리스너**로 명령을 전달하기로 했다 — 즉 보호자 쓰기가 막힌 채로는 즉시 변경·폰찾기
기능 자체가 동작하지 않는다. 4단계 계획에 `commands/` 전용 규칙 분리를 반드시
넣는다.

### fix round 1 (보안 리뷰) — `inviteCodes` 컬렉션 추가

Task 6 최초 버전은 `families`를 `inviteCode` 필드로 query(`whereEqualTo`)해서 코드를
찾았는데, Firestore 규칙은 `get`과 `list`를 구분하지 못해 이 조회를 열어두려면 결국
`families` 컬렉션 전체를 회원 아닌 사람도 `list`할 수 있게 열어야 했다 — 초대 코드가
전부 새어나가는 구멍이었다. 그리고 `members/{uid}` 의 `create` 규칙이 역할·코드를
전혀 검증하지 않아, 아무나 아무 가족의 `familyId`만 알면 자기를 그 가족의 `guardian`으로
등록할 수 있었다.

고친 구조: `inviteCodes/{code}` 컬렉션을 새로 두고 문서 ID 자체를 코드로 쓴다 —
`get`(정확한 ID 하나)만 허용하고 `list`는 규칙에서 아예 막는다. `families` 문서에는
`ownerUid`(생성자 uid)를, `members` 문서에는 `joinCode`(가입 시 사용한 코드)를
추가해, `members/{uid}`를 `create`할 때 규칙이 서버에서 "보호자 자리는 `ownerUid`
본인만, 자녀 자리는 살아있는 코드를 실제로 아는 사람만" 가져갈 수 있게 대조한다.
`core/model/Documents.kt`의 `FamilyDoc.ownerUid`, `MemberDoc.joinCode`,
`InviteCodeDoc`이 이 변경분이다. 이 프로젝트는 이 시점까지 규칙을 한 번도 게시하지
않았으므로(위 참고) 콘솔에 남아있는 기존 데이터·구버전 문서는 없다 — 마이그레이션
불필요.

## 자녀 권한 온보딩 기기 확인 (Task 7)

Task 7은 코드만 작성했고 실기기 확인은 사람이 직접 한다. 확인 절차:

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug && adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

1. `pm clear com.kidcare.family` 후 아이 역할로 페어링 → 권한 화면이 나온다
2. `위치 권한` → `켜기` → 시스템 창에서 `앱을 사용하는 동안만 허용` → 화면이
   `위치 '항상 허용'` 단계로 바뀐다
3. `켜기` → (안드로이드 11+ 는) 설정 앱이 열림 → 권한 > 위치 > `항상 허용` 선택
   → 뒤로 → 화면이 `알림` 단계로 바뀐다
4. 알림 허용 → `배터리 최적화 제외` 단계로 바뀜 → `켜기` → 배터리 최적화 제외
   목록 화면이 열림 → 목록에서 직접 `우리아이 지킴이`를 찾아 `제한 없음`으로 바꿈
   (화면에 이 안내 문구가 같이 뜬다)
5. 뒤로 오면 "위치 공유 중" 화면(`ChildHomeActivity`)이 뜬다
6. 앱을 껐다 켜면 (RouterActivity가 페어링 완료 상태를 보고) 바로 "위치 공유 중"
   화면으로 간다
7. 거부 경로 확인: 아무 단계에서나 시스템 다이얼로그가 뜨면 `거부`를 두 번
   누르거나 `다시 묻지 않음`을 체크 → 화면 문구가 "방금 거부돼서... 설정에서
   켜기"로 바뀌고 버튼도 `설정에서 켜기`로 바뀌는지 확인 → 눌러서 앱 설정 화면이
   열리는지, 거기서 권한을 켜고 돌아오면 다음 단계로 정상 진행되는지 확인

**삼성 기기라면** 위 표준 API 확인(4단계)과 별도로, `설정 > 배터리 > 백그라운드
사용 제한 > 절전 앱`에서도 `우리아이 지킴이`를 제외해야 한다. 삼성은 표준
`PowerManager.isIgnoringBatteryOptimizations`와 별개로 자체 절전 앱 목록을 두고
백그라운드에서 앱을 죽이는데, 이건 표준 API로는 확인도 해제도 안 되는
제조사 전용 기능이라 앱 코드로 감지·유도할 수 없다 — 사람이 수동으로 확인해야
한다.

## 카카오 지도 앱키 설정 (Task 10)

보호자 화면 지도는 카카오맵 SDK를 쓴다. 앱키가 없으면 빌드는 되지만 지도
자리에 "지도 키가 설정되지 않았습니다" 안내만 뜨고 나머지 기능(페어링·위치
수집)은 그대로 동작한다 — 이 저장소를 처음 받은 사람은 아래 절차를 밟기
전까지 이 상태로 개발을 계속할 수 있다.

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
5. 릴리스 APK를 만들 때는 릴리스 키스토어의 키 해시도 같은 자리(`앱 설정 >
   플랫폼 > Android`)에 **추가로** 등록해야 한다. 디버그 키 해시만 등록하면
   릴리스 빌드는 컴파일·실행은 되지만 지도만 조용히 안 뜬다(예외 없이
   `onMapError` 콜백만 호출됨) — 배포 직전에 반드시 확인할 것.

### 두 폰 확인 (Task 10, 1~2단계 최종 확인)

Task 10 코드 작업은 여기까지고, 실기기 확인은 사람이 직접 한다:

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug
adb -s <엄마폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

1. 두 폰 `pm clear com.kidcare.family` → 페어링 → 아이폰 권한 전부 켜기
2. 아이폰을 창가에 두고 1~2분 기다린다
3. 엄마폰에 카카오 지도가 뜨고, 아이 위치에 파란 마커가 찍히는지 확인
4. 위쪽 카드에 `🔋 78% · 15:42 기준` 같은 문구가 보이는지 확인
5. 아이폰을 들고 100m 이상 이동하면 엄마폰 마커가 앱을 만지지 않아도
   따라 움직이는지 확인
6. 엄마폰 앱을 껐다 켜도 마지막 위치가 그대로 보이는지 확인
7. `local.properties` 의 `KAKAO_APP_KEY` 를 지우고 다시 빌드하면 "지도 키가
   설정되지 않았습니다" 가 뜨고 앱이 죽지 않는지 확인 (확인 후 키를 되돌린다)
