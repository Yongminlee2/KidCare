# iOS 7단계 구현 계획 — 출시 준비(개인정보 매니페스트, 심사 대비, 로컬 아카이브까지)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰 보호자 앱을 "가족에게 TestFlight 로 나눠줄 수 있고, 나중에 App Store 심사에 그대로 낼 수 있는" 상태로 만든다. 끝은 **로컬에서 검증한 `.xcarchive`·`.ipa`, 실기기 Release 읽기 확인, 그리고 사람이 할 일 목록**이다. App Store Connect 에 올리거나 앱 레코드를 만드는 일은 이 계획서에 없다.

**Architecture:** 코드 변경은 둘뿐이다. (1) 출시 설정 — 앱 타깃의 `PrivacyInfo.xcprivacy`, Info.plist 출시 키, 버전, 14개 언어 앱 이름, Release 빌드에서 에뮬레이터 구성 코드 제거. 모두 **빌드된 번들을 여는 테스트**로 고정한다. (2) 가이드라인 5.1.1(v) 대응 — 선택기 메뉴 맨 아래 "이 아이폰을 가족에서 빼기"(자기 멤버 문서 삭제 → 익명 계정 삭제 → 이 폰의 기록 삭제)와 "개인정보 처리방침" 줄. 판단은 `LeaveFamilyModel` 에, Firestore·Auth 는 `LeaveFamilyRepository` 에 둔다. 규칙은 고치지 않는다. 나머지는 문서(`docs/app-store/`)와 로컬 검증 스크립트(`tools/ios-release-check.sh`)다.

**Tech Stack:** Swift 6 / SwiftUI / Firebase Auth·Firestore 12.19.1 / NMapsMap 3.23.3 / Swift Testing / XcodeGen / Python 3(표준 라이브러리) / bash + `plutil`·`PlistBuddy`·`codesign`·`security`·`strings`·`xcrun devicectl`. 새 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-12-kidcare-ios-design.md`. 이 단계가 기대는 곳은 다음과 같다.
- §9 7단계 "아이콘 · 개인정보 매니페스트 · TestFlight 배포 준비 — 가족이 실제로 설치 가능"
- §1 배포 방식 "나중에 App Store 정식 출시를 염두에 두고 만든다 … 심사를 막는 선택(권한 과다 요청, 개인정보 매니페스트 누락, 아이 동의 흐름 부재)을 하지 않는다"
- §1 "이 앱이 요청하는 권한은 0개다 … 가이드라인 2.5.4, 배경 위치를 통째로 피한다", 푸시(FCM) 제외
- §10-4 Apple Developer Program 은 7단계에서, §11 "TestFlight 빌드는 90일 만료"
- §13 "App Store 정식 출시 시점과 그때 필요한 자료(개인정보처리방침 웹페이지, 심사용 테스트 계정, 시연 영상, 아이 동의 흐름)"

**저장 위치.** 이 계획서는 저장소에 넣을 때 `docs/superpowers/plans/2026-09-13-kidcare-ios-phase7.md` 로 커밋한다(6단계 선례 `0c7c7d8`).

**선행 조건.** 6단계 Task 1~5 와 단계 마무리가 `ios-guardian-app` 에 모두 커밋돼 있어야 한다. 2026-09-13 이 계획서를 쓸 때 `/Users/com/work/KidCare` 에는 6단계 Task 1 이 **커밋 전**이었다(`tools/ios-strings.py`·`tools/i18n-untranslated.json`·`LocalizationBundleTests.swift` 가 추적 안 됨, `project.yml`·`Info.plist` 등 수정됨). 별도 작업 트리(`scratchpad/kidcare-p6`, 가지 `ios-p6-t2`)는 커밋이 없었다. 그래서 이 계획서는 **6단계 계획서에 적힌 이름**을 쓴다. 시작 전에 이름이 실제로 그대로인지 확인한다.

```bash
cd /Users/com/work/KidCare
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
git branch --show-current                                             # ios-guardian-app
git status --short                                                    # 비어 있어야 한다
git log --oneline | grep -E "6단계 Task (1|2|3|4)" | wc -l             # 4 이상
grep -n "## 아이폰 6단계\|### 아이폰 6단계" README.md                   # 한 줄(6단계 개발일지)
grep -n "#if DEBUG" -A2 ios/KidCare/Guardian/ReadOnlyCheck.swift       # -readOnlyCheck 가 DEBUG 안에 있다
grep -n "^LANGS = \|^def load\|^def build\|^def main\|^CATALOG = " tools/ios-strings.py   # 다섯 줄
grep -n "struct ChildMenu\|Button(model.보호자_초대_문구)" ios/KidCare/Guardian/ChildSelectorBar.swift   # 두 줄
grep -n "\.environment(selector)\|fullScreenCover" ios/KidCare/Guardian/GuardianHomeView.swift        # 두 줄
grep -n "GuardianHomeView(familyId: familyId)" ios/KidCare/RouterView.swift                            # 한 줄
grep -n "private(set) var guardians" ios/KidCare/Guardian/ChildSelectorModel.swift                     # 한 줄
grep -n "static let 언어_태그\|static func 카탈로그_값" ios/KidCareTests/LocalizableCatalogTests.swift   # 두 줄
grep -n "enum TestRepo\|enum TestDefaults\|func eventually" ios/KidCareTests/*.swift                   # 세 줄
grep -n "CFBundleLocalizations" ios/project.yml                                                         # 한 줄
python3 tools/ios-strings.py --check; echo $?                                                           # 0
```

하나라도 다르면 맨 아래 Pre-flight conflict table 의 해당 행을 먼저 처리한다. 테스트 개수 기준(M)도 여기서 한 번 적어 둔다.

## Global Constraints

6단계 계획서의 Global Constraints 를 그대로 옮긴 것(verbatim, 5단계 목록 + 6단계 추가분):

- Swift 6 strict concurrency, iOS 17.0, SwiftUI, XcodeGen (`ios/project.yml`; never hand-edit the xcodeproj), Swift Testing. `ios/KidCare/Logic/` imports Foundation only. No `@unchecked Sendable` or `nonisolated(unsafe)` in app code.
- Android `app/`, `firestore.rules` and `gradlew` are not modified. Android defects found go into the README dev log only.
- No push notifications and no FCM (the Firebase Spark free plan). Every Firestore listener has a removal path on disappear.
- i18n: new keys are added to **both** `i18n/ko.json` and `i18n/en.json` and are regenerated into `Localizable.xcstrings` the way earlier phases did (find the mechanism, e.g. `tools/check-i18n-keys.swift` and the existing parity tests, and state the exact command). `%@` is never used in `i18n/*.json`. A literal `%` must be `%%` in format strings. **Never borrow a string key from an unrelated screen** (this was rejected twice).
- Tests never write to production Firestore. Emulator tests use `configureForEmulator(projectId: "kidcare-emulator")` (Auth 127.0.0.1:9099, Firestore 8080), and `KidCareApp.init()` must call `configureForApp()` at commit time.
- Commits are in Korean, author `Yongminlee2 <dydals5678@gmail.com>`, with no Co-Authored-By trailer and no AI traces.
- Test command: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`.
- **보이는 뒤로 가기.** push 되는 화면은 모두 시스템 뒤로 버튼이 보인다. `.navigationBarBackButtonHidden` 은 쓰지 않는다.
- **진짜 가족 보호.** 진짜 가족 문서에 쓰는 동작은 에뮬레이터에서만 확인한다. 실기기 Task 는 읽기만 한다.
- **정본은 안드로이드다.** 이 계획서가 코틀린과 다르면 코틀린이 맞다. 상수는 인용한 줄에서 그대로 옮긴다. 색과 치수는 `res/values/colors.xml`·`themes.xml`·`dimens.xml` 값을 그대로 쓰고, sp·dp 는 pt 로 1:1 옮긴다. 글자 크기는 `themes.xml:125-148`(HeadlineSmall 24 medium, TitleMedium 18 medium, TitleSmall 16 medium, BodyLarge 17, BodyMedium 15, BodySmall 13, DisplayMedium 34 medium)을 따른다.
- 주석은 한국어로 '왜'를 적는다. 실행 전 PATH 는 `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"` 이다. 파일을 새로 만들었으면 테스트 전에 `cd ios && xcodegen generate` 를 돌린다. 에뮬레이터는 저장소 루트에서 `firebase emulators:start --only auth,firestore --project kidcare-emulator` 로 띄운다.
- **푸시 알림도 FCM 도 쓰지 않는다**(Spark 요금제). 알림 탭은 Firestore `events` 문서만 읽는다. 모든 리스너(알림 목록, 멤버 목록, 초대 완료 감시)에는 떼는 길이 있다.
- **다국어 생성.** 스크립트 하나(`tools/ios-strings.py`)가 `i18n/*.json` 에서 14개 언어를 모두 쓴다. **번역을 지어내지 않는다.** 어떤 언어에 키가 없으면 그 칸은 영어 값으로 채우고 `needs_review` 로 표시한다. `%@` 는 `i18n/*.json` 에 절대 나오지 않는다.
- **뒤로 가기.** 새로 띄우는 화면에도 눈에 보이는 뒤로 버튼이 있다.

7단계 브리프가 더한 것:

- **절대 올리지 않는다.** 다음을 실행하지 않는다: `xcrun altool --upload-app`/`--upload-package`/`--validate-app`, `destination` 이 `upload` 인 `xcodebuild -exportArchive`, Xcode Organizer 의 Distribute App → Upload/Validate, Transporter, `fastlane pilot`/`deliver`. `notarytool` 은 macOS 앱 공증 도구라 이 앱과 관계없다. 쓰지 않는다.
- **App Store Connect 에 아무것도 만들지 않는다.** 앱 레코드, TestFlight 그룹, 테스터, API 키를 만들지 않고, appstoreconnect.apple.com 에 로그인하지 않는다. 이것들은 README "아이폰 TestFlight로 올리는 법"의 **사람이 할 일**이다.
- `-allowProvisioningUpdates` 는 **로컬 서명**(개발자 포털의 개발·배포 프로파일 받기)에만 쓴다. Apple Distribution 인증서가 키체인에 없으면 만들지 않고 멈춘다. 사람이 할 일 A 로 넘긴다.
- **비밀을 커밋하지 않는다.** `ios/Config/Secrets.xcconfig`, `ios/KidCare/GoogleService-Info.plist`(둘 다 `.gitignore` 에 있다), `*.p8`, `*.ipa`, `*.xcarchive`, `embedded.mobileprovision`, 그리고 **팀 ID 문자열**이 대상이다. `Base.xcconfig` 주석대로 팀 ID 는 `Secrets.xcconfig` 에서만 읽는다. 그 두 파일은 열지도 출력하지도 않는다. 검증 스크립트는 값의 **있다/없다·길이**만 적는다.
- 산출물은 저장소 밖 `/tmp/kidcare-p7/` 에만 만든다.
- **실기기는 읽기만 한다.** Release 빌드에서는 `-readOnlyCheck` 가 꺼져 있다(그걸 증명하는 것이 이 단계 일이다). 그래서 실기기 Release 확인에서는 **알림 탭과 관리 탭을 열지 않는다.** 알림 탭은 열면 읽음을 쓰고, 관리 탭은 열면 `query_ringer` 를 쓴다.
- 앱이 요청하는 권한 0개(설계서 §1)를 유지한다. 쓰지 않는 권한의 문구를 넣지 않는다.

## 공통 절차 A — 문구 키를 카탈로그에 넣는 법 (6단계 그대로)

1. 새 문구는 `i18n/ko.json` 과 `i18n/en.json` **둘 다**에 넣는다. 두 파일은 키가 코드 포인트 순으로 정렬돼 있고 `json.dumps(d, indent=2, ensure_ascii=False) + "\n"` 모양이다. 나머지 12개 언어 파일에는 넣지 않는다.
2. 키를 더했으므로 `python3 tools/ios-strings.py --write-gaps` 로 빈 칸 목록과 카탈로그를 함께 다시 쓴다. diff 에서 빈 칸 변화가 의도한 것인지 본다.
3. 검사: `python3 tools/ios-strings.py --check` 가 0, `LocalizableCatalogTests`·`I18nKeyParityTests`·`LocalizationBundleTests` 가 초록.

## 공통 절차 B — 커밋

```bash
cd /Users/com/work/KidCare
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew     # 비어 있어야 한다
git diff ios/KidCare/KidCareApp.swift                              # 비어 있어야 한다(configureForApp)
grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|navigationBarBackButtonHidden" ios/KidCare   # 비어 있어야 한다
python3 tools/ios-strings.py --check                               # 종료 코드 0
git add <이 Task 의 파일들>
# 비밀·산출물이 섞이지 않았는지 — 둘 다 비어 있어야 한다
git diff --cached --name-only | grep -E 'Secrets\.xcconfig$|GoogleService-Info\.plist$|\.p8$|\.ipa$|\.xcarchive|mobileprovision$'
git diff --cached | grep -E '[A-Z0-9]{10}' | grep -iE 'team|DEVELOPMENT_TEAM'
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "<한국어 메시지>"
```

## 이 단계에서 다루지 않는 것

- **업로드, App Store Connect 앱 레코드, TestFlight 그룹·테스터, 심사 제출.** 사람이 할 일이다(Task 4 의 README 절).
- **개인정보 처리방침 웹페이지 게시.** 원고(Task 3)만 쓴다. URL 은 주인이 정한다. 이 계획서는 URL 을 지어내지 않는다.
- **App Store 스크린샷·시연 영상 제작.** TestFlight 에는 필요 없다. 목록에만 올린다.
- **심사용 데모 모드**(가짜 가족 데이터를 보여주는 화면). 판정 기록 11 을 본다.
- **12개 언어의 빈 칸 번역.** 6단계 판정 3 그대로다. 새 키 11개도 ko/en 에만 넣는다.
- 다크·틴트 아이콘 변형, iPad 전용 레이아웃, 위젯, 앱 클립.
- **안드로이드 아이 앱의 공개 배포**(플레이스토어). 판정 기록 12 에 적은 App Store 출시의 선결 과제이지만 이 저장소의 iOS 단계 밖이다.

## 판정 기록 — 이 계획서가 내린 결정

1. **범위.** 설계서 §9 는 7단계를 "아이콘 · 개인정보 매니페스트 · TestFlight 배포 준비"로 적는다.
   - **아이콘은 이미 있다.** `ios/KidCare/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` 는 1024×1024 이고 알파 채널이 없다(2026-09-13 `sips -g hasAlpha` → `no`). App Store 는 1024 아이콘에 알파가 있으면 거부한다. 그래서 새로 그리지 않는다. Task 4 의 스크립트가 `Assets.car` 에 실렸는지만 본다.
   - **"TestFlight 배포 준비"는 로컬 아카이브·내보내기까지다.** 올리는 일은 브리프가 사람 몫으로 뺐다.
   - 브리프가 더한 심사 대비(판정 8~12)는 §1 "심사를 막는 선택을 하지 않는다"와 §13 미결정 사항을 지금 닫는 것이다. 설계서와 부딪히지 않는다.
2. **개인정보 매니페스트 — 무엇을 신고하는가.**
   - **이유가 필요한 API.** 앱 코드는 `UserDefaults` 하나만 쓴다. 쓰는 곳은 `Core/RoleStore.swift`, `Guardian/RequestLog.swift`, `Guardian/AlarmMemoStore.swift`, `Guardian/RuleSyncStore.swift`(2026-09-13 grep)이고 모두 이 앱 자신의 값만 읽고 쓴다. 그래서 이유는 `CA92.1` 이다. 파일 시각, 부팅 시각(`systemUptime`·`mach_absolute_time`), 디스크 공간, 활성 키보드 호출은 0건이다. `ProcessInfo.processInfo.environment`·`arguments` 는 이유가 필요한 API 가 아니다. 이 목록이 코드와 어긋나지 않게 `ReleaseConfigTests.이유_필요_API` 가 소스를 훑어 대조한다.
   - **추적.** `NSPrivacyTracking = false`, 추적 도메인 없음. 광고·분석 SDK 가 없다. 링크되는 제품은 `FirebaseAuth`·`FirebaseFirestore`·`NMapsMap` 셋뿐이다(`project.yml`). `GoogleAppMeasurement` 는 패키지 그래프에만 있고 링크되지 않는다.
   - **수집 데이터.** 판단 기준은 "이 앱이 읽거나 쓰는 가족 데이터 전부"다. 안드로이드 아이 앱이 모은 것을 이 앱이 보여주더라도 **같은 개발자, 같은 서버**이므로 넓게 신고한다. 적게 신고한 것은 거부 사유가 되지만, 넓게 신고한 것은 그렇지 않다. 여섯 개 모두 사용자와 연결됨(가족·익명 uid 에 묶임), 추적 아님, 목적은 앱 기능이다.

     | 매니페스트 키 | 이 앱에서의 실체 | 근거 |
     |---|---|---|
     | `NSPrivacyCollectedDataTypePreciseLocation` | 아이 폰 위치·경로(표시), 보호자가 지도에서 고른 장소 좌표(씀) | `firestore.rules` `children/{uid}`·`trails`·`places` |
     | `NSPrivacyCollectedDataTypeName` | 아이·보호자 표시 이름. 안드로이드 페어링에서 입력(`pairing_child_name_hint`) | `members/{uid}.displayName` |
     | `NSPrivacyCollectedDataTypeUserID` | Firebase 익명 uid(멤버 문서 ID, `createdByUid`) | `AuthGateway`, `inviteCodes` |
     | `NSPrivacyCollectedDataTypeEmailsOrTextMessages` | 아이 폰에 보내는 한마디(`CommandType.message`, `payloadText`) | `ControlViewModel.swift:377` |
     | `NSPrivacyCollectedDataTypeOtherUserContent` | 알람 이름(`payloadLabel`), 예약·장소 이름 | `ControlViewModel.swift:390`, `schedules`·`places` |
     | `NSPrivacyCollectedDataTypeOtherDataTypes` | 아이 폰 배터리·소리 모드·연결 상태, 도착·이탈 사건 | `children/{uid}`, `events` |

   - **SDK 가 따로 신고하는 것.** `OtherDiagnosticData` 는 Firebase 가 자기 매니페스트로 신고한다(연결 안 됨, 목적 Analytics). 앱 매니페스트에 되풀이하지 않는다. 대신 App Store 영양 라벨(Task 3)에는 합쳐서 적는다. 애플의 개인정보 보고서가 SDK 매니페스트를 합치는 것과 같은 방식이다.
   - **SDK 매니페스트는 로컬에서 확인했다**(2026-09-13, `~/Library/Developer/Xcode/DerivedData/KidCare-aelfotxibfhqzlclyqugdlhsnryl/SourcePackages`, `workspace-state.json` 버전 대조).
     - `firebase-ios-sdk 12.19.1`: `FirebaseAuth/Sources/Resources/PrivacyInfo.xcprivacy`(UserID 연결·앱 기능, OtherDiagnosticData, UserDefaults CA92.1), `Firestore/Source/Resources/PrivacyInfo.xcprivacy`(OtherDiagnosticData), `FirebaseFirestoreInternal.xcframework/…/FirebaseFirestoreInternal_Privacy.bundle`, `FirebaseCore`
     - `GoogleUtilities 8.1.3`, `gtm-session-fetcher 5.3.1`, `grpc-binary 1.69.1`, `abseil-cpp-binary`, `leveldb 1.22.5`, `nanopb 2.30910.1`, `promises 2.4.1` 모두 있음
     - `spm-nmapsmap 3.23.3`: `NMapsMap.xcframework/ios-arm64/NMapsMap.framework/PrivacyInfo.xcprivacy` 있음 — FileTimestamp `C617.1`, SystemBootTime `35F9.1`, 수집 없음, 추적 false
     - `spm-nmapsgeometry 1.0.2`: 있음(빈 선언)
     - 다른 기계에서는 Task 1 Step 1 의 명령으로 다시 확인한다. **없으면** 판정은 이렇다. 그 SDK 의 required-reason API 사용을 앱 매니페스트에 대신 적지 않는다(SDK 가 무엇을 왜 쓰는지 우리가 보증할 수 없다). 멈추고 보고한다. 버전을 올릴지는 주인이 정한다.
3. **수출 규정: `ITSAppUsesNonExemptEncryption = false`.** 이 앱이 쓰는 암호는 Firebase(HTTPS·gRPC TLS)와 지도 타일 HTTPS 의 **전송 구간 보호**뿐이다. 앱의 주 기능이 정보 보안이 아니고, 자체·비표준 알고리즘도 없다. grpc-binary 가 BoringSSL(`openssl_grpc`)을 싣고 있어도 용도는 같은 TLS 다. 값을 plist 에 넣어 두면 업로드할 때마다 묻는 수출 규정 질문이 사라진다. 법률 판단이 필요해지면 주인이 App Store Connect 문서를 보고 바꾼다(README 사람이 할 일 D).
4. **버전: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`.** 설계서는 안드로이드 버전(`app/build.gradle.kts:40-41` `versionCode = 8`, `versionName = "0.8"`)과 묶으라고 하지 않았다. 안드로이드 0.8 은 스토어에 낸 적 없는 사이드로드 번호다. 두 스토어의 번호는 서로 비교되지 않는다. 그래서 iOS 는 첫 제출 번호 1.0 (1)로 시작한다. **빌드 번호는 업로드마다 1씩 올린다**(같은 번호는 App Store Connect 가 거부한다). `project.yml` 한 곳에서만 올리고 Info.plist 는 `$(MARKETING_VERSION)`·`$(CURRENT_PROJECT_VERSION)` 을 읽는다. `ExportOptions` 의 `manageAppVersionAndBuildNumber` 는 `false` 다. Xcode 가 몰래 올리면 저장소와 올린 번호가 갈린다.
5. **권한 문구 0개.** 앱 코드에 `CoreLocation`·`UserNotifications`·카메라·사진·연락처·ATT·`NMFLocationManager`·`positionMode` 호출이 0건이다(2026-09-13 grep). 그래서 `NS*UsageDescription` 을 하나도 넣지 않는다. `ReleaseConfigTests.출시_Info` 가 `UsageDescription` 으로 끝나는 키가 생기면 실패한다.
   - **위험 하나를 적어 둔다.** NMapsMap 바이너리는 자기 위치 기능 때문에 `CLLocationManager` 선택자를 싣고 있을 수 있다. 그러면 업로드 뒤 App Store Connect 가 ITMS-90683("Missing purpose string") 메일을 보낼 수 있다. 네트워크 없이는 확인할 수 없다. Task 4 스크립트가 `NMapsMap` 안의 `requestWhenInUseAuthorization` 개수를 **참고로** 적는다. 메일이 오면 사람이 할 일 G 로 처리한다. 그때도 이 앱이 위치를 묻지 않는다는 사실은 그대로이므로, 문구는 "이 앱은 위치를 요청하지 않습니다"라는 사실만 적는다.
6. **Release 빌드의 DEBUG 전용 코드.**
   - `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG` 는 Debug 구성에만 있다(`KidCare.xcodeproj/project.pbxproj:940`, XcodeGen 기본값). Release 에는 없다.
   - `ReadOnlyCheck.isOn` 은 6단계가 `#if DEBUG` 안에 두었으므로 Release 에서 늘 `false` 다.
   - **`FirebaseBootstrap.configureForEmulator` 는 지금 Release 에도 컴파일된다.** 이 함수는 가짜 `googleAppID`·`apiKey` 와 `127.0.0.1` 을 싣고 있다. 부르는 곳은 테스트(`EmulatorHarness`, Debug 로 빌드됨)뿐이지만 출시 바이너리에 남길 이유가 없다. `#if DEBUG` 로 감싼다. 테스트 스킴은 `test: config: Debug` 라 영향이 없다.
   - `RouterView.isRunningTests`·`FirebaseBootstrap.configureForApp` 의 `XCTestConfigurationFilePath` 검사는 Release 에 남아도 무해하다. 그 환경 변수는 XCTest 가 띄울 때만 있다.
   - `KidCareApp` 의 `assert` 는 Release 에서 빠진다. `Logger.error` 는 남는다. 의도한 동작이다(그 파일 주석).
   - **증명 방법.** Swift 는 15바이트 이하 문자열 리터럴을 기계어 안에 직접 넣는다. 그래서 `strings` 로는 `-readOnlyCheck`(14바이트)나 `127.0.0.1` 을 **원래부터 못 찾는다.** 못 찾았다고 없는 게 아니다. 그래서 둘로 나눈다.
     - 에뮬레이터 코드는 긴 표지 문자열 둘로 본다. `emulator-does-not-check-this`(28바이트)와 `1:000000000000:ios:0000000000000000` 이다. 같은 방법으로 **Debug 빌드에서는 찾아지는지**(대조군)를 함께 본다.
     - `-readOnlyCheck` 는 동작으로 본다. Release 를 실기기에서 `-readOnlyCheck` 로 띄워도 선택기 메뉴의 초대 두 줄이 **흐리지 않다**(Task 4 Step 7).
7. **서명.** `CODE_SIGN_STYLE = Automatic`(`Base.xcconfig`), 팀은 `Secrets.xcconfig` 에서 온다. Individual 팀 "YONGMIN LEE" 의 1년 개발 프로파일은 이미 된다. 두 가지를 구분한다.
   - **아카이브**는 개발 인증서로 서명된다. `pbxproj` 의 Release `CODE_SIGN_IDENTITY = "iPhone Developer"` 대로다.
   - **App Store 용 내보내기**는 Apple Distribution 인증서로 다시 서명한다. 키체인에 그 인증서가 없으면 이 계획서는 만들지 않는다. 사람이 Xcode 설정에서 만든다(사람이 할 일 A). 내보내기의 `-allowProvisioningUpdates` 는 개발자 포털에서 App Store 프로파일을 받아 온다. 이것은 업로드가 아니라 서명 준비다.
   - 내보내기가 "App Store Connect 앱 레코드가 없다"는 이유로 실패하면 **멈추고 보고한다.** 레코드를 만들지 않는다.
8. **계정 삭제 — 가이드라인 5.1.1(v) "Apps that support account creation must also offer account deletion within the app."**
   - **해당하는가.** 이 앱은 로그인 화면이 없지만 합류하는 순간 **서버에 계정을 만든다.** Firebase 익명 사용자와 `families/{id}/members/{uid}` 문서(역할, 표시 이름, 초대 코드, 시각)가 생기고, 그 uid 로 메시지·알람 이름·장소를 쓴다. "눈에 보이는 가입 절차가 없으니 해당 없음"은 심사에서 다툼거리가 된다. 막는 선택을 하지 않는다는 설계서 §1 의 태도에 따라 **앱 안에 삭제 길을 만든다.**
   - **안드로이드에는 없다.** `app/src/main` 에 가족 나가기·멤버 삭제·계정 삭제 경로가 0건이다. 있는 것은 `store.clear()`(역할 다시 고르기, 아이 폰 '다시 연결')뿐이다. 6단계 판정도 "멤버 삭제, 가족 나가기 … 안드로이드 보호자 화면에도 없다"고 적었다. **App Store 요구라서 iOS 에만 두는 예외**이고, 개발일지에 그렇게 적는다.
   - **규칙은 이미 허용한다. 고치지 않는다.** `members/{uid}` 의 `allow delete: if memberOf(familyId) && roleIn(familyId) == 'guardian'` 는 보호자가 자기 문서를 지우는 것을 허용한다. 규칙은 요청 전 상태로 평가되므로 지우는 순간에는 아직 멤버다.
   - **지우는 것:**
     - ① 이 폰의 `members/{uid}` 문서
     - ② Firebase 익명 계정. `User.delete()` 를 부른다. 서버가 거부하면(대표적으로 오래전 로그인이라 `requiresRecentLogin`) **로그아웃만** 한다. 익명 계정은 다시 로그인할 길이 없고, 남는 기록은 uid 와 만든 시각뿐이다. 운영 Auth 가 익명 계정에 이 오류를 내는지는 네트워크 없이 확인할 수 없다. 두 갈래를 모두 처리한다.
     - ③ 이 폰의 `UserDefaults`(역할·가족·아이·명령 기록·알람 메모·못 보낸 알림 깃발 전부). 이것까지 지운 뒤 첫 화면으로 간다.
   - **남는 것(규칙상 이 폰이 지울 수 없거나 가족 공용인 것):**
     - 아이 폰이 쓴 `children/*`·`trails`·`events`. 쓰기는 아이 본인만 허용된다.
     - 가족 공용 `schedules`·`places`·`settings`. 다른 보호자가 계속 쓴다.
     - `families/{id}`. `allow delete: if false` 다.
     - 내가 만든 `inviteCodes`. `list: false` 라 찾을 수 없고, 10분 뒤 만료된다(`FamilyRepository.inviteTtlMillis`).
     - 내가 보낸 `commands`. 보낸 사람 필드가 없어 가를 수 없다(`CommandRepository.send` 필드 목록).
     - 기기의 Firestore 캐시. 멤버가 아니게 된 뒤에는 규칙이 읽기를 막고, 앱을 지우면 함께 지워진다. `clearPersistence()` 는 인스턴스를 종료해야 해서, 같은 실행에서 다시 합류하면 앱이 죽는다. 그래서 쓰지 않는다.

     이 목록은 확인 문구와 개인정보 처리방침(Task 3)에 **그대로** 적는다. 아이 기록 삭제는 처리방침의 연락처로 요청받아 주인이 콘솔에서 지운다.
   - **마지막 보호자.** 이 폰이 가족의 유일한 보호자면 빼고 난 뒤 아이 폰의 기록을 볼 사람이 없다. 막지 않는다(삭제를 막으면 5.1.1(v) 위반이다). 대신 확인 문구 앞에 경고를 붙인다. 보호자 수는 6단계 `ChildSelectorModel.guardians` 에서 온다.
   - **오프라인.** 서버가 멤버 삭제를 확인하기 전에는 이 폰의 기록을 지우지 않는다. 지우면 "가족에는 남았는데 이 폰은 모르는" 상태가 된다. 15초(`firstToFinish`) 안에 확인이 없으면 그렇다고 말하고 그대로 둔다.
     - **다시 누른 경우.** 앞 시도가 서버에 닿았다면 두 번째 삭제는 `memberOf` 가 거짓이라 `PERMISSION_DENIED` 가 난다. 그래서 거부되면 가족 문서를 서버에서 읽어 본다. 그것도 거부되면 이미 빠진 것이므로 성공으로 본다. 읽히면 아직 멤버인데 거부된 것이므로 오류다.
   - **자리.** 선택기 메뉴(`ChildMenu`) 맨 아래다. 6단계가 이 메뉴를 선택기 줄(지도 탭 외)과 지도 카드 아이 이름 양쪽에 붙였으므로 모든 탭에서 닿는다. 새 화면을 만들지 않는다. `ReadOnlyCheck.isOn` 에서는 초대 두 줄처럼 흐리게 한다.
   - **확인은 에뮬레이터에서만 한다**(Global Constraints). 실기기에서는 누르지 않는다.
9. **개인정보 처리방침 URL — 가이드라인 5.1.1(i).** 처리방침 링크는 App Store Connect 메타데이터와 **앱 안** 양쪽에 있어야 한다.
   - URL 은 주인이 게시한 뒤 정한다. 이 계획서는 지어내지 않는다.
   - `project.yml` 의 Info.plist 속성 `KidCarePrivacyPolicyURL` 을 **빈 문자열**로 둔다. 비었거나 `https://` 로 시작하지 않으면 메뉴에 줄이 안 보인다(`PrivacyPolicyLink`).
   - 값을 `.xcconfig` 에 두지 않는 이유가 있다. xcconfig 는 `//` 뒤를 주석으로 잘라서 `https://…` 가 `https:` 로 남는다.
   - TestFlight 내부 테스트에는 없어도 된다. **외부 테스트와 App Store 제출 전에는 반드시 채운다**(README 사람이 할 일 H). Task 4 스크립트가 비었으면 "참고"로 적는다.
10. **배경 위치 — 가이드라인 2.5.4.** iOS 보호자 앱은 위치를 수집하지 않는다. `UIBackgroundModes` 가 없고 위치 API 호출이 0건이다. 앱 매니페스트·Info.plist 테스트가 둘 다 지킨다. 심사 메모에 그대로 적는다.
11. **데모 계정 — 가이드라인 2.1.** 로그인이 없으니 줄 계정도 없다. 대신 보려면 **안드로이드 아이 폰과의 페어링**이 필요하다. 보호자 초대 코드는 10분 만료다(`inviteTtlMillis`). 그래서 고정 코드를 메모에 적을 수 없다.
    - 판정: **데모 모드를 만들지 않는다.** 가짜 가족 데이터를 보여주는 화면은 안드로이드에 없는 지어낸 화면이다. 운영 Firestore 에 심사용 데이터를 쓰는 것은 "진짜 가족 보호"와 부딪힌다.
    - 대신 심사 메모(Task 3)가 셋을 준다. ① 시연 영상 URL, ② 심사 기간 동안 켜 두는 데모 가족(안드로이드 시험 폰 한 대)과, 요청하면 즉시 보호자 초대 코드를 보내 줄 연락처, ③ 화면별 설명. ①②는 주인이 채운다.
    - TestFlight **내부** 테스트는 Beta App Review 가 없다. **외부** 테스트는 첫 빌드에 같은 메모가 필요하다.
12. **키즈 카테고리 — 가이드라인 1.3, 그리고 아이 동의.**
    - 이 앱은 부모가 쓰는 앱이다. **키즈 카테고리에 넣지 않는다.** 1차 카테고리는 라이프스타일, 2차는 유틸리티다.
    - 아이 위치를 모으는 쪽은 안드로이드 아이 앱이다. 그 앱은 아이콘을 숨기지 않고 알림줄에 "위치 공유 중"을 늘 띄운다(README "의도적으로 안 만든 것"). 페어링은 아이 폰을 손에 쥐고 초대 코드를 넣어야만 된다. 설계서 §1 이 말한 "아이 동의 흐름"에 대한 답은 이것이다. 심사 메모에 적는다.
    - **App Store 출시의 선결 과제:** 아이 앱이 **공개적으로 구할 수 없으면**(지금은 가족끼리 APK 직접 설치, README:43) 일반 사용자에게 이 iOS 앱은 쓸모가 없다. 심사도 "리뷰어가 기능을 쓸 수 없다"로 막힐 수 있다. TestFlight 가족 배포에는 문제가 없다. App Store 제출 전에 주인이 정할 일로 README 사람이 할 일 H 에 적는다.
13. **홈 화면 이름 14개 언어.** 안드로이드는 런처 이름을 `app_name` 으로 현지화한다. `i18n/*.json` 의 `app_name` 은 ko 가 "우리아이 지킴이", 나머지 13개가 "KidCare" 다(2026-09-13 확인). 지어낼 번역이 없다. `tools/ios-strings.py` 가 같은 원본에서 `ios/KidCare/InfoPlist.xcstrings`(`CFBundleDisplayName`)도 생성한다. Info.plist 값은 서식 문자열이 아니므로 `%` 변환(`conv`)을 하지 않는다. Info.plist 의 기본 `CFBundleDisplayName` "우리아이 지킴이" 는 그대로 둔다.
14. **실기기 Release 확인은 개발 서명 Release 빌드로 한다.** App Store 용 `.ipa` 는 배포 프로파일이라 기기에 설치되지 않는다. 그래서 같은 Release 구성을 개발 서명으로 빌드해 덮어 설치한다. 번들 ID 와 팀이 같으므로 UserDefaults·키체인(익명 로그인)이 유지되어 가족 합류가 그대로다. `-readOnlyCheck` 가 꺼져 있으므로 쓰는 탭은 열지 않는다(Global Constraints).
15. **아이폰 전용·세로 고정 유지.** `TARGETED_DEVICE_FAMILY: "1"`, `UISupportedInterfaceOrientations` 세로 하나 그대로다. iPad 에서는 호환 모드로 돌고 iPad 스크린샷이 필요 없다. Xcode 템플릿이 늘 넣는 `LSRequiresIPhoneOS = true` 가 지금 Info.plist 에 없어서 더한다.
16. **`.xcprivacy` 를 확장자 추측에 맡기지 않는다.** XcodeGen 이 `.xcprivacy` 를 리소스로 분류하는지는 버전마다 다르다. 실리지 않으면 "매니페스트 없는 앱"이 조용히 만들어진다. 그래서 `KidCareTests` 가 `golden/` 을 명시한 것과 같은 방식으로 소스에서 빼고 `buildPhase: resources` 로 따로 적는다.

---

## File Structure

```
ios/project.yml                              수정. 버전 2개, Info.plist 속성 5개, PrivacyInfo 리소스 명시
ios/KidCare/
├─ PrivacyInfo.xcprivacy                     신규. 앱 매니페스트(판정 2)
├─ InfoPlist.xcstrings                       생성물. CFBundleDisplayName 14개 언어(판정 13)
├─ Info.plist                                생성물(xcodegen). 출시 키
├─ RouterView.swift                          수정(Task 2). 가족에서 빠지면 showMain 을 되돌린다
├─ Core/
│  ├─ FirebaseBootstrap.swift                수정(Task 1). configureForEmulator 를 #if DEBUG 로
│  └─ LeaveFamilyRepository.swift            신규(Task 2). 멤버 문서·익명 계정 삭제
└─ Guardian/
   ├─ LeaveFamilyModel.swift                 신규(Task 2). 확인 → 서버 → 계정 → 이 폰
   ├─ PrivacyPolicyLink.swift                신규(Task 2). Info.plist URL 읽기
   ├─ ChildSelectorBar.swift                 수정(Task 2). ChildMenu 맨 아래 두 줄
   └─ GuardianHomeView.swift                 수정(Task 2). 확인 대화상자·진행·실패 알림
ios/KidCareTests/
├─ ReleaseConfigTests.swift                  신규(Task 1). 매니페스트·Info.plist·앱 이름
├─ LeaveFamilyModelTests.swift               신규(Task 2). 가짜 주입
└─ LeaveFamilyTests.swift                    신규(Task 2). 에뮬레이터
ios/Config/ExportOptions-AppStore.plist      신규(Task 4). method app-store-connect, destination export
tools/ios-strings.py                         수정(Task 1). InfoPlist.xcstrings 도 생성
tools/ios-release-check.sh                   신규(Task 4). 산출물 검증(네트워크 없음)
i18n/ko.json, i18n/en.json                   수정(Task 2). ios_leave_family_* 10개, ios_privacy_policy
tools/i18n-untranslated.json                 수정(Task 2). 12개 언어 × 11키
ios/KidCare/Localizable.xcstrings            생성물(Task 2)
docs/app-store/
├─ metadata.md                               신규(Task 3). 이름·부제·설명·키워드·카테고리·등급 답(ko/en)
├─ privacy-label.md                          신규(Task 3). 영양 라벨 답과 근거
├─ review-notes.md                           신규(Task 3). App Review·Beta App Review 메모(en/ko)
└─ privacy-policy.md                         신규(Task 3). 처리방침 원고(ko/en) — 게시는 주인
README.md                                    수정(Task 4). 7단계 개발일지, "아이폰 TestFlight로 올리는 법"
```

| Task | 끝나면 |
|---|---|
| 1 | 앱 번들에 매니페스트가 실리고, 출시 Info.plist 값·14개 언어 앱 이름·권한 0개가 테스트로 고정되며, Release 에 에뮬레이터 구성 코드가 컴파일되지 않는다 |
| 2 | 선택기 메뉴에서 "이 아이폰을 가족에서 빼기"가 서버 → 계정 → 이 폰 순서로 지우고 첫 화면으로 돌아간다(에뮬레이터). 처리방침 URL 이 있으면 메뉴에 줄이 뜬다 |
| 3 | App Store Connect 에 붙여 넣을 원고(ko/en), 영양 라벨 답, 심사 메모, 처리방침 원고가 저장소에 있다 |
| 단계 마무리 | 통합 리뷰 한 번, 에뮬레이터 시뮬레이터로 빼기 흐름 확인 한 번 |
| 4 | 로컬 `.xcarchive`·`.ipa` 가 스크립트 검사를 모두 통과하고, 실기기 Release 읽기 확인과 개발일지·TestFlight 절이 남는다. 업로드는 없다 |

---
### Task 1: 출시 설정 — 매니페스트, 출시 Info.plist, 14개 언어 앱 이름, Release 에서 에뮬레이터 코드 빼기

**끝나면 빌드된 `KidCare.app` 최상위에 `PrivacyInfo.xcprivacy` 가 있다.** Info.plist 에는 `ITSAppUsesNonExemptEncryption = false`·`1.0 (1)`·`LSRequiresIPhoneOS` 가 있고 권한 문구·배경 모드는 없다. 14개 `lproj` 에 앱 이름이 들어가고, Release 구성은 `configureForEmulator` 를 컴파일하지 않는다. 화면 변화는 없다(영어 등 13개 언어 기기의 홈 화면 이름이 "KidCare" 로 바뀌는 것뿐이다).

**Files:**
- Create: `ios/KidCare/PrivacyInfo.xcprivacy`, `ios/KidCareTests/ReleaseConfigTests.swift`, `ios/KidCare/InfoPlist.xcstrings`(생성물)
- Modify: `ios/project.yml`, `ios/KidCare/Core/FirebaseBootstrap.swift`, `tools/ios-strings.py`, `ios/KidCare/Info.plist`(xcodegen 생성물)

**Interfaces:**
- Consumes: 6단계 `tools/ios-strings.py`(`LANGS`, `load()`, `build(src, version)`, `report(gaps)`, `CATALOG`, `GAPS`, `fail()`), `LocalizableCatalogTests.언어_태그`, `TestRepo.root()`.
- Produces:
  - Info.plist 키 `KidCarePrivacyPolicyURL`(String, 지금은 `""`) — Task 2 `PrivacyPolicyLink` 가 읽는다
  - 빌드 설정 `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` — Task 4 가 대조한다
  - `ReleaseConfigTests.신고한_수집_항목: Set<String>` — Task 3 영양 라벨 문서가 같은 여섯 개를 적는다
  - 명령 `python3 tools/ios-strings.py [--check | --write-gaps]` 가 `InfoPlist.xcstrings` 도 쓰고 검사한다

- [ ] **Step 1: SDK 매니페스트를 이 기계에서 다시 확인한다(판정 기록 2)** — 네트워크를 쓰지 않는다. 한 번이라도 빌드한 DerivedData 를 본다.

```bash
SP=$(ls -d ~/Library/Developer/Xcode/DerivedData/KidCare-*/SourcePackages 2>/dev/null | head -1); echo "$SP"
python3 - "$SP/workspace-state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = {p['packageRef']['identity']: p.get('state', {}).get('checkoutState', {}).get('version') for p in d['object']['dependencies']}
print('firebase-ios-sdk', v.get('firebase-ios-sdk'), '/ spm-nmapsmap', v.get('spm-nmapsmap'))
assert v.get('firebase-ios-sdk') == '12.19.1' and v.get('spm-nmapsmap') == '3.23.3', v
PY
find "$SP" -name PrivacyInfo.xcprivacy | grep -E 'FirebaseAuth/Sources|Firestore/Source/Resources|FirebaseCore/Sources|FirebaseFirestoreInternal.xcframework/ios-arm64/|NMapsMap.xcframework/ios-arm64/|NMapsGeometry.xcframework/ios-arm64/|GoogleUtilities/UserDefaults|gtm-session-fetcher/Sources/Core|grpc.xcframework/ios-arm64/|leveldb/|nanopb/|promises/Sources/FBLPromises' | sed "s|$SP/||"
# 기대: 12줄. NMapsMap 줄이 없으면 멈추고 보고한다(판정 기록 2 마지막 문단).
plutil -p "$SP/artifacts/spm-nmapsmap/NMapsMapBinary/framework/NMapsMap.xcframework/ios-arm64/NMapsMap.framework/PrivacyInfo.xcprivacy"
# 기대: NSPrivacyTracking => false, FileTimestamp C617.1, SystemBootTime 35F9.1, CollectedDataTypes 빈 배열
```

`SP` 가 비었으면(이 기계에서 빌드한 적이 없다) 먼저 `cd ios && xcodegen generate && xcodebuild -resolvePackageDependencies -project KidCare.xcodeproj -scheme KidCare` 를 돌린다. 이 명령은 GitHub 에서 패키지를 받는다. Apple·Firebase 서버에는 닿지 않는다. 그 뒤 위를 다시 돌린다.

- [ ] **Step 2: 테스트를 먼저 쓴다**

`ios/KidCareTests/ReleaseConfigTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 출시 빌드가 지켜야 할 성질을 **빌드된 앱 번들을 열어** 본다(7단계 계획서 판정 기록 2·3·4·5·13·15).
/// 설정 파일이 맞아도 빌드가 매니페스트를 빠뜨리거나 권한 문구가 끼어들면, 올린 뒤 메일로 알게 된다.
/// 테스트는 Debug 로 돌지만 여기서 보는 값(매니페스트, Info.plist, lproj)은 구성마다 다르지 않다.
struct ReleaseConfigTests {

    /// 판정 기록 2 의 여섯 개. `docs/app-store/privacy-label.md` 의 "연결된 데이터" 표와 같은 목록이다.
    static let 신고한_수집_항목: Set<String> = [
        "NSPrivacyCollectedDataTypePreciseLocation",
        "NSPrivacyCollectedDataTypeName",
        "NSPrivacyCollectedDataTypeUserID",
        "NSPrivacyCollectedDataTypeEmailsOrTextMessages",
        "NSPrivacyCollectedDataTypeOtherUserContent",
        "NSPrivacyCollectedDataTypeOtherDataTypes",
    ]

    /// 이유가 필요한 API 를 앱 소스에서 찾는 글자들. 애플 목록의 다섯 갈래다.
    /// 주석에 이 단어를 쓰면 걸린다 — 그때는 사람이 보고 판정한다(넓게 걸리는 쪽이 안전하다).
    static let 이유_필요_API: [(category: String, pattern: String)] = [
        ("NSPrivacyAccessedAPICategoryFileTimestamp", #"creationDate|modificationDate|ModificationDate|attributesOfItem|getattrlist|\bf?stat\("#),
        ("NSPrivacyAccessedAPICategorySystemBootTime", #"systemUptime|mach_absolute_time"#),
        ("NSPrivacyAccessedAPICategoryDiskSpace", #"volumeAvailableCapacity|systemFreeSize|systemSize|statfs"#),
        ("NSPrivacyAccessedAPICategoryActiveKeyboards", #"activeInputModes"#),
        ("NSPrivacyAccessedAPICategoryUserDefaults", #"UserDefaults|@AppStorage"#),
    ]

    private func 매니페스트() throws -> [String: Any] {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy 가 앱 번들 최상위에 없다 — project.yml 의 buildPhase: resources 를 본다(판정 기록 16)"
        )
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("추적하지 않는다 — 추적 도메인도 없다(판정 기록 2)")
    func 추적_없음() throws {
        let m = try 매니페스트()
        #expect(m["NSPrivacyTracking"] as? Bool == false)
        #expect((m["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    }

    @Test("수집 항목은 판정 기록 2 의 여섯 개 — 모두 연결됨, 추적 아님, 앱 기능")
    func 수집_항목() throws {
        let items = try #require(try 매니페스트()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(items.count == Self.신고한_수집_항목.count)
        #expect(Set(items.compactMap { $0["NSPrivacyCollectedDataType"] as? String }) == Self.신고한_수집_항목)
        for item in items {
            let name = item["NSPrivacyCollectedDataType"] as? String ?? "?"
            #expect(item["NSPrivacyCollectedDataTypeLinked"] as? Bool == true, "\(name)")
            #expect(item["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, "\(name)")
            #expect(item["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"], "\(name)")
        }
    }

    @Test("앱 코드가 부르는 이유 필요 API 는 모두 신고했고, 안 부르는 것은 신고하지 않았다 — UserDefaults 는 CA92.1")
    func 이유_필요_API() throws {
        let root = try #require(TestRepo.root())
        let app = root.appendingPathComponent("ios/KidCare")
        var source = ""
        let files = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            source += try String(contentsOf: url, encoding: .utf8) + "\n"
        }
        let used = Set(Self.이유_필요_API
            .filter { source.range(of: $0.pattern, options: .regularExpression) != nil }
            .map(\.category))

        let declared = try #require(try 매니페스트()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(Set(declared.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }) == used,
                "코드에서 찾은 갈래 \(used.sorted()) 와 매니페스트가 다르다")
        let userDefaults = declared.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }
        #expect(userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    @Test("출시 Info.plist — 수출 규정, 1.0 (1), 아이폰 세로 전용, 권한 문구·배경 모드 없음(판정 기록 3·4·5·10·15)")
    func 출시_Info() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        #expect(info["CFBundleShortVersionString"] as? String == "1.0")
        #expect(info["CFBundleVersion"] as? String == "1")
        #expect(info["LSRequiresIPhoneOS"] as? Bool == true)
        #expect(info["UIDeviceFamily"] as? [Int] == [1])
        #expect(info["UISupportedInterfaceOrientations"] as? [String] == ["UIInterfaceOrientationPortrait"])
        #expect(info.keys.filter { $0.hasSuffix("UsageDescription") }.sorted() == [],
                "권한 문구가 생겼다 — 설계서 §1 '이 앱이 요청하는 권한은 0개다'")
        #expect(info["UIBackgroundModes"] == nil, "배경 모드가 생겼다 — 가이드라인 2.5.4(판정 기록 10)")
        #expect(info["KidCarePrivacyPolicyURL"] is String, "Task 2 의 처리방침 줄이 읽는 키")
    }

    @Test("홈 화면 이름은 i18n app_name 그대로 14개 언어(판정 기록 13)")
    func 앱_이름() throws {
        let root = try #require(TestRepo.root())
        for (file, tag) in LocalizableCatalogTests.언어_태그 {
            let data = try Data(contentsOf: root.appendingPathComponent("i18n/\(file).json"))
            let src = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let expected = try #require(src["app_name"] as? String, "\(file).json 에 app_name 이 없다")
            let path = try #require(Bundle.main.path(forResource: tag, ofType: "lproj"), "\(tag).lproj")
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: "CFBundleDisplayName", value: "(없음)", table: "InfoPlist") == expected, "\(tag)")
        }
    }
}
```

- [ ] **Step 3: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/ReleaseConfigTests`
Expected: FAIL 5개. 네 개는 매니페스트·출시 키가 없어서(`PrivacyInfo.xcprivacy 가 앱 번들 최상위에 없다`, `ITSAppUsesNonExemptEncryption`), `앱_이름` 은 `en` 이 "(없음)" 이어서 실패한다.

- [ ] **Step 4: 매니페스트를 쓴다**

`ios/KidCare/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePreciseLocation</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeName</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeUserID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeEmailsOrTextMessages</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherUserContent</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherDataTypes</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

`plutil -lint ios/KidCare/PrivacyInfo.xcprivacy` → `OK`. plist 안에는 주석을 두지 않는다. 근거는 판정 기록 2 에 있다.

- [ ] **Step 5: `project.yml` 을 고친다**

`targets.KidCare` 에서 세 곳을 바꾼다.

1. `sources:` 를 이것으로 바꾼다.

```yaml
    sources:
      # .xcprivacy 를 확장자 추측에 맡기지 않는다 — 리소스로 안 실리면 매니페스트 없는 앱이 조용히
      # 만들어진다(7단계 판정 기록 16). KidCareTests 의 golden/ 과 같은 방식이다.
      - path: KidCare
        excludes:
          - "PrivacyInfo.xcprivacy"
      - path: KidCare/PrivacyInfo.xcprivacy
        buildPhase: resources
```

2. `settings.base` 에 더한다(`ASSETCATALOG_COMPILER_APPICON_NAME` 아래).

```yaml
        # 올릴 때마다 CURRENT_PROJECT_VERSION 을 1 올린다 — 같은 번호는 App Store Connect 가 거부한다.
        # 안드로이드 versionCode 와 묶지 않는다(7단계 판정 기록 4). 여기 한 곳에서만 바꾼다.
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
```

3. `info.properties` 에 더한다(`CFBundleLocalizations` 아래).

```yaml
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSRequiresIPhoneOS: true
        # 전송 구간 TLS 만 쓴다 — 수출 규정 면제(7단계 판정 기록 3). 올릴 때마다 묻는 질문이 사라진다.
        ITSAppUsesNonExemptEncryption: false
        # 개인정보 처리방침 URL(가이드라인 5.1.1(i)). 주인이 게시한 뒤 https:// 주소를 넣는다. 비어 있으면
        # 메뉴에 줄이 안 뜬다. xcconfig 에 두지 않는 이유: xcconfig 는 // 뒤를 주석으로 잘라낸다(판정 기록 9).
        KidCarePrivacyPolicyURL: ""
```

- [ ] **Step 6: Release 에서 에뮬레이터 구성을 뺀다**

`ios/KidCare/Core/FirebaseBootstrap.swift` 에서 `/// 테스트용. **plist 가 없어도 돈다** …` 주석부터 `configureForEmulator` 함수 끝의 `}` 까지를 `#if DEBUG` / `#endif` 로 감싼다. `#if DEBUG` 바로 위에 주석 한 줄을 둔다.

```swift
    // 출시 빌드에는 싣지 않는다 — 가짜 googleAppID·apiKey 와 127.0.0.1 을 배포 바이너리에 남길 이유가 없다.
    // 부르는 곳은 테스트(EmulatorHarness)뿐이고 테스트 스킴은 Debug 다(7단계 판정 기록 6).
    #if DEBUG
```

함수 본문은 한 글자도 바꾸지 않는다.

- [ ] **Step 7: 생성기가 앱 이름도 쓴다**

`tools/ios-strings.py` 를 고친다.

1. 머리 주석 첫 줄 아래에 한 줄을 더한다: `# 같은 원본의 app_name 으로 ios/KidCare/InfoPlist.xcstrings(CFBundleDisplayName)도 만든다(7단계 판정 기록 13).`
2. `GAPS = …` 줄 아래에 더한다.

```python
INFOPLIST = os.path.join(ROOT, 'ios/KidCare/InfoPlist.xcstrings')
# Info.plist 키 → i18n 키. 안드로이드 런처 이름이 app_name 이다.
INFOPLIST_KEYS = {'CFBundleDisplayName': 'app_name'}
```

3. `def report(gaps):` 바로 위에 더한다.

```python
def build_infoplist(src):
    """InfoPlist.xcstrings. Info.plist 값은 서식 문자열이 아니므로 conv() 를 거치지 않는다 — 거치면 % 가 %% 로 남는다."""
    en = src['en']
    strings = {}
    for plist_key, key in sorted(INFOPLIST_KEYS.items()):
        if key not in en:
            fail('en.json 에 %s 가 없다' % key)
        localizations = {}
        for name, tag in LANGS:
            if key in src[name]:
                unit = {'state': 'translated', 'value': src[name][key]}
            else:
                unit = {'state': 'needs_review', 'value': en[key]}
            localizations[tag] = {'stringUnit': unit}
        strings[plist_key] = {'extractionState': 'manual', 'localizations': localizations}
    catalog = {'sourceLanguage': 'ko', 'strings': strings, 'version': '1.0'}
    return json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True) + '\n'
```

4. `main` 에서 `text, gaps = build(src, version)` 바로 아래에 더한다.

```python
    plist_text = build_infoplist(src)
    plist_current = ''
    if os.path.exists(INFOPLIST):
        with open(INFOPLIST, encoding='utf-8') as f:
            plist_current = f.read()
```

5. `main` 의 `--check` 갈래와 쓰기 갈래를 이것으로 바꾼다.

```python
    if '--check' in args:
        if current != text:
            fail('카탈로그가 원본에서 생성한 결과와 다르다. python3 tools/ios-strings.py 를 돌린다')
        if plist_current != plist_text:
            fail('InfoPlist.xcstrings 가 원본에서 생성한 결과와 다르다. python3 tools/ios-strings.py 를 돌린다')
        return
    if current != text:
        with open(CATALOG, 'w', encoding='utf-8') as f:
            f.write(text)
    if plist_current != plist_text:
        with open(INFOPLIST, 'w', encoding='utf-8') as f:
            f.write(plist_text)
    print('카탈로그 %d키 × %d개 언어, InfoPlist %d키' % (len(src['ko']), len(LANGS), len(INFOPLIST_KEYS)))
```

```bash
cd /Users/com/work/KidCare
python3 tools/ios-strings.py            # "InfoPlist 1키" 가 찍힌다. Localizable.xcstrings 는 diff 가 없어야 한다
git diff --stat ios/KidCare/Localizable.xcstrings   # 비어 있어야 한다
python3 -c "import json;d=json.load(open('ios/KidCare/InfoPlist.xcstrings'));l=d['strings']['CFBundleDisplayName']['localizations'];print(l['ko']['stringUnit'],l['en']['stringUnit'],len(l))"
# 기대: {'state': 'translated', 'value': '우리아이 지킴이'} {'state': 'translated', 'value': 'KidCare'} 14
python3 tools/ios-strings.py --check; echo $?        # 0
```

- [ ] **Step 8: 통과를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`(에뮬레이터를 띄운 채)
Expected: 전체 PASS. `ReleaseConfigTests` 5개가 새로 들어간다(M+5).

`앱_이름` 이 `InfoPlist` 표를 못 찾아 "(없음)"으로 실패하면 **멈추고 보고한다.** XcodeGen 이 `InfoPlist.xcstrings` 를 리소스로 싣지 않았다는 뜻이다. Step 5 처럼 `buildPhase: resources` 로 명시할지는 보고 뒤에 정한다.

```bash
cd /Users/com/work/KidCare/ios
grep -n "ITSAppUsesNonExemptEncryption\|LSRequiresIPhoneOS\|KidCarePrivacyPolicyURL\|MARKETING_VERSION\|CURRENT_PROJECT_VERSION" KidCare/Info.plist   # 다섯 줄
grep -c "UsageDescription\|UIBackgroundModes" KidCare/Info.plist                         # 0
grep -n "PrivacyInfo.xcprivacy in Resources" KidCare.xcodeproj/project.pbxproj | head -2  # 한 줄 이상
# Release 가 DEBUG 조건 없이, 에뮬레이터 함수 없이 컴파일되는지(서명 없이, 네트워크 없이)
xcodebuild -project KidCare.xcodeproj -scheme KidCare -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/kidcare-p7/dd-release-sim build 2>&1 | tail -3   # ** BUILD SUCCEEDED **
xcodebuild -project KidCare.xcodeproj -scheme KidCare -configuration Release -showBuildSettings 2>/dev/null \
  | grep -E '^ +(SWIFT_ACTIVE_COMPILATION_CONDITIONS|MARKETING_VERSION|CURRENT_PROJECT_VERSION|CODE_SIGN_STYLE|TARGETED_DEVICE_FAMILY|IPHONEOS_DEPLOYMENT_TARGET) ='
# 기대: SWIFT_ACTIVE_COMPILATION_CONDITIONS 가 없거나 DEBUG 를 안 담는다, 1.0, 1, Automatic, 1, 17.0
```

- [ ] **Step 9: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/PrivacyInfo.xcprivacy ios/KidCare/InfoPlist.xcstrings ios/KidCare/Info.plist ios/project.yml \
  ios/KidCare/Core/FirebaseBootstrap.swift ios/KidCareTests/ReleaseConfigTests.swift tools/ios-strings.py
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 7단계 Task 1: 출시 설정 — 개인정보 매니페스트와 출시 Info.plist 를 번들에서 확인하고, 에뮬레이터 구성은 출시 빌드에 싣지 않는다"
```

---
### Task 2: 이 아이폰을 가족에서 빼기(계정·내 데이터 삭제)와 처리방침 줄 — 가이드라인 5.1.1

**끝나면 선택기 메뉴 맨 아래에 "이 아이폰을 가족에서 빼기"가 있다.** 누르면 확인 대화상자가 뜨고, 이 폰이 마지막 보호자면 경고가 앞에 붙는다. "빼기"를 누르면 서버의 내 멤버 문서 → 익명 계정 → 이 폰의 기록 순으로 지우고 역할 선택 화면으로 돌아간다. 서버가 15초 안에 확인하지 않거나 거부하면 아무것도 지우지 않고 사유를 알린다. `KidCarePrivacyPolicyURL` 이 `https://` 로 채워져 있으면 "개인정보 처리방침" 줄도 뜬다(지금은 비어 있어 안 뜬다).

**Files:**
- Create: `ios/KidCare/Core/LeaveFamilyRepository.swift`, `ios/KidCare/Guardian/LeaveFamilyModel.swift`, `ios/KidCare/Guardian/PrivacyPolicyLink.swift`, `ios/KidCareTests/LeaveFamilyModelTests.swift`, `ios/KidCareTests/LeaveFamilyTests.swift`
- Modify: `ios/KidCare/Guardian/ChildSelectorBar.swift`(`ChildMenu`), `ios/KidCare/Guardian/GuardianHomeView.swift`, `ios/KidCare/RouterView.swift`, `i18n/ko.json`, `i18n/en.json`, `tools/i18n-untranslated.json`, `ios/KidCare/Localizable.xcstrings`

**Interfaces:**
- Consumes:
  - Task 1 Info.plist 키 `KidCarePrivacyPolicyURL`
  - 6단계 `ChildMenu<Content>`, `ChildSelectorModel.guardians`, `GuardianHomeView`(`selector`, `.environment(selector)`, `fullScreenCover`), `ReadOnlyCheck.isOn`, `RouterView` 의 `GuardianHomeView(familyId:).id(familyId)`
  - 5단계 `firstToFinish(timeoutMillis:sleep:operation:)`(`Guardian/FirstToFinish.swift`)
  - 1단계 `AuthGateway.currentUid()`, `RoleStore.shared.clear()`, `errorMessage(_:)`, `EmulatorHarness.start()/freshUser()/freshChildSession()/joinAsChild(_:familyId:joinCode:)`, `FamilyRepository.createFamily/createInvite/joinFamily`
  - 테스트 도우미 `eventually`
- Produces:
  - `enum LeaveFamilyRepository { enum AuthOutcome: Equatable, Sendable { case deleted, signedOutOnly }; static func removeMember(familyId: String, uid: String) async throws; static func deleteAuthUser() async -> AuthOutcome }`
  - `@MainActor @Observable final class LeaveFamilyModel { typealias RemoveMember, DeleteAuth; nonisolated static let timeoutMillis: Int64; let familyId; 묻는중, 빼는중, 실패_문구: String?, 계정_결과: AuthOutcome?; init(familyId:currentUid:removeMember:deleteAuth:clearLocal:sleep:); static func 확인_문구(보호자_수:) -> String; static func 이_폰의_기록을_지운다(); 묻는다(), 취소한다(), 실패를_닫는다(), 뺀다() async }`
  - `enum PrivacyPolicyLink { static func url(info: [String: Any]?) -> URL? }`
  - 문구 키 11개(Step 1). Task 3 의 심사 메모·처리방침이 메뉴 이름을 이 값 그대로 인용한다.

**규칙 확인.** 새 쓰기는 `members/{uid}` delete 하나다. `firestore.rules` 의 members `allow delete: if memberOf(familyId) && roleIn(familyId) == 'guardian'` 로 허용된다. 재시도 판정의 `families/{id}` get 은 `allow get: if memberOf(familyId)` 다. 규칙 파일은 고치지 않는다.

- [ ] **Step 1: 문구 키를 넣는다** (공통 절차 A)

```bash
cd /Users/com/work/KidCare
python3 - <<'PY'
import json
add = {
    'ko': {
        'ios_leave_family_menu': '이 아이폰을 가족에서 빼기',
        'ios_leave_family_title': '이 아이폰을 가족에서 뺄까요?',
        'ios_leave_family_message': '이 아이폰의 보호자 연결과 익명 계정을 지워요. 아이 폰의 기록과 예약·장소는 가족에 그대로 남아요. 다시 보려면 새 초대 번호를 받아야 해요.',
        'ios_leave_family_last_guardian_format': '이 아이폰이 이 가족의 마지막 보호자예요. 빼고 나면 아이 폰이 올리는 기록을 볼 사람이 없으니 아이 폰의 앱도 함께 지워 주세요.\n\n%1$s',
        'ios_leave_family_confirm': '빼기',
        'ios_leave_family_cancel': '취소',
        'ios_leave_family_in_progress': '가족에서 빼는 중…',
        'ios_leave_family_offline': '인터넷에 연결되지 않아 빼지 못했어요. 연결된 뒤 다시 해 주세요.',
        'ios_leave_family_failed_title': '가족에서 빼지 못했어요',
        'ios_leave_family_failed_ok': '확인',
        'ios_privacy_policy': '개인정보 처리방침',
    },
    'en': {
        'ios_leave_family_menu': 'Remove this iPhone from the family',
        'ios_leave_family_title': 'Remove this iPhone from the family?',
        'ios_leave_family_message': "This deletes this iPhone's guardian link and its anonymous account. Your child's records, schedules and places stay with the family. To see them again, you'll need a new invite code.",
        'ios_leave_family_last_guardian_format': "This iPhone is the family's last guardian. Once it's removed, no one can see what your child's phone uploads, so please delete the app on your child's phone too.\n\n%1$s",
        'ios_leave_family_confirm': 'Remove',
        'ios_leave_family_cancel': 'Cancel',
        'ios_leave_family_in_progress': 'Removing from the family…',
        'ios_leave_family_offline': "Couldn't remove it because you're offline. Please try again once you're connected.",
        'ios_leave_family_failed_title': "Couldn't remove this iPhone",
        'ios_leave_family_failed_ok': 'OK',
        'ios_privacy_policy': 'Privacy Policy',
    },
}
for lang, kv in add.items():
    path = 'i18n/%s.json' % lang
    with open(path, encoding='utf-8') as f:
        d = json.load(f)
    for k in kv:
        assert k not in d, k
    d.update(kv)
    d = dict(sorted(d.items()))
    with open(path, 'w', encoding='utf-8') as f:
        f.write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
PY
python3 tools/ios-strings.py --write-gaps   # 번역 대기 언어마다 +11
git diff --stat i18n tools/i18n-untranslated.json ios/KidCare/Localizable.xcstrings
python3 tools/ios-strings.py --check; echo $?   # 0
```

- [ ] **Step 2: 테스트를 먼저 쓴다**

`ios/KidCareTests/LeaveFamilyModelTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// "이 아이폰을 가족에서 빼기"의 순서와 실패 규칙(7단계 계획서 판정 기록 8). 서버·계정·이 폰은 모두 가짜로 주입한다.
@MainActor
struct LeaveFamilyModelTests {

    final class 기록: Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [String]())
        var 순서: [String] { lock.withLock { $0 } }
        func 적는다(_ s: String) { lock.withLock { $0.append(s) } }
    }

    /// 시간 초과가 이기지 않게 하는 기본 sleep — 한 시간.
    static let 오래: @Sendable (Int64) async -> Void = { _ in try? await Task.sleep(nanoseconds: 3_600_000_000_000) }

    private func 만든다(
        _ log: 기록,
        uid: String? = "me",
        remove: @escaping LeaveFamilyModel.RemoveMember,
        sleep: @escaping @Sendable (Int64) async -> Void = LeaveFamilyModelTests.오래
    ) -> LeaveFamilyModel {
        LeaveFamilyModel(
            familyId: "fam",
            currentUid: { uid },
            removeMember: remove,
            deleteAuth: { log.적는다("auth"); return .deleted },
            clearLocal: { log.적는다("local") },
            sleep: sleep
        )
    }

    @Test("서버가 빠진 것을 확인한 뒤에만 계정, 그다음 이 폰의 기록을 지운다")
    func 순서() async {
        let log = 기록()
        let m = 만든다(log, remove: { familyId, uid in log.적는다("remove \(familyId) \(uid)") })
        m.묻는다()
        await m.뺀다()
        #expect(log.순서 == ["remove fam me", "auth", "local"])
        #expect(m.실패_문구 == nil)
        #expect(m.빼는중 == false)
        #expect(m.묻는중 == false)
        #expect(m.계정_결과 == .deleted)
    }

    @Test("서버 확인이 15초 안에 안 오면 아무것도 지우지 않고 오프라인이라고 말한다")
    func 시간_초과() async {
        let log = 기록()
        let m = 만든다(
            log,
            remove: { _, _ in try await Task.sleep(nanoseconds: 3_600_000_000_000) },
            sleep: { millis in
                #expect(millis == LeaveFamilyModel.timeoutMillis)
            }
        )
        await m.뺀다()
        #expect(log.순서 == [])
        #expect(m.실패_문구 == String(localized: "ios_leave_family_offline"))
        #expect(m.빼는중 == false)
        #expect(LeaveFamilyModel.timeoutMillis == 15_000)
    }

    @Test("서버가 거부하면 errorMessage 문구를 보이고 아무것도 지우지 않는다")
    func 거부() async {
        let log = 기록()
        let denied = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        let m = 만든다(log, remove: { _, _ in throw denied })
        await m.뺀다()
        #expect(log.순서 == [])
        #expect(m.실패_문구 == errorMessage(denied))
        m.실패를_닫는다()
        #expect(m.실패_문구 == nil)
    }

    @Test("로그인한 적이 없으면 서버에 묻지 않고 이 폰의 기록만 지운다")
    func 로그인_전() async {
        let log = 기록()
        let m = 만든다(log, uid: nil, remove: { _, _ in log.적는다("remove") })
        await m.뺀다()
        #expect(log.순서 == ["local"])
    }

    @Test("빼는 중에 다시 눌러도 서버에는 한 번만 간다")
    func 두_번_눌러도_한_번() async {
        let log = 기록()
        let m = 만든다(log, remove: { _, _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            log.적는다("remove")
        })
        let first = Task { await m.뺀다() }
        await eventually { m.빼는중 }
        await m.뺀다()
        m.묻는다()                       // 빼는 중에는 대화상자를 다시 열지 않는다
        #expect(m.묻는중 == false)
        await first.value
        #expect(log.순서 == ["remove", "auth", "local"])
    }

    @Test("마지막 보호자면 경고를 앞에 붙이고, 둘 이상이면 기본 문구만")
    func 확인_문구() {
        let base = String(localized: "ios_leave_family_message")
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 2) == base)
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 1) != base)
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 1).hasSuffix(base))
        // 멤버 목록을 아직 못 받았으면(0) 경고 쪽으로 기운다 — 경고가 빠지는 것보다 남는 것이 안전하다.
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 0) == LeaveFamilyModel.확인_문구(보호자_수: 1))
    }

    @Test("묻고 취소하면 아무것도 지우지 않는다")
    func 취소() async {
        let log = 기록()
        let m = 만든다(log, remove: { _, _ in log.적는다("remove") })
        m.묻는다()
        #expect(m.묻는중)
        m.취소한다()
        #expect(m.묻는중 == false)
        #expect(log.순서 == [])
    }
}

/// 처리방침 줄은 https 주소가 있을 때만 뜬다(판정 기록 9).
struct PrivacyPolicyLinkTests {
    @Test("비었거나 https 가 아니면 nil, https 면 그 주소")
    func 주소() {
        #expect(PrivacyPolicyLink.url(info: nil) == nil)
        #expect(PrivacyPolicyLink.url(info: ["KidCarePrivacyPolicyURL": ""]) == nil)
        #expect(PrivacyPolicyLink.url(info: ["KidCarePrivacyPolicyURL": "http://example.com/privacy"]) == nil)
        #expect(PrivacyPolicyLink.url(info: ["KidCarePrivacyPolicyURL": "https://example.com/privacy"])?.absoluteString
                == "https://example.com/privacy")
    }
}
```

`ios/KidCareTests/LeaveFamilyTests.swift`:

```swift
import FirebaseAuth
import FirebaseFirestore
import Testing
@testable import KidCare

/// 보안 규칙 상대의 통합 테스트. 에뮬레이터가 떠 있어야 돈다. 규칙을 고치지 않고 빼기가 되는지를 본다(판정 기록 8).
@Suite(.serialized)
struct LeaveFamilyTests {

    init() async { await EmulatorHarness.start() }

    @Test("보호자가 빠지면 멤버 문서가 사라지고, 그 계정은 더는 가족을 못 읽는다 — 아이는 그대로 남는다")
    func 빠진다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)

        try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: owner)

        let members = try await child.db.collection("families").document(familyId)
            .collection("members").getDocuments(source: .server)
        #expect(members.documents.map(\.documentID) == [child.uid])
        await #expect(throws: (any Error).self) {
            _ = try await Firestore.firestore().collection("families").document(familyId).getDocument(source: .server)
        }
    }

    @Test("이미 빠진 뒤에 다시 불러도 성공한다 — 시간 초과 뒤 다시 누른 경우")
    func 다시_불러도_성공() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: owner)
        try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: owner)
    }

    @Test("아직 가족에 있는데 규칙이 거부하면 성공으로 삼키지 않는다 — 아이 역할 계정")
    func 멤버인데_거부되면_던진다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let childUid = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(code: invite.code, uid: childUid, expectedRole: .child, displayName: "아이")

        // 아이는 members delete 가 거부되지만(roleIn == guardian 아님) families get 은 된다 → 진짜 오류다.
        await #expect(throws: (any Error).self) {
            try await LeaveFamilyRepository.removeMember(familyId: familyId, uid: childUid)
        }
    }

    @Test("익명 계정을 지우면 로그인이 풀린다")
    func 계정_삭제() async throws {
        _ = try await EmulatorHarness.freshUser()
        let outcome = await LeaveFamilyRepository.deleteAuthUser()
        #expect(outcome == .deleted)
        #expect(Auth.auth().currentUser == nil)
    }
}
```

- [ ] **Step 3: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/LeaveFamilyModelTests -only-testing:KidCareTests/PrivacyPolicyLinkTests -only-testing:KidCareTests/LeaveFamilyTests`
Expected: 컴파일 실패. `cannot find 'LeaveFamilyModel' in scope`, `cannot find 'LeaveFamilyRepository' in scope`, `cannot find 'PrivacyPolicyLink' in scope`.

- [ ] **Step 4: 저장소를 쓴다**

`ios/KidCare/Core/LeaveFamilyRepository.swift`:

```swift
import FirebaseAuth
import FirebaseFirestore
import Foundation

/// "이 아이폰을 가족에서 빼기"의 서버 쪽(7단계 계획서 판정 기록 8).
///
/// **안드로이드에는 대응물이 없다.** App Store 가이드라인 5.1.1(v)(계정을 만드는 앱은 앱 안에서 삭제도 제공)
/// 때문에 iOS 에만 둔다. 규칙은 고치지 않는다 — 보호자는 자기 멤버 문서를 지울 수 있다
/// (firestore.rules members `allow delete: if memberOf(familyId) && roleIn(familyId) == 'guardian'`).
///
/// 지우지 못하는 것(아이가 쓴 기록, 가족 공용 예약·장소, 가족 문서, 내가 만든 초대 코드와 명령)은 규칙과
/// 필드 구조 때문이다. 목록과 이유는 판정 기록 8 에 있고, 확인 문구와 처리방침에 그대로 적는다.
enum LeaveFamilyRepository {

    enum AuthOutcome: Equatable, Sendable {
        /// 익명 계정까지 서버에서 지웠다.
        case deleted
        /// 서버가 계정 삭제를 받지 않아 로그아웃만 했다. 남은 익명 계정에는 uid 와 만든 시각뿐이다.
        case signedOutOnly
    }

    private static var db: Firestore { Firestore.firestore() }

    /// `families/{familyId}/members/{uid}` 를 지운다. **이미 빠진 상태면 성공으로 본다.**
    ///
    /// 앞 시도가 시간 초과로 끝났는데 서버에는 닿았다면, 다시 지우려는 지금은 `memberOf` 가 거짓이라
    /// PERMISSION_DENIED 가 난다. 그것을 "아직 멤버인데 거부됐다"와 가르려고 가족 문서를 서버에서 읽는다.
    /// `families` get 도 `memberOf` 라서, 여기서도 거부되면 정말 빠진 것이다. 읽히면 아직 멤버이므로 원래 오류를
    /// 던진다 — 삼키면 가족에는 남았는데 이 폰은 빠졌다고 믿게 된다.
    ///
    /// 한계: 이 계정이 **처음부터** 그 가족의 멤버가 아니었어도 같은 판정(성공)이 난다. 부르는 곳(`LeaveFamilyModel`)은
    /// 늘 이 폰의 `RoleStore.familyId` 와 로그인 uid 를 넘기므로 그 경우가 생기지 않는다.
    static func removeMember(familyId: String, uid: String) async throws {
        let family = db.collection("families").document(familyId)
        do {
            try await family.collection("members").document(uid).delete()
        } catch {
            guard isPermissionDenied(error) else { throw error }
            do {
                _ = try await family.getDocument(source: .server)
            } catch let readError where isPermissionDenied(readError) {
                return
            }
            throw error
        }
    }

    /// 익명 계정을 지운다. 어떤 이유로든 못 지우면 로그아웃만 하고 그렇다고 돌려준다.
    ///
    /// 던지지 않는 이유: 이 함수는 멤버 문서를 지운 **뒤에만** 불린다. 여기서 실패를 화면에 올리면 "가족에서는 빠졌는데
    /// 실패했다"는 모순된 안내가 된다. 익명 계정은 로그아웃하면 다시 들어갈 길이 없으므로 로그아웃이 곧 이 폰에서의 끝이다.
    /// 운영 Auth 가 오래된 익명 로그인에 `requiresRecentLogin` 을 내는지는 확인하지 못했다(판정 기록 8) — 두 갈래 모두 여기서 끝난다.
    static func deleteAuthUser() async -> AuthOutcome {
        guard let user = Auth.auth().currentUser else { return .signedOutOnly }
        do {
            try await user.delete()
            return .deleted
        } catch {
            try? Auth.auth().signOut()
            return .signedOutOnly
        }
    }

    private static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == FirestoreErrorDomain && ns.code == FirestoreErrorCode.permissionDenied.rawValue
    }
}
```

Swift 6 가 `user.delete()` 를 "non-Sendable `User` 를 넘긴다"로 막으면, `AuthGateway` 가 `signInAnonymously` 를 actor 안 `Task` 에서 부르는 것과 같은 모양으로 옮긴다. `nonisolated(unsafe)` 로 막지 않는다(Global Constraints).

- [ ] **Step 5: 뷰모델과 링크를 쓴다**

`ios/KidCare/Guardian/PrivacyPolicyLink.swift`:

```swift
import Foundation

/// 개인정보 처리방침 주소(가이드라인 5.1.1(i) — 앱 안에서도 닿아야 한다). 값은 `project.yml` 의 Info.plist 속성
/// `KidCarePrivacyPolicyURL` 에서 온다. 주인이 게시하기 전에는 비어 있고, 그동안 메뉴에 줄이 뜨지 않는다(7단계 판정 기록 9).
enum PrivacyPolicyLink {
    static func url(info: [String: Any]? = Bundle.main.infoDictionary) -> URL? {
        guard let text = info?["KidCarePrivacyPolicyURL"] as? String, text.hasPrefix("https://") else { return nil }
        return URL(string: text)
    }
}
```

`ios/KidCare/Guardian/LeaveFamilyModel.swift`:

```swift
import Foundation
import Observation

/// "이 아이폰을 가족에서 빼기"의 판단(7단계 계획서 판정 기록 8). 순서는 **서버 확인 → 계정 → 이 폰** 이다.
///
/// 서버가 확인하기 전에 이 폰의 기록을 지우면, 가족에는 이 폰이 남았는데 이 폰은 빠졌다고 믿는 상태가 된다 — 그러면
/// 다시 합류해도 옛 멤버 문서가 영영 남는다. 그래서 서버 확인이 오기 전에는 아무것도 지우지 않는다.
@MainActor
@Observable
final class LeaveFamilyModel {

    typealias RemoveMember = @Sendable (_ familyId: String, _ uid: String) async throws -> Void
    typealias DeleteAuth = @Sendable () async -> LeaveFamilyRepository.AuthOutcome

    /// 서버 확인을 기다리는 한도. `FamilyRepository.measureTimeoutNanos`(15초)와 같은 값이다 — 둘 다 "오프라인이면
    /// 서버 확인이 영영 안 온다"는 같은 사실을 막는 장치다.
    nonisolated static let timeoutMillis: Int64 = 15_000

    let familyId: String
    private(set) var 묻는중 = false
    private(set) var 빼는중 = false
    private(set) var 실패_문구: String?
    private(set) var 계정_결과: LeaveFamilyRepository.AuthOutcome?

    private let currentUid: @Sendable () -> String?
    private let removeMember: RemoveMember
    private let deleteAuth: DeleteAuth
    private let clearLocal: @MainActor () -> Void
    private let sleep: @Sendable (Int64) async -> Void

    init(
        familyId: String,
        currentUid: @escaping @Sendable () -> String? = { AuthGateway.currentUid() },
        removeMember: @escaping RemoveMember = LeaveFamilyRepository.removeMember,
        deleteAuth: @escaping DeleteAuth = LeaveFamilyRepository.deleteAuthUser,
        clearLocal: @escaping @MainActor () -> Void = LeaveFamilyModel.이_폰의_기록을_지운다,
        sleep: @escaping @Sendable (Int64) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }
    ) {
        self.familyId = familyId
        self.currentUid = currentUid
        self.removeMember = removeMember
        self.deleteAuth = deleteAuth
        self.clearLocal = clearLocal
        self.sleep = sleep
    }

    /// 확인 대화상자 본문. 보호자가 이 폰 하나(또는 아직 목록을 못 받은 0)면 경고를 앞에 붙인다 — 막지는 않는다.
    static func 확인_문구(보호자_수: Int) -> String {
        let base = String(localized: "ios_leave_family_message")
        guard 보호자_수 <= 1 else { return base }
        return String(format: String(localized: "ios_leave_family_last_guardian_format"), base)
    }

    func 묻는다() {
        guard !빼는중 else { return }
        실패_문구 = nil
        묻는중 = true
    }

    func 취소한다() {
        묻는중 = false
    }

    func 실패를_닫는다() {
        실패_문구 = nil
    }

    func 뺀다() async {
        guard !빼는중 else { return }
        묻는중 = false
        빼는중 = true
        실패_문구 = nil
        defer { 빼는중 = false }

        guard let uid = currentUid() else {
            // 로그인한 적이 없으면 서버에 이 폰의 흔적이 없다. 이 폰의 기록만 지운다.
            clearLocal()
            return
        }
        let familyId = familyId
        let removeMember = removeMember
        do {
            let confirmed = try await firstToFinish(timeoutMillis: Self.timeoutMillis, sleep: sleep) {
                try await removeMember(familyId, uid)
                return true
            }
            guard confirmed == true else {
                실패_문구 = String(localized: "ios_leave_family_offline")
                return
            }
        } catch {
            실패_문구 = errorMessage(error)
            return
        }
        계정_결과 = await deleteAuth()
        clearLocal()
    }

    /// 이 폰에 남은 가족 기록을 지운다. 역할·가족·아이(`RoleStore`), 명령 기록(`RequestLog`), 알람 메모(`AlarmMemoStore`),
    /// 못 보낸 알림 깃발(`RuleSyncStore`)이 모두 같은 `UserDefaults.standard` 에 있다.
    static func 이_폰의_기록을_지운다() {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        // 마지막에 부른다 — RouterView 가 familyId 가 nil 이 되는 것을 보고 첫 화면으로 간다.
        RoleStore.shared.clear()
    }
}
```

- [ ] **Step 6: 메뉴·본 화면·라우터를 잇는다**

`ios/KidCare/Guardian/ChildSelectorBar.swift` 의 `struct ChildMenu`:

1. `let model: ChildSelectorModel` 아래에 더한다.

```swift
    /// 본 화면이 넘겨준 빼기 뷰모델. 미리보기처럼 없는 곳에서는 줄을 그리지 않는다.
    @Environment(LeaveFamilyModel.self) private var leave: LeaveFamilyModel?
    @Environment(\.openURL) private var openURL
```

2. `Button(model.보호자_초대_문구) { model.초대한다(.guardian) }` 와 그 `.disabled(ReadOnlyCheck.isOn)` 바로 아래에 더한다.

```swift
            // App Store 가이드라인 5.1.1 — 처리방침 링크와 계정 삭제는 앱 안에서 닿아야 한다(7단계 판정 기록 8·9).
            // 안드로이드 메뉴에는 없는 줄이다. 선택기 줄과 지도 카드가 이 메뉴를 함께 쓰므로 모든 탭에서 닿는다.
            Divider()
            if let url = PrivacyPolicyLink.url() {
                Button { openURL(url) } label: { Text("ios_privacy_policy") }
            }
            if let leave {
                // 실기기 읽기 전용 확인에서는 누를 수 없다(6단계 판정 기록 10 과 같은 자리).
                Button(role: .destructive) { leave.묻는다() } label: { Text("ios_leave_family_menu") }
                    .disabled(ReadOnlyCheck.isOn)
            }
```

`ios/KidCare/Guardian/GuardianHomeView.swift`:

1. `@State private var selector: ChildSelectorModel` 아래에 `@State private var leave: LeaveFamilyModel` 을 더한다. `init` 의 `_selector = …` 아래에 `_leave = State(initialValue: LeaveFamilyModel(familyId: familyId))` 를 더한다.
2. `body` 의 `.environment(selector)` 바로 아래에 더한다.

```swift
        .environment(leave)
        // 확인 → 빼기. 누르는 순간 대화상자는 닫히고(isPresented 가 false 로) 빼기는 따로 돈다.
        .confirmationDialog(
            Text("ios_leave_family_title"),
            isPresented: Binding(get: { leave.묻는중 }, set: { if !$0 { leave.취소한다() } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) { Task { await leave.뺀다() } } label: { Text("ios_leave_family_confirm") }
            Button(role: .cancel) { leave.취소한다() } label: { Text("ios_leave_family_cancel") }
        } message: {
            Text(verbatim: LeaveFamilyModel.확인_문구(보호자_수: selector.guardians.count))
        }
        .alert(
            Text("ios_leave_family_failed_title"),
            isPresented: Binding(get: { leave.실패_문구 != nil }, set: { if !$0 { leave.실패를_닫는다() } })
        ) {
            Button(role: .cancel) { leave.실패를_닫는다() } label: { Text("ios_leave_family_failed_ok") }
        } message: {
            Text(verbatim: leave.실패_문구 ?? "")
        }
        // 빼는 동안에는 다른 버튼을 누를 수 없게 덮는다 — 반쯤 빠진 가족에 명령이 나가지 않게.
        .overlay {
            if leave.빼는중 {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("ios_leave_family_in_progress")
                            .font(.system(size: 15))
                            .foregroundStyle(KidCarePalette.ink)
                    }
                    .padding(24)
                    .background(KidCarePalette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
```

`ios/KidCare/RouterView.swift` 의 `body` 를 이것으로 바꾼다(6단계 모양에서 `Group` 과 `onChange` 만 더한다).

```swift
    var body: some View {
        Group {
            if isRunningTests {
                Color.clear
            } else if showMain, let familyId = store.familyId {
                GuardianHomeView(familyId: familyId)
                    // 가족이 바뀌면 선택기까지 새로 만든다. 아이가 바뀌면 GuardianHomeView 안에서 탭만 새로 만든다
                    // (통합 검토 M1 의 .id(familyId+childUid) 를 두 겹으로 나눴다 — 6단계 판정 기록 7).
                    .id(familyId)
            } else {
                RoleSelectView(onGuardianReady: { showMain = true })
            }
        }
        // 가족에서 빠지면(7단계 판정 기록 8) familyId 가 nil 이 된다. showMain 을 되돌려 두지 않으면, 다시 합류하는
        // 도중 InviteCodeView 가 familyId 를 쓰는 순간 코드를 보기도 전에 본 화면으로 튕긴다 — 1단계 1차 리뷰
        // CRITICAL 과 같은 사고다(이 파일 머리 주석).
        .onChange(of: store.familyId) { _, newValue in
            if newValue == nil { showMain = false }
        }
    }
```

- [ ] **Step 7: 통과를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`(에뮬레이터를 띄운 채)
Expected: 전체 PASS. `LeaveFamilyModelTests` 7개, `PrivacyPolicyLinkTests` 1개, `LeaveFamilyTests` 4개가 새로 들어간다(M+5+12). `LocalizableCatalogTests.코드가_부르는_키는_카탈로그에_있다` 는 새 키 11개를 Step 1 에서 넣었으므로 초록이다.

`계정_삭제` 가 에뮬레이터에서 `.signedOutOnly` 로 실패하면 **멈추고 보고한다.** 에뮬레이터가 방금 만든 익명 계정 삭제를 거부했다는 뜻이고, 판정 기록 8 의 가정이 흔들린다.

```bash
cd /Users/com/work/KidCare
git diff --stat firestore.rules app                                  # 비어 있어야 한다
grep -rn "ios_leave_family_\|ios_privacy_policy" ios/KidCare --include='*.swift' | wc -l   # 12 이상
grep -c "ios_leave_family_\|ios_privacy_policy" i18n/ko.json i18n/en.json   # 각 11
```

- [ ] **Step 8: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Core/LeaveFamilyRepository.swift ios/KidCare/Guardian/LeaveFamilyModel.swift ios/KidCare/Guardian/PrivacyPolicyLink.swift \
  ios/KidCare/Guardian/ChildSelectorBar.swift ios/KidCare/Guardian/GuardianHomeView.swift ios/KidCare/RouterView.swift \
  ios/KidCareTests/LeaveFamilyModelTests.swift ios/KidCareTests/LeaveFamilyTests.swift \
  i18n/ko.json i18n/en.json tools/i18n-untranslated.json ios/KidCare/Localizable.xcstrings
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 7단계 Task 2: 이 아이폰을 가족에서 빼기 — 서버가 확인한 뒤에만 계정과 이 폰의 기록을 지우고, 처리방침 줄을 메뉴에 둔다"
```

---
### Task 3: App Store Connect 원고 — 이름·설명·키워드, 영양 라벨 답, 심사 메모, 처리방침

**끝나면 `docs/app-store/` 네 파일에 주인이 App Store Connect 에 붙여 넣을 글이 한국어(기본)와 영어로 있다.** 코드 변경은 없다. 주인만 채울 수 있는 값은 모두 `【주인이 채움: …】` 로 표시한다. 이 계획서는 URL·연락처·이름을 지어내지 않는다.

**Files:**
- Create: `docs/app-store/metadata.md`, `docs/app-store/privacy-label.md`, `docs/app-store/review-notes.md`, `docs/app-store/privacy-policy.md`

**Interfaces:**
- Consumes: Task 1 `ReleaseConfigTests.신고한_수집_항목`(여섯 개), `KidCarePrivacyPolicyURL`. Task 2 메뉴 문구 `ios_leave_family_menu`("이 아이폰을 가족에서 빼기" / "Remove this iPhone from the family"), `ios_privacy_policy`.
- Produces: Task 4 README "아이폰 TestFlight로 올리는 법"이 이 네 파일을 가리킨다.

**글자 수 한도**(App Store Connect 입력칸, 2026-09 기준으로 알고 있는 값 — 칸 옆 카운터로 다시 본다): 이름 30, 부제 30, 프로모션 텍스트 170, 설명 4,000, 키워드 100(쉼표 포함).

- [ ] **Step 1: `docs/app-store/metadata.md` 를 쓴다**

````markdown
# App Store Connect 원고 — 우리아이 지킴이 (아이폰 보호자 앱)

붙여 넣는 곳: App Store Connect → 앱 → 우리아이 지킴이 → 배포(Distribution) → iOS 앱 → 버전 1.0.
기본 언어는 **한국어**, 추가 현지화는 **영어(미국)** 하나다. 나머지 12개 언어는 앱 안에만 있다(스토어 문구 번역을 지어내지 않는다).
`【주인이 채움】` 이 남아 있으면 제출하지 않는다.

## 공통

| 칸 | 값 |
|---|---|
| 번들 ID | `com.kidcare.family` |
| SKU | `kidcare-ios-guardian` |
| 1차 카테고리 | 라이프스타일 (Lifestyle) |
| 2차 카테고리 | 유틸리티 (Utilities) |
| 키즈 카테고리 | **넣지 않는다** — 부모가 쓰는 앱이다(7단계 판정 기록 12) |
| 가격 | 무료 |
| 저작권 | `2026 【주인이 채움: App Store 판매자 이름과 같게】` |
| 지원 URL | `【주인이 채움: 지원 페이지 https 주소】` |
| 마케팅 URL | 비워 둔다(선택 칸) |
| 개인정보 처리방침 URL | `【주인이 채움: privacy-policy.md 를 게시한 https 주소】` — 같은 값을 `ios/project.yml` 의 `KidCarePrivacyPolicyURL` 에도 넣는다 |
| 수출 규정 | Info.plist `ITSAppUsesNonExemptEncryption = false` 라 묻지 않는다(판정 기록 3) |

## 한국어

**이름** (8자)
```
우리아이 지킴이
```
같은 이름이 이미 있으면 App Store Connect 가 거부한다. 그때 대안: `우리아이 지킴이 보호자`

**부제** (19자)
```
아이 폰의 하루를 부모가 확인해요
```

**프로모션 텍스트**
```
아이 폰(안드로이드)이 오늘 어디에 머물렀고 어떻게 움직였는지, 소리 모드와 배터리는 어떤지 아이폰에서 확인하세요.
```

**설명**
```
우리아이 지킴이는 부모가 아이폰으로 아이 폰을 살피는 앱입니다.

아이 폰은 안드로이드여야 합니다. 아이 폰에 설치한 우리아이 지킴이(아이용)와 같은 가족으로 연결해 씁니다. 가족의 보호자가 보낸 초대 번호를 넣으면 합류하고, 아이폰만 있는 집은 새 가족을 만들어 아이 폰을 초대할 수 있습니다.

■ 지도
· 아이가 하루 동안 머문 곳과 이동한 경로를 지도와 타임라인으로 보여줍니다.
· 날짜를 넘겨 지난 기록을 봅니다.
· '지금 위치 확인'으로 아이 폰에 현재 위치를 물어보고, 실시간 보기로 10분 동안 따라갑니다.

■ 관리
· 아이 폰의 소리·진동·무음을 바꿉니다.
· 핸드폰 찾기로 아이 폰을 울립니다.
· 아이 폰에 짧은 메시지를 보내고, 알람을 맞춥니다.
· 아이 폰이 대답하지 않으면 모든 탭 위에 알려 줍니다.

■ 예약
· 학교·학원 시간에 아이 폰이 저절로 무음이 되도록 요일과 시간대를 정합니다.
· 공휴일에는 예약을 쉬게 할 수 있습니다.

■ 장소
· 학교, 학원, 할머니 댁을 지도에서 고르면 아이가 도착하거나 나설 때 기록됩니다.

■ 알림
· 도착·이탈·배터리 부족 같은 소식을 앱을 열었을 때 모아서 보여줍니다. 아이폰에서는 푸시 알림을 보내지 않습니다.

■ 가족
· 아이 여럿, 보호자 여럿이 한 가족으로 함께 씁니다.
· 14개 언어를 지원합니다.

■ 개인정보
· 이 앱은 위치, 알림, 카메라, 연락처 등 어떤 권한도 요청하지 않습니다.
· 아이 폰은 몰래 감시하지 않습니다. 아이 폰에는 앱 아이콘과 "위치 공유 중" 알림이 항상 보입니다.
· 메뉴의 '이 아이폰을 가족에서 빼기'로 언제든 이 아이폰의 연결과 계정을 지울 수 있습니다.
```

**키워드** (100자 이내, 쉼표 뒤 공백 없음)
```
위치,가족,자녀,보호자,안심,경로,타임라인,무음,예약,장소,도착알림,핸드폰찾기,배터리
```

## English (U.S.)

**Name**
```
KidCare
```
If taken: `KidCare Family Guardian`

**Subtitle**
```
See your child's phone and day
```

**Promotional Text**
```
Check where your child's Android phone stayed today, how it moved, and its sound mode and battery, right from your iPhone.
```

**Description**
```
KidCare lets a parent look after their child's phone from an iPhone.

Your child's phone must be an Android phone running KidCare (child app) in the same family. Join with an invite code from a guardian in the family, or create a new family on this iPhone and invite your child's phone.

MAP
- See where your child stayed and how they moved today, on a map and a timeline.
- Go back to earlier days.
- Ask your child's phone for its current location, or follow it live for 10 minutes.

CONTROL
- Switch your child's phone between sound, vibrate and silent.
- Ring your child's phone to find it.
- Send a short message and set an alarm on your child's phone.
- If your child's phone stops answering, a banner appears on every tab.

SCHEDULE
- Set days and times when your child's phone goes silent on its own, such as school hours.
- Pause schedules on public holidays.

PLACES
- Pick places such as school on the map; arrivals and departures are recorded.

ALERTS
- Arrivals, departures and low battery are collected and shown when you open the app. The iPhone app does not send push notifications.

FAMILY
- Several children and several guardians can share one family.
- Available in 14 languages.

PRIVACY
- This app asks for no permissions: no location, notifications, camera or contacts.
- No hidden tracking: your child's phone always shows the app icon and a "sharing location" notification.
- Use "Remove this iPhone from the family" in the menu to delete this iPhone's link and account at any time.
```

**Keywords**
```
family,kids,child,location,parent,guardian,safety,timeline,silent,schedule,geofence,find phone
```

## 연령 등급 설문 답 (App Store Connect → 앱 정보 → 연령 등급)

설문 문항 이름은 해마다 바뀐다. 아래는 **사실**이고, 칸 이름이 다르면 사실에 맞는 답을 고른다.

| 사실 | 답 |
|---|---|
| 폭력·성적 내용·욕설·약물·도박·공포 요소 | 없음 |
| 웹 브라우저·무제한 웹 접근 | 없음(처리방침 링크만 시스템 브라우저로 연다) |
| 사용자끼리의 메시지 | **가족 안 한 방향**(보호자 → 아이 폰 짧은 메시지). 공개 채팅·낯선 사람과의 연락 없음 |
| 사용자 생성 콘텐츠의 공개 | 없음 |
| 위치 공유 | 가족 안에서만(아이 폰 → 같은 가족 보호자) |
| 보호자 통제(Parental Controls) 기능 | 있음 — 이 앱의 목적이다 |
| 광고 | 없음 |

## 스크린샷 (App Store 제출에만 필요, TestFlight 는 불필요)

- 6.9형(iPhone 17 Pro Max 등) 세로 3~10장. 탭 다섯(지도·알림·관리·예약·장소) 한 장씩이 기본이다.
- **진짜 가족의 아이 이름·위치가 보이면 쓰지 않는다.** 에뮬레이터 가족(`kidcare-emulator`)으로 시뮬레이터에서 찍는다.
- 【주인이 채움: 찍은 파일 위치】
````

- [ ] **Step 2: `docs/app-store/privacy-label.md` 를 쓴다**

````markdown
# App Store 개인정보 영양 라벨 답 — 우리아이 지킴이 (iOS)

붙여 넣는 곳: App Store Connect → 앱 → 앱 개인정보 보호(App Privacy) → 시작하기.
근거: `docs/superpowers/plans/2026-09-13-kidcare-ios-phase7.md` 판정 기록 2. 앱 매니페스트(`ios/KidCare/PrivacyInfo.xcprivacy`)의 여섯 항목과 같고,
Firebase SDK 가 스스로 신고하는 진단 데이터 하나를 더했다. `ReleaseConfigTests.신고한_수집_항목` 을 바꾸면 이 파일도 같이 바꾼다.

## 기본 질문

| 질문 | 답 |
|---|---|
| 이 앱에서 데이터를 수집합니까? | **예** |
| 추적(다른 회사 앱·웹사이트 데이터와 연결하거나 데이터 브로커와 공유)에 사용합니까? | **아니요**(모든 항목) |

## 수집하는 데이터

넓게 신고하는 이유: 안드로이드 아이 앱이 모은 데이터라도 **같은 개발자·같은 서버**에 저장되고 이 앱이 보여준다. 적게 신고하는 쪽이 거부 사유가 된다.

| App Store Connect 분류 | 사용자에게 연결 | 추적 | 목적 | 이 앱에서의 실체 | 매니페스트 키 |
|---|---|---|---|---|---|
| 위치 → 정확한 위치 | 예 | 아니요 | 앱 기능 | 아이 폰 위치·경로(표시), 보호자가 고른 장소 좌표(저장) | `NSPrivacyCollectedDataTypePreciseLocation` |
| 연락처 정보 → 이름 | 예 | 아니요 | 앱 기능 | 가족 안 표시 이름(아이 이름은 안드로이드 페어링에서 입력) | `NSPrivacyCollectedDataTypeName` |
| 식별자 → 사용자 ID | 예 | 아니요 | 앱 기능 | Firebase 익명 uid | `NSPrivacyCollectedDataTypeUserID` |
| 사용자 콘텐츠 → 이메일 또는 문자 메시지 | 예 | 아니요 | 앱 기능 | 아이 폰에 보내는 짧은 메시지 | `NSPrivacyCollectedDataTypeEmailsOrTextMessages` |
| 사용자 콘텐츠 → 기타 사용자 콘텐츠 | 예 | 아니요 | 앱 기능 | 알람 이름, 예약·장소 이름 | `NSPrivacyCollectedDataTypeOtherUserContent` |
| 기타 데이터 → 기타 데이터 유형 | 예 | 아니요 | 앱 기능 | 아이 폰 배터리·소리 모드·연결 상태, 도착·이탈 기록 | `NSPrivacyCollectedDataTypeOtherDataTypes` |
| 진단 → 기타 진단 데이터 | **아니요** | 아니요 | 분석 | Firebase Auth·Firestore SDK 가 스스로 신고하는 항목(`FirebaseAuth`·`Firestore` 의 `PrivacyInfo.xcprivacy`) | SDK 매니페스트 |

## 수집하지 않는 데이터 (체크하지 않는다)

- 연락처 정보 중 이메일 주소·전화번호·실제 주소 — 이 앱은 묻지 않는다(로그인 없음)
- 건강 및 피트니스, 금융 정보, 민감한 정보
- 연락처(주소록), 사진 또는 비디오, 오디오 데이터, 게임 플레이 콘텐츠, 고객 지원
- 검색 기록, 방문 기록
- 식별자 중 기기 ID — `members.fcmToken` 은 iOS 에서 늘 빈 값이다(`Documents.swift` `MemberDoc`)
- 구매 내역
- 사용 데이터(제품 상호 작용, 광고 데이터) — 분석·광고 SDK 없음
- 진단 중 충돌 데이터·성능 데이터 — Crashlytics·Performance 미사용
- 위치 중 대략적인 위치 — 정확한 위치로 신고했다

## 데이터 삭제 안내(심사에서 물으면)

앱 메뉴 → "이 아이폰을 가족에서 빼기": 서버의 이 아이폰 멤버 기록 → Firebase 익명 계정 → 기기에 저장된 가족 정보 순으로 지운다.
아이 폰이 올린 기록과 가족 공용 예약·장소는 규칙상 이 아이폰이 지울 수 없어 남는다. 처리방침의 연락처로 요청하면 운영자가 지운다.
````

- [ ] **Step 3: `docs/app-store/review-notes.md` 를 쓴다**

````markdown
# 심사 메모 — App Review / TestFlight Beta App Review

붙여 넣는 곳:
- App Store 제출: App Store Connect → 앱 → 배포 → 버전 1.0 → **앱 심사 정보**(App Review Information) → 메모. "로그인 필요" 체크는 **끈다**.
- TestFlight **외부** 테스트: TestFlight → 테스트 정보(Test Information) → 베타 앱 심사 정보 → 메모, 그리고 "테스트할 항목(What to Test)". 내부 테스트에는 필요 없다.

심사자는 영어로 읽는다. 영어를 붙여 넣고 한국어는 주인 확인용이다. `【주인이 채움】` 이 남아 있으면 제출하지 않는다.

## Notes (English — paste this)

```
KidCare (iOS) is the GUARDIAN app of a two-device family service. The child's phone runs our Android child app; iOS supports only the guardian role because the child features (remote ringer switching, find-phone siren) are not possible on iOS.

No login. The app signs in anonymously with Firebase. There is no username or password to provide.

HOW TO REVIEW
Pairing requires a child phone, and invite codes expire after 10 minutes, so we cannot put a fixed code here.
1. Demo video of every screen: 【OWNER: https video URL】
2. Live demo family: during review we keep a demo family online with an Android test phone. Contact 【OWNER: email / phone】 and we will send a guardian invite code within 【OWNER: hours】. On the first screen tap "Parent (mum or dad)" > "Join an existing family with a code" and enter it.
3. Without a code, the first screen, the role selection, and "Create a new family" (which shows an invite code for a child phone) can be reviewed.

PERMISSIONS AND BACKGROUND
- The app requests no permissions (no location, notifications, camera, photos, contacts, tracking).
- No background modes. The iOS app does not collect this device's location.
- No push notifications. Alerts are shown when the app is opened.

CHILD CONSENT
The child's location is collected by the Android child app, which always shows its app icon and a persistent "sharing location" notification. Pairing requires physically entering a code on the child's phone. This app is for parents and is not in the Kids category.

ACCOUNT DELETION (5.1.1(v))
Menu (tap the child name at the top of any tab) > "Remove this iPhone from the family". This deletes the member record, the anonymous Firebase account and the family data stored on the device.

PRIVACY POLICY
In-app: the same menu > "Privacy Policy". URL: 【OWNER: https privacy policy URL】

ENCRYPTION
Only standard TLS for network connections (Firebase, map tiles). ITSAppUsesNonExemptEncryption is set to NO.
```

## What to Test (TestFlight 외부 테스트, English)

```
Join your family with a guardian invite code, then check the Map, Alerts, Control, Schedule and Places tabs for your child. Please report anything that looks different from the Android guardian app.
```

## 메모 (한국어 — 주인 확인용)

KidCare(iOS)는 두 기기 가족 서비스의 **보호자** 앱이다. 아이 폰은 안드로이드 아이 앱을 쓴다. 아이 역할은 iOS 에서 불가능한 기능(원격 소리 전환, 폰찾기 사이렌)이 있어 만들지 않았다.

- 로그인 없음(Firebase 익명 로그인). 줄 계정이 없다.
- 페어링에 아이 폰이 필요하고 초대 코드는 10분 만료다. 그래서 시연 영상 + 심사 기간 동안 켜 두는 데모 가족 + 연락하면 보호자 초대 코드를 보내는 방식으로 대신한다.
- 권한 요청 0개, 배경 모드 없음, 이 기기 위치 수집 없음, 푸시 없음.
- 아이 동의: 안드로이드 아이 앱은 아이콘과 "위치 공유 중" 알림을 늘 보인다. 페어링은 아이 폰에 직접 코드를 넣어야 된다. 키즈 카테고리 아님.
- 계정 삭제: 메뉴 → "이 아이폰을 가족에서 빼기".
- 처리방침: 같은 메뉴 → "개인정보 처리방침".
- 암호화: 표준 TLS 만.

**버튼 이름 확인.** 위 영어 메모의 "Parent (mum or dad)"·"Join an existing family with a code"·"Create a new family" 는 `i18n/en.json` 의 `role_guardian`·`guardian_start_join_family`·`guardian_start_new_family` 값과 글자까지 같아야 한다. Task 3 Step 5 가 대조한다.
````

- [ ] **Step 4: `docs/app-store/privacy-policy.md` 를 쓴다**

````markdown
# 개인정보 처리방침 원고 — 우리아이 지킴이

이 파일은 **원고**다. 주인이 웹에 게시하고 그 https 주소를 App Store Connect 와 `ios/project.yml` 의 `KidCarePrivacyPolicyURL` 에 넣는다.
**게시 전에 주인이 법률 검토를 한다.** 특히 만 14세 미만 아동의 개인정보(개인정보 보호법 제22조의2 법정대리인 동의)와 국외 이전 항목을 확인한다.
`【주인이 채움】` 이 남아 있으면 게시하지 않는다.

---

## 한국어

**우리아이 지킴이 개인정보 처리방침**

시행일: 【주인이 채움: YYYY-MM-DD】
운영자: 【주인이 채움: 이름】 · 연락처: 【주인이 채움: 이메일】

우리아이 지킴이(이하 "앱")는 보호자가 자녀의 휴대폰 상태를 확인하도록 돕는 가족용 앱입니다. 안드로이드 아이 앱과 안드로이드·아이폰 보호자 앱이 같은 서버를 씁니다.

**1. 처리하는 정보와 목적**

| 정보 | 어디서 생기나 | 목적 |
|---|---|---|
| 익명 사용자 ID | 앱을 처음 연결할 때 자동 생성(Firebase 익명 로그인) | 같은 가족만 정보를 보게 하기 |
| 가족 안 표시 이름 | 페어링할 때 입력(아이 이름 등) | 가족 구성원 구분 |
| 아이 폰 위치와 이동 경로 | 아이 폰(안드로이드) | 지도·타임라인 표시 |
| 아이 폰 배터리, 소리 모드, 연결 상태, 장소 도착·이탈 기록 | 아이 폰 | 상태 표시, 알림 목록 |
| 보호자가 정한 장소(이름·좌표·반경), 시간대 예약 | 보호자 앱 | 도착·이탈 기록, 소리 자동 전환 |
| 보호자가 보낸 메시지와 알람 이름 | 보호자 앱 | 아이 폰에 전달 |

아이폰 보호자 앱은 **이 아이폰의 위치를 수집하지 않고**, 위치·알림·카메라·연락처 등 어떤 권한도 요청하지 않습니다. 광고와 외부 분석 도구를 쓰지 않으며 정보를 판매하거나 추적에 쓰지 않습니다.

**2. 보관 장소와 처리 위탁**

- Google LLC — Firebase Authentication, Cloud Firestore. 가족 데이터는 Cloud Firestore 서울 리전(asia-northeast3)에 저장됩니다. 익명 로그인 정보는 Google 의 전 세계 인프라에서 처리될 수 있습니다.
- NAVER Cloud — 지도 표시(지도 타일 요청). 앱은 가족 데이터를 네이버에 보내지 않습니다.
- 【주인이 채움: 국외 이전 고지 문구 — 법률 검토 결과】

**3. 보유 기간**

위치 기록 등 가족 데이터는 현재 **자동으로 지우지 않습니다.** 가족 구성원이 앱에서 지우거나(아래 4), 운영자에게 삭제를 요청하면 지웁니다.

**4. 삭제 방법**

- 아이폰 보호자 앱: 메뉴 → "이 아이폰을 가족에서 빼기". 이 아이폰의 가족 멤버 기록, 익명 계정, 기기에 저장된 가족 정보를 지웁니다.
- 앱에서 지울 수 없는 정보(아이 폰이 올린 위치·상태 기록, 가족 공용 예약·장소, 가족 자체): 【주인이 채움: 이메일】로 가족을 알려 주시면 【주인이 채움: 기간】 안에 지웁니다.
- 앱을 삭제하면 기기에 남은 정보는 함께 지워집니다.

**5. 아동의 개인정보**

아이 폰은 보호자(법정대리인)가 직접 설치하고 초대 번호로 연결합니다. 아이 폰에는 앱 아이콘과 "위치 공유 중" 알림이 항상 보여, 아이도 공유 중임을 알 수 있습니다. 【주인이 채움: 법정대리인 동의 확인 방법 — 법률 검토 결과】

**6. 안전성 확보 조치**

모든 통신은 암호화(TLS)됩니다. 서버 보안 규칙은 같은 가족 구성원만 그 가족의 정보를 읽게 합니다.

**7. 문의**

【주인이 채움: 이메일】

---

## English

**KidCare Privacy Policy**

Effective date: 【OWNER: YYYY-MM-DD】
Operator: 【OWNER: name】 · Contact: 【OWNER: email】

KidCare ("the app") helps parents check on their child's phone. The Android child app and the Android and iPhone guardian apps share one server.

**1. Information we process and why**

| Information | Where it comes from | Purpose |
|---|---|---|
| Anonymous user ID | Created automatically when the app is first linked (Firebase anonymous sign-in) | Letting only your family see your family's data |
| Display name within the family | Entered during pairing (e.g. a child's name) | Telling family members apart |
| Child phone location and route | Child's Android phone | Map and timeline |
| Child phone battery, sound mode, connection status, place arrivals/departures | Child's phone | Status and alert list |
| Places set by a guardian (name, coordinates, radius), time schedules | Guardian app | Arrival records, automatic sound switching |
| Messages and alarm labels sent by a guardian | Guardian app | Delivery to the child's phone |

The iPhone guardian app does **not** collect the iPhone's location and asks for no permissions (location, notifications, camera, contacts). We use no advertising or third-party analytics, and we do not sell data or use it for tracking.

**2. Storage and processors**

- Google LLC — Firebase Authentication and Cloud Firestore. Family data is stored in the Cloud Firestore Seoul region (asia-northeast3). Anonymous sign-in data may be processed on Google's global infrastructure.
- NAVER Cloud — map display (map tile requests). The app does not send family data to NAVER.

**3. Retention**

Family data such as location history is currently **not deleted automatically**. It is deleted when removed in the app (section 4) or on request.

**4. Deleting your data**

- iPhone guardian app: Menu > "Remove this iPhone from the family". This deletes this iPhone's family membership record, its anonymous account and the family data stored on the device.
- Data the app cannot delete (records uploaded by the child's phone, shared schedules and places, the family itself): email 【OWNER: email】 and we will delete it within 【OWNER: period】.
- Deleting the app removes the data stored on the device.

**5. Children**

A parent or legal guardian installs the child app and links it with an invite code. The child's phone always shows the app icon and a "sharing location" notification.

**6. Security**

All connections are encrypted (TLS). Server security rules allow only members of a family to read that family's data.

**7. Contact**

【OWNER: email】
````

- [ ] **Step 5: 원고가 코드와 어긋나지 않았는지 대조한다**

```bash
cd /Users/com/work/KidCare
python3 - <<'PY'
import json, re
en = json.load(open('i18n/en.json', encoding='utf-8'))
ko = json.load(open('i18n/ko.json', encoding='utf-8'))
notes = open('docs/app-store/review-notes.md', encoding='utf-8').read()
policy = open('docs/app-store/privacy-policy.md', encoding='utf-8').read()
meta = open('docs/app-store/metadata.md', encoding='utf-8').read()
label = open('docs/app-store/privacy-label.md', encoding='utf-8').read()
# 심사 메모가 인용한 버튼 글자는 앱과 같아야 한다 — 심사자가 그 글자를 찾는다
for key in ['role_guardian', 'guardian_start_join_family', 'guardian_start_new_family', 'ios_leave_family_menu', 'ios_privacy_policy']:
    assert key in en, key
    assert en[key] in notes, (key, en[key])
for key in ['ios_leave_family_menu']:
    assert ko[key] in policy and en[key] in policy and ko[key] in meta, key
# 영양 라벨 표와 매니페스트 여섯 개가 같다
keys = set(re.findall(r'`(NSPrivacyCollectedDataType\w+)`', label))
manifest = set(re.findall(r'<string>(NSPrivacyCollectedDataType(?!Purpose)\w+)</string>', open('ios/KidCare/PrivacyInfo.xcprivacy').read()))
assert keys == manifest and len(keys) == 6, (keys, manifest)
# 글자 수
assert len('우리아이 지킴이') <= 30 and len('아이 폰의 하루를 부모가 확인해요') <= 30 and len("See your child's phone and day") <= 30
kw_ko = '위치,가족,자녀,보호자,안심,경로,타임라인,무음,예약,장소,도착알림,핸드폰찾기,배터리'
kw_en = 'family,kids,child,location,parent,guardian,safety,timeline,silent,schedule,geofence,find phone'
assert kw_ko in meta and kw_en in meta and len(kw_ko) <= 100 and len(kw_en) <= 100
# 지어낸 URL 이 없다 — 주소 칸은 전부 주인이 채움 표시
assert not re.search(r'https://(?!example)[a-z0-9.-]+\.[a-z]{2,}', meta + notes + policy + label), '실제 주소가 들어갔다'
print('원고 대조 통과')
PY
```

Expected: `원고 대조 통과`. `guardian_start_new_family` 가 `en.json` 에 없거나 값이 다르면 심사 메모의 그 따옴표 글자를 `en.json` 값으로 고치고 다시 돌린다. 키 이름이 다르면 `RoleSelectView.swift` 가 부르는 키를 찾아 쓴다. **앱 문구를 원고에 맞춰 바꾸지 않는다.**

- [ ] **Step 6: 커밋** (공통 절차 B)

```bash
git add docs/app-store/metadata.md docs/app-store/privacy-label.md docs/app-store/review-notes.md docs/app-store/privacy-policy.md
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 7단계 Task 3: App Store Connect 원고 — 이름과 설명, 영양 라벨 답, 심사 메모, 개인정보 처리방침 초안"
```

---

## 단계 마무리 — 통합 리뷰 한 번, 에뮬레이터로 빼기 흐름 한 번

- [ ] **Step 1: 기계 검사**

```bash
cd /Users/com/work/KidCare
git status --short                                                   # 비어 있어야 한다
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew         # 비어 있어야 한다
python3 tools/ios-strings.py --check; echo $?                        # 0
cd ios && xcodegen generate && git -C .. status --short               # xcodegen 이 아무것도 안 바꿔야 한다
xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'   # M+17 PASS(에뮬레이터 켠 채)
```

- [ ] **Step 2: 통합 리뷰** — superpowers:requesting-code-review 로 7단계 첫 커밋의 부모부터 HEAD 까지를 한 번 리뷰받는다. 리뷰어에게 이 계획서의 "판정 기록" 열여섯 줄과 "Pre-flight conflict table" 을 함께 준다. 특히 네 가지를 봐 달라고 적는다.
  1. `LeaveFamilyModel.뺀다` 가 어떤 실패 경로에서도 서버 확인 전에 `clearLocal` 을 부르지 않는가.
  2. `LeaveFamilyRepository.removeMember` 의 PERMISSION_DENIED 삼킴이 "아직 멤버"를 성공으로 잘못 보는 길이 있는가.
  3. `RouterView` 의 `onChange` 가 1단계 CRITICAL(합류 도중 본 화면으로 튕김)을 되살리지 않는가.
  4. 매니페스트·영양 라벨·처리방침 세 문서가 같은 사실을 말하는가.

  지적은 같은 Task 의 "보완" 커밋으로 고친다.

- [ ] **Step 3: 에뮬레이터 시뮬레이터 확인** — 진짜 가족에 쓰지 않는다.
  1. 저장소 루트에서 에뮬레이터를 띄운다.
  2. `ios/KidCare/KidCareApp.swift` 의 `FirebaseBootstrap.configureForApp()` 를 **임시로** `FirebaseBootstrap.configureForEmulator(projectId: "kidcare-emulator")` 로 바꾼다. Debug 빌드라 Task 1 의 `#if DEBUG` 안에서도 부를 수 있다.
  3. iPhone 17 시뮬레이터에서 보호자 → 새 가족 만들기 → 본 화면으로 간다.
  4. 예약 탭 선택기 줄을 누른다. 메뉴 맨 아래에 "이 아이폰을 가족에서 빼기"가 빨간 글씨로 있다. "개인정보 처리방침" 줄은 **없다**(URL 비어 있음).
  5. 누르면 확인 대화상자가 뜨고, 보호자가 하나뿐이므로 "마지막 보호자" 경고가 본문 앞에 있다. "취소" → 아무 일도 없다.
  6. 다시 열어 "빼기" → "가족에서 빼는 중…" 이 잠깐 뜬 뒤 역할 선택 화면이다.
  7. 에뮬레이터 UI(`http://127.0.0.1:4000/firestore`)에서 그 가족의 `members` 가 비었는지 본다. Auth 탭에서 그 익명 사용자가 사라졌는지 본다.
  8. 곧바로 보호자 → 새 가족 만들기를 다시 한다. **초대 번호 화면이 보이고, 번호를 보기 전에 본 화면으로 튕기지 않는다**(RouterView `onChange`).
  9. 에뮬레이터 터미널을 `Ctrl+C` 로 멈춘 뒤 다시 "빼기" 를 누른다. 15초 뒤 "가족에서 빼지 못했어요 / 인터넷에 연결되지 않아…" 알림이 뜨고 본 화면에 그대로 머문다.
  10. `KidCareApp.swift` 를 되돌리고 `git diff ios/KidCare/KidCareApp.swift` 가 비었는지 본다.

  결과(각 항목 통과 여부, 걸린 시간)를 Task 4 개발일지에 적는다. 하나라도 다르면 멈추고 보고한다.

---
### Task 4: 로컬 아카이브·내보내기 검증, 실기기 Release 읽기 확인, 개발일지와 "TestFlight로 올리는 법"

**끝나면 `/tmp/kidcare-p7/` 에 Release `.xcarchive` 와 App Store 용 `.ipa` 가 있고, `tools/ios-release-check.sh` 가 둘 다 "전부 통과"를 낸다.** 실기기에서 Release 빌드가 읽기만으로 확인되고, README 에 7단계 개발일지와 사람이 할 일 목록이 남는다. **아무것도 올리지 않는다.**

**Files:**
- Create: `ios/Config/ExportOptions-AppStore.plist`, `tools/ios-release-check.sh`
- Modify: `README.md`(6단계 개발일지 절 바로 다음에 7단계 절, 문서 표 아래에 "아이폰 TestFlight로 올리는 법")

**Interfaces:**
- Consumes: Task 1 `MARKETING_VERSION 1.0`·`CURRENT_PROJECT_VERSION 1`·`PrivacyInfo.xcprivacy`·`InfoPlist.xcstrings`·`#if DEBUG configureForEmulator`. Task 2 메뉴 줄. Task 3 `docs/app-store/*`. 6단계 `ReadOnlyCheck`(`-readOnlyCheck`), 선택기 메뉴의 초대 두 줄.
- Produces: 명령 `tools/ios-release-check.sh <KidCare.xcarchive | KidCare.ipa> [대조용 Debug KidCare.app]`(종료 코드 0 = 전부 통과), README 절 두 개.

**운영에 닿는 것의 경계.**
- 이 Task 의 `-allowProvisioningUpdates` 는 개발자 포털에서 **서명 자료**(개발·App Store 프로파일)를 받는 데만 쓴다.
- `-exportArchive` 는 `destination = export` 로 로컬 파일만 만든다.
- App Store Connect·TestFlight 에 닿는 명령은 README 절에 **"주인이 확인한 뒤에만"** 으로 적기만 하고 실행하지 않는다.

- [ ] **Step 1: 선행 확인** — 하나라도 다르면 멈추고 보고한다.

```bash
cd /Users/com/work/KidCare
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
git status --short                                         # 비어 있어야 한다
ls ios/Config/Secrets.xcconfig ios/KidCare/GoogleService-Info.plist   # 둘 다 있어야 한다(내용은 열지 않는다)
git check-ignore ios/Config/Secrets.xcconfig ios/KidCare/GoogleService-Info.plist   # 두 줄 — 커밋되지 않는다
security find-identity -v -p codesigning | grep -c "Apple Distribution"   # 1 이상
```

`Apple Distribution` 이 0 이면 **여기서 멈춘다.** 사람이 할 일 A(README 절)를 주인에게 요청한다. 이 계획서는 인증서를 만들지 않는다.

```bash
cd ios && xcodegen generate
xcodebuild -project KidCare.xcodeproj -scheme KidCare -configuration Release -showBuildSettings 2>/dev/null \
  | grep -E '^ +(DEVELOPMENT_TEAM|CODE_SIGN_STYLE|SWIFT_ACTIVE_COMPILATION_CONDITIONS|MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER) =' \
  | sed -E 's/(DEVELOPMENT_TEAM = ).+/\1(값 있음 — 적지 않는다)/'
# 기대: DEVELOPMENT_TEAM 값 있음, Automatic, DEBUG 없음, 1.0, 1, com.kidcare.family
```

- [ ] **Step 2: 내보내기 설정과 검증 스크립트를 만든다**

`ios/Config/ExportOptions-AppStore.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
```

`teamID` 를 넣지 않는다. 아카이브의 팀(= `Secrets.xcconfig`)을 그대로 쓰고, 팀 ID 가 저장소에 남지 않는다. `destination` 을 `upload` 로 바꾸지 않는다 — 바꾸는 순간 이 명령이 올리기가 된다. `manageAppVersionAndBuildNumber = false` 의 이유는 판정 기록 4 다. `plutil -lint ios/Config/ExportOptions-AppStore.plist` → `OK`.

`tools/ios-release-check.sh`(만든 뒤 `chmod +x`):

```bash
#!/usr/bin/env bash
# 출시 산출물(.xcarchive 또는 .ipa)을 열어 7단계 계획서 판정 기록이 요구한 성질을 확인한다.
# 네트워크에 닿지 않는다. 비밀인 값(NMFNcpKeyId, GoogleService-Info.plist)은 있다/없다·길이만 적는다.
#
#   tools/ios-release-check.sh /tmp/kidcare-p7/KidCare.xcarchive [/tmp/kidcare-p7/dd-debug/Build/Products/Debug-iphoneos/KidCare.app]
#   tools/ios-release-check.sh /tmp/kidcare-p7/export/KidCare.ipa [같은 대조군]
#
# 두 번째 인자(Debug 빌드)는 대조군이다. Swift 는 15바이트 이하 문자열을 기계어 안에 넣어 strings 로 안 보이므로,
# "Release 에 없다"가 의미 있으려면 같은 방법으로 Debug 에서는 찾아져야 한다(판정 기록 6).
set -uo pipefail

INPUT="${1:?사용법: tools/ios-release-check.sh <KidCare.xcarchive | KidCare.ipa> [Debug KidCare.app]}"
CONTROL="${2:-}"
WORK="$(mktemp -d /tmp/kidcare-release-check.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
ok()   { printf '  통과  %s\n' "$1"; }
bad()  { printf '  실패  %s\n' "$1"; FAILS=$((FAILS + 1)); }
note() { printf '  참고  %s\n' "$1"; }

case "$INPUT" in
  *.ipa)        unzip -q "$INPUT" -d "$WORK/ipa"; APP="$WORK/ipa/Payload/KidCare.app"; KIND=ipa ;;
  *.xcarchive)  APP="$INPUT/Products/Applications/KidCare.app"; KIND=archive ;;
  *)            echo "모르는 입력: $INPUT"; exit 2 ;;
esac
[ -d "$APP" ] || { echo "KidCare.app 이 없다: $APP"; exit 2; }
INFO="$APP/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

echo "== $KIND: $INPUT"

echo "-- 개인정보 매니페스트 (판정 기록 2·16)"
if [ -f "$APP/PrivacyInfo.xcprivacy" ]; then
  ok "앱 최상위에 PrivacyInfo.xcprivacy"
  [ "$(pb "$APP/PrivacyInfo.xcprivacy" NSPrivacyTracking)" = "false" ] && ok "NSPrivacyTracking = false" || bad "NSPrivacyTracking 이 false 가 아니다"
  n="$(plutil -convert xml1 -o - "$APP/PrivacyInfo.xcprivacy" | grep -c '<string>NSPrivacyCollectedDataType[A-Z][A-Za-z]*</string>' | tr -d ' ')"
  # Purposes 문자열(…PurposeAppFunctionality)도 같은 접두어라 6 + 6 = 12
  [ "$n" = "12" ] && ok "수집 항목 6개(목적 포함 12줄)" || bad "수집 항목 줄 수 $n (기대 12)"
else
  bad "앱 최상위에 PrivacyInfo.xcprivacy 가 없다"
fi
find "$APP" -path '*NMapsMap.framework/PrivacyInfo.xcprivacy' | grep -q . && ok "NMapsMap.framework 매니페스트" || bad "NMapsMap.framework 매니페스트가 없다"
note "번들 안의 매니페스트 $(find "$APP" -name PrivacyInfo.xcprivacy | wc -l | tr -d ' ')개:"
find "$APP" -name PrivacyInfo.xcprivacy | sed "s|$APP/|          |"

echo "-- Info.plist (판정 기록 3·4·5·10·15)"
expect() { local got; got="$(pb "$INFO" "$1")"; [ "$got" = "$2" ] && ok "$1 = $2" || bad "$1 = '$got' (기대 '$2')"; }
expect CFBundleIdentifier com.kidcare.family
expect CFBundleShortVersionString 1.0
expect CFBundleVersion 1
expect ITSAppUsesNonExemptEncryption false
expect LSRequiresIPhoneOS true
expect MinimumOSVersion 17.0
[ "$(plutil -extract UIDeviceFamily json -o - "$INFO")" = "[1]" ] && ok "UIDeviceFamily = [1]" || bad "UIDeviceFamily 가 아이폰 전용이 아니다"
[ "$(plutil -extract UISupportedInterfaceOrientations json -o - "$INFO")" = '["UIInterfaceOrientationPortrait"]' ] && ok "세로 전용" || bad "지원 방향이 세로 하나가 아니다"
n="$(plutil -convert xml1 -o - "$INFO" | grep -c 'UsageDescription</key>' | tr -d ' ')"
[ "$n" = "0" ] && ok "권한 문구 0개" || bad "권한 문구 ${n}개 — 설계서 §1"
pb "$INFO" UIBackgroundModes >/dev/null && bad "UIBackgroundModes 가 있다" || ok "배경 모드 없음"
len="$(pb "$INFO" NMFNcpKeyId | tr -d '\n' | wc -c | tr -d ' ')"
[ "$len" -gt 0 ] && ok "NMFNcpKeyId 있음(${len}자, 값은 적지 않는다)" || bad "NMFNcpKeyId 가 비었다 — Secrets.xcconfig"
[ -f "$APP/GoogleService-Info.plist" ] && ok "GoogleService-Info.plist 실림(내용은 열지 않는다)" || bad "GoogleService-Info.plist 가 없다"
case "$(pb "$INFO" KidCarePrivacyPolicyURL)" in
  https://*) ok "개인정보 처리방침 URL 있음" ;;
  *)         note "개인정보 처리방침 URL 이 비었다 — 내부 TestFlight 는 되지만 외부 테스트·App Store 제출 전 필수(판정 기록 9)" ;;
esac

echo "-- 14개 언어 앱 이름 (판정 기록 13)"
for tag in ko en ja zh-Hans zh-Hant es pt de fr it ru id vi th; do
  f="$APP/$tag.lproj/InfoPlist.strings"
  if [ -f "$f" ]; then ok "$tag: $(plutil -extract CFBundleDisplayName raw -o - "$f")"; else bad "$tag.lproj/InfoPlist.strings 가 없다"; fi
done

echo "-- 출시 빌드에 에뮬레이터 구성이 없다 (판정 기록 6)"
MARKERS=("emulator-does-not-check-this" "1:000000000000:ios:0000000000000000")
strings -a "$APP/KidCare" > "$WORK/release.txt"
for s in "${MARKERS[@]}"; do
  n="$(grep -cF -- "$s" "$WORK/release.txt" | tr -d ' ')"
  [ "$n" = "0" ] && ok "Release: '$s' 0건" || bad "Release: '$s' ${n}건"
done
if [ -n "$CONTROL" ]; then
  : > "$WORK/debug.txt"
  find "$CONTROL" -maxdepth 1 -type f \( -name KidCare -o -name '*.debug.dylib' \) -exec strings -a {} \; >> "$WORK/debug.txt"
  for s in "${MARKERS[@]}"; do
    n="$(grep -cF -- "$s" "$WORK/debug.txt" | tr -d ' ')"
    [ "$n" -gt 0 ] && ok "대조군 Debug: '$s' ${n}건(검사 방법이 유효하다)" || bad "대조군 Debug 에서도 '$s' 를 못 찾는다 — 이 검사는 증명이 되지 못한다"
  done
else
  note "대조군 없음 — 0건이 '없다'는 증명이 되려면 두 번째 인자로 Debug KidCare.app 을 준다"
fi
note "-readOnlyCheck 는 14바이트라 strings 로 볼 수 없다. 실기기 동작으로 확인한다(Task 4 Step 7)"

echo "-- 서명 (판정 기록 7)"
auth="$(codesign -dvv "$APP" 2>&1 | grep '^Authority=' | head -1)"
codesign -d --xml --entitlements "$WORK/ent.plist" "$APP" >/dev/null 2>&1
if [ "$KIND" = ipa ]; then
  case "$auth" in *"Apple Distribution"*) ok "배포 인증서로 서명" ;; *) bad "배포 인증서가 아니다: $auth" ;; esac
  security cms -D -i "$APP/embedded.mobileprovision" > "$WORK/profile.plist" 2>/dev/null
  pb "$WORK/profile.plist" ProvisionedDevices >/dev/null && bad "프로파일에 기기 목록이 있다 — App Store 프로파일이 아니다" || ok "App Store 프로파일(기기 목록 없음)"
  [ "$(pb "$WORK/ent.plist" get-task-allow)" = "true" ] && bad "get-task-allow = true" || ok "get-task-allow 꺼짐"
else
  note "아카이브는 개발 인증서로 서명돼 있다(내보내기에서 다시 서명된다)"
fi
pb "$WORK/ent.plist" aps-environment >/dev/null && bad "aps-environment 가 있다 — 푸시는 쓰지 않는다" || ok "푸시 권한 없음"

echo "-- 아이콘 (판정 기록 1)"
xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep -q 'AppIcon' && ok "Assets.car 에 AppIcon" || bad "Assets.car 에 AppIcon 이 없다"

echo "-- 참고: 지도 SDK 의 위치 권한 선택자 (판정 기록 5, ITMS-90683 대비)"
NM="$APP/Frameworks/NMapsMap.framework/NMapsMap"
if [ -f "$NM" ]; then
  note "NMapsMap 안의 requestWhenInUseAuthorization $(strings -a "$NM" | grep -c requestWhenInUseAuthorization | tr -d ' ')건 — 0 이 아니면 업로드 뒤 ITMS-90683 메일이 올 수 있다"
fi
[ "$KIND" = ipa ] && note "IPA 크기 $(du -h "$INPUT" | cut -f1)"
[ "$KIND" = archive ] && note "dSYM $(ls "$INPUT/dSYMs" 2>/dev/null | wc -l | tr -d ' ')개"

if [ "$FAILS" = 0 ]; then echo "== 전부 통과"; exit 0; else echo "== 실패 ${FAILS}건"; exit 1; fi
```

- [ ] **Step 3: 대조군 Debug 빌드** — 서명 없이, 네트워크 없이.

```bash
cd /Users/com/work/KidCare/ios
mkdir -p /tmp/kidcare-p7
xcodebuild -project KidCare.xcodeproj -scheme KidCare -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/kidcare-p7/dd-debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -2        # ** BUILD SUCCEEDED **
ls /tmp/kidcare-p7/dd-debug/Build/Products/Debug-iphoneos/KidCare.app/ | grep -E '^KidCare$|debug.dylib'
```

- [ ] **Step 4: Release 아카이브**

```bash
cd /Users/com/work/KidCare/ios
xcodebuild archive -project KidCare.xcodeproj -scheme KidCare -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/kidcare-p7/KidCare.xcarchive \
  -allowProvisioningUpdates 2>&1 | tail -3                                                          # ** ARCHIVE SUCCEEDED **
/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' -c 'Print :ApplicationProperties:CFBundleVersion' /tmp/kidcare-p7/KidCare.xcarchive/Info.plist   # 1.0 / 1
```

- [ ] **Step 5: 로컬 내보내기(올리지 않는다)**

```bash
cd /Users/com/work/KidCare/ios
plutil -extract destination raw -o - Config/ExportOptions-AppStore.plist     # export — upload 이면 멈춘다
xcodebuild -exportArchive -archivePath /tmp/kidcare-p7/KidCare.xcarchive \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist -exportPath /tmp/kidcare-p7/export \
  -allowProvisioningUpdates 2>&1 | tail -3                                                          # ** EXPORT SUCCEEDED **
ls -la /tmp/kidcare-p7/export/                                                                      # KidCare.ipa, ExportOptions.plist, DistributionSummary.plist, Packaging.log
```

실패하면 **멈추고 보고한다.** 오류 원문 마지막 20줄을 붙인다. 특히 셋이다.
- "No signing certificate 'iOS Distribution' found" → 사람이 할 일 A
- "No profiles for 'com.kidcare.family' were found" / App Store Connect 앱이 없다는 뜻의 오류 → 레코드를 만들지 않는다. 사람이 할 일 B 가 먼저 필요한지 주인에게 묻는다
- 계정 로그인 요구 → Xcode → Settings → Accounts 는 사람이 한다

- [ ] **Step 6: 산출물을 검사한다**

```bash
cd /Users/com/work/KidCare
CONTROL=/tmp/kidcare-p7/dd-debug/Build/Products/Debug-iphoneos/KidCare.app
tools/ios-release-check.sh /tmp/kidcare-p7/KidCare.xcarchive "$CONTROL"; echo "종료 $?"     # == 전부 통과, 종료 0
tools/ios-release-check.sh /tmp/kidcare-p7/export/KidCare.ipa "$CONTROL"; echo "종료 $?"    # == 전부 통과, 종료 0
```

두 출력 전체를 개발일지 근거로 남긴다(값이 비밀인 줄은 스크립트가 이미 가렸다). "참고" 줄(처리방침 URL, NMapsMap 선택자 개수, 크기)은 README 사람이 할 일에 옮긴다.
- **"실패"가 하나라도 있으면 멈추고 보고한다.**
- 대조군에서 표지 문자열을 못 찾으면 에뮬레이터 코드가 없다는 증명을 할 수 없다. 이때 Release 쪽 "0건"을 통과로 적지 않는다.

- [ ] **Step 7: 실기기 Release 읽기 확인**

**진짜 가족이다. Release 빌드에는 `-readOnlyCheck` 가 없다**(판정 기록 6·14).
- **열지 않는 것:** 알림 탭(열면 읽음을 쓴다), 관리 탭(열면 `query_ringer` 를 쓴다)
- **누르지 않는 것:** 지도 탭의 '지금 위치 확인'·실시간 보기, 예약·장소의 저장·켬끔·삭제·'다시 알리기', 선택기 메뉴의 초대 두 줄·"이 아이폰을 가족에서 빼기"
- **안전한 것:** 지도 탭 보기(지도·타임라인·날짜 넘기기), 예약·장소 탭 목록 보기, 선택기 메뉴 **열고 닫기**

```bash
xcrun devicectl list devices      # 6C5120C8-779D-5250-AB4C-B152B9A648A2 가 available(paired) 이어야 한다. unavailable 이면 멈추고 보고한다 — 케이블은 사람이 꽂는다
mkdir -p /tmp/kidcare-p7
xcrun devicectl list devices --json-output /tmp/kidcare-p7/devices.json >/dev/null
UDID=$(python3 -c "import json;d=json.load(open('/tmp/kidcare-p7/devices.json'));print(next(x['hardwareProperties']['udid'] for x in d['result']['devices'] if x['identifier']=='6C5120C8-779D-5250-AB4C-B152B9A648A2'))")
echo "$UDID"
cd /Users/com/work/KidCare/ios
# App Store .ipa 는 기기에 못 깐다(배포 프로파일). 같은 Release 구성을 개발 서명으로 빌드해 덮어 설치한다 — 가족 합류가 유지된다.
xcodebuild -project KidCare.xcodeproj -scheme KidCare -configuration Release -destination "platform=iOS,id=$UDID" \
  -derivedDataPath /tmp/kidcare-p7/dd-release-device -allowProvisioningUpdates build 2>&1 | tail -2    # ** BUILD SUCCEEDED **
xcrun devicectl device install app --device 6C5120C8-779D-5250-AB4C-B152B9A648A2 /tmp/kidcare-p7/dd-release-device/Build/Products/Release-iphoneos/KidCare.app
xcrun devicectl device process launch --device 6C5120C8-779D-5250-AB4C-B152B9A648A2 com.kidcare.family -readOnlyCheck
```

보기만 한다. 스크린샷은 사람이 기기에서 찍는다.
1. **홈 화면 이름**이 "우리아이 지킴이"다(기기 언어가 한국어일 때).
2. 앱이 죽지 않고 지도 탭이 뜬다. 지도 타일과 아이 마커·경로가 그려진다(NCP 키, 운영 Firebase 가 Release 에서도 붙는다).
3. 예약 탭으로 가 선택기 줄을 **누르기만** 한다. 메뉴의 '＋ 아이 추가'·'＋ 보호자 초대' 두 줄이 **흐리지 않다.** `-readOnlyCheck` 인자를 줬는데도 흐리지 않다는 것이 **Release 에서 그 스위치가 꺼져 있다는 증거**다. 흐리면 Release 가 DEBUG 코드를 싣고 있다는 뜻이니 멈추고 보고한다. 맨 아래 "이 아이폰을 가족에서 빼기"가 빨간 글씨로 있고, "개인정보 처리방침" 줄은 없다. **아무 줄도 누르지 않고** 메뉴 바깥을 눌러 닫는다.
4. 장소 탭 목록이 안드로이드 보호자 폰과 같다.
5. 앱을 닫는다. 다음 실행부터는 인자 없이 쓴다. Release 빌드는 그대로 둬도 된다(같은 번들·같은 팀).

- [ ] **Step 8: README 를 쓴다**

**(a) 개발일지.** `README.md` 에 절 하나를 더한다. 자리는 6단계 절(`### 아이폰 6단계 …`) 바로 다음이다. 앞 절들과 같은 말투(부모와 다음 개발자가 읽는 한국어 설명문)로 아래 내용을 **다 담는다.**

```markdown
### 아이폰 7단계 — 출시 준비: 올리기 직전까지 (2026-09-13)

아이폰 앱을 가족에게 TestFlight 로 나눠줄 수 있고, 나중에 App Store 심사에 그대로 낼 수 있는 상태로 만들었습니다. **업로드는 하지 않았습니다.** 올리는 일은 아래 "아이폰 TestFlight로 올리는 법"에 사람이 할 일로 적었습니다.

#### 무엇을 모으는지 파일로 적었습니다
```

이 제목 아래에 담을 내용은 다음과 같다.
- 매니페스트 여섯 항목과 넓게 신고한 이유(판정 기록 2), 이유 필요 API 는 UserDefaults 하나.
- Firebase 12.19.1·NMapsMap 3.23.3 이 각자 매니페스트를 싣고 있음을 로컬 패키지에서 확인한 사실.
- 이 목록이 코드와 어긋나면 `ReleaseConfigTests` 가 빨개진다는 것.

이어서 소제목 다섯을 같은 방식으로 쓴다.
- `#### 권한은 여전히 0개입니다` — 권한 문구·배경 모드 없음, 수출 규정 false, 버전 1.0 (1)과 안드로이드 0.8 을 묶지 않은 이유. NMapsMap 선택자 개수(Step 6 참고 줄)와 ITMS-90683 가능성.
- `#### 이 아이폰을 가족에서 뺄 수 있습니다` — 5.1.1(v) 때문에 **안드로이드에 없는 기능을 아이폰에만** 넣었다는 것. 지우는 것·남는 것(판정 기록 8 목록 그대로), 서버 확인 전에는 아무것도 안 지우는 이유, 마지막 보호자 경고, 단계 마무리 Step 3 결과.
- `#### 출시 빌드에 개발용 스위치가 없다는 증명` — 짧은 문자열은 `strings` 로 안 보인다는 함정, 긴 표지 + Debug 대조군, `-readOnlyCheck` 는 실기기에서 초대 줄이 흐리지 않은 것으로 확인. Step 6 두 검사의 "통과" 개수와 IPA 크기.
- `#### 안드로이드와 다른 점, 남은 것` — 안드로이드에는 계정 삭제가 없다(결함 후보로만 적고 고치지 않음). App Store 제출 전 선결 과제: 처리방침 게시, 데모 가족·시연 영상, **안드로이드 아이 앱을 공개적으로 구할 수 있는가**(판정 기록 12).
- `#### 그래서 지금` — 가족 TestFlight 는 사람이 할 일 A~F 만 하면 된다. App Store 는 G~H 가 더 필요하다. 테스트 개수 N(단계 마무리 Step 1).

**(b) 사람이 할 일.** `## 문서` 표의 절 끝 `---` 바로 다음에 새 절을 넣고, 아래 내용을 **그대로** 옮긴다.

````markdown
## 아이폰 TestFlight로 올리는 법 (사람이 할 일)

코드로 대신 못 하는 것들입니다. **A~F 는 가족에게 TestFlight 로 나눠줄 때, G~H 는 App Store 에 낼 때** 필요합니다.
명령이 적힌 항목은 **주인이 직접 확인한 뒤에만** 실행합니다. 개발 도구(에이전트 포함)는 올리기·레코드 만들기를 하지 않습니다.

로컬 산출물은 `ios/` 에서 이렇게 다시 만들고 검사합니다(아무것도 올리지 않습니다).

```bash
cd ios && xcodegen generate
xcodebuild archive -project KidCare.xcodeproj -scheme KidCare -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/kidcare-p7/KidCare.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath /tmp/kidcare-p7/KidCare.xcarchive -exportOptionsPlist Config/ExportOptions-AppStore.plist -exportPath /tmp/kidcare-p7/export -allowProvisioningUpdates
cd .. && tools/ios-release-check.sh /tmp/kidcare-p7/export/KidCare.ipa
```

### A. 배포 인증서 (처음 한 번, 없을 때만)
Xcode → Settings… → Accounts → Apple ID 선택 → 팀 "YONGMIN LEE (Individual)" 선택 → **Manage Certificates…** → 왼쪽 아래 **+** → **Apple Distribution**.
확인: 터미널에서 `security find-identity -v -p codesigning | grep "Apple Distribution"` 가 한 줄 나옵니다.

### B. App Store Connect 에 앱 만들기 (처음 한 번)
https://appstoreconnect.apple.com → **앱** → 왼쪽 위 **+** → **신규 앱**
- 플랫폼: iOS
- 이름: `우리아이 지킴이`(이미 있으면 `docs/app-store/metadata.md` 의 대안)
- 기본 언어: 한국어
- 번들 ID: `com.kidcare.family`(목록에 없으면 developer.apple.com → Certificates, Identifiers & Profiles → Identifiers 에 있는지 봅니다. Xcode 자동 서명이 이미 만들었습니다)
- SKU: `kidcare-ios-guardian`
- 사용자 액세스: 전체 액세스

→ **생성**.

### C. 올리기 — 둘 중 하나 (주인이 확인한 뒤에만)
**Xcode Organizer (권장)**
Xcode → Window → **Organizer** → Archives → `KidCare 1.0 (1)` 선택 → **Distribute App** → **TestFlight Internal Only**(가족만) 또는 **App Store Connect**(외부 테스트·심사까지) → **Distribute** → 자동 서명 그대로 → 업로드가 끝나면 10~30분 뒤 App Store Connect → TestFlight 에 빌드가 "처리 중"으로 보입니다.

**터미널 — run only after owner confirms**
App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API → 키 생성(역할: 앱 관리자). 받은 `AuthKey_<KEY_ID>.p8` 은 `~/.appstoreconnect/private_keys/` 에 두고 **절대 커밋하지 않습니다.**
```bash
# run only after owner confirms — 이 명령이 실제로 올린다
xcrun altool --upload-app -f /tmp/kidcare-p7/export/KidCare.ipa -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```
옵션 이름은 Xcode 버전마다 바뀝니다. 실행 전에 `xcrun altool --help` 로 `--upload-app`(또는 `--upload-package`)이 있는지 봅니다. `notarytool` 은 macOS 앱 공증 도구라 아이폰 앱에는 쓰지 않습니다.

### D. 수출 규정
Info.plist 에 `ITSAppUsesNonExemptEncryption = NO` 가 들어 있어 업로드 뒤 질문이 뜨지 않습니다. 뜨면 "표준 암호화(HTTPS/TLS)만 사용"에 해당하는 답을 고릅니다. 앱에 자체 암호화를 넣게 되면 이 값을 다시 판단합니다.

### E. 가족에게 나눠주기
- **내부 테스트(심사 없음, 권장):** App Store Connect → 사용자 및 액세스 → **+** → 가족의 Apple ID 이메일, 역할 "고객 지원"(가장 좁은 역할) → 초대. 가족이 메일에서 수락합니다. 그다음 앱 → **TestFlight** → 내부 테스트 → **+** 그룹 "가족" → 테스터 추가 → 빌드 추가.
- **외부 테스트(심사 필요):** TestFlight → 외부 테스트 → **+** 그룹 → 빌드 추가 → 테스트 정보에 `docs/app-store/review-notes.md` 의 메모·What to Test, 피드백 이메일, **개인정보 처리방침 URL**(H-1) 입력 → 심사 제출. 승인되면 공개 링크를 만들 수 있습니다.
- 가족 아이폰: App Store 에서 **TestFlight** 앱 설치 → 초대 수락 → 설치 → 앱에서 보호자 → 가족에 합류(안드로이드 보호자 폰에서 '＋ 보호자 초대' 번호).

### F. 90일마다, 그리고 고칠 때마다
- TestFlight 빌드는 **90일 뒤 만료**됩니다(설계서 §11). 만료 전에 새 빌드를 올립니다.
- 올릴 때마다 `ios/project.yml` 의 `CURRENT_PROJECT_VERSION` 을 1 올리고 커밋한 뒤 위 명령으로 다시 만듭니다. 같은 번호는 거부됩니다. 기능이 바뀌면 `MARKETING_VERSION` 도 올립니다(1.0 → 1.1).

### G. 업로드 뒤 메일이 오면
- **ITMS-90683 Missing purpose string**(지도 SDK 가 위치 API 를 싣고 있어서 올 수 있습니다 — 검사 스크립트의 NMapsMap 참고 줄): 앱은 위치를 묻지 않습니다. 메일에 적힌 키를 `project.yml` Info.plist 속성에 넣되, 문구는 사실만 적습니다 — 예: `NSLocationWhenInUseUsageDescription: 이 앱은 기기 위치를 요청하지 않습니다. 지도 기능에 포함된 항목입니다.` 넣은 뒤 `ReleaseConfigTests.출시_Info` 의 "권한 문구 0개" 검사를 그 키 하나만 허용하도록 바꾸고, 그 결정을 개발일지에 적습니다.
- **ITMS-91053 Missing API declaration**: 메일에 적힌 API 분류가 앱 코드에서 쓰인 것인지 `ReleaseConfigTests.이유_필요_API` 로 확인합니다. SDK 쪽이면 그 SDK 버전을 올릴지 판단합니다. 앱 매니페스트에 대신 적지 않습니다.

### H. App Store 에 내기 전에 (TestFlight 에는 필요 없음)
1. `docs/app-store/privacy-policy.md` 의 【주인이 채움】을 채우고 법률 검토 → 웹에 게시 → 그 https 주소를 App Store Connect(앱 정보 → 개인정보 처리방침 URL)와 `ios/project.yml` 의 `KidCarePrivacyPolicyURL` 에 넣고 새 빌드. 앱 메뉴에 "개인정보 처리방침" 줄이 뜹니다.
2. 앱 개인정보 보호 → `docs/app-store/privacy-label.md` 표대로 입력.
3. 배포 → 버전 1.0 → `docs/app-store/metadata.md` 의 이름·부제·설명·키워드·지원 URL·스크린샷, 연령 등급 설문.
4. 앱 심사 정보 → `docs/app-store/review-notes.md` 메모. 시연 영상 URL, 데모 가족(안드로이드 시험 폰)과 연락처를 준비해 둡니다.
5. **안드로이드 아이 앱을 누구나 구할 수 있는가.** 지금은 가족끼리 APK 로만 설치합니다. 이대로면 일반 사용자에게 이 아이폰 앱은 쓸 수 없고, 심사도 그 이유로 막힐 수 있습니다. 제출 전에 정합니다.
6. 키즈 카테고리에 넣지 않습니다.
````

- [ ] **Step 9: 커밋** (공통 절차 B)

```bash
cd /Users/com/work/KidCare
git add ios/Config/ExportOptions-AppStore.plist tools/ios-release-check.sh README.md
git diff --cached | grep -nE 'Authority=|UDID|hardwareProperties' | head   # 개발일지에 서명 원문·기기 UDID 를 붙이지 않았는지 — 비어 있어야 한다
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "개발일지: 아이폰 7단계 — 출시 준비, 로컬 아카이브 검증과 TestFlight 로 올리는 법"
```

`/tmp/kidcare-p7/` 는 지우지 않는다. 주인이 사람이 할 일 C 에서 그 아카이브를 쓸 수 있다.

---

## 7단계 완료 기준

- [ ] 앱 번들 최상위에 `PrivacyInfo.xcprivacy` 가 있고, 추적 false·수집 여섯 개·UserDefaults CA92.1 이 코드 스캔과 맞는다(`ReleaseConfigTests`).
- [ ] Info.plist 에 `ITSAppUsesNonExemptEncryption = false`, `1.0 (1)`, `LSRequiresIPhoneOS`, 아이폰·세로 전용이 있고, 권한 문구·배경 모드·푸시 권한이 없다.
- [ ] 14개 `lproj` 의 앱 이름이 `i18n/*.json` `app_name` 과 같고, `python3 tools/ios-strings.py --check` 가 0 이다.
- [ ] Release 바이너리에 에뮬레이터 표지 문자열이 없고, 같은 검사가 Debug 대조군에서는 찾는다. Release 실기기에서 `-readOnlyCheck` 가 초대 줄을 흐리게 하지 않는다.
- [ ] "이 아이폰을 가족에서 빼기"가 서버 확인 → 계정 → 이 폰 순서로 지우고, 확인이 없거나 거부되면 아무것도 지우지 않는다(뷰모델 테스트 7, 에뮬레이터 테스트 4, 시뮬레이터 확인). 다시 합류할 때 본 화면으로 튕기지 않는다.
- [ ] `docs/app-store/` 네 파일이 있고 원고 대조 스크립트가 통과한다. 지어낸 URL 이 없다.
- [ ] `.xcarchive` 와 `.ipa` 모두 `tools/ios-release-check.sh` "전부 통과".
- [ ] README 에 7단계 개발일지와 "아이폰 TestFlight로 올리는 법"(A~H)이 있다.
- [ ] 아무것도 올리지 않았고 App Store Connect 에 아무것도 만들지 않았다. 비밀·팀 ID·산출물이 커밋에 없다.
- [ ] `git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew` 가 비어 있다.

---

## 자기 검토 결과 (writing-plans self-review)

**설계서 대응.**
- §9 7단계 "아이콘" → 판정 기록 1(이미 있음, 알파 없음 확인), Task 4 스크립트 `Assets.car` 검사.
- §9 "개인정보 매니페스트" → Task 1(`PrivacyInfo.xcprivacy`, `ReleaseConfigTests` 5개), 판정 기록 2(SDK 매니페스트 로컬 확인과 없을 때의 처리).
- §9 "TestFlight 배포 준비 — 가족이 실제로 설치 가능" → Task 4(로컬 아카이브·내보내기·검사, 실기기 Release, README A~F). 업로드는 브리프가 사람 몫으로 뺐다.
- §1 "심사를 막는 선택(권한 과다 요청, 개인정보 매니페스트 누락, 아이 동의 흐름 부재)을 하지 않는다" → 권한 0개 테스트(판정 5), 매니페스트(Task 1), 아이 동의(판정 12, 심사 메모).
- §1 권한 0개·푸시 없음 → `출시_Info` 의 `UsageDescription`·`UIBackgroundModes` 검사, 스크립트의 `aps-environment` 검사.
- §10-4 Apple Developer Program → 이미 가입(브리프). 배포 인증서만 사람이 할 일 A.
- §11 "TestFlight 90일 만료" → README F.
- §13 "처리방침 웹페이지, 심사용 테스트 계정, 시연 영상, 아이 동의 흐름" → 처리방침 원고(Task 3)와 앱 안 링크 자리(Task 2), 데모 대체(판정 11, 심사 메모), 시연 영상(주인이 채움), 아이 동의(판정 12).

**브리프 요구 대응.**
- 매니페스트 → 판정 2, Task 1. 이유 필요 API 는 grep 으로 찾았다(UserDefaults 네 파일). 추적 false. Firebase·NMapsMap 매니페스트는 DerivedData 에서 확인했고, 다시 확인하는 명령과 없을 때의 처리를 Task 1 Step 1·판정 2 에 적었다.
- Info.plist·설정 → 수출 규정(판정 3), 권한 문구 0개(판정 5, 요청 권한 없음을 grep 으로 확인), 버전(판정 4 — 설계서가 안드로이드와 묶으라 하지 않음), 아이폰·세로·iOS 17.0(판정 15, 스크립트 `MinimumOSVersion`), 14개 언어 이름(판정 13 — 설계서는 요구하지 않았지만 안드로이드가 `app_name` 을 현지화하고 원본에 값이 있어 지어낼 것이 없다), DEBUG 전용 코드(판정 6, Task 1 Step 6, Task 4 Step 6·7), 서명(판정 7, 사람이 할 일 A).
- 심사 대비 → 판정 8(계정 삭제, 코드 Task 2, 에뮬레이터 전용), 10(배경 위치), 9(처리방침), 11(데모), 12(키즈 카테고리).
- 메타데이터 원고 ko/en → Task 3. URL 은 모두 【주인이 채움】이고, 대조 스크립트가 실제 주소를 막는다.
- 로컬 검증 → Task 4 Step 4~6(`app-store-connect` + `destination export`), 버전·매니페스트·에뮬레이터 문자열·`-readOnlyCheck` 무력(실기기). 실기기 id `6C5120C8-779D-5250-AB4C-B152B9A648A2`, 읽기만 한다.
- README 개발일지와 "TestFlight로 올리는 법" → Task 4 Step 8, 명령마다 "주인이 확인한 뒤에만"을 표시했다.
- Global Constraints → 6단계 목록 verbatim + 7단계 추가(올리지 않음, 레코드 없음, 비밀 없음, `app/` 그대로, 커밋 규칙).
- 과제 수 4개 + 단계 마무리. 마지막 Task 가 아카이브·실기기·개발일지다.

**자리표시 검사.** "TBD/TODO/나중에/적절히"는 없다. `【주인이 채움】`·`【OWNER】` 은 브리프가 요구한 **주인 제공 값 표시**이고, 대조 스크립트가 남은 표시를 셀 수 있다. `<KEY_ID>`·`<ISSUER_ID>` 는 사람이 할 일 C 의 "주인이 확인한 뒤에만" 명령 안에만 있다. 개발일지 틀의 N 과 Step 6 의 통과 개수·크기는 실행해야 아는 값이다.

**타입·이름 일관성(고친 것 포함).**
- `LeaveFamilyModelTests` 는 `LeaveFamilyModel(familyId:currentUid:removeMember:deleteAuth:clearLocal:sleep:)`, `묻는다`·`취소한다`·`실패를_닫는다`·`뺀다`, `묻는중`·`빼는중`·`실패_문구`·`계정_결과`, `확인_문구(보호자_수:)`, `timeoutMillis`, `RemoveMember` 를 쓴다. 모두 Step 5 구현에 있다.
- `LeaveFamilyTests` 는 `LeaveFamilyRepository.removeMember(familyId:uid:)`·`deleteAuthUser()`·`AuthOutcome.deleted` 를 쓴다(Step 4).
- `PrivacyPolicyLinkTests` 는 `PrivacyPolicyLink.url(info:)` 를 쓴다.
- `ReleaseConfigTests.신고한_수집_항목` 여섯 개 = 매니페스트 여섯 = `privacy-label.md` 표의 매니페스트 키 여섯. Task 3 Step 5 가 기계로 대조한다.
- 초안에서 고친 것은 넷이다.
  - 심사 메모의 버튼 글자를 "Guardian"·"…with an invite code"로 적었다가 `en.json` 실제 값("Parent (mum or dad)", "Join an existing family with a code")으로 고쳤다.
  - 스크립트에 `127.0.0.1`·`readOnlyCheck` 문자열 검사를 넣었다가 뺐다. Swift 짧은 문자열 리터럴은 `strings` 로 보이지 않아 증명이 되지 못한다. 긴 표지 + 대조군 + 실기기 동작으로 바꿨다(판정 6).
  - 실기기 확인을 App Store `.ipa` 로 하려다 뺐다. 배포 프로파일이라 설치되지 않는다. 개발 서명 Release 빌드로 바꿨다(판정 14).
  - `LeaveFamilyRepository.deleteAuthUser` 를 `throws` 로 두려다, 멤버 삭제 뒤의 실패가 "빠졌는데 실패"라는 모순 안내가 되어 로그아웃으로 끝나는 비던지기로 바꿨다.
- 테스트 수 기대값: Task 1 은 5(`ReleaseConfigTests` 의 `@Test` 개수), Task 2 는 12(뷰모델 7 + 링크 1 + 에뮬레이터 4). 합계 M+17.
- **실행 전에 확인이 필요한 가정.** 모두 멈추고 보고하게 적었다.
  - XcodeGen 이 `InfoPlist.xcstrings` 를 리소스로 싣는가(Task 1 Step 8)
  - 에뮬레이터가 방금 만든 익명 계정 삭제를 받는가(Task 2 Step 7)
  - App Store Connect 레코드 없이 `app-store-connect` 내보내기가 되는가(Task 4 Step 5)
  - Debug 대조군이 표지 문자열을 싣는가(Task 4 Step 6)
  - Swift 6 가 `User.delete()` 를 격리 오류로 막는가(Task 2 Step 4)

---

## Pre-flight conflict table

| 짝 | 함께 만지는 것 | 충돌 여부와 처리 |
|---|---|---|
| **6단계 Task 2 ↔ 7단계 Task 1·2·4** | `ios/KidCare/Guardian/ReadOnlyCheck.swift` 의 `ReadOnlyCheck.isOn`, `#if DEBUG` 안의 `ProcessInfo.processInfo.arguments.contains("-readOnlyCheck")` | 6단계 계획서 `:1282-1296` 의 이름과 모양이다. 2026-09-13 HEAD 에는 아직 없다. 선행 조건 grep 으로 확인한다. `#if DEBUG` 가 아니면 판정 기록 6 이 무너지므로 **7단계를 시작하지 않고** 보고한다. Task 2 는 이 값을 읽기만 한다. Task 4 Step 7 은 Release 에서 이 값이 꺼져 있음을 동작으로 증명한다 |
| **6단계 Task 1 ↔ 7단계 Task 1** | `tools/ios-strings.py` 의 `ROOT`·`CATALOG`·`GAPS`·`LANGS`·`load()`·`build(src, version)`·`report(gaps)`·`main(args)`·`--check`·`--write-gaps` | 2026-09-13 작업 트리의 **커밋 전** 파일(162줄)에서 이름을 확인했다. 커밋본이 달라졌으면 Step 7 의 다섯 수정 자리를 커밋본의 같은 역할 자리에 넣는다. `build()` 의 출력 형태(`sort_keys`, `indent=2`, 끝 줄바꿈)를 `build_infoplist` 가 따라야 `--check` 가 흔들리지 않는다 |
| **6단계 Task 1 ↔ 7단계 Task 1** | `InfoPlist` 현지화 — `project.yml` 의 `CFBundleLocalizations: [ko, en, ja, zh-Hans, zh-Hant, es, pt, de, fr, it, ru, id, vi, th]`, `LocalizationBundleTests`(14개 lproj), `LocalizableCatalogTests.언어_태그` | `ReleaseConfigTests.앱_이름` 이 `언어_태그` 를 그대로 돌고, 번들 lproj 가 14개라는 6단계 결과에 기댄다. 태그 목록이 바뀌었으면 스크립트의 `for tag in …` 줄도 같은 목록으로 바꾼다. 6단계가 lproj 를 싣지 못해 멈췄다면 7단계 Task 1 도 시작하지 않는다 |
| 6단계 Task 1 ↔ 7단계 Task 2 | 공통 절차 A(`--write-gaps`), `tools/i18n-untranslated.json`, `i18n/ko.json`·`en.json` 정렬 모양 | 새 키 11개를 ko/en 에만 넣고 빈 칸 목록을 한 번 다시 쓴다. 12개 언어 × 11 이 목록에 더해지는 것이 의도한 변화다 |
| **6단계 Task 4 ↔ 7단계 Task 2** | `ios/KidCare/Guardian/ChildSelectorBar.swift` 의 `struct ChildMenu<Content: View>`(`let model`, `Menu { … }`, `Button(model.보호자_초대_문구) … .disabled(ReadOnlyCheck.isOn)`) | 6단계 계획서 `:2921-2946` 의 모양이다. Task 2 는 그 버튼 **바로 아래**에 `Divider`·두 줄을 더하고 `@Environment` 두 줄을 넣는다. 메뉴 구조가 달라졌으면 "초대 줄들 뒤, 메뉴 끝"이라는 자리만 지킨다 |
| **6단계 Task 4 ↔ 7단계 Task 2** | `ios/KidCare/Guardian/GuardianHomeView.swift` — `@State private var selector`, `init(familyId:)`, `.environment(selector)`, `.onAppear/.onDisappear`, `.fullScreenCover(isPresented:)` / `ChildSelectorModel.guardians` | 6단계 계획서 `:2952-3000`. Task 2 는 `@State` 한 줄, `init` 한 줄, `.environment(selector)` 아래 수식어 넷을 더한다. `fullScreenCover` 와 `confirmationDialog`·`alert` 는 같은 뷰에 함께 붙어도 된다. 한쪽이 떠 있는 동안 다른 쪽을 열지 않는다(초대 화면이 떠 있으면 메뉴를 누를 수 없다) |
| **6단계 Task 4 ↔ 7단계 Task 2** | `ios/KidCare/RouterView.swift` 의 `GuardianHomeView(familyId: familyId).id(familyId)`, `showMain`, `isRunningTests` | 6단계 계획서 `:3023-3030` 모양 위에 `Group` 과 `.onChange(of: store.familyId)` 만 더한다. 1단계 머리 주석의 "showMain 은 init 에서 한 번만 정한다"는 그대로다 — `onChange` 는 **false 로 되돌리는 방향만** 한다 |
| 6단계 Task 5 ↔ 7단계 Task 4 | `README.md` 개발일지 자리, 실기기 읽기 전용 규칙 | 7단계 절은 6단계 절 바로 다음에 둔다. 6단계 절이 없으면 시작하지 않는다(선행 조건). 6단계는 Debug + `-readOnlyCheck` 로 알림 탭을 열었지만, 7단계는 Release 라 알림·관리 탭을 **열지 않는다**(Global Constraints) |
| 6단계 작업 트리 상태 ↔ 7단계 시작 | 2026-09-13 `/Users/com/work/KidCare` 에 6단계 Task 1 이 커밋 전이다(`M ios/project.yml`, `M ios/KidCare/Info.plist`, `?? tools/ios-strings.py` 등). 별도 트리 `scratchpad/kidcare-p6`(가지 `ios-p6-t2`)에는 커밋이 없다 | 선행 조건 `git status --short` 가 비어 있고 6단계 Task 1~4 커밋이 `ios-guardian-app` 에 있어야 한다. 6단계 두 작업 트리가 합쳐진 뒤 시작한다 |
| 5단계 ↔ 7단계 Task 2 | `Guardian/FirstToFinish.swift` 의 `firstToFinish<T: Sendable>(timeoutMillis: Int64, sleep: @escaping @Sendable (Int64) async -> Void, operation: @escaping @Sendable () async throws -> T) async throws -> T?` | HEAD 에서 시그니처를 확인했다(2026-09-13) |
| 4단계 ↔ 7단계 Task 4 | 관리 탭은 열리는 순간 `query_ringer` 를 쓴다(6단계 Task 5 "누르지 않는 것") | Release 실기기 확인에서 관리 탭을 열지 않는다 |
| 3단계 ↔ 7단계 Task 4 | 지도 탭의 '지금 위치 확인'·실시간 보기는 명령을 쓴다 | 누르지 않는다. 지도 보기와 날짜 넘기기만 한다 |
| 1단계 ↔ 7단계 Task 1 | `FirebaseBootstrap.configureForEmulator` — 부르는 곳 `KidCareTests/EmulatorHarness.swift:18-20` | `#if DEBUG` 로 감싸도 테스트 스킴이 `test: config: Debug`(`project.yml`)라 컴파일된다. 테스트를 Release 로 돌리도록 스킴을 바꾸면 이 줄에서 깨진다 — 바꾸지 않는다. 단계 마무리 Step 3 의 임시 에뮬레이터 전환도 Debug 빌드라 된다 |
| 1단계 ↔ 7단계 Task 1 | `KidCare.xcodeproj/project.pbxproj:940` `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`(Debug 구성에만) | XcodeGen 기본값이라 `xcodegen generate` 뒤에도 같다. Task 1 Step 8 의 `-showBuildSettings -configuration Release` 로 매번 확인한다 |
| 1단계 ↔ 7단계 Task 1·4 | `ios/Config/Base.xcconfig`(`#include? "Secrets.xcconfig"`, `CODE_SIGN_STYLE = Automatic`), `Secrets.xcconfig`·`GoogleService-Info.plist`(gitignore) | 두 비밀 파일을 열거나 출력하지 않는다. 팀 ID 는 `-showBuildSettings` 결과에서도 가려 적는다(Task 4 Step 1 `sed`). `ExportOptions` 에 `teamID` 를 넣지 않는다 |
| 패키지 캐시 ↔ 7단계 Task 1 Step 1 | `~/Library/Developer/Xcode/DerivedData/KidCare-*/SourcePackages`(2026-09-13 확인한 폴더는 `KidCare-aelfotxibfhqzlclyqugdlhsnryl`, 같은 이름의 폴더가 하나 더 있다) | `ls -d … | head -1` 로 고른 폴더의 `workspace-state.json` 버전이 12.19.1·3.23.3 인지 먼저 본다. 다르면 다른 `KidCare-*` 폴더를 본다 |
| Task 1 ↔ Task 2 | Info.plist 키 `KidCarePrivacyPolicyURL` | 순서 의존. Task 2 의 `PrivacyPolicyLink` 기본 인자가 이 키를 읽는다 |
| Task 1·2 ↔ Task 3 | 매니페스트 여섯 키, 메뉴 문구 `ios_leave_family_menu`·`ios_privacy_policy`, `en.json` 의 `role_guardian`·`guardian_start_join_family`·`guardian_start_new_family` | Task 3 Step 5 대조 스크립트가 글자까지 본다. 앱 문구를 원고에 맞추지 않고 원고를 앱에 맞춘다 |
| Task 1~3 ↔ Task 4 | 버전 1.0 (1), 매니페스트, InfoPlist.strings 14개, `docs/app-store/*` | 스크립트와 README 가 이 값들을 인용한다. 버전을 올렸으면 스크립트의 `expect CFBundleShortVersionString`·`CFBundleVersion` 두 줄도 함께 올린다 |
