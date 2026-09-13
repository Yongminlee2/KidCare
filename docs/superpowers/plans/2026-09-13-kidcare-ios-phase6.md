# iOS 6단계 구현 계획 — 알림 탭, 아이 선택기와 초대, 14개 언어

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰 보호자 앱의 마지막 자리표시(알림 탭)를 안드로이드 `AlertFragment` 와 같은 화면으로 채운다. 안드로이드 `GuardianMainActivity` 의 아이 선택기(팝업의 '＋ 아이 추가'·'＋ 보호자 초대' 포함)와 지구본 버튼을 옮긴다. `i18n/*.json` 14벌에서 `Localizable.xcstrings` 를 통째로 생성하는 `tools/ios-strings.py` 를 만들고, 12개의 `withKnownIssue` 를 실제 검사로 바꾼다.

**Architecture:** 알림 탭의 판단(구독, "화면을 연 순간의 안 읽은 ID" 붙들기, `read` 한 필드 쓰기)은 `AlertViewModel`(@MainActor @Observable) 한 곳에 둔다. Firestore 쪽은 주입 클로저로 받는다. 뷰모델은 4·5단계와 같이 `GuardianRootView` 가 소유한다. 아이 선택기는 **아이를 바꿔도 살아남아야 하므로** `GuardianRootView` 바깥의 새 `GuardianHomeView` 가 소유한다. 이 뷰가 선택 탭(`@SceneStorage`)도 넘겨받아 들고, `GuardianRootView` 를 `.id(childUid)` 로 감싼다. 아이를 고르면 `RoleStore.childUid` 가 바뀌고, 탭 뷰모델 다섯이 새 아이로 다시 만들어진다(안드로이드 `recreateTabsForSelectedChild` 자리). 초대 발급은 `GuardianPairingActivity` 의 초대 갈래를 옮긴 `InviteSession` 이 소유한다. 다국어는 생성기 하나가 14개 언어를 모두 쓰고, 번역이 없는 칸은 영어로 채워 `needs_review` 로 표시한다. 빈 칸 목록은 `tools/i18n-untranslated.json` 에 기록하고 테스트가 그 목록과 정확히 맞는지 본다.

**Tech Stack:** Swift 6 / SwiftUI(`TabView`, `Menu`, `fullScreenCover`, `@SceneStorage`, `@Environment(Type.self)`) / Firebase Firestore 12.19.1 / Swift Testing / Python 3(생성기, 표준 라이브러리만). 새 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-12-kidcare-ios-design.md`. 이 단계가 기대는 곳은 다음과 같다.
- §4 ① "알림 탭의 `AlertService` 스위치가 없다 — 그 자리에 제약을 한 줄로"
- §4 대응표 `AlertFragment`("살구빛 하이라이트와 `read` 한 필드만 쓰는 계약 그대로")와 `GuardianMainActivity`("탭 컨테이너 · 아이 선택기 · 무응답 배너")
- §4 "알림 탭의 살구빛은 화면을 여는 순간의 안 읽은 ID를 따로 붙들어 칠한다"
- §5 "보호자는 합류한 뒤에도 자기가 코드를 발급할 수 있어야 한다", `EventRepository.markRead` 본보기
- §7 다국어
- §9 6단계 "알림 탭 · 아이 선택기 · 14개 언어 · 오프라인/예외 화면"

**선행 조건.** 5단계 Task 2·3, 5단계 단계 마무리, 5단계 Task 4(개발일지)가 모두 커밋돼 있어야 한다. 2026-09-13 이 계획서를 쓸 때 HEAD 는 `64a95d2`(5단계 Task 1)였고, Task 2·3 은 작업 중이었다. 그래서 이 계획서는 **5단계 계획서에 적힌 이름**을 쓴다. 시작 전에 이름이 실제로 그대로인지 확인한다.

```bash
cd /Users/com/work/KidCare
git status --short                                                   # 비어 있어야 한다
git log --oneline | grep -E "5단계 Task (2|3|4)"                     # 세 줄 이상
grep -n "struct RuleStateLine" ios/KidCare/Guardian/RuleListParts.swift                      # 한 줄
grep -n "static let apricotSoft\|static let berryInk\|static let lineSoft" ios/KidCare/Guardian/KidCarePalette.swift   # 세 줄
ls ios/KidCare/Assets.xcassets/Mascot3D.imageset/mascot_3d.png       # 있어야 한다
grep -n "scheduleViewModel\|placeViewModel\|TabPlaceholderView(tab: .alert)\|onChange(of: scenePhase)" ios/KidCare/Guardian/GuardianRootView.swift   # 넷 이상
grep -n "@SceneStorage(\"guardian.selectedTab\")" ios/KidCare/Guardian/GuardianRootView.swift   # 한 줄
grep -rn "add-ios-catalog-keys" docs/superpowers/plans/2026-09-13-kidcare-ios-phase5.md | head -1   # 5단계가 이 도구를 썼다
swift tools/check-i18n-keys.swift > /tmp/p6-i18n-before.txt; echo $?   # 1 (12개 언어 × 21키). 기준으로 남긴다
```

하나라도 다르면 맨 아래 Pre-flight conflict table 의 해당 행을 먼저 처리한다. 테스트 개수 기준(M)도 여기서 한 번 적어 둔다.

## Global Constraints

5단계 계획서의 Global Constraints 를 그대로 옮긴 것(verbatim):

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

6단계 브리프가 더한 것:

- **푸시 알림도 FCM 도 쓰지 않는다**(Spark 요금제). 알림 탭은 Firestore `events` 문서만 읽는다. 모든 리스너(알림 목록, 멤버 목록, 초대 완료 감시)에는 떼는 길이 있다.
- **다국어 생성.**
  - 스크립트 하나(`tools/ios-strings.py`)가 `i18n/*.json` 에서 14개 언어를 모두 `Localizable.xcstrings` 로 쓴다.
  - 서식 변환 규칙은 `tools/add-ios-catalog-keys.py` 와 같다. 정규식은 `%(\d+\$)?(\d+)?(\.\d+)?([sdf])` 이고, `s` 는 `@` 가 되며, 서식이 아닌 `%` 는 `%%` 가 된다.
  - 기존 한국어 항목은 바이트까지 같게 나와야 한다. 예외는 1단계에서 손으로 고친 세 키(`guardian_start_join_family`, `map_no_child`, `role_guardian`)뿐이고, 이 셋은 **명시적으로 원본 값으로 옮긴다**(판정 기록 4).
  - **번역을 지어내지 않는다.** 어떤 언어에 키가 없으면 그 칸은 영어 값으로 채우고 `needs_review` 로 표시한다. 빈 칸 목록은 생성기가 매번 출력하고, `tools/i18n-untranslated.json` 과 테스트가 정확히 맞는지 본다(판정 기록 3).
  - `%@` 는 `i18n/*.json` 에 절대 나오지 않는다.
- **아이 선택기와 초대.** 아이 선택기는 `GuardianRootView` 의 뷰모델들이 보는 아이를 바꾼다. 다시 만드는 일은 `.id(childUid)` 가 한다(4단계 통합 검토 M1 의 `.id(familyId+childUid)` 를 두 겹으로 나눈 것). 초대 발급은 진짜 가족에 쓰므로 **에뮬레이터에서만** 확인한다. 실기기 확인에서는 초대를 만들지 않는다.
- **뒤로 가기.** 새로 띄우는 화면(초대 번호)에도 눈에 보이는 뒤로 버튼이 있다(판정 기록 8).

## 공통 절차 A — 문구 키를 카탈로그에 넣는 법 (6단계부터 바뀐다)

Task 1 이 끝나면 **카탈로그를 손으로도, `add-ios-catalog-keys.py` 로도 고치지 않는다.** 그 도구는 Task 1 에서 지운다. 절차는 셋이다.

1. 새 문구가 필요하면 `i18n/ko.json` 과 `i18n/en.json` **둘 다**에 키를 넣는다. 두 파일은 키가 가나다(코드 포인트) 순으로 정렬돼 있고, 파일 끝에 줄바꿈이 하나 있다(2026-09-13 확인: 14개 파일 모두 `json.dumps(d, indent=2, ensure_ascii=False) + "\n"` 와 바이트까지 같다). 나머지 12개 언어 파일에는 **넣지 않는다.**
2. 빈 칸 목록을 고친다. `python3 tools/ios-strings.py --write-gaps` 는 지금 빈 칸을 `tools/i18n-untranslated.json` 에 다시 쓰고 카탈로그도 쓴다. **이 옵션은 키를 일부러 더하거나 뺐을 때만 쓴다.** diff 에 나온 빈 칸 변화가 의도한 것인지 눈으로 본다.
3. 평소에는 `python3 tools/ios-strings.py` 를 돌린다. 빈 칸이 기록과 다르면 쓰지 않고 멈춘다(종료 코드 1).

검사는 셋이다.
- `python3 tools/ios-strings.py --check`: 카탈로그가 원본에서 지금 생성한 결과와 바이트까지 같으면 0 이다.
- `swift tools/check-i18n-keys.swift`: 언어별 빈 칸을 나열한다. 빈 칸이 남아 있는 한 종료 코드는 1 이고, 이것이 정상이다. 사람이 읽는 보고서다.
- `LocalizableCatalogTests`·`I18nKeyParityTests`·`LocalizationBundleTests`: 기계가 막는다.

## 공통 절차 B — 커밋

```bash
cd /Users/com/work/KidCare
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew   # 비어 있어야 한다
git diff ios/KidCare/KidCareApp.swift                            # 비어 있어야 한다(configureForApp)
grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|navigationBarBackButtonHidden" ios/KidCare   # 비어 있어야 한다
python3 tools/ios-strings.py --check                             # Task 1 이후: 종료 코드 0
git add <이 Task 의 파일들>
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "<한국어 메시지>"
```

## 이 단계에서 다루지 않는 것

- **`AlertService`(상시 수신 서비스)와 알림 권한.** 설계서 §1 이 제외했다. 그래서 스위치(`fragment_alert.xml:19-53`)도, `alert_notification_denied` 권한 거절 문구(`AlertFragment.kt:77-85`)도, `AlertService.setListVisible`·`cancelAlert`(`:192, :196`)도 옮기지 않는다. 앱 권한 0개는 그대로다.
- **알림을 눌러 들어오는 길**(`EXTRA_OPEN_ALERTS`, `GuardianMainActivity.kt:168-173, 309-319`). 알림을 띄우지 않으니 눌러 들어올 길도 없다.
- **옛 1:1 가족 자료 옮기기**(`FamilyRepository.migrateLegacyFamilyData`, `GuardianMainActivity.kt:209-212`). 판정 기록 6 을 본다.
- **멤버 삭제, 가족 나가기, 아이 이름 바꾸기.** 안드로이드 보호자 화면에도 없다.
- **앱 안에서 언어를 바꾸는 대화상자.** 판정 기록 9 를 본다.
- **12개 언어의 빈 칸 번역.** 판정 기록 3 을 본다. 주인이 번역을 주면 공통 절차 A 로 채운다.
- 다크 모드, 아이콘, 개인정보 매니페스트, TestFlight 는 7단계 몫이다.

## 판정 기록 — 이 계획서가 내린 결정

1. **범위.** 설계서 §9 는 6단계를 "알림 탭 · 아이 선택기 · 14개 언어 · 오프라인/예외 화면"으로 적는다. 브리프와 같다. 아이 선택기에는 안드로이드가 그 팝업에 둔 초대 발급 두 갈래(`GuardianMainActivity.kt:250-260`)와, 같은 줄에 있는 지구본 버튼(`activity_guardian_main.xml:39-61`)이 함께 들어온다. **"오프라인/예외 화면"은 새 화면이 아니다.** 안드로이드에 오프라인 전용 화면은 없다. 오프라인은 `ListLoad` 의 `LOADING` 으로 접히고(`ListLoadState.kt:23-39`), 예외는 `errorMessage` 한 줄로 나온다. 둘 다 1·5단계가 이미 옮겼다. 이 단계는 새로 생기는 화면 셋(알림 목록, 선택기, 초대 번호)이 같은 두 장치를 지나게 한다. 그리고 단계 마무리에서 에뮬레이터를 끈 채로 다섯 탭을 확인한다.
2. **스위치 자리의 한 줄(설계서 §4 ①).** 스위치 카드 자리(`fragment_alert.xml:19-53`)에 같은 카드를 두되 스위치를 뺀다. 여백 20·위 12·아래 6, 바탕 `colorSurfaceContainerHigh`=`paper_fold`, 모서리 Medium 18, 안쪽 20×12 는 그대로다. 안의 글은 `alert_service_hint` 와 같은 BodySmall 13 `ink_soft` 로 새 키 `ios_alert_open_app_hint` 를 쓴다. 한국어 값은 설계서 문장 그대로 "아이폰에서는 앱을 열었을 때 새 소식을 확인해요."이다. 영어 값은 1~4단계의 `ios_*` 키처럼 이 계획서가 적는다. 설계서는 "14개 언어를 함께 채운다"고 했지만 브리프는 "번역을 지어내지 않는다"고 했다. **브리프가 이긴다.** 12개 언어는 판정 3 의 빈 칸으로 간다.
3. **빈 칸은 영어로 물러나고, 목록이 곧 계약이다.**
   - 지금 21개 키(1~4단계가 ko/en 에만 더한 것)가 12개 언어에 없다(2026-09-13, `swift tools/check-i18n-keys.swift`). 설계서 §7 은 "각 346문장"을 전제했는데 지금은 ko/en 이 367개다.
   - 번역을 지어낼 수 없으므로 `withKnownIssue` 를 "번역을 채워서" 닫는 길은 없다. 대신 이렇게 바꾼다. **(a)** ko·en 은 전체 키를 가져야 한다. **(b)** 다른 12개 언어의 빈 칸은 `tools/i18n-untranslated.json` 에 적힌 목록과 **정확히 같아야** 한다. 빈 칸이 새로 생겨도 실패하고, 누가 번역을 채웠는데 목록을 안 줄여도 실패한다. **(c)** 카탈로그의 빈 칸은 영어 값에 `needs_review` 로 들어가 있어야 한다.
   - 영어로 물러나는 이유는 안드로이드가 그렇게 하기 때문이다. `values/` 가 영어이고(`values/strings.xml:2` "고치려면 i18n/en.json 을 고치고"), 번역이 없는 키는 `values-de/` 에서 빠져 기본값인 영어로 나온다. iOS 는 개발 언어가 `ko`(`project.yml` `DEVELOPMENT_LANGUAGE`)라서, 칸을 비워 두면 독일어 폰에 한국어가 뜬다. 그래서 생성기가 영어를 **적어 넣는다.**
4. **1단계의 손 고침 세 키는 원본 값으로 옮긴다.**
   - 원본 값은 `guardian_start_join_family` "초대 번호로 기존 가족 참여", `map_no_child` "아직 아이 폰이 연결되지 않았어요.", `role_guardian` "보호자 (엄마·아빠)"이다. 생성기에 예외표를 두지 않는다. 두면 "생성물은 원본에서 나온다"가 영영 거짓이 된다(`LocalizableCatalogTests.알려진_어긋남` 주석이 6단계에 이 정리를 맡겼다).
   - `PairingUITests` 가 버튼을 찾는 글자 두 개를 새 값으로 바꾸고, `-AppleLanguages (ko)` 로 앱 언어를 한국어로 고정한다. 실기기의 기기 언어가 무엇이든 같은 글자로 찾기 위해서다.
   - **서버에 저장되는 이름은 문구 키를 쓰지 않는다.** `role_guardian` 이 "보호자 (엄마·아빠)"로 바뀌면 iOS 로 합류한 보호자의 `displayName` 도 따라 바뀐다. 이 앱에 영어 카탈로그가 생기면 "Parent (mum or dad)"로도 저장된다. 안드로이드는 `"우리 가족"`(`FamilyRepository.kt:145`), `"보호자"`(`:156`), `"보호자"`/`"아이"`(`:349`)를 글자 그대로 저장한다. README "안드로이드에 남은 다국어 구멍" 3번이 이것을 "화면 문장이 아니라 서버에 저장되는 값"으로 따로 분류했다. iOS 도 같은 글자를 저장한다.
5. **알림 시각 서식은 키에 담는다.** `AlertText.timeText` 는 `"a h시 m분"`·`"M월 d일 a h시 m분"` 을 `Locale.KOREA` 로 하드코딩한다(`AlertAdapter.kt:95-98`). 3단계가 같은 모양의 `LastSignalText.clockText` 를 `control_last_seen_clock_format` 키(서식 패턴 자체)로 옮긴 선례를 따른다(`StatusCardView.swift:143-160`). 새 키는 `alert_time_today_format`(ko `a h시 m분`, en `h:mm a`)과 `alert_time_date_format`(ko `M월 d일 a h시 m분`, en `MMM d, h:mm a`)이다. 달력은 그레고리력으로 고정한다. 태국어 기기의 기본 달력은 불교력이다. 오전/오후 글자는 패턴을 꺼낸 언어(`Bundle.main.preferredLocalizations.first`)의 로캘로 찍는다. 한국어 폰에서 결과는 안드로이드와 글자까지 같다.
6. **옛 1:1 가족 자료 옮기기는 옮기지 않는다.** 안드로이드는 멤버 스냅샷마다 `migrateLegacyFamilyData` 를 부른다(`:209-212`). 이 함수는 `schemaVersion < 2` 인 가족의 공용 예약·장소·설정을 한 아이 아래로 **쓰고** `families` 문서를 갱신한다(`FamilyRepository.kt:445-472`). 아이폰 보호자는 이미 안드로이드 보호자가 있는 가족에 합류한다(설계서 §5). 그 안드로이드 앱이 열리는 순간 이 옮기기를 이미 끝냈다. iOS 가 만든 가족은 처음부터 `schemaVersion = 2` 다(`Documents.swift` `FamilyDoc.currentSchemaVersion`). 옮기면 얻는 것이 없고, 대가는 **아이를 고르기만 해도 진짜 가족에 쓰는 코드**가 생긴다는 것이다. 이 쓰기가 없으면 아이 고르기가 쓰기 없는 동작이 되어 실기기에서 안전하게 확인할 수 있다.
7. **선택기는 `GuardianRootView` 바깥에 산다.**
   - 안드로이드 선택기는 액티비티에 있고, 아이를 바꾸면 **프래그먼트만** 다시 만든다(`recreateTabsForSelectedChild` :288-300). 멤버 리스너(`subscribeMembers` :185-193)는 살아남는다.
   - iOS 에서 선택기를 `GuardianRootView` 안에 두면 `.id` 가 바뀔 때 선택기와 리스너도 같이 죽고 다시 붙는다. 아이를 바꿀 때마다 멤버 전체를 다시 읽고 메뉴 상태도 사라진다.
   - 그래서 `GuardianHomeView` 가 `ChildSelectorModel` 과 선택 탭을 들고, 그 안에서 `GuardianRootView(...).id(childUid)` 를 그린다. `RouterView` 는 `GuardianHomeView(familyId:).id(familyId)` 를 그린다.
   - 선택 탭을 위로 올리는 이유는 둘이다. 첫째, 안드로이드는 **지도 탭에서 선택기 줄을 숨긴다**(`showTab` :330). 바깥 뷰가 지금 탭을 알아야 한다. 둘째, `.id` 재생성을 넘어 탭 선택이 유지돼야 한다(:293-298 `selectedTabId`).
   - 지도 탭에서는 안드로이드처럼 상태 카드의 아이 이름을 누르면 같은 메뉴가 뜬다(`MapTimelineFragment.kt:211-213`, `fragment_map_timeline.xml:41-69`).
8. **초대 번호 화면은 `fullScreenCover` 로 띄우고, 눈에 보이는 뒤로 버튼을 단다.**
   - 안드로이드는 새 액티비티(`GuardianPairingActivity`, `EXTRA_RETURN_TO_MAIN`)로 띄운다.
   - iOS 에서 push 하려면 탭들 **바깥**에 `NavigationStack` 이 있어야 한다. 그런데 5단계 예약·장소 탭은 탭 안에 자기 `NavigationStack` 을 둔다(5단계 판정 2, `ScheduleView`·`PlaceView`). 스택을 겹치면 SwiftUI 가 push 를 엉뚱한 스택으로 보낸다.
   - 그래서 전체 화면 커버 안에 스택을 하나 두고, 왼쪽 위에 `chevron.backward` 버튼을 둔다. VoiceOver 는 이 기호를 시스템 이름("뒤로")으로 읽으므로 새 키가 필요 없다.
   - 안드로이드 화면 아래의 '역할 다시 고르기'(`GuardianPairingActivity.kt:81-101`)는 **초대 갈래에서 뺀다.** 본 화면에서 연 초대 화면에서 누르면 `store.clear()` 로 이 폰의 가족 연결 기록을 지우고 첫 화면으로 보낸다. 뒤로 버튼이 이미 나가는 길이다. 안드로이드 쪽의 이 동작은 개발일지에 결함 후보로 적는다.
9. **지구본 버튼은 iOS 설정의 이 앱 페이지를 연다.** 안드로이드 버튼이 있는 이유는 "안드로이드 13 미만에는 앱별 언어 칸이 없어서"다(`activity_guardian_main.xml:39-43`). iOS 는 앱에 현지화가 둘 이상이면 설정 → 앱 → 언어 칸을 **항상** 만든다. 앱 안에서 언어를 바꾸는 대화상자를 흉내 내려면 `AppleLanguages` 를 고쳐 쓰고 재시작해야 한다. 이것은 애플이 권하지 않는 길이다. 그래서 같은 자리, 같은 모양(48×48, 그림 22, `ink_soft`)의 버튼이 `UIApplication.openSettingsURLString` 을 연다. 접근성 이름은 안드로이드와 같은 `language_picker_title` 이다.
10. **실기기 읽기 전용 스위치.** 알림 탭은 **여는 순간** 안 읽은 사건에 `read: true` 를 쓴다(`AlertFragment.kt:211-228`). 실기기 확인에서 그 탭을 열면 진짜 가족에 쓰게 된다. 그래서 `DEBUG` 빌드에서 `-readOnlyCheck` 인자로 켰을 때만 두 가지를 막는 `ReadOnlyCheck.isOn` 을 둔다. 읽음 쓰기는 아무것도 하지 않는 클로저로 바뀌고, 선택기 메뉴의 초대 두 줄은 흐려진다. 출시 빌드에서는 늘 `false` 다. 판단 코드(뷰모델)는 건드리지 않고 주입만 바꾼다.
11. **시각 기준.** 알림 줄의 "오늘인가"와 초대 번호의 "몇 분 남았나"는 안드로이드가 기기 시계를 쓴다(`AlertAdapter.kt:101, 151`, `GuardianPairingActivity.kt:204`). iOS 도 기기 시계를 쓴다. 초대 **만료 시각 자체**는 `createInvite` 가 서버 보정 시각으로 계산한다(1단계에서 이미 그렇다).
12. **알림 줄의 그림.** 벡터를 새로 그리지 않고 SF Symbol 을 쓴다. 한 앱 안에서 같은 뜻이면 같은 그림을 쓴다.
    - `ic_tab_place` → `GuardianTab.place.systemImage`(`mappin.and.ellipse`)
    - `ic_tab_alert` → `GuardianTab.alert.systemImage`(`bell.badge`)
    - `ic_route` → `point.topleft.down.to.point.bottomright.curvepath`
    - `ic_battery` → `battery.25`
    - `ic_shield_alert` → `exclamationmark.shield`
    - `ic_signal_off` → `antenna.radiowaves.left.and.right.slash`
    - `ic_error` → `exclamationmark.circle`
    - 색은 `AlertText.color`(`AlertAdapter.kt:125-133`) 그대로다.

---

## File Structure

```
tools/
├─ ios-strings.py                     신규. i18n/*.json 14벌 → Localizable.xcstrings(설계서 §7)
├─ i18n-untranslated.json             신규. 언어별 빈 칸 목록(판정 3의 계약)
└─ add-ios-catalog-keys.py            삭제. ios-strings.py 로 대체
i18n/ko.json, i18n/en.json            수정. 새 키 3개(Task 1), ios_tab_not_ready_body 삭제(Task 2)
ios/project.yml                       수정. CFBundleLocalizations 14개, KidCare 스킴 test 언어 ko/KR
ios/KidCare/
├─ Localizable.xcstrings              생성물. 14개 언어
├─ RouterView.swift                   수정. GuardianRootView → GuardianHomeView
├─ Core/
│  ├─ Documents.swift                 수정. 파일 끝에 EventDoc·EventType
│  ├─ EventRepository.swift           신규. observeEvents·markRead
│  └─ FamilyRepository.swift          수정. FamilyMember·observeMembers·fetchMembers, 저장 이름 글자(판정 4)
├─ Onboarding/
│  ├─ JoinFamilyView.swift            수정. displayName 빈 값(판정 4)
│  ├─ InviteSession.swift             신규. GuardianPairingActivity 초대 갈래 짝
│  ├─ GuardianInviteView.swift         신규. activity_guardian_pairing.xml 짝(초대 갈래)
│  └─ InviteCodeView.swift             수정. 주석만(초대 갈래는 GuardianInviteView)
└─ Guardian/
   ├─ ReadOnlyCheck.swift             신규. DEBUG 전용 -readOnlyCheck(판정 10)
   ├─ AlertText.swift                 신규. AlertText 짝
   ├─ AlertViewModel.swift            신규. AlertFragment 두뇌
   ├─ AlertView.swift                 신규. fragment_alert.xml·item_alert.xml
   ├─ ChildSelectorModel.swift        신규. applyMembers·childLabel·selectChild 짝
   ├─ ChildSelectorBar.swift          신규. child_selector_bar·언어 버튼·ChildMenu
   ├─ GuardianHomeView.swift          신규. 선택기·선택 탭·초대 커버의 주인
   ├─ GuardianRootView.swift          수정. 알림 탭, selectedTab 바인딩, 자리표시 삭제
   └─ StatusCardView.swift            수정. 아이 이름을 누르면 선택 메뉴(지도 탭)
ios/KidCareTests/
├─ I18nKeyParityTests.swift           수정. withKnownIssue → 빈 칸 계약
├─ LocalizableCatalogTests.swift      수정. 14개 언어·needs_review·알려진 어긋남 삭제
├─ LocalizationBundleTests.swift      신규. 번들에 14개 lproj, 테스트 언어 ko, 영어 물러남
├─ EventDocumentsTests.swift          신규
├─ EventRepositoryTests.swift         신규(에뮬레이터)
├─ AlertTextTests.swift               신규
├─ AlertViewModelTests.swift          신규
├─ ChildSelectorModelTests.swift      신규
├─ FamilyMembersTests.swift           신규(에뮬레이터)
├─ InviteSessionTests.swift           신규
└─ InviteFlowTests.swift              신규(에뮬레이터)
ios/KidCareUITests/PairingUITests.swift   수정. 새 버튼 글자, -AppleLanguages (ko)
README.md                             수정(Task 5). 개발일지·함께 고쳐야 하는 짝·다국어 절
```

| Task | 끝나면 |
|---|---|
| 1 | 카탈로그가 14개 언어로 생성되고, 빈 칸 계약·영어 물러남·테스트 언어 고정이 테스트로 고정된다 |
| 2 | 알림 탭이 안드로이드와 같은 화면으로 뜨고, 살구빛·읽음 쓰기·세 상태가 뷰모델 테스트와 에뮬레이터 테스트로 고정된다 |
| 3 | 초대 세션과 번호 화면이 안드로이드 초대 갈래처럼 발급·새 번호·시간 초과·합류 감지를 하고, 에뮬레이터에서 아이가 들어오면 한 번 넘어간다(여는 곳은 Task 4) |
| 4 | 선택기 줄·지도 카드 메뉴로 아이를 바꾸면 탭 뷰모델 다섯이 새 아이로 다시 만들어지고, 메뉴의 초대 두 줄이 번호 화면을 연다. 지구본 버튼이 설정을 연다 |
| 단계 마무리 | 통합 리뷰 한 번, 에뮬레이터 시뮬레이터 확인(오프라인 포함) 한 번 |
| 5 | 실기기에서 읽기 전용으로 알림·선택기·언어를 보고, 개발일지를 쓴다 |

---
### Task 1: 14개 언어 카탈로그 생성기 — 빈 칸은 영어로 물러나고, 목록이 계약이 된다

**끝나면 `python3 tools/ios-strings.py` 한 번으로 `Localizable.xcstrings` 가 367+3개 키 × 14개 언어로 나온다.** 기존 한국어 항목은 세 키를 빼고 바이트까지 같다. 빌드된 앱 번들에 `lproj` 가 14개 들어 있다. 12개의 `withKnownIssue` 는 빈 칸 계약 검사로 바뀐다. 테스트는 한국어로 고정돼 돈다. 화면 변화는 없다. 예외는 역할 선택의 두 버튼 글자로, 원본 값으로 바뀐다.

**Files:**
- Create: `tools/ios-strings.py`, `tools/i18n-untranslated.json`(생성기가 씀)
- Delete: `tools/add-ios-catalog-keys.py`
- Modify: `tools/check-i18n-keys.swift:84`(마지막 안내 한 줄)
- Modify: `i18n/ko.json`, `i18n/en.json`(키 3개 추가)
- Modify: `ios/project.yml`(`CFBundleLocalizations`, `KidCare` 스킴 test `language`/`region`)
- Modify: `ios/KidCare/Localizable.xcstrings`(생성물)
- Modify: `ios/KidCare/Core/FamilyRepository.swift`(`createFamily`·`joinFamily` 의 저장 이름), `ios/KidCare/Onboarding/JoinFamilyView.swift`(`displayName: ""`)
- Modify: `ios/KidCareUITests/PairingUITests.swift`
- Test: `ios/KidCareTests/I18nKeyParityTests.swift`(다시 씀), `LocalizableCatalogTests.swift`(수정), `LocalizationBundleTests.swift`(신규)

**Interfaces:**
- Consumes: `TestRepo.root()`(TestDoubles), `LocalizableCatalogTests.카탈로그_값(_:)`
- Produces:
  - 명령 `python3 tools/ios-strings.py [--check | --write-gaps]`
  - 파일 `tools/i18n-untranslated.json` — `{ "<i18n 파일 이름>": [키, …] }`, ko·en 을 뺀 12개
  - `LocalizableCatalogTests.언어_태그: [(file: String, tag: String)]` — Task 5 개발일지와 다른 테스트가 쓴다
  - 문구 키 `ios_alert_open_app_hint`, `alert_time_today_format`, `alert_time_date_format` — Task 2 가 쓴다

**정본:** 서식 변환은 `tools/add-ios-catalog-keys.py:21-45`(지우기 전에 옮긴다)와 `LocalizableCatalogTests.swift:19-40`. 언어 태그는 `core/AppLanguage.kt:23-36`·`res/xml/locales_config.xml`(인도네시아어 파일은 `id`, 리소스는 `values-in`). 영어 물러남은 `res/values/strings.xml:2`. 저장 이름은 `core/FamilyRepository.kt:145, 156, 349`.

- [ ] **Step 1: 빈 칸 계약 테스트를 먼저 쓴다**

`ios/KidCareTests/I18nKeyParityTests.swift` 를 통째로 바꾼다:

```swift
import Foundation
import Testing

/// `i18n/*.json` 14벌의 키 계약(6단계 계획서 판정 기록 3).
///
/// 5단계까지는 `withKnownIssue` 로 "12개 언어에 21키가 없다"를 알려진 문제로만 기록했다. 번역은 지어낼 수
/// 없으므로(안전 문구를 기계 번역으로 흘려보내지 않는다) 그 문제를 "채워서" 닫는 길은 없다. 대신 빈 칸을
/// `tools/i18n-untranslated.json` 에 적어 두고 **정확히** 같은지 본다 — 빈 칸이 새로 생겨도, 누가 번역을
/// 채웠는데 목록을 안 줄여도 빨개진다. 빈 칸이 기기에서 어떻게 보이는지는 `LocalizationBundleTests` 가 본다.
struct I18nKeyParityTests {

    /// 빈 칸이 물러날 곳이라 빠지면 안 되는 두 언어. en 은 안드로이드 `values/` 의 언어다(strings.xml:2).
    static let 전부_있어야_하는_언어: Set<String> = ["ko", "en"]
    static let 언어: Set<String> = ["ko", "en", "ja", "zh", "zh_Hant", "es", "pt", "de", "fr", "it", "ru", "id", "vi", "th"]

    private func json(_ relative: String) throws -> [String: Any] {
        let root = try #require(TestRepo.root(), "저장소 루트를 못 찾았다 (i18n/ 와 ios/ 가 함께 있는 폴더가 없다)")
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], "\(relative) 이 JSON 객체가 아니다")
    }

    private func keys(_ lang: String) throws -> Set<String> {
        Set(try json("i18n/\(lang).json").keys)
    }

    @Test("i18n/ 에는 정확히 14개 언어 파일이 있다 — 하나가 통째로 빠지면 그 언어 칸 전체가 조용히 영어가 된다")
    func 언어_파일은_열넷() throws {
        let root = try #require(TestRepo.root())
        let names = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("i18n").path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
        #expect(Set(names) == Self.언어)
    }

    @Test("ko 와 en 은 모든 키를 가진다")
    func 한국어와_영어는_빈_칸이_없다() throws {
        var union = Set<String>()
        for lang in Self.언어 { union.formUnion(try keys(lang)) }
        for lang in Self.전부_있어야_하는_언어.sorted() {
            let missing = union.subtracting(try keys(lang)).sorted()
            #expect(missing.isEmpty, "\(lang).json 에 없는 키: \(missing.joined(separator: ", "))")
        }
    }

    @Test("나머지 12개 언어의 빈 칸은 tools/i18n-untranslated.json 과 정확히 같고, 원본에 없는 키는 없다")
    func 빈_칸은_기록과_같다() throws {
        let ko = try keys("ko")
        let recorded = try json("tools/i18n-untranslated.json")
        let others = Self.언어.subtracting(Self.전부_있어야_하는_언어)
        #expect(Set(recorded.keys) == others, "기록의 언어 목록이 12개 언어와 다르다")
        for lang in others.sorted() {
            let have = try keys(lang)
            #expect(have.subtracting(ko).isEmpty, "\(lang).json 에만 있는 키: \(have.subtracting(ko).sorted())")
            let actual = ko.subtracting(have)
            let expected = Set(try #require(recorded[lang] as? [String], "\(lang) 기록이 배열이 아니다"))
            #expect(
                actual == expected,
                "\(lang): 새 빈 칸 \(actual.subtracting(expected).sorted()) / 채웠는데 기록에 남은 칸 \(expected.subtracting(actual).sorted()) — 의도한 변화면 python3 tools/ios-strings.py --write-gaps"
            )
        }
    }
}
```

`ios/KidCareTests/LocalizableCatalogTests.swift` 를 고친다.

1. `static let 알려진_어긋남 …` 과 그 문서 주석을 지운다.
2. 타입 주석 첫 문단을 "`Localizable.xcstrings` 는 `tools/ios-strings.py` 가 `i18n/*.json` 14벌에서 생성한다(6단계). 생성물이 원본과 어긋나지 않았는지, 코드가 부르는 키가 빠지지 않았는지를 기계로 본다."로 바꾼다.
3. `서식_변환` 테스트와 `카탈로그_값` 은 그대로 둔다. 파이썬 생성기와 **따로 구현한 두 번째 답**이라서, 둘이 갈리면 여기서 드러난다.
4. `카탈로그()` 아래에 다음을 더하고, 테스트 `카탈로그는_원본에서_나온다`·`원본에는_iOS_서식이_없다` 를 아래 코드로 바꾼다:

```swift
    /// (i18n 파일 이름, 카탈로그 언어 태그). 태그는 안드로이드 `AppLanguage.kt:23-36` 의 tag 와 같다 —
    /// 인도네시아어는 파일도 태그도 `id` 다(`values-in` 은 안드로이드 리소스 폴더 이름일 뿐이다).
    static let 언어_태그: [(file: String, tag: String)] = [
        ("ko", "ko"), ("en", "en"), ("ja", "ja"), ("zh", "zh-Hans"), ("zh_Hant", "zh-Hant"),
        ("es", "es"), ("pt", "pt"), ("de", "de"), ("fr", "fr"), ("it", "it"),
        ("ru", "ru"), ("id", "id"), ("vi", "vi"), ("th", "th"),
    ]

    private func 항목들() throws -> [String: [String: Any]] {
        try #require(try json("ios/KidCare/Localizable.xcstrings")["strings"] as? [String: [String: Any]])
    }

    private func 칸(_ entry: [String: Any], _ tag: String) -> (state: String?, value: String?) {
        let unit = ((entry["localizations"] as? [String: Any])?[tag] as? [String: Any])?["stringUnit"] as? [String: Any]
        return (unit?["state"] as? String, unit?["value"] as? String)
    }

    @Test("원본의 모든 키가 14개 언어 칸을 가진다 — 번역은 translated, 빈 칸은 en 값의 needs_review(판정 기록 3)")
    func 카탈로그는_원본에서_나온다() throws {
        let strings = try 항목들()
        let ko = try json("i18n/ko.json")
        let en = try json("i18n/en.json")
        #expect(Set(strings.keys) == Set(ko.keys), "카탈로그 키가 원본과 다르다 — python3 tools/ios-strings.py")
        for (file, tag) in Self.언어_태그 {
            let source = try json("i18n/\(file).json")
            for key in ko.keys.sorted() {
                let entry = try #require(strings[key], "\(key) 가 카탈로그에 없다")
                let unit = 칸(entry, tag)
                if let value = source[key] as? String {
                    #expect(unit.state == "translated", "\(tag) \(key)")
                    #expect(unit.value == Self.카탈로그_값(value), "\(tag) \(key) 값이 원본과 다르다")
                } else {
                    let fallback = try #require(en[key] as? String)
                    #expect(unit.state == "needs_review", "\(tag) \(key) 빈 칸이 표시되지 않았다")
                    #expect(unit.value == Self.카탈로그_값(fallback), "\(tag) \(key) 빈 칸이 영어로 물러나지 않았다")
                }
            }
        }
    }

    @Test("공유 원본 i18n/*.json 14벌에는 iOS 서식 %@ 가 없다")
    func 원본에는_iOS_서식이_없다() throws {
        for (file, _) in Self.언어_태그 {
            for (key, value) in try json("i18n/\(file).json") {
                #expect(!(value as? String ?? "").contains("%@"), "i18n/\(file).json 의 \(key) 에 %@ 가 있다")
            }
        }
    }
```

`코드가_부르는_키는_카탈로그에_있다` 는 그대로 둔다(`카탈로그()` 가 ko 값을 준다).

`ios/KidCareTests/LocalizationBundleTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 빌드된 앱 번들이 정말 14개 언어를 싣는지, 테스트가 한국어로 도는지를 **결과물을 열어** 본다.
/// 카탈로그 파일이 맞아도 빌드가 언어를 빠뜨리면 그 언어 기기에서만 틀리고, 다른 어떤 테스트도 못 잡는다.
struct LocalizationBundleTests {

    private func json(_ relative: String) throws -> [String: Any] {
        let root = try #require(TestRepo.root())
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("테스트는 한국어로 돈다 — 한국어 기대값을 적은 테스트 전부의 전제(project.yml 스킴 test language: ko)")
    func 테스트_언어는_한국어() {
        #expect(Bundle.main.preferredLocalizations.first == "ko")
        #expect(String(localized: "tab_alert") == "알림")
    }

    @Test("번들에 14개 언어 lproj 가 모두 있고, 각자 자기 원본 값을 낸다")
    func 열네_언어가_실린다() throws {
        for (file, tag) in LocalizableCatalogTests.언어_태그 {
            let path = try #require(Bundle.main.path(forResource: tag, ofType: "lproj"), "\(tag).lproj 가 번들에 없다")
            let bundle = try #require(Bundle(path: path))
            let expected = try #require(try json("i18n/\(file).json")["tab_alert"] as? String)
            #expect(bundle.localizedString(forKey: "tab_alert", value: "(없음)", table: nil) == expected, "\(tag)")
        }
    }

    @Test("빈 칸은 개발 언어(한국어)가 아니라 영어로 나온다 — 안드로이드 values/ 와 같은 물러남(판정 기록 3)")
    func 빈_칸은_영어로_나온다() throws {
        let gaps = try json("tools/i18n-untranslated.json")
        guard let key = (gaps["de"] as? [String])?.first else { return }   // 모두 번역되면 볼 칸이 없다
        let en = try #require(try json("i18n/en.json")[key] as? String)
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        #expect(bundle.localizedString(forKey: key, value: "(없음)", table: nil) == LocalizableCatalogTests.카탈로그_값(en))
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/I18nKeyParityTests -only-testing:KidCareTests/LocalizableCatalogTests -only-testing:KidCareTests/LocalizationBundleTests`
Expected: FAIL. `tools/i18n-untranslated.json` 이 없고, 카탈로그 키가 원본과 다르고, `de.lproj` 가 번들에 없다.

- [ ] **Step 3: 새 키 셋을 ko·en 에 넣는다**

```bash
cd /Users/com/work/KidCare && python3 - <<'EOF'
import json
ADD = {
    'ko': {
        'ios_alert_open_app_hint': '아이폰에서는 앱을 열었을 때 새 소식을 확인해요.',   # 설계서 §4 ① 문장 그대로
        'alert_time_today_format': 'a h시 m분',                                       # AlertAdapter.kt:95-96
        'alert_time_date_format': 'M월 d일 a h시 m분',                                # AlertAdapter.kt:97-98
    },
    'en': {
        'ios_alert_open_app_hint': 'On iPhone, new updates show up when you open the app.',
        'alert_time_today_format': 'h:mm a',
        'alert_time_date_format': 'MMM d, h:mm a',
    },
}
for lang, add in ADD.items():
    path = f'i18n/{lang}.json'
    raw = open(path, encoding='utf-8').read()
    d = json.loads(raw)
    assert list(d) == sorted(d) and json.dumps(d, indent=2, ensure_ascii=False) + '\n' == raw, path + ' 모양이 예상과 다르다'
    for k, v in add.items():
        assert k not in d, k
        d[k] = v
    open(path, 'w', encoding='utf-8').write(json.dumps(dict(sorted(d.items())), indent=2, ensure_ascii=False) + '\n')
print('ok')
EOF
git diff --stat i18n    # ko.json·en.json 각 3줄 추가만
```

- [ ] **Step 4: 생성기를 쓴다**

`tools/ios-strings.py`:

```python
#!/usr/bin/env python3
# i18n/*.json 14벌 → ios/KidCare/Localizable.xcstrings (설계서 §7, 6단계 계획서 공통 절차 A).
#
#   python3 tools/ios-strings.py              생성한다. 빈 칸이 기록과 다르면 쓰지 않고 멈춘다.
#   python3 tools/ios-strings.py --check      쓰지 않는다. 카탈로그가 지금 생성 결과와 다르면 종료 코드 1.
#   python3 tools/ios-strings.py --write-gaps 빈 칸 기록(tools/i18n-untranslated.json)도 새로 쓴다.
#
# 번역을 짓지 않는다. 어떤 언어에 키가 없으면 그 칸에 영어 값을 넣고 needs_review 로 표시한다 —
# 안드로이드도 values-<언어>/ 에 없는 키는 기본 values/(영어)로 나온다(values/strings.xml:2).
# iOS 는 개발 언어가 ko 라서 칸을 비워 두면 독일어 폰에 한국어가 뜬다.
#
# 서식 변환은 옛 tools/add-ios-catalog-keys.py 와 LocalizableCatalogTests.카탈로그_값 과 같다:
# %1$s → %1$@, 숫자 서식(%1$d, %1$02d, %1$.1f)은 그대로, 서식이 아닌 % 는 %%.
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, 'ios/KidCare/Localizable.xcstrings')
GAPS = os.path.join(ROOT, 'tools/i18n-untranslated.json')
# (i18n 파일 이름, 카탈로그 언어 태그). 태그는 안드로이드 AppLanguage.kt:23-36 의 tag 와 같다.
LANGS = [
    ('ko', 'ko'), ('en', 'en'), ('ja', 'ja'), ('zh', 'zh-Hans'), ('zh_Hant', 'zh-Hant'),
    ('es', 'es'), ('pt', 'pt'), ('de', 'de'), ('fr', 'fr'), ('it', 'it'),
    ('ru', 'ru'), ('id', 'id'), ('vi', 'vi'), ('th', 'th'),
]
FULL = ('ko', 'en')
FORMAT = re.compile(r'%(\d+\$)?(\d+)?(\.\d+)?([sdf])')


def scan(value):
    """(iOS 값, 서식 인자 목록[(위치, 변환 문자)])."""
    out, specs, i = [], [], 0
    while i < len(value):
        if value[i] != '%':
            out.append(value[i])
            i += 1
            continue
        m = FORMAT.match(value, i)
        if m:
            c = m.group(4)
            out.append('%' + (m.group(1) or '') + (m.group(2) or '') + (m.group(3) or '') + ('@' if c == 's' else c))
            specs.append((m.group(1) or '', c))
            i = m.end()
        elif value.startswith('%%', i):
            out.append('%%')
            i += 2
        else:
            out.append('%%')
            i += 1
    return ''.join(out), specs


def conv(value):
    return scan(value)[0]


# 변환 규칙이 조용히 바뀌지 않게 실행할 때마다 확인한다(옛 add-ios-catalog-keys.py 의 세 줄 그대로).
assert conv('%1$.1fkm') == '%1$.1fkm'
assert conv('배터리 %1$d%\n%2$s 기준') == '배터리 %1$d%%\n%2$@ 기준'
assert conv('%1$02d:%2$02d') == '%1$02d:%2$02d'


def fail(message):
    sys.exit('ios-strings: ' + message)


def load():
    src = {}
    for name, _ in LANGS:
        with open(os.path.join(ROOT, 'i18n', name + '.json'), encoding='utf-8') as f:
            d = json.load(f)
        if not all(isinstance(k, str) and isinstance(v, str) for k, v in d.items()):
            fail(name + '.json 에 문자열이 아닌 값이 있다')
        src[name] = d
    return src


def build(src, version):
    ko, en = src['ko'], src['en']
    if set(ko) != set(en):
        fail('ko·en 키가 다르다: ko 에만 %s / en 에만 %s' % (sorted(set(ko) - set(en)), sorted(set(en) - set(ko))))
    gaps, problems = {}, []
    for name, _ in LANGS:
        d = src[name]
        extra = sorted(set(d) - set(ko))
        if extra:
            problems.append('%s.json 에만 있는 키: %s' % (name, extra))
        for key, value in d.items():
            if '%@' in value:
                problems.append('%s.json %s 에 %%@ 가 있다 — 원본은 안드로이드 서식만 쓴다' % (name, key))
            # 번역이 ko 에 없는 인자를 읽으면 String(format:) 이 없는 인자를 읽어 앱이 죽는다.
            # 인자를 덜 쓰는 것은 안전하다(2026-09-13 원본 14벌 전부 이 검사를 통과한다).
            if key in ko and not set(scan(value)[1]) <= set(scan(ko[key])[1]):
                problems.append('%s.json %s 가 ko 에 없는 서식 인자를 쓴다' % (name, key))
        if name not in FULL:
            gaps[name] = sorted(set(ko) - set(d))
    if problems:
        fail('\n'.join(problems))

    strings = {}
    for key in sorted(ko):
        localizations = {}
        for name, tag in LANGS:
            if key in src[name]:
                unit = {'state': 'translated', 'value': conv(src[name][key])}
            else:
                unit = {'state': 'needs_review', 'value': conv(en[key])}
            localizations[tag] = {'stringUnit': unit}
        strings[key] = {'extractionState': 'manual', 'localizations': localizations}
    catalog = {'sourceLanguage': 'ko', 'strings': strings, 'version': version}
    # sort_keys + indent=2 + ensure_ascii=False + 끝 줄바꿈: 5단계까지의 카탈로그와 같은 모양이다
    # (2026-09-13 확인 — 기존 파일을 이 방식으로 다시 쓰면 바이트까지 같다).
    return json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True) + '\n', gaps


def report(gaps):
    for name, keys in sorted(gaps.items()):
        print('번역 대기 %-8s %3d개' % (name, len(keys)))
    if gaps:
        common = sorted(set.intersection(*(set(v) for v in gaps.values())))
        if common:
            print('12개 언어 모두 영어로 물러나는 키: ' + ' '.join(common))


def main(args):
    with open(CATALOG, encoding='utf-8') as f:
        current = f.read()
    version = json.loads(current).get('version', '1.0')
    src = load()
    text, gaps = build(src, version)
    report(gaps)

    if '--write-gaps' in args:
        with open(GAPS, 'w', encoding='utf-8') as f:
            f.write(json.dumps(gaps, indent=2, ensure_ascii=False, sort_keys=True) + '\n')
    else:
        with open(GAPS, encoding='utf-8') as f:
            recorded = json.load(f)
        if recorded != gaps:
            for name in sorted(set(recorded) | set(gaps)):
                before, after = set(recorded.get(name, [])), set(gaps.get(name, []))
                if before != after:
                    print('%s: 새 빈 칸 %s / 채워진 칸 %s' % (name, sorted(after - before), sorted(before - after)))
            fail('빈 칸이 tools/i18n-untranslated.json 과 다르다. 의도한 변화면 --write-gaps 로 다시 쓴다')

    if '--check' in args:
        if current != text:
            fail('카탈로그가 원본에서 생성한 결과와 다르다. python3 tools/ios-strings.py 를 돌린다')
        return
    if current != text:
        with open(CATALOG, 'w', encoding='utf-8') as f:
            f.write(text)
    print('카탈로그 %d키 × %d개 언어' % (len(src['ko']), len(LANGS)))


if __name__ == '__main__':
    main(sys.argv[1:])
```

- [ ] **Step 5: 생성하고, 한국어 항목이 바이트까지 같은지 대조한다**

```bash
cd /Users/com/work/KidCare
cp ios/KidCare/Localizable.xcstrings /tmp/p6-catalog-before.xcstrings
python3 tools/ios-strings.py --write-gaps
# 기대: "번역 대기 de 24개" … 12줄(21키 + Step 3 의 3키). "카탈로그 370키 × 14개 언어"
python3 - <<'EOF'
import json
old = json.load(open('/tmp/p6-catalog-before.xcstrings', encoding='utf-8'))
new = json.load(open('ios/KidCare/Localizable.xcstrings', encoding='utf-8'))
MIGRATED = {'guardian_start_join_family', 'map_no_child', 'role_guardian'}   # 판정 기록 4
assert set(old['strings']) <= set(new['strings'])
for k, e in old['strings'].items():
    if k in MIGRATED:
        continue
    assert new['strings'][k]['extractionState'] == e['extractionState'], k
    assert new['strings'][k]['localizations']['ko'] == e['localizations']['ko'], k
# ko 칸만 남기면 옛 파일(세 키 제외)과 바이트까지 같다
ko_only = {k: {'extractionState': v['extractionState'], 'localizations': {'ko': v['localizations']['ko']}}
           for k, v in new['strings'].items() if k in old['strings'] and k not in MIGRATED}
old_rest = {k: v for k, v in old['strings'].items() if k not in MIGRATED}
dump = lambda s: json.dumps({'sourceLanguage': 'ko', 'strings': s, 'version': old['version']}, indent=2, ensure_ascii=False, sort_keys=True)
assert dump(ko_only) == dump(old_rest)
for k in sorted(MIGRATED):
    print(k, old['strings'][k]['localizations']['ko']['stringUnit']['value'], '→', new['strings'][k]['localizations']['ko']['stringUnit']['value'])
print('한국어 항목 일치')
EOF
python3 tools/ios-strings.py --check; echo $?    # 0
```

기대하는 세 줄은 이렇다: `guardian_start_join_family 가족에 합류하기 → 초대 번호로 기존 가족 참여`, `map_no_child 아직 연결된 아이가 없어요 → 아직 아이 폰이 연결되지 않았어요.`, `role_guardian 보호자 → 보호자 (엄마·아빠)`.

`tools/add-ios-catalog-keys.py` 를 지운다(`git rm`). `tools/check-i18n-keys.swift:84` 의 안내를 바꾼다:

```swift
    print("번역을 지어내지 말 것 — 빈 칸은 tools/i18n-untranslated.json 에 기록돼 있고 카탈로그에서는 영어로 물러난다(python3 tools/ios-strings.py).")
```

- [ ] **Step 6: 번들 언어와 테스트 언어를 못박는다**

`ios/project.yml` 의 `KidCare` 타깃 `info.properties` 에서 `CFBundleDisplayName` 아래에 더한다:

```yaml
        # 14개 언어(안드로이드 AppLanguage.kt:23-36 의 tag). 설정 → 앱 → 언어 칸과 번들이 고르는 언어가
        # 이 목록을 본다. 번역 빈 칸은 카탈로그가 영어로 채운다(tools/ios-strings.py).
        CFBundleLocalizations: [ko, en, ja, zh-Hans, zh-Hant, es, pt, de, fr, it, ru, id, vi, th]
```

`schemes.KidCare.test` 를 이렇게 바꾼다:

```yaml
    test:
      config: Debug
      # 6단계부터 카탈로그에 en 이 있다. 시뮬레이터 언어가 영어면 한국어 기대값을 적은 테스트가 전부
      # 빨개지므로 테스트 언어를 못박는다(LocalizationBundleTests.테스트_언어는_한국어 가 지킨다).
      language: ko
      region: KR
      targets:
        - KidCareTests
```

`cd ios && xcodegen generate` 가 `language`/`region` 을 모른다고 거부하면 **멈추고 보고한다.** 테스트 명령(Global Constraints)을 바꾸지 않는다.

- [ ] **Step 7: 세 키를 원본 값으로 옮긴 뒷정리(판정 기록 4)**

`ios/KidCareUITests/PairingUITests.swift`:
- 두 테스트의 `app.launch()` 바로 앞에 `app.launchArguments += ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]` 를 더한다. 그 위에 주석 "기기 언어와 무관하게 한국어 글자로 버튼을 찾는다(6단계부터 14개 언어)"를 단다.
- `app.buttons["보호자"]` 두 곳을 `app.buttons["보호자 (엄마·아빠)"]` 로 바꾼다.
- `app.buttons["가족에 합류하기"]` 를 `app.buttons["초대 번호로 기존 가족 참여"]` 로 바꾼다.
- 테스트 주석 "보호자 → 가족에 합류하기 → …"도 같은 글자로 고친다.

`ios/KidCare/Core/FamilyRepository.swift`:
- `createFamily` 의 `name: String(localized: "family_default_name")` 를 `name: "우리 가족"` 으로 바꾼다.
- 같은 함수의 `displayName: String(localized: "role_guardian")` 을 `displayName: "보호자"` 로 바꾼다.
- `joinFamily` 의 `fallback` 을 `let fallback = doc.role == .guardian ? "보호자" : "아이"` 로 바꾼다.
- 세 자리 위에 한 번 적는다:

```swift
        // 서버에 **저장되는** 기본 이름은 문구 키를 쓰지 않는다. 키 값은 언어마다 달라지고(6단계부터 14개),
        // role_guardian 은 화면용이라 "보호자 (엄마·아빠)"다. 안드로이드는 이 값들을 글자 그대로 저장한다
        // (FamilyRepository.kt:145, 156, 349 — README "안드로이드에 남은 다국어 구멍" 3번).
```

`ios/KidCare/Onboarding/JoinFamilyView.swift` 의 `displayName: String(localized: "role_guardian")` 을 `displayName: ""` 로 바꾼다(빈 값이면 `joinFamily` 가 "보호자"로 물러난다).

- [ ] **Step 8: 통과를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS. `I18nKeyParityTests` 3개, `LocalizationBundleTests` 3개가 새로 들어간다. `withKnownIssue` 로 기록되던 알려진 문제 12개가 사라진다. `LocalizationBundleTests.열네_언어가_실린다` 가 `xx.lproj 가 번들에 없다` 로 실패하면 **멈추고 보고한다.** `CFBundleLocalizations` 만으로 빌드가 언어를 싣지 않는다는 뜻이다. 프로젝트 언어 목록을 손으로 고치지 않는다.

```bash
grep -rn "withKnownIssue\|알려진_어긋남\|add-ios-catalog-keys" ios tools docs/superpowers/specs   # 비어 있어야 한다
```

- [ ] **Step 9: 커밋** (공통 절차 B)

```bash
git add tools/ios-strings.py tools/i18n-untranslated.json tools/check-i18n-keys.swift i18n/ko.json i18n/en.json \
  ios/project.yml ios/KidCare/Localizable.xcstrings ios/KidCare/Core/FamilyRepository.swift ios/KidCare/Onboarding/JoinFamilyView.swift \
  ios/KidCareUITests/PairingUITests.swift ios/KidCareTests/I18nKeyParityTests.swift ios/KidCareTests/LocalizableCatalogTests.swift \
  ios/KidCareTests/LocalizationBundleTests.swift
git rm tools/add-ios-catalog-keys.py
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 6단계 Task 1: 14개 언어 카탈로그를 i18n 원본에서 생성한다 — 빈 칸은 영어로 물러나고 그 목록이 계약이 된다"
```

---
### Task 2: 알림 탭 — 살구빛은 연 순간의 안 읽은 ID, 쓰기는 `read` 하나

**끝나면 '알림' 탭이 안드로이드와 같은 순서로 뜬다.** 위에서부터 제약 한 줄 카드(스위치 자리), 상태 줄, 사건 카드 목록(종류별 그림과 색·제목 · 시각·detail), 빈 목록 마스코트다. 탭이 보이는 순간 안 읽은 사건이 살구빛으로 칠해지고 서버에는 `read: true` 한 필드만 쓰인다. 읽음이 먼저 도착해도 색은 탭을 떠날 때까지 남는다. 자리표시 뷰와 `ios_tab_not_ready_body` 키가 사라진다.

**Files:**
- Modify: `ios/KidCare/Core/Documents.swift`(파일 끝에 `EventDoc`·`EventType`)
- Create: `ios/KidCare/Core/EventRepository.swift`
- Create: `ios/KidCare/Guardian/ReadOnlyCheck.swift`, `AlertText.swift`, `AlertViewModel.swift`, `AlertView.swift`
- Modify: `ios/KidCare/Guardian/GuardianRootView.swift`
- Modify: `i18n/ko.json`, `i18n/en.json`(`ios_tab_not_ready_body` 삭제), `tools/i18n-untranslated.json`, `ios/KidCare/Localizable.xcstrings`(생성)
- Test: `ios/KidCareTests/EventDocumentsTests.swift`, `AlertTextTests.swift`, `AlertViewModelTests.swift`, `EventRepositoryTests.swift`(에뮬레이터)

**Interfaces:**
- Consumes: Task 1 의 키 셋. 5단계의 `ListLoad`(`after(fromCache:)`, `emptyText(isEmpty:loaded:)`), `RuleStateLine(text:)`, `KidCarePalette.apricotSoft·berryInk·lineSoft·paperFold`, `Mascot3D` 자산, `GuardianRootView` 의 `.onChange(of: scenePhase) { _, phase in … }`. 4단계의 `errorMessage(_:)`, `GuardianTab`. 테스트 도구 `TestCallbackBox`·`TestListenerRegistration`·`TestGate`·`eventually`·`EmulatorHarness`.
- Produces:
  - `struct EventDoc: Equatable, Sendable { id, type, at: Int64, childUid, placeName, detail, read: Bool; init(id:type:at:childUid:placeName:detail:read:); init(id: String, _ data: [String: Any]) }`, `enum EventType { placeEnter, placeExit, lowBattery, permissionOff, signalLost, commandFailed }`
  - `enum EventRepository { static let recentLimit = 100; static func observeEvents(familyId:childUid:onChange:onError:) -> ListenerRegistration; static func markRead(familyId:ids:) async throws }`
  - `enum ReadOnlyCheck { static let isOn: Bool }` — Task 4 도 쓴다
  - `enum AlertText { title(_:), line(_:nowMillis:zone:locale:), timeText(atMillis:nowMillis:zone:locale:), look(_:) -> AlertLook }`, `struct AlertLook { systemImage, strong, soft }`
  - `@MainActor @Observable final class AlertViewModel { events, listLoad, 상태_줄, 강조, 읽음_쓰는_중, 빈_목록_문구; 시작한다(), 보임이_바뀌었다(_:), 정리한다() }`
  - `struct AlertView`, `struct AlertRowView`

**정본:** `guardian/AlertFragment.kt` 전체(302줄), `guardian/AlertAdapter.kt`(`bind` :51-74, `AlertText` :91-165), `core/EventRepository.kt`(`RECENT_LIMIT` :45, `observeEvents` :86-112, `markRead` :131-136), `core/model/Documents.kt:420-458`, `res/layout/fragment_alert.xml`, `res/layout/item_alert.xml`, `res/drawable/bg_icon_soft.xml`(sky_soft, 모서리 14), `guardian/ListLoadState.kt`.

치수는 다음과 같다.
- 제약 카드: 좌우 20, 위 12, 아래 6, 안쪽 20×12, 모서리 18, 바탕 `paper_fold`, 글자 13 `ink_soft`
- 상태 줄: 좌우 20, 위아래 16, 15 `ink_soft`. `RuleStateLine` 과 같은 값이다
- 목록: 위 4, 아래 12
- 카드: 좌우 20, 위아래 5, 모서리 18(`Widget.KidCare.Card`, `themes.xml:170-176`), 테두리 `line_soft` 1, 최소 높이 48, 안쪽 14×7
- 카드 안: 그림 칸 40·안쪽 9(그림 22)·모서리 14, 글 시작 12, 제목 18 medium `ink`, detail 위 2·13 `ink_soft`
- 빈 목록: 마스코트 104·불투명도 0.9, 글 위 16·줄 간격 3·15 `ink_soft`·가운데, 묶음 안쪽 20×24

**규칙 확인(`firestore.rules:267-321`).** 이 Task 가 새로 만드는 쓰기는 **보호자의 `read` 한 필드 update** 하나다(`:315-318` `affectedKeys().hasOnly(['read'])`). 읽기는 `memberOf`(`:268`)다. 쿼리 `childUid == … order by at desc limit 100` 은 운영에서 복합 색인 `events(childUid ASC, at DESC)` 가 필요하다. 이 색인은 이미 있다(`firestore.indexes.json`, 안드로이드가 같은 쿼리를 쓴다). 규칙은 바꾸지 않는다.

- [ ] **Step 1: 문서·문구·뷰모델 테스트를 먼저 쓴다**

`ios/KidCareTests/EventDocumentsTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `Documents.kt:420-458`. 아이 폰(안드로이드)이 Long 으로 쓴 at 이 NSNumber 로 온다.
struct EventDocumentsTests {

    @Test("일곱 필드를 읽고, 문서 ID 는 본문이 아니라 인자로 받는다")
    func 읽기() {
        let doc = EventDoc(id: "e1", [
            "id": "", "type": "place_enter", "at": NSNumber(value: Int64(1_789_279_920_000)),
            "childUid": "c1", "placeName": "학교", "detail": "", "read": false,
        ])
        #expect(doc == EventDoc(id: "e1", type: EventType.placeEnter, at: 1_789_279_920_000, childUid: "c1", placeName: "학교", detail: "", read: false))
    }

    @Test("빠진 필드는 코틀린 기본값(빈 문자열·0·false)으로 읽는다")
    func 기본값() {
        #expect(EventDoc(id: "e2", [:]) == EventDoc(id: "e2", type: "", at: 0))
    }

    @Test("종류 값은 안드로이드 EventType 문자열 그대로(:437-458)")
    func 종류() {
        #expect([EventType.placeEnter, EventType.placeExit, EventType.lowBattery, EventType.permissionOff, EventType.signalLost, EventType.commandFailed]
                == ["place_enter", "place_exit", "low_battery", "permission_off", "signal_lost", "command_failed"])
    }
}
```

`ios/KidCareTests/AlertTextTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `AlertAdapter.kt:91-165` 의 `AlertText`.
struct AlertTextTests {

    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private let ko = Locale(identifier: "ko")
    /// 2026-09-13 15:12 KST
    private let 오후_세시 = Int64(1_789_279_920_000)

    private func 사건(_ type: String, place: String = "", at: Int64 = 0) -> EventDoc {
        EventDoc(id: "e", type: type, at: at, childUid: "c", placeName: place)
    }

    @Test("종류마다 안드로이드와 같은 제목, 모르는 종류도 줄을 버리지 않는다(:104-115)")
    func 제목() {
        #expect(AlertText.title(사건(EventType.placeEnter, place: "학교")) == "학교에 도착했어요")
        #expect(AlertText.title(사건(EventType.placeExit, place: "학원")) == "학원에서 나섰어요")
        #expect(AlertText.title(사건(EventType.lowBattery)) == "애기폰 배터리가 얼마 안 남았어요")
        #expect(AlertText.title(사건(EventType.permissionOff)) == "애기폰에서 권한이 꺼졌어요")
        #expect(AlertText.title(사건(EventType.signalLost)) == "애기폰이 한동안 대답하지 않았어요")
        #expect(AlertText.title(사건(EventType.commandFailed)) == "애기폰에 보낸 요청이 실패했어요")
        #expect(AlertText.title(사건("geofence_v2")) == "새로운 소식이 있어요")
    }

    @Test("장소 이름이 비었거나 공백뿐이면 타임라인과 같은 '머무른 곳'(:162-164, 코틀린 ifBlank)")
    func 이름_없음() {
        #expect(AlertText.title(사건(EventType.placeEnter, place: " \n")) == "머무른 곳에 도착했어요")
    }

    @Test("오늘이면 시각만, 아니면 날짜까지 — 한국어는 안드로이드 패턴과 글자까지 같다(:95-98, :151-160)")
    func 시각() {
        #expect(AlertText.timeText(atMillis: 오후_세시, nowMillis: 오후_세시 + 60_000, zone: seoul, locale: ko) == "오후 3시 12분")
        // 자정을 막 넘긴 새벽에 어제 저녁 사건을 본다(2026-09-12 23:05 KST, 지금 09-13 00:30)
        #expect(AlertText.timeText(atMillis: 1_789_221_900_000, nowMillis: 1_789_227_000_000, zone: seoul, locale: ko) == "9월 12일 오후 11시 5분")
    }

    @Test("한 줄은 alert_row 로 제목과 시각을 잇는다(:100-102)")
    func 한_줄() {
        let doc = 사건(EventType.placeEnter, place: "학교", at: 오후_세시)
        #expect(AlertText.line(doc, nowMillis: 오후_세시, zone: seoul, locale: ko) == "학교에 도착했어요 · 오후 3시 12분")
    }

    @Test("그림과 색: 도착 풀빛, 나섬 살구빛, 배터리·권한·신호·명령 실패 자두빛, 모르는 것 하늘빛(:125-144)")
    func 모양() {
        #expect(AlertText.look(사건(EventType.placeEnter)) == AlertLook(systemImage: GuardianTab.place.systemImage, strong: KidCarePalette.grass, soft: KidCarePalette.grassSoft))
        #expect(AlertText.look(사건(EventType.placeExit)) == AlertLook(systemImage: "point.topleft.down.to.point.bottomright.curvepath", strong: KidCarePalette.apricot, soft: KidCarePalette.apricotSoft))
        #expect(AlertText.look(사건(EventType.lowBattery)) == AlertLook(systemImage: "battery.25", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft))
        #expect(AlertText.look(사건(EventType.permissionOff)).systemImage == "exclamationmark.shield")
        #expect(AlertText.look(사건(EventType.signalLost)).systemImage == "antenna.radiowaves.left.and.right.slash")
        #expect(AlertText.look(사건(EventType.commandFailed)) == AlertLook(systemImage: "exclamationmark.circle", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft))
        #expect(AlertText.look(사건("x")) == AlertLook(systemImage: GuardianTab.alert.systemImage, strong: KidCarePalette.sky, soft: KidCarePalette.skySoft))
    }
}
```

`ios/KidCareTests/AlertViewModelTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// 정본은 `AlertFragment.kt`. 줄 번호는 테스트 이름에 적는다.
@MainActor
struct AlertViewModelTests {

    /// 가짜 구독. 콜백을 꺼내 두고 테스트가 스냅샷을 직접 흘린다.
    final class 가짜_구독: Sendable {
        let onChange = TestCallbackBox<([EventDoc], Bool) -> Void>()
        let onError = TestCallbackBox<(Error) -> Void>()
        let registration = TestListenerRegistration()
        private let 횟수_잠금 = OSAllocatedUnfairLock(initialState: 0)
        var 횟수: Int { 횟수_잠금.withLock { $0 } }
        func 불렸다() { 횟수_잠금.withLock { $0 += 1 } }

        func 보낸다(_ docs: [EventDoc], fromCache: Bool = false) { onChange.value?(docs, fromCache) }
    }

    actor 읽음_기록 {
        private(set) var 호출: [[String]] = []
        func 기록(_ ids: [String]) { 호출.append(ids) }
    }

    private func 만든다(
        childUid: String? = "c1",
        구독: 가짜_구독,
        기록: 읽음_기록,
        문: TestGate? = nil,
        실패: Bool = false
    ) -> AlertViewModel {
        AlertViewModel(
            familyId: "fam",
            childUid: childUid,
            observe: { _, _, onChange, onError in
                구독.onChange.set(onChange)
                구독.onError.set(onError)
                구독.불렸다()
                return 구독.registration
            },
            markRead: { _, ids in
                await 기록.기록(ids)
                if let 문 { await 문.wait() }
                if 실패 { throw URLError(.notConnectedToInternet) }
            }
        )
    }

    private func 사건(_ id: String, read: Bool = false) -> EventDoc {
        EventDoc(id: id, type: EventType.placeEnter, at: 1, childUid: "c1", placeName: "학교", read: read)
    }

    private func 잠깐() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    /// 읽음 쓰기가 몇 번 불렸는지로 기다린다. `events` 는 앞 스냅샷과 같은 값일 수 있어 기다림 조건이 못 된다.
    private func 기록을_기다린다(_ 기록: 읽음_기록, 개수: Int) async {
        for _ in 0..<400 {
            if await 기록.호출.count >= 개수 { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("읽음 쓰기가 \(개수)번 불리지 않았다")
    }

    @Test("캐시본은 '불러오는 중', 서버본이어야 '없어요'(:152-158)")
    func 캐시본은_단언하지_않는다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([], fromCache: true)
        await eventually { vm.listLoad == .loading }
        #expect(vm.빈_목록_문구 == String(localized: "list_loading"))
        구독.보낸다([], fromCache: false)
        await eventually { vm.listLoad == .loaded }
        #expect(vm.빈_목록_문구 == String(localized: "alert_empty"))
    }

    @Test("보이는 순간 안 읽은 것만 읽음으로 쓰고, 읽음이 도착해도 살구빛은 남는다(:204-228, 클래스 주석 :34-39)")
    func 살구빛은_연_순간을_붙든다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([사건("a"), 사건("b", read: true)])
        await eventually { vm.events.count == 2 }
        vm.보임이_바뀌었다(true)
        #expect(vm.강조 == ["a"])
        await eventually { !vm.읽음_쓰는_중 }
        #expect(await 기록.호출 == [["a"]])
        구독.보낸다([사건("a", read: true), 사건("b", read: true)])
        await eventually { vm.events.allSatisfy(\.read) }
        #expect(vm.강조 == ["a"])
    }

    @Test("안 보이는 동안에는 쓰지 않는다 — 부모가 본 적 없는 것을 읽었다고 적지 않는다")
    func 숨어_있으면_안_쓴다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([사건("a")])
        await eventually { vm.events.count == 1 }
        await 잠깐()
        #expect(await 기록.호출.isEmpty)
        #expect(vm.강조.isEmpty)
    }

    @Test("떠나면 강조를 비우고, 다음에 열 때는 그 사이 새로 온 것만 살구빛(:197-200, 클래스 주석 :38-39)")
    func 다음엔_새것만() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        구독.보낸다([사건("a")])
        await eventually { vm.events.count == 1 }
        vm.보임이_바뀌었다(true)
        await eventually { !vm.읽음_쓰는_중 }
        구독.보낸다([사건("a", read: true)])
        await eventually { vm.events.first?.read == true }
        vm.보임이_바뀌었다(false)
        #expect(vm.강조.isEmpty)
        구독.보낸다([사건("c"), 사건("a", read: true)])
        await eventually { vm.events.count == 2 }
        vm.보임이_바뀌었다(true)
        #expect(vm.강조 == ["c"])
        await eventually { !vm.읽음_쓰는_중 }
        #expect(await 기록.호출 == [["a"], ["c"]])
    }

    @Test("보는 동안 새로 온 것도 그 자리에서 읽음이 된다(:159-161)")
    func 보는_동안_온_것() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        vm.보임이_바뀌었다(true)
        구독.보낸다([사건("a")])
        await eventually { vm.강조 == ["a"] && !vm.읽음_쓰는_중 }
        구독.보낸다([사건("n"), 사건("a", read: true)])
        await eventually { vm.강조 == ["a", "n"] && !vm.읽음_쓰는_중 }
        #expect(await 기록.호출 == [["a"], ["n"]])
    }

    @Test("읽음 쓰기가 도는 동안에는 겹쳐 보내지 않고, 끝난 뒤 다음 스냅샷에서 남은 것을 보낸다(:216 markJob?.isActive)")
    func 겹쳐_쓰지_않는다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록(), 문 = TestGate()
        let vm = 만든다(구독: 구독, 기록: 기록, 문: 문)
        vm.시작한다()
        vm.보임이_바뀌었다(true)
        구독.보낸다([사건("a")])
        await eventually { vm.읽음_쓰는_중 }
        구독.보낸다([사건("b"), 사건("a")])
        await eventually { vm.강조 == ["a", "b"] }
        await 잠깐()
        #expect(await 기록.호출 == [["a"]])
        await 문.open()
        await eventually { !vm.읽음_쓰는_중 }
        구독.보낸다([사건("b"), 사건("a", read: true)])
        await 기록을_기다린다(기록, 개수: 2)
        await eventually { !vm.읽음_쓰는_중 }
        #expect(await 기록.호출 == [["a"], ["b"]])
    }

    @Test("읽음 쓰기 실패는 화면에 아무 말도 하지 않는다 — 부모가 한 일이 아니다(:204-210)")
    func 읽음_실패는_조용하다() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록, 실패: true)
        vm.시작한다()
        vm.보임이_바뀌었다(true)
        구독.보낸다([사건("a")])
        await eventually { vm.강조 == ["a"] && !vm.읽음_쓰는_중 }
        #expect(await 기록.호출.count == 1)
        #expect(vm.상태_줄 == nil)
        #expect(vm.listLoad == .loaded)
    }

    @Test("구독 오류는 실패 상태와 alert_error_format 한 줄, 빈 자리는 비운다(:142-148)")
    func 구독_오류() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        구독.onError.value?(error)
        await eventually { vm.listLoad == .failed }
        #expect(vm.상태_줄 == String(format: String(localized: "alert_error_format"), errorMessage(error)))
        #expect(vm.빈_목록_문구 == nil)
    }

    @Test("아이가 없으면 구독하지 않고 map_no_child, '불러오는 중'에 갇히지 않는다(:131-137)")
    func 아이가_없으면() {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(childUid: nil, 구독: 구독, 기록: 기록)
        vm.시작한다()
        #expect(구독.횟수 == 0)
        #expect(vm.listLoad == .loaded)
        #expect(vm.상태_줄 == String(localized: "map_no_child"))
        #expect(vm.빈_목록_문구 == String(localized: "alert_empty"))
    }

    @Test("두 번 시작해도 구독은 하나, 정리하면 리스너를 떼고 늦은 스냅샷·다시 시작을 무시한다(:286-297)")
    func 정리() async {
        let 구독 = 가짜_구독(), 기록 = 읽음_기록()
        let vm = 만든다(구독: 구독, 기록: 기록)
        vm.시작한다()
        vm.시작한다()
        #expect(구독.횟수 == 1)
        vm.보임이_바뀌었다(true)
        vm.정리한다()
        #expect(구독.registration.removed)
        구독.보낸다([사건("a")])
        await 잠깐()
        #expect(vm.events.isEmpty)
        #expect(await 기록.호출.isEmpty)
        vm.시작한다()
        #expect(구독.횟수 == 1)
    }
}
```

`ios/KidCareTests/EventRepositoryTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 사건 구독과 읽음 쓰기를 에뮬레이터로 확인한다 — 보안 규칙(firestore.rules:267-321)까지 태운다.
@Suite(.serialized)
struct EventRepositoryTests {

    init() async { await EmulatorHarness.start() }

    private func 가족과_자녀() async throws -> (familyId: String, child: EmulatorHarness.ChildSession) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)
        return (familyId, child)
    }

    /// 아이 폰이 남기는 사건. 안드로이드 `EventRepository.add` 는 `doc.copy(id = "")` 를 통째로 쓴다(:53-58) —
    /// @Exclude 가 없어 본문에 "id": "" 가 실린다. 규칙: childUid 본인, read false, at 창 안(:306-310).
    private func 아이가_남긴다(_ child: EmulatorHarness.ChildSession, familyId: String, type: String, at: Int64) async throws -> String {
        let ref = child.db.collection("families").document(familyId).collection("events").document()
        try await ref.setData(["id": "", "type": type, "at": at, "childUid": child.uid, "placeName": "학교", "detail": "", "read": false])
        return ref.documentID
    }

    private func 지금() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    actor 스냅샷_기록 {
        private(set) var 마지막: (docs: [EventDoc], fromCache: Bool)?
        func 기록(_ docs: [EventDoc], _ fromCache: Bool) { 마지막 = (docs, fromCache) }
    }

    private func 기다린다(timeoutSeconds: Double = 5, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("\(timeoutSeconds)초 안에 조건이 참이 되지 않았다")
    }

    @Test("그 아이의 사건을 최신순으로, 서버 확인본(fromCache false)까지 준다(:86-112)")
    func 최신순_구독() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let 옛것 = try await 아이가_남긴다(child, familyId: familyId, type: EventType.placeEnter, at: 지금() - 2_000)
        let 새것 = try await 아이가_남긴다(child, familyId: familyId, type: EventType.placeExit, at: 지금() - 1_000)
        let 기록 = 스냅샷_기록()
        let listener = EventRepository.observeEvents(
            familyId: familyId, childUid: child.uid,
            onChange: { docs, fromCache in Task { await 기록.기록(docs, fromCache) } },
            onError: { error in Issue.record("구독 실패: \(error)") }
        )
        defer { listener.remove() }
        try await 기다린다 { await 기록.마지막?.fromCache == false && await 기록.마지막?.docs.count == 2 }
        let docs = try #require(await 기록.마지막?.docs)
        #expect(docs.map(\.id) == [새것, 옛것])
        #expect(docs.allSatisfy { $0.childUid == child.uid && !$0.read })
        #expect(EventRepository.recentLimit == 100)
    }

    @Test("읽음 표시는 read 한 필드만 바꾼다 — 규칙 hasOnly(['read']) 를 통과한다(:131-136)")
    func 읽음은_한_필드() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let id = try await 아이가_남긴다(child, familyId: familyId, type: EventType.lowBattery, at: 지금() - 1_000)
        let ref = Firestore.firestore().collection("families").document(familyId).collection("events").document(id)
        let before = try #require(try await ref.getDocument(source: .server).data())

        try await EventRepository.markRead(familyId: familyId, ids: [id])

        let after = try #require(try await ref.getDocument(source: .server).data())
        #expect(Set(after.keys) == Set(before.keys))
        #expect(after["read"] as? Bool == true)
        #expect(after["type"] as? String == EventType.lowBattery)
        #expect((after["at"] as? NSNumber)?.int64Value == (before["at"] as? NSNumber)?.int64Value)
    }

    @Test("아이는 자기 사건을 읽음으로 못 바꾼다 — 부모의 안 읽은 목록에서 지우는 길을 규칙이 막는다(:311-318)")
    func 아이는_읽음을_못_쓴다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let id = try await 아이가_남긴다(child, familyId: familyId, type: EventType.placeExit, at: 지금() - 1_000)
        await #expect(throws: (any Error).self) {
            try await child.db.collection("families").document(familyId).collection("events").document(id).updateData(["read": true])
        }
    }

    @Test("빈 목록이면 아무것도 쓰지 않는다")
    func 빈_목록() async throws {
        let (familyId, _) = try await 가족과_자녀()
        try await EventRepository.markRead(familyId: familyId, ids: [])
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/AlertTextTests`
Expected: 컴파일 실패("cannot find 'EventDoc' in scope").

- [ ] **Step 3: 문서와 저장소**

`ios/KidCare/Core/Documents.swift` 끝에 더한다:

```swift
/// families/{familyId}/events/{id} — 아이 폰이 만들고 보호자가 읽는다. 정본은 `Documents.kt:420-428`.
///
/// `firestoreData` 가 없다. 보호자가 이 문서에 쓰는 것은 `read` 한 필드뿐이고(규칙 `hasOnly(['read'])`,
/// firestore.rules:315-318), 그 계약은 `EventRepository.markRead` 안에 갇혀 있다(설계서 §5).
struct EventDoc: Equatable, Sendable {
    var id: String
    var type: String
    var at: Int64
    var childUid: String
    var placeName: String
    var detail: String
    var read: Bool

    init(id: String, type: String, at: Int64, childUid: String = "", placeName: String = "", detail: String = "", read: Bool = false) {
        self.id = id
        self.type = type
        self.at = at
        self.childUid = childUid
        self.placeName = placeName
        self.detail = detail
        self.read = read
    }

    /// 본문의 "id"(안드로이드가 빈 값으로 싣는다)는 무시하고 문서 ID 를 쓴다(`EventRepository.kt:106`).
    init(id: String, _ data: [String: Any]) {
        self.init(
            id: id,
            type: data["type"] as? String ?? "",
            at: millis(data["at"]) ?? 0,
            childUid: data["childUid"] as? String ?? "",
            placeName: data["placeName"] as? String ?? "",
            detail: data["detail"] as? String ?? "",
            read: data["read"] as? Bool ?? false
        )
    }
}

/// `EventDoc.type` 값들. 규칙이 일부러 값 목록으로 잠그지 않으므로(firestore.rules:297-301) 이 목록이 곧
/// 약속이다. 정본은 `Documents.kt:437-458`.
enum EventType {
    static let placeEnter = "place_enter"
    static let placeExit = "place_exit"
    static let lowBattery = "low_battery"
    static let permissionOff = "permission_off"
    static let signalLost = "signal_lost"
    static let commandFailed = "command_failed"
}
```

`ios/KidCare/Core/EventRepository.swift`:

```swift
import FirebaseFirestore
import Foundation
import os

/// events/ 의 보호자 쪽 절반 — 구독과 읽음 표시. 정본은 안드로이드 `core/EventRepository.kt`.
/// 만드는 쪽(`add`)은 아이 폰 전용이라 옮기지 않는다(설계서 §1).
enum EventRepository {

    /// 한 번에 들고 오는 최근 사건 수(`EventRepository.kt:45`). 목록 화면과 안드로이드 상시 수신 서비스가
    /// 같은 창을 본다. 창이 없으면 구독할 때마다 쌓인 사건 전부를 다시 읽는다(무료 한도).
    static let recentLimit = 100

    /// 규칙의 `hasOnly(['read'])` 와 **글자 그대로** 같아야 한다(:32-33).
    private static let fieldRead = "read"

    private static var db: Firestore { Firestore.firestore() }
    private static let logger = Logger(subsystem: "com.kidcare.family", category: "EventRepository")

    private static func events(_ familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("events")
    }

    /// 최근 사건을 **최신순**으로 구독한다(:86-112).
    ///
    /// `at` 으로 **거르지 않는다**(:63-75). 아이 폰 시계가 어긋난 채 적힌 at 은 보호자 폰이 정한 문턱과 어긋나
    /// 목록에 영영 안 나타난다. 정렬은 거르기가 아니라 줄 세우기라서 그런 위험이 없다.
    /// `includeMetadataChanges: true` 가 빠지면 빈 캐시 결과 뒤에 오는 빈 서버 결과를 못 받아 "불러오는 중"에
    /// 갇힌다(:97-99). `fromCache` 가 false 일 때만 "없어요"를 단언할 수 있다(`ListLoad`).
    static func observeEvents(
        familyId: String,
        childUid: String?,
        onChange: @escaping (_ docs: [EventDoc], _ fromCache: Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        let base: Query = childUid.map { events(familyId).whereField("childUid", isEqualTo: $0) } ?? events(familyId)
        return base
            .order(by: "at", descending: true)
            .limit(to: recentLimit)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    logger.warning("observeEvents 실패: familyId=\(familyId, privacy: .public) \(String(describing: error), privacy: .public)")
                    onError(error)
                    return
                }
                let docs = snapshot?.documents.map { EventDoc(id: $0.documentID, $0.data()) } ?? []
                onChange(docs, snapshot?.metadata.isFromCache ?? true)
            }
    }

    /// 읽음 표시. **`read` 필드 하나만** 쓴다(:114-130). `readAt` 같은 것을 함께 적으면 쓰기가 통째로 거부되고
    /// 안 읽음 표시가 영영 안 지워진다. 일괄 쓰기라 하나가 실패하면 전부 실패하는데, 대가는 "다음에 탭을 열면
    /// 한 번 더 시도"뿐이고 낱개로 쪼개면 쓰기 수가 줄 수만큼 는다.
    static func markRead(familyId: String, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let batch = db.batch()
        for id in ids {
            batch.updateData([fieldRead: true], forDocument: events(familyId).document(id))
        }
        try await batch.commit()
    }
}
```

`ios/KidCare/Guardian/ReadOnlyCheck.swift`:

```swift
import Foundation

/// 실기기 확인 전용 스위치(6단계 계획서 판정 기록 10).
///
/// 알림 탭은 **여는 순간** 진짜 가족의 사건에 `read: true` 를 쓰고(`AlertFragment.kt:211-228`), 선택기 메뉴는
/// 진짜 가족에 초대 코드를 만든다. 실기기 확인은 읽기만 해야 하므로, DEBUG 빌드를 `-readOnlyCheck` 인자로
/// 띄웠을 때만 읽음 쓰기를 빈 동작으로 바꾸고 초대 두 줄을 흐리게 한다. 출시 빌드에서는 늘 false 다.
/// 판단 코드(뷰모델)는 건드리지 않고 주입만 바꾼다 — 그래야 실기기에서 본 화면이 출시 화면과 같다.
enum ReadOnlyCheck {
    static let isOn: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-readOnlyCheck")
        #else
        return false
        #endif
    }()
}
```

- [ ] **Step 4: 문구 조립**

`ios/KidCare/Guardian/AlertText.swift`:

```swift
import Foundation
import SwiftUI

/// 알림 줄 하나의 그림과 색. 정본은 `AlertText.color`·`icon`(AlertAdapter.kt:125-144).
struct AlertLook: Equatable {
    let systemImage: String
    let strong: Color
    let soft: Color
}

/// 사건 문서를 부모가 읽는 한 줄로 옮긴다. 정본은 `AlertAdapter.kt:91-165` 의 `AlertText`.
enum AlertText {

    /// `🏫 학교에 도착했어요 · 오후 3시 12분` (:100-102)
    static func line(_ doc: EventDoc, nowMillis: Int64, zone: TimeZone = .current, locale: Locale = 패턴_로캘) -> String {
        String(format: String(localized: "alert_row"), title(doc), timeText(atMillis: doc.at, nowMillis: nowMillis, zone: zone, locale: locale))
    }

    /// 규칙이 type 을 잠그지 않으므로 모르는 값이 올 수 있다. 줄을 버리지 않는다 — 뜻은 몰라도 "무슨 일이 언제
    /// 있었다"는 사실은 남기 때문이다(:111-114).
    static func title(_ doc: EventDoc) -> String {
        switch doc.type {
        case EventType.placeEnter: String(format: String(localized: "alert_place_enter"), placeName(doc))
        case EventType.placeExit: String(format: String(localized: "alert_place_exit"), placeName(doc))
        case EventType.lowBattery: String(localized: "alert_low_battery")
        case EventType.permissionOff: String(localized: "alert_permission_off")
        case EventType.signalLost: String(localized: "alert_signal_lost")
        case EventType.commandFailed: String(localized: "alert_command_failed")
        default: String(localized: "alert_unknown")
        }
    }

    /// 오늘이면 시각만, 아니면 날짜까지(:146-160). 자정을 막 넘긴 새벽에 어제 저녁 사건을 볼 때 시각만 보이면
    /// 방금 일어난 일로 읽힌다. 패턴은 키에 담는다(판정 기록 5). 달력은 그레고리력으로 고정한다(태국어 기기의
    /// 기본 달력은 불교력이다). 오전/오후 글자는 패턴을 꺼낸 언어로 찍는다.
    static func timeText(atMillis: Int64, nowMillis: Int64, zone: TimeZone = .current, locale: Locale = 패턴_로캘) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let at = Date(timeIntervalSince1970: Double(atMillis) / 1000)
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1000)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = locale
        formatter.dateFormat = calendar.isDate(at, inSameDayAs: now)
            ? String(localized: "alert_time_today_format")
            : String(localized: "alert_time_date_format")
        return formatter.string(from: at)
    }

    /// 지금 앱이 고른 언어. 패턴(`alert_time_*_format`)을 꺼낸 언어와 오전/오후 글자의 언어를 맞춘다.
    static var 패턴_로캘: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "ko")
    }

    /// 종류별 색은 뜻에 맞춘다: 도착 풀빛(좋은 일), 나섬 살구빛(움직임), 나머지 넷은 살펴볼 일(:117-133).
    /// 그림은 판정 기록 12.
    static func look(_ doc: EventDoc) -> AlertLook {
        switch doc.type {
        case EventType.placeEnter:
            AlertLook(systemImage: GuardianTab.place.systemImage, strong: KidCarePalette.grass, soft: KidCarePalette.grassSoft)
        case EventType.placeExit:
            AlertLook(systemImage: "point.topleft.down.to.point.bottomright.curvepath", strong: KidCarePalette.apricot, soft: KidCarePalette.apricotSoft)
        case EventType.lowBattery:
            AlertLook(systemImage: "battery.25", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft)
        case EventType.permissionOff:
            AlertLook(systemImage: "exclamationmark.shield", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft)
        case EventType.signalLost:
            AlertLook(systemImage: "antenna.radiowaves.left.and.right.slash", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft)
        case EventType.commandFailed:
            AlertLook(systemImage: "exclamationmark.circle", strong: KidCarePalette.berryInk, soft: KidCarePalette.berrySoft)
        default:
            AlertLook(systemImage: GuardianTab.alert.systemImage, strong: KidCarePalette.sky, soft: KidCarePalette.skySoft)
        }
    }

    /// 장소 이름이 비어 있는 옛 문서를 위한 물러섬. 타임라인과 문구를 맞춘다(:162-164, 코틀린 `ifBlank`).
    private static func placeName(_ doc: EventDoc) -> String {
        doc.placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "timeline_unknown_place")
            : doc.placeName
    }
}
```

- [ ] **Step 5: 뷰모델**

`ios/KidCare/Guardian/AlertViewModel.swift`:

```swift
import FirebaseFirestore
import Foundation
import Observation
import os

/// 알림 탭의 두뇌. 정본은 `AlertFragment.kt`.
///
/// ## 살구빛과 읽음 표시가 부딪히는 문제 (:34-39, 설계서 §4)
/// "안 읽은 것은 살구빛"과 "보이면 읽음으로 바꾼다"를 곧이곧대로 붙이면 색이 부모 눈에 닿기 전에 사라진다.
/// 그래서 보이는 순간의 안 읽은 ID 를 `강조` 에 따로 붙들고 그것으로 칠한다. 탭을 떠나면 비운다.
///
/// ## 읽음 표시는 `read` 하나 (:41-44)
/// 이 뷰모델은 ID 목록만 넘긴다. 필드 계약은 `EventRepository.markRead` 안에 있다.
@MainActor
@Observable
final class AlertViewModel {

    typealias Observe = @Sendable (
        _ familyId: String, _ childUid: String?,
        _ onChange: @escaping ([EventDoc], Bool) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
    typealias MarkRead = @Sendable (_ familyId: String, _ ids: [String]) async throws -> Void

    /// 마지막 스냅샷. 최신순이다(:55-56).
    private(set) var events: [EventDoc] = []
    /// 세 상태를 왜 나누는지는 `ListLoad` 주석(:58-59).
    private(set) var listLoad: ListLoad = .loading
    /// 목록 위 한 줄. nil 이면 감춘다(:279-284).
    private(set) var 상태_줄: String?
    /// 이번에 보이기 시작했을 때 안 읽은 상태였던 ID 들(:61-62).
    private(set) var 강조: Set<String> = []
    /// 읽음 쓰기가 도는 중인가(`markJob?.isActive`, :64-65, :216).
    private(set) var 읽음_쓰는_중 = false

    let familyId: String
    let childUid: String?

    private let observe: Observe
    private let markRead: MarkRead
    private var listener: ListenerRegistration?
    private var 시작했다 = false
    /// `정리한다()` 뒤로는 구독도 쓰기도 새로 만들지 않는다(4단계 통합 검토 M1 과 같은 규율).
    private var 닫혔다 = false
    /// 지금 부모 눈앞에 있는가. 탭 전환과 앱 전환이 여기로 모인다(:67-68).
    private var 보이는가 = false
    private var 읽음_쓰기: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "AlertViewModel")

    init(
        familyId: String,
        childUid: String?,
        observe: @escaping Observe = EventRepository.observeEvents,
        markRead: @escaping MarkRead = EventRepository.markRead
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.observe = observe
        self.markRead = markRead
    }

    /// 빈 목록 자리의 문구. nil 이면 감춘다(`renderEmptyState`, :274-276).
    var 빈_목록_문구: String? {
        listLoad.emptyText(isEmpty: events.isEmpty, loaded: String(localized: "alert_empty"))
    }

    /// 탭을 처음 보일 때 구독한다(`onViewCreated` → `subscribe`, :116-150). 두 번째부터는 무시한다.
    /// 가족이 없는 갈래(:121-129)는 iOS 에 없다 — `GuardianRootView` 는 familyId 가 있어야 만들어진다.
    func 시작한다() {
        guard !시작했다, !닫혔다 else { return }
        시작했다 = true
        guard let childUid else {
            // :131-137 — 구독을 시작조차 못 하지만 "불러오는 중"에 가두지 않는다.
            listLoad = .loaded
            상태_줄 = String(localized: "map_no_child")
            return
        }
        listener = observe(familyId, childUid, { [weak self] docs, fromCache in
            Task { @MainActor in self?.스냅샷을_받았다(docs, fromCache: fromCache) }
        }, { [weak self] error in
            Task { @MainActor in self?.구독이_실패했다(error) }
        })
    }

    /// 보임이 바뀌었다(`setVisible`, :189-202). 같은 값이면 아무 일도 하지 않는다.
    func 보임이_바뀌었다(_ 보인다: Bool) {
        guard !닫혔다, 보이는가 != 보인다 else { return }
        보이는가 = 보인다
        if 보인다 {
            안_읽은_것을_거둔다()
        } else {
            // 다음에 열 때는 그 사이에 새로 온 것만 살구빛이어야 한다(:38-39).
            강조.removeAll()
        }
    }

    /// 화면이 사라진다(`onDestroyView`, :286-297).
    func 정리한다() {
        닫혔다 = true
        보이는가 = false
        listener?.remove()
        listener = nil
        읽음_쓰기?.cancel()
        읽음_쓰기 = nil
        읽음_쓰는_중 = false
        강조.removeAll()
    }

    private func 스냅샷을_받았다(_ docs: [EventDoc], fromCache: Bool) {
        guard !닫혔다 else { return }
        events = docs
        // 캐시본으로는 loaded 로 올리지 않는다 — 오프라인의 빈 목록은 "조용한 하루"가 아니다(:155-158).
        listLoad = ListLoad.after(fromCache: fromCache)
        // 보는 동안 새로 온 것도 그 자리에서 읽음이 된다(:159-161).
        if 보이는가 { 안_읽은_것을_거둔다() }
    }

    private func 구독이_실패했다(_ error: Error) {
        guard !닫혔다 else { return }
        listLoad = .failed
        상태_줄 = String(format: String(localized: "alert_error_format"), errorMessage(error))
    }

    /// 지금 안 읽은 것들을 강조에 넣고 서버에 읽음으로 적는다(:204-228).
    ///
    /// 쓰기가 실패해도 화면에는 아무 말도 하지 않는다. 부모가 한 일이 아니라 화면이 혼자 한 일이고, 대가는
    /// "다음에 열면 한 번 더 시도"뿐이다. 흔적은 로그에 남긴다.
    private func 안_읽은_것을_거둔다() {
        let ids = events.filter { !$0.read }.map(\.id)
        guard !ids.isEmpty else { return }
        강조.formUnion(ids)
        guard 읽음_쓰기 == nil else { return }   // 겹쳐 나가지 않게 하나로 묶는다(:64-65, :216)
        let familyId = familyId
        let markRead = markRead
        읽음_쓰는_중 = true
        읽음_쓰기 = Task { [weak self] in
            do {
                try await markRead(familyId, ids)
            } catch is CancellationError {
                // 정리한다() 가 취소했다.
            } catch {
                Self.logger.warning("읽음 표시 실패 — 다음에 다시 시도한다: \(String(describing: error), privacy: .public)")
            }
            guard let self, !self.닫혔다 else { return }
            self.읽음_쓰기 = nil
            self.읽음_쓰는_중 = false
        }
    }
}
```

- [ ] **Step 6: 화면**

`ios/KidCare/Guardian/AlertView.swift`:

```swift
import SwiftUI

/// 알림 탭. 정본은 `fragment_alert.xml`(위에서부터 카드 · 상태 한 줄 · 목록)과 `AlertFragment.renderList`(:270-277).
struct AlertView: View {
    let viewModel: AlertViewModel

    var body: some View {
        VStack(spacing: 0) {
            제약_카드
            if let 줄 = viewModel.상태_줄 {
                RuleStateLine(text: 줄)
            }
            ZStack {
                ScrollView {
                    // 줄마다 시각 표기를 그릴 때의 기기 시각. 안드로이드도 bind 할 때 한 번 읽는다(AlertAdapter.kt:101).
                    let now = Int64(Date().timeIntervalSince1970 * 1000)
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.events, id: \.id) { doc in
                            AlertRowView(doc: doc, 새것: viewModel.강조.contains(doc.id), nowMillis: now)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                // 스크롤한 글이 상태 표시줄 밑으로 비치지 않게(4단계 Task 4 보완 5209a6e 와 같은 처리).
                .clipped()

                if let 문구 = viewModel.빈_목록_문구 {
                    빈_목록(문구)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(KidCarePalette.paper)
    }

    /// 스위치 카드 자리(fragment_alert.xml:19-53). 스위치 대신 아이폰의 제약을 한 줄로 적는다(설계서 §4 ①).
    private var 제약_카드: some View {
        Text("ios_alert_open_app_hint")
            .font(.system(size: 13))
            .foregroundStyle(KidCarePalette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(KidCarePalette.paperFold, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    /// 빈 목록(fragment_alert.xml:83-116). 글자만 떠 있으면 화면의 8할이 빈 종이라 "고장인가"로 읽힌다.
    private func 빈_목록(_ 문구: String) -> some View {
        VStack(spacing: 0) {
            Image("Mascot3D")
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .opacity(0.9)
                .accessibilityHidden(true)
            Text(문구)
                .font(.system(size: 15))
                .foregroundStyle(KidCarePalette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

/// 알림 한 줄. 정본은 `item_alert.xml` 과 `AlertAdapter.Holder.bind`(:51-74). 누를 것이 없다 — 읽는 목록이다.
struct AlertRowView: View {
    let doc: EventDoc
    /// "이번에 보이기 시작했을 때 안 읽었던 줄". 문서의 read 를 직접 보지 않는다(:25-28).
    let 새것: Bool
    let nowMillis: Int64

    var body: some View {
        let look = AlertText.look(doc)
        HStack(spacing: 12) {
            Image(systemName: look.systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(look.strong)
                .frame(width: 40, height: 40)
                .background(look.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AlertText.line(doc, nowMillis: nowMillis))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)
                // detail 이 비면 줄 자체를 없앤다 — 빈 줄이 남으면 줄 높이만 들쭉날쭉해진다(:61-65).
                if !doc.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(doc.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(새것 ? KidCarePalette.apricotSoft : KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(KidCarePalette.lineSoft, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }
}
```

- [ ] **Step 7: 탭에 붙이고 자리표시를 지운다**

`ios/KidCare/Guardian/GuardianRootView.swift`(5단계 Task 3 이 끝난 모양):

1. `placeViewModel` 아래에 더한다:

```swift
    /// 알림 탭 뷰모델. 지도·관리·예약·장소와 같은 수명이다. 보임은 이 뷰가 탭 선택과 앱 활성으로 알려준다.
    @State private var alertViewModel: AlertViewModel
```

2. `init` 끝에 더한다:

```swift
        _alertViewModel = State(initialValue: AlertViewModel(
            familyId: familyId,
            childUid: childUid,
            // 실기기 확인에서는 진짜 가족에 읽음을 쓰지 않는다(판정 기록 10).
            markRead: ReadOnlyCheck.isOn ? { _, _ in } : EventRepository.markRead
        ))
```

3. `TabPlaceholderView(tab: .alert)` 로 시작하는 세 줄을 바꾼다:

```swift
                AlertView(viewModel: alertViewModel)
                    // 처음 보일 때 구독(AlertFragment.onViewCreated :116), 그리고 보임을 맞춘다(onResume :177-180).
                    .onAppear {
                        alertViewModel.시작한다()
                        알림_보임을_맞춘다()
                    }
                    .tabItem { Label(GuardianTab.alert.title, systemImage: GuardianTab.alert.systemImage) }
                    .tag(GuardianTab.alert)
```

4. 5단계가 둔 `.onChange(of: scenePhase) { _, phase in` 블록의 **첫 줄**(`guard phase == .active` 보다 앞)에 `알림_보임을_맞춘다(phase: phase)` 를 넣는다. 백그라운드로 내려갈 때도 불려야 한다(`onPause` :182-187). 그 블록 바로 아래에 더한다:

```swift
        // 탭 전환은 안드로이드 onHiddenChanged(:172-175) 자리다.
        .onChange(of: selectedTab) { _, _ in 알림_보임을_맞춘다() }
```

5. `.onDisappear` 안에 `alertViewModel.정리한다()` 를 더한다.
6. `body` 아래(파일의 `TabPlaceholderView` 자리)에 더한다. 그리고 `private struct TabPlaceholderView` 를 통째로 지운다.

```swift
    /// 알림 목록이 지금 부모 눈앞에 있는가 — 알림 탭이 골라져 있고 앱이 활성일 때뿐이다(`setVisible` :189-202).
    /// `phase` 는 onChange 가 넘기는 새 값이다(그 순간 환경값이 아직 옛 값일 수 있어 인자를 먼저 본다).
    private func 알림_보임을_맞춘다(phase: ScenePhase? = nil) {
        alertViewModel.보임이_바뀌었다(selectedTab == .alert && (phase ?? scenePhase) == .active)
    }
```

7. `ios_tab_not_ready_body` 를 원본에서 지우고 다시 생성한다(아이폰 전용 키이고 안드로이드는 쓰지 않는다 — `grep -rn ios_tab_not_ready_body app` 이 비어 있어야 한다):

```bash
cd /Users/com/work/KidCare
grep -rn "ios_tab_not_ready_body" app ios/KidCare --include=*.kt --include=*.xml --include=*.swift   # 비어 있어야 한다
python3 - <<'EOF'
import json
for lang in ('ko', 'en'):
    path = f'i18n/{lang}.json'
    d = json.load(open(path, encoding='utf-8'))
    del d['ios_tab_not_ready_body']
    open(path, 'w', encoding='utf-8').write(json.dumps(dict(sorted(d.items())), indent=2, ensure_ascii=False) + '\n')
EOF
python3 tools/ios-strings.py --write-gaps    # 번역 대기 언어마다 24 → 23
git diff tools/i18n-untranslated.json          # 12개 언어에서 ios_tab_not_ready_body 한 줄씩만 빠져야 한다
```

- [ ] **Step 8: 통과 확인**

에뮬레이터를 띄운 채로 실행한다.

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS. 새로 들어가는 테스트는 `EventDocumentsTests` 3개, `AlertTextTests` 5개, `AlertViewModelTests` 10개, `EventRepositoryTests` 4개다.

```bash
grep -rn "TabPlaceholderView\|ios_tab_not_ready_body" ios/KidCare   # 비어 있어야 한다(xcstrings 포함)
python3 tools/ios-strings.py --check; echo $?                        # 0
```

- [ ] **Step 9: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Core/Documents.swift ios/KidCare/Core/EventRepository.swift \
  ios/KidCare/Guardian/ReadOnlyCheck.swift ios/KidCare/Guardian/AlertText.swift ios/KidCare/Guardian/AlertViewModel.swift \
  ios/KidCare/Guardian/AlertView.swift ios/KidCare/Guardian/GuardianRootView.swift \
  i18n/ko.json i18n/en.json tools/i18n-untranslated.json ios/KidCare/Localizable.xcstrings \
  ios/KidCareTests/EventDocumentsTests.swift ios/KidCareTests/AlertTextTests.swift \
  ios/KidCareTests/AlertViewModelTests.swift ios/KidCareTests/EventRepositoryTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 6단계 Task 2: 알림 탭 — 연 순간의 안 읽은 사건을 살구빛으로 붙들고, 서버에는 read 한 필드만 쓴다"
```

---
### Task 3: 초대 세션과 번호 화면 — 안드로이드 초대 갈래 그대로, 에뮬레이터에서만 쓴다

**끝나면 `InviteSession` 이 안드로이드 `GuardianPairingActivity` 의 초대 갈래와 같은 순서로 일한다.** 순서는 기준 멤버 읽기 → 번호 발급 → 새 멤버 감시다. 20초 시간 초과, '다시 시도', '새 번호 받기'(이전 코드 정리), 역할별 제목과 안내, "N분 뒤에 만료"도 같다. `GuardianInviteView` 가 그 상태를 `activity_guardian_pairing.xml` 모양으로 그리고, 왼쪽 위에 뒤로 버튼이 있다. 에뮬레이터 테스트에서 아이가 그 번호로 들어오면 세션이 **한 번** 넘어간다. 이 화면을 여는 곳은 Task 4 가 단다.

**Files:**
- Modify: `ios/KidCare/Core/FamilyRepository.swift`(`FamilyMember`, `observeMembers`, `fetchMembers`)
- Create: `ios/KidCare/Onboarding/InviteSession.swift`, `ios/KidCare/Onboarding/GuardianInviteView.swift`
- Modify: `ios/KidCare/Onboarding/InviteCodeView.swift:12-15`(주석만)
- Test: `ios/KidCareTests/InviteSessionTests.swift`, `FamilyMembersTests.swift`(에뮬레이터), `InviteFlowTests.swift`(에뮬레이터)

**Interfaces:**
- Consumes: 1단계 `FamilyRepository.createInvite(familyId:role:previousCode:)`·`InviteCodeInfo`·`MemberRole`·`AuthGateway`, 4단계 `firstToFinish(timeoutMillis:sleep:operation:)`·`errorMessage(_:)`, `KidCarePalette.sky·skySoft·ink·inkSoft·paper`, 테스트 도구
- Produces:
  - `struct FamilyMember: Equatable, Sendable { let uid: String; let role: String; let displayName: String; let joinedAt: Int64 }`
  - `FamilyRepository.observeMembers(familyId:onChange:onError:) -> ListenerRegistration`, `FamilyRepository.fetchMembers(familyId:) async throws -> [FamilyMember]`
  - `@MainActor @Observable final class InviteSession { typealias Create, Fetch, Observe; nonisolated static let setupTimeoutMillis; let role; 코드, 만료_분, 진행중, 안내, 버튼_문구, 버튼_활성, 제목, 만료_문구; init(familyId:role:create:fetch:observe:deviceNow:sleep:onJoined:); 시작한다(), 버튼을_눌렀다(), 정리한다() }`
  - `struct GuardianInviteView: View { let session: InviteSession; let onClose: () -> Void }`

**정본:** `onboarding/GuardianPairingActivity.kt` 전체(253줄). 초대 갈래는 `:64-70`(역할·되돌아가기), `:74-79`(버튼 하나가 '다시 시도'와 '새 번호'를 겸함), `:104-160`(startPairing), `:163-168`(showSetupFailure), `:171-194`(refreshCode), `:197-215`(showCode, 만료 분 올림 `:203-205`), `:217-230`(goToMain, `navigated` :46-50), `:232-240`(renderInviteRole), `:249-251`(상수 `SETUP_TIMEOUT_MILLIS = 20_000L`)이다. 저장소는 `core/FamilyRepository.kt:245-278`(observeMembers·fetchMembers), `:522-527`(FamilyMember). 레이아웃은 `res/layout/activity_guardian_pairing.xml` 전체다.

치수는 다음과 같다.
- 바깥 안쪽 32
- 제목 24 medium 가운데
- 번호 카드: 위 24, 바탕 `colorPrimaryContainer`=`sky_soft`, 모서리 ExtraLarge 28(`themes.xml:94-97`), 테두리 0
- 번호: DisplayMedium 34 medium, 자간 0.25em(= 8.5pt), `colorOnPrimaryContainer`=`ink`, 안쪽 16×28, 비었을 때 `pairing_code_placeholder`
- 안내: 위 24, 15 `ink_soft` 가운데
- 만료: 위 8, 13 `ink_soft`
- 진행 표시: 위 28
- 버튼: 위 24, `Widget.KidCare.Button.Tonal`(바탕 `sky_soft`, 글자 `sky`, 최소 높이 50, 모서리 18, LabelLarge 15 medium)

'역할 다시 고르기'는 뺀다(판정 기록 8).

**규칙 확인.** 새로 만드는 쓰기는 없다. `createInvite` 는 1단계 그대로다(`firestore.rules:39-55` 의 첫 갈래: 보호자 멤버, `createdByUid` 본인, `role` 이 둘 중 하나, 만료가 미래). `previousCode` 삭제도 그대로다(`:69`). 읽기는 `members` 목록(`:99` `memberOf`)이다.

- [ ] **Step 1: 테스트를 먼저 쓴다**

`ios/KidCareTests/InviteSessionTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 정본은 `GuardianPairingActivity.kt` 의 초대 갈래. 줄 번호는 테스트 이름에 적는다.
@MainActor
struct InviteSessionTests {

    final class 가짜_멤버_구독: Sendable {
        let onChange = TestCallbackBox<([FamilyMember]) -> Void>()
        let onError = TestCallbackBox<(Error) -> Void>()
        let registration = TestListenerRegistration()
        func 보낸다(_ members: [FamilyMember]) { onChange.value?(members) }
    }

    actor 발급_기록 {
        private(set) var 이전_코드들: [String?] = []
        func 기록(_ previous: String?) { 이전_코드들.append(previous) }
    }

    @MainActor final class 합류_기록 {
        var 멤버들: [FamilyMember] = []
    }

    private static let 지금 = Int64(1_789_279_920_000)
    private static let 오래_잔다: @Sendable (Int64) async -> Void = { _ in try? await Task.sleep(nanoseconds: 60_000_000_000) }

    private func 멤버(_ uid: String, _ role: String) -> FamilyMember {
        FamilyMember(uid: uid, role: role, displayName: "", joinedAt: 1)
    }

    /// 기본 가짜: 기준 멤버 둘(g1 보호자, c1 아이), 첫 발급은 ABC234, 새 번호는 XYZ789, 만료는 10분 뒤.
    private func 만든다(
        role: MemberRole = .child,
        expiresIn: Int64 = 600_000,
        기록: 발급_기록 = 발급_기록(),
        구독: 가짜_멤버_구독 = 가짜_멤버_구독(),
        합류: 합류_기록 = 합류_기록(),
        sleep: @escaping @Sendable (Int64) async -> Void = InviteSessionTests.오래_잔다,
        create: InviteSession.Create? = nil
    ) -> InviteSession {
        let now = Self.지금
        let 기준 = [멤버("g1", "guardian"), 멤버("c1", "child")]
        return InviteSession(
            familyId: "fam",
            role: role,
            create: create ?? { _, role, previous in
                await 기록.기록(previous)
                return InviteCodeInfo(code: previous == nil ? "ABC234" : "XYZ789", expiresAt: now + expiresIn, role: role)
            },
            fetch: { _ in 기준 },
            observe: { _, onChange, onError in
                구독.onChange.set(onChange)
                구독.onError.set(onError)
                return 구독.registration
            },
            deviceNow: { now },
            sleep: sleep,
            onJoined: { 합류.멤버들.append($0) }
        )
    }

    @Test("아이 초대: 번호·안내·만료·'새 번호 받기'가 뜨고 진행 표시가 꺼진다(:197-215, :232-240)")
    func 아이_초대_발급() async {
        let s = 만든다(role: .child)
        #expect(s.제목 == String(localized: "pairing_guardian_title"))
        s.시작한다()
        await eventually { s.코드 == "ABC234" }
        #expect(s.안내 == String(localized: "pairing_guardian_hint"))
        #expect(s.만료_문구 == "이 번호는 10분 뒤에 만료돼요")
        #expect(s.버튼_문구 == "새 번호 받기")
        #expect(s.버튼_활성)
        #expect(!s.진행중)
    }

    @Test("보호자 초대는 다른 보호자용 제목과 안내를 쓴다(:232-240)")
    func 보호자_초대_문구() async {
        let s = 만든다(role: .guardian)
        #expect(s.제목 == String(localized: "pairing_guardian_invite_guardian_title"))
        #expect(s.안내 == String(localized: "pairing_guardian_invite_guardian_hint"))
        s.시작한다()
        await eventually { s.코드 != nil }
        #expect(s.안내 == String(localized: "pairing_guardian_invite_guardian_hint"))
    }

    @Test("만료 분은 기기 시계로 올림하고 최소 1분(:203-205)")
    func 만료_분() async {
        for (expiresIn, 분) in [(Int64(1), Int64(1)), (-5_000, 1), (600_001, 11)] {
            let s = 만든다(expiresIn: expiresIn)
            s.시작한다()
            await eventually { s.코드 != nil }
            #expect(s.만료_분 == 분, "\(expiresIn)")
        }
    }

    @Test("기준에 없던 같은 역할 멤버가 들어오면 한 번만 넘어가고 감시를 뗀다(:123-130, :46-50, :217-230)")
    func 합류는_한_번() async {
        let 구독 = 가짜_멤버_구독(), 합류 = 합류_기록()
        let s = 만든다(role: .child, 구독: 구독, 합류: 합류)
        s.시작한다()
        await eventually { s.코드 != nil && 구독.onChange.value != nil }
        구독.보낸다([멤버("g1", "guardian"), 멤버("c1", "child")])
        구독.보낸다([멤버("g1", "guardian"), 멤버("c1", "child"), 멤버("g2", "guardian")])
        구독.보낸다([멤버("g1", "guardian"), 멤버("c1", "child"), 멤버("g2", "guardian"), 멤버("c2", "child")])
        구독.보낸다([멤버("c2", "child"), 멤버("c3", "child")])
        await eventually { !합류.멤버들.isEmpty }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(합류.멤버들.map(\.uid) == ["c2"])
        #expect(구독.registration.removed)
    }

    @Test("20초 안에 발급이 안 끝나면 pairing_offline 과 '다시 시도', 누르면 처음부터 다시 한다(:133-146, :163-168, :77-79)")
    func 시간_초과() async {
        let 기록 = 발급_기록(), 첫_발급 = TestGate(), 발급_횟수 = TestCounter(), 잠_횟수 = TestCounter()
        let now = Self.지금
        let s = 만든다(
            sleep: { _ in
                if await 잠_횟수.next() == 1 { return }                        // 첫 판은 곧장 시간 초과
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            },
            create: { _, role, previous in
                await 기록.기록(previous)
                if await 발급_횟수.next() == 1 { await 첫_발급.wait() }        // 첫 발급은 매달린다
                return InviteCodeInfo(code: "QWE345", expiresAt: now + 600_000, role: role)
            }
        )
        s.시작한다()
        await eventually { s.버튼_문구 == "다시 시도" }
        #expect(s.안내 == String(localized: "pairing_offline"))
        #expect(s.버튼_활성)
        #expect(!s.진행중)
        #expect(s.코드 == nil)
        s.버튼을_눌렀다()
        await eventually { s.코드 == "QWE345" }
        #expect(await 기록.이전_코드들 == [nil, nil])
        await 첫_발급.open()
    }

    @Test("발급 실패는 pairing_failed 에 errorMessage 를 끼운다(:147-159)")
    func 발급_실패() async {
        let error = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let s = 만든다(create: { _, _, _ in throw error })
        s.시작한다()
        await eventually { s.버튼_문구 == "다시 시도" }
        #expect(s.안내 == String(format: String(localized: "pairing_failed"), errorMessage(error)))
    }

    @Test("'새 번호 받기'는 이전 코드를 넘겨 새로 받고, 기준 멤버와 감시는 그대로 둔다(:171-194)")
    func 새_번호() async {
        let 기록 = 발급_기록(), 구독 = 가짜_멤버_구독()
        let s = 만든다(기록: 기록, 구독: 구독)
        s.시작한다()
        await eventually { s.코드 == "ABC234" && s.버튼_활성 }
        s.버튼을_눌렀다()
        await eventually { s.코드 == "XYZ789" && s.버튼_활성 }
        #expect(await 기록.이전_코드들 == [nil, "ABC234"])
        #expect(!구독.registration.removed)
    }

    @Test("감시 오류는 안내 자리에 pairing_failed 한 줄, 번호는 그대로(:131-133)")
    func 감시_오류() async {
        let 구독 = 가짜_멤버_구독()
        let s = 만든다(구독: 구독)
        s.시작한다()
        await eventually { s.코드 != nil && 구독.onError.value != nil }
        let error = NSError(domain: "test", code: 8, userInfo: [NSLocalizedDescriptionKey: "listen"])
        구독.onError.value?(error)
        await eventually { s.안내 == String(format: String(localized: "pairing_failed"), errorMessage(error)) }
        #expect(s.코드 == "ABC234")
    }

    @Test("정리하면 감시를 떼고, 늦게 온 합류는 무시한다(:241-244)")
    func 정리() async {
        let 구독 = 가짜_멤버_구독(), 합류 = 합류_기록()
        let s = 만든다(구독: 구독, 합류: 합류)
        s.시작한다()
        await eventually { 구독.onChange.value != nil }
        s.정리한다()
        #expect(구독.registration.removed)
        구독.보낸다([멤버("c9", "child")])
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(합류.멤버들.isEmpty)
    }
}
```

`ios/KidCareTests/FamilyMembersTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 멤버 목록 읽기를 에뮬레이터로 확인한다(firestore.rules:99 `memberOf`). 정본은 `FamilyRepository.kt:245-278`.
@Suite(.serialized)
struct FamilyMembersTests {

    init() async { await EmulatorHarness.start() }

    actor 목록 {
        private(set) var 마지막: [FamilyMember] = []
        func 기록(_ m: [FamilyMember]) { 마지막 = m }
    }

    @Test("한 번 읽기와 구독이 같은 멤버(역할·이름·가입 시각)를 준다")
    func 멤버를_읽는다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)

        let fetched = try await FamilyRepository.fetchMembers(familyId: familyId)
        #expect(Set(fetched.map(\.uid)) == [guardianUid, child.uid])
        let 아이 = try #require(fetched.first { $0.uid == child.uid })
        #expect(아이.role == "child")
        #expect(아이.displayName == "아이")
        #expect(아이.joinedAt > 0)
        #expect(fetched.first { $0.uid == guardianUid }?.displayName == "보호자")   // Task 1 판정 기록 4

        let 기록 = 목록()
        let listener = FamilyRepository.observeMembers(
            familyId: familyId,
            onChange: { members in Task { await 기록.기록(members) } },
            onError: { error in Issue.record("구독 실패: \(error)") }
        )
        defer { listener.remove() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, await 기록.마지막.count < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(Set(await 기록.마지막) == Set(fetched))
    }
}
```

`FamilyMember` 를 `Set` 에 넣으려면 `Hashable` 이어야 한다. 그래서 Step 3 에서 `Equatable` 대신 `Hashable` 로 선언한다.

`ios/KidCareTests/InviteFlowTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 초대 한 판을 진짜 저장소 함수로 에뮬레이터에서 끝까지 돌린다. **초대 발급은 진짜 가족에 쓰므로 이 테스트가
/// 확인의 전부다** — 실기기 확인(Task 5)은 초대를 만들지 않는다.
@Suite(.serialized)
@MainActor
struct InviteFlowTests {

    init() async { await EmulatorHarness.start() }

    @MainActor final class 합류_기록 { var 멤버들: [FamilyMember] = [] }

    @Test("아이 초대: 번호를 받고, 그 번호로 새 아이가 들어오면 그 아이로 한 번 넘어간다")
    func 아이가_들어온다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let 합류 = 합류_기록()
        let session = InviteSession(familyId: familyId, role: .child, onJoined: { 합류.멤버들.append($0) })
        defer { session.정리한다() }

        session.시작한다()
        await eventually(timeoutSeconds: 10) { session.코드 != nil }
        let code = try #require(session.코드)

        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: code)
        await eventually(timeoutSeconds: 10) { !합류.멤버들.isEmpty }
        #expect(합류.멤버들.map(\.uid) == [child.uid])
    }

    @Test("'새 번호 받기'는 새 코드를 만들고 이전 코드 문서를 지운다(FamilyRepository.createInvite previousCode)")
    func 새_번호는_옛_코드를_지운다() async throws {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let session = InviteSession(familyId: familyId, role: .guardian, onJoined: { _ in })
        defer { session.정리한다() }

        session.시작한다()
        await eventually(timeoutSeconds: 10) { session.코드 != nil && session.버튼_활성 }
        let first = try #require(session.코드)
        session.버튼을_눌렀다()
        await eventually(timeoutSeconds: 10) { session.코드 != first && session.버튼_활성 }
        let old = try await Firestore.firestore().collection("inviteCodes").document(first).getDocument(source: .server)
        #expect(!old.exists)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/InviteSessionTests`
Expected: 컴파일 실패("cannot find 'InviteSession' in scope").

- [ ] **Step 3: 멤버 읽기**

`ios/KidCare/Core/FamilyRepository.swift` 의 파일 위쪽 `struct JoinResult` 아래에 더한다:

```swift
/// 가족 멤버 한 명. 정본은 `FamilyRepository.kt:522-527`.
///
/// `role` 을 `MemberRole` 이 아니라 문자열로 두는 이유: 선택기는 "child"/"guardian" 만 걸러 쓰고, 모르는 역할
/// 문서가 하나 섞여도 목록 전체가 깨지면 안 된다(`MemberDoc(_:)` 는 모르는 역할이면 nil 을 돌려준다).
struct FamilyMember: Hashable, Sendable {
    let uid: String
    let role: String
    let displayName: String
    let joinedAt: Int64
}
```

`enum FamilyRepository` 본문 끝에 더한다:

```swift
    /// 보호자·자녀 전체 멤버를 감시한다. 선택기와 초대 완료 판정이 쓴다(`FamilyRepository.kt:245-267`).
    /// 붙인 리스너는 부르는 쪽이 사라질 때 반드시 remove 한다.
    static func observeMembers(
        familyId: String,
        onChange: @escaping ([FamilyMember]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families").document(familyId).collection("members")
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                onChange(snapshot?.documents.map(familyMember) ?? [])
            }
    }

    /// 한 번 읽는다. 초대 화면이 "이미 있던 멤버"를 기준으로 삼는다(`:269-278`, `GuardianPairingActivity.kt:121`).
    static func fetchMembers(familyId: String) async throws -> [FamilyMember] {
        try await db.collection("families").document(familyId).collection("members")
            .getDocuments().documents.map(familyMember)
    }

    private static func familyMember(_ doc: QueryDocumentSnapshot) -> FamilyMember {
        let data = doc.data()
        return FamilyMember(
            uid: doc.documentID,
            role: data["role"] as? String ?? "",
            displayName: data["displayName"] as? String ?? "",
            joinedAt: (data["joinedAt"] as? NSNumber)?.int64Value ?? 0
        )
    }
```

- [ ] **Step 4: 초대 세션**

`ios/KidCare/Onboarding/InviteSession.swift`:

```swift
import FirebaseFirestore
import Foundation
import Observation
import os

/// 본 화면에서 여는 초대 한 판 — 기준 멤버 읽기 → 번호 발급 → 새 멤버 감시. 정본은 `GuardianPairingActivity`
/// 의 초대 갈래(`EXTRA_INVITE_ROLE`·`EXTRA_RETURN_TO_MAIN`, :64-70). 가족을 새로 만드는 갈래는 1단계
/// `NewFamilySession` 이 옮겼다.
///
/// **이 세션은 화면이 아니라 `ChildSelectorModel` 이 소유한다.** 커버·push 의 내용 뷰는 SwiftUI 가 다시 마운트할
/// 수 있어서, 일을 뷰가 들고 있으면 한 번의 초대에 번호가 두 번 발급된다(`NewFamilySession` 타입 주석의 실측).
///
/// 페어링의 끝은 "번호를 보여줬다"가 아니라 "새 멤버가 실제로 들어왔다"다(:31-34). 들어오면 `onJoined` 를
/// 딱 한 번 부른다.
@MainActor
@Observable
final class InviteSession {

    typealias Create = @Sendable (_ familyId: String, _ role: MemberRole, _ previousCode: String?) async throws -> InviteCodeInfo
    typealias Fetch = @Sendable (_ familyId: String) async throws -> [FamilyMember]
    typealias Observe = @Sendable (
        _ familyId: String, _ onChange: @escaping ([FamilyMember]) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration

    /// `SETUP_TIMEOUT_MILLIS = 20_000L`(:251). 오프라인이면 쓰기가 서버 확인 없이 걸려 무한 스피너가 된다(:112-113).
    nonisolated static let setupTimeoutMillis: Int64 = 20_000

    let role: MemberRole
    private(set) var 코드: String?
    /// 발급 순간의 남은 분. 실시간 카운트다운이 아니다(:196, activity_guardian_pairing.xml:61-63).
    private(set) var 만료_분: Int64?
    private(set) var 진행중 = true
    /// `hint_text` 자리 — 역할별 안내, 또는 실패 문구(:131-132, :163-168).
    private(set) var 안내: String
    /// 버튼 하나가 '새 번호 받기'와 '다시 시도'를 겸한다(:74-79, :166).
    private(set) var 버튼_문구 = String(localized: "pairing_new_code_button")
    private(set) var 버튼_활성 = false

    private let familyId: String
    private let create: Create
    private let fetch: Fetch
    private let observe: Observe
    private let deviceNow: @Sendable () -> Int64
    private let sleep: @Sendable (Int64) async -> Void
    private let onJoined: @MainActor (FamilyMember) -> Void

    /// 발급 전에 이미 있던 멤버. 이 밖의 같은 역할 멤버가 "새로 들어온 사람"이다(:121, :126-127).
    private var 기준_멤버: Set<String> = []
    private var listener: ListenerRegistration?
    private var 작업: Task<Void, Never>?
    private var 닫혔다 = false
    /// 스냅샷이 캐시→서버로 두 번 와도 한 번만 넘어간다(`navigated`, :46-50).
    private var 넘어갔다 = false

    private struct 준비됨: Sendable {
        let baseline: Set<String>
        let info: InviteCodeInfo
    }

    init(
        familyId: String,
        role: MemberRole,
        create: @escaping Create = FamilyRepository.createInvite,
        fetch: @escaping Fetch = FamilyRepository.fetchMembers,
        observe: @escaping Observe = FamilyRepository.observeMembers,
        deviceNow: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        sleep: @escaping @Sendable (Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        },
        onJoined: @escaping @MainActor (FamilyMember) -> Void
    ) {
        self.familyId = familyId
        self.role = role
        self.create = create
        self.fetch = fetch
        self.observe = observe
        self.deviceNow = deviceNow
        self.sleep = sleep
        self.onJoined = onJoined
        안내 = Self.역할_안내(role)
    }

    /// 제목(:232-236).
    var 제목: String {
        role == .guardian
            ? String(localized: "pairing_guardian_invite_guardian_title")
            : String(localized: "pairing_guardian_title")
    }

    var 만료_문구: String? {
        만료_분.map { String(format: String(localized: "pairing_code_expiry_format"), Int($0)) }
    }

    /// 화면이 보일 때 부른다(`onCreate` → `startPairing`, :103). 이미 번호가 있거나 진행 중이면 아무 일도 하지 않는다.
    func 시작한다() {
        guard !닫혔다, 작업 == nil, 코드 == nil else { return }
        listener?.remove()
        listener = nil
        버튼_활성 = false
        버튼_문구 = String(localized: "pairing_new_code_button")
        진행중 = true
        안내 = Self.역할_안내(role)
        let familyId = familyId, role = role, create = create, fetch = fetch
        작업 = Task { [weak self] in
            guard let self else { return }
            do {
                let 결과 = try await firstToFinish(timeoutMillis: Self.setupTimeoutMillis, sleep: self.sleep) {
                    let baseline = Set(try await fetch(familyId).map(\.uid))
                    let info = try await create(familyId, role, nil)
                    return 준비됨(baseline: baseline, info: info)
                }
                guard !self.닫혔다 else { return }
                if let 결과 {
                    self.기준_멤버 = 결과.baseline
                    self.번호를_보인다(결과.info)
                    self.듣는다()
                } else {
                    self.실패를_보인다(String(localized: "pairing_offline"))   // withTimeout (:133-146)
                }
            } catch is CancellationError {
                // 정리한다() 가 취소했다 — 실패로 적지 않는다(:148-151).
            } catch {
                guard !self.닫혔다 else { return }
                self.실패를_보인다(String(format: String(localized: "pairing_failed"), errorMessage(error)))
            }
            self.작업 = nil
        }
    }

    /// 버튼(:77-79). 번호가 아직 없으면 처음부터, 있으면 새 번호.
    func 버튼을_눌렀다() {
        if 코드 == nil { 시작한다() } else { 새_번호를_받는다() }
    }

    /// 화면이 사라진다(`onDestroy`, :241-244).
    func 정리한다() {
        닫혔다 = true
        listener?.remove()
        listener = nil
        작업?.cancel()
        작업 = nil
    }

    /// "새 번호 받기": 만료 전이어도 새로 발급해 이전 코드를 죽인다(:170-194). 기준 멤버와 감시는 그대로다.
    private func 새_번호를_받는다() {
        guard !닫혔다, 작업 == nil else { return }
        버튼_활성 = false
        진행중 = true
        let familyId = familyId, role = role, create = create, previous = 코드
        작업 = Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await firstToFinish(timeoutMillis: Self.setupTimeoutMillis, sleep: self.sleep) {
                    try await create(familyId, role, previous)
                }
                if !self.닫혔다 {
                    if let info {
                        self.번호를_보인다(info)
                    } else {
                        self.진행중 = false
                        self.안내 = String(localized: "pairing_offline")
                    }
                }
            } catch is CancellationError {
            } catch {
                if !self.닫혔다 {
                    self.진행중 = false
                    self.안내 = String(format: String(localized: "pairing_failed"), errorMessage(error))
                }
            }
            if !self.닫혔다 { self.버튼_활성 = true }   // finally (:192-194)
            self.작업 = nil
        }
    }

    /// `showCode`(:197-215). 번호가 떴으면 기다리는 상태라 진행 표시를 끈다 — 아이가 언제 폰을 들지는 모른다.
    private func 번호를_보인다(_ info: InviteCodeInfo) {
        코드 = info.code
        버튼_문구 = String(localized: "pairing_new_code_button")
        만료_분 = max(1, (info.expiresAt - deviceNow() + 59_999) / 60_000)
        안내 = Self.역할_안내(role)
        버튼_활성 = true
        진행중 = false
    }

    /// `showSetupFailure`(:163-168). 같은 화면에서 다시 시도할 수 있게 버튼을 켠다.
    private func 실패를_보인다(_ message: String) {
        진행중 = false
        안내 = message
        버튼_문구 = String(localized: "router_retry")
        버튼_활성 = true
    }

    private func 듣는다() {
        guard !닫혔다, listener == nil else { return }
        listener = observe(familyId, { [weak self] members in
            Task { @MainActor in self?.멤버가_바뀌었다(members) }
        }, { [weak self] error in
            Task { @MainActor in
                guard let self, !self.닫혔다 else { return }
                // 번호는 그대로 둔다 — 아직 유효한 번호를 오류로 덮지 않는다(:131-133 은 hint 자리만 바꾼다).
                self.안내 = String(format: String(localized: "pairing_failed"), errorMessage(error))
            }
        })
    }

    private func 멤버가_바뀌었다(_ members: [FamilyMember]) {
        guard !닫혔다, !넘어갔다 else { return }
        guard let joined = members.first(where: { $0.role == role.rawValue && !기준_멤버.contains($0.uid) }) else { return }
        넘어갔다 = true
        listener?.remove()
        listener = nil
        onJoined(joined)
    }

    private static func 역할_안내(_ role: MemberRole) -> String {
        role == .guardian
            ? String(localized: "pairing_guardian_invite_guardian_hint")
            : String(localized: "pairing_guardian_hint")
    }
}
```

`시작한다` 의 `catch` 두 갈래 뒤 `self.작업 = nil` 은 `guard !self.닫혔다 else { return }` 로 먼저 빠져나간 경우에는 돌지 않는다. 그래도 괜찮다. 닫힌 세션은 다시 시작하지 않는다.

- [ ] **Step 5: 번호 화면**

`ios/KidCare/Onboarding/GuardianInviteView.swift`:

```swift
import SwiftUI

/// 본 화면에서 여는 초대 번호 화면. 정본은 `activity_guardian_pairing.xml` 과 `GuardianPairingActivity` 의 초대 갈래.
///
/// 부모가 하는 일은 여섯 글자를 소리 내어 읽어주는 것 하나다 — 번호를 카드 한 장에 크게 얹는다(XML 머리 주석).
/// '역할 다시 고르기'는 두지 않는다. 본 화면에서 누르면 이 폰의 가족 연결을 지우는 버튼이라 뒤로 버튼이 나가는
/// 길을 대신한다(계획서 판정 기록 8). 커버라 시스템 뒤로 버튼이 없으므로 왼쪽 위에 직접 둔다.
struct GuardianInviteView: View {
    let session: InviteSession
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(session.제목)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)
                    .multilineTextAlignment(.center)

                // 코드가 없을 때도 자리가 쪼그라들지 않게 자리표시자를 둔다(XML :34-36).
                Text(session.코드 ?? String(localized: "pairing_code_placeholder"))
                    .font(.system(size: 34, weight: .medium))
                    .tracking(34 * 0.25)
                    .foregroundStyle(KidCarePalette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 28)
                    .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.top, 24)

                Text(session.안내)
                    .font(.system(size: 15))
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                if let 만료 = session.만료_문구 {
                    Text(만료)
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.top, 8)
                }

                if session.진행중 {
                    ProgressView().padding(.top, 28)
                }

                Button { session.버튼을_눌렀다() } label: {
                    Text(session.버튼_문구)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(KidCarePalette.sky)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 50)
                        .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!session.버튼_활성)
                .opacity(session.버튼_활성 ? 1 : 0.5)
                .padding(.top, 24)

                Spacer(minLength: 0)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KidCarePalette.paper)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // VoiceOver 는 이 기호를 시스템 이름("뒤로")으로 읽는다 — 새 문구 키가 필요 없다.
                    Button(action: onClose) {
                        Image(systemName: "chevron.backward").font(.system(size: 17, weight: .semibold))
                    }
                    .tint(KidCarePalette.sky)
                }
            }
        }
        .task { session.시작한다() }
    }
}
```

`ios/KidCare/Onboarding/InviteCodeView.swift:12-15` 의 주석을 바꾼다:

```swift
        /// 이미 있는 가족에 아이나 다른 보호자를 부르는 갈래는 이 화면이 아니라 `GuardianInviteView` +
        /// `InviteSession` 이다(6단계). 소유자가 온보딩(`RoleSelectView`)이 아니라 본 화면의 선택기이고,
        /// 안드로이드도 그 갈래만 따로 그린다(`GuardianPairingActivity.renderInviteRole`).
```

- [ ] **Step 6: 통과 확인**

에뮬레이터를 띄운 채로 실행한다.

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS. 새로 들어가는 테스트는 `InviteSessionTests` 9개, `FamilyMembersTests` 1개, `InviteFlowTests` 2개다.

- [ ] **Step 7: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Core/FamilyRepository.swift ios/KidCare/Onboarding/InviteSession.swift ios/KidCare/Onboarding/GuardianInviteView.swift \
  ios/KidCare/Onboarding/InviteCodeView.swift ios/KidCareTests/InviteSessionTests.swift ios/KidCareTests/FamilyMembersTests.swift \
  ios/KidCareTests/InviteFlowTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 6단계 Task 3: 초대 세션과 번호 화면 — 기준 멤버 밖의 새 멤버가 들어올 때 한 번만 넘어간다"
```

---
### Task 4: 아이 선택기 — 선택기 줄, 지도 카드의 같은 메뉴, 초대 두 줄, 지구본

**끝나면 지도 탭이 아닌 탭 위에 안드로이드와 같은 선택기 줄이 뜬다.** 줄에는 "민준 보는 중 ▾"와 지구본 버튼이 있다. 지도 탭에서는 줄이 숨고, 상태 카드의 아이 이름을 누르면 같은 메뉴가 뜬다. 메뉴에는 아이들(지금 아이에 체크), '＋ 아이 추가', '＋ 보호자 초대 · 현재 N명'이 있다. 다른 아이를 고르면 탭 뷰모델 다섯이 새 아이로 다시 만들어지고, 보던 탭은 그대로다. 초대 두 줄은 Task 3 의 번호 화면을 전체 화면으로 연다. 아이가 그 번호로 들어오면 화면이 닫히고 그 아이가 선택된다. 멤버 목록이 바뀌어 저장된 아이가 사라지면 안전한 대체 아이로 옮긴다.

**Files:**
- Create: `ios/KidCare/Guardian/ChildSelectorModel.swift`, `ChildSelectorBar.swift`(줄·`ChildMenu`), `GuardianHomeView.swift`
- Modify: `ios/KidCare/Guardian/GuardianRootView.swift`(`@SceneStorage` → `@Binding`), `ios/KidCare/RouterView.swift:47-51`, `ios/KidCare/Guardian/StatusCardView.swift`(아이 이름 → 메뉴)
- Test: `ios/KidCareTests/ChildSelectorModelTests.swift`

**Interfaces:**
- Consumes: Task 2 `ReadOnlyCheck.isOn`, 알림 탭이 붙은 `GuardianRootView`. Task 3 `FamilyMember`, `FamilyRepository.observeMembers`, `InviteSession`(`Observe`, `init`, `정리한다`), `GuardianInviteView(session:onClose:)`. 2단계 `ChildSelector.select(children:preferredUid:)`, `SelectableChild`. 1단계 `RoleStore`(`childUid`), `MemberRole`. `KidCarePalette.skySoft·lineSoft·ink·inkSoft·sky·paper`.
- Produces:
  - `@MainActor @Observable final class ChildSelectorModel { typealias InviteFactory; let familyId; children, guardians, 불러오기_실패, 초대: InviteSession?, selectedUid, 줄_문구, 지도_이름, 보호자_초대_문구; init(familyId:roleStore:membersObserve:inviteFactory:); 시작한다(), 고른다(_:), 라벨(_:), 초대한다(_:), 초대를_닫는다(), 정리한다() }`
  - `struct ChildSelectorBar: View { let model: ChildSelectorModel }`, `struct ChildMenu<Content: View>: View`
  - `struct GuardianHomeView: View { init(familyId:) }`
  - `GuardianRootView.init(familyId:childUid:selectedTab: Binding<GuardianTab>)`

**정본:** `guardian/GuardianMainActivity.kt` 의 여러 자리다.
- `onCreate` :137-183(선택기·언어 버튼 연결 :142-143)
- `subscribeMembers` :185-193, `applyMembers` :195-216, `renderChildSelector` :218-225, `selectedChildLabelText` :227-231, `childLabel` :233-237
- `showChildMenuFrom` :239-241, `showChildMenu` :243-269, `selectChild` :271-278, `openInvite` :280-286, `recreateTabsForSelectedChild` :288-300
- `showTab` 의 선택기 줄 숨김 :330, `onResume` :406-413, `onDestroy` :423-428, 상수 :474-478

레이아웃은 `res/layout/activity_guardian_main.xml:17-62`(선택기 줄), `res/drawable/bg_child_selector.xml`, `guardian/MapTimelineFragment.kt:211-213, 248-252`·`fragment_map_timeline.xml:41-69`(지도 카드의 선택기)다. 초대 결과는 `onboarding/GuardianPairingActivity.kt:217-230` 을 따른다.

치수는 다음과 같다.
- 줄: 바탕 `paper`, 안쪽 좌우 12·위아래 8
- 선택기: 높이 48, 안쪽 좌우 12, 바탕 `sky_soft`, 테두리 `line_soft` 1, 모서리 20, TitleMedium 18 medium `ink`, 앞 정렬
- 지구본: 48×48, 앞 간격 6, 그림 22, `ink_soft`
- 지도 카드: 이름 뒤 화살표 20×20·앞 2·`sky`

**규칙 확인.** 새 쓰기가 없다. 아이 고르기는 이 폰의 `RoleStore` 에만 적는다(판정 기록 6). 멤버 구독은 `firestore.rules:99` 로 허용된다. 초대 쓰기는 Task 3 그대로다.

- [ ] **Step 1: 테스트를 먼저 쓴다**

`ios/KidCareTests/ChildSelectorModelTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// 정본은 `GuardianMainActivity.kt` 의 선택기 부분. 줄 번호는 테스트 이름에 적는다.
@MainActor
struct ChildSelectorModelTests {

    final class 가짜_구독: Sendable {
        let onChange = TestCallbackBox<([FamilyMember]) -> Void>()
        let onError = TestCallbackBox<(Error) -> Void>()
        let registration = TestListenerRegistration()
        private let 횟수_잠금 = OSAllocatedUnfairLock(initialState: 0)
        var 횟수: Int { 횟수_잠금.withLock { $0 } }
        func 불렸다() { 횟수_잠금.withLock { $0 += 1 } }
        func 보낸다(_ members: [FamilyMember]) { onChange.value?(members) }
    }

    @MainActor final class 초대_기록 {
        var 역할들: [MemberRole] = []
        var onJoined: (@MainActor (FamilyMember) -> Void)?
    }

    private func 저장소(_ childUid: String? = nil) -> RoleStore {
        let store = RoleStore(defaults: TestDefaults.isolated("ChildSelectorModelTests"))
        store.childUid = childUid
        return store
    }

    private func 멤버(_ uid: String, _ role: String, _ name: String = "", joined: Int64 = 1) -> FamilyMember {
        FamilyMember(uid: uid, role: role, displayName: name, joinedAt: joined)
    }

    private func 만든다(_ store: RoleStore, _ 구독: 가짜_구독, 초대: 초대_기록 = 초대_기록()) -> ChildSelectorModel {
        ChildSelectorModel(
            familyId: "fam",
            roleStore: store,
            membersObserve: { _, onChange, onError in
                구독.onChange.set(onChange)
                구독.onError.set(onError)
                구독.불렸다()
                return 구독.registration
            },
            inviteFactory: { familyId, role, onJoined in
                초대.역할들.append(role)
                초대.onJoined = onJoined
                // 이 테스트는 세션을 시작하지 않는다 — 소유와 닫기만 본다.
                return InviteSession(
                    familyId: familyId, role: role,
                    create: { _, _, _ in throw CancellationError() },
                    fetch: { _ in [] },
                    observe: { _, _, _ in TestListenerRegistration() },
                    onJoined: onJoined
                )
            }
        )
    }

    @Test("저장된 아이가 아직 가족에 있으면 그대로, 보호자와 아이를 나눠 든다(:195-206)")
    func 저장된_아이를_유지한다() async {
        let store = 저장소("c2"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("c1", "child", "민준", joined: 1), 멤버("c2", "child", "서연", joined: 2), 멤버("g1", "guardian", "엄마")])
        await eventually { m.children.count == 2 }
        #expect(store.childUid == "c2")
        #expect(m.guardians.map(\.uid) == ["g1"])
        #expect(m.줄_문구 == "서연 보는 중 ▾")
        #expect(m.지도_이름 == "서연")
    }

    @Test("저장된 아이가 사라졌거나 처음이면 가장 먼저 들어온 아이로 옮긴다(ChildSelector.kt, :199-205)")
    func 사라지면_대체_아이() async {
        let store = 저장소("gone"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("c2", "child", "서연", joined: 2), 멤버("c1", "child", "민준", joined: 1)])
        await eventually { store.childUid == "c1" }
        #expect(m.줄_문구 == "민준 보는 중 ▾")
    }

    @Test("아이가 없으면 선택을 비우고 child_selector_empty, 지도 카드는 child_default_name(:221-222, :227-231)")
    func 아이가_없으면() async {
        let store = 저장소("c1"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("g1", "guardian")])
        await eventually { m.guardians.count == 1 }
        #expect(store.childUid == nil)
        #expect(m.줄_문구 == String(localized: "child_selector_empty"))
        #expect(m.지도_이름 == String(localized: "child_default_name"))
    }

    @Test("이름이 겹치면 uid 끝 네 자리를 붙이고, 빈 이름은 '아이'로 센다(:233-237)")
    func 같은_이름() async {
        let store = 저장소(), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("child-aaaa1111", "child", ""), 멤버("child-bbbb2222", "child", "아이"), 멤버("c3", "child", "민준")])
        await eventually { m.children.count == 3 }
        #expect(m.children.map(m.라벨) == ["아이 · 1111", "아이 · 2222", "민준"])
    }

    @Test("고르면 이 폰의 선택만 바뀐다 — 서버에는 쓰지 않는다(:271-278, 판정 기록 6)")
    func 고른다() async {
        let store = 저장소("c1"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("c1", "child", "민준", joined: 1), 멤버("c2", "child", "서연", joined: 2)])
        await eventually { m.children.count == 2 }
        m.고른다("c2")
        #expect(store.childUid == "c2")
        #expect(m.selectedUid == "c2")
    }

    @Test("멤버 구독 실패는 child_selector_load_failed, 다음 스냅샷이 오면 풀린다(:191, :218-225)")
    func 불러오기_실패() async {
        let store = 저장소(), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.onError.value?(NSError(domain: "test", code: 1))
        await eventually { m.불러오기_실패 }
        #expect(m.줄_문구 == String(localized: "child_selector_load_failed"))
        구독.보낸다([멤버("c1", "child", "민준")])
        await eventually { !m.불러오기_실패 }
        #expect(m.줄_문구 == "민준 보는 중 ▾")
    }

    @Test("'＋ 보호자 초대' 줄에 지금 보호자 수를 적는다(:251-256)")
    func 보호자_수() async {
        let store = 저장소(), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        구독.보낸다([멤버("g1", "guardian"), 멤버("g2", "guardian"), 멤버("c1", "child")])
        await eventually { m.guardians.count == 2 }
        #expect(m.보호자_초대_문구 == "＋ 보호자 초대 · 현재 2명")
    }

    @Test("초대는 한 판만 열리고, 아이가 들어오면 그 아이를 고르고 닫는다(:280-286, GuardianPairingActivity.kt:217-230)")
    func 아이_초대() async {
        let store = 저장소("c1"), 구독 = 가짜_구독(), 초대 = 초대_기록()
        let m = 만든다(store, 구독, 초대: 초대)
        m.시작한다()
        m.초대한다(.child)
        m.초대한다(.guardian)
        #expect(초대.역할들 == [.child])
        #expect(m.초대?.role == .child)
        초대.onJoined?(멤버("c9", "child", "지우", joined: 9))
        #expect(store.childUid == "c9")
        #expect(m.초대 == nil)
    }

    @Test("보호자가 초대로 들어오면 아이 선택은 그대로 두고 닫기만 한다(GuardianPairingActivity.kt:226 은 아이일 때만 고른다)")
    func 보호자_초대() async {
        let store = 저장소("c1"), 구독 = 가짜_구독(), 초대 = 초대_기록()
        let m = 만든다(store, 구독, 초대: 초대)
        m.시작한다()
        m.초대한다(.guardian)
        초대.onJoined?(멤버("g9", "guardian"))
        #expect(store.childUid == "c1")
        #expect(m.초대 == nil)
    }

    @Test("두 번 시작해도 구독은 하나, 정리하면 리스너를 떼고 초대를 닫고 늦은 스냅샷을 무시한다(:423-428)")
    func 정리() async {
        let store = 저장소("c1"), 구독 = 가짜_구독()
        let m = 만든다(store, 구독)
        m.시작한다()
        m.시작한다()
        #expect(구독.횟수 == 1)
        m.초대한다(.child)
        m.정리한다()
        #expect(구독.registration.removed)
        #expect(m.초대 == nil)
        구독.보낸다([멤버("c2", "child", "서연")])
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(m.children.isEmpty)
        #expect(store.childUid == "c1")
        m.초대한다(.child)
        #expect(m.초대 == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/ChildSelectorModelTests`
Expected: 컴파일 실패("cannot find 'ChildSelectorModel' in scope").

- [ ] **Step 3: 선택기 모델**

`ios/KidCare/Guardian/ChildSelectorModel.swift`:

```swift
import FirebaseFirestore
import Foundation
import Observation

/// N:N 자녀 선택기. 정본은 `GuardianMainActivity.kt` 의 `subscribeMembers`·`applyMembers`·`childLabel`·
/// `showChildMenu`·`selectChild`·`openInvite`(:185-286).
///
/// **아이를 바꿔도 살아남는다.** `GuardianHomeView` 가 소유하고, 선택이 바뀌면 그 안의 `GuardianRootView` 만
/// `.id(childUid)` 로 다시 만들어진다(안드로이드가 액티비티는 두고 프래그먼트만 다시 만드는 것, :288-300 —
/// 계획서 판정 기록 7). 선택 결과는 `RoleStore.childUid` 하나에만 적는다. 서버에는 쓰지 않는다(판정 기록 6).
@MainActor
@Observable
final class ChildSelectorModel {

    typealias InviteFactory = @MainActor (
        _ familyId: String, _ role: MemberRole, _ onJoined: @escaping @MainActor (FamilyMember) -> Void
    ) -> InviteSession

    let familyId: String
    private(set) var children: [FamilyMember] = []
    private(set) var guardians: [FamilyMember] = []
    /// 멤버 구독이 실패했다(:191). 다음 스냅샷이 오면 풀린다.
    private(set) var 불러오기_실패 = false
    /// 열려 있는 초대 한 판. nil 이면 번호 화면이 닫혀 있다.
    private(set) var 초대: InviteSession?

    private let roleStore: RoleStore
    private let membersObserve: InviteSession.Observe
    private let inviteFactory: InviteFactory
    private var listener: ListenerRegistration?
    private var 시작했다 = false
    private var 닫혔다 = false

    init(
        familyId: String,
        roleStore: RoleStore,
        membersObserve: @escaping InviteSession.Observe = FamilyRepository.observeMembers,
        inviteFactory: @escaping InviteFactory = { familyId, role, onJoined in
            InviteSession(familyId: familyId, role: role, onJoined: onJoined)
        }
    ) {
        self.familyId = familyId
        self.roleStore = roleStore
        self.membersObserve = membersObserve
        self.inviteFactory = inviteFactory
    }

    var selectedUid: String? { roleStore.childUid }

    /// 선택기 줄의 글(:218-225). 구독 실패면 그 사실을 적는다(:191).
    var 줄_문구: String {
        if 불러오기_실패 { return String(localized: "child_selector_load_failed") }
        guard let selected = children.first(where: { $0.uid == selectedUid }) else {
            return String(localized: "child_selector_empty")
        }
        return String(format: String(localized: "child_selector_value"), 라벨(selected))
    }

    /// 지도 카드의 아이 이름(`selectedChildLabelText`, :227-231).
    var 지도_이름: String {
        children.first(where: { $0.uid == selectedUid }).map(라벨) ?? String(localized: "child_default_name")
    }

    /// '＋ 보호자 초대 · 현재 N명'(:251-256).
    var 보호자_초대_문구: String {
        String(format: String(localized: "child_selector_add_guardian_count"), guardians.count)
    }

    /// 이름이 겹치는 아이는 uid 끝 네 자리로 가른다(:233-237). 두 아이가 다 "아이"면 메뉴에서 구분이 안 된다.
    func 라벨(_ child: FamilyMember) -> String {
        let base = Self.이름(child)
        return children.filter { Self.이름($0) == base }.count > 1 ? "\(base) · \(child.uid.suffix(4))" : base
    }

    /// 본 화면이 뜰 때 구독한다(:182). 두 번째부터는 무시한다.
    func 시작한다() {
        guard !시작했다, !닫혔다 else { return }
        시작했다 = true
        listener = membersObserve(familyId, { [weak self] members in
            Task { @MainActor in self?.멤버를_반영한다(members) }
        }, { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.닫혔다 else { return }
                self.불러오기_실패 = true
            }
        })
    }

    /// 메뉴에서 아이를 골랐다(:271-278). 같은 아이면 아무 일도 하지 않는다 — 다시 적으면 탭이 괜히 다시 만들어진다.
    func 고른다(_ uid: String) {
        guard !닫혔다, roleStore.childUid != uid else { return }
        roleStore.childUid = uid
    }

    /// '＋ 아이 추가'·'＋ 보호자 초대'(:280-286). 이미 열린 초대가 있으면 새로 열지 않는다.
    /// 세션은 여기, 버튼 액션에서 만든다 — 뷰 빌더 안에서 만들면 한 번의 표시에 여러 번 만들어진다(`NewFamilySession` 주석).
    func 초대한다(_ role: MemberRole) {
        guard !닫혔다, 초대 == nil else { return }
        초대 = inviteFactory(familyId, role) { [weak self] member in
            self?.초대로_들어왔다(member)
        }
    }

    /// 번호 화면을 닫는다(뒤로 버튼, 합류 완료, 정리).
    func 초대를_닫는다() {
        초대?.정리한다()
        초대 = nil
    }

    /// 본 화면이 사라진다(`onDestroy`, :423-428).
    func 정리한다() {
        닫혔다 = true
        listener?.remove()
        listener = nil
        초대를_닫는다()
    }

    /// `applyMembers`(:195-216). 옛 가족 자료 옮기기(:209-212)는 하지 않는다(판정 기록 6).
    private func 멤버를_반영한다(_ members: [FamilyMember]) {
        guard !닫혔다 else { return }
        불러오기_실패 = false
        let next = members.filter { $0.role == MemberRole.child.rawValue }
        guardians = members.filter { $0.role == MemberRole.guardian.rawValue }
        children = next
        let selected = ChildSelector.select(
            children: next.map { SelectableChild(uid: $0.uid, displayName: $0.displayName, joinedAt: $0.joinedAt) },
            preferredUid: roleStore.childUid
        )
        if roleStore.childUid != selected?.uid {
            roleStore.childUid = selected?.uid
        }
    }

    /// `goToMain`(GuardianPairingActivity.kt:217-230): 아이가 들어왔으면 그 아이를 고른다. 보호자면 닫기만 한다.
    private func 초대로_들어왔다(_ member: FamilyMember) {
        if member.role == MemberRole.child.rawValue, !닫혔다 {
            roleStore.childUid = member.uid
        }
        초대를_닫는다()
    }

    private static func 이름(_ child: FamilyMember) -> String {
        child.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "child_default_name")
            : child.displayName
    }
}
```

`라벨` 의 `ifBlank` 는 코틀린처럼 공백·줄바꿈만 있는 이름도 비었다고 본다. 테스트 `같은_이름` 의 `""` 와 `"아이"` 가 같은 base 로 묶이는 이유다.

- [ ] **Step 4: 줄·메뉴·집 화면**

`ios/KidCare/Guardian/ChildSelectorBar.swift`:

```swift
import SwiftUI
import UIKit

/// 선택기 줄. 정본은 `activity_guardian_main.xml:17-62` — 선택기 한 칸과 지구본 버튼.
struct ChildSelectorBar: View {
    let model: ChildSelectorModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 6) {
            ChildMenu(model: model) {
                Text(model.줄_문구)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(KidCarePalette.lineSoft, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            // 안드로이드는 앱 안 언어 대화상자를 연다. iOS 는 설정 → 앱 → 언어 칸이 늘 있으므로 그 페이지를 연다(판정 기록 9).
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(Text("language_picker_title"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(KidCarePalette.paper)
    }
}

/// 선택 팝업. 정본은 `showChildMenu`(:243-269) — 아이들(지금 아이에 체크) 뒤에 '＋ 아이 추가', '＋ 보호자 초대 · 현재 N명'.
/// 선택기 줄과 지도 카드가 같은 메뉴를 쓴다(`showChildMenuFrom`, :239-241).
struct ChildMenu<Content: View>: View {
    let model: ChildSelectorModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            ForEach(model.children, id: \.uid) { child in
                Button { model.고른다(child.uid) } label: {
                    if child.uid == model.selectedUid {
                        Label(model.라벨(child), systemImage: "checkmark")
                    } else {
                        Text(model.라벨(child))
                    }
                }
            }
            // 실기기 읽기 전용 확인에서는 진짜 가족에 초대 코드를 만들지 않는다(판정 기록 10).
            Button("child_selector_add_child") { model.초대한다(.child) }
                .disabled(ReadOnlyCheck.isOn)
            Button(model.보호자_초대_문구) { model.초대한다(.guardian) }
                .disabled(ReadOnlyCheck.isOn)
        } label: {
            content()
        }
    }
}
```

`ios/KidCare/Guardian/GuardianHomeView.swift`:

```swift
import SwiftUI

/// 보호자 본 화면의 바깥 틀 — 선택기 줄, 선택 탭, 초대 번호 화면의 주인. 정본은 `GuardianMainActivity` 의
/// "액티비티 몫"(선택기·멤버 리스너·초대 열기)이고, 탭과 배너는 안쪽 `GuardianRootView` 몫이다.
///
/// 이렇게 두 겹인 이유(판정 기록 7): 아이를 바꾸면 탭 뷰모델은 새 아이로 **다시 만들어야** 하지만, 선택기와
/// 멤버 리스너와 보던 탭은 **살아남아야** 한다. `.id(childUid)` 를 안쪽에만 건다.
struct GuardianHomeView: View {

    let familyId: String
    @State private var store = RoleStore.shared
    @State private var selector: ChildSelectorModel
    /// 4단계 `GuardianRootView` 에 있던 것을 위로 올렸다. 키 문자열은 그대로라 저장된 선택 탭을 그대로 읽는다.
    @SceneStorage("guardian.selectedTab") private var selectedTab: GuardianTab = .map

    init(familyId: String) {
        self.familyId = familyId
        _selector = State(initialValue: ChildSelectorModel(familyId: familyId, roleStore: RoleStore.shared))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 지도 탭에서는 줄을 숨긴다(showTab :330). 지도는 상태 카드의 아이 이름이 같은 메뉴를 연다.
            if selectedTab != .map {
                ChildSelectorBar(model: selector)
            }
            GuardianRootView(familyId: familyId, childUid: store.childUid, selectedTab: $selectedTab)
                // 아이가 바뀌면 탭 뷰모델 다섯을 새 아이로 다시 만든다(recreateTabsForSelectedChild :288-300).
                // 옛 뷰의 onDisappear 가 옛 뷰모델들의 리스너를 뗀다.
                .id(store.childUid ?? "")
        }
        .environment(selector)
        .onAppear { selector.시작한다() }
        .onDisappear { selector.정리한다() }
        // 안드로이드는 새 액티비티로 띄운다(openInvite :280-286). 탭마다 NavigationStack 이 있어 바깥에서 push 할
        // 수 없으므로 전체 화면 커버로 띄우고 뒤로 버튼을 단다(판정 기록 8).
        .fullScreenCover(isPresented: Binding(
            get: { selector.초대 != nil },
            set: { if !$0 { selector.초대를_닫는다() } }
        )) {
            if let session = selector.초대 {
                GuardianInviteView(session: session, onClose: { selector.초대를_닫는다() })
            }
        }
    }
}
```

- [ ] **Step 5: 기존 화면 셋을 잇는다**

`ios/KidCare/Guardian/GuardianRootView.swift`:
1. `@SceneStorage("guardian.selectedTab") private var selectedTab: GuardianTab = .map` 줄과 그 주석을 이것으로 바꾼다:

```swift
    /// 선택 탭. 주인은 `GuardianHomeView` 다 — 아이를 바꿔 이 뷰가 다시 만들어져도 보던 탭이 남아야 하고
    /// (recreateTabsForSelectedChild :293-298), 바깥의 선택기 줄이 지도 탭인지 알아야 한다(:330).
    @Binding var selectedTab: GuardianTab
```

2. `init(familyId: String, childUid: String?)` 를 `init(familyId: String, childUid: String?, selectedTab: Binding<GuardianTab>)` 로 바꾸고, 본문 첫 줄에 `_selectedTab = selectedTab` 을 넣는다. Task 2 의 `알림_보임을_맞춘다`·`.onChange(of: selectedTab)`, 5단계의 `if selectedTab == .schedule` 은 이름이 같아서 그대로 컴파일된다.

`ios/KidCare/RouterView.swift:47-51` 을 바꾼다:

```swift
        } else if showMain, let familyId = store.familyId {
            GuardianHomeView(familyId: familyId)
                // 가족이 바뀌면 선택기까지 새로 만든다. 아이가 바뀌면 GuardianHomeView 안에서 탭만 새로 만든다
                // (통합 검토 M1 의 .id(familyId+childUid) 를 두 겹으로 나눴다 — 6단계 판정 기록 7).
                .id(familyId)
```

`ios/KidCare/Guardian/StatusCardView.swift`:
1. `@State private var 배터리_설명_표시 = false` 위에 더한다:

```swift
    /// 본 화면의 선택기. 있으면 아이 이름이 선택 메뉴가 된다(MapTimelineFragment.kt:211-213). 미리보기처럼
    /// 선택기가 없는 곳에서는 넘겨받은 이름만 그린다.
    @Environment(ChildSelectorModel.self) private var selector: ChildSelectorModel?
```

2. `body` 의 첫 요소 `Text(childName) … .fixedSize(horizontal: true, vertical: false)` 네 줄을 바꾼다:

```swift
            if let selector {
                // fragment_map_timeline.xml:41-69 — 이름 뒤에 하늘색 화살표, 누르면 선택기 줄과 같은 메뉴.
                ChildMenu(model: selector) {
                    HStack(spacing: 2) {
                        Text(selector.지도_이름)
                            .font(.headline)
                            .foregroundStyle(KidCarePalette.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KidCarePalette.sky)
                            .frame(width: 20, height: 20)
                    }
                }
            } else {
                Text(childName)
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
```

- [ ] **Step 6: 통과 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS. `ChildSelectorModelTests` 10개가 새로 들어간다.

```bash
grep -rn "GuardianRootView(" ios/KidCare | grep -v "GuardianHomeView.swift"   # 비어 있어야 한다(RouterView 는 GuardianHomeView 를 부른다)
grep -rn "@SceneStorage" ios/KidCare                                            # GuardianHomeView.swift 한 줄
```

- [ ] **Step 7: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Guardian/ChildSelectorModel.swift ios/KidCare/Guardian/ChildSelectorBar.swift ios/KidCare/Guardian/GuardianHomeView.swift \
  ios/KidCare/Guardian/GuardianRootView.swift ios/KidCare/RouterView.swift ios/KidCare/Guardian/StatusCardView.swift \
  ios/KidCareTests/ChildSelectorModelTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 6단계 Task 4: 아이 선택기 — 아이를 바꾸면 탭만 새로 만들고, 초대 두 줄과 지구본 버튼을 옮긴다"
```

---
## 단계 마무리 — 통합 리뷰 한 번, 시뮬레이터 확인 한 번

Task 1~4 는 단위 테스트만 돌리고 넘어간다(4·5단계와 같은 빠른 방식). 여기서 한 번에 본다.

- [ ] **Step 1: 기계 검사**

```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
cd /Users/com/work/KidCare
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'; cd ..
python3 tools/ios-strings.py --check; echo $?                                               # 0
swift tools/check-i18n-keys.swift > /tmp/p6-i18n-after.txt; diff /tmp/p6-i18n-before.txt /tmp/p6-i18n-after.txt
grep -rn "^import" ios/KidCare/Logic | grep -v "import Foundation$"                          # 비어 있어야 한다
grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|navigationBarBackButtonHidden" ios/KidCare  # 비어 있어야 한다
grep -rn "withKnownIssue\|TabPlaceholderView\|add-ios-catalog-keys" ios tools                 # 비어 있어야 한다
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew                                # 비어 있어야 한다
git diff ios/KidCare/KidCareApp.swift                                                       # 비어 있어야 한다
```

`check-i18n-keys` 의 diff 는 정확히 이 모양이어야 한다. 12개 언어마다 "21개 키 없음"이 "23개 키 없음"이 되고, `alert_time_date_format`·`alert_time_today_format`·`ios_alert_open_app_hint` 가 더해지고 `ios_tab_not_ready_body` 가 빠진다. 다른 변화가 있으면 멈추고 보고한다.

테스트 개수를 적어 둔다(Task 5 개발일지). 기대값은 5단계 끝보다 **49개** 많고, 알려진 문제는 **12개 → 0개**다. 내역은 이렇다.
- Task 1: +5(`I18nKeyParityTests` 1→3, `LocalizationBundleTests` 3. `LocalizableCatalogTests` 는 개수가 그대로)
- Task 2: 22(`EventDocuments` 3, `AlertText` 5, `AlertViewModel` 10, `EventRepository` 4)
- Task 3: 12(`InviteSession` 9, `FamilyMembers` 1, `InviteFlow` 2)
- Task 4: 10(`ChildSelectorModel` 10)

- [ ] **Step 2: 통합 리뷰** — superpowers:requesting-code-review 로 6단계 첫 커밋의 부모부터 HEAD 까지를 한 번 리뷰받는다. 리뷰어에게 이 계획서의 "판정 기록" 열두 줄과 "Pre-flight conflict table" 을 함께 준다. 특히 다섯 가지를 봐 달라고 적는다.
  1. 아이를 바꿔 `GuardianRootView` 가 `.id` 로 다시 만들어질 때, 옛 뷰의 `onDisappear` 가 다섯 뷰모델의 `정리한다()` 를 **모두** 부르는가. 새 뷰의 `onAppear` 전에 옛 리스너가 새 아이 화면에 값을 흘리는 길이 없는가.
  2. `AlertViewModel` 의 보임 판정이 탭 전환·앱 전환·`.inactive`(제어 센터)에서 안드로이드 `setVisible` 과 같은 결과를 내는가.
  3. `InviteSession` 이 커버의 재마운트나 `시작한다()` 중복 호출에도 번호를 한 번만 발급하는가. 닫힌 뒤 늦게 끝난 발급이 상태를 건드리지 않는가.
  4. 생성기(`tools/ios-strings.py`)와 Swift 대조(`LocalizableCatalogTests.카탈로그_값`)가 서로 독립인가. 한쪽 규칙만 바꾸면 테스트가 빨개지는가.
  5. 섭동 확인이다. 다음을 바꾸면 적힌 테스트가 빨개져야 한다.
     - `AlertRowView` 가 아니라 뷰모델 쪽에서 `강조` 를 `events.filter { !$0.read }` 로 바꾸면 `살구빛은_연_순간을_붙든다` 가 빨개진다.
     - 생성기의 빈 칸 `state` 를 `translated` 로 바꾸면 `카탈로그는_원본에서_나온다` 가 빨개진다.
     - `InviteSession.멤버가_바뀌었다` 에서 `기준_멤버` 검사를 빼면 `합류는_한_번` 이 빨개진다.
     - `ChildSelectorModel.멤버를_반영한다` 가 `roleStore.childUid` 를 안 고치면 `사라지면_대체_아이` 가 빨개진다.

  반려 항목은 고친 뒤 한국어 커밋(`iOS 6단계 Fix round N: …`)으로 남긴다.

- [ ] **Step 3: 시뮬레이터 확인 준비 — 에뮬레이터에만 쓴다**

5단계 단계 마무리 Step 3 과 같다. 순서는 이렇다.
1. 다른 터미널에서 `firebase emulators:start --only auth,firestore --project kidcare-emulator` 를 띄운다.
2. `ios/KidCare/KidCareApp.swift` 를 **잠시** `configureForEmulator(projectId: "kidcare-emulator")` 로 바꾸고 새로 설치한다.
3. 앱에서 보호자 → 새 가족 만들기로 가족을 만든다.
4. 아래 셸로 `sim-child`(민준)와 상태 문서를 넣는다. 사건을 넣는 도우미와 보는 도우미도 함께 둔다. owner 토큰은 규칙을 건너뛰므로 **데이터 준비에만** 쓴다. 규칙은 에뮬레이터 테스트가 이미 태웠다.

```bash
EMU="http://127.0.0.1:8080/v1/projects/kidcare-emulator/databases/(default)/documents"
AUTH="Authorization: Bearer owner"
FAMILY=$(curl -s -H "$AUTH" "$EMU/families" | python3 -c 'import json,sys; print(json.load(sys.stdin)["documents"][-1]["name"].split("/")[-1])')
NOW=$(python3 -c 'import time; print(int(time.time()*1000))')
child() {  # child <uid> <이름> <joinedAt>
  curl -s -X PATCH -H "$AUTH" -H "Content-Type: application/json" "$EMU/families/$FAMILY/members/$1" \
    -d "{\"fields\":{\"role\":{\"stringValue\":\"child\"},\"displayName\":{\"stringValue\":\"$2\"},\"fcmToken\":{\"stringValue\":\"\"},\"appVersion\":{\"stringValue\":\"\"},\"joinCode\":{\"stringValue\":\"\"},\"updatedAt\":{\"integerValue\":\"$3\"},\"joinedAt\":{\"integerValue\":\"$3\"}}}" > /dev/null; }
ev() {     # ev <type> <at> <childUid> <placeName> <detail>
  curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" "$EMU/families/$FAMILY/events" \
    -d "{\"fields\":{\"id\":{\"stringValue\":\"\"},\"type\":{\"stringValue\":\"$1\"},\"at\":{\"integerValue\":\"$2\"},\"childUid\":{\"stringValue\":\"$3\"},\"placeName\":{\"stringValue\":\"$4\"},\"detail\":{\"stringValue\":\"$5\"},\"read\":{\"booleanValue\":false}}}" > /dev/null; }
events() { curl -s -H "$AUTH" "$EMU/families/$FAMILY/events" | python3 -c 'import json,sys; [print(d["fields"]["childUid"]["stringValue"], d["fields"]["type"]["stringValue"], d["fields"]["read"]["booleanValue"], sorted(d["fields"])) for d in json.load(sys.stdin).get("documents",[])]'; }
child sim-child 민준 $NOW
curl -s -X PATCH -H "$AUTH" -H "Content-Type: application/json" "$EMU/families/$FAMILY/children/sim-child" \
  -d "{\"fields\":{\"lat\":{\"doubleValue\":37.5665},\"lng\":{\"doubleValue\":126.978},\"battery\":{\"integerValue\":\"77\"},\"ringerMode\":{\"stringValue\":\"normal\"},\"dnd\":{\"stringValue\":\"off\"},\"network\":{\"stringValue\":\"wifi\"},\"wifiOn\":{\"booleanValue\":true},\"lastSeenAt\":{\"integerValue\":\"$NOW\"}}}" > /dev/null
```

- [ ] **Step 4: 시뮬레이터에서 본다** — 항목마다 `xcrun simctl io booted screenshot /tmp/p6-<번호>.png` 로 남기고, 가능하면 안드로이드 보호자 폰의 같은 화면과 나란히 둔다.

1. **선택기 줄.** 지도 탭에는 줄이 없고, 상태 카드에 "민준 ›"(하늘색 화살표)이 보인다. 알림 탭으로 가면 맨 위에 옅은 보라 칸 "민준 보는 중 ▾"와 지구본이 뜬다. 그 아래에 무응답 배너 자리, 그 아래 탭 내용 순서다.
2. **빈 알림 탭.** 옅은 보라 카드에 "아이폰에서는 앱을 열었을 때 새 소식을 확인해요.", 가운데 마스코트와 "아직 온 알림이 없어요…"가 뜬다. 스위치는 없다.
3. **사건 넷.** `ev place_enter $((NOW-60000)) sim-child 학교 ""`, `ev place_exit $((NOW-1800000)) sim-child 학원 ""`, `ev low_battery $((NOW-86400000)) sim-child "" "12% 남음"`, `ev geofence_v2 $((NOW-120000)) sim-child "" ""`. 다른 탭을 보다가 알림 탭으로 온다.
   - 최신순으로 네 줄이 뜬다. 풀빛 핀 "학교에 도착했어요 · 오후 …", 하늘빛 종 "새로운 소식이 있어요 · …", 살구빛 경로 "학원에서 나섰어요 · …", 자두빛 배터리 "애기폰 배터리가 얼마 안 남았어요 · 9월 12일 …"와 둘째 줄 "12% 남음" 순서다.
   - **네 줄 모두 살구빛 바탕**이다.
   - 몇 초 안에 `events` 의 네 줄이 `True` 가 되고, 필드 목록은 일곱 그대로다. 그래도 화면의 살구빛은 **남아 있다.**
4. **떠났다 돌아오기.** 지도 탭을 봤다 돌아오면 살구빛이 모두 사라진다. 다른 탭에 있는 동안 `ev signal_lost $NOW sim-child "" ""` 를 넣고 돌아오면 **그 한 줄만** 살구빛이다. 알림 탭을 보는 동안 `ev command_failed $NOW sim-child "" "권한 없음"` 을 넣으면 그 줄이 살구빛으로 나타나고 곧 `True` 가 된다. 홈으로 나갔다 돌아와도 같은 규칙이다.
5. **두 번째 아이.** `child sim-child-2 서연 $((NOW+1000))` 와 `ev place_enter $NOW sim-child-2 도서관 ""`. 선택기를 누르면 메뉴에 "민준 ✓", "서연", "＋ 아이 추가", "＋ 보호자 초대 · 현재 1명"이 뜬다. 서연을 고르면 줄이 "서연 보는 중 ▾"가 되고, **보던 알림 탭에 그대로 머문 채** 목록이 "도서관에 도착했어요" 한 줄로 바뀐다. 지도 탭 카드 이름도 "서연"이다. 앱을 껐다 켜도 서연이 선택돼 있다.
6. **이름 겹침.** `child sim-child-3 서연 $((NOW+2000))` 을 넣으면 메뉴에 "서연 · ld-2"와 "서연 · ld-3"이 뜬다(uid 끝 네 자리).
7. **초대 — 아이.** 메뉴 '＋ 아이 추가'를 누르면 전체 화면이 뜨고 **왼쪽 위에 뒤로 화살표**가 보인다. 화면에는 "아이 폰에 이 번호를 입력하세요", 옅은 보라 카드의 여섯 글자, 안내 두 줄, "이 번호는 10분 뒤에 만료돼요", '새 번호 받기'가 있다. `curl -s -H "$AUTH" "$EMU/inviteCodes/<번호>"` 로 `role: child`, `createdByUid` 가 보인다. '새 번호 받기'를 누르면 글자가 바뀌고, 옛 번호 문서는 404 가 된다. 이어서 `child sim-child-4 지우 $((NOW+3000))` 을 넣으면 화면이 저절로 닫히고 선택기가 "지우 보는 중 ▾"가 된다.
8. **초대 — 보호자.** '＋ 보호자 초대 · 현재 1명'을 누르면 "다른 보호자 폰에 이 번호를 입력하세요"와 보호자용 안내가 뜬다. 뒤로 화살표를 누르면 닫히고 선택은 그대로다. '역할 다시 고르기' 버튼은 없다.
9. **언어.** 지구본을 누르면 설정 앱의 KidCare 페이지가 열리고 '언어' 칸이 있다. English 를 고르고 앱으로 돌아온다. 탭 이름이 Map·Updates…로 바뀌고, 알림 카드가 "On iPhone, new updates show up when you open the app.", 선택기가 "Viewing 지우 ▾"다. 日本語 로 바꾸면 탭과 선택기는 일본어인데 알림 카드 한 줄만 영어다(빈 칸이 영어로 물러남). 시각이 "午後3:12" 꼴이 아니라 영어 패턴(`h:mm a`)으로 찍히는 것도 빈 칸이라서다. 한국어로 되돌린다.
10. **오프라인·예외(판정 기록 1).** 에뮬레이터 터미널을 `Ctrl+C` 로 멈춘다. 이 항목은 **맨 마지막**에 한다.
    - 알림 탭 목록은 캐시로 그대로 남고 "아직 온 알림이 없어요"로 바뀌지 않는다.
    - 선택기 줄은 마지막 이름을 그대로 보여준다(구독이 끊겨도 목록을 비우지 않는다).
    - 선택기 메뉴 '＋ 아이 추가'를 연다. 20초 뒤 "인터넷에 연결할 수 없어요…"와 '다시 시도'가 뜬다. 뒤로 화살표로 닫힌다.
    - 예약·장소 탭은 5단계 Step 4-10 과 같은 모양인지 본다.

- [ ] **Step 5: 되돌리고 확인** — `KidCareApp.swift` 를 `configureForApp()` 로 되돌리고 `git diff ios/KidCare/KidCareApp.swift` 가 비어 있는지 확인한다. 시뮬레이터에서 앱을 지운다. 여기서 찾은 결함은 고친 뒤 테스트를 다시 돌리고 `iOS 6단계 Fix round N: …` 으로 커밋한다.

---

### Task 5: 실기기에서 읽기만 하는 확인, 그리고 개발일지

**Files:**
- Modify: `README.md`(개발일지 절, "함께 고쳐야 하는 짝", "14개 언어" 절)

**진짜 가족에 쓰는 동작은 실기기에서 하지 않는다.** 읽음 쓰기와 초대 발급은 위 단계 마무리에서 에뮬레이터로만 확인했다. 실기기는 운영 Firebase 에 붙은 진짜 가족이다.
- **`-readOnlyCheck` 로 띄운다(판정 기록 10).** 이 인자가 먹었는지 **알림 탭을 열기 전에** 확인한다. 선택기 메뉴의 초대 두 줄이 흐려져 있어야 한다. 흐리지 않으면 알림 탭을 열지 말고 멈추고 보고한다.
- **누르지 않는 것:** 초대 두 줄(흐려져 있다), 관리 탭(여는 순간 `query_ringer` 를 쓴다 — 4단계 Task 6), 예약·장소의 저장·켬끔·삭제·'다시 알리기', 지도 탭의 명령 버튼. 앱을 지우거나 역할을 다시 고르지 않는다.
- **안전한 것:** 아이 고르기다. 이 폰의 `RoleStore` 에만 적는다(판정 기록 6). 알림·예약·장소 탭 열기는 읽기뿐이다(`-readOnlyCheck` 에서 알림 읽음은 빈 동작).

- [ ] **Step 1: 실기기 연결 확인** — `xcrun devicectl list devices`. `unavailable` 이면 **여기서 멈추고 보고한다.** 케이블은 사람이 꽂아야 한다.

- [ ] **Step 2: 운영 설정으로 설치하고 읽기 전용으로 띄운다** — `configureForApp()` 그대로 둔다. 기존 앱 위에 덮어 설치해야 가족 합류가 유지된다. 기기에서 앱이 떠 있으면 먼저 완전히 닫는다.

```bash
cd /Users/com/work/KidCare/ios
xcodebuild -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS,id=<UDID>' -derivedDataPath /tmp/kidcare-dd-device -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> /tmp/kidcare-dd-device/Build/Products/Debug-iphoneos/KidCare.app
xcrun devicectl device process launch --device <UDID> com.kidcare.family -readOnlyCheck
```

- [ ] **Step 3: 보기만 한다** — 안드로이드 보호자 폰을 옆에 둔다. 안드로이드 폰의 **알림 탭은 아이폰 확인이 끝날 때까지 열지 않는다**(열면 안드로이드가 읽음을 써서 비교할 살구빛이 사라진다). 스크린샷은 사람이 기기에서 찍는다.
  1. **읽기 전용 확인.** 예약 탭으로 가 선택기 줄을 누른다. 초대 두 줄이 흐리다. 메뉴의 아이 이름·순서·"현재 N명"이 안드로이드 선택기 메뉴와 같다.
  2. **알림 탭.** 줄 순서·제목·시각 표기·그림 색·detail 줄이 안드로이드 알림 목록과 같다. 시각은 한국어 폰이면 "오후 3시 12분" 꼴로 **글자까지** 같다. 안 읽은 사건이 있었다면 아이폰에서 살구빛으로 보인다. 아이폰 확인을 끝낸 뒤 안드로이드 알림 탭을 열어 **같은 줄이 여전히 살구빛인지** 본다. 그래야 아이폰이 쓰지 않았다는 증거가 된다. 안 읽은 사건이 하나도 없었으면 그렇다고 적는다.
  3. **아이 바꾸기.** 아이가 둘 이상이면 다른 아이를 골라 알림·예약·장소 목록과 지도 카드 이름이 그 아이 것으로 바뀌는지 본다. 그리고 원래 아이로 되돌린다. 하나뿐이면 메뉴만 열어 본다.
  4. **언어.** 지구본 → 설정의 '언어'를 English 로 바꿨다가 앱이 영어로 뜨는 것을 보고 한국어로 되돌린다.
  5. 앱을 닫는다. 다음 실행은 인자 없이 한다(평소 동작).

- [ ] **Step 4: 개발일지를 쓴다** — `README.md` 에 절 하나를 더한다. 자리는 5단계 절(`### 아이폰 5단계 …`) 바로 다음이다. 앞 절들과 같은 말투(부모와 다음 개발자가 읽는 한국어 설명문)로 아래 내용을 **다 담는다.**

```markdown
### 아이폰 6단계 — 알림 탭, 아이 선택기, 14개 언어 (2026-09-13)

아이폰 보호자 앱의 마지막 자리표시였던 알림 탭을 안드로이드와 같은 목록으로 채웠고, 여러 아이 중 볼 아이를 고르는 선택기와 그 메뉴의 '＋ 아이 추가'·'＋ 보호자 초대'를 옮겼습니다. 화면 문장은 이제 `i18n/*.json` 14벌에서 아이폰 카탈로그로 한 번에 뽑습니다.

#### 알림은 앱을 열었을 때 봅니다

안드로이드 보호자 폰은 켜 둔 서비스가 새 사건을 곧바로 알려줍니다. 아이폰에서 같은 일을 하려면 푸시가 필요하고, 푸시는 유료 요금제로 넘어가야 해서 하지 않기로 했습니다. 그래서 알림 탭 맨 위, 안드로이드의 '알림 바로 받기' 스위치 자리에 "아이폰에서는 앱을 열었을 때 새 소식을 확인해요."라고 적었습니다.

#### 살구빛은 연 순간을 기억합니다

안 읽은 사건은 살구빛으로 칠하고, 화면을 여는 순간 읽음으로 적습니다. 둘을 그대로 붙이면 읽음 표시가 색보다 먼저 도착해 부모 눈에 아무것도 안 남습니다. 안드로이드처럼 **연 순간 안 읽었던 줄을 따로 기억해** 그 줄을 칠하고, 탭을 떠나면 잊습니다. 서버에는 `read` 한 칸만 씁니다 — 규칙이 그 한 칸만 허락합니다.

#### 아이를 바꾸면 탭만 새로 만듭니다

선택기에서 다른 아이를 고르면 지도·알림·관리·예약·장소가 새 아이로 다시 만들어지고, 보던 탭과 선택기는 그대로 남습니다. 고르기는 이 폰에만 기억합니다. 안드로이드는 고를 때마다 옛 1:1 가족 자료를 옮기는 쓰기를 시도하는데, 아이폰은 이미 옮겨진 가족에 합류하므로 하지 않았습니다.

초대 번호 화면은 전체 화면으로 뜨고 왼쪽 위에 뒤로 화살표가 있습니다. 아이가 그 번호로 들어오면 저절로 닫히고 그 아이가 선택됩니다. 초대 발급은 진짜 가족에 쓰는 일이라 에뮬레이터에서만 확인했습니다.

#### 14개 언어 — 번역을 지어내지 않았습니다

`python3 tools/ios-strings.py` 가 14벌을 읽어 카탈로그를 만듭니다. 1~6단계가 아이폰을 위해 더한 문장 N개(단계 마무리 Step 1 의 "N개 키 없음")는 아직 한국어와 영어에만 있습니다. 안전에 관한 문장을 기계 번역으로 채워 넣지 않기로 했고, 대신 그 칸은 **영어로** 나옵니다 — 안드로이드도 번역이 없는 문장은 기본값인 영어로 보여줍니다. 아이폰의 기본 언어는 한국어라서 가만두면 독일어 폰에 한국어가 뜨기 때문에 생성기가 영어를 적어 넣습니다. 빈 칸 목록은 `tools/i18n-untranslated.json` 에 있고, 번역을 받아 채우면 이 목록을 줄이면 됩니다. 목록과 실제가 한 칸이라도 다르면 테스트가 빨개집니다.

1단계에서 화면에 맞춰 손으로 고쳐 두었던 세 문장("보호자", "가족에 합류하기", "아직 연결된 아이가 없어요")은 원본 문장으로 돌아갔습니다. 서버에 저장되는 기본 이름("우리 가족", "보호자")은 언어가 바뀌어도 흔들리지 않게 안드로이드처럼 글자 그대로 저장합니다.

#### 안드로이드에서 찾은 것 (고치지 않았습니다)

- 본 화면의 선택기 메뉴에서 연 초대 화면에도 '역할 다시 고르기' 버튼이 보입니다(`GuardianPairingActivity.kt:81-101`). 누르면 이 폰의 가족 연결 기록을 지우고 첫 화면으로 갑니다. 아이폰 초대 화면에는 두지 않았습니다.
- `EventRepository.kt:25`·`:39` 주석은 사건 `at` 창을 "과거 24시간"으로 적었지만, 규칙은 6단계에서 7일로 넓혔습니다(`firestore.rules:282-286`).
- 알림 시각 표기가 `Locale.KOREA` 로 박혀 있어(`AlertAdapter.kt:95-98`) 영어 폰에서도 "오후 3시 12분"으로 나옵니다. 아이폰은 서식을 문구 키에 담았습니다.
- `GuardianMainActivity.applyMembers` 는 멤버 스냅샷이 올 때마다 `migrateLegacyFamilyData` 를 불러(`:208-212`) 이미 옮긴 가족도 매번 가족 문서를 한 번 더 읽습니다(`FamilyRepository.kt:447`).
- (단계 마무리·실기기에서 더 찾은 것이 있으면 여기에)

#### 그래서 지금

iOS 테스트 N개(5단계 끝 M개), 번역 대기 알려진 문제 0개(5단계까지 12개). 읽음 쓰기와 초대는 에뮬레이터에서만 확인했고, 실기기(운영)에서는 읽기 전용으로 알림·선택기·언어를 보았습니다. (실기기 비교 결과 한 줄) **안드로이드 `app/`·`firestore.rules` 는 한 줄도 안 바뀌었습니다.**
```

N·M 과 괄호 안 지시문은 실제 값·문장으로 바꾼다. 둘째 N 은 단계 마무리 Step 1 의 테스트 개수, M 은 선행 조건에서 적어 둔 개수다. `#### 14개 언어` 문단의 "문장 N개"는 `swift tools/check-i18n-keys.swift` 가 보고한 키 수(23)로 바꾼다.

"함께 고쳐야 하는 짝"(`README.md` 의 `### 함께 고쳐야 하는 짝`)을 이렇게 고친다:

```markdown
- **새 이벤트 타입** → `EventType` + `guardian/AlertAdapter.kt`의 `when`. 상수를 참조하면 컴파일러가 잡아줍니다(리터럴 쓰지 마세요). 아이폰은 `ios/KidCare/Core/Documents.swift`의 `EventType` + `ios/KidCare/Guardian/AlertText.swift`의 `title`·`look`.
- **화면 문장** → `i18n/<언어>.json` 을 고칩니다. 안드로이드는 `gen.py`, 아이폰은 `python3 tools/ios-strings.py`로 다시 뽑습니다. 키를 더하거나 빼면 `python3 tools/ios-strings.py --write-gaps` 로 번역 빈 칸 목록(`tools/i18n-untranslated.json`)도 함께 고칩니다. `Localizable.xcstrings` 는 손으로 고치지 않습니다.
- **초대 완료 판정** → 안드로이드 `GuardianPairingActivity`의 `baselineMemberUids`, 아이폰 `InviteSession.기준_멤버`. "발급 전에 있던 멤버 밖의 같은 역할"이 새 멤버라는 규칙을 둘 다 지킵니다.
```

`### 14개 언어 — 원본은 한 벌, 기본값은 영어 (2026-08-18)` 절의 "`strings.xml` 을 손으로 쓰지 않습니다" 문단 끝에 한 문장을 더한다:

```markdown
아이폰도 같은 원본에서 `python3 tools/ios-strings.py` 로 `ios/KidCare/Localizable.xcstrings` 를 만듭니다(2026-09-13). 번역이 없는 칸은 안드로이드처럼 영어로 나옵니다.
```

- [ ] **Step 5: 커밋**

```bash
cd /Users/com/work/KidCare
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew   # 비어 있어야 한다
git add README.md
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 6단계 Task 5: 실기기에서 읽기 전용으로 알림·선택기·언어를 보고 개발일지를 쓴다"
```

---

## 6단계 완료 기준

- [ ] 알림 탭이 안드로이드와 같은 순서·색·치수로 뜬다. 제약 한 줄 카드, 상태 줄, 사건 카드, 빈 목록 마스코트다.
- [ ] 보이는 순간의 안 읽은 사건이 살구빛으로 남고, 서버에는 `read` 한 필드만 쓰이며, 떠났다 돌아오면 그 사이 새로 온 것만 살구빛이다.
- [ ] 캐시본만 받은 동안 "없어요"라고 단언하지 않고, 구독 실패는 목록 위 한 줄로 나온다.
- [ ] 선택기 줄(지도 탭 제외)과 지도 카드 이름이 같은 메뉴를 열고, 아이를 바꾸면 탭 다섯이 새 아이로 다시 만들어지며 보던 탭이 남는다.
- [ ] 초대 두 줄이 번호 화면(뒤로 화살표 보임)을 열고, 새 번호·시간 초과·다시 시도가 안드로이드와 같으며, 아이가 들어오면 닫히고 선택된다(에뮬레이터).
- [ ] 지구본 버튼이 설정의 앱 페이지를 열고, 14개 언어 lproj 가 번들에 있으며, 빈 칸은 영어로 나온다.
- [ ] `withKnownIssue` 가 없고, 빈 칸이 `tools/i18n-untranslated.json` 과 정확히 같으며, `python3 tools/ios-strings.py --check` 가 0 이다.
- [ ] 실기기에서 읽기 전용으로 알림·선택기가 안드로이드와 같다(쓰기 없음, 초대 없음).
- [ ] 모든 새 리스너(사건, 멤버, 초대 감시)에 떼는 길이 있고, 푸시·FCM·권한 요청이 없다.
- [ ] `ios/KidCare/Logic/` 이 Foundation 만 import 하고, 앱 코드에 `@unchecked Sendable`·`nonisolated(unsafe)`·`navigationBarBackButtonHidden` 이 없다.
- [ ] `git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew` 가 비어 있다.

---

## 자기 검토 결과 (writing-plans self-review)

**설계서 대응.**
- §4 ① "알림 탭의 `AlertService` 스위치가 없다 — 제약을 한 줄로" → Task 1(`ios_alert_open_app_hint`), Task 2(`AlertView.제약_카드`). "14개 언어를 함께 채운다"는 브리프의 "번역을 지어내지 않는다"와 부딪혀 판정 기록 2·3 으로 갈랐다.
- §4 대응표 `AlertFragment`("살구빛 하이라이트와 `read` 한 필드만 쓰는 계약 그대로") → `AlertViewModel.강조`·`EventRepository.markRead`, 테스트 `살구빛은_연_순간을_붙든다`·`읽음은_한_필드`.
- §4 대응표 `GuardianMainActivity`("탭 컨테이너 · 아이 선택기 · 무응답 배너") → 판정 기록 7 의 두 겹(`GuardianHomeView` + `GuardianRootView`), Task 4. 배너는 4단계 그대로 안쪽에 남는다.
- §4 "알림 탭의 살구빛은 화면을 여는 순간의 안 읽은 ID를 따로 붙들어 칠한다" → Task 2 Step 5.
- §4 "탭을 바꿔도 지도를 다시 만들지 않는다" → 탭 전환에서는 그대로다. **아이를 바꿀 때만** 다시 만든다. 안드로이드도 그때 프래그먼트를 새로 만든다(`:288-300`).
- §5 "보호자는 합류한 뒤에도 자기가 코드를 발급할 수 있어야 한다" → Task 3·4.
- §7 다국어 → Task 1. §7 이 적은 네 가지 가운데 "1. `%1$s` → `%1$@`"과 "3. 키 유지"는 생성기가 한다. "2. 안드로이드 이스케이프 풀기"는 할 일이 없다 — 원본 JSON 에는 `\'` 가 없고 줄바꿈은 JSON 의 진짜 `\n` 이다(2026-09-13 확인, 역슬래시 0건). "4. iOS 전용 키를 원본에 먼저 추가"는 공통 절차 A 다. 설계서 §3 의 `Resources/Localizable.xcstrings` 경로는 코드(`ios/KidCare/Localizable.xcstrings`)를 따른다(설계서 머리말 "문서와 코드가 다르면 코드가 맞다").
- §8 오류 → 새 실패 문구가 모두 `errorMessage(_:)` 를 지난다(`alert_error_format`, `pairing_failed`). 오프라인은 `ListLoad`·`pairing_offline`(판정 기록 1, 단계 마무리 Step 4-10).
- §1 권한 0개·푸시 없음 → 알림 권한·서비스를 옮기지 않았다("다루지 않는 것"). 지구본은 설정 URL 을 열 뿐 권한을 묻지 않는다.
- §9 6단계 "알림 탭 · 아이 선택기 · 14개 언어 · 오프라인/예외 화면" → Task 1~4, 단계 마무리.
- 브리프 요구도 모두 대응했다.
  - Global Constraints 는 5단계 목록 + 6단계 추가분이다.
  - 리스너 제거 길은 각 뷰모델의 `정리한다()` 와 그 테스트다.
  - 생성기 서식 규칙은 `add-ios-catalog-keys.py` 와 같다(`assert` 세 줄 그대로 옮김).
  - 한국어 바이트 일치와 세 키 명시적 이전은 Task 1 Step 5 의 대조 스크립트다.
  - 번역 금지와 빈 칸 처리는 판정 3 이다.
  - `%@` 금지는 생성기와 `원본에는_iOS_서식이_없다` 가 지킨다.
  - `.id` 로 다시 만들기는 판정 7 이다.
  - 초대는 에뮬레이터에서만 확인한다(`InviteFlowTests`, 단계 마무리). 실기기는 초대하지 않는다(`ReadOnlyCheck`, Task 5).
  - 뒤로 버튼은 판정 8 이다.
  - Kotlin `file:line` 은 모든 코드 주석과 테스트 이름에 있다.
  - 지어낸 화면은 없다. 번호 화면은 `GuardianPairingActivity` 의 초대 갈래이고, 지구본은 안드로이드 버튼 자리다.

**자리표시 검사.** "TBD/적절히/나중에"는 없다. Task 5 Step 4 의 개발일지 틀에만 괄호 지시문 둘과 N·M 이 있다. 실행해야 알 수 있는 값(테스트 개수, 실기기 비교 결과, 단계 마무리에서 더 찾은 것)이다.

**타입·이름 일관성(고친 것 포함).**
- 테스트와 구현 대조:
  - `AlertViewModelTests` 는 `AlertViewModel(familyId:childUid:observe:markRead:)`, `시작한다`·`보임이_바뀌었다(_:)`·`정리한다`, `events`·`listLoad`·`상태_줄`·`강조`·`읽음_쓰는_중`·`빈_목록_문구` 를 쓴다. 모두 Step 5 구현에 있다.
  - `InviteSessionTests` 는 `InviteSession(familyId:role:create:fetch:observe:deviceNow:sleep:onJoined:)`, `시작한다`·`버튼을_눌렀다`·`정리한다`, `코드`·`만료_분`·`만료_문구`·`진행중`·`안내`·`버튼_문구`·`버튼_활성`·`제목`·`role` 을 쓴다.
  - `ChildSelectorModelTests` 는 `ChildSelectorModel(familyId:roleStore:membersObserve:inviteFactory:)`, `children`·`guardians`·`불러오기_실패`·`초대`·`selectedUid`·`줄_문구`·`지도_이름`·`보호자_초대_문구`·`라벨`·`시작한다`·`고른다`·`초대한다`·`정리한다` 를 쓴다.
- `InviteSession.Observe` 를 `ChildSelectorModel.membersObserve` 가 그대로 쓴다. 이름이 둘로 갈리지 않는다.
- 초안에서 고친 것은 넷이다.
  - `FamilyMember` 를 `Equatable` 로 선언했다가 `FamilyMembersTests` 가 `Set` 에 넣어 `Hashable` 로 바꿨다.
  - 초대 화면을 `InviteCodeView` 의 새 모드로 두려다, 소유자와 레이아웃이 달라 `GuardianInviteView` 로 나눴다(File Structure 반영).
  - `fullScreenCover(item:)` 은 `@MainActor` 클래스의 `Identifiable` 준수 문제를 피하려 `isPresented:` 바인딩으로 바꿨다.
  - `겹쳐_쓰지_않는다` 의 기다림 조건이 앞 스냅샷 값으로 이미 참일 수 있어 호출 횟수로 기다리게 바꿨다(`기록을_기다린다`).
- 시각 테스트의 밀리초는 파이썬으로 계산했다. 2026-09-13 15:12 KST = 1,789,279,920,000, 09-12 23:05 = 1,789,221,900,000, 09-13 00:30 = 1,789,227,000,000.
- 테스트 수 기대값(Task 2 는 22, Task 3 은 12, Task 4 는 10, Task 1 은 순증 5)은 각 코드 블록의 `@Test` 개수를 센 값이다.
- **실행 전에 확인이 필요한 가정 둘.** 둘 다 테스트가 잡고, 실패하면 멈추고 보고하게 적었다.
  - XcodeGen 스킴의 `test.language`/`test.region` 지원(Task 1 Step 6)
  - `CFBundleLocalizations` 만으로 14개 `lproj` 가 실리는지(`LocalizationBundleTests.열네_언어가_실린다`)

---

## Pre-flight conflict table

| 짝 | 함께 만지는 것 | 충돌 여부와 처리 |
|---|---|---|
| **5단계 Task 2(작업 중) ↔ 6단계 Task 2** | `Guardian/RuleListParts.swift` 의 `struct RuleStateLine { let text: String }`(15pt `inkSoft`, 좌우 20·위아래 16), `Guardian/KidCarePalette.swift` 의 `apricot`·`apricotSoft`·`berryInk`·`lineSoft`·`paperFold` | 5단계 계획서 Task 2 Interfaces(`:952`, `:955`)와 코드(`:1444-1454`, `:2141-2152`)의 이름이다. 2026-09-13 HEAD `64a95d2` 에는 아직 없다. 선행 조건 grep 으로 확인하고, 이름이 다르면 `AlertView` 의 두 곳과 `AlertText.look` 을 커밋된 이름으로 맞춘다. `berrySoft`·`grass`·`grassSoft`·`sky`·`skySoft` 는 4단계부터 있다 |
| **5단계 Task 3(작업 중) ↔ 6단계 Task 2** | `Assets.xcassets/Mascot3D.imageset`(`Image("Mascot3D")`) | 5단계 Task 3 이 만든다(`:2817`, `:4220-4222`). 없으면 5단계 Task 3 이 안 끝난 것이다. 6단계를 시작하지 않는다 |
| **5단계 Task 2·3 ↔ 6단계 Task 2·4** | `Guardian/GuardianRootView.swift` — `scheduleViewModel`·`placeViewModel`, 5단계 Task 2 Step 9 가 둔 `.onChange(of: scenePhase) { _, phase in guard phase == .active … }`, `TabPlaceholderView(tab: .alert)`, `@SceneStorage("guardian.selectedTab")` | 6단계 Task 2 는 알림 자리표시 한 덩어리를 바꾸고, `scenePhase` onChange 의 **첫 줄**에 한 줄을 넣고, `.onChange(of: selectedTab)` 를 더하고, `TabPlaceholderView` 를 지운다. 5단계가 매개변수 이름을 다르게 썼으면(`newPhase` 등) 그 이름을 넘긴다. Task 4 는 `@SceneStorage` 한 줄을 `@Binding` 으로 바꾸고 `init` 에 인자 하나를 더한다. 이름 `selectedTab` 이 같아서 5단계의 `if selectedTab == .schedule` 은 그대로 컴파일된다 |
| **5단계 Task 2·3 ↔ 6단계 Task 4** | 예약·장소 탭이 탭 안에 자기 `NavigationStack` 을 둔다(5단계 `:2255`, `:3908`) | 그래서 초대 화면을 바깥 push 가 아니라 `fullScreenCover` 로 띄운다(판정 기록 8). 바깥에 `NavigationStack` 을 새로 두지 않는다 |
| 5단계 전체 ↔ 6단계 Task 1 | `Localizable.xcstrings` — 5단계가 `tools/add-ios-catalog-keys.py` 로 넣은 `schedule_*`·`place_*`·`holiday_*`·`list_loading` 키 | Task 1 이 원본에서 통째로 다시 만든다. 5단계 키는 14개 파일에 모두 있으므로(5단계 계획서 공통 절차 A, 누락 0) 빈 칸에 더해지지 않는다. 한국어 값은 Step 5 대조 스크립트가 바이트까지 본다. Task 1 이 그 도구를 지우므로 **5단계가 모두 커밋된 뒤에** 시작한다 |
| 5단계 Task 2·3 테스트 ↔ 6단계 Task 1 | `ScheduleViewModelTests`·`PlaceViewModelTests`·`ControlViewModelTests` 가 `String(localized: "map_no_child")` 로 기대값을 만든다 | 값이 "아직 아이 폰이 연결되지 않았어요."로 바뀌어도 양쪽이 같은 키를 읽어 그대로 초록이다. 한국어 리터럴을 적은 테스트는 스킴 테스트 언어 `ko` 로 지킨다(`LocalizationBundleTests.테스트_언어는_한국어`) |
| 5단계 Task 1(`64a95d2`) ↔ 6단계 Task 2 | `Guardian/ListLoad.swift` 의 `ListLoad.after(fromCache:)`·`emptyText(isEmpty:loaded:)` | HEAD 에서 이름과 시그니처를 확인했다(2026-09-13) |
| 5단계 Task 4(README, 작업 전) ↔ 6단계 Task 5 | `README.md` 개발일지 자리 | 5단계 절 바로 다음에 둔다. 5단계 절이 없으면 6단계를 시작하지 않는다(선행 조건) |
| 5단계 작업 트리 상태 ↔ 6단계 시작 | 2026-09-13 `/Users/com/work/KidCare` 에 ` M ios/KidCare/KidCareApp.swift`(에뮬레이터 확인용 임시 변경으로 보인다) | 선행 조건 `git status --short` 가 비어 있어야 한다. 이 파일이 `configureForApp()` 로 돌아온 뒤 시작한다 |
| 4단계 통합 검토 M1 ↔ 6단계 Task 4 | `RouterView.swift:47-51` 의 `.id("\(familyId)\|\(childUid)")` | 두 겹으로 나눈다: `RouterView` 는 `.id(familyId)`, `GuardianHomeView` 는 안쪽 `GuardianRootView` 에 `.id(childUid ?? "")`. 가족·아이 어느 쪽이 바뀌어도 탭 뷰모델은 새로 생긴다 |
| 3단계 ↔ 6단계 Task 4 | `Guardian/StatusCardView.swift` 의 `Text(childName)` 네 줄 | 선택기가 환경에 있을 때만 메뉴로 바꾸고, 없으면 옛 줄 그대로다. 3단계 `StatusCardTests` 는 뷰를 그리지 않고 문구 함수만 보므로 영향이 없다 |
| 1단계 ↔ 6단계 Task 1 | `KidCareUITests/PairingUITests.swift` 의 "보호자"·"가족에 합류하기", `LocalizableCatalogTests.알려진_어긋남` | 원본 값으로 옮기고 테스트 글자와 `-AppleLanguages (ko)` 를 함께 고친다(판정 기록 4). UI 테스트는 실기기 전용 스킴이라 기본 테스트 명령으로는 돌지 않는다. 다음 실기기 페어링 때 새 글자로 돈다 |
| 1단계 ↔ 6단계 Task 1 | `FamilyRepository.createFamily`·`joinFamily` 의 저장 이름, `JoinFamilyView` 의 `displayName` | 글자 그대로("우리 가족", "보호자", "아이")로 바꾼다. `GuardianJoinTests` 등 기존 테스트에 `role_guardian`·`family_default_name` 기대값이 없음을 grep 으로 확인했다(2026-09-13) |
| 1단계 ↔ 6단계 Task 3 | `Onboarding/InviteCodeView.swift`·`NewFamilySession.swift` | 주석 세 줄만 바꾼다. 새 가족 갈래의 동작은 그대로다 |
| Task 1 ↔ Task 2 | `ios_alert_open_app_hint`·`alert_time_*_format` 키, `tools/i18n-untranslated.json` | 순서 의존. Task 2 는 `ios_tab_not_ready_body` 를 지우고 `--write-gaps` 로 목록을 한 번 더 쓴다 |
| Task 2 ↔ Task 4 | `ReadOnlyCheck.isOn`, `GuardianRootView` | Task 4 는 `ReadOnlyCheck` 를 읽기만 한다. `GuardianRootView` 는 Task 2 가 끝난 모양 위에 두 줄을 바꾼다 |
| Task 3 ↔ Task 4 | `FamilyMember`, `FamilyRepository.observeMembers`, `InviteSession`(`Observe`, `init`, `정리한다`, `role`), `GuardianInviteView` | 순서 의존 — Task 4 는 Task 3 이 커밋된 뒤에 컴파일된다 |
| Task 2~4 ↔ `LocalizableCatalogTests.코드가_부르는_키는_카탈로그에_있다` | 코드 리터럴 키 전부 | 6단계는 원본의 **모든** 키를 생성하므로, 코드가 부르는 키가 원본에 있기만 하면 카탈로그에도 있다. 새로 부르는 키는 Task 1 이 넣은 셋뿐이고, 나머지(`alert_*`, `child_selector_*`, `pairing_*`, `router_retry`, `language_picker_title`, `timeline_unknown_place`)는 14개 파일에 이미 있다(2026-09-13 확인: 빈 칸 21키에 들지 않는다) |
| Task 5 ↔ 전체 | `README.md` 만 | 코드 충돌 없음 |
