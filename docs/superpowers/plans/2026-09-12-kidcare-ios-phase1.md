# iOS 1단계 구현 계획 — 뼈대·인증·페어링·아이 마커

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰에서 익명 로그인으로 기존 가족에 **보호자로 합류**하고, 지도 위에 그 가족 아이의 마지막 위치 마커 하나를 띄운다.

**Architecture:** `ios/` 를 새로 세운다. 안드로이드 `app/` 은 건드리지 않는다. 계산은 `Logic/`(Foundation만), Firestore는 `Core/`, 화면은 `Onboarding/`·`Guardian/` — 안드로이드의 모듈 경계를 그대로 옮긴다. 이 단계의 존재 이유는 화면을 예쁘게 만드는 것이 아니라 **위험한 것 셋을 먼저 뚫는 것**이다: 네이버 지도 iOS SDK가 붙는가, Firestore가 도는가, 보호자 합류가 보안 규칙을 통과하는가.

**Tech Stack:** Swift 6 / SwiftUI / iOS 17.0+ / Xcode 26.6, Firebase iOS SDK(Auth·Firestore, SPM), 네이버 지도 iOS SDK 3.23.3(SPM), Swift Testing, Firebase Local Emulator Suite.

**Spec:** `docs/superpowers/specs/2026-09-12-kidcare-ios-design.md`

## Global Constraints

- **최소 iOS 17.0.** Swift 6, SwiftUI. 지도만 `UIViewRepresentable` 로 감싼다.
- **안드로이드 `app/` 아래를 수정하지 않는다.** 이 단계에는 예외가 없다.
- **`Logic/` 은 Firebase·SwiftUI·UIKit 을 import 하지 않는다.** Foundation만 쓴다. 이 경계가 깨지면 테스트가 시뮬레이터를 필요로 하기 시작한다.
- **Firestore 문서 매핑에 `Codable` 을 쓰지 않는다.** `firestore.rules` 가 `hasOnly()` 로 필드 집합을 검사해서 필드가 하나만 더 나가도 쓰기가 통째로 거부된다. 손으로 `[String: Any]` 를 만든다.
- **시각은 전부 UTC 밀리초 `Int64`.** 안드로이드 `Documents.kt` 와 같은 단위다.
- 주석은 **한국어로 '왜'** 를 적는다. 무엇을 하는지는 코드가 말한다. 집필 기준은 `app/src/main/java/com/kidcare/family/core/AuthGateway.kt`.
- 화면 문구는 **하드코딩하지 않는다.** 1단계에서는 `String(localized:)` 키만 쓰고, 키 정의는 6단계(다국어)에서 `i18n` 원본에서 생성한다. 1단계 동안은 `Localizable.xcstrings` 에 한국어만 직접 넣어 둔다.
- **커밋 메시지는 한국어, author `Yongminlee2 <dydals5678@gmail.com>`, 도구·AI 흔적 금지.** 기존 113개 커밋과 같은 결을 지킨다.
- **비밀은 커밋하지 않는다.** `GoogleService-Info.plist` 와 `ios/Config/Secrets.xcconfig` 는 `.gitignore` 에 넣는다. 안드로이드가 `local.properties` 를 쓰는 것과 같은 대우다.
- **`.xcodeproj` 를 커밋하지 않는다.** `project.yml` 이 정본이고 `xcodegen generate` 로 만든다.
- **`Task.checkCancellation()` / `CancellationError` 는 다른 어떤 일반 `catch` 보다 먼저 다시 던진다.** 안드로이드의 `CancellationException` 규칙과 같은 이유다.

## 이 단계에서 다루지 않는 것

- 탭 다섯(알림·관리·예약·장소)과 타임라인·경로선. 3~6단계다.
- `Logic/` 나머지 8개 포팅과 골든 파일 대조. 2단계다.
- 다국어 14벌과 `tools/ios-strings.py`. 6단계다.
- 아이콘·개인정보 매니페스트·TestFlight. 7단계다.
- **푸시(FCM).** 설계서 §1에서 안 만들기로 확정했다. `MemberDoc.fcmToken` 필드는 스키마에 있지만 iOS는 빈 값으로 둔다.

## 사용자가 먼저 해줘야 하는 것

**Task 1 전:** 없음 — Task 1 자체가 도구 설치다.

**Task 8 전에 두 가지가 필요하다.** Task 2~7 은 이것 없이도 끝까지 간다(테스트가 에뮬레이터와 가짜 `FirebaseOptions` 만 쓰기 때문이다).

1. Firebase 콘솔 → 프로젝트 설정 → iOS 앱 추가(번들 ID `com.kidcare.family`) → `GoogleService-Info.plist` 를 `ios/KidCare/GoogleService-Info.plist` 에 저장
2. 네이버 클라우드 플랫폼 콘솔 → 이미 쓰는 Mobile Dynamic Map 키에 **iOS 번들 ID `com.kidcare.family` 추가** → 그 Key ID 를 `ios/Config/Secrets.xcconfig` 에 적기

---

## File Structure

```
ios/
├─ .gitignore                            빌드 산출물·비밀 파일
├─ project.yml                           XcodeGen 정의. **프로젝트의 정본**
├─ Config/
│  ├─ Base.xcconfig                      커밋됨. Secrets 를 포함하고 Info.plist 로 넘긴다
│  └─ Secrets.xcconfig.example           커밋됨. 빈 템플릿
│  └─ Secrets.xcconfig                   gitignore. 실제 NCP Key ID
├─ KidCare.xcodeproj/                    생성물 — 커밋하지 않는다
├─ KidCare/
│  ├─ KidCareApp.swift                   진입점. Firebase 구성 + 지도 인증 한 자리
│  ├─ RouterView.swift                   첫 화면 분기 (역할·가족 유무)
│  ├─ Info.plist
│  ├─ Localizable.xcstrings              1단계 동안은 한국어만 손으로
│  ├─ Logic/
│  │  └─ InviteCode.swift                6자리 코드 생성·정규화·검증
│  ├─ Core/
│  │  ├─ FirebaseBootstrap.swift         구성과 에뮬레이터 전환이 일어나는 유일한 자리
│  │  ├─ AuthGateway.swift               익명 로그인 (동시 호출 가드)
│  │  ├─ RoleStore.swift                 역할·familyId·childUid 를 UserDefaults 에
│  │  ├─ Documents.swift                 FamilyDoc·MemberDoc·InviteCodeDoc·ChildStatusDoc
│  │  └─ FamilyRepository.swift          createFamily·createInvite·joinFamily·observe*
│  ├─ Onboarding/
│  │  ├─ RoleSelectView.swift            보호자(새 가족/합류) · 아이(안내만)
│  │  ├─ JoinFamilyView.swift            코드 입력 → 합류
│  │  └─ InviteCodeView.swift            코드 발급 (아이용·보호자용)
│  └─ Guardian/
│     ├─ NaverMapView.swift              NMFNaverMapView 를 SwiftUI 로 감싼 것
│     └─ ChildMapView.swift              아이 상태 구독 + 마커 하나
└─ KidCareTests/
   ├─ EmulatorHarness.swift              에뮬레이터 접속과 계정 갈아타기
   ├─ InviteCodeTests.swift
   ├─ DocumentsTests.swift
   └─ GuardianJoinTests.swift            ★ 1단계의 핵심 증명
```

---

### Task 1: 개발 도구 설치와 에뮬레이터 기동

이 맥에는 Xcode 말고 아무것도 없다(Homebrew·Node·Java 전부 없음). Firestore 에뮬레이터는 Java 로 돌고 firebase-tools 는 Node 로 돈다. 뒤 Task 들의 테스트가 전부 에뮬레이터를 상대하므로 이것이 맨 앞이다.

**Files:** 없음 (환경 구성)

**Interfaces:**
- Consumes: 저장소 루트의 `firebase.json`(이미 있다 — auth 9099, firestore 8080), `firestore.rules`
- Produces: `firebase emulators:start` 로 뜨는 로컬 Auth(9099)·Firestore(8080)

- [ ] **Step 1: Homebrew 설치 — 사용자가 직접 실행한다**

관리자 비밀번호를 묻기 때문에 사람이 직접 돌려야 한다.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

설치가 끝나면 화면이 안내하는 `eval "$(/opt/homebrew/bin/brew shellenv)"` 줄을 `~/.zprofile` 에 넣으라는 지시까지 따라간다.

- [ ] **Step 2: Java · Node · XcodeGen 설치**

Java 는 Firestore 에뮬레이터가, Node 는 firebase-tools 가 쓴다. XcodeGen 은 `.xcodeproj` 를
`project.yml` 에서 만들어 준다 — **이게 없으면 프로젝트 생성과 패키지 추가가 전부 Xcode
GUI 조작이 되어 자동화가 끊긴다.**

```bash
brew install openjdk@21 node xcodegen
```

- [ ] **Step 3: Java 를 시스템이 찾을 수 있게 연결 — 사용자가 직접 실행한다**

`/Library/Java/JavaVirtualMachines` 는 sudo 가 필요하다.

```bash
sudo ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk
```

- [ ] **Step 4: Java 가 보이는지 확인**

Run: `java -version`
Expected: `openjdk version "21...` 이 출력된다. `Unable to locate a Java Runtime` 이 나오면 Step 3 이 안 끝난 것이다.

- [ ] **Step 5: firebase-tools 설치**

```bash
npm install -g firebase-tools
```

- [ ] **Step 6: 에뮬레이터를 띄운다**

```bash
cd /Users/com/work/KidCare && firebase emulators:start --only auth,firestore --project kidcare-emulator
```

처음 실행이면 Firestore 에뮬레이터 jar 를 내려받느라 1~2분 걸린다. 뜬 채로 둔다 — 뒤 Task 들이 이걸 쓴다.

- [ ] **Step 7: 두 포트가 실제로 응답하는지 확인**

다른 터미널에서:

```bash
curl -s -o /dev/null -w "firestore=%{http_code}\n" http://127.0.0.1:8080/ && curl -s -o /dev/null -w "auth=%{http_code}\n" http://127.0.0.1:9099/
```

Expected: 둘 다 200. 연결 거부가 나오면 에뮬레이터가 안 뜬 것이다.

- [ ] **Step 8: 규칙이 실제로 실린 프로젝트인지 확인**

Run: 에뮬레이터를 띄운 터미널의 출력에서 `firestore: Rules updated` 또는 rules 파일 경로가 보이는지 확인한다.
Expected: `firestore.rules` 가 로드됐다는 줄이 있다. 없으면 `firebase.json` 이 있는 디렉터리에서 실행하지 않은 것이다.

이 Task 는 커밋하지 않는다 — 저장소에 남는 변경이 없다.

---

### Task 2: 프로젝트 뼈대와 비밀 주입

**Files:**
- Create: `ios/.gitignore`
- Create: `ios/project.yml` (XcodeGen 정의 — 이것이 프로젝트의 정본이다)
- Create: `ios/Config/Base.xcconfig`, `ios/Config/Secrets.xcconfig.example`
- Create: `ios/KidCare/KidCareApp.swift`, `ios/KidCare/RouterView.swift`
- Create: `ios/KidCareTests/SmokeTests.swift`
- Modify: `.gitignore` (루트 — iOS 비밀 파일 추가)

**Interfaces:**
- Consumes: Task 1 의 `xcodegen`
- Produces: `xcodegen generate` 로 만들어지는 `ios/KidCare.xcodeproj`, 그 위에서 도는 `xcodebuild test`. Info.plist 의 `NMFNcpKeyId` 가 빌드 설정 `NAVER_MAP_NCP_KEY_ID` 에서 채워진다.

> **`.xcodeproj` 를 커밋하지 않고 `project.yml` 을 커밋한다.** `project.pbxproj` 는 파일을
> 하나 더할 때마다 바뀌어서 병합 충돌의 상설 무대가 되고, 사람이 읽고 고칠 수 있는 형식도
> 아니다. `project.yml` 한 장이면 타깃·의존성·빌드 설정이 전부 한눈에 보이고, 프로젝트는
> 언제든 다시 만들 수 있다.

- [ ] **Step 1: 폴더를 만든다**

```bash
mkdir -p /Users/com/work/KidCare/ios/{Config,KidCare/{Logic,Core,Onboarding,Guardian},KidCareTests}
```

- [ ] **Step 2: `ios/project.yml` 을 쓴다**

```yaml
name: KidCare

options:
  bundleIdPrefix: com.kidcare
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true

configFiles:
  Debug: Config/Base.xcconfig
  Release: Config/Base.xcconfig

packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk
    from: 12.0.0
  # 안드로이드가 쓰는 버전과 정확히 같은 값이다(gradle/libs.versions.toml 의 naverMap).
  # 버전이 갈리면 타일과 좌표계 차이로 두 폰이 같은 자리를 다르게 그리는 날이 온다.
  NMapsMap:
    url: https://github.com/navermaps/SPM-NMapsMap
    exactVersion: 3.23.3

targets:
  KidCare:
    type: application
    platform: iOS
    sources:
      - path: KidCare
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kidcare.family
        GENERATE_INFOPLIST_FILE: "NO"
        SWIFT_VERSION: "6.0"
        TARGETED_DEVICE_FAMILY: "1"
    info:
      path: KidCare/Info.plist
      properties:
        CFBundleDisplayName: 우리아이 지킴이
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        # 네이버 SDK 가 이 이름 그대로 읽는다. 값은 Base.xcconfig → Secrets.xcconfig 에서 온다.
        NMFNcpKeyId: $(NAVER_MAP_NCP_KEY_ID)
    dependencies:
      - package: Firebase
        product: FirebaseAuth
      - package: Firebase
        product: FirebaseFirestore
      - package: NMapsMap
        product: NMapsMap

  KidCareTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: KidCareTests
    dependencies:
      - target: KidCare

schemes:
  KidCare:
    build:
      targets:
        KidCare: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - KidCareTests
```

- [ ] **Step 3: `ios/.gitignore` 를 쓴다**

```gitignore
# 생성물. project.yml 이 정본이라 .xcodeproj 는 커밋하지 않는다.
KidCare.xcodeproj/
build/
DerivedData/
*.xcuserstate
xcuserdata/

# 비밀. 안드로이드의 local.properties 와 같은 대우다 — 저장소에는 키도 값도 남지 않는다.
Config/Secrets.xcconfig
KidCare/GoogleService-Info.plist

.DS_Store
```

- [ ] **Step 4: 루트 `.gitignore` 에도 두 줄 더한다**

루트에서 실수로 `git add -A` 를 해도 막히게 하려는 것이다. `google-services.json` 줄 바로 아래에 `GoogleService-Info.plist` 와 `Secrets.xcconfig` 를 넣는다.

Run: `grep -n "GoogleService-Info.plist" /Users/com/work/KidCare/.gitignore`
Expected: 한 줄이 나온다.

- [ ] **Step 5: xcconfig 두 벌을 만든다**

`ios/Config/Secrets.xcconfig.example` (커밋됨):

```
// 이 파일을 Secrets.xcconfig 로 복사하고 값을 채운다. Secrets.xcconfig 는 커밋되지 않는다.
// 네이버 클라우드 플랫폼 Mobile Dynamic Map 의 Key ID. 번들 ID 로 제한된 값이라
// Secret 이 아니지만, 저장소에 두면 남의 앱이 우리 할당량을 태울 수 있어 빼 둔다.
NAVER_MAP_NCP_KEY_ID =
```

`ios/Config/Base.xcconfig` (커밋됨):

```
// Secrets.xcconfig 가 없어도 빌드는 되게 한다 — 키스토어가 없는 기계에서 안드로이드
// assembleDebug 가 도는 것과 같은 이유다. 대신 키가 비면 지도를 켜는 순간 크게
// 실패한다(KidCareApp 의 검사). 조용히 빈 지도를 보여주는 것이 최악이다.
#include? "Secrets.xcconfig"

NAVER_MAP_NCP_KEY_ID = $(inherited)
```

- [ ] **Step 6: 앱 진입점과 임시 RouterView 를 쓴다**

`ios/KidCare/KidCareApp.swift`:

```swift
import SwiftUI

@main
struct KidCareApp: App {
    var body: some Scene {
        WindowGroup { RouterView() }
    }
}
```

`ios/KidCare/RouterView.swift`:

```swift
import SwiftUI

/// Task 7 에서 본체로 바뀐다. 지금은 앱이 뜨는지만 본다.
struct RouterView: View {
    var body: some View { Text(verbatim: "KidCare") }
}
```

- [ ] **Step 7: 연기 테스트를 쓴다**

`ios/KidCareTests/SmokeTests.swift`:

```swift
import Testing

/// 테스트 대상과 러너가 실제로 붙어 있는지만 본다. 안드로이드 `SmokeTest` 와 같은 자리다 —
/// 이게 빨간 날은 코드가 아니라 빌드 설정이 깨진 날이다.
struct SmokeTests {
    @Test("테스트 러너가 돈다")
    func 러너가_돈다() {
        #expect(1 + 1 == 2)
    }
}
```

- [ ] **Step 8: 프로젝트를 생성한다**

```bash
cd /Users/com/work/KidCare/ios && xcodegen generate
```

Expected: `Created project at .../ios/KidCare.xcodeproj`

- [ ] **Step 9: 빌드와 테스트를 돌린다**

첫 실행은 Firebase 와 네이버 지도 패키지를 내려받느라 몇 분 걸린다.

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```

Expected: `TEST SUCCEEDED`. 시뮬레이터 이름이 다르면 `xcrun simctl list devices available` 로 확인해 바꾼다.

- [ ] **Step 10: 커밋**

커밋 메시지는 한국어로, 도구·AI 흔적 없이. 담을 내용: project.yml 을 정본으로 두고
.xcodeproj 를 커밋하지 않는 이유(pbxproj 가 병합 충돌의 상설 무대가 된다), 지도 키를
Secrets.xcconfig 에서만 읽는 이유(안드로이드 local.properties 와 같은 대우), 네이버 지도를
안드로이드와 같은 3.23.3 에 못 박는 이유(버전이 갈리면 두 폰이 같은 자리를 다르게 그린다).

```bash
cd /Users/com/work/KidCare && git add ios .gitignore && git commit
```

---

### Task 3: Firebase 붙이고 익명 로그인

**Files:**
- Create: `ios/KidCare/Core/FirebaseBootstrap.swift`
- Create: `ios/KidCare/Core/AuthGateway.swift`
- Create: `ios/KidCareTests/EmulatorHarness.swift`
- Create: `ios/KidCareTests/AuthGatewayTests.swift`
- Modify: `ios/KidCare/KidCareApp.swift`

**Interfaces:**
- Consumes: Task 2 의 프로젝트
- Produces:
  - `FirebaseBootstrap.configureForApp()` / `FirebaseBootstrap.configureForEmulator(projectId: String)`
  - `AuthGateway.currentUid() -> String?`
  - `AuthGateway.signIn() async throws -> String`
  - `EmulatorHarness.start()` / `EmulatorHarness.freshUser() async throws -> String`

- [ ] **Step 1: Firebase 의존성이 이미 들어와 있는지 확인한다**

Task 2 의 `project.yml` 이 `FirebaseAuth` 와 `FirebaseFirestore` 를 이미 선언한다. **둘만
쓰고 Analytics 는 넣지 않는다** — 이 앱은 아무것도 수집하지 않고, 수집 SDK 가 들어가면
나중에 App Store 개인정보 라벨에 적을 것이 생긴다.

Run: `grep -n "FirebaseAuth\|FirebaseFirestore\|FirebaseAnalytics" /Users/com/work/KidCare/ios/project.yml`
Expected: `FirebaseAuth` 와 `FirebaseFirestore` 가 각각 한 번씩 나오고 `FirebaseAnalytics` 는 안 나온다.

- [ ] **Step 2: `FirebaseBootstrap.swift` 를 쓴다**

```swift
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Firebase 구성과 에뮬레이터 전환이 일어나는 **유일한** 자리.
///
/// 두 갈래를 한 파일에 가둔 이유: 에뮬레이터 전환을 부르는 쪽마다 흩어 놓으면
/// 언젠가 한 군데가 빠지고, 그러면 테스트가 **운영 Firestore 에 쓰기 시작한다.**
/// 그 사고는 조용히 성공하기 때문에 아무도 못 알아챈다.
enum FirebaseBootstrap {

    private static var configured = false

    /// 실제 앱용. `GoogleService-Info.plist` 를 읽는다.
    static func configureForApp() {
        guard !configured else { return }
        FirebaseApp.configure()
        configured = true
    }

    /// 테스트용. **plist 가 없어도 돈다** — 그래서 Firebase 콘솔 설정이 끝나기 전에도
    /// Task 4~6 의 테스트를 다 쓸 수 있다. 에뮬레이터는 apiKey 를 검사하지 않는다.
    static func configureForEmulator(projectId: String) {
        guard !configured else { return }
        let options = FirebaseOptions(
            googleAppID: "1:000000000000:ios:0000000000000000",
            gcmSenderID: "000000000000"
        )
        options.projectID = projectId
        options.apiKey = "emulator-does-not-check-this"
        FirebaseApp.configure(options: options)

        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
        Firestore.firestore().useEmulator(withHost: "127.0.0.1", port: 8080)

        // 캐시를 메모리로 둔다. 디스크 캐시가 남으면 다음 테스트가 앞 테스트의
        // 문서를 "서버에 있는 것"으로 착각한다. useEmulator 뒤에 설정을 바꿔야
        // 한다 — 순서가 바뀌면 Firestore 가 "이미 시작됐다"며 막는다.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings

        configured = true
    }
}
```

- [ ] **Step 3: `AuthGateway.swift` 를 쓴다**

안드로이드 `core/AuthGateway.kt` 의 동시 호출 가드를 그대로 옮긴다.

```swift
import FirebaseAuth

/// 익명 로그인. 이 앱의 모든 Firestore 접근이 여기서 받은 uid 로 이뤄진다.
///
/// **동시 호출 가드가 핵심이다.** 화면 둘이 같은 순간에 로그인을 시작하면 익명 계정이
/// 둘 생기고, 그러면 한쪽이 만든 가족을 다른 쪽이 못 읽는다 — 증상은 "가족을 찾을 수
/// 없어요" 인데 원인은 로그인이라 찾는 데 오래 걸린다. actor 로 진입을 하나로 묶는다.
actor AuthGateway {

    static let shared = AuthGateway()

    private var inFlight: Task<String, Error>?

    /// 로그인된 uid. 없으면 nil — 부르는 쪽이 `signIn()` 을 기다릴지 정한다.
    nonisolated static func currentUid() -> String? {
        Auth.auth().currentUser?.uid
    }

    static func signIn() async throws -> String {
        try await shared.signInInternal()
    }

    /// 있으면 그대로, 없으면 로그인해서 uid 를 준다.
    ///
    /// **`currentUid() ?? signIn()` 으로 쓰지 않는 이유**: `??` 의 우변은 async 가 될 수
    /// 없어서 컴파일되지 않는다. 부르는 쪽마다 if-let 을 반복하느니 여기 한 번 둔다.
    static func uid() async throws -> String {
        if let uid = currentUid() { return uid }
        return try await signIn()
    }

    private func signInInternal() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        if let inFlight { return try await inFlight.value }

        let task = Task { () -> String in
            let result = try await Auth.auth().signInAnonymously()
            return result.user.uid
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
```

- [ ] **Step 4: `EmulatorHarness.swift` 를 쓴다**

```swift
import FirebaseAuth
import Foundation
@testable import KidCare

/// 테스트가 에뮬레이터를 상대하게 만들고, 테스트마다 새 익명 계정으로 갈아탄다.
///
/// 계정을 갈아타는 것이 왜 필요한가: 보안 규칙 검증은 "이 uid 가 이 문서를 만들 수
/// 있는가"를 묻는다. 테스트 전부가 한 uid 를 공유하면 앞 테스트에서 이미 멤버가 된
/// 계정으로 "아직 멤버가 아닌 사람"을 흉내 낼 수 없다.
enum EmulatorHarness {

    static let projectId = "kidcare-emulator"

    static func start() {
        FirebaseBootstrap.configureForEmulator(projectId: projectId)
    }

    /// 지금 계정을 버리고 새 익명 계정으로 로그인해 그 uid 를 준다.
    @discardableResult
    static func freshUser() async throws -> String {
        try? Auth.auth().signOut()
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }
}
```

- [ ] **Step 5: 실패하는 테스트를 쓴다**

`ios/KidCareTests/AuthGatewayTests.swift`:

```swift
import Testing
@testable import KidCare

@Suite(.serialized)
struct AuthGatewayTests {

    init() { EmulatorHarness.start() }

    @Test("익명 로그인이 uid 를 준다")
    func 로그인이_uid를_준다() async throws {
        _ = try await EmulatorHarness.freshUser()
        let uid = try await AuthGateway.signIn()
        #expect(!uid.isEmpty)
        #expect(AuthGateway.currentUid() == uid)
    }

    @Test("동시에 불러도 계정이 하나만 생긴다")
    func 동시_호출은_같은_uid를_준다() async throws {
        try? FirebaseAuth.Auth.auth().signOut()
        async let a = AuthGateway.signIn()
        async let b = AuthGateway.signIn()
        async let c = AuthGateway.signIn()
        let uids = try await [a, b, c]
        #expect(Set(uids).count == 1)
    }
}
```

`FirebaseAuth` import 가 빠져 컴파일이 안 된다면 파일 맨 위에 `import FirebaseAuth` 를 더한다.

- [ ] **Step 6: 테스트가 실패하는지 확인**

에뮬레이터가 떠 있는 상태에서:

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/AuthGatewayTests 2>&1 | tail -20
```

Expected: 컴파일 실패(`AuthGateway` 없음) 또는 테스트 실패. Step 2~4 를 아직 안 썼다면 컴파일 실패가 정상이다.

- [ ] **Step 7: Step 2~4 의 파일을 실제로 넣고 다시 돌린다**

Run: Step 6 과 같은 명령
Expected: `TEST SUCCEEDED`, 2개 통과.

- [ ] **Step 8: `KidCareApp.swift` 에서 앱 구성을 부른다**

```swift
import SwiftUI

@main
struct KidCareApp: App {

    init() {
        FirebaseBootstrap.configureForApp()
    }

    var body: some Scene {
        WindowGroup {
            RouterView()
        }
    }
}
```

`RouterView` 의 본체는 Task 7 에서 만든다. 지금은 컴파일이 되도록 임시로 이 파일을 둔다 —
`ios/KidCare/RouterView.swift`:

```swift
import SwiftUI

/// Task 7 에서 본체로 바뀐다. 지금은 앱이 뜨는지만 본다.
struct RouterView: View {
    var body: some View { Text(verbatim: "KidCare") }
}
```

- [ ] **Step 9: 커밋**

```bash
cd /Users/com/work/KidCare && git add ios && git commit -F - <<'MSG'
익명 로그인을 붙인다

동시 호출 가드를 actor 로 둔다. 화면 둘이 같은 순간에 로그인을 시작하면 익명
계정이 둘 생기고, 한쪽이 만든 가족을 다른 쪽이 못 읽는다 — 화면에는 "가족을
찾을 수 없어요" 만 뜨고 원인이 로그인이라는 단서는 아무 데도 안 남는다.

에뮬레이터 전환을 FirebaseBootstrap 한 곳에 가둔다. 부르는 쪽마다 흩어 놓으면
언젠가 한 군데가 빠지고, 그날 테스트가 운영 Firestore 에 쓰기 시작한다. 그
사고는 조용히 성공해서 아무도 못 알아챈다.

테스트용 구성은 GoogleService-Info.plist 없이도 돈다. Firebase 콘솔 설정이
끝나기 전에도 규칙 검증까지 밀고 갈 수 있어야 하기 때문이다.
MSG
```

---

### Task 4: 문서 모델 네 개

**Files:**
- Create: `ios/KidCare/Core/Documents.swift`
- Create: `ios/KidCareTests/DocumentsTests.swift`

**Interfaces:**
- Consumes: 없음 (Foundation만)
- Produces:
  - `struct FamilyDoc`, `struct MemberDoc`, `struct InviteCodeDoc`, `struct ChildStatusDoc`
  - 각각 `init?(_ data: [String: Any])` 와 `var firestoreData: [String: Any]`
  - `enum MemberRole { case guardian, child }` — `rawValue` 는 `"guardian"` / `"child"`

정본은 `app/src/main/java/com/kidcare/family/core/model/Documents.kt` 다. 필드 이름 철자가 하나라도 다르면 안드로이드가 쓴 문서를 못 읽는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`ios/KidCareTests/DocumentsTests.swift`:

```swift
import Testing
@testable import KidCare

struct DocumentsTests {

    @Test("MemberDoc 은 안드로이드가 쓴 필드 이름을 그대로 읽는다")
    func 멤버문서_읽기() throws {
        let doc = try #require(MemberDoc([
            "role": "guardian",
            "displayName": "엄마",
            "fcmToken": "",
            "appVersion": "0.8",
            "updatedAt": Int64(1_757_000_000_000),
            "joinCode": "ABC234",
            "joinedAt": Int64(1_757_000_000_000),
        ]))
        #expect(doc.role == .guardian)
        #expect(doc.displayName == "엄마")
        #expect(doc.joinCode == "ABC234")
    }

    @Test("MemberDoc 쓰기는 선언한 필드만 내보낸다")
    func 멤버문서_쓰기는_필드를_안_늘린다() {
        let doc = MemberDoc(role: .child, displayName: "아이", updatedAt: 1, joinCode: "ABC234", joinedAt: 1)
        let keys = Set(doc.firestoreData.keys)
        // 규칙이 hasOnly() 로 검사하는 자리가 있어 필드가 하나만 더 나가도 쓰기가
        // 통째로 거부된다. 그래서 "무엇이 나가는가"를 테스트로 못 박는다.
        #expect(keys == ["role", "displayName", "fcmToken", "appVersion", "updatedAt", "joinCode", "joinedAt"])
    }

    @Test("ChildStatusDoc 의 wifiOn 은 없으면 nil 이다")
    func 옛문서의_wifiOn은_nil() throws {
        let doc = try #require(ChildStatusDoc([
            "lat": 37.5, "lng": 127.0, "accuracy": 12.0,
            "at": Int64(1_757_000_000_000), "battery": 80, "charging": false,
            "ringerMode": "normal", "lastSeenAt": Int64(1_757_000_000_000),
        ]))
        // false(꺼짐)와 nil(모름)은 다른 말이다 — 안드로이드 주석이 그렇게 못 박았다.
        #expect(doc.wifiOn == nil)
        #expect(doc.lat == 37.5)
    }

    @Test("InviteCodeDoc 의 role 기본값은 child 다")
    func 옛_초대코드는_child로_읽힌다() throws {
        let doc = try #require(InviteCodeDoc([
            "familyId": "F1", "expiresAt": Int64(1_757_000_600_000),
        ]))
        #expect(doc.role == .child)
        #expect(doc.createdByUid == "")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/DocumentsTests 2>&1 | tail -20
```

Expected: 컴파일 실패 — `MemberDoc` 이 없다.

- [ ] **Step 3: `Documents.swift` 를 쓴다**

```swift
import Foundation

/// Firestore 문서와 1:1 로 대응하는 구조체들. 정본은 안드로이드
/// `core/model/Documents.kt` 다 — 필드 이름이 하나라도 어긋나면 안드로이드가
/// 쓴 문서를 못 읽는다.
///
/// **Codable 을 쓰지 않는다.** 규칙이 hasOnly() 로 필드 집합을 검사하는 자리가
/// 있어서, 인코더가 옵셔널 필드를 하나 더 내보내는 순간 쓰기가 통째로 거부된다.
/// 무엇이 나가는지를 눈으로 볼 수 있어야 한다.
///
/// 시각은 전부 UTC 밀리초다.

enum MemberRole: String {
    case guardian
    case child
}

// MARK: - 읽기 도우미
//
// Firestore 는 정수를 NSNumber 로 돌려주는데, 안드로이드가 Long 으로 쓴 값이
// Int64 로 올 때도 Double 로 올 때도 있다. 한 자리에서 흡수한다.
private func millis(_ any: Any?) -> Int64? {
    if let n = any as? NSNumber { return n.int64Value }
    if let i = any as? Int64 { return i }
    if let i = any as? Int { return Int64(i) }
    return nil
}

private func double(_ any: Any?) -> Double? {
    (any as? NSNumber)?.doubleValue
}

struct FamilyDoc {
    var name: String = ""
    var createdAt: Int64 = 0
    var inviteCode: String = ""
    var inviteExpiresAt: Int64 = 0
    var ownerUid: String = ""
    var schemaVersion: Int = 0
    var primaryChildUid: String = ""

    static let currentSchemaVersion = 2

    init(name: String, createdAt: Int64, ownerUid: String, schemaVersion: Int) {
        self.name = name
        self.createdAt = createdAt
        self.ownerUid = ownerUid
        self.schemaVersion = schemaVersion
    }

    init?(_ data: [String: Any]) {
        name = data["name"] as? String ?? ""
        createdAt = millis(data["createdAt"]) ?? 0
        inviteCode = data["inviteCode"] as? String ?? ""
        inviteExpiresAt = millis(data["inviteExpiresAt"]) ?? 0
        ownerUid = data["ownerUid"] as? String ?? ""
        schemaVersion = Int(millis(data["schemaVersion"]) ?? 0)
        primaryChildUid = data["primaryChildUid"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "name": name,
            "createdAt": createdAt,
            "inviteCode": inviteCode,
            "inviteExpiresAt": inviteExpiresAt,
            "ownerUid": ownerUid,
            "schemaVersion": schemaVersion,
            "primaryChildUid": primaryChildUid,
        ]
    }
}

struct MemberDoc {
    var role: MemberRole
    var displayName: String = ""
    var fcmToken: String = ""      // iOS 는 푸시를 안 쓴다(설계서 §1). 늘 빈 값이다.
    var appVersion: String = ""
    var updatedAt: Int64 = 0
    var joinCode: String = ""
    var joinedAt: Int64 = 0

    init(role: MemberRole, displayName: String, updatedAt: Int64, joinCode: String = "", joinedAt: Int64) {
        self.role = role
        self.displayName = displayName
        self.updatedAt = updatedAt
        self.joinCode = joinCode
        self.joinedAt = joinedAt
    }

    init?(_ data: [String: Any]) {
        guard let raw = data["role"] as? String, let role = MemberRole(rawValue: raw) else { return nil }
        self.role = role
        displayName = data["displayName"] as? String ?? ""
        fcmToken = data["fcmToken"] as? String ?? ""
        appVersion = data["appVersion"] as? String ?? ""
        updatedAt = millis(data["updatedAt"]) ?? 0
        joinCode = data["joinCode"] as? String ?? ""
        joinedAt = millis(data["joinedAt"]) ?? 0
    }

    var firestoreData: [String: Any] {
        [
            "role": role.rawValue,
            "displayName": displayName,
            "fcmToken": fcmToken,
            "appVersion": appVersion,
            "updatedAt": updatedAt,
            "joinCode": joinCode,
            "joinedAt": joinedAt,
        ]
    }
}

struct InviteCodeDoc {
    var familyId: String
    var expiresAt: Int64
    var role: MemberRole = .child   // 빈 값은 옛 자녀 코드다
    var createdByUid: String = ""

    init(familyId: String, expiresAt: Int64, role: MemberRole, createdByUid: String) {
        self.familyId = familyId
        self.expiresAt = expiresAt
        self.role = role
        self.createdByUid = createdByUid
    }

    init?(_ data: [String: Any]) {
        guard let familyId = data["familyId"] as? String else { return nil }
        self.familyId = familyId
        expiresAt = millis(data["expiresAt"]) ?? 0
        role = MemberRole(rawValue: data["role"] as? String ?? "child") ?? .child
        createdByUid = data["createdByUid"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "familyId": familyId,
            "expiresAt": expiresAt,
            "role": role.rawValue,
            "createdByUid": createdByUid,
        ]
    }
}

/// children/{childUid} — 아이 폰의 현재 상태. 1단계는 지도 마커에 필요한 것만 읽는다.
/// 이 구조체는 **읽기 전용이다** — 보호자 앱은 이 문서를 쓰지 않는다.
struct ChildStatusDoc {
    var lat: Double
    var lng: Double
    var accuracy: Double
    var at: Int64
    var battery: Int
    var charging: Bool
    var ringerMode: String
    var dnd: String
    var network: String
    /// **false(꺼짐)와 nil(모름)은 다른 말이다.** 옛 문서에는 이 칸이 아예 없다.
    var wifiOn: Bool?
    var lastSeenAt: Int64

    init?(_ data: [String: Any]) {
        guard let lat = double(data["lat"]), let lng = double(data["lng"]) else { return nil }
        self.lat = lat
        self.lng = lng
        accuracy = double(data["accuracy"]) ?? 0
        at = millis(data["at"]) ?? 0
        battery = Int(millis(data["battery"]) ?? -1)
        charging = data["charging"] as? Bool ?? false
        ringerMode = data["ringerMode"] as? String ?? "normal"
        dnd = data["dnd"] as? String ?? ""
        network = data["network"] as? String ?? ""
        wifiOn = data["wifiOn"] as? Bool
        lastSeenAt = millis(data["lastSeenAt"]) ?? 0
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인**

Run: Step 2 와 같은 명령
Expected: `TEST SUCCEEDED`, 4개 통과.

- [ ] **Step 5: 커밋**

```bash
cd /Users/com/work/KidCare && git add ios && git commit -F - <<'MSG'
문서 모델 넷을 옮긴다

Codable 을 쓰지 않고 손으로 맵을 만든다. 규칙이 hasOnly() 로 필드 집합을
검사하는 자리가 있어서, 인코더가 옵셔널 필드를 하나 더 내보내면 쓰기가 통째로
거부된다. 실패는 화면에 "저장이 안 돼요" 한 줄로만 보여서 원인을 찾는 데
오래 걸린다. 무엇이 나가는지를 테스트로 못 박아 둔다.

wifiOn 은 Bool? 이다. 안드로이드가 그렇게 둔 이유를 그대로 지킨다 — 꺼짐과
모름은 다른 말이고, 옛 문서에는 이 칸이 아예 없다.

정수는 NSNumber 를 거쳐 읽는다. 안드로이드가 Long 으로 쓴 값이 Int64 로 올
때도 Double 로 올 때도 있어서, 한 자리에서 흡수하지 않으면 필드마다 갈린다.
MSG
```

---

### Task 5: InviteCode 포팅

**Files:**
- Create: `ios/KidCare/Logic/InviteCode.swift`
- Create: `ios/KidCareTests/InviteCodeTests.swift`

**Interfaces:**
- Consumes: 없음 (Foundation만)
- Produces:
  - `InviteCode.alphabet: String`, `InviteCode.length: Int`
  - `InviteCode.generate(using: inout some RandomNumberGenerator) -> String`
  - `InviteCode.generate() -> String`
  - `InviteCode.normalize(_ raw: String) -> String`
  - `InviteCode.isValid(_ raw: String) -> Bool`
  - `struct SeededGenerator: RandomNumberGenerator` (테스트 전용이 아니라 본체에 둔다 — `generate(using:)` 의 의미를 고정하는 유일한 방법이다)

정본은 `app/src/main/java/com/kidcare/family/logic/InviteCode.kt` 다.

> **주의: 생성 결과는 안드로이드와 같지 않다.** Kotlin `Random(seed)` 와 Swift 의 난수기는 알고리즘이 달라 같은 시드에서 같은 코드가 나올 수 없다. 그래서 2단계의 골든 파일 대조에서도 `generate` 는 제외한다 — 대조할 수 있는 것은 `normalize` 와 `isValid` 뿐이고, 그 둘이 **서로 다른 폰이 같은 코드를 같게 읽는가**를 결정하는 자리라 실제로 중요한 것도 그 둘이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`ios/KidCareTests/InviteCodeTests.swift` — 안드로이드 `InviteCodeTest.kt` 8개를 그대로 옮긴다.

```swift
import Testing
@testable import KidCare

struct InviteCodeTests {

    @Test("코드는 6자리다")
    func 코드는_6자리다() {
        var rng = SeededGenerator(seed: 1)
        #expect(InviteCode.generate(using: &rng).count == 6)
    }

    @Test("코드는 헷갈리는 글자를 쓰지 않는다")
    func 헷갈리는_글자를_안_쓴다() {
        // 0/O, 1/I/L 은 손으로 옮겨 적을 때 잘못 읽힌다.
        for seed in 0..<500 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let code = InviteCode.generate(using: &rng)
            for c in code {
                #expect(!"01OIL".contains(c), "생성된 코드에 \(c) 가 들어있다: \(code)")
            }
        }
    }

    @Test("생성된 코드는 항상 유효하다")
    func 생성된_코드는_유효하다() {
        for seed in 0..<500 {
            var rng = SeededGenerator(seed: UInt64(seed))
            #expect(InviteCode.isValid(InviteCode.generate(using: &rng)))
        }
    }

    @Test("같은 시드는 같은 코드를 만든다")
    func 같은_시드는_같은_코드() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        #expect(InviteCode.generate(using: &a) == InviteCode.generate(using: &b))
    }

    @Test("소문자와 공백과 하이픈을 받아준다")
    func 소문자_공백_하이픈() {
        #expect(InviteCode.normalize(" abc-234 ") == "ABC234")
    }

    @Test("헷갈리는 글자를 교정한다")
    func 헷갈리는_글자를_교정한다() {
        // 0 과 O 는 둘 다 알파벳 밖이라 O -> 0 이 아니라 가까운 대체를 정해 둔다.
        #expect(InviteCode.normalize("aObcde") == "AQBCDE")
        #expect(InviteCode.normalize("023456") == "Q23456")
        #expect(InviteCode.normalize("I23456") == "J23456")
        #expect(InviteCode.normalize("l23456") == "J23456")
    }

    @Test("길이가 다르면 무효다")
    func 길이가_다르면_무효() {
        #expect(!InviteCode.isValid("ABC23"))
        #expect(!InviteCode.isValid("ABC2345"))
        #expect(!InviteCode.isValid(""))
    }

    @Test("알파벳에 없는 글자가 남으면 무효다")
    func 알파벳_밖_글자는_무효() {
        #expect(!InviteCode.isValid("가나다라마바"))
        #expect(!InviteCode.isValid("ABC@34"))
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/InviteCodeTests 2>&1 | tail -20
```

Expected: 컴파일 실패 — `InviteCode` 가 없다.

- [ ] **Step 3: `InviteCode.swift` 를 쓴다**

```swift
import Foundation

/// 페어링용 6자리 초대 코드.
///
/// 부모 폰 화면에 뜬 코드를 사람이 눈으로 읽어 다른 폰에 옮겨 적는다. 그래서
/// 0/O, 1/I/L 처럼 화면에서 헷갈리는 글자를 알파벳에서 빼고, 사용자가 그런 글자를
/// 입력하면 조용히 교정한다.
///
/// 정본은 안드로이드 `logic/InviteCode.kt` 다. **생성 결과는 안드로이드와 다르다** —
/// 난수기 알고리즘이 달라 같은 시드에서 같은 코드가 나올 수 없다. 두 폰이 맞아야
/// 하는 것은 생성이 아니라 `normalize`·`isValid` 다(한쪽이 만든 코드를 다른 쪽이
/// 같게 읽어야 한다).
enum InviteCode {

    /// 0, 1, O, I, L 을 뺀 31글자.
    static let alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

    static let length = 6

    /// 사용자가 잘못 입력하기 쉬운 글자 → 알파벳 안의 대체 글자.
    private static let corrections: [Character: Character] = [
        "0": "Q", "O": "Q",
        "1": "J", "I": "J", "L": "J",
    ]

    static func generate(using generator: inout some RandomNumberGenerator) -> String {
        let letters = Array(alphabet)
        return String((0..<length).map { _ in letters.randomElement(using: &generator)! })
    }

    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(using: &rng)
    }

    /// 대문자화 → 공백·하이픈 제거 → 헷갈리는 글자 교정.
    static func normalize(_ raw: String) -> String {
        String(
            raw.uppercased()
                .filter { !$0.isWhitespace && $0 != "-" }
                .map { corrections[$0] ?? $0 }
        )
    }

    static func isValid(_ raw: String) -> Bool {
        let code = normalize(raw)
        return code.count == length && code.allSatisfy { alphabet.contains($0) }
    }
}

/// 시드를 주면 늘 같은 수열을 내는 난수기. SplitMix64 다.
///
/// 테스트 폴더가 아니라 여기 두는 이유: `generate(using:)` 이 "주어진 난수기를
/// 그대로 쓴다"는 것을 보증하는 유일한 방법이 결정적 난수기로 그 성질을
/// 확인하는 것이라, 이 타입이 곧 그 API 의 의미다.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인**

Run: Step 2 와 같은 명령
Expected: `TEST SUCCEEDED`, 8개 통과.

- [ ] **Step 5: 커밋**

```bash
cd /Users/com/work/KidCare && git add ios && git commit -F - <<'MSG'
초대 코드를 옮긴다

안드로이드 테스트 여덟을 그대로 가져와 먼저 빨갛게 두고 통과시켰다. 옮긴 것이
맞는지를 눈으로 대조하지 않기 위해서다.

생성 결과는 안드로이드와 같지 않다. 난수기 알고리즘이 달라 같은 시드에서 같은
코드가 나올 수 없다. 두 폰이 맞아야 하는 것은 생성이 아니라 normalize 와
isValid 다 — 한쪽이 만든 코드를 다른 쪽이 같게 읽어야 하는 것이지, 같은 코드를
만들 필요는 없다.

시드 난수기를 테스트 폴더가 아니라 본체에 둔다. generate(using:) 이 주어진
난수기를 그대로 쓴다는 것을 확인할 방법이 이것뿐이라, 이 타입이 곧 그 API 의
의미다.
MSG
```

---

### Task 6: FamilyRepository 와 보호자 합류 규칙 검증 ★

이 Task 가 1단계의 존재 이유다. **"아이폰 보호자가 기존 가족에 합류할 수 있는가"를 보안 규칙 상대로 증명한다.**

**Files:**
- Create: `ios/KidCare/Core/FamilyRepository.swift`
- Create: `ios/KidCareTests/GuardianJoinTests.swift`

**Interfaces:**
- Consumes: `AuthGateway`, `Documents.swift` 의 네 구조체, `InviteCode`, `EmulatorHarness`
- Produces:
  - `FamilyRepository.serverNow(familyId: String?, uid: String?) async -> Int64`
  - `FamilyRepository.createFamily(guardianUid: String) async throws -> String`
  - `FamilyRepository.createInvite(familyId: String, role: MemberRole, previousCode: String?) async throws -> InviteCodeInfo`
  - `FamilyRepository.joinFamily(code: String, uid: String, expectedRole: MemberRole, displayName: String) async throws -> JoinResult`
  - `FamilyRepository.observeChildStatus(familyId: String, childUid: String, onChange: @escaping (ChildStatusDoc?) -> Void, onError: @escaping (Error) -> Void) -> ListenerRegistration`
  - `FamilyRepository.findChildUid(familyId: String, preferred: String?) async throws -> String?`
  - `struct InviteCodeInfo { let code: String; let expiresAt: Int64; let role: MemberRole }`
  - `struct JoinResult { let familyId: String; let role: MemberRole }`
  - `enum PairingError: Error { case notFound, offline, expired, wrongRole }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`ios/KidCareTests/GuardianJoinTests.swift`:

```swift
import FirebaseFirestore
import Testing
@testable import KidCare

/// 보안 규칙 상대의 통합 테스트. 에뮬레이터가 떠 있어야 돈다.
///
/// `.serialized` 인 이유: 익명 계정을 갈아타며 "누가 요청했는가"를 바꾸는 테스트라
/// 병렬로 돌면 서로의 로그인 상태를 덮어쓴다.
@Suite(.serialized)
struct GuardianJoinTests {

    init() { EmulatorHarness.start() }

    @Test("보호자가 가족을 만들면 자기 멤버 문서가 생긴다")
    func 가족_생성() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)

        let snap = try await Firestore.firestore()
            .collection("families").document(familyId)
            .collection("members").document(owner).getDocument()
        let member = try #require(MemberDoc(snap.data() ?? [:]))
        #expect(member.role == .guardian)
    }

    @Test("★ 두 번째 보호자가 보호자 코드로 같은 가족에 합류한다")
    func 보호자_합류() async throws {
        // 첫 보호자(안드로이드 폰 역할)가 가족을 만들고 보호자용 코드를 발급한다.
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(
            familyId: familyId, role: .guardian, previousCode: nil
        )
        #expect(invite.role == .guardian)

        // 아이폰 역할: 완전히 다른 익명 계정으로 갈아탄 뒤 그 코드로 합류한다.
        let iphone = try await EmulatorHarness.freshUser()
        #expect(iphone != owner)

        let result = try await FamilyRepository.joinFamily(
            code: invite.code, uid: iphone, expectedRole: .guardian, displayName: "아빠"
        )
        #expect(result.familyId == familyId)
        #expect(result.role == .guardian)

        // 규칙이 실제로 통과시켰는지 문서로 확인한다 — 반환값만 보면 거짓말일 수 있다.
        let snap = try await Firestore.firestore()
            .collection("families").document(familyId)
            .collection("members").document(iphone).getDocument()
        let member = try #require(MemberDoc(snap.data() ?? [:]))
        #expect(member.role == .guardian)
        #expect(member.joinCode == invite.code)
    }

    @Test("합류한 보호자는 가족의 멤버 목록을 읽을 수 있다")
    func 합류한_보호자가_멤버를_읽는다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .guardian, previousCode: nil)

        let iphone = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(code: invite.code, uid: iphone, expectedRole: .guardian, displayName: "아빠")

        let members = try await Firestore.firestore()
            .collection("families").document(familyId).collection("members").getDocuments()
        #expect(members.documents.count == 2)
    }

    @Test("자녀용 코드로 보호자가 되려 하면 막힌다")
    func 역할이_다른_코드는_거부된다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let childInvite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)

        let iphone = try await EmulatorHarness.freshUser()
        await #expect(throws: PairingError.wrongRole) {
            _ = try await FamilyRepository.joinFamily(
                code: childInvite.code, uid: iphone, expectedRole: .guardian, displayName: "아빠"
            )
        }
    }

    @Test("없는 코드는 notFound 다")
    func 없는_코드() async throws {
        _ = try await EmulatorHarness.freshUser()
        await #expect(throws: PairingError.notFound) {
            _ = try await FamilyRepository.joinFamily(
                code: "ZZZZZZ", uid: AuthGateway.currentUid()!, expectedRole: .guardian, displayName: "아빠"
            )
        }
    }

    @Test("합류하면 쓴 코드가 지워진다")
    func 쓴_코드는_지워진다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .guardian, previousCode: nil)

        let iphone = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(code: invite.code, uid: iphone, expectedRole: .guardian, displayName: "아빠")

        let snap = try await Firestore.firestore().collection("inviteCodes").document(invite.code).getDocument()
        #expect(!snap.exists)
    }
}
```

- [ ] **Step 2: 에뮬레이터를 띄운 채 테스트가 실패하는지 확인**

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/GuardianJoinTests 2>&1 | tail -20
```

Expected: 컴파일 실패 — `FamilyRepository` 가 없다.

- [ ] **Step 3: `FamilyRepository.swift` 를 쓴다**

```swift
import FirebaseFirestore
import Foundation

struct InviteCodeInfo {
    let code: String
    let expiresAt: Int64
    let role: MemberRole
}

struct JoinResult {
    let familyId: String
    let role: MemberRole
}

enum PairingError: Error, Equatable {
    case notFound
    case offline
    case expired
    case wrongRole
}

/// 가족 문서와 멤버·초대 코드를 다룬다. 정본은 안드로이드 `core/FamilyRepository.kt` 다.
enum FamilyRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static let inviteTtlMillis: Int64 = 10 * 60 * 1000
    private static let measureTimeoutNanos: UInt64 = 15_000_000_000

    /// 기기 시계와 서버 시계의 차이(밀리초). 서버가 앞서면 양수다.
    /// 프로세스당 한 번만 재고 캐시한다.
    nonisolated(unsafe) private static var serverOffsetMillis: Int64?

    private static func deviceNow() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// 서버 기준 "지금"(UTC 밀리초).
    ///
    /// 초대 코드의 만료는 기기 시계로 쓰는데 보안 규칙은 서버 시각으로 검사한다.
    /// 폰 시계가 15분 느리면 **만들자마자 죽은 코드**가 되고, 재발급해도 같은 시계를
    /// 쓰므로 영원히 죽은 코드만 나온다 — 화면에는 "만료됨"만 뜨고 원인은 아무 데도
    /// 안 남는다.
    static func serverNow(familyId: String?, uid: String?) async -> Int64 {
        if let offset = serverOffsetMillis { return deviceNow() + offset }

        let measured: Int64?
        do {
            measured = try await withThrowingTaskGroup(of: Int64.self) { group in
                group.addTask { try await measureServerOffset(familyId: familyId, uid: uid) }
                group.addTask {
                    try await Task.sleep(nanoseconds: measureTimeoutNanos)
                    throw PairingError.offline
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch is CancellationError {
            // 부른 쪽이 취소된 정상 종료다. 값을 캐시하지 않고 기기 시계를 준다.
            return deviceNow()
        } catch {
            measured = nil
        }

        guard let offset = measured else {
            // 시간 초과는 **캐시하지 않는다.** 0 을 굳히면 그 뒤 초대 코드 만료가
            // 전부 기기 시계로 계산돼 "만들자마자 죽은 코드"가 되살아난다.
            return deviceNow()
        }
        serverOffsetMillis = offset
        return deviceNow() + offset
    }

    /// members/{uid} 의 updatedAt 에 서버 타임스탬프를 쓰고 **서버에서** 다시 읽는다.
    /// 아직 멤버가 아니면 규칙이 막으므로 실패하고, 부르는 쪽이 기기 시계로 물러난다.
    private static func measureServerOffset(familyId: String?, uid: String?) async throws -> Int64 {
        guard let familyId, let uid else { return 0 }
        let ref = db.collection("families").document(familyId).collection("members").document(uid)
        let before = deviceNow()
        try await ref.updateData(["updatedAt": FieldValue.serverTimestamp()])
        let after = deviceNow()
        let snap = try await ref.getDocument(source: .server)
        guard let ts = snap.get("updatedAt") as? Timestamp else { return 0 }
        let serverMillis = Int64(ts.dateValue().timeIntervalSince1970 * 1000)
        // 왕복의 절반을 오차로 보고 중간값을 쓴다 — before 만 쓰면 지연이 클수록
        // 오프셋을 과대평가한다.
        return serverMillis - (before + after) / 2
    }

    /// 가족 문서를 만들고 보호자를 첫 멤버로 넣는다.
    ///
    /// 순서가 중요하다: members/{uid} 를 만들 때 규칙이 families/{id}.ownerUid 를
    /// 대조하므로 가족 문서가 **먼저** 있어야 한다.
    static func createFamily(guardianUid: String) async throws -> String {
        let bootTime = deviceNow()
        let familyRef = db.collection("families").document()

        try await familyRef.setData(
            FamilyDoc(
                name: String(localized: "family_default_name"),
                createdAt: bootTime,
                ownerUid: guardianUid,
                schemaVersion: FamilyDoc.currentSchemaVersion
            ).firestoreData
        )
        try await familyRef.collection("members").document(guardianUid).setData(
            MemberDoc(
                role: .guardian,
                displayName: String(localized: "role_guardian"),
                updatedAt: bootTime,
                joinedAt: bootTime
            ).firestoreData
        )
        return familyRef.documentID
    }

    /// 초대 코드를 발급한다. `previousCode` 를 주면 발급 뒤 그 코드를 지운다.
    static func createInvite(
        familyId: String,
        role: MemberRole,
        previousCode: String?
    ) async throws -> InviteCodeInfo {
        let creatorUid = try await AuthGateway.uid()
        let now = await serverNow(familyId: familyId, uid: creatorUid)
        let expiresAt = now + inviteTtlMillis

        // 6자리 충돌은 드물지만 다른 가족의 살아있는 코드를 덮어쓰면 안 된다.
        // 문서 ID 한 건만 확인하므로 목록 조회 권한도 색인도 필요 없다.
        var code = ""
        for _ in 0..<8 {
            let candidate = InviteCode.generate()
            let existing = try await db.collection("inviteCodes").document(candidate).getDocument()
            if !existing.exists { code = candidate; break }
        }
        guard !code.isEmpty else {
            throw NSError(domain: "KidCare", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "겹치지 않는 초대 코드를 만들지 못했다"])
        }

        try await db.collection("inviteCodes").document(code).setData(
            InviteCodeDoc(familyId: familyId, expiresAt: expiresAt, role: role, createdByUid: creatorUid).firestoreData
        )

        if let previousCode, !previousCode.isEmpty, previousCode != code {
            // 실패해도 넘어간다 — 옛 코드가 남는 것은 만료로 죽지만, 여기서 던지면
            // 방금 발급한 새 코드를 화면이 못 받는다.
            try? await db.collection("inviteCodes").document(previousCode).delete()
        }
        return InviteCodeInfo(code: code, expiresAt: expiresAt, role: role)
    }

    /// 초대 코드로 가족에 합류한다. 아이폰 보호자가 쓰는 주된 경로다.
    static func joinFamily(
        code: String,
        uid: String,
        expectedRole: MemberRole,
        displayName: String
    ) async throws -> JoinResult {
        let normalized = InviteCode.normalize(code)
        let codeRef = db.collection("inviteCodes").document(normalized)
        let codeDoc = try await codeRef.getDocument()

        guard codeDoc.exists else {
            // 없는 게 아니라 **물어볼 수가 없었던** 경우일 수 있다. 오프라인이면 이
            // 읽기는 캐시로 답하는데 이 코드가 캐시에 있을 리 없으므로 똑같이
            // "없음"으로 나온다 — 그러면 "코드가 틀렸다"가 아니라 "인터넷이 안 된다"고
            // 말해야 한다. 안 그러면 멀쩡한 코드를 계속 다시 입력하게 된다.
            throw codeDoc.metadata.isFromCache ? PairingError.offline : PairingError.notFound
        }
        guard let doc = InviteCodeDoc(codeDoc.data() ?? [:]) else { throw PairingError.notFound }
        guard doc.role == expectedRole else { throw PairingError.wrongRole }

        let now = await serverNow(familyId: doc.familyId, uid: uid)
        guard doc.expiresAt > now else { throw PairingError.expired }

        let familyRef = db.collection("families").document(doc.familyId)
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = doc.role == .guardian
            ? String(localized: "role_guardian")
            : String(localized: "role_child")
        let name = trimmed.isEmpty ? fallback : String(trimmed.prefix(20))

        try await familyRef.collection("members").document(uid).setData(
            MemberDoc(role: doc.role, displayName: name, updatedAt: now, joinCode: normalized, joinedAt: now).firestoreData
        )

        try? await codeRef.delete()
        return JoinResult(familyId: doc.familyId, role: doc.role)
    }

    /// 가족의 자녀 uid 하나를 고른다. `preferred` 가 아직 멤버면 그것을 유지한다.
    static func findChildUid(familyId: String, preferred: String?) async throws -> String? {
        let snap = try await db.collection("families").document(familyId)
            .collection("members").whereField("role", isEqualTo: MemberRole.child.rawValue).getDocuments()
        let uids = snap.documents.map(\.documentID).sorted()
        if let preferred, uids.contains(preferred) { return preferred }
        return uids.first
    }

    /// 아이 상태 문서를 구독한다. 돌려받은 등록은 화면이 사라질 때 반드시 remove 한다.
    ///
    /// onError 없이 에러를 삼키면 권한 거부나 리스너 끊김이 나도 화면은 계속 비어
    /// 있기만 하고 아무 데도 단서가 안 남는다 — 이 앱에서 가장 흔한 실패 유형인데
    /// 원인을 알 방법이 없었다(안드로이드 쪽 같은 함수의 주석).
    static func observeChildStatus(
        familyId: String,
        childUid: String,
        onChange: @escaping (ChildStatusDoc?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                guard let data = snapshot?.data() else { onChange(nil); return }
                onChange(ChildStatusDoc(data))
            }
    }
}
```

- [ ] **Step 4: 문구 키 세 개를 `Localizable.xcstrings` 에 넣는다**

`family_default_name` = `우리 가족`, `role_guardian` = `보호자`, `role_child` = `아이`.
Xcode 에서 `Localizable.xcstrings` 를 열어 한국어 값으로 채운다. **하드코딩하지 않는 이유**는 6단계에서 이 파일이 `i18n` 원본에서 통째로 생성되기 때문이다 — 지금 문자열을 코드에 박아두면 그때 14개 언어 중 한국어만 안 바뀌는 자리가 생긴다.

- [ ] **Step 5: `children` 컬렉션 경로가 맞는지 안드로이드와 대조한다**

Run: `grep -rn "collection(\"children\")" /Users/com/work/KidCare/app/src/main/java/com/kidcare/family/core/FamilyRepository.kt`
Expected: `observeChildStatus`·`fetchChildStatus` 가 쓰는 경로가 위 Swift 코드와 같다. 다르면 **안드로이드가 맞다** — Swift 를 고친다.

- [ ] **Step 6: 에뮬레이터를 띄운 채 테스트를 돌린다**

Run: Step 2 와 같은 명령
Expected: `TEST SUCCEEDED`, 6개 전부 통과. 특히 `★ 두 번째 보호자가 보호자 코드로 같은 가족에 합류한다` 가 초록이어야 한다.

**여기서 `PERMISSION_DENIED` 가 나면 그것이 1단계가 찾아내려던 바로 그 문제다.** 규칙을 고쳐야 할 수 있고, 그건 안드로이드에도 영향이 가는 변경이므로 **멈추고 사용자에게 알린다.** 혼자 `firestore.rules` 를 고치지 않는다.

- [ ] **Step 7: 전체 테스트를 한 번 돌린다**

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```

Expected: `TEST SUCCEEDED`. 누적 21개(연기 1 + 인증 2 + 문서 4 + 초대코드 8 + 합류 6).

- [ ] **Step 8: 커밋**

```bash
cd /Users/com/work/KidCare && git add ios && git commit -F - <<'MSG'
가족 저장소를 옮기고, 보호자 합류를 규칙 상대로 증명한다

이 커밋의 핵심은 코드가 아니라 테스트다. "아이폰이 보호자용 코드로 기존 가족에
들어갈 수 있는가"를 에뮬레이터의 진짜 보안 규칙에 대고 물어본다. 규칙은 21KB
짜리고 이 저장소에서 가장 오래 걸린 부분이라, 화면을 만들기 전에 이것부터
확인해야 했다. 반환값만 보면 거짓말일 수 있어서 멤버 문서를 다시 읽어 대조한다.

서버 시각 보정을 그대로 옮긴다. 초대 만료는 기기 시계로 쓰는데 규칙은 서버
시각으로 검사해서, 폰 시계가 느리면 만들자마자 죽은 코드가 나오고 재발급해도
같은 시계를 쓰므로 영원히 죽은 코드만 나온다. 시간 초과로 못 잰 값은 캐시하지
않는다 — 0 을 굳히면 그 증상이 통째로 되살아난다.

없는 코드와 오프라인을 구분한다. 오프라인이면 읽기가 캐시로 답해서 똑같이
"없음"이 되는데, 그때 "코드가 틀렸다"고 말하면 멀쩡한 코드를 계속 다시 입력하게
된다.
MSG
```

---

### Task 7: 역할 선택과 페어링 화면

**Files:**
- Create: `ios/KidCare/Core/RoleStore.swift`
- Create: `ios/KidCare/Onboarding/RoleSelectView.swift`
- Create: `ios/KidCare/Onboarding/JoinFamilyView.swift`
- Create: `ios/KidCare/Onboarding/InviteCodeView.swift`
- Create: `ios/KidCare/RouterView.swift` (Task 3 임시본을 본체로 교체)
- Create: `ios/KidCare/Guardian/ChildMapView.swift` (임시본 — Task 8 이 갈아끼운다)
- Create: `ios/KidCareTests/RoleStoreTests.swift`
- Modify: `ios/KidCare/KidCareApp.swift`

**Interfaces:**
- Consumes: `FamilyRepository`, `AuthGateway`, `InviteCode`, `MemberRole`
- Produces:
  - `final class RoleStore` — `role: MemberRole?`, `familyId: String?`, `childUid: String?`, `clear()`
  - `RoleStore.shared`
  - `RouterView` — 저장된 상태를 보고 `RoleSelectView` 또는 `ChildMapView` 를 연다

- [ ] **Step 1: RoleStore 의 실패하는 테스트를 쓴다**

`ios/KidCareTests/RoleStoreTests.swift`:

```swift
import Testing
@testable import KidCare

struct RoleStoreTests {

    private func 새_저장소() -> RoleStore {
        let suite = "kidcare.test.\(UUID().uuidString)"
        return RoleStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test("빈 저장소는 역할이 없다")
    func 빈_저장소() {
        #expect(새_저장소().role == nil)
    }

    @Test("역할과 가족을 적고 다시 읽는다")
    func 적고_읽는다() {
        let store = 새_저장소()
        store.role = .guardian
        store.familyId = "F1"
        store.childUid = "C1"
        #expect(store.role == .guardian)
        #expect(store.familyId == "F1")
        #expect(store.childUid == "C1")
    }

    @Test("clear 는 전부 지운다")
    func clear가_전부_지운다() {
        let store = 새_저장소()
        store.role = .guardian
        store.familyId = "F1"
        store.clear()
        #expect(store.role == nil)
        #expect(store.familyId == nil)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/RoleStoreTests 2>&1 | tail -20
```

Expected: 컴파일 실패 — `RoleStore` 가 없다.

- [ ] **Step 3: `RoleStore.swift` 를 쓴다**

```swift
import Foundation
import Observation

/// 이 기기가 무엇인지(역할), 어느 가족인지, 어느 아이를 보고 있는지를 기억한다.
///
/// `UserDefaults` 를 주입받는 이유는 테스트 때문만이 아니다 — 기본 저장소를 쓰면
/// 테스트가 시뮬레이터에 남긴 값이 다음 실행의 앱 상태가 된다.
@Observable
final class RoleStore {

    static let shared = RoleStore(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        role = defaults.string(forKey: "role").flatMap(MemberRole.init(rawValue:))
        familyId = defaults.string(forKey: "familyId")
        childUid = defaults.string(forKey: "childUid")
    }

    // **저장 프로퍼티여야 한다.** UserDefaults 를 그때그때 읽는 계산 프로퍼티로 두면
    // @Observable 이 변경을 추적하지 못해서, 합류가 끝나도 RouterView 가 다시 그려지지
    // 않는다 — 화면이 역할 선택에 머문 채로 아무 일도 안 일어난 것처럼 보인다.
    // 값은 읽을 때 한 번 싣고, 쓸 때마다 UserDefaults 로 흘려보낸다.
    var role: MemberRole? { didSet { defaults.set(role?.rawValue, forKey: "role") } }
    var familyId: String? { didSet { defaults.set(familyId, forKey: "familyId") } }
    var childUid: String? { didSet { defaults.set(childUid, forKey: "childUid") } }

    func clear() {
        role = nil
        familyId = nil
        childUid = nil
        for key in ["role", "familyId", "childUid"] { defaults.removeObject(forKey: key) }
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인**

Run: Step 2 와 같은 명령
Expected: `TEST SUCCEEDED`, 3개 통과.

- [ ] **Step 5: `RoleSelectView.swift` 를 쓴다**

```swift
import SwiftUI

/// 첫 실행 화면. 보호자는 두 갈래(새 가족 / 합류)로 갈린다.
///
/// 아이 버튼을 **지우지 않고 안내로 두는 이유**는 설계서 §1 에 있다 — 지우면
/// 나중에 붙일 자리를 되살려야 하고, 흐리게만 두면 왜 안 되는지를 말해주지 못한다.
struct RoleSelectView: View {

    @State private var 보호자_갈래를_묻는다 = false
    @State private var 아이는_안된다고_알린다 = false
    @State private var 합류로_간다 = false
    @State private var 발급으로_간다 = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("role_select_title").font(.title2).bold()

                Button("role_guardian") { 보호자_갈래를_묻는다 = true }
                    .buttonStyle(.borderedProminent)

                Button("role_child") { 아이는_안된다고_알린다 = true }
                    .buttonStyle(.bordered)
            }
            .padding()
            .confirmationDialog("guardian_start_title", isPresented: $보호자_갈래를_묻는다) {
                Button("guardian_start_new_family") { 발급으로_간다 = true }
                Button("guardian_start_join_family") { 합류로_간다 = true }
                Button("dialog_cancel", role: .cancel) {}
            }
            .alert("ios_child_unsupported_title", isPresented: $아이는_안된다고_알린다) {
                Button("dialog_ok", role: .cancel) {}
            } message: {
                Text("ios_child_unsupported_body")
            }
            .navigationDestination(isPresented: $합류로_간다) {
                JoinFamilyView(expectedRole: .guardian)
            }
            .navigationDestination(isPresented: $발급으로_간다) {
                InviteCodeView(mode: .newFamily)
            }
        }
    }
}
```

- [ ] **Step 6: `JoinFamilyView.swift` 를 쓴다**

```swift
import SwiftUI

/// 초대 코드를 입력해 가족에 합류한다. 아이폰 보호자의 주된 입구다.
struct JoinFamilyView: View {

    let expectedRole: MemberRole

    @State private var 입력 = ""
    @State private var 진행중 = false
    @State private var 오류: String?

    private var 보낼_수_있나: Bool { InviteCode.isValid(입력) && !진행중 }

    var body: some View {
        VStack(spacing: 16) {
            Text("join_family_hint")
            TextField("join_family_code_placeholder", text: $입력)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(.largeTitle, design: .monospaced))
                .textFieldStyle(.roundedBorder)

            if let 오류 { Text(오류).foregroundStyle(.red) }

            Button("join_family_submit") { Task { await 합류한다() } }
                .buttonStyle(.borderedProminent)
                .disabled(!보낼_수_있나)
        }
        .padding()
    }

    private func 합류한다() async {
        진행중 = true
        오류 = nil
        defer { 진행중 = false }
        do {
            let uid = try await AuthGateway.uid()
            let result = try await FamilyRepository.joinFamily(
                code: 입력, uid: uid, expectedRole: expectedRole,
                displayName: String(localized: "role_guardian")
            )
            RoleStore.shared.role = result.role
            RoleStore.shared.familyId = result.familyId
            RoleStore.shared.childUid = try await FamilyRepository.findChildUid(
                familyId: result.familyId, preferred: nil
            )
        } catch let e as PairingError {
            오류 = String(localized: 문구키(e))
        } catch {
            오류 = error.localizedDescription
        }
    }

    /// 예외를 화면 문장으로 바꾸는 자리는 여기 하나다. 안드로이드 `ErrorText` 와 같은 역할이고,
    /// 3단계에서 공용 `errorMessage(_:)` 로 옮긴다.
    private func 문구키(_ e: PairingError) -> String.LocalizationValue {
        switch e {
        case .notFound: "pairing_error_not_found"
        case .offline: "pairing_error_offline"
        case .expired: "pairing_error_expired"
        case .wrongRole: "pairing_error_wrong_role"
        }
    }
}
```

- [ ] **Step 7: `InviteCodeView.swift` 를 쓴다**

```swift
import SwiftUI

/// 초대 코드를 발급해 보여준다. 새 가족을 시작할 때와, 이미 있는 가족에 아이나
/// 다른 보호자를 부를 때 같은 화면을 쓴다.
struct InviteCodeView: View {

    enum Mode {
        /// 가족을 새로 만들고 자녀용 코드를 낸다.
        case newFamily
        /// 이미 있는 가족에 이 역할을 부른다.
        case invite(familyId: String, role: MemberRole)
    }

    let mode: Mode

    @State private var 코드: String?
    @State private var 진행중 = true
    @State private var 오류: String?

    var body: some View {
        VStack(spacing: 16) {
            if 진행중 {
                ProgressView()
            } else if let 코드 {
                Text("invite_code_hint")
                Text(코드)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
            } else if let 오류 {
                Text(오류).foregroundStyle(.red)
            }
        }
        .padding()
        .task { await 발급한다() }
    }

    private func 발급한다() async {
        진행중 = true
        defer { 진행중 = false }
        do {
            let uid = try await AuthGateway.uid()
            let (familyId, role): (String, MemberRole)
            switch mode {
            case .newFamily:
                let id = try await FamilyRepository.createFamily(guardianUid: uid)
                RoleStore.shared.role = .guardian
                RoleStore.shared.familyId = id
                (familyId, role) = (id, .child)
            case let .invite(id, r):
                (familyId, role) = (id, r)
            }
            코드 = try await FamilyRepository.createInvite(
                familyId: familyId, role: role, previousCode: nil
            ).code
        } catch {
            오류 = error.localizedDescription
        }
    }
}
```

- [ ] **Step 8: `RouterView.swift` 를 쓴다**

```swift
import SwiftUI

/// 앱을 열었을 때 어디로 갈지 정한다. 안드로이드 `RouterActivity` 와 같은 자리다.
///
/// 판단 재료는 저장소에 있는 것뿐이다 — 네트워크를 기다리지 않는다. 여기서 서버를
/// 물어보면 통신이 느린 날 첫 화면이 통째로 비어 있게 된다.
struct RouterView: View {

    @State private var store = RoleStore.shared

    var body: some View {
        if let familyId = store.familyId, store.role == .guardian {
            ChildMapView(familyId: familyId, childUid: store.childUid)
        } else {
            RoleSelectView()
        }
    }
}
```

`ChildMapView` 의 본체는 Task 8 에서 만든다. **지금 이 파일을 안 만들면 Task 7 이 통째로
컴파일되지 않는다** — 아래 임시본을 `ios/KidCare/Guardian/ChildMapView.swift` 에 둔다.
Task 8 Step 4 가 이 파일을 통째로 갈아끼운다.

```swift
import SwiftUI

/// Task 8 에서 지도로 바뀐다. 지금은 합류가 끝나 화면이 넘어왔는지만 눈으로 본다.
struct ChildMapView: View {
    let familyId: String
    let childUid: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: familyId)
            Text(verbatim: childUid ?? "-")
        }
    }
}
```

- [ ] **Step 9: 문구 키를 `Localizable.xcstrings` 에 넣는다**

한국어 값으로 채운다. **이 문장들은 6단계에서 `i18n` 원본으로 옮겨진다.**

| 키 | 한국어 |
|---|---|
| `role_select_title` | 이 폰은 누구의 폰인가요? |
| `guardian_start_title` | 어떻게 시작할까요? |
| `guardian_start_new_family` | 새 가족 만들기 |
| `guardian_start_join_family` | 가족에 합류하기 |
| `dialog_cancel` | 취소 |
| `dialog_ok` | 확인 |
| `ios_child_unsupported_title` | 아이 폰은 안드로이드만 지원해요 |
| `ios_child_unsupported_body` | 아이 폰에 필요한 소리 전환과 핸드폰 찾기는 아이폰에서 만들 수 없어요. 아이 폰에는 안드로이드용 앱을 설치해 주세요. |
| `join_family_hint` | 다른 폰에 뜬 6자리 코드를 넣어 주세요 |
| `join_family_code_placeholder` | ABC234 |
| `join_family_submit` | 합류하기 |
| `invite_code_hint` | 이 코드를 상대 폰에 넣어 주세요. 10분 동안 쓸 수 있어요. |
| `pairing_error_not_found` | 그런 코드가 없어요. 다시 확인해 주세요. |
| `pairing_error_offline` | 인터넷에 연결되어 있지 않아요. |
| `pairing_error_expired` | 코드가 만료됐어요. 새 코드를 받아 주세요. |
| `pairing_error_wrong_role` | 이 코드는 다른 역할용이에요. |

- [ ] **Step 10: 전체 테스트를 돌린다**

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```

Expected: `TEST SUCCEEDED`, 누적 24개.

- [ ] **Step 11: 커밋**

```bash
cd /Users/com/work/KidCare && git add ios && git commit -F - <<'MSG'
역할 선택과 페어링 화면을 만든다

보호자 갈래를 안드로이드와 같이 둘로 둔다 — 새 가족 만들기와 합류. 합류만
만들면 아이폰만 있는 집은 이 앱을 시작조차 못 한다.

아이 버튼은 보이되 누르면 안내한다. 지우면 나중에 되살려야 하고, 흐리게만 두면
왜 안 되는지를 말해주지 못한다.

RouterView 는 저장소에 있는 값만 보고 판단한다. 여기서 서버를 물어보면 통신이
느린 날 첫 화면이 통째로 비어 있게 된다.

RoleStore 가 UserDefaults 를 주입받는 이유는 테스트 때문만이 아니다. 기본
저장소를 쓰면 테스트가 시뮬레이터에 남긴 값이 다음 실행의 앱 상태가 된다.
MSG
```

---

### Task 8: 네이버 지도와 아이 마커

**여기서부터 사용자가 준비한 두 파일이 필요하다** — `GoogleService-Info.plist` 와 `Secrets.xcconfig` 의 NCP Key ID.

**Files:**
- Create: `ios/KidCare/Guardian/NaverMapView.swift`
- Replace: `ios/KidCare/Guardian/ChildMapView.swift` (Task 7 의 임시본을 통째로 갈아끼운다)
- Modify: `ios/KidCare/KidCareApp.swift` (지도 인증)

**Interfaces:**
- Consumes: `FamilyRepository.observeChildStatus`, `ChildStatusDoc`, `RoleStore`
- Produces: `NaverMapView(center: (lat: Double, lng: Double)?, markerAt: (lat: Double, lng: Double)?)`, `ChildMapView(familyId: String, childUid: String?)`

- [ ] **Step 1: 네이버 지도 의존성이 이미 들어와 있는지 확인한다**

Task 2 의 `project.yml` 이 `exactVersion: 3.23.3` 으로 이미 못 박아 두었다. 안드로이드가
쓰는 버전과 **정확히 같은 값**이다(`gradle/libs.versions.toml` 의 `naverMap = "3.23.3"`).

Run: `grep -n -A2 "NMapsMap:" /Users/com/work/KidCare/ios/project.yml`
Expected: `exactVersion: 3.23.3` 이 보인다.

> **좌표 타입은 다른 모듈에 있다.** `NMGLatLng` 는 `NMapsMap` 이 의존하는 `NMapsGeometry`
> 패키지의 타입이라, `import NMapsMap` 만으로 안 잡히면 `import NMapsGeometry` 를 함께
> 적는다. 이 한 줄 때문에 Task 8 이 컴파일 안 되는 일이 잦다.

- [ ] **Step 2: 앱 시작 때 지도 인증을 건다**

`KidCareApp.swift` 를 고친다.

```swift
import NMapsMap
import SwiftUI

@main
struct KidCareApp: App {

    init() {
        FirebaseBootstrap.configureForApp()

        // 지도 키는 Secrets.xcconfig → Info.plist 를 거쳐 들어온다. 비어 있으면 지도가
        // 조용히 회색 사각형이 되는데, 그 화면은 "인터넷이 안 되나?"로 읽혀서 원인을
        // 찾는 데 오래 걸린다. 그래서 여기서 크게 실패시킨다 — 안드로이드가 릴리스
        // 패키징 직전에 키를 검사하는 것과 같은 판단이다.
        let key = Bundle.main.object(forInfoDictionaryKey: "NMFNcpKeyId") as? String ?? ""
        assert(!key.isEmpty, """
            네이버 지도 NCP Key ID 가 없습니다. ios/Config/Secrets.xcconfig 에
            NAVER_MAP_NCP_KEY_ID = 발급받은_Key_ID 를 넣으세요.
            (Secrets.xcconfig.example 을 복사해 쓰면 됩니다)
            """)
        NMFAuthManager.shared().client = NMFNcpKeyClient(ncpKeyId: key, beta: false)
    }

    var body: some Scene {
        WindowGroup { RouterView() }
    }
}
```

- [ ] **Step 3: `NaverMapView.swift` 를 쓴다**

```swift
import NMapsMap
import SwiftUI

/// 네이버 지도를 SwiftUI 에 끼워 넣는다.
///
/// **지도 뷰를 매번 새로 만들지 않는다.** `makeUIView` 에서 한 번 만들고 `updateUIView`
/// 는 마커와 카메라만 손댄다. 안드로이드가 탭을 바꿀 때 프래그먼트를 replace 하지 않는
/// 것과 같은 이유다 — 지도를 다시 만들면 타일을 처음부터 내려받고, 부모가 옮겨둔
/// 지도 위치도 초기화된다.
struct NaverMapView: UIViewRepresentable {

    var markerAt: (lat: Double, lng: Double)?
    /// 마커가 처음 생겼을 때 한 번만 카메라를 옮긴다. 그 뒤에는 부모가 옮긴 자리를 지킨다.
    @Binding var 카메라를_한번_맞췄나: Bool

    final class Coordinator {
        let marker = NMFMarker()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NMFNaverMapView {
        let view = NMFNaverMapView(frame: .zero)
        view.showLocationButton = false   // 보호자 앱은 위치 권한을 쓰지 않는다(설계서 §1)
        view.showZoomControls = true
        return view
    }

    func updateUIView(_ view: NMFNaverMapView, context: Context) {
        guard let markerAt else {
            context.coordinator.marker.mapView = nil
            return
        }
        let position = NMGLatLng(lat: markerAt.lat, lng: markerAt.lng)
        context.coordinator.marker.position = position
        context.coordinator.marker.mapView = view.mapView

        if !카메라를_한번_맞췄나 {
            view.mapView.moveCamera(NMFCameraUpdate(scrollTo: position))
            DispatchQueue.main.async { 카메라를_한번_맞췄나 = true }
        }
    }
}
```

- [ ] **Step 4: `ChildMapView.swift` 를 쓴다**

```swift
import FirebaseFirestore
import SwiftUI

/// 1단계의 지도 화면. 아이의 마지막 위치 마커 하나만 띄운다.
/// 경로선·타임라인·날짜 이동은 3단계다.
struct ChildMapView: View {

    let familyId: String
    let childUid: String?

    @State private var 상태: ChildStatusDoc?
    @State private var 오류: String?
    @State private var 카메라를_한번_맞췄나 = false
    @State private var 구독: ListenerRegistration?

    var body: some View {
        ZStack(alignment: .top) {
            NaverMapView(
                markerAt: 상태.map { (lat: $0.lat, lng: $0.lng) },
                카메라를_한번_맞췄나: $카메라를_한번_맞췄나
            )
            .ignoresSafeArea()

            if let 오류 {
                Text(오류).padding().background(.thinMaterial).foregroundStyle(.red)
            } else if childUid == nil {
                Text("map_no_child").padding().background(.thinMaterial)
            } else if 상태 == nil {
                Text("map_waiting_first_signal").padding().background(.thinMaterial)
            }
        }
        .onAppear { 구독한다() }
        .onDisappear {
            // 리스너를 안 걷으면 화면을 떠난 뒤에도 읽기가 계속 일어난다. 이 앱은
            // Spark 무료 한도 안에서 도는 것이 전제라 그 누수가 곧 요금이다.
            구독?.remove()
            구독 = nil
        }
    }

    private func 구독한다() {
        guard let childUid, 구독 == nil else { return }
        구독 = FamilyRepository.observeChildStatus(
            familyId: familyId,
            childUid: childUid,
            onChange: { 상태 = $0 },
            onError: { 오류 = $0.localizedDescription }
        )
    }
}
```

- [ ] **Step 5: 문구 키 둘을 더한다**

`map_no_child` = `아직 연결된 아이가 없어요`, `map_waiting_first_signal` = `아직 아이 폰에서 받은 위치가 없어요`

- [ ] **Step 6: `RouterView` 를 건드릴 필요가 없는지 확인한다**

Task 7 에서 이미 `ChildMapView(familyId:childUid:)` 를 부르고 있고 Step 4 가 같은 이름·같은
인자로 갈아끼웠으므로 `RouterView` 는 그대로다.

Run: `grep -n "ChildMapView" /Users/com/work/KidCare/ios/KidCare/RouterView.swift`
Expected: `ChildMapView(familyId: familyId, childUid: store.childUid)` 한 줄이 그대로 있다.

- [ ] **Step 7: 빌드와 테스트**

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```

Expected: `TEST SUCCEEDED`, 누적 24개(지도는 화면이라 단위 테스트를 두지 않는다 — 안드로이드가 "화면과 서비스는 실기기로 검증한다"고 정한 것과 같다).

- [ ] **Step 8: 시뮬레이터에서 실제로 띄워 눈으로 본다**

앱을 실행해 지도 타일이 실제로 그려지는지 본다. 회색 사각형만 나오면 NCP Key ID 에 iOS 번들 ID 가 등록되지 않은 것이다 — 콘솔 로그에 네이버 SDK 의 인증 실패 메시지가 남는다.

- [ ] **Step 9: 실기기 왕복 확인 — 사람이 한다**

이것이 1단계의 진짜 합격선이다.

1. 안드로이드 보호자 폰에서 **보호자 초대 코드**를 발급한다
2. 아이폰에서 앱을 열고 → 보호자 → 가족에 합류하기 → 그 코드를 넣는다
3. 지도에 그 가족 아이의 마지막 위치 마커가 뜨는지 본다

Expected: 마커가 뜬다. 안 뜨면 아이 폰이 아직 한 번도 위치를 올린 적이 없는 경우일 수 있다 — 안드로이드 보호자 화면에서 '지금 위치 확인'을 한 번 눌러 상태 문서를 만든 뒤 다시 본다.

- [ ] **Step 10: 커밋**

```bash
cd /Users/com/work/KidCare && git add ios && git commit -F - <<'MSG'
지도를 붙이고 아이 마커를 띄운다

네이버 지도를 안드로이드와 같은 3.23.3 에 못 박는다. 버전이 갈리면 타일과
좌표계 차이로 두 폰이 같은 자리를 다르게 그리는 날이 온다.

지도 키가 비면 시작할 때 크게 실패시킨다. 키가 없으면 지도는 조용히 회색
사각형이 되는데, 그 화면은 "인터넷이 안 되나?"로 읽혀서 원인을 찾는 데 오래
걸린다. 안드로이드가 릴리스 패키징 직전에 키를 검사하는 것과 같은 판단이다.

지도 뷰는 한 번만 만들고 그 뒤에는 마커와 카메라만 손댄다. 다시 만들면 타일을
처음부터 내려받고 부모가 옮겨둔 자리도 초기화된다.

화면을 떠날 때 리스너를 걷는다. 이 앱은 Spark 무료 한도 안에서 도는 것이
전제라 구독 누수가 곧 요금이다.
MSG
```

---

## 1단계 완료 기준

- [ ] `xcodebuild test` 가 초록이고 테스트 24개가 통과한다
- [ ] `GuardianJoinTests` 의 `★ 두 번째 보호자가 보호자 코드로 같은 가족에 합류한다` 가 에뮬레이터의 진짜 `firestore.rules` 상대로 통과한다
- [ ] 안드로이드 폰에서 발급한 보호자 코드로 실제 아이폰이 가족에 합류한다
- [ ] 그 아이폰 지도에 아이 마커가 뜬다
- [ ] `git status` 가 깨끗하고, `GoogleService-Info.plist` 와 `Secrets.xcconfig` 가 커밋되지 않았다
- [ ] `app/` 아래 파일이 하나도 안 바뀌었다 (`git diff --stat main -- app/` 가 비어 있다)
