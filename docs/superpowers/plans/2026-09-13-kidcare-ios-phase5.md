# iOS 5단계 구현 계획 — 예약 탭과 장소 탭

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰 보호자 앱의 예약·장소 자리표시를 안드로이드 `ScheduleFragment`·`PlaceFragment` 와 같은 화면으로 채운다. 예약 탭에는 기본 모드 카드, 공휴일 스위치, 하루 띠가 달린 규칙 목록과 규칙 편집이 들어간다. 장소 탭에는 이름 첫 글자 스티커 목록과, 지도 한가운데 십자와 반경 원으로 고르는 장소 편집이 들어간다. 두 탭 모두 쓰기가 끝나면 `sync_rules` 명령을 보내고, 못 보냈으면 "아직 애기폰에 전달되지 않았어요" 줄을 남긴다.

**Architecture:** 두 탭의 뷰모델(`ScheduleViewModel`·`PlaceViewModel`, @MainActor @Observable)은 `GuardianRootView` 가 소유한다(4단계 판정 기록 2와 같은 수명). 판단은 전부 뷰모델에 있고 Firestore 쪽은 주입 클로저라서, 가짜 저장소로 UI 없이 테스트한다. 안드로이드의 "목록 판 ↔ 편집 판"(한 프래그먼트 안에서 판을 바꾸고 뒤로 가기를 가로챔)은 탭 안 `NavigationStack` 의 push 로 옮기고, 시스템 뒤로 버튼을 늘 보인다. 쓰기는 셋이다. 4단계 Task 3 의 `ScheduleRepository` 에 규칙·기본 모드·공휴일을 더하고, 새 `PlaceRepository` 를 만들고, 기존 `CommandRepository.send` 로 `sync_rules` 를 보낸다.

**Tech Stack:** Swift 6 / SwiftUI(`NavigationStack`, `Slider`, `DatePicker(.wheel)`, `.alert`) / Firebase Firestore 12.19.1 / NMapsMap 3.23.3(`NMFCircleOverlay`, `NMFMapViewCameraDelegate`) / Swift Testing. 새 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-12-kidcare-ios-design.md`. §4 탭별 대응표의 `ScheduleFragment`("하루 띠 UI · 공휴일 스위치 · 저장 후 `SYNC_RULES` 전송")와 `PlaceFragment`("지도 한가운데를 좌표로 삼는 방식 그대로") 두 행, §4 "색과 치수는 안드로이드 리소스에서 그대로", §5 손 매핑, §9 5단계 "예약 탭 · 장소 탭 — 하루 띠 UI와 지도 위 반경 고르기".

**선행 조건:** 4단계 Task 3·4 는 커밋됐다(`8e9ebc6`, `0b0a5f1`, 보완 `5209a6e`). 이 계획서는 그 커밋이 실제로 만든 이름을 쓴다. 4단계 계획서와 달라진 점은 `.superpowers/sdd/2026-09-13-kidcare-ios-phase4/task-3-4-report.md` 에 있고, 이 계획서에 반영한 것은 맨 아래 Pre-flight conflict table 에 적었다. 시작 전에 이름이 그대로인지 확인한다(4단계 통합 리뷰가 이름을 바꿨을 수 있다):

```bash
cd /Users/com/work/KidCare
git log --oneline | grep -E "4단계 Task (3|4)"        # 세 줄 이상 나와야 한다
git log --oneline | grep "4단계 Fix round"              # 4단계 통합 검토(I1·I2·M1·M2·M3) 수정이 커밋돼 있어야 한다
git status --short                                     # 비어 있어야 한다
grep -n "static func observeRingerSettings\|private static func ringerSettingsRef\|private static var db" ios/KidCare/Core/ScheduleRepository.swift   # 세 줄
grep -n "func firstToFinish" ios/KidCare/Guardian/FirstToFinish.swift                                                                            # 한 줄
grep -n "static func date(minuteOfDay\|static func minuteOfDay" ios/KidCare/Guardian/ControlView.swift                                           # 두 줄
grep -n "static let vibrate\|struct RingerSettingsDoc" ios/KidCare/Core/Documents.swift                                                          # 두 줄
```

하나라도 다르면 Pre-flight conflict table 의 해당 행을 먼저 처리한다.

## Global Constraints

4단계 계획서 브리프에서 그대로 옮긴 것(verbatim):

- Swift 6 strict concurrency, iOS 17.0, SwiftUI, XcodeGen (`ios/project.yml`; never hand-edit the xcodeproj), Swift Testing. `ios/KidCare/Logic/` imports Foundation only. No `@unchecked Sendable` or `nonisolated(unsafe)` in app code.
- Android `app/`, `firestore.rules` and `gradlew` are not modified. Android defects found go into the README dev log only.
- No push notifications and no FCM (the Firebase Spark free plan). Every Firestore listener has a removal path on disappear.
- i18n: new keys are added to **both** `i18n/ko.json` and `i18n/en.json` and are regenerated into `Localizable.xcstrings` the way earlier phases did (find the mechanism, e.g. `tools/check-i18n-keys.swift` and the existing parity tests, and state the exact command). `%@` is never used in `i18n/*.json`. A literal `%` must be `%%` in format strings. **Never borrow a string key from an unrelated screen** (this was rejected twice).
- Tests never write to production Firestore. Emulator tests use `configureForEmulator(projectId: "kidcare-emulator")` (Auth 127.0.0.1:9099, Firestore 8080), and `KidCareApp.init()` must call `configureForApp()` at commit time.
- Commits are in Korean, author `Yongminlee2 <dydals5678@gmail.com>`, with no Co-Authored-By trailer and no AI traces.
- Test command: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`.

5단계 브리프가 더한 것:

- **보이는 뒤로 가기.** push 되는 화면(규칙 편집, 장소 편집)은 모두 **시스템 뒤로 버튼이 보인다.** 아이폰에서 주인이 요구한 것이다. `.navigationBarBackButtonHidden` 은 쓰지 않는다. 장소 편집에서는 네이버 지도가 화면 가장자리 밀기 제스처를 삼킬 수 있으므로, 지도는 내비게이션 바를 덮지 않는 260pt 칸 안에만 두고(`fragment_place.xml:231-234`) 뒤로 버튼으로 늘 나갈 수 있게 한다.
- **진짜 가족 보호.** 규칙·장소를 만들고 고치고 지우는 동작은 진짜 가족 문서에 쓴다. 이 쓰기는 **에뮬레이터에서만** 확인한다. 실기기 Task 는 목록을 열어 보기만 하고 저장하지 않는다.
- **푸시 알림도 FCM 도 쓰지 않는다.** 장소 도착·이탈 알림은 안드로이드에서 이미 Firestore 이벤트로 보호자에게 간다. 이 단계는 보호자 **화면**이 하는 일(장소 정하기)만 옮기고, 알림을 받거나 보여주는 쪽은 만들지 않는다.

이 저장소에서 이어지는 규칙:

- **정본은 안드로이드다.** `guardian/ScheduleFragment.kt`(1,206줄), `guardian/ScheduleAdapter.kt`(`ScheduleText` 포함), `guardian/ScheduleSyncStore.kt`, `guardian/PlaceFragment.kt`(981줄), `guardian/PlaceAdapter.kt`(`PlaceText` 포함), `guardian/PlaceSyncStore.kt`, `guardian/ListLoadState.kt`, `core/ScheduleRepository.kt`, `core/PlaceRepository.kt`, `core/model/Documents.kt`, `res/layout/fragment_schedule.xml`·`item_schedule.xml`·`fragment_place.xml`·`item_place.xml`, `res/color/day_chip_*.xml`, `res/drawable/ic_map_crosshair.xml`. 이 계획서가 코틀린과 다르면 코틀린이 맞다. 상수는 인용한 줄에서 **그대로** 옮긴다.
- 색과 치수는 안드로이드 리소스 값을 그대로 쓴다(`res/values/colors.xml`, `themes.xml`, `dimens.xml`). sp·dp 는 pt 로 1:1 옮긴다. 글자 크기는 `themes.xml:125-148` 의 KidCare 텍스트 스타일(HeadlineSmall 24 medium, TitleMedium 18 medium, BodyLarge 17, BodyMedium 15, BodySmall 13, LabelLarge 15 medium)을 따른다.
- 주석은 **한국어로 '왜'** 를 적는다. 커밋 전에 `KidCareApp.init()` 이 `FirebaseBootstrap.configureForApp()` 을 부르는지 `git diff ios/KidCare/KidCareApp.swift` 로 확인한다.
- 실행 전 PATH: `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"`
- 파일을 새로 만들었으면 테스트 전에 `cd ios && xcodegen generate` 를 돌린다(`.xcodeproj` 는 커밋하지 않는다).
- 에뮬레이터는 저장소 루트에서 `firebase emulators:start --only auth,firestore --project kidcare-emulator` 로 띄운다. 에뮬레이터를 쓰는 스위트는 기존처럼 `init() async { await EmulatorHarness.start() }` 로 시작한다.

## 공통 절차 A — 문구 키를 카탈로그에 넣는 법

4단계 공통 절차 A 와 같은 방식이다. 설계서 §7 의 `tools/ios-strings.py` 는 아직 없으므로(6단계 몫) `i18n/ko.json` 의 한국어 값을 `ios/KidCare/Localizable.xcstrings` 에 명령으로 옮긴다. 이미 있는 키는 **건너뛴다**.

**4단계 명령에서 고친 것 하나.** 4단계의 변환 정규식 `%(\d+\$)?(\d+)?([sd])` 는 소수 서식을 몰라 `%1$.1f` 를 `%%1$.1f` 로 망가뜨렸다. 아래 정규식은 너비와 정밀도를 둘 다 받고 `f` 는 그대로 둔다. 순서(위치 → 너비 → 정밀도 → 변환)는 `ios/KidCareTests/LocalizableCatalogTests.swift:19` 의 `#/%(\d+\$)?(\d+)?(\.\d+)?([sdf])/#` 와 **같다**. 둘이 다르면 그 테스트가 빨개진다.

| `i18n/*.json` | `Localizable.xcstrings` |
|---|---|
| `%1$s` | `%1$@` |
| `%1$d`, `%1$02d`, `%1$.1f` | 그대로 |
| 서식이 아닌 `%` | `%%` |

```bash
cd /Users/com/work/KidCare && KEYS="여기에 키를 공백으로" python3 - <<'EOF'
import json, os, re
FORMAT = re.compile(r'%(\d+\$)?(\d+)?(\.\d+)?([sdf])')
def conv(v):
    out, i = [], 0
    while i < len(v):
        if v[i] != '%':
            out.append(v[i]); i += 1; continue
        m = FORMAT.match(v, i)
        if m:
            conversion = '@' if m.group(4) == 's' else m.group(4)
            out.append('%' + (m.group(1) or '') + (m.group(2) or '') + (m.group(3) or '') + conversion)
            i = m.end()
        elif v.startswith('%%', i):
            out.append('%%'); i += 2
        else:
            out.append('%%'); i += 1
    return ''.join(out)
assert conv('%1$.1fkm') == '%1$.1fkm', conv('%1$.1fkm')
assert conv('%1$02d:%2$02d') == '%1$02d:%2$02d'
assert conv('배터리 %1$d%') == '배터리 %1$d%%'
assert conv("'%1$s' 외 %2$d개") == "'%1$@' 외 %2$d개"
ko = json.load(open('i18n/ko.json', encoding='utf-8'))
path = 'ios/KidCare/Localizable.xcstrings'
cat = json.load(open(path, encoding='utf-8'))
for k in os.environ['KEYS'].split():
    if k in cat['strings']:
        continue
    cat['strings'][k] = {"extractionState": "manual", "localizations": {"ko": {"stringUnit": {"state": "translated", "value": conv(ko[k])}}}}
cat['strings'] = dict(sorted(cat['strings'].items()))
open(path, 'w', encoding='utf-8').write(json.dumps(cat, indent=2, ensure_ascii=False) + '\n')
EOF
```

`assert` 넷은 명령 자체를 검사한다. 하나라도 걸리면 파일을 쓰기 전에 멈춘다.

**4단계 통합 검토 M3 판정**은 이 고친 명령을 `tools/` 의 재사용 스크립트로 두게 했다. 수정 라운드가 그 스크립트를 만들었으면(`ls tools/` — 2026-09-13 작업 트리에 커밋 전 `tools/add-ios-catalog-keys.py` 가 보였다) **그 스크립트를 부른다.** 위 python 은 스크립트가 같은 결과를 내는지 대조할 때만 쓴다. 두 결과가 다르면 멈추고 보고한다.

검사 둘:

- `swift tools/check-i18n-keys.swift` — 14개 언어의 키 집합을 비교한다. **이 단계는 `i18n/*.json` 에 키를 하나도 더하지 않는다.** 쓰는 `schedule_*`·`place_*`·`holiday_*`·`list_loading` 키는 14개 파일에 이미 전부 있다(2026-09-13 확인, 누락 0). 그래서 출력은 4단계 끝과 **글자 하나 다르지 않아야 한다.** 종료 코드 1 은 1~4단계 키 때문에 여전히 정상이다.
- `LocalizableCatalogTests` — 카탈로그 값이 위 변환대로 `ko.json` 에서 나왔는지, 앱 코드가 쓰는 키가 전부 카탈로그에 있는지를 본다.

## 공통 절차 B — 커밋

```bash
cd /Users/com/work/KidCare
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew   # 비어 있어야 한다
git diff ios/KidCare/KidCareApp.swift                            # 비어 있어야 한다(configureForApp)
grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|navigationBarBackButtonHidden" ios/KidCare   # 비어 있어야 한다
git add <이 Task 의 파일들>
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "<한국어 메시지>"
```

## 이 단계에서 다루지 않는 것

- **아이 선택기와 `observeChildJoined` 재구독.** 4단계 판정 기록 1과 같다. 설계서 §9 는 아이 선택기를 6단계에 둔다. 이 단계도 `RoleStore.childUid` 하나를 쓴다. 그래서 두 프래그먼트의 `joinedListener`(`ScheduleFragment.kt:391-407`, `PlaceFragment.kt:393-407`)와 거기서 부르는 재시도·아이 위치 다시 읽기는 6단계로 넘긴다.
- **알림 탭과 장소 도착·이탈 알림 목록**은 6단계 몫이다. 푸시는 만들지 않는다(설계서 §1).
- **옛 1:1 가족 경로**(`families/{f}/schedules`, `families/{f}/places`)는 보지 않는다. 안드로이드 보호자 화면의 구독(`ScheduleRepository.kt:113-129`, `PlaceRepository.kt:77-93`)도 자녀 경로만 본다. 옛 경로로 물러나는 `fetch*` 는 자녀 폰만 쓴다.
- **화면 회전·프로세스 복원**(`onSaveInstanceState`, `rebindTimePickers`)은 옮기지 않는다. 앱은 세로 고정이고(`project.yml` 의 `UISupportedInterfaceOrientations`), 편집 중인 값은 `GuardianRootView` 수명의 뷰모델에 있어 복원할 대상이 없다.
- **규칙별 공휴일 예외**는 만들지 않는다. 안드로이드에도 없다(README "알려진 제약").
- 14개 언어(6단계)와 다크 모드.

## 판정 기록 — 이 계획서가 내린 결정

1. **범위.** 설계서 §9 는 5단계를 "예약 탭 · 장소 탭 — 하루 띠 UI와 지도 위 반경 고르기"로 적는다. 브리프와 같다. 기본 모드 카드(README "규칙이 끝나도 안 돌아오던 문제", `fragment_schedule.xml:23-149`)와 공휴일 스위치(README "공휴일엔 예약을 쉬어요", `:151-219`)는 지금 안드로이드 예약 탭에 실제로 있으므로 함께 옮긴다. 격자 통일과 밀도 조정(README 2026-08-18 두 절)이 끝난 **지금의** 레이아웃 값을 옮긴다. 목록 판에는 화면 제목도 부제도 없다.
2. **편집 판은 push 로 옮긴다. 새 화면을 지어내지 않는다.** 안드로이드에는 별도 추가·편집 화면이 없다. 한 프래그먼트 안에 판 둘을 겹쳐 두고(`fragment_schedule.xml:3-9`, `fragment_place.xml:3-9`) 뒤로 가기를 가로채 목록으로 돌아간다(`ScheduleFragment.kt:265-271`, `PlaceFragment.kt:219-223`). 부모 눈에는 "목록 → 편집 → 뒤로 가면 목록"이다. iOS 에서 같은 경험을 주는 수단은 탭 안 `NavigationStack` 의 push 이고, 판 내용과 순서는 XML 그대로다. 탭 바는 안드로이드처럼 편집 중에도 보인다.
3. **저장 중의 뒤로 가기.** 안드로이드는 쓰기가 도는 동안 취소와 뒤로 가기를 막는다(`ScheduleFragment.kt:443-460`, `PlaceFragment.kt:487-493, 860-868`). iOS 시스템 뒤로 버튼은 숨기지 않고는 막을 수 없는데, 숨기는 것은 주인이 금했다. 그래서 **뒤로 가기는 늘 된다.** 편집 판 안의 '취소' 버튼만 안드로이드처럼 잠근다. 막으려던 사고 둘은 이렇게 따로 막는다.
   - *늦게 돌아온 쓰기가 새로 연 편집기를 닫는 것.* 뒤로 가면 세대를 올린다(`cancelEditor` 와 같다). 늦은 결과는 편집기를 절대 만지지 않는다. 대신 그 쓰기의 **실패와 '서버 확인 안 됨'은 목록 줄이 이어받는다.** 조용히 사라지는 실패는 이 앱에서 가장 나쁜 실패이기 때문이다. 그 사이 다른 쓰기가 시작됐으면 그 쓰기가 줄의 주인이다.
   - *같은 우선순위가 두 번 나가는 것.* `lastAssignedPriority`(`:171-181`)가 쓰기 **전에** 동기로 올라가므로, 뒤로 간 뒤 곧바로 새 규칙을 저장해도 우선순위가 겹치지 않는다. 테스트로 못박는다.
4. **편집 판 제목.** 안드로이드 편집 판 제목은 본문 맨 위의 HeadlineSmall 글자다(`fragment_schedule.xml:333-337`, `fragment_place.xml:161-165`). iOS 도 본문에 두고, 내비게이션 바는 뒤로 버튼만 보이는 인라인 바로 둔다. 목록 판은 내비게이션 바를 숨긴다(판정 1).
5. **시각 고르기.** 안드로이드는 24시간 `MaterialTimePicker` 대화상자에 `schedule_editor_start_title`·`schedule_editor_end_title` 제목을 붙인다(`ScheduleFragment.kt:981-999`). iOS 는 살구빛 시각 버튼(`fragment_schedule.xml:555-591`)을 누르면 같은 제목과 `en_GB`(24시간) 바퀴 `DatePicker` 가 든 시트를 띄운다. 확인·취소 버튼은 시스템 문구라 새 키가 필요하므로 두지 않는다. 고른 값은 곧바로 반영되고, 시트는 끌어내려 닫는다. 4단계 판정 기록 6과 같은 이유다. 분 ↔ 날짜 변환은 4단계 Task 4 의 `ControlInput.date(minuteOfDay:)`·`minuteOfDay(_:)` 를 그대로 쓴다.
6. **문서 본문의 `"id": ""`.** 안드로이드 `saveSchedule`·`savePlace` 는 `ref.set(doc.copy(id = ""))` 로 데이터 클래스를 통째로 넘긴다(`ScheduleRepository.kt:73-82`, `PlaceRepository.kt:60-67`). `ScheduleDoc`·`PlaceDoc` 에 `@Exclude` 가 없으므로(`Documents.kt` 전체에 `Exclude`·`DocumentId` 0건) Firestore 는 모든 프로퍼티를 직렬화한다. 그래서 **본문에 `"id": ""` 가 실린다.** 그 줄의 주석("본문에는 담지 않는다")은 코드와 다르다. 스키마의 정본은 코드이므로(설계서 머리말) iOS 도 같은 일곱 필드를 쓴다. 규칙은 이 세 컬렉션에 `hasOnly` 를 걸지 않는다(`firestore.rules:208-230`). 안드로이드 주석 불일치는 개발일지에만 적는다.
7. **"못 보낸 알림" 깃발의 저장 자리와 재시도 경로.** 안드로이드는 prefs 파일 둘(`kidcare_schedule_sync`, `kidcare_place_sync`)에 같은 키 `pending_sync_<uid>` 를 쓴다. iOS 는 `UserDefaults.standard` 하나를 쓰므로 `schedule_sync_pending_sync_<uid>`·`place_sync_pending_sync_<uid>` 로 접두사를 붙인다(4단계 판정 기록 7과 같은 이유). 두 깃발을 합치지 않는 이유는 `PlaceSyncStore.kt:12-21` 에 있다. 재시도를 부르는 자리는 이렇게 옮긴다.
   - `onHiddenChanged(false)`(탭을 다시 누름)와 첫 `onResume` → 그 탭 뷰의 `.onAppear`. `TabView` 는 탭을 보일 때마다 `onAppear` 를 부른다.
   - `onResume`(앱으로 돌아옴) → `GuardianRootView` 의 `scenePhase == .active` 이면서 그 탭이 선택돼 있을 때.
   - '다시 알리기' 버튼 → 그대로.
   - `onJoined` → 6단계(위 "다루지 않는 것").
8. **지도 좌표를 정하는 순간.** 안드로이드는 지도에 손가락이 닿는 순간(`ACTION_DOWN`) `coordinateChosen` 을 세우고 부모 스크롤의 가로채기를 막는다(`PlaceFragment.kt:242-257`). 카메라가 멈추면(`OnCameraIdle`) 가운데를 좌표로 적되, 프로그램이 옮긴 멈춤은 깃발로 걸러낸다(`:151-161, 274-283, 520-533`). iOS 에서는 이렇게 옮긴다.
   - **손이 닿는 순간:** 지속시간 0인 `UILongPressGestureRecognizer`(다른 제스처와 동시 인식)를 붙인다. `.began` 에서 좌표를 골랐다고 표시하고, 편집 판 `ScrollView` 를 `.scrollDisabled(true)` 로 잠근다(`requestDisallowInterceptTouchEvent` 자리). `.ended` 에서 풀어준다.
   - **프로그램 이동 거르기:** 깃발 대신 네이버 SDK 가 알려주는 **카메라 이동 원인**을 쓴다. `cameraWillChangeByReason` 의 `NMFMapChangedByGesture`(-1, `NMFCameraUpdate.h:24`)일 때만 멈춤을 좌표로 받는다. 이벤트가 같은 프레임에 오는지 다음 프레임에 오는지에 기대지 않아도 된다.
   - **손이 닿는 순간의 가운데를 곧바로 좌표로 적는다.** 안드로이드는 이때 깃발만 세우고 좌표는 멈춤 이벤트를 기다린다. 그래서 끌지 않고 톡 건드리기만 한 뒤 저장하면, 멈춤 이벤트가 오지 않는 한 편집 좌표가 (0,0)으로 남을 수 있다. 코드로만 본 가능성이고 실기기로 확인하지 않았으므로 개발일지에 "확인 필요"로 적는다. iOS 는 터치 순간 `cameraPosition.target` 을 좌표로 적어 이 틈을 닫는다.
9. **편집 지도의 수명.** 안드로이드 `MapView` 는 프래그먼트 뷰와 수명이 같아서, 편집 판을 닫았다 열어도 지도 객체가 남는다. iOS 는 편집 화면을 push 할 때 만들고 pop 할 때 버린다. 설계서 §4 의 "탭을 바꿔도 지도를 다시 만들지 않는다"는 지도 탭 규칙이고, 이 단계에서도 지킨다. 편집 화면을 열어 둔 채 다른 탭을 보고 돌아오면 `NavigationStack` 경로가 살아 있어 지도가 그대로다. 편집을 새로 열 때마다 타일을 받는 비용은 받아들인다(장소 편집은 드문 일이다).
10. **정렬·반올림·해시는 코틀린의 뜻 그대로 옮긴다.** 이름·ID 정렬은 코틀린 `String.compareTo` 처럼 UTF-16 코드 단위로 비교한다(Swift `<` 는 유니코드 스칼라 순서라 이모지·전각 문자에서 갈린다). 반경 눈금 맞추기와 표기는 `Math.round`(= `floor(x + 0.5)`)로 한다(Swift `.rounded()` 는 음수 .5 에서 갈린다). 장소 스티커 색은 자바 `String.hashCode()` 를 32비트 넘침까지 그대로 옮긴 `floorMod(hash, 4)` 로 고른다(`PlaceAdapter.kt:69-72`). 하나라도 다르면 같은 장소가 두 부모 폰에서 다른 순서·다른 색·다른 반경으로 보인다. 세 함수는 `Logic/KotlinMath.swift` 에 모으고 자바에서 알려진 값으로 테스트한다.
11. **스티커 글자.** 코틀린 `firstOrNull()` 은 UTF-16 한 칸이라 이모지로 시작하는 이름에서 반쪽 글자를 그린다. iOS 는 첫 **글자**(grapheme)를 쓴다. 한글·영문 이름에서는 두 폰의 결과가 같다. 안드로이드 쪽 결함은 개발일지에만 적는다. 이름 20자 제한(`fragment_place.xml:187`)도 같은 이유로 글자 단위로 센다. 한글 음절은 UTF-16 한 칸이라 결과가 같다.
12. **마스코트 그림.** 빈 장소 목록은 `mascot_3d`(768×768 PNG, `drawable-nodpi`)를 쓴다(`fragment_place.xml:111-116`). iOS 자산에는 아직 없다. `app/` 의 파일을 **읽어서 복사만** 하고(안드로이드 파일은 바뀌지 않는다) `Assets.xcassets/Mascot3D.imageset` 으로 넣는다. 눈대중으로 다른 그림을 고르지 않는다(README "화면을 새로 만들거나 고칠 때" — 마스코트는 `mascot_3d` 하나).
13. **그림 대응.** 벡터를 새로 그리지 않고 SF Symbol 을 쓴다. 소리 모드 셋은 **관리 탭이 이미 고른 이름을 그대로 쓴다.** 벨소리 `speaker.wave.2.fill`, 진동 `iphone.radiowaves.left.and.right`, 무음 `speaker.slash.fill` 이다(`ControlView.swift` `모드_버튼들`, `ControlViewModel.소리_상태_아이콘`). 안드로이드 예약 탭은 `ic_bell_ring`·`ic_phone_shake`·`ic_bell_off` 를 쓰지만(`ScheduleAdapter.kt:222-231`), 한 앱 안에서 같은 모드가 탭마다 다른 그림이면 부모가 "다른 것"으로 읽는다. 나머지는 모르는 모드 `ic_alarm` → `alarm`, `ic_holiday` → `calendar`, `ic_trash` → `trash`, `ic_add` → `plus` 다. 지도 십자 `ic_map_crosshair` 는 SF Symbol 이 없으므로 XML 의 획(흰 6 위에 `#4A4038` 2.5, 48 격자)을 `Canvas` 로 그대로 그린다. 참고로 XML 주석은 이 색이 `@color/ink` 와 같다고 하지만 `ink` 는 `#342D3F` 다. 값은 XML 의 `#4A4038` 을 따른다.
14. **아이가 없을 때의 쓰기.** 안드로이드는 쓰기마다 `childUid == null` 이면 `schedule_no_family`·`place_no_family` 를 보인다. 아이가 없으면 `subscribe` 가 목록을 비워 두어 사실상 닿지 않는 갈래지만, 문구와 함께 그대로 옮긴다. `notifyChild` 의 "아이 없음 → 깃발 내림" 갈래(`ScheduleFragment.kt:905-912`)도 같이 옮긴다.

---

## File Structure

```
ios/KidCare/
├─ Logic/
│  └─ KotlinMath.swift               신규. roundToInt·javaHashCode·floorMod·UTF-16 순서(판정 10)
├─ Core/
│  ├─ Documents.swift                수정. CommandType.syncRules, ScheduleDoc, PlaceDoc
│  ├─ ScheduleRepository.swift       수정(4단계 Task 3 파일). 규칙 저장·삭제·구독, 기본 모드·공휴일 병합
│  └─ PlaceRepository.swift          신규. 안드로이드 PlaceRepository 짝
├─ Assets.xcassets/Mascot3D.imageset 신규. mascot_3d.png 복사(판정 12)
└─ Guardian/
   ├─ KidCarePalette.swift           수정. apricot·apricotSoft·onApricotSoft·berryInk·line·lineSoft·paperFold
   ├─ ListLoad.swift                 신규. 안드로이드 ListLoadState 짝
   ├─ RuleSyncStore.swift            신규. ScheduleSyncStore·PlaceSyncStore 짝
   ├─ RuleListParts.swift            신규. 두 목록이 함께 쓰는 줄·막대·버튼
   ├─ ScheduleText.swift             신규. ScheduleText·하루 띠 조각
   ├─ ScheduleViewModel.swift        신규. 예약 탭 두뇌
   ├─ ScheduleView.swift             신규. 목록 판·규칙 줄·기본 모드·공휴일 카드
   ├─ ScheduleEditorView.swift       신규. 편집 판
   ├─ PlaceText.swift                신규. PlaceText
   ├─ PlaceViewModel.swift           신규. 장소 탭 두뇌
   ├─ PlaceView.swift                신규. 목록 판·장소 줄
   ├─ PlaceEditorView.swift          신규. 편집 판
   ├─ PlacePickerMapView.swift       신규. 편집 지도·반경 원·십자
   └─ GuardianRootView.swift         수정. 예약·장소 자리표시 → 두 뷰, 수명·재시도 연결
ios/KidCareTests/
├─ KotlinMathTests.swift             신규
├─ RuleDocumentsTests.swift          신규
├─ ListLoadTests.swift               신규
├─ RuleSyncStoreTests.swift          신규
├─ RuleRepositoryTests.swift         신규(에뮬레이터)
├─ RuleTestDoubles.swift             신규. 쓰기 제한시간 가짜
├─ ScheduleTextTests.swift           신규
├─ ScheduleViewModelTests.swift      신규
├─ PlaceTextTests.swift              신규
└─ PlaceViewModelTests.swift         신규
ios/KidCare/Localizable.xcstrings    수정. 공통 절차 A(키 추가만, i18n/*.json 은 그대로)
README.md                            수정(Task 4). 개발일지·함께 고쳐야 하는 짝
```

Task 는 넷이다. 각 Task 끝에서 테스트로 확인할 수 있는 결과가 나온다.

| Task | 끝나면 |
|---|---|
| 1 | 규칙·장소 문서가 안드로이드와 같은 필드로 에뮬레이터에 쓰이고 읽힌다. 깃발·빈 목록 판정·코틀린 수학이 테스트로 고정된다 |
| 2 | 예약 탭이 안드로이드와 같은 화면으로 뜨고, 뷰모델 테스트가 저장·겹침·하루 종일·우선순위·깃발·뒤로 가기를 못박는다 |
| 3 | 장소 탭과 지도 반경 고르기가 뜨고, 뷰모델 테스트가 좌표·반경·상한·깃발·뒤로 가기를 못박는다 |
| 단계 마무리 | 통합 리뷰 한 번, 에뮬레이터를 붙인 시뮬레이터 확인 한 번 |
| 4 | 실기기에서 목록만 열어 보고, 개발일지를 쓴다 |

---
### Task 1: 규칙·장소 문서와 저장소 — 안드로이드가 쓰는 필드 그대로

**끝나면 규칙과 장소가 안드로이드와 같은 일곱 필드로 에뮬레이터에 쓰이고, 구독이 캐시본인지 서버본인지까지 알려준다.** 기본 모드와 공휴일은 `settings/ringer` 에 한 필드씩 병합되고 관리 탭의 잠금을 지우지 않는다. 화면 변화는 없다. 두 탭이 함께 쓰는 판정 셋(빈 목록 문구, 못 보낸 알림 깃발, 코틀린 수학)도 여기서 테스트로 고정한다.

**Files:**
- Create: `ios/KidCare/Logic/KotlinMath.swift`
- Modify: `ios/KidCare/Core/Documents.swift` (`CommandType.syncRules`, 파일 끝에 `ScheduleDoc`·`PlaceDoc`)
- Modify: `ios/KidCare/Core/ScheduleRepository.swift` (enum 본문 끝에 규칙·기본 모드·공휴일)
- Create: `ios/KidCare/Core/PlaceRepository.swift`
- Create: `ios/KidCare/Guardian/ListLoad.swift`, `ios/KidCare/Guardian/RuleSyncStore.swift`
- Modify: `ios/KidCare/Localizable.xcstrings` (`list_loading`)
- Test: `ios/KidCareTests/KotlinMathTests.swift`, `RuleDocumentsTests.swift`, `ListLoadTests.swift`, `RuleSyncStoreTests.swift`, `RuleRepositoryTests.swift`(에뮬레이터)

**Interfaces:**
- Consumes: 4단계 Task 3 의 `ScheduleRepository`(`private static var db`, `private static func ringerSettingsRef(familyId:childUid:)`, `setRingerLock`, `observeRingerSettings`), `RingerMode`, `RingerSettingsDoc(_:)`, `EmulatorHarness.ChildSession`·`freshChildSession()`·`joinAsChild(_:familyId:joinCode:)`; 1단계의 `FamilyRepository.createFamily(guardianUid:)`·`createInvite(familyId:role:previousCode:)`, `ScheduleRule`(2단계)
- Produces:
  - `enum KotlinMath { static func roundToInt(_ x: Double) -> Int; static func javaHashCode(_ s: String) -> Int32; static func floorMod(_ x: Int32, _ m: Int) -> Int; static func precedes(_ a: String, _ b: String) -> Bool }`
  - `CommandType.syncRules`
  - `struct ScheduleDoc: Equatable { var id, days, startMinute, endMinute, mode, enabled, priority; init(id:days:startMinute:endMinute:mode:enabled:priority:); init(id: String, _ data: [String: Any]); var firestoreData: [String: Any]; var asRule: ScheduleRule }`
  - `struct PlaceDoc: Equatable { var id, name, lat, lng, radiusMeters, notifyEnter, notifyExit; init(id:name:lat:lng:radiusMeters:notifyEnter:notifyExit:); init(id: String, _ data: [String: Any]); var firestoreData: [String: Any] }`
  - `ScheduleRepository.saveSchedule(familyId:childUid:doc:) async throws -> String`, `deleteSchedule(familyId:childUid:id:)`, `setDefaultMode(familyId:childUid:mode:)`, `setHolidayOff(familyId:childUid:enabled:)`, `observeSchedules(familyId:childUid:onChange:onError:) -> ListenerRegistration`
  - `enum PlaceRepository { savePlace(familyId:childUid:doc:) async throws -> String; deletePlace(familyId:childUid:id:); observePlaces(familyId:childUid:onChange:onError:) -> ListenerRegistration }`
  - `enum ListLoad: Equatable { case loading, loaded, failed; static func after(fromCache:) -> ListLoad; func emptyText(isEmpty:loaded:) -> String? }`
  - `struct RuleSyncStore { enum Kind: String { case schedule, place }; init(kind:defaults:); func pendingSync(childUid:) -> Bool; func setPendingSync(childUid:_:) }`

**정본:** `core/ScheduleRepository.kt:34-37, 73-107, 109-129, 147-162`, `core/PlaceRepository.kt:37-40, 56-93`, `core/model/Documents.kt:222`(SYNC_RULES), `:348-369`(ScheduleDoc), `:371-396`(PlaceDoc), `guardian/ListLoadState.kt` 전체, `guardian/ScheduleSyncStore.kt`·`PlaceSyncStore.kt` 전체, `guardian/PlaceAdapter.kt:69-72, 107`(해시·반올림).

**규칙 확인(`firestore.rules`).** 이 Task 가 새로 만드는 쓰기는 다섯이다. 전부 기존 규칙으로 허용되고, 규칙은 바꾸지 않는다.
- `children/{c}/schedules/{id}` set·delete — `:224-230` "보호자이고 `isChildMember(familyId, childUid)`". `hasOnly` 없음. 일곱 필드(판정 기록 6).
- `children/{c}/places/{id}` set·delete — `:216-222`, 조건은 같다.
- `children/{c}/settings/ringer` 에 `{"defaultMode": String}`·`{"holidayOff": Bool}` 를 **각각 한 필드씩** `merge: true` 로 쓴다 — `:208-214`. 통째로 덮으면 관리 탭의 `lockEnabled` 가 기본값으로 돌아간다(`ScheduleRepository.kt:88-92`).
- 읽기: 보호자와 그 아이 본인 — `:209-210, 217-218, 225-226`.

- [ ] **Step 1: 코틀린 수학 테스트를 먼저 쓴다**

`ios/KidCareTests/KotlinMathTests.swift`:

```swift
import Testing
@testable import KidCare

/// 정렬·반올림·해시는 코틀린·자바 표준 함수의 뜻을 그대로 따라야 한다(계획서 판정 기록 10).
/// 기대값은 자바에서 알려진 값이다 — "polygenelubricants".hashCode() 가 Int.MIN_VALUE 인 것은
/// 자바 문서·Stack Overflow 에서 널리 인용되는 넘침 사례다.
struct KotlinMathTests {

    @Test("String.hashCode — UTF-16 단위에 31 을 곱해 더하고 32비트로 넘친다")
    func 자바_해시() {
        #expect(KotlinMath.javaHashCode("") == 0)
        #expect(KotlinMath.javaHashCode("a") == 97)
        #expect(KotlinMath.javaHashCode("학교") == 1_737_495)
        #expect(KotlinMath.javaHashCode("polygenelubricants") == Int32.min)
        #expect(KotlinMath.javaHashCode("3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f") == 1_153_660_321)
    }

    @Test("Math.floorMod — 음수 해시도 0..<m 로 떨어진다(PlaceAdapter.kt:71)")
    func 바닥_나머지() {
        #expect(KotlinMath.floorMod(Int32.min, 4) == 0)
        #expect(KotlinMath.floorMod(-1, 4) == 3)
        #expect(KotlinMath.floorMod(1_737_495, 4) == 3)
    }

    @Test("roundToInt = Math.round = floor(x + 0.5) — 음수 .5 에서 Swift rounded() 와 갈린다")
    func 반올림() {
        #expect(KotlinMath.roundToInt(1.5) == 2)
        #expect(KotlinMath.roundToInt(0.5) == 1)
        #expect(KotlinMath.roundToInt(-1.5) == -1)
        #expect(KotlinMath.roundToInt(200.4) == 200)
        #expect(KotlinMath.roundToInt(200.5) == 201)
    }

    @Test("String.compareTo — UTF-16 단위 순서라 이모지(D83D…)가 전각 A(FF21)보다 앞선다")
    func 문자열_순서() {
        #expect(KotlinMath.precedes("가게", "학원"))
        #expect(KotlinMath.precedes("Zoo", "가게"))
        #expect(KotlinMath.precedes("😀", "Ａ"))
        #expect(!KotlinMath.precedes("Ａ", "😀"))
        #expect(!KotlinMath.precedes("같다", "같다"))
    }
}
```

- [ ] **Step 2: 문서·빈 목록·깃발 테스트를 쓴다**

`ios/KidCareTests/RuleDocumentsTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `Documents.kt:348-396` 과 `ScheduleRepository.kt:73-82`·`PlaceRepository.kt:60-67`.
struct RuleDocumentsTests {

    @Test("예약 문서는 안드로이드가 실제로 쓰는 일곱 필드 그대로다 — id 는 본문에 빈 값(판정 기록 6)")
    func 예약_필드() {
        let doc = ScheduleDoc(id: "r1", days: [1, 2, 3, 4, 5], startMinute: 1260, endMinute: 420,
                              mode: RingerMode.vibrate, enabled: false, priority: 3)
        let data = doc.firestoreData
        #expect(Set(data.keys) == ["id", "days", "startMinute", "endMinute", "mode", "enabled", "priority"])
        #expect(data["id"] as? String == "")
        #expect(data["days"] as? [Int] == [1, 2, 3, 4, 5])
        #expect(data["startMinute"] as? Int == 1260)
        #expect(data["enabled"] as? Bool == false)
        #expect(data["priority"] as? Int == 3)
    }

    @Test("필드가 빠진 예약 문서는 코틀린 기본값으로 읽는다 — enabled 는 true, 본문의 id 는 무시")
    func 예약_기본값() {
        let doc = ScheduleDoc(id: "r2", [
            "id": "",
            "days": [NSNumber(value: 7), NSNumber(value: 6)],
            "startMinute": NSNumber(value: 540),
        ])
        #expect(doc == ScheduleDoc(id: "r2", days: [7, 6], startMinute: 540, endMinute: 0, mode: "", enabled: true, priority: 0))
        #expect(doc.asRule == ScheduleRule(id: "r2", days: [6, 7], startMinute: 540, endMinute: 0, mode: "", enabled: true, priority: 0))
    }

    @Test("장소 문서 일곱 필드, 빠진 알림 스위치는 켜짐, 빠진 반경은 0(안 정해짐)")
    func 장소() {
        let doc = PlaceDoc(id: "p1", name: "학교", lat: 37.5, lng: 127.0, radiusMeters: 200, notifyEnter: true, notifyExit: false)
        let data = doc.firestoreData
        #expect(Set(data.keys) == ["id", "name", "lat", "lng", "radiusMeters", "notifyEnter", "notifyExit"])
        #expect(data["id"] as? String == "")
        #expect(data["radiusMeters"] as? Double == 200)
        #expect(data["notifyExit"] as? Bool == false)

        let 옛_문서 = PlaceDoc(id: "p2", ["name": "학원", "lat": NSNumber(value: 37), "lng": NSNumber(value: 127.25)])
        #expect(옛_문서 == PlaceDoc(id: "p2", name: "학원", lat: 37, lng: 127.25, radiusMeters: 0, notifyEnter: true, notifyExit: true))
    }

    @Test("sync_rules 명령 이름은 안드로이드와 같다(Documents.kt:222)")
    func 명령_이름() {
        #expect(CommandType.syncRules == "sync_rules")
    }
}
```

`ios/KidCareTests/ListLoadTests.swift`:

```swift
import Testing
@testable import KidCare

/// 정본은 안드로이드 `guardian/ListLoadState.kt`. 못 불러온 화면과 정말 빈 화면이 같은 말을
/// 하지 않게 하는 판정이다(:13-18).
struct ListLoadTests {

    @Test("캐시본은 불러오는 중으로 접는다 — 오프라인은 네 번째 상태가 아니다(:23-39)")
    func 캐시본() {
        #expect(ListLoad.after(fromCache: true) == .loading)
        #expect(ListLoad.after(fromCache: false) == .loaded)
    }

    @Test("빈 목록 문구는 서버가 확인한 뒤에만 '없어요'라고 말하고, 실패면 자리를 감춘다(:80-97)")
    func 빈_목록_문구() {
        #expect(ListLoad.loading.emptyText(isEmpty: true, loaded: "없음") == String(localized: "list_loading"))
        #expect(ListLoad.loaded.emptyText(isEmpty: true, loaded: "없음") == "없음")
        #expect(ListLoad.failed.emptyText(isEmpty: true, loaded: "없음") == nil)
        #expect(ListLoad.loaded.emptyText(isEmpty: false, loaded: "없음") == nil)
    }
}
```

`ios/KidCareTests/RuleSyncStoreTests.swift`:

```swift
import Testing
@testable import KidCare

/// 정본은 안드로이드 `ScheduleSyncStore.kt`·`PlaceSyncStore.kt`.
struct RuleSyncStoreTests {

    @Test("깃발은 저장소에 남아 앱을 다시 켜도 그대로다 — 뒤로 가기를 넘기려고 프로세스 밖에 둔다(ScheduleSyncStore.kt:15-23)")
    func 남는다() {
        let defaults = TestDefaults.isolated("RuleSyncStoreTests")
        #expect(!RuleSyncStore(kind: .schedule, defaults: defaults).pendingSync(childUid: "c"))
        RuleSyncStore(kind: .schedule, defaults: defaults).setPendingSync(childUid: "c", true)
        #expect(RuleSyncStore(kind: .schedule, defaults: defaults).pendingSync(childUid: "c"))
        #expect(!RuleSyncStore(kind: .schedule, defaults: defaults).pendingSync(childUid: "other"))
    }

    @Test("예약 깃발과 장소 깃발은 서로를 지우지 않는다(PlaceSyncStore.kt:12-21)")
    func 따로다() {
        let defaults = TestDefaults.isolated("RuleSyncStoreTests-kind")
        let schedule = RuleSyncStore(kind: .schedule, defaults: defaults)
        let place = RuleSyncStore(kind: .place, defaults: defaults)
        schedule.setPendingSync(childUid: "c", true)
        place.setPendingSync(childUid: "c", true)
        schedule.setPendingSync(childUid: "c", false)
        #expect(place.pendingSync(childUid: "c"))
    }
}
```

- [ ] **Step 3: 에뮬레이터 테스트를 쓴다**

`ios/KidCareTests/RuleRepositoryTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 규칙·장소·설정 쓰기를 에뮬레이터에서 확인한다. 보안 규칙(firestore.rules:208-230)도 함께 태운다.
/// 자녀 세션은 4단계 Task 3 이 `EmulatorHarness` 로 옮긴 도우미를 쓴다.
@Suite(.serialized)
struct RuleRepositoryTests {

    init() async { await EmulatorHarness.start() }

    private func 가족과_자녀() async throws -> (familyId: String, child: EmulatorHarness.ChildSession) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)
        return (familyId, child)
    }

    private func 자녀_문서(_ db: Firestore, _ familyId: String, _ childUid: String) -> DocumentReference {
        db.collection("families").document(familyId).collection("children").document(childUid)
    }

    /// 구독 콜백이 넘겨준 것 중 테스트가 보는 값만 담는다(ID 목록과 캐시본 여부).
    private actor 스냅샷_기록 {
        private(set) var 마지막: (ids: [String], fromCache: Bool)?
        func 기록(_ ids: [String], _ fromCache: Bool) { 마지막 = (ids, fromCache) }
    }

    @Test("규칙 저장은 일곱 필드로 쓰이고, 구독은 서버가 확인한 스냅샷을 fromCache=false 로 준다")
    func 규칙_저장과_구독() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let 기록 = 스냅샷_기록()
        let listener = ScheduleRepository.observeSchedules(
            familyId: familyId, childUid: child.uid,
            onChange: { docs, fromCache in
                let ids = docs.map(\.id)
                Task { await 기록.기록(ids, fromCache) }
            },
            onError: { _ in }
        )
        defer { listener.remove() }

        let id = try await ScheduleRepository.saveSchedule(
            familyId: familyId, childUid: child.uid,
            doc: ScheduleDoc(id: "", days: [1, 2, 3, 4, 5], startMinute: 1260, endMinute: 420,
                             mode: RingerMode.vibrate, enabled: true, priority: 1)
        )
        #expect(!id.isEmpty)
        let data = try #require(try await 자녀_문서(Firestore.firestore(), familyId, child.uid)
            .collection("schedules").document(id).getDocument(source: .server).data())
        #expect(Set(data.keys) == ["id", "days", "startMinute", "endMinute", "mode", "enabled", "priority"])
        try await 기다린다 {
            let 마지막 = await 기록.마지막
            return 마지막?.ids == [id] && 마지막?.fromCache == false
        }
    }

    @Test("같은 ID 로 두 번 저장하면 규칙은 하나다 — 편집을 열 때 ID 를 정해 두는 이유(ScheduleFragment.kt:151-160)")
    func 두_번_저장() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let doc = ScheduleDoc(id: "fixed", days: [6, 7], startMinute: 540, endMinute: 600, mode: RingerMode.silent, enabled: true, priority: 1)
        try await ScheduleRepository.saveSchedule(familyId: familyId, childUid: child.uid, doc: doc)
        try await ScheduleRepository.saveSchedule(familyId: familyId, childUid: child.uid, doc: doc)
        let snapshot = try await 자녀_문서(Firestore.firestore(), familyId, child.uid)
            .collection("schedules").getDocuments(source: .server)
        #expect(snapshot.documents.map(\.documentID) == ["fixed"])

        try await ScheduleRepository.deleteSchedule(familyId: familyId, childUid: child.uid, id: "fixed")
        let 지운_뒤 = try await 자녀_문서(Firestore.firestore(), familyId, child.uid)
            .collection("schedules").getDocuments(source: .server)
        #expect(지운_뒤.documents.isEmpty)
    }

    @Test("기본 모드·공휴일은 한 필드씩 병합한다 — 관리 탭의 lockEnabled 를 지우지 않는다(ScheduleRepository.kt:88-107)")
    func 설정_병합() async throws {
        let (familyId, child) = try await 가족과_자녀()
        try await ScheduleRepository.setRingerLock(familyId: familyId, childUid: child.uid, enabled: true)
        try await ScheduleRepository.setDefaultMode(familyId: familyId, childUid: child.uid, mode: RingerMode.silent)
        try await ScheduleRepository.setHolidayOff(familyId: familyId, childUid: child.uid, enabled: true)

        let data = try #require(try await 자녀_문서(Firestore.firestore(), familyId, child.uid)
            .collection("settings").document("ringer").getDocument(source: .server).data())
        #expect(data["lockEnabled"] as? Bool == true)
        #expect(data["defaultMode"] as? String == RingerMode.silent)
        #expect(data["holidayOff"] as? Bool == true)
        #expect(Set(data.keys) == ["lockEnabled", "defaultMode", "holidayOff"])
    }

    @Test("장소 저장은 일곱 필드, 삭제하면 사라진다")
    func 장소_저장과_삭제() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let id = try await PlaceRepository.savePlace(
            familyId: familyId, childUid: child.uid,
            doc: PlaceDoc(id: "", name: "학교", lat: 37.5665, lng: 126.978, radiusMeters: 200, notifyEnter: true, notifyExit: false)
        )
        let ref = 자녀_문서(Firestore.firestore(), familyId, child.uid).collection("places").document(id)
        let data = try #require(try await ref.getDocument(source: .server).data())
        #expect(Set(data.keys) == ["id", "name", "lat", "lng", "radiusMeters", "notifyEnter", "notifyExit"])
        #expect(data["name"] as? String == "학교")

        try await PlaceRepository.deletePlace(familyId: familyId, childUid: child.uid, id: id)
        #expect(try await ref.getDocument(source: .server).exists == false)
    }

    @Test("아이는 자기 규칙·장소를 읽을 수 있지만 쓸 수는 없다(firestore.rules:216-230)")
    func 아이는_읽기만() async throws {
        let (familyId, child) = try await 가족과_자녀()
        _ = try await PlaceRepository.savePlace(
            familyId: familyId, childUid: child.uid,
            doc: PlaceDoc(id: "p", name: "학교", lat: 37.5, lng: 127, radiusMeters: 200)
        )
        let 자녀_경로 = 자녀_문서(child.db, familyId, child.uid)
        let 읽음 = try await 자녀_경로.collection("places").getDocuments(source: .server)
        #expect(읽음.documents.count == 1)

        await #expect(throws: (any Error).self) {
            try await 자녀_경로.collection("places").document("p").setData(["radiusMeters": 0], merge: true)
        }
        await #expect(throws: (any Error).self) {
            try await 자녀_경로.collection("schedules").document("s").setData(ScheduleDoc(id: "s").firestoreData)
        }
    }

    private func 기다린다(timeoutSeconds: Double = 5, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("조건이 \(timeoutSeconds)초 안에 참이 되지 않았다")
    }
}
```

- [ ] **Step 4: 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/KotlinMathTests -only-testing:KidCareTests/RuleDocumentsTests -only-testing:KidCareTests/ListLoadTests -only-testing:KidCareTests/RuleSyncStoreTests`
Expected: 컴파일 실패. `KotlinMath`·`ScheduleDoc`·`PlaceDoc`·`ListLoad`·`RuleSyncStore`·`CommandType.syncRules` 가 없다.

- [ ] **Step 5: 코틀린 수학**

`ios/KidCare/Logic/KotlinMath.swift`:

```swift
import Foundation

/// 코틀린·자바 표준 함수 넷의 뜻을 그대로 옮긴다(계획서 판정 기록 10).
///
/// 왜 따로 두는가: 장소 목록의 순서, 스티커 색, 반경 표기는 안드로이드 보호자 폰과 아이폰 보호자
/// 폰이 **나란히 보는** 값이다. Swift 의 가장 가까운 함수(`<`, `.rounded()`, `hashValue`)는 뜻이
/// 조금씩 달라서, 이모지 이름이나 음수 .5 같은 드문 입력에서 두 폰이 다른 그림을 그린다. 그런 어긋남은
/// 코드를 봐서는 안 보이므로 한 곳에 모으고 자바에서 알려진 값으로 테스트한다.
enum KotlinMath {

    /// `Double.roundToInt()` = `Math.round(double)` = `floor(x + 0.5)`.
    /// Swift `.rounded()` 는 `-1.5` 를 `-2` 로 보내지만 자바는 `-1` 이다.
    static func roundToInt(_ x: Double) -> Int {
        Int((x + 0.5).rounded(.down))
    }

    /// `String.hashCode()` — `s[0]*31^(n-1) + … + s[n-1]` 을 UTF-16 코드 단위로, 32비트 넘침 그대로.
    static func javaHashCode(_ s: String) -> Int32 {
        var hash: Int32 = 0
        for unit in s.utf16 {
            hash = hash &* 31 &+ Int32(unit)
        }
        return hash
    }

    /// `Math.floorMod(int, int)` — 결과가 늘 `0..<m` 이다(자바 `%` 는 음수를 돌려준다).
    static func floorMod(_ x: Int32, _ m: Int) -> Int {
        let r = Int(x) % m
        return r < 0 ? r + m : r
    }

    /// `String.compareTo` 의 "앞선다" — UTF-16 코드 단위 사전순. Swift `<` 는 유니코드 스칼라 순서라
    /// 보조 평면 문자(이모지)와 U+E000 이상 문자 사이에서 순서가 뒤집힌다.
    static func precedes(_ a: String, _ b: String) -> Bool {
        a.utf16.lexicographicallyPrecedes(b.utf16)
    }
}
```

- [ ] **Step 6: 문서**

`ios/KidCare/Core/Documents.swift` 의 `enum CommandType` 본문 끝(4단계 Task 3 이 더한 `errorAlarmExactDenied` 아래)에 더한다:

```swift
    /// 예약·장소를 바꾼 뒤 보낸다. 자녀 폰이 받으면 규칙과 장소를 **둘 다** 다시 읽고 알람·지오펜스를
    /// 다시 건다(child/CommandHandler.kt:174-177). 정본은 `Documents.kt:222`.
    static let syncRules = "sync_rules"
```

같은 파일 끝에 더한다:

```swift
/// children/{childUid}/schedules/{id} — 시간대 규칙 하나. 정본은 안드로이드 `ScheduleDoc`
/// (Documents.kt:348-369). 필드 이름·기본값이 그대로다. 필드가 빠진 옛 문서는 코틀린
/// `toObject` 처럼 기본값으로 읽는다 — 특히 `enabled` 의 기본값은 true 다.
///
/// [id] 는 문서 ID 다. 본문의 `id` 필드는 읽지 않는다(안드로이드도 `copy(id = doc.id)` 로 덮는다).
struct ScheduleDoc: Equatable {
    var id: String
    /// 1=월 … 7=일(`ScheduleRule.days` 와 같은 규칙). Firestore 는 배열을 목록으로 주므로 Set 이 아니다.
    var days: [Int]
    var startMinute: Int
    var endMinute: Int
    var mode: String
    var enabled: Bool
    /// 만든 순서대로 자동 부여한다. 화면에 절대 내보이지 않는다(ScheduleFragment.kt:75-79).
    var priority: Int

    init(id: String = "", days: [Int] = [], startMinute: Int = 0, endMinute: Int = 0,
         mode: String = "", enabled: Bool = true, priority: Int = 0) {
        self.id = id
        self.days = days
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.mode = mode
        self.enabled = enabled
        self.priority = priority
    }

    init(id: String, _ data: [String: Any]) {
        self.id = id
        days = (data["days"] as? [Any] ?? []).compactMap { element in millis(element).map { Int($0) } }
        startMinute = Int(millis(data["startMinute"]) ?? 0)
        endMinute = Int(millis(data["endMinute"]) ?? 0)
        mode = data["mode"] as? String ?? ""
        enabled = data["enabled"] as? Bool ?? true
        priority = Int(millis(data["priority"]) ?? 0)
    }

    /// 안드로이드 `saveSchedule` 은 `ref.set(doc.copy(id = ""))` 로 데이터 클래스를 통째로 넘기고,
    /// `@Exclude` 가 없어 Firestore 가 `id` 까지 직렬화한다. 그 줄 주석("본문에는 담지 않는다")과
    /// 달리 **본문에 `"id": ""` 가 실린다**(계획서 판정 기록 6). 스키마의 정본은 코드이므로 같은
    /// 일곱 필드를 쓴다.
    var firestoreData: [String: Any] {
        [
            "id": "",
            "days": days,
            "startMinute": startMinute,
            "endMinute": endMinute,
            "mode": mode,
            "enabled": enabled,
            "priority": priority,
        ]
    }

    /// `ScheduleDoc.toRule()`(ScheduleRepository.kt:154-162) — 겹침 판정은 순수 모델로 한다.
    var asRule: ScheduleRule {
        ScheduleRule(id: id, days: Set(days), startMinute: startMinute, endMinute: endMinute,
                     mode: mode, enabled: enabled, priority: priority)
    }
}

/// children/{childUid}/places/{id} — 부모가 정한 장소 하나. 정본은 안드로이드 `PlaceDoc`
/// (Documents.kt:371-396).
///
/// [radiusMeters] 의 기본값 0 은 "안 정해졌다"는 뜻이다. 자녀 폰은 그런 장소를 지오펜스로 걸지
/// 않는다. 그럴듯한 200 을 기본으로 넣으면 필드가 빠진 문서가 부모가 정하지 않은 반경으로 조용히
/// 동작한다(:380-383).
struct PlaceDoc: Equatable {
    var id: String
    var name: String
    var lat: Double
    var lng: Double
    var radiusMeters: Double
    var notifyEnter: Bool
    var notifyExit: Bool

    init(id: String = "", name: String = "", lat: Double = 0, lng: Double = 0,
         radiusMeters: Double = 0, notifyEnter: Bool = true, notifyExit: Bool = true) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lng = lng
        self.radiusMeters = radiusMeters
        self.notifyEnter = notifyEnter
        self.notifyExit = notifyExit
    }

    init(id: String, _ data: [String: Any]) {
        self.id = id
        name = data["name"] as? String ?? ""
        lat = double(data["lat"]) ?? 0
        lng = double(data["lng"]) ?? 0
        radiusMeters = double(data["radiusMeters"]) ?? 0
        notifyEnter = data["notifyEnter"] as? Bool ?? true
        notifyExit = data["notifyExit"] as? Bool ?? true
    }

    /// `savePlace` 도 `ref.set(doc.copy(id = ""))` 라 본문에 `"id": ""` 가 실린다(ScheduleDoc 과 같다).
    var firestoreData: [String: Any] {
        [
            "id": "",
            "name": name,
            "lat": lat,
            "lng": lng,
            "radiusMeters": radiusMeters,
            "notifyEnter": notifyEnter,
            "notifyExit": notifyExit,
        ]
    }
}
```

`millis`·`double` 은 같은 파일 위쪽의 `private` 도우미라서, 같은 파일 안에 두어야 쓸 수 있다.

- [ ] **Step 7: 저장소**

`ios/KidCare/Core/ScheduleRepository.swift` 의 `enum ScheduleRepository` 본문 **끝 `}` 바로 앞**에 더한다. `db`·`ringerSettingsRef` 가 `private` 라 같은 본문 안이어야 한다. 파일 머리 주석의 "예약 규칙(schedules/)은 5단계가 이 파일에 더한다"는 "5단계가 더했다"로 고친다.

```swift
    // MARK: - 예약 규칙과 규칙 바탕 설정 (5단계). 정본은 ScheduleRepository.kt:34-37, 73-129.

    private static func schedules(familyId: String, childUid: String) -> CollectionReference {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("schedules")
    }

    /// id 가 비어 있으면 새 문서를, 아니면 그 ID 에 덮어쓴다(:73-82). 보호자 화면은 늘 ID 를 정해서
    /// 넘긴다 — 저장이 두 번 나가도 규칙이 둘 생기지 않게(ScheduleFragment.kt:151-160).
    ///
    /// 오프라인이면 서버 확인이 올 때까지 안 돌아온다. 부르는 쪽이 `firstToFinish` 로 15초를 건다.
    @discardableResult
    static func saveSchedule(familyId: String, childUid: String, doc: ScheduleDoc) async throws -> String {
        let collection = schedules(familyId: familyId, childUid: childUid)
        let ref = doc.id.isEmpty ? collection.document() : collection.document(doc.id)
        try await ref.setData(doc.firestoreData)
        return ref.documentID
    }

    static func deleteSchedule(familyId: String, childUid: String, id: String) async throws {
        try await schedules(familyId: familyId, childUid: childUid).document(id).delete()
    }

    /// 빈 문자열이면 "규칙이 없는 시간에는 아무것도 강제하지 않는다"(:98-102). `setRingerLock` 과 같은
    /// 이유로 **이 필드 하나만** 병합한다.
    static func setDefaultMode(familyId: String, childUid: String, mode: String) async throws {
        try await ringerSettingsRef(familyId: familyId, childUid: childUid)
            .setData(["defaultMode": mode], merge: true)
    }

    static func setHolidayOff(familyId: String, childUid: String, enabled: Bool) async throws {
        try await ringerSettingsRef(familyId: familyId, childUid: childUid)
            .setData(["holidayOff": enabled], merge: true)
    }

    /// 정렬 없이 준다(문서 ID 순). `fromCache` 는 캐시본인지를 알려준다 — 화면이 캐시본으로
    /// "없어요"라고 단언하지 않게 하려는 것이다(ListLoadState.kt:23-39). 그래서 메타데이터 변화도
    /// 받는다(`MetadataChanges.INCLUDE`, :119).
    static func observeSchedules(
        familyId: String,
        childUid: String,
        onChange: @escaping (_ docs: [ScheduleDoc], _ fromCache: Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        schedules(familyId: familyId, childUid: childUid)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error { onError(error); return }
                let docs = snapshot?.documents.map { ScheduleDoc(id: $0.documentID, $0.data()) } ?? []
                onChange(docs, snapshot?.metadata.isFromCache ?? true)
            }
    }
```

`ios/KidCare/Core/PlaceRepository.swift`:

```swift
import FirebaseFirestore
import Foundation

/// 장소(places/). 정본은 안드로이드 `core/PlaceRepository.kt` — `ScheduleRepository` 와 같은 모양이다.
///
/// 보호자 화면만 구독한다. 자녀 폰은 한 번 읽기만 하는데(:14-27), 그 갈래는 이 앱(보호자 전용)에 없다.
/// 쓰기는 보호자만 허용된다(firestore.rules:216-222).
enum PlaceRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static func places(familyId: String, childUid: String) -> CollectionReference {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("places")
    }

    /// 만들기와 고치기가 한 경로다(:56-67). 화면은 늘 ID 를 정해서 넘긴다.
    @discardableResult
    static func savePlace(familyId: String, childUid: String, doc: PlaceDoc) async throws -> String {
        let collection = places(familyId: familyId, childUid: childUid)
        let ref = doc.id.isEmpty ? collection.document() : collection.document(doc.id)
        try await ref.setData(doc.firestoreData)
        return ref.documentID
    }

    static func deletePlace(familyId: String, childUid: String, id: String) async throws {
        try await places(familyId: familyId, childUid: childUid).document(id).delete()
    }

    /// `observeSchedules` 와 같은 계약(:73-93). 돌려받은 등록은 보호자 화면이 사라질 때 remove 한다.
    static func observePlaces(
        familyId: String,
        childUid: String,
        onChange: @escaping (_ docs: [PlaceDoc], _ fromCache: Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        places(familyId: familyId, childUid: childUid)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error { onError(error); return }
                let docs = snapshot?.documents.map { PlaceDoc(id: $0.documentID, $0.data()) } ?? []
                onChange(docs, snapshot?.metadata.isFromCache ?? true)
            }
    }
}
```

- [ ] **Step 8: 빈 목록 판정과 깃발**

`ios/KidCare/Guardian/ListLoad.swift`:

```swift
import Foundation

/// 목록 화면 셋(예약·장소, 6단계의 알림)이 함께 쓰는 "빈 목록" 판정. 정본은 안드로이드
/// `guardian/ListLoadState.kt`.
///
/// 목록이 비었다는 사실만 보고 "없어요"를 띄우면, 못 불러온 화면과 정말 빈 화면이 **같은 말을
/// 한다**(:13-18). 부모는 가운데 큰 글씨를 읽고 "아직 없구나"로 이해하는데 진실은 "아무것도 못
/// 읽었다"다. 그래서 세 상태를 나눈다.
enum ListLoad: Equatable {
    /// 첫 스냅샷을 아직 못 받았다. 캐시본만 받은 상태(오프라인)도 여기다(:43-51).
    case loading
    /// 서버가 확인해 준 스냅샷을 받았다. 비어 있다면 정말 비어 있다.
    case loaded
    /// 못 불러왔다. 이유는 목록 위 한 줄이 이미 말하므로 빈 자리는 통째로 비운다(:59-63).
    case failed

    /// 캐시본으로는 `loaded` 로 올리지 않는다 — 오프라인은 네 번째 상태가 아니다(:23-39).
    static func after(fromCache: Bool) -> ListLoad {
        fromCache ? .loading : .loaded
    }

    /// 빈 목록 자리에 쓸 문구. nil 이면 그 자리를 감춘다(:80-97). [loaded] 는 `loaded` 일 때만 쓴다.
    func emptyText(isEmpty: Bool, loaded: @autoclosure () -> String) -> String? {
        guard isEmpty, self != .failed else { return nil }
        return self == .loaded ? loaded() : String(localized: "list_loading")
    }
}
```

`ios/KidCare/Guardian/RuleSyncStore.swift`:

```swift
import Foundation

/// "규칙(또는 장소)을 바꿨는데 아직 아이 폰에 `sync_rules` 를 확실히 못 보냈다" 깃발. 정본은 안드로이드
/// `guardian/ScheduleSyncStore.kt`·`PlaceSyncStore.kt`.
///
/// 이 깃발이 없으면 조용히 고장 난다. 자녀 폰이 다음 경계에 깨어나는 유일한 수단은 알람 하나인데,
/// 그걸 다시 걸게 하는 신호가 `sync_rules` 다. 규칙은 저장됐는데 명령만 못 나가면 부모는 정해 뒀다고
/// 믿고, 아이 폰은 옛 규칙(또는 이미 지운 장소의 지오펜스)대로 돈다(ScheduleSyncStore.kt:6-13).
///
/// 뷰모델이 아니라 저장소에 두는 이유는 안드로이드와 같다. 앱이 꺼져도 남아서, 다음에 탭을 열 때
/// 한 번 더 보내야 하기 때문이다(:15-23).
struct RuleSyncStore {

    enum Kind: String {
        /// 안드로이드 prefs 파일 `kidcare_schedule_sync`(ScheduleSyncStore.kt:31).
        case schedule
        /// 안드로이드 prefs 파일 `kidcare_place_sync`(PlaceSyncStore.kt:25). 두 깃발을 합치지 않는
        /// 이유는 그 파일 :12-21.
        case place
    }

    let kind: Kind
    private let defaults: UserDefaults

    init(kind: Kind, defaults: UserDefaults = .standard) {
        self.kind = kind
        self.defaults = defaults
    }

    func pendingSync(childUid: String) -> Bool {
        defaults.bool(forKey: key(childUid))
    }

    func setPendingSync(childUid: String, _ value: Bool) {
        defaults.set(value, forKey: key(childUid))
    }

    /// 안드로이드는 파일이 둘이라 키 `pending_sync_<uid>` 가 겹쳐도 되지만, iOS 는 `RoleStore`·
    /// `RequestLog`·`AlarmMemoStore` 와 같은 저장소 하나를 쓰므로 종류를 앞에 붙인다(판정 기록 7).
    private func key(_ childUid: String) -> String {
        "\(kind.rawValue)_sync_pending_sync_\(childUid)"
    }
}
```

- [ ] **Step 9: 카탈로그**

공통 절차 A 로 `KEYS="list_loading"` 을 넣는다.

- [ ] **Step 10: 통과 확인**

에뮬레이터를 띄운 채로:

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/KotlinMathTests -only-testing:KidCareTests/RuleDocumentsTests -only-testing:KidCareTests/ListLoadTests -only-testing:KidCareTests/RuleSyncStoreTests -only-testing:KidCareTests/RuleRepositoryTests -only-testing:KidCareTests/ScheduleRepositoryTests -only-testing:KidCareTests/LocalizableCatalogTests`
Expected: 새 스위트 다섯이 모두 PASS 한다. `KotlinMathTests` 4, `RuleDocumentsTests` 4, `ListLoadTests` 2, `RuleSyncStoreTests` 2, `RuleRepositoryTests` 5 다. 4단계 `ScheduleRepositoryTests` 3개도 그대로 PASS 해야 한다(같은 파일에 더했으므로).

`RuleRepositoryTests.아이는_읽기만` 이 규칙을 정말 태우는지는 에뮬레이터 규칙을 잠시 `allow write: if true` 로 바꿔 빨개지는지 보는 식으로 확인할 수 있다. 다만 **`firestore.rules` 파일은 고치지 않는다.** 1단계 개발일지 "규칙을 꺼도 초록인 테스트는 규칙을 증명하지 않습니다"에 적힌 방법대로, 에뮬레이터 UI 의 규칙 편집에서만 해 보고 되돌린다. 이 확인은 선택이다.

- [ ] **Step 11: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Logic/KotlinMath.swift ios/KidCare/Core/Documents.swift ios/KidCare/Core/ScheduleRepository.swift \
  ios/KidCare/Core/PlaceRepository.swift ios/KidCare/Guardian/ListLoad.swift ios/KidCare/Guardian/RuleSyncStore.swift \
  ios/KidCare/Localizable.xcstrings ios/KidCareTests/KotlinMathTests.swift ios/KidCareTests/RuleDocumentsTests.swift \
  ios/KidCareTests/ListLoadTests.swift ios/KidCareTests/RuleSyncStoreTests.swift ios/KidCareTests/RuleRepositoryTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 5단계 Task 1: 예약·장소 문서와 저장소 — 안드로이드가 쓰는 필드 그대로, 못 보낸 알림 깃발"
```

---
### Task 2: 예약 탭 — 하루 띠, 기본 모드, 공휴일, 규칙 편집

**끝나면 '예약' 탭에 안드로이드와 같은 순서로 기본 모드 카드, 공휴일 카드, 상태 줄, 못 보낸 알림 줄, 규칙 카드 목록(스티커·요일·시각·하루 띠·스위치·삭제), '규칙 추가' 버튼이 뜬다.** 규칙을 누르거나 추가하면 편집 화면이 push 되고 시스템 뒤로 버튼이 보인다. 판단은 전부 `ScheduleViewModel` 에 있고, 테스트가 저장 관문 셋, 우선순위, 깃발 순서, 15초 제한, 뒤로 가기, 되돌리기를 못박는다.

**Files:**
- Modify: `ios/KidCare/Guardian/KidCarePalette.swift`
- Create: `ios/KidCare/Guardian/ScheduleText.swift`, `ScheduleViewModel.swift`, `RuleListParts.swift`, `ScheduleView.swift`, `ScheduleEditorView.swift`
- Modify: `ios/KidCare/Guardian/GuardianRootView.swift`
- Modify: `ios/KidCare/Localizable.xcstrings`
- Test: `ios/KidCareTests/RuleTestDoubles.swift`, `ScheduleTextTests.swift`, `ScheduleViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1 전부; 4단계의 `firstToFinish(timeoutMillis:sleep:operation:)`, `ControlInput.date(minuteOfDay:calendar:)`·`minuteOfDay(_:calendar:)`, `RingerMode`, `RingerSettingsDoc`, `ScheduleRepository.observeRingerSettings`, `CommandRepository.send`, `errorMessage(_:)`, `GuardianRootView`(Task 4 모양); 2단계의 `ScheduleResolver.overlaps(rules:candidate:)`, `HolidayCalendar.next(from:)`, `Holiday`, `CalendarMath.ymd(of:zone:)`; 테스트 도구 `TestGate`·`TestCounter`·`TestDefaults`·`TestCallbackBox`·`TestListenerRegistration`·`eventually`
- Produces:
  - `KidCarePalette.apricot, apricotSoft, onApricotSoft, berryInk, line, lineSoft, paperFold`
  - `enum ScheduleText { dayName(_:), daysText(_:), timeText(_:), rangeText(start:end:), modeText(_:), summary(_:), rowDetail(_:), holidayName(_:) }`, `enum DayRibbon { struct Piece; static func pieces(start:end:) -> [Piece] }`
  - `@MainActor @Observable final class ScheduleViewModel` — Step 5 코드 블록의 공개면 그대로(`시작한다`, `편집을_연다`, `취소를_눌렀다`, `뒤로_갔다`, `요일을_누른다`, `모드를_고른다`, `저장을_눌렀다`, `하루_종일을_확인했다`, `겹쳐도_저장한다`, `켬끔을_바꾼다`, `삭제를_눌렀다`, `삭제를_확인했다`, `기본_모드를_고른다`, `공휴일을_바꾼다`, `다시_알린다`, `정리한다`, 상태 프로퍼티, `enum 확인`)
  - `struct RuleStateLine`, `SyncPendingBar`, `RuleAddButton`, `RowDeleteButton`, `extension View { func ruleCard() }` — Task 3 도 쓴다
  - `struct ScheduleView: View { let viewModel: ScheduleViewModel }`, `struct ScheduleEditorView`, `struct ScheduleModeLook`, `struct DayRibbonView`
  - 테스트 공용 `final class WriteSleepFake: Sendable { let 첫_번째, 나머지: TestGate; func sleep(_:) async }` — Task 3 도 쓴다

**정본:** `ScheduleFragment.kt` 전체(줄 번호는 코드 주석), `ScheduleAdapter.kt`(`bind` :40-76, `bindRibbon` :89-126, `ScheduleText` :146-250), `fragment_schedule.xml`(목록 판 :16-312, 편집 판 :314-758), `item_schedule.xml`, `res/color/day_chip_*.xml`. 상수(`ScheduleFragment.kt:1179-1190`): 새 규칙 기본값 `DEFAULT_DAYS = setOf(1, 2, 3, 4, 5)`, `DEFAULT_START_MINUTE = 21 * 60`, `DEFAULT_END_MINUTE = 7 * 60`, 모드 `vibrate`, `WRITE_TIMEOUT_MILLIS = 15_000L`. 치수: 좌우 `@dimen/edge` 20, 카드 사이 `card_gap` 5, 카드 안 `card_pad` 14, 스티커 40(밀도 조정 뒤 xml 값 — `dimens.xml` 의 `sticker` 44 가 아니다, README "밀도"), 하루 띠 높이 4·위 4·모서리 5, 기본 모드 칸 높이 40·간격 6·모서리 12·테두리 1.5·글자 12, 요일 칸 높이 44·간격 6·알약·테두리 1.5·글자 15, 시각 버튼 높이 56·모서리 18·글자 18, 모드 버튼 높이 72·간격 8·모서리 18·그림 22·글자 13, 취소·저장 높이 52·간격 10·글자 16, 추가 버튼 높이 48·위 6·아래 10.

**화면은 그리기와 뷰모델 호출만 한다.**

- [ ] **Step 1: 문구·하루 띠 테스트를 먼저 쓴다**

`ios/KidCareTests/ScheduleTextTests.swift`:

```swift
import Testing
@testable import KidCare

/// 정본은 안드로이드 `ScheduleText`(ScheduleAdapter.kt:146-250)와 `bindRibbon`(:89-126).
struct ScheduleTextTests {

    @Test("자주 쓰는 요일 조합은 이름으로, 나머지는 '·'로 잇는다 — 범위 밖 값은 버린다(:174-184)")
    func 요일() {
        #expect(ScheduleText.daysText([1, 2, 3, 4, 5]) == "평일")
        #expect(ScheduleText.daysText([7, 6]) == "주말")
        #expect(ScheduleText.daysText(Array(1...7)) == "매일")
        #expect(ScheduleText.daysText([]) == "요일 없음")
        #expect(ScheduleText.daysText([5, 1, 3, 9]) == "월·수·금")
    }

    @Test("시간대는 세 가지로 다르게 읽힌다 — 같은 날, 자정 넘김, 하루 종일(:189-213)")
    func 시간대() {
        #expect(ScheduleText.rangeText(start: 540, end: 900) == "09:00 ~ 15:00")
        #expect(ScheduleText.rangeText(start: 1260, end: 420) == "21:00 ~ 다음 날 07:00")
        #expect(ScheduleText.rangeText(start: 0, end: 0) == "하루 종일 (00:00부터 24시간)")
    }

    @Test("줄의 둘째 줄은 꺼둔 규칙에만 '(꺼둠)'이 붙고, 요약은 요일·시간대·모드다(:48-55, :243-249)")
    func 줄과_요약() {
        let 규칙 = ScheduleDoc(id: "a", days: [1, 2, 3, 4, 5], startMinute: 1260, endMinute: 420, mode: RingerMode.vibrate, enabled: false, priority: 1)
        #expect(ScheduleText.rowDetail(규칙) == "21:00 ~ 다음 날 07:00 (꺼둠)")
        #expect(ScheduleText.summary(규칙) == "평일 · 21:00 ~ 다음 날 07:00 · 진동")
        #expect(ScheduleText.modeText("loud") == "loud")
        #expect(ScheduleText.holidayName(.foundation) == "개천절")
    }

    @Test("하루 띠: 낮 규칙은 가운데, 밤 규칙은 양 끝, 하루 종일은 통째로 찬다(:97-126)")
    func 하루_띠() {
        typealias P = DayRibbon.Piece
        #expect(DayRibbon.pieces(start: 540, end: 900) == [P(weight: 540, filled: false), P(weight: 360, filled: true), P(weight: 540, filled: false)])
        #expect(DayRibbon.pieces(start: 1260, end: 420) == [P(weight: 420, filled: true), P(weight: 840, filled: false), P(weight: 180, filled: true)])
        #expect(DayRibbon.pieces(start: 0, end: 0) == [P(weight: 0, filled: false), P(weight: 1, filled: true), P(weight: 0, filled: false)])
        #expect(DayRibbon.pieces(start: -5, end: 2000) == [P(weight: 0, filled: false), P(weight: 1440, filled: true), P(weight: 0, filled: false)])
    }
}
```

- [ ] **Step 2: 뷰모델 테스트를 먼저 쓴다**

`ios/KidCareTests/RuleTestDoubles.swift`:

```swift
import Foundation
@testable import KidCare

/// 쓰기 제한시간(15초) 가짜. 첫 번째 sleep 과 나머지를 따로 연다.
///
/// 저장 쓰기가 매달린 동안에는 그 쓰기의 sleep 이 반드시 첫 번째로 불린다(`firstToFinish` 가 쓰기와
/// 제한시간을 동시에 띄우고, 그 전에는 아무도 sleep 하지 않는다). 그래서 `첫_번째` 만 열면 저장만
/// 시간 초과되고, 뒤따르는 `sync_rules` 발행은 `나머지` 가 닫혀 있어 제때 끝난다. `Task.yield()`
/// 횟수로 순서를 가정하지 않는다(3단계 리뷰 I2).
final class WriteSleepFake: Sendable {
    let 첫_번째 = TestGate()
    let 나머지 = TestGate()
    private let 횟수 = TestCounter()

    func sleep(_ millis: Int64) async {
        if await 횟수.next() == 1 {
            await 첫_번째.wait()
        } else {
            await 나머지.wait()
        }
    }
}
```

`ios/KidCareTests/ScheduleViewModelTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 예약 탭 가짜 Firestore. 쓰기는 기록하고, 테스트가 정한 오류를 던진다.
private actor ScheduleFakeLog {
    private(set) var 저장한_규칙: [ScheduleDoc] = []
    private(set) var 지운_ID: [String] = []
    private(set) var 저장한_기본_모드: [String] = []
    private(set) var 저장한_공휴일: [Bool] = []
    private(set) var 보낸_명령: [String] = []
    private var 쓰기_오류: (any Error)?
    private var 명령_오류: (any Error)?

    func 쓰기_오류를_둔다(_ error: (any Error)?) { 쓰기_오류 = error }
    func 명령_오류를_둔다(_ error: (any Error)?) { 명령_오류 = error }

    func 저장(_ doc: ScheduleDoc) throws -> String {
        if let 쓰기_오류 { throw 쓰기_오류 }
        저장한_규칙.append(doc)
        return doc.id
    }
    func 지운다(_ id: String) throws {
        if let 쓰기_오류 { throw 쓰기_오류 }
        지운_ID.append(id)
    }
    func 기본_모드를_쓴다(_ mode: String) throws {
        if let 쓰기_오류 { throw 쓰기_오류 }
        저장한_기본_모드.append(mode)
    }
    func 공휴일을_쓴다(_ on: Bool) throws {
        if let 쓰기_오류 { throw 쓰기_오류 }
        저장한_공휴일.append(on)
    }
    func 명령(_ type: String) throws -> String {
        if let 명령_오류 { throw 명령_오류 }
        보낸_명령.append(type)
        return "cmd-\(보낸_명령.count)"
    }
}

/// 한 테스트가 쓰는 가짜 한 벌.
private final class ScheduleFakes: Sendable {
    let log = ScheduleFakeLog()
    let sleep = WriteSleepFake()
    let 저장_문 = TestGate()
    let 목록 = TestCallbackBox<([ScheduleDoc], Bool) -> Void>()
    let 설정 = TestCallbackBox<(RingerSettingsDoc) -> Void>()
    let 설정_오류 = TestCallbackBox<(Error) -> Void>()
    let 목록_등록 = TestListenerRegistration()
    let 설정_등록 = TestListenerRegistration()
}

/// 정본은 안드로이드 `guardian/ScheduleFragment.kt`. 줄 번호는 각 테스트 이름에 적었다.
@MainActor
struct ScheduleViewModelTests {

    private struct 가짜_오류: Error {}

    private func 만든다(
        _ f: ScheduleFakes,
        childUid: String? = "child",
        store: RuleSyncStore? = nil,
        저장이_기다린다: Bool = false,
        holidayNext: @escaping (DateComponents) -> (DateComponents, Holiday)? = { _ in nil }
    ) -> ScheduleViewModel {
        var 번호 = 0
        return ScheduleViewModel(
            familyId: "family",
            childUid: childUid,
            syncStore: store ?? RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests")),
            schedulesObserve: { _, _, onChange, _ in
                f.목록.set(onChange)
                return f.목록_등록
            },
            settingsObserve: { _, _, onChange, onError in
                f.설정.set(onChange)
                f.설정_오류.set(onError)
                return f.설정_등록
            },
            scheduleSave: { _, _, doc in
                if 저장이_기다린다 { await f.저장_문.wait() }
                return try await f.log.저장(doc)
            },
            scheduleDelete: { _, _, id in try await f.log.지운다(id) },
            defaultModeSave: { _, _, mode in try await f.log.기본_모드를_쓴다(mode) },
            holidayOffSave: { _, _, on in try await f.log.공휴일을_쓴다(on) },
            commandSend: { _, _, type, _ in try await f.log.명령(type) },
            writeSleep: { millis in await f.sleep.sleep(millis) },
            today: { DateComponents(year: 2026, month: 9, day: 13) },
            holidayNext: holidayNext,
            newId: {
                번호 += 1
                return "new-\(번호)"
            }
        )
    }

    private func 규칙(_ id: String, _ start: Int, _ end: Int, days: [Int] = [1, 2, 3, 4, 5],
                    mode: String = RingerMode.vibrate, enabled: Bool = true, priority: Int = 0) -> ScheduleDoc {
        ScheduleDoc(id: id, days: days, startMinute: start, endMinute: end, mode: mode, enabled: enabled, priority: priority)
    }

    private func 목록을_받는다(_ f: ScheduleFakes, _ vm: ScheduleViewModel, _ docs: [ScheduleDoc], fromCache: Bool = false) async {
        f.목록.value?(docs, fromCache)
        await eventually { vm.rules.count == docs.count && vm.listLoad == ListLoad.after(fromCache: fromCache) }
    }

    @Test("스냅샷은 시작·끝·ID 순으로 정렬하고, 캐시본이면 아직 '없어요'라고 말하지 않는다(:410-422)")
    func 정렬과_캐시() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        await 목록을_받는다(f, vm, [규칙("b", 1320, 420), 규칙("a", 540, 900), 규칙("c", 540, 600)], fromCache: true)
        #expect(vm.rules.map(\.id) == ["c", "a", "b"])
        #expect(vm.listLoad.emptyText(isEmpty: true, loaded: "없음") == "불러오는 중이에요…")
        await 목록을_받는다(f, vm, [], fromCache: false)
        #expect(vm.listLoad.emptyText(isEmpty: vm.rules.isEmpty, loaded: "없음") == "없음")
    }

    @Test("아이가 없으면 구독하지 않고, 목록은 '불러옴'에 안내 한 줄이다(:351-357)")
    func 아이_없음() {
        let f = ScheduleFakes()
        let vm = 만든다(f, childUid: nil)
        vm.시작한다()
        #expect(vm.listLoad == .loaded)
        #expect(vm.상태_줄 == String(localized: "map_no_child"))
        #expect(f.목록.value == nil)
        #expect(vm.다시_알린다() == nil)
    }

    @Test("요일이 비면 저장하지 않고 경고하며, 하나라도 고르면 경고를 거둔다(:474-493, :251-253)")
    func 요일_없음() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        vm.편집을_연다(nil)
        for day in 1...5 { vm.요일을_누른다(day) }
        await vm.저장을_눌렀다()
        #expect(vm.요일_경고)
        #expect(vm.편집_중)
        #expect(await f.log.저장한_규칙.isEmpty)
        vm.요일을_누른다(6)
        #expect(!vm.요일_경고)
    }

    @Test("시작과 끝이 같으면 하루 종일인지 먼저 묻고, 확인하면 저장한다(:480-482, :503-518)")
    func 하루_종일() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        vm.편집을_연다(nil)
        vm.시작분 = 0
        vm.끝분 = 0
        await vm.저장을_눌렀다()
        #expect(vm.확인창 == .하루_종일(message: "시작과 끝이 00:00(으)로 같아요.\n이대로 저장하면 고른 요일에는 24시간 내내 진동(으)로 바뀝니다."))
        #expect(await f.log.저장한_규칙.isEmpty)
        vm.확인창 = nil
        await vm.하루_종일을_확인했다()
        #expect(await f.log.저장한_규칙.map(\.startMinute) == [0])
    }

    @Test("겹치면 첫 규칙 이름과 나머지 개수를 대고 묻는다 — 꺼둔 규칙과는 겹침을 말하지 않는다(:520-561)")
    func 겹침() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        await 목록을_받는다(f, vm, [
            규칙("night", 1320, 420),
            규칙("eve", 1200, 1380),
            규칙("off", 1260, 300, enabled: false),
        ])
        vm.편집을_연다(nil)   // 기본값 평일 21:00~07:00 진동
        await vm.저장을_눌렀다()
        #expect(vm.확인창 == .겹침(message: "이 시간대는 '평일 · 20:00 ~ 23:00 · 진동' 외 1개 규칙과 겹칩니다.\n겹치는 동안에는 나중에 만든 규칙이 이깁니다."))
        #expect(await f.log.저장한_규칙.isEmpty)
        vm.확인창 = nil
        await vm.겹쳐도_저장한다()
        #expect(await f.log.저장한_규칙.count == 1)
    }

    @Test("새 규칙은 나중에 만든 것이 이긴다 — 스냅샷 전에 두 번 저장해도 우선순위가 겹치지 않고, 고치기는 원래 값을 지킨다(:171-181, :582-588, :976-977)")
    func 우선순위() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        await 목록을_받는다(f, vm, [규칙("old", 540, 600, priority: 4)])
        vm.편집을_연다(nil)
        await vm.저장을_눌렀다()
        vm.편집을_연다(nil)
        await vm.저장을_눌렀다()
        vm.편집을_연다(규칙("old", 540, 600, priority: 4))
        vm.끝분 = 660
        await vm.저장을_눌렀다()
        let 저장 = await f.log.저장한_규칙
        #expect(저장.map(\.id) == ["new-1", "new-2", "old"])
        #expect(저장.map(\.priority) == [5, 6, 4])
    }

    @Test("저장은 편집을 열 때 정한 ID 로, 깃발을 먼저 세우고, 끝나야 편집기를 닫고, sync_rules 를 보낸 뒤 깃발을 내린다(:151-160, :575-629, :894-933)")
    func 저장_흐름() async {
        let f = ScheduleFakes()
        let store = RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests-flow"))
        let vm = 만든다(f, store: store, 저장이_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        #expect(vm.editorNewDocId == "new-1")
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        #expect(vm.편집_줄 == "저장 중…")
        #expect(vm.편집_중)
        #expect(vm.pendingSync)
        #expect(store.pendingSync(childUid: "child"))

        await f.저장_문.open()
        await 저장.value
        #expect(!vm.편집_중)
        #expect(vm.상태_줄 == nil)
        #expect(await f.log.저장한_규칙.map(\.id) == ["new-1"])
        #expect(await f.log.저장한_규칙.map(\.days) == [[1, 2, 3, 4, 5]])
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
        #expect(!vm.pendingSync)
        #expect(!store.pendingSync(childUid: "child"))
    }

    @Test("쓰기가 거부되면 편집기는 열린 채 이유를 말하고 입력값을 지킨다 — 알림은 안 보내고 깃발은 남는다(:567-573, :621-627)")
    func 쓰기_실패() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        await f.log.쓰기_오류를_둔다(가짜_오류())
        vm.시작한다()
        vm.편집을_연다(nil)
        vm.요일을_누른다(6)
        await vm.저장을_눌렀다()
        #expect(vm.편집_중)
        #expect(!vm.저장_중)
        #expect(vm.편집_줄 == errorMessage(가짜_오류()))
        #expect(vm.요일 == [1, 2, 3, 4, 5, 6])
        #expect(await f.log.보낸_명령.isEmpty)
        #expect(vm.pendingSync)
    }

    @Test("15초 안에 서버 확인이 없으면 편집기를 닫고 '저장 요청은 보냈지만' 줄을 남긴다 — 알림은 그래도 보낸다(:610-617)")
    func 서버_확인_없음() async {
        let f = ScheduleFakes()
        let vm = 만든다(f, 저장이_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        await f.sleep.첫_번째.open()
        await 저장.value
        #expect(!vm.편집_중)
        #expect(vm.상태_줄 == String(localized: "schedule_save_slow"))
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
    }

    @Test("알림 발행이 실패하면 깃발이 남아 이유를 말하고, 다음에 탭을 열면(다시_알린다) 한 번 더 보내 깃발을 내린다(:913-933, :935-969)")
    func 명령_실패와_재시도() async {
        let f = ScheduleFakes()
        let store = RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests-retry"))
        store.setPendingSync(childUid: "child", true)   // 지난 세션에서 못 보낸 알림
        let vm = 만든다(f, store: store)
        await f.log.명령_오류를_둔다(가짜_오류())
        vm.시작한다()
        #expect(vm.pendingSync)

        await vm.다시_알린다()?.value
        #expect(vm.상태_줄 == String(format: String(localized: "schedule_sync_failed_format"), errorMessage(가짜_오류())))
        #expect(vm.pendingSync)

        await f.log.명령_오류를_둔다(nil)
        await vm.다시_알린다()?.value
        #expect(!vm.pendingSync)
        #expect(!store.pendingSync(childUid: "child"))
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
    }

    @Test("저장 중에 뒤로 가면 늦게 온 실패는 목록 줄로 가고, 그사이 새로 연 편집기는 닫지 않는다(판정 기록 3)")
    func 뒤로_가기_중_실패() async {
        let f = ScheduleFakes()
        let vm = 만든다(f, 저장이_기다린다: true)
        await f.log.쓰기_오류를_둔다(가짜_오류())
        vm.시작한다()
        vm.편집을_연다(nil)
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }

        vm.취소를_눌렀다()          // 안드로이드처럼 취소 버튼은 막힌다
        #expect(vm.편집_중)
        vm.뒤로_갔다()              // 시스템 뒤로 버튼은 막을 수 없다
        #expect(!vm.편집_중)
        vm.편집을_연다(nil)

        await f.저장_문.open()
        await 저장.value
        #expect(vm.편집_중)
        #expect(vm.편집_줄 == nil)
        #expect(vm.상태_줄 == errorMessage(가짜_오류()))
        #expect(await f.log.보낸_명령.isEmpty)
    }

    @Test("기본 모드·공휴일 저장이 거부되면 화면도 되돌린다 — 고른 것으로 보이는데 안 바뀐 것이 가장 나쁜 거짓말(:722-727, :801-805)")
    func 설정_되돌리기() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        f.설정.value?(RingerSettingsDoc(["defaultMode": RingerMode.normal, "holidayOff": false]))
        await eventually { vm.defaultMode == RingerMode.normal }

        await f.log.쓰기_오류를_둔다(가짜_오류())
        await vm.기본_모드를_고른다(RingerMode.silent)
        #expect(vm.defaultMode == RingerMode.normal)
        #expect(vm.상태_줄 == errorMessage(가짜_오류()))
        await vm.공휴일을_바꾼다(true)
        #expect(!vm.holidayOff)

        await f.log.쓰기_오류를_둔다(nil)
        await vm.기본_모드를_고른다(RingerMode.silent)
        #expect(vm.defaultMode == RingerMode.silent)
        #expect(vm.상태_줄 == "규칙이 끝나면 무음(으)로 돌아가요.")
        await vm.기본_모드를_고른다("")
        #expect(vm.상태_줄 == "규칙이 끝나도 소리를 그대로 둬요.")
        await vm.공휴일을_바꾼다(true)
        #expect(vm.상태_줄 == "공휴일에는 예약을 쉬어요.")
        #expect(await f.log.저장한_기본_모드 == [RingerMode.silent, ""])
        #expect(await f.log.보낸_명령.count == 3)
    }

    @Test("공휴일 줄은 켜졌을 때만 다음 쉬는 날을 적고, 계산을 못 하면 그렇게 말한다. 설정을 못 읽으면 스위치를 잠근다(:382-388, :810-835)")
    func 공휴일_안내() async {
        let f = ScheduleFakes()
        let vm = 만든다(f, holidayNext: { _ in (DateComponents(year: 2026, month: 10, day: 3), .foundation) })
        #expect(vm.공휴일_안내 == "쉬는 날에는 아래 규칙을 하나도 켜지 않아요.")
        vm.시작한다()
        f.설정.value?(RingerSettingsDoc(["holidayOff": true]))
        await eventually { vm.holidayOff }
        #expect(vm.공휴일_안내 == "다음 쉬는 날은 10월 3일 개천절이에요.")
        f.설정_오류.value?(가짜_오류())
        await eventually { vm.설정_잠김 }

        let g = ScheduleFakes()
        let 모름 = 만든다(g)
        모름.시작한다()
        g.설정.value?(RingerSettingsDoc(["holidayOff": true]))
        await eventually { 모름.holidayOff }
        #expect(모름.공휴일_안내 == "이 기기에서는 공휴일 날짜를 계산하지 못했어요. 스위치를 켜도 요일대로만 돌아요.")
    }

    @Test("켬끔은 그 규칙을 enabled 만 바꿔 저장하고, 삭제는 요약을 대고 물은 뒤 지운다 — 둘 다 알림을 보낸다(:631-666, :852-892)")
    func 켬끔과_삭제() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        let 낮 = 규칙("a", 540, 900, priority: 2)
        await vm.켬끔을_바꾼다(낮, enabled: false)
        #expect(await f.log.저장한_규칙 == [규칙("a", 540, 900, enabled: false, priority: 2)])

        vm.삭제를_눌렀다(낮)
        #expect(vm.확인창 == .삭제(낮, message: "평일 · 09:00 ~ 15:00 · 진동\n\n지우면 이 시간대에는 소리가 저절로 바뀌지 않아요."))
        vm.확인창 = nil
        await vm.삭제를_확인했다(낮)
        #expect(await f.log.지운_ID == ["a"])
        #expect(vm.상태_줄 == nil)
        #expect(await f.log.보낸_명령 == [CommandType.syncRules, CommandType.syncRules])
    }

    @Test("정리하면 리스너 둘을 떼고, 그 뒤로는 다시 구독하지도 알림을 보내지도 않는다(:1158-1177, 4단계 통합 검토 M1)")
    func 정리() async {
        let f = ScheduleFakes()
        let store = RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests-close"))
        store.setPendingSync(childUid: "child", true)
        let vm = 만든다(f, store: store)
        vm.시작한다()
        vm.정리한다()
        #expect(f.목록_등록.removed)
        #expect(f.설정_등록.removed)
        #expect(vm.다시_알린다() == nil)
        vm.시작한다()
        #expect(await f.log.보낸_명령.isEmpty)

        let g = ScheduleFakes()
        let 먼저_닫힘 = 만든다(g)
        먼저_닫힘.정리한다()
        먼저_닫힘.시작한다()
        #expect(g.목록.value == nil)
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/ScheduleTextTests -only-testing:KidCareTests/ScheduleViewModelTests`
Expected: 컴파일 실패. `ScheduleText`·`DayRibbon`·`ScheduleViewModel` 이 없다.

- [ ] **Step 4: 색과 문구**

`ios/KidCare/Guardian/KidCarePalette.swift` 의 `onBerrySoft` 아래에 더한다:

```swift
    /// colors.xml:14-16 — 벨소리 스티커(ScheduleAdapter.kt:224)와 시각 버튼(fragment_schedule.xml:565-567).
    static let apricot = Color(hex: 0xF2A05F)
    static let apricotSoft = Color(hex: 0xFFF0E2)
    static let onApricotSoft = Color(hex: 0x5A3216)
    /// colors.xml:23 — `themes.xml:20` 의 colorError. 삭제 그림, 경고 글자, 일요일 칸.
    static let berryInk = Color(hex: 0xB64C66)
    /// colors.xml:25 — `themes.xml:36` 의 colorOutline. 입력칸 테두리.
    static let line = Color(hex: 0xA398AE)
    /// colors.xml:26 — 카드 테두리, 고르지 않은 칸, 하루 띠 바탕.
    static let lineSoft = Color(hex: 0xE9E1ED)
    /// colors.xml:6 — `themes.xml:29` 의 colorSurfaceVariant. 장소 상한 안내 바탕.
    static let paperFold = Color(hex: 0xF5F0FF)
```

`ios/KidCare/Guardian/ScheduleText.swift`:

```swift
import Foundation

/// 규칙을 사람이 읽는 문장으로. 정본은 안드로이드 `ScheduleText`(ScheduleAdapter.kt:146-250).
///
/// 목록 줄, 확인 대화상자, 편집 판의 범위 안내가 **같은 말**로 규칙을 가리켜야 해서(:20-23) 조립은
/// 여기 한 곳이다.
enum ScheduleText {

    /// 1=월 … 7=일(:158-168).
    static func dayName(_ day: Int) -> String {
        switch day {
        case 1: return String(localized: "schedule_day_mon")
        case 2: return String(localized: "schedule_day_tue")
        case 3: return String(localized: "schedule_day_wed")
        case 4: return String(localized: "schedule_day_thu")
        case 5: return String(localized: "schedule_day_fri")
        case 6: return String(localized: "schedule_day_sat")
        case 7: return String(localized: "schedule_day_sun")
        default: return ""
        }
    }

    /// "평일" / "주말" / "매일" / "월·수·금"(:174-184).
    static func daysText(_ days: [Int]) -> String {
        let set = Set(days.filter { (1...7).contains($0) })
        if set.isEmpty { return String(localized: "schedule_days_none") }
        if set == Set(1...7) { return String(localized: "schedule_days_everyday") }
        if set == Set(1...5) { return String(localized: "schedule_days_weekday") }
        if set == [6, 7] { return String(localized: "schedule_days_weekend") }
        return set.sorted().map(dayName).joined(separator: "·")
    }

    static func timeText(_ minuteOfDay: Int) -> String {
        String(format: String(localized: "schedule_time_format"), minuteOfDay / 60, minuteOfDay % 60)
    }

    /// 같은 날·자정 넘김·하루 종일이 서로 다르게 읽혀야 한다(:189-213). "22:00 ~ 07:00" 이라고만 쓰면
    /// 끝이 시작보다 앞이라 잘못 넣은 값처럼 보인다.
    static func rangeText(start: Int, end: Int) -> String {
        if start == end {
            return String(format: String(localized: "schedule_range_allday"), timeText(start))
        }
        if end < start {
            return String(format: String(localized: "schedule_range_overnight"), timeText(start), timeText(end))
        }
        return String(format: String(localized: "schedule_range"), timeText(start), timeText(end))
    }

    /// 모르는 값이면 셋 중 하나로 넘겨짚지 않고 저장된 값을 그대로 보인다(:237-241).
    static func modeText(_ mode: String) -> String {
        switch mode {
        case RingerMode.normal: return String(localized: "schedule_mode_normal")
        case RingerMode.vibrate: return String(localized: "schedule_mode_vibrate")
        case RingerMode.silent: return String(localized: "schedule_mode_silent")
        default: return mode
        }
    }

    /// 대화상자에서 규칙 하나를 가리키는 한 줄(:243-249).
    static func summary(_ doc: ScheduleDoc) -> String {
        String(format: String(localized: "schedule_summary"),
               daysText(doc.days), rangeText(start: doc.startMinute, end: doc.endMinute), modeText(doc.mode))
    }

    /// 목록 줄의 둘째 줄. 모드 이름은 스티커가 말하므로 쓰지 않는다(ScheduleAdapter.kt:46-55).
    static func rowDetail(_ doc: ScheduleDoc) -> String {
        let range = rangeText(start: doc.startMinute, end: doc.endMinute)
        return doc.enabled ? range : String(format: String(localized: "schedule_row_off"), range)
    }

    /// ScheduleFragment.kt:837-850.
    static func holidayName(_ holiday: Holiday) -> String {
        switch holiday {
        case .newYear: return String(localized: "holiday_new_year")
        case .seollal: return String(localized: "holiday_seollal")
        case .independence: return String(localized: "holiday_independence")
        case .buddha: return String(localized: "holiday_buddha")
        case .children: return String(localized: "holiday_children")
        case .memorial: return String(localized: "holiday_memorial")
        case .liberation: return String(localized: "holiday_liberation")
        case .chuseok: return String(localized: "holiday_chuseok")
        case .foundation: return String(localized: "holiday_foundation")
        case .hangul: return String(localized: "holiday_hangul")
        case .christmas: return String(localized: "holiday_christmas")
        case .substitute: return String(localized: "holiday_substitute")
        }
    }
}

/// 하루 띠의 세 조각. 정본은 `ScheduleAdapter.bindRibbon`(:89-126).
///
/// 조각이 셋인 이유는 자정 넘김이다. 낮 규칙은 가운데만 차고 밤 규칙은 **양 끝**이 찬다.
/// 시작 == 끝(하루 종일)은 가운데 하나가 통째로 찬다.
enum DayRibbon {

    struct Piece: Equatable {
        let weight: Int
        let filled: Bool
    }

    static let minutesPerDay = 24 * 60

    static func pieces(start: Int, end: Int) -> [Piece] {
        let s = min(max(start, 0), minutesPerDay)
        let e = min(max(end, 0), minutesPerDay)
        if s == e {
            return [Piece(weight: 0, filled: false), Piece(weight: 1, filled: true), Piece(weight: 0, filled: false)]
        }
        if e < s {
            return [Piece(weight: e, filled: true), Piece(weight: s - e, filled: false), Piece(weight: minutesPerDay - s, filled: true)]
        }
        return [Piece(weight: s, filled: false), Piece(weight: e - s, filled: true), Piece(weight: minutesPerDay - e, filled: false)]
    }
}
```

`-5`·`2000` 입력은 둘 다 끝으로 잘려 `s = 0`, `e = 1440` 이 되므로 낮 규칙 갈래로 간다. 테스트의 기대값 `[0, 1440, 0]` 이 이것이다.

- [ ] **Step 5: 뷰모델**

`ios/KidCare/Guardian/ScheduleViewModel.swift`:

```swift
import FirebaseFirestore
import Foundation
import Observation

/// 예약 탭의 두뇌. 정본은 안드로이드 `guardian/ScheduleFragment.kt` — 줄 번호는 각 주석에 적었다.
///
/// ## 규칙이 바뀌면 반드시 아이 폰에 알린다(:43-65)
/// 저장·켬끔·삭제·기본 모드·공휴일, 다섯 갈래 모두 쓰기 뒤에 `sync_rules` 를 보낸다
/// (`아이에게_알린다`). 못 보냈으면 깃발(`RuleSyncStore`)을 남기고 목록 위에 그렇게 적는다.
///
/// ## 낙관적으로 그리지 않는다(:67-73)
/// 목록은 오직 스냅샷으로만 그린다. 편집기는 쓰기가 끝날 때까지 열려 있고, 실패하면 그 자리에서
/// 이유를 말하며 입력값을 지킨다. 기본 모드·공휴일만 누른 즉시 바뀌어 보이고, 거부되면 되돌린다.
///
/// ## 세대 번호(:99-113)
/// 쓰기는 왕복이 있어 늦게 돌아온다. 쓰기를 시작하거나 편집을 접을 때마다 세대를 올리고, 화면을
/// 만지기 직전에 확인한다. 명령 발행은 세대와 무관하게 늘 한다 — 규칙이 바뀐 사실은 없어지지 않는다.
@Observable
@MainActor
final class ScheduleViewModel {

    // MARK: - 상수 (ScheduleFragment.kt:1179-1190)

    nonisolated static let writeTimeoutMillis: Int64 = 15_000
    /// 새 규칙 기본값: 평일 21:00~07:00 진동 — "밤에는 조용히"에 가장 가깝다(:1180).
    nonisolated static let defaultDays: Set<Int> = [1, 2, 3, 4, 5]
    nonisolated static let defaultStartMinute = 21 * 60
    nonisolated static let defaultEndMinute = 7 * 60

    /// 떠 있는 확인 대화상자. 안드로이드는 `activeDialog` 하나만 둔다(:188-189, :1149-1156).
    enum 확인: Equatable {
        case 하루_종일(message: String)
        case 겹침(message: String)
        case 삭제(ScheduleDoc, message: String)

        var message: String {
            switch self {
            case .하루_종일(let message), .겹침(let message), .삭제(_, let message): return message
            }
        }
    }

    // MARK: - 목록 판

    let familyId: String
    let childUid: String?
    private(set) var rules: [ScheduleDoc] = []
    private(set) var listLoad: ListLoad = .loading
    /// 목록 위 한 줄(`showState`). nil 이면 감춘다.
    private(set) var 상태_줄: String?
    private(set) var pendingSync = false
    private(set) var holidayOff = false
    /// 빈 값은 "그대로 두기".
    private(set) var defaultMode = ""
    /// 설정 문서를 못 읽었다 — 목록 안내를 덮지 않고 스위치만 잠근다(:382-388).
    private(set) var 설정_잠김 = false
    var 확인창: 확인?

    // MARK: - 편집 판 (:142-184) — 편집 중인 값은 전부 여기가 정답이다

    private(set) var 편집_중 = false
    private(set) var editorRuleId: String?
    /// 새 규칙의 문서 ID 는 편집을 열 때 한 번 정한다 — 저장이 두 번 나가도 규칙이 하나다(:151-160).
    private(set) var editorNewDocId: String?
    private(set) var 요일: Set<Int> = ScheduleViewModel.defaultDays
    var 시작분 = ScheduleViewModel.defaultStartMinute
    var 끝분 = ScheduleViewModel.defaultEndMinute
    private(set) var 모드 = RingerMode.vibrate
    private(set) var 저장_중 = false
    private(set) var 편집_줄: String?
    private(set) var 요일_경고 = false

    @ObservationIgnored private var editorEnabled = true
    @ObservationIgnored private var editorPriority = 0
    @ObservationIgnored private var writeGeneration = 0
    /// 뒤로 가기로 떠난 저장의 세대(판정 기록 3).
    @ObservationIgnored private var 떠난_저장_세대: Int?
    /// 이 화면이 방금 부여한 가장 큰 우선순위(:171-181).
    @ObservationIgnored private var lastAssignedPriority = 0
    @ObservationIgnored private var 시작함 = false
    /// `정리한다()` 뒤에는 새 구독도 새 명령도 만들지 않는다(4단계 통합 검토 M1).
    @ObservationIgnored private var 닫힘 = false
    @ObservationIgnored private var scheduleListener: ListenerRegistration?
    @ObservationIgnored private var settingsListener: ListenerRegistration?
    @ObservationIgnored private var syncRetryTask: Task<Void, Never>?

    private let syncStore: RuleSyncStore
    private let schedulesObserve: @Sendable (String, String, @escaping ([ScheduleDoc], Bool) -> Void, @escaping (Error) -> Void) -> ListenerRegistration
    private let settingsObserve: @Sendable (String, String, @escaping (RingerSettingsDoc) -> Void, @escaping (Error) -> Void) -> ListenerRegistration
    private let scheduleSave: @Sendable (String, String, ScheduleDoc) async throws -> String
    private let scheduleDelete: @Sendable (String, String, String) async throws -> Void
    private let defaultModeSave: @Sendable (String, String, String) async throws -> Void
    private let holidayOffSave: @Sendable (String, String, Bool) async throws -> Void
    private let commandSend: @Sendable (String, String, String, [String: String]) async throws -> String
    private let writeSleep: @Sendable (Int64) async -> Void
    private let today: () -> DateComponents
    private let holidayNext: (DateComponents) -> (DateComponents, Holiday)?
    private let newId: () -> String

    init(
        familyId: String,
        childUid: String?,
        syncStore: RuleSyncStore = RuleSyncStore(kind: .schedule),
        schedulesObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping ([ScheduleDoc], Bool) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = ScheduleRepository.observeSchedules,
        settingsObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping (RingerSettingsDoc) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = ScheduleRepository.observeRingerSettings,
        scheduleSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ doc: ScheduleDoc) async throws -> String = ScheduleRepository.saveSchedule,
        scheduleDelete: @escaping @Sendable (_ familyId: String, _ childUid: String, _ id: String) async throws -> Void = ScheduleRepository.deleteSchedule,
        defaultModeSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ mode: String) async throws -> Void = ScheduleRepository.setDefaultMode,
        holidayOffSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ enabled: Bool) async throws -> Void = ScheduleRepository.setHolidayOff,
        commandSend: @escaping @Sendable (_ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]) async throws -> String = CommandRepository.send,
        writeSleep: @escaping @Sendable (_ millis: Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        },
        today: @escaping () -> DateComponents = ScheduleViewModel.오늘,
        holidayNext: @escaping (DateComponents) -> (DateComponents, Holiday)? = { HolidayCalendar.next(from: $0) },
        newId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.syncStore = syncStore
        self.schedulesObserve = schedulesObserve
        self.settingsObserve = settingsObserve
        self.scheduleSave = scheduleSave
        self.scheduleDelete = scheduleDelete
        self.defaultModeSave = defaultModeSave
        self.holidayOffSave = holidayOffSave
        self.commandSend = commandSend
        self.writeSleep = writeSleep
        self.today = today
        self.holidayNext = holidayNext
        self.newId = newId
    }

    /// 안드로이드 `LocalDate.now()`(:824) — 기기 시간대의 오늘.
    nonisolated static func 오늘() -> DateComponents {
        let ymd = CalendarMath.ymd(of: Date(), zone: .current)
        return DateComponents(year: ymd.year, month: ymd.month, day: ymd.day)
    }

    // MARK: - 구독 (:334-422)

    /// 탭을 처음 보일 때 한 번. 두 번째부터는 아무것도 안 한다(관리 탭 `시작한다` 와 같은 규율).
    func 시작한다() {
        guard !시작함, !닫힘 else { return }
        시작함 = true
        guard let childUid else {
            listLoad = .loaded
            상태_줄 = String(localized: "map_no_child")
            return
        }
        pendingSync = syncStore.pendingSync(childUid: childUid)
        // 구독은 await 없이 곧바로 붙인다 — 붙이기 전에 `정리한다()` 가 끼어들 틈이 없다(4단계 M1 의 경주가 없다).
        scheduleListener = schedulesObserve(familyId, childUid, { [weak self] docs, fromCache in
            Task { @MainActor in self?.규칙이_바뀌었다(docs, fromCache: fromCache) }
        }, { [weak self] error in
            Task { @MainActor in self?.목록을_못_읽었다(error) }
        })
        settingsListener = settingsObserve(familyId, childUid, { [weak self] doc in
            Task { @MainActor in
                self?.holidayOff = doc.holidayOff
                self?.defaultMode = doc.defaultMode
            }
        }, { [weak self] _ in
            Task { @MainActor in self?.설정_잠김 = true }
        })
    }

    /// 보호자 화면이 통째로 사라질 때(`onDestroyView` :1158-1177).
    func 정리한다() {
        닫힘 = true
        scheduleListener?.remove()
        scheduleListener = nil
        settingsListener?.remove()
        settingsListener = nil
        syncRetryTask?.cancel()
        syncRetryTask = nil
        writeGeneration += 1
    }

    private func 규칙이_바뀌었다(_ docs: [ScheduleDoc], fromCache: Bool) {
        rules = docs.sorted(by: Self.목록_순서)
        listLoad = ListLoad.after(fromCache: fromCache)
    }

    /// 이른 시각이 위로. priority 는 화면에 안 쓰므로 정렬에도 안 쓴다(:411-416). ID 는 코틀린
    /// `String.compareTo` 와 같은 UTF-16 순서(판정 기록 10).
    nonisolated static func 목록_순서(_ a: ScheduleDoc, _ b: ScheduleDoc) -> Bool {
        if a.startMinute != b.startMinute { return a.startMinute < b.startMinute }
        if a.endMinute != b.endMinute { return a.endMinute < b.endMinute }
        return KotlinMath.precedes(a.id, b.id)
    }

    private func 목록을_못_읽었다(_ error: Error) {
        listLoad = .failed
        상태_줄 = String(format: String(localized: "schedule_error_format"), errorMessage(error))
    }

    // MARK: - 편집 판 (:424-561)

    func 편집을_연다(_ doc: ScheduleDoc?) {
        editorRuleId = doc?.id
        editorNewDocId = doc == nil ? newId() : nil
        요일 = doc.map { d in Set(d.days.filter { (1...7).contains($0) }) } ?? Self.defaultDays
        시작분 = doc?.startMinute ?? Self.defaultStartMinute
        끝분 = doc?.endMinute ?? Self.defaultEndMinute
        모드 = doc?.mode ?? RingerMode.vibrate
        editorEnabled = doc?.enabled ?? true
        editorPriority = doc?.priority ?? 0
        저장_중 = false
        편집_줄 = nil
        요일_경고 = false
        상태_줄 = nil
        편집_중 = true
    }

    /// 편집 판의 '취소' 버튼. 쓰기가 도는 동안은 막는다(:443-460).
    func 취소를_눌렀다() {
        guard !저장_중 else { return }
        writeGeneration += 1
        편집기를_닫는다()
    }

    /// 시스템 뒤로 버튼·밀어서 뒤로 가기. 막을 수 없으므로 막지 않는다. 도는 중이던 쓰기의 결과는 목록 줄이
    /// 이어받고, 새로 연 편집기는 절대 만지지 않는다(판정 기록 3). 코드가 `편집_중` 을 먼저 내린 뒤
    /// SwiftUI 가 바인딩에 false 를 한 번 더 쓰는 경우에도 아무 일이 없게 첫 줄에서 거른다.
    func 뒤로_갔다() {
        guard 편집_중 else { return }
        if 저장_중 { 떠난_저장_세대 = writeGeneration }
        writeGeneration += 1
        편집기를_닫는다()
    }

    private func 편집기를_닫는다() {
        편집_중 = false
        저장_중 = false
        editorRuleId = nil
        editorNewDocId = nil
        편집_줄 = nil
    }

    func 요일을_누른다(_ day: Int) {
        if 요일.contains(day) { 요일.remove(day) } else { 요일.insert(day) }
        // 하나라도 고르는 순간 경고를 거둔다 — 고쳤는데 빨간 글씨가 남으면 아직 틀린 줄 안다(:251-253).
        if !요일.isEmpty { 요일_경고 = false }
    }

    func 모드를_고른다(_ mode: String) {
        모드 = mode
    }

    var 편집기_제목: String {
        editorRuleId == nil
            ? String(localized: "schedule_editor_title_new")
            : String(localized: "schedule_editor_title_edit")
    }

    /// 시각 두 칸만으로는 알 수 없는 "다음 날까지"·"하루 종일"을 미리 말한다(:1064-1070).
    var 범위_안내: String? {
        끝분 <= 시작분 ? ScheduleText.rangeText(start: 시작분, end: 끝분) : nil
    }

    /// 저장 버튼. 요일 → 하루 종일 → 겹침, 세 관문을 순서대로 지난다(:471-501).
    func 저장을_눌렀다() async {
        guard !저장_중 else { return }
        guard !요일.isEmpty else {
            요일_경고 = true
            return
        }
        요일_경고 = false
        if 시작분 == 끝분 {
            확인창 = .하루_종일(message: String(format: String(localized: "schedule_allday_message"),
                                              ScheduleText.timeText(시작분), ScheduleText.modeText(모드)))
            return
        }
        await 겹침을_확인하고_저장한다()
    }

    func 하루_종일을_확인했다() async {
        await 겹침을_확인하고_저장한다()
    }

    func 겹쳐도_저장한다() async {
        await 규칙을_저장한다()
    }

    /// 후보는 늘 켜진 것으로 보고, 비교 대상 중 꺼진 것은 뺀다 — `ScheduleResolver.overlaps` 주석(:520-561).
    private func 겹침을_확인하고_저장한다() async {
        let candidate = ScheduleRule(id: editorRuleId ?? "", days: 요일, startMinute: 시작분, endMinute: 끝분,
                                     mode: 모드, enabled: editorEnabled, priority: editorPriority)
        let hits = ScheduleResolver.overlaps(rules: rules.map(\.asRule), candidate: candidate)
        guard let first = hits.first, let firstDoc = rules.first(where: { $0.id == first.id }) else {
            await 규칙을_저장한다()
            return
        }
        let name = ScheduleText.summary(firstDoc)
        let message = hits.count == 1
            ? String(format: String(localized: "schedule_overlap_message"), name)
            : String(format: String(localized: "schedule_overlap_message_more"), name, hits.count - 1)
        확인창 = .겹침(message: message)
    }

    // MARK: - 쓰기

    /// 만들기와 고치기가 같은 경로다. 쓰기가 끝날 때까지 편집기를 닫지 않는다(:565-629).
    private func 규칙을_저장한다() async {
        guard let childUid else {
            편집_줄 = String(localized: "schedule_no_family")
            return
        }
        // 새 규칙은 지금 있는 것보다 하나 크게, 고치기는 원래 값 그대로(:582-588).
        let priority = editorRuleId == nil ? 다음_우선순위() : editorPriority
        if editorRuleId == nil { lastAssignedPriority = priority }
        let doc = ScheduleDoc(id: editorRuleId ?? editorNewDocId ?? newId(), days: 요일.sorted(),
                              startMinute: 시작분, endMinute: 끝분, mode: 모드,
                              enabled: editorEnabled, priority: priority)
        writeGeneration += 1
        let generation = writeGeneration
        저장_중 = true
        편집_줄 = String(localized: "schedule_saving")
        // 쓰기보다 **먼저** 세운다 — 반대 순서의 사고(쓰기는 됐는데 깃발이 없음)는 조용한 고장이다(:603-606).
        깃발을_바꾼다(true)

        let (fid, save) = (familyId, scheduleSave)
        do {
            let savedId = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await save(fid, childUid, doc)
            }
            if generation == writeGeneration {
                편집기를_닫는다()
                상태_줄 = savedId == nil ? String(localized: "schedule_save_slow") : nil
            } else if 목록이_이어받았나(generation), savedId == nil {
                상태_줄 = String(localized: "schedule_save_slow")
            }
            await 아이에게_알린다(generation)
        } catch {
            if generation == writeGeneration {
                저장_중 = false
                편집_줄 = errorMessage(error)
            } else if 목록이_이어받았나(generation) {
                상태_줄 = errorMessage(error)
            }
        }
    }

    /// 켬/끔. 보이는 값은 스냅샷이 정하므로 직접 되돌리지 않고, 왜 돌아갔는지만 말한다(:631-666).
    func 켬끔을_바꾼다(_ doc: ScheduleDoc, enabled: Bool) async {
        guard let childUid else {
            상태_줄 = String(localized: "schedule_no_family")
            return
        }
        writeGeneration += 1
        let generation = writeGeneration
        상태_줄 = nil
        깃발을_바꾼다(true)
        var copy = doc
        copy.enabled = enabled
        let (fid, save, changed) = (familyId, scheduleSave, copy)
        do {
            let savedId = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await save(fid, childUid, changed)
            }
            if savedId == nil, generation == writeGeneration {
                상태_줄 = String(localized: "schedule_save_slow")
            }
            await 아이에게_알린다(generation)
        } catch {
            if generation == writeGeneration { 상태_줄 = errorMessage(error) }
        }
    }

    func 삭제를_눌렀다(_ doc: ScheduleDoc) {
        확인창 = .삭제(doc, message: String(format: String(localized: "schedule_delete_message"), ScheduleText.summary(doc)))
    }

    /// :863-892.
    func 삭제를_확인했다(_ doc: ScheduleDoc) async {
        guard let childUid else {
            상태_줄 = String(localized: "schedule_no_family")
            return
        }
        writeGeneration += 1
        let generation = writeGeneration
        상태_줄 = String(localized: "schedule_deleting")
        깃발을_바꾼다(true)
        let (fid, delete, id) = (familyId, scheduleDelete, doc.id)
        do {
            let done: Void? = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await delete(fid, childUid, id)
            }
            if generation == writeGeneration {
                상태_줄 = done == nil ? String(localized: "schedule_save_slow") : nil
            }
            await 아이에게_알린다(generation)
        } catch {
            if generation == writeGeneration { 상태_줄 = errorMessage(error) }
        }
    }

    /// 예약이 없는 시간의 기본 모드. 거부되면 되돌린다(:676-729).
    func 기본_모드를_고른다(_ mode: String) async {
        guard let childUid else {
            상태_줄 = String(localized: "schedule_no_family")
            return
        }
        let previous = defaultMode
        writeGeneration += 1
        let generation = writeGeneration
        defaultMode = mode
        상태_줄 = nil
        깃발을_바꾼다(true)
        let (fid, save) = (familyId, defaultModeSave)
        do {
            let done: Void? = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await save(fid, childUid, mode)
            }
            if generation == writeGeneration {
                if done == nil {
                    상태_줄 = String(localized: "schedule_save_slow")
                } else if mode.isEmpty {
                    상태_줄 = String(localized: "schedule_default_cleared")
                } else {
                    상태_줄 = String(format: String(localized: "schedule_default_saved"), ScheduleText.modeText(mode))
                }
            }
            await 아이에게_알린다(generation)
        } catch {
            guard generation == writeGeneration else { return }
            defaultMode = previous
            상태_줄 = errorMessage(error)
        }
    }

    /// 공휴일 스위치. 거부되면 되돌린다(:760-808).
    func 공휴일을_바꾼다(_ enabled: Bool) async {
        guard let childUid else {
            상태_줄 = String(localized: "schedule_no_family")
            return
        }
        writeGeneration += 1
        let generation = writeGeneration
        holidayOff = enabled
        상태_줄 = nil
        깃발을_바꾼다(true)
        let (fid, save) = (familyId, holidayOffSave)
        do {
            let done: Void? = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await save(fid, childUid, enabled)
            }
            if generation == writeGeneration {
                if done == nil {
                    상태_줄 = String(localized: "schedule_save_slow")
                } else if enabled {
                    상태_줄 = String(localized: "schedule_holiday_saved")
                } else {
                    상태_줄 = String(localized: "schedule_holiday_cleared")
                }
            }
            await 아이에게_알린다(generation)
        } catch {
            guard generation == writeGeneration else { return }
            holidayOff = !enabled
            상태_줄 = errorMessage(error)
        }
    }

    /// 켜져 있을 때만 다음 쉬는 날을 적는다 — 음력 환산이 틀렸는지 부모가 달력과 맞춰볼 유일한 검산이다(:810-835).
    var 공휴일_안내: String {
        guard holidayOff else { return String(localized: "schedule_holiday_subtitle") }
        guard let next = holidayNext(today()) else { return String(localized: "schedule_holiday_unknown") }
        let 날짜 = String(format: String(localized: "schedule_holiday_date"), next.0.month ?? 0, next.0.day ?? 0)
        return String(format: String(localized: "schedule_holiday_next"), 날짜, ScheduleText.holidayName(next.1))
    }

    // MARK: - 아이 폰에 알리기 (:894-969)

    /// 세대는 **글자를 쓸지만** 가른다. 명령은 늘 보낸다(:894-901).
    private func 아이에게_알린다(_ generation: Int) async {
        guard let childUid else {
            // 보낼 곳이 없다. 아이 폰이 연결되면 저절로 규칙을 읽으므로 깃발을 내린다(:905-912).
            깃발을_바꾼다(false)
            if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "schedule_sync_no_child") }
            return
        }
        let (fid, send) = (familyId, commandSend)
        do {
            let commandId = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await send(fid, childUid, CommandType.syncRules, [:])
            }
            guard commandId != nil else {
                // 오프라인이면 명령도 로컬 큐에서 연결을 기다린다. 그래도 깃발은 내리지 않는다(:917-923).
                if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "schedule_sync_slow") }
                return
            }
            깃발을_바꾼다(false)
        } catch {
            if 글자를_쓸_수_있나(generation) {
                상태_줄 = String(format: String(localized: "schedule_sync_failed_format"), errorMessage(error))
            }
        }
    }

    /// 못 보낸 알림을 한 번 더 보낸다. 부르는 곳은 탭을 보일 때, 앱으로 돌아왔을 때, '다시 알리기'다
    /// (판정 기록 7). 테스트가 기다릴 수 있게 작업을 돌려준다.
    @discardableResult
    func 다시_알린다() -> Task<Void, Never>? {
        // 아이 uid 를 모르면 "연결되면 저절로"로 깃발을 내려버리므로 부르지 않는다(:951-955).
        guard pendingSync, childUid != nil, syncRetryTask == nil, !닫힘 else { return nil }
        let generation = writeGeneration
        let task = Task { [weak self] in
            await self?.아이에게_알린다(generation)
            self?.syncRetryTask = nil
        }
        syncRetryTask = task
        return task
    }

    // MARK: - 도우미

    private func 깃발을_바꾼다(_ value: Bool) {
        guard let childUid else { return }
        syncStore.setPendingSync(childUid: childUid, value)
        pendingSync = value
    }

    private func 다음_우선순위() -> Int {
        max(rules.map(\.priority).max() ?? 0, lastAssignedPriority) + 1
    }

    /// 뒤로 가기로 떠난 저장이고, 그 뒤로 다른 쓰기가 시작되지 않았는가(판정 기록 3).
    private func 목록이_이어받았나(_ generation: Int) -> Bool {
        떠난_저장_세대 == generation && writeGeneration == generation + 1
    }

    private func 글자를_쓸_수_있나(_ generation: Int) -> Bool {
        generation == writeGeneration || 목록이_이어받았나(generation)
    }
}
```

`Holiday` 는 `Logic/KoreanHolidays.swift` 의 enum 이라 Sendable 이고, `firstToFinish` 로 넘기는 클로저가 붙드는 값(`String`, `ScheduleDoc`, `Bool`, `@Sendable` 클로저)도 전부 Sendable 이다.

- [ ] **Step 6: 두 목록이 함께 쓰는 조각**

`ios/KidCare/Guardian/RuleListParts.swift`:

```swift
import SwiftUI

/// 예약·장소 목록 판이 함께 쓰는 조각. 두 XML 은 "같은 뼈대"를 쓴다(item_place.xml:2-4).
/// 한쪽만 고치면 탭을 넘길 때 선이 튄다(README "네 탭을 한 격자에").

/// 목록 위 오류·저장 결과 한 줄(fragment_schedule.xml:221-230, fragment_place.xml:23-32).
struct RuleStateLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(KidCarePalette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
    }
}

/// "아직 애기폰에 전달되지 않았어요" 줄(fragment_schedule.xml:232-271, fragment_place.xml:34-68).
/// 바탕은 colorErrorContainer(berry_soft), 글자와 버튼은 colorOnErrorContainer(on_berry_soft) —
/// 기본 하늘색 글자 버튼이면 이 바탕 위에서 1.7:1 로 안 보인다(:259-261).
struct SyncPendingBar: View {
    let text: String
    let retryTitle: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(KidCarePalette.onBerrySoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Text(retryTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(KidCarePalette.onBerrySoft)
                    .frame(minHeight: 48)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(KidCarePalette.berrySoft)
    }
}

/// 목록 맨 아래 추가 버튼(fragment_schedule.xml:299-311, fragment_place.xml:131-143). `Widget.KidCare.Button`
/// — 채운 sky, 모서리 18, 높이 48, 그림 22·간격 8, TitleMedium. 잠기면 Material3 비활성 색(글자 38%, 바탕 12%).
struct RuleAddButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 18, weight: .medium))
            }
            .foregroundStyle(enabled ? KidCarePalette.onAccent : KidCarePalette.ink.opacity(0.38))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(enabled ? KidCarePalette.sky : KidCarePalette.ink.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

/// 줄 끝 삭제 그림 버튼 44×44(item_schedule.xml:122-139, `dimens.xml` row_icon_button). 그림 21, berry_ink.
struct RowDeleteButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 18))
                .foregroundStyle(KidCarePalette.berryInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

extension View {
    /// 목록 카드 한 장. `Widget.KidCare.Card`(themes.xml:170-176) — paper_card, 모서리 18(item 이
    /// `ShapeAppearance.KidCare.Medium` 을 적었다, item_schedule.xml:22), 테두리 line_soft 1.
    func ruleCard() -> some View {
        background(KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KidCarePalette.lineSoft, lineWidth: 1))
    }
}
```

- [ ] **Step 7: 목록 판**

`ios/KidCare/Guardian/ScheduleView.swift`:

```swift
import SwiftUI

/// 예약 탭 목록 판. 정본은 `fragment_schedule.xml` 목록 판(:16-312)과 `item_schedule.xml`.
/// 위에서 아래로 기본 모드 카드 → 공휴일 카드 → 상태 줄 → 못 보낸 알림 줄 → 규칙 목록 → 추가 버튼.
/// 편집 판은 탭 안 `NavigationStack` 으로 push 한다(판정 기록 2).
struct ScheduleView: View {

    let viewModel: ScheduleViewModel

    var body: some View {
        NavigationStack {
            목록_판
                // 목록 판에는 화면 제목이 없다 — 아래 탭이 이미 "예약"이라 말한다(README "밀도").
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: Binding(
                    get: { viewModel.편집_중 },
                    set: { if !$0 { viewModel.뒤로_갔다() } }
                )) {
                    ScheduleEditorView(viewModel: viewModel)
                }
        }
        .alert(확인_제목, isPresented: Binding(
            get: { viewModel.확인창 != nil },
            set: { if !$0 { viewModel.확인창 = nil } }
        ), presenting: viewModel.확인창) { 확인 in
            switch 확인 {
            case .하루_종일:
                Button(String(localized: "schedule_allday_confirm")) { Task { await viewModel.하루_종일을_확인했다() } }
                Button(String(localized: "schedule_allday_cancel"), role: .cancel) {}
            case .겹침:
                Button(String(localized: "schedule_overlap_confirm")) { Task { await viewModel.겹쳐도_저장한다() } }
                Button(String(localized: "schedule_overlap_cancel"), role: .cancel) {}
            case .삭제(let doc, _):
                Button(String(localized: "schedule_delete_confirm"), role: .destructive) { Task { await viewModel.삭제를_확인했다(doc) } }
                Button(String(localized: "schedule_delete_cancel"), role: .cancel) {}
            }
        } message: { 확인 in
            Text(verbatim: 확인.message)
        }
    }

    private var 확인_제목: String {
        switch viewModel.확인창 {
        case .하루_종일: return String(localized: "schedule_allday_title")
        case .겹침: return String(localized: "schedule_overlap_title")
        case .삭제: return String(localized: "schedule_delete_title")
        case nil: return ""
        }
    }

    private var 목록_판: some View {
        VStack(spacing: 0) {
            기본_모드_카드
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 6)
            공휴일_카드
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            if let 줄 = viewModel.상태_줄 {
                RuleStateLine(text: 줄)
            }
            if viewModel.pendingSync {
                SyncPendingBar(text: String(localized: "schedule_sync_pending"),
                               retryTitle: String(localized: "schedule_sync_retry")) {
                    viewModel.다시_알린다()
                }
            }
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.rules, id: \.id) { rule in
                            ScheduleRowView(
                                rule: rule,
                                onEdit: { viewModel.편집을_연다(rule) },
                                onToggle: { on in Task { await viewModel.켬끔을_바꾼다(rule, enabled: on) } },
                                onDelete: { viewModel.삭제를_눌렀다(rule) }
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                // 4단계 Task 4 보완(5209a6e)과 같다 — 스크롤한 줄이 위 카드 밑으로 비치지 않게 자른다.
                .clipped()
                if let 빈_문구 = viewModel.listLoad.emptyText(isEmpty: viewModel.rules.isEmpty,
                                                          loaded: String(localized: "schedule_empty")) {
                    Text(빈_문구)
                        .font(.system(size: 15))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
            .frame(maxHeight: .infinity)
            RuleAddButton(title: String(localized: "schedule_add")) { viewModel.편집을_연다(nil) }
        }
        .background(KidCarePalette.paper)
    }

    // MARK: 기본 모드 카드 (:23-149, 칠하기 ScheduleFragment.kt:731-758)

    private var 기본_모드_카드: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("schedule_default_label")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KidCarePalette.ink)
            HStack(spacing: 6) {
                기본_모드_칸("", 제목: String(localized: "schedule_default_none"))
                기본_모드_칸(RingerMode.normal, 제목: String(localized: "schedule_mode_normal"))
                기본_모드_칸(RingerMode.vibrate, 제목: String(localized: "schedule_mode_vibrate"))
                기본_모드_칸(RingerMode.silent, 제목: String(localized: "schedule_mode_silent"))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruleCard()
    }

    /// 고른 칸만 그 모드의 옅은 색으로 차고 테두리·글자는 진한 색이다. '그대로 두기'는 ink_soft/line_soft(:738-747).
    private func 기본_모드_칸(_ mode: String, 제목: String) -> some View {
        let 고름 = viewModel.defaultMode == mode
        let look = mode.isEmpty ? ScheduleModeLook.그대로_두기 : ScheduleModeLook.of(mode)
        return Button {
            Task { await viewModel.기본_모드를_고른다(mode) }
        } label: {
            Text(제목)
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(고름 ? look.strong : KidCarePalette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(고름 ? look.soft : KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(고름 ? look.strong : KidCarePalette.lineSoft, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.설정_잠김)
        .opacity(viewModel.설정_잠김 ? 0.38 : 1)
    }

    // MARK: 공휴일 카드 (:151-219)

    private var 공휴일_카드: some View {
        HStack(spacing: 0) {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundStyle(KidCarePalette.berryInk)
                .frame(width: 24, height: 24)
                .padding(.trailing, 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("schedule_holiday_title")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(KidCarePalette.onBerrySoft)
                Text(verbatim: viewModel.공휴일_안내)
                    .font(.system(size: 13))
                    .foregroundStyle(KidCarePalette.onBerrySoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 사람이 민 값만 저장으로 간다 — 스냅샷이 대입한 값으로는 쓰기가 안 나간다(:227-230).
            Toggle("", isOn: Binding(
                get: { viewModel.holidayOff },
                set: { on in Task { await viewModel.공휴일을_바꾼다(on) } }
            ))
            .labelsHidden()
            .tint(KidCarePalette.sky)
            .frame(minHeight: 48)
            .padding(.leading, 8)
            .disabled(viewModel.설정_잠김)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(KidCarePalette.berrySoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 소리 모드 하나의 생김새 — 그림, 진한 색, 옅은 색. 스티커·하루 띠·편집 판 버튼이 같은 표를 쓴다
/// (ScheduleAdapter.kt:215-231). 그림 이름은 관리 탭과 같다(판정 기록 13).
struct ScheduleModeLook {
    let systemImage: String
    let strong: Color
    let soft: Color

    static func of(_ mode: String) -> ScheduleModeLook {
        switch mode {
        case RingerMode.normal:
            return ScheduleModeLook(systemImage: "speaker.wave.2.fill", strong: KidCarePalette.apricot, soft: KidCarePalette.apricotSoft)
        case RingerMode.vibrate:
            return ScheduleModeLook(systemImage: "iphone.radiowaves.left.and.right", strong: KidCarePalette.sky, soft: KidCarePalette.skySoft)
        case RingerMode.silent:
            return ScheduleModeLook(systemImage: "speaker.slash.fill", strong: KidCarePalette.grass, soft: KidCarePalette.grassSoft)
        default:
            // 모르는 값이면 색으로 아는 척하지 않는다(:229-230).
            return ScheduleModeLook(systemImage: "alarm", strong: KidCarePalette.inkSoft, soft: KidCarePalette.lineSoft)
        }
    }

    /// 기본 모드 카드의 '그대로 두기' 칸.
    static let 그대로_두기 = ScheduleModeLook(systemImage: "", strong: KidCarePalette.inkSoft, soft: KidCarePalette.lineSoft)
}

/// 규칙 한 장(item_schedule.xml). 누르는 자리 셋(고치기·켬끔·삭제)을 겹치지 않게 나눈다(:2-4).
struct ScheduleRowView: View {
    let rule: ScheduleDoc
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        let look = ScheduleModeLook.of(rule.mode)
        HStack(spacing: 0) {
            Button(action: onEdit) {
                HStack(spacing: 0) {
                    Image(systemName: look.systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                        .foregroundStyle(look.strong)
                        .frame(width: 40, height: 40)
                        .background(look.soft, in: Circle())
                        .padding(.trailing, 11)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: ScheduleText.daysText(rule.days))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(KidCarePalette.ink)
                        Text(verbatim: ScheduleText.rowDetail(rule))
                            .font(.system(size: 13))
                            .foregroundStyle(KidCarePalette.inkSoft)
                        DayRibbonView(start: rule.startMinute, end: rule.endMinute, color: look.strong)
                            .frame(height: 4)
                            .padding(.top, 4)
                            .opacity(rule.enabled ? 1 : 0.45)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
                // 꺼둔 규칙은 지워진 게 아니라 쉬는 것 — 흐리게만 한다(ScheduleAdapter.kt:56-58).
                .opacity(rule.enabled ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { rule.enabled }, set: onToggle))
                .labelsHidden()
                .tint(KidCarePalette.sky)
                .padding(.leading, 6)
            RowDeleteButton(label: String(localized: "schedule_delete"), action: onDelete)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .ruleCard()
    }
}

/// 하루 띠(item_schedule.xml:86-111). 바탕 line_soft·모서리 5(bg_ribbon_track.xml), 조각 폭은 분 비율.
struct DayRibbonView: View {
    let start: Int
    let end: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pieces = DayRibbon.pieces(start: start, end: end)
            let total = CGFloat(max(pieces.reduce(0) { $0 + $1.weight }, 1))
            HStack(spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    Rectangle()
                        .fill(piece.filled ? color : Color.clear)
                        .frame(width: geo.size.width * CGFloat(piece.weight) / total)
                }
            }
        }
        .background(KidCarePalette.lineSoft)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
```

- [ ] **Step 8: 편집 판**

`ios/KidCare/Guardian/ScheduleEditorView.swift`:

```swift
import SwiftUI

/// 예약 편집 판. 정본은 `fragment_schedule.xml` 편집 판(:314-758) — 제목, 요일 일곱, 시각 두 칸, 범위 안내,
/// 모드 셋, 진행 줄, 취소·저장. 바탕은 colorSurface(paper), 좌우 20·위아래 16.
/// 내비게이션 바는 시스템 뒤로 버튼만 보인다(판정 기록 4). 뒤로 가면 `뒤로_갔다()` 가 불린다.
struct ScheduleEditorView: View {

    let viewModel: ScheduleViewModel

    private enum 시각_칸: String, Identifiable {
        case 시작, 끝
        var id: String { rawValue }
    }

    @State private var 고르는_칸: 시각_칸?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: viewModel.편집기_제목)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)

                머리말("schedule_editor_days_label")
                요일_줄
                if viewModel.요일_경고 {
                    Text("schedule_editor_days_required")
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.berryInk)
                        .padding(.top, 8)
                }

                머리말("schedule_editor_time_label")
                HStack(spacing: 0) {
                    시각_버튼(.시작)
                    Text("schedule_range_separator")
                        .font(.system(size: 18))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.horizontal, 12)
                    시각_버튼(.끝)
                }
                if let 안내 = viewModel.범위_안내 {
                    Text(verbatim: 안내)
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.top, 8)
                }

                머리말("schedule_editor_mode_label")
                HStack(spacing: 8) {
                    모드_버튼(RingerMode.normal, 제목: String(localized: "schedule_mode_normal"))
                    모드_버튼(RingerMode.vibrate, 제목: String(localized: "schedule_mode_vibrate"))
                    모드_버튼(RingerMode.silent, 제목: String(localized: "schedule_mode_silent"))
                }

                HStack(spacing: 10) {
                    if viewModel.저장_중 {
                        ProgressView().controlSize(.small).frame(width: 18, height: 18)
                    }
                    if let 줄 = viewModel.편집_줄 {
                        Text(verbatim: 줄).font(.system(size: 13)).foregroundStyle(KidCarePalette.ink)
                    }
                }
                .padding(.top, 20)

                HStack(spacing: 10) {
                    // 취소는 외곽선 버튼이라 저장과 같은 격자에 앉는다(:721-742). 쓰기 중에는 잠근다.
                    Button { viewModel.취소를_눌렀다() } label: {
                        Text("schedule_editor_cancel")
                            .font(.system(size: 16))
                            .foregroundStyle(KidCarePalette.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KidCarePalette.lineSoft, lineWidth: 1.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { Task { await viewModel.저장을_눌렀다() } } label: {
                        Text("schedule_editor_save")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(KidCarePalette.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(KidCarePalette.sky, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(viewModel.저장_중)
                .opacity(viewModel.저장_중 ? 0.38 : 1)
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .clipped()
        .background(KidCarePalette.paper)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $고르는_칸) { 칸 in
            시각_시트(칸)
        }
    }

    private func 머리말(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(KidCarePalette.ink)
            .padding(.top, 24)
            .padding(.bottom, 10)
    }

    /// 요일 일곱. 여백은 칸 **사이**에만(:348-353). 고르면 sky 바탕·흰 글자, 안 고르면 paper_card·line_soft,
    /// 글자는 평일 ink·토 sky·일 berry_ink(res/color/day_chip_*.xml).
    private var 요일_줄: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let 고름 = viewModel.요일.contains(day)
                Button { viewModel.요일을_누른다(day) } label: {
                    Text(verbatim: ScheduleText.dayName(day))
                        .font(.system(size: 15))
                        .foregroundStyle(고름 ? KidCarePalette.onAccent : Self.요일_글자색(day))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(고름 ? KidCarePalette.sky : KidCarePalette.paperCard, in: Capsule())
                        .overlay(Capsule().stroke(고름 ? KidCarePalette.sky : KidCarePalette.lineSoft, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func 요일_글자색(_ day: Int) -> Color {
        switch day {
        case 6: return KidCarePalette.sky
        case 7: return KidCarePalette.berryInk
        default: return KidCarePalette.ink
        }
    }

    /// 살구빛 시각 칸(:555-591). 그림은 뺐다 — 머리말이 이미 "몇 시부터 몇 시까지"라 말한다(:544-547).
    private func 시각_버튼(_ 칸: 시각_칸) -> some View {
        let minute = 칸 == .시작 ? viewModel.시작분 : viewModel.끝분
        return Button { 고르는_칸 = 칸 } label: {
            Text(verbatim: ScheduleText.timeText(minute))
                .font(.system(size: 18))
                .monospacedDigit()
                .foregroundStyle(KidCarePalette.onApricotSoft)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(KidCarePalette.apricotSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 24시간 바퀴(판정 기록 5). 로캘은 고르기 하나에만 건다 — 라벨까지 걸면 6단계에 영어가 들어올 때
    /// 한국어 화면에 영어 라벨이 뜬다(4단계 Task 4 보고서).
    @ViewBuilder
    private func 시각_시트(_ 칸: 시각_칸) -> some View {
        VStack(spacing: 8) {
            if 칸 == .시작 {
                Text("schedule_editor_start_title").font(.system(size: 18, weight: .medium)).foregroundStyle(KidCarePalette.ink)
            } else {
                Text("schedule_editor_end_title").font(.system(size: 18, weight: .medium)).foregroundStyle(KidCarePalette.ink)
            }
            DatePicker("", selection: Binding(
                get: { ControlInput.date(minuteOfDay: 칸 == .시작 ? viewModel.시작분 : viewModel.끝분) },
                set: { date in
                    let minute = ControlInput.minuteOfDay(date)
                    if 칸 == .시작 { viewModel.시작분 = minute } else { viewModel.끝분 = minute }
                }
            ), displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "en_GB"))
        }
        .padding(.top, 24)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    /// 모드 버튼 셋(:614-695). 고른 것은 그 모드의 옅은 색 바탕·진한 테두리·진한 그림과 글자, 나머지는
    /// paper_card·line_soft·ink_soft. 색표는 목록 스티커와 같다(ScheduleFragment.kt:1085-1109).
    private func 모드_버튼(_ mode: String, 제목: String) -> some View {
        let 고름 = viewModel.모드 == mode
        let look = ScheduleModeLook.of(mode)
        return Button { viewModel.모드를_고른다(mode) } label: {
            VStack(spacing: 3) {
                Image(systemName: look.systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(verbatim: 제목).font(.system(size: 13)).lineLimit(1)
            }
            .foregroundStyle(고름 ? look.strong : KidCarePalette.inkSoft)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(고름 ? look.soft : KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(고름 ? look.strong : KidCarePalette.lineSoft, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 9: 탭에 붙인다**

`ios/KidCare/Guardian/GuardianRootView.swift`(4단계 Task 4 가 끝난 모양, HEAD `5209a6e`):

1. `controlViewModel` 프로퍼티 아래에 더한다:

```swift
    /// 예약 탭 뷰모델. 지도·관리와 같은 수명(계획서 5단계 판정 기록 7).
    @State private var scheduleViewModel: ScheduleViewModel
```

2. `init` 끝(`_controlViewModel = State(initialValue: control)` 다음)에 더한다:

```swift
        _scheduleViewModel = State(initialValue: ScheduleViewModel(familyId: familyId, childUid: childUid))
```

3. `TabPlaceholderView(tab: .schedule)` 로 시작하는 세 줄을 바꾼다:

```swift
                ScheduleView(viewModel: scheduleViewModel)
                    // 처음 보일 때 구독(ScheduleFragment.kt:279), 보일 때마다 못 보낸 알림 재시도 —
                    // 안드로이드는 첫 onResume(:293-297)과 onHiddenChanged(false)(:288-291)가 이 자리다.
                    .onAppear {
                        scheduleViewModel.시작한다()
                        scheduleViewModel.다시_알린다()
                    }
                    .tabItem { Label(GuardianTab.schedule.title, systemImage: GuardianTab.schedule.systemImage) }
                    .tag(GuardianTab.schedule)
```

4. `.task(id: scenePhase) { … }` 바로 아래에 더한다:

```swift
        // 앱으로 돌아왔을 때는 **보고 있는** 탭만 재시도한다 — 안드로이드 onResume 의 `if (!isHidden)`
        // (ScheduleFragment.kt:294-297, PlaceFragment.kt:290-294).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if selectedTab == .schedule { scheduleViewModel.다시_알린다() }
        }
```

5. `.onDisappear` 안 `controlViewModel.정리한다()` 아래에 `scheduleViewModel.정리한다()` 를 더한다.
6. `TabPlaceholderView` 타입 주석의 "예약·장소 5단계"를 "장소 5단계"로 고친다(알림은 그대로 남는다).

- [ ] **Step 10: 카탈로그**

공통 절차 A. 이미 있는 키(`schedule_day_*`, `schedule_time_format`, `map_no_child`)는 명령이 건너뛴다.

```
KEYS="schedule_add schedule_allday_cancel schedule_allday_confirm schedule_allday_message schedule_allday_title schedule_days_everyday schedule_days_none schedule_days_weekday schedule_days_weekend schedule_default_cleared schedule_default_label schedule_default_none schedule_default_saved schedule_delete schedule_delete_cancel schedule_delete_confirm schedule_delete_message schedule_delete_title schedule_deleting schedule_editor_cancel schedule_editor_days_label schedule_editor_days_required schedule_editor_end_title schedule_editor_mode_label schedule_editor_save schedule_editor_start_title schedule_editor_time_label schedule_editor_title_edit schedule_editor_title_new schedule_empty schedule_error_format schedule_holiday_cleared schedule_holiday_date schedule_holiday_next schedule_holiday_saved schedule_holiday_subtitle schedule_holiday_title schedule_holiday_unknown schedule_mode_normal schedule_mode_silent schedule_mode_vibrate schedule_no_family schedule_overlap_cancel schedule_overlap_confirm schedule_overlap_message schedule_overlap_message_more schedule_overlap_title schedule_range schedule_range_allday schedule_range_overnight schedule_range_separator schedule_row_off schedule_save_slow schedule_saving schedule_summary schedule_sync_failed_format schedule_sync_no_child schedule_sync_pending schedule_sync_retry schedule_sync_slow holiday_buddha holiday_children holiday_christmas holiday_chuseok holiday_foundation holiday_hangul holiday_independence holiday_liberation holiday_memorial holiday_new_year holiday_seollal holiday_substitute"
```

- [ ] **Step 11: 통과 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS. `ScheduleTextTests` 4개, `ScheduleViewModelTests` 15개가 새로 들어간다. `LocalizableCatalogTests.코드가_부르는_키는_카탈로그에_있다` 가 초록이면 Step 10 키 목록이 코드와 맞다는 뜻이다. 화면 모양은 "단계 마무리"에서 본다.

- [ ] **Step 12: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Guardian/KidCarePalette.swift ios/KidCare/Guardian/ScheduleText.swift ios/KidCare/Guardian/ScheduleViewModel.swift \
  ios/KidCare/Guardian/RuleListParts.swift ios/KidCare/Guardian/ScheduleView.swift ios/KidCare/Guardian/ScheduleEditorView.swift \
  ios/KidCare/Guardian/GuardianRootView.swift ios/KidCare/Localizable.xcstrings \
  ios/KidCareTests/RuleTestDoubles.swift ios/KidCareTests/ScheduleTextTests.swift ios/KidCareTests/ScheduleViewModelTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 5단계 Task 2: 예약 탭 — 하루 띠·기본 모드·공휴일, 저장하면 아이 폰에 알리고 못 알리면 그렇게 적는다"
```

---
### Task 3: 장소 탭 — 이름 첫 글자 스티커, 지도 한가운데 십자와 반경 원

**끝나면 '장소' 탭에 상태 줄, 못 보낸 알림 줄, 상한 안내, 장소 카드 목록(첫 글자 스티커·이름·알림·반경·삭제), 빈 목록 마스코트, '장소 추가' 버튼이 뜬다.** 장소를 누르거나 추가하면 편집 화면이 push 된다. 이름 칸, 가운데 십자가 고정된 260pt 지도와 반경 원, 반경 슬라이더(100~1000, 50 눈금), 도착·나섬 스위치가 들어 있고, 시스템 뒤로 버튼이 보인다. 지도는 아이의 마지막 위치에서 열리고, 그 위치를 모르면 한반도 전체로 열리며 안내가 뜬다. 뷰모델 테스트가 좌표를 정하는 세 순간, 반경 눈금, 20개 상한, 저장·삭제·깃발, 뒤로 가기를 못박는다.

**Files:**
- Create: `ios/KidCare/Guardian/PlaceText.swift`, `PlaceViewModel.swift`, `PlaceView.swift`, `PlaceEditorView.swift`, `PlacePickerMapView.swift`
- Create: `ios/KidCare/Assets.xcassets/Mascot3D.imageset/Contents.json`, `mascot_3d.png`(복사)
- Modify: `ios/KidCare/Guardian/GuardianRootView.swift`
- Modify: `ios/KidCare/Localizable.xcstrings`
- Test: `ios/KidCareTests/PlaceTextTests.swift`, `PlaceViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1(`PlaceDoc`, `PlaceRepository`, `ListLoad`, `RuleSyncStore`, `KotlinMath`), Task 2(`RuleStateLine`, `SyncPendingBar`, `RuleAddButton`, `RowDeleteButton`, `ruleCard()`, `WriteSleepFake`, `KidCarePalette` 새 색, `GuardianRootView` 의 `scenePhase` 재시도 자리); 4단계 `firstToFinish`, `FamilyRepository.fetchChildStatus`, `ChildStatusDoc`, `CommandRepository.send`, `errorMessage`; NMapsMap `NMFNaverMapView`·`NMFCircleOverlay`·`NMFMapViewCameraDelegate`·`NMFCameraUpdate`·`NMFMapChangedByGesture`
- Produces:
  - `enum PlaceText { radiusMeters(_:), notifyText(_:), summary(_:), rowDetail(_:), stickerLetter(_:), stickerIndex(_:) }`
  - `@MainActor @Observable final class PlaceViewModel` — Step 5 코드 블록의 공개면 그대로(`시작한다`, `정리한다`, `편집을_연다`, `취소를_눌렀다`, `뒤로_갔다`, `이름을_바꾼다`, `지도를_만졌다(centerLat:centerLng:)`, `지도가_멈췄다(centerLat:centerLng:사람이_옮겼나:)`, `저장을_눌렀다`, `삭제를_눌렀다`, `삭제를_확인했다`, `다시_알린다`, 상태 프로퍼티, `struct 좌표`·`카메라`·`반경_원`, `nonisolated static func 반경을_눈금에(_:)`·`유효한_좌표(_:_:)`)
  - `struct PlaceView`, `PlaceRowView`, `PlaceEditorView`, `PlacePickerMapView: UIViewRepresentable`, `PlaceCrosshair`

**정본:** `PlaceFragment.kt` 전체(줄 번호는 코드 주석), `PlaceAdapter.kt`(`bind` :37-56, 스티커 :58-88, `PlaceText` :96-120), `fragment_place.xml`(목록 판 :16-144, 편집 판 :146-364), `item_place.xml`, `ic_map_crosshair.xml`. 상수(`PlaceFragment.kt:921-953`): `MAX_PLACES = 20`(자녀 `PlaceWatcher.MAX_GEOFENCES = 20` 과 같아야 한다, `child/PlaceWatcher.kt:217`), `MIN_RADIUS_METERS = 100.0`, `MAX_RADIUS_METERS = 1000.0`, `RADIUS_STEP_METERS = 50.0`, `DEFAULT_RADIUS_METERS = 200.0`, `PLACE_ZOOM = 16.0`, `COUNTRY_ZOOM = 6.0`, `COUNTRY_LAT = 36.5`, `COUNTRY_LNG = 127.8`, `WRITE_TIMEOUT_MILLIS = 15_000L`, 원 채움 `0x333D6DF5`·테두리 `0xBB3D6DF5`·두께 4dp. 이름 최대 20자(`fragment_place.xml:187`). 치수: 편집 판 안쪽 여백 16(`:159`, 예약 편집의 좌우 20 과 다르다 — XML 그대로), 지도 높이 260·위 8, 십자 48, 슬라이더 위 4, 스위치 최소 높이 52, 취소·저장 높이 56·간격 8, 목록 위아래 12, 줄 안쪽 시작 14·끝 6·위아래 6, 스티커 40·글자 18 medium, 빈 목록 마스코트 104·불투명도 0.9·글자 위 16·줄 간격 3.

- [ ] **Step 1: 문구 테스트를 먼저 쓴다**

`ios/KidCareTests/PlaceTextTests.swift`:

```swift
import Testing
@testable import KidCare

/// 정본은 안드로이드 `PlaceText`·스티커(PlaceAdapter.kt:58-120).
struct PlaceTextTests {

    private func 장소(_ id: String = "p", name: String = "학교", radius: Double = 200, enter: Bool = true, exit: Bool = true) -> PlaceDoc {
        PlaceDoc(id: id, name: name, lat: 37.5, lng: 127, radiusMeters: radius, notifyEnter: enter, notifyExit: exit)
    }

    @Test("알림 문구 네 가지와 줄·요약(:109-120, :43-47)")
    func 문구() {
        #expect(PlaceText.notifyText(장소()) == "도착·이탈 알림")
        #expect(PlaceText.notifyText(장소(exit: false)) == "도착 알림만")
        #expect(PlaceText.notifyText(장소(enter: false)) == "이탈 알림만")
        #expect(PlaceText.notifyText(장소(enter: false, exit: false)) == "알림 꺼둠")
        #expect(PlaceText.rowDetail(장소()) == "도착·이탈 알림 · 반경 200m")
        #expect(PlaceText.summary(장소()) == "학교 (반경 200m)")
    }

    @Test("반경은 Math.round 로 정수 표기(:102-107)")
    func 반경() {
        #expect(PlaceText.radiusMeters(장소(radius: 200.4)) == 200)
        #expect(PlaceText.radiusMeters(장소(radius: 200.5)) == 201)
    }

    @Test("스티커 색은 문서 ID 의 자바 해시로, ID 가 비면 이름으로 고른다 — 순서가 바뀌어도 같은 장소는 같은 색(:58-72)")
    func 스티커() {
        #expect(PlaceText.stickerIndex(장소("3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f")) == 1)
        #expect(PlaceText.stickerIndex(장소("", name: "학교")) == 3)
        #expect(PlaceText.stickerIndex(장소("polygenelubricants")) == 0)
        #expect(PlaceText.stickerLetter(장소(name: "  학원")) == "학")
        #expect(PlaceText.stickerLetter(장소(name: "")) == "")
    }
}
```

- [ ] **Step 2: 뷰모델 테스트를 먼저 쓴다**

`ios/KidCareTests/PlaceViewModelTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

private actor PlaceFakeLog {
    private(set) var 저장한_장소: [PlaceDoc] = []
    private(set) var 지운_ID: [String] = []
    private(set) var 보낸_명령: [String] = []
    private var 쓰기_오류: (any Error)?
    private var 명령_오류: (any Error)?

    func 쓰기_오류를_둔다(_ error: (any Error)?) { 쓰기_오류 = error }
    func 명령_오류를_둔다(_ error: (any Error)?) { 명령_오류 = error }

    func 저장(_ doc: PlaceDoc) throws -> String {
        if let 쓰기_오류 { throw 쓰기_오류 }
        저장한_장소.append(doc)
        return doc.id
    }
    func 지운다(_ id: String) throws {
        if let 쓰기_오류 { throw 쓰기_오류 }
        지운_ID.append(id)
    }
    func 명령(_ type: String) throws -> String {
        if let 명령_오류 { throw 명령_오류 }
        보낸_명령.append(type)
        return "cmd-\(보낸_명령.count)"
    }
}

private final class PlaceFakes: Sendable {
    let log = PlaceFakeLog()
    let sleep = WriteSleepFake()
    let 저장_문 = TestGate()
    let 위치_문 = TestGate()
    let 목록 = TestCallbackBox<([PlaceDoc], Bool) -> Void>()
    let 목록_등록 = TestListenerRegistration()
}

/// 정본은 안드로이드 `guardian/PlaceFragment.kt`. 줄 번호는 각 테스트 이름에 적었다.
@MainActor
struct PlaceViewModelTests {

    private struct 가짜_오류: Error {}

    private func 만든다(
        _ f: PlaceFakes,
        childUid: String? = "child",
        아이_위치: (lat: Double, lng: Double)? = nil,
        위치가_기다린다: Bool = false,
        저장이_기다린다: Bool = false
    ) -> PlaceViewModel {
        var 번호 = 0
        return PlaceViewModel(
            familyId: "family",
            childUid: childUid,
            syncStore: RuleSyncStore(kind: .place, defaults: TestDefaults.isolated("PlaceViewModelTests")),
            placesObserve: { _, _, onChange, _ in
                f.목록.set(onChange)
                return f.목록_등록
            },
            placeSave: { _, _, doc in
                if 저장이_기다린다 { await f.저장_문.wait() }
                return try await f.log.저장(doc)
            },
            placeDelete: { _, _, id in try await f.log.지운다(id) },
            statusFetch: { _, _ in
                if 위치가_기다린다 { await f.위치_문.wait() }
                guard let 아이_위치 else { return nil }
                return ChildStatusDoc(["lat": 아이_위치.lat, "lng": 아이_위치.lng])
            },
            commandSend: { _, _, type, _ in try await f.log.명령(type) },
            writeSleep: { millis in await f.sleep.sleep(millis) },
            newId: {
                번호 += 1
                return "new-\(번호)"
            }
        )
    }

    private func 장소(_ id: String, _ name: String, radius: Double = 200) -> PlaceDoc {
        PlaceDoc(id: id, name: name, lat: 37.5, lng: 127.0, radiusMeters: radius, notifyEnter: true, notifyExit: true)
    }

    private func 시작하고_위치를_읽는다(_ vm: PlaceViewModel) async {
        vm.시작한다()
        await vm.아이_위치_읽기?.value
    }

    @Test("스냅샷은 이름의 UTF-16 순서로 정렬하고, 캐시본이면 불러오는 중이다(:446-455, 판정 기록 10)")
    func 정렬과_캐시() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.시작한다()
        f.목록.value?([장소("a", "Ａ"), 장소("b", "😀"), 장소("c", "가게")], true)
        await eventually { vm.places.count == 3 }
        #expect(vm.places.map(\.name) == ["가게", "😀", "Ａ"])
        #expect(vm.listLoad == .loading)
    }

    @Test("20개를 채우면 추가가 잠기고 이유가 뜨며, 편집도 열리지 않는다(:68-71, :461-463, :791-804)")
    func 상한() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.시작한다()
        f.목록.value?((1...19).map { 장소("id\($0)", "장소\($0)") }, false)
        await eventually { vm.places.count == 19 }
        #expect(vm.추가할_수_있나)
        #expect(vm.상한_안내 == nil)

        f.목록.value?((1...20).map { 장소("id\($0)", "장소\($0)") }, false)
        await eventually { vm.places.count == 20 }
        #expect(!vm.추가할_수_있나)
        #expect(vm.상한_안내 == "장소는 20개까지 정할 수 있어요. 새로 만들려면 안 쓰는 장소를 먼저 지워주세요.")
        vm.편집을_연다(nil)
        #expect(!vm.편집_중)
    }

    @Test("새 장소는 아이의 마지막 확인 위치에서 배율 16으로 열리고 반경 200 원이 그려진다(:410-444, :459-485, :515-536)")
    func 아이_위치에서_연다() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5665, 126.978))
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        #expect(vm.좌표를_골랐나)
        #expect(!vm.지도_안내가_보이나)
        #expect(vm.카메라_요청 == PlaceViewModel.카메라(lat: 37.5665, lng: 126.978, zoom: 16, 번호: 1))
        #expect(vm.원 == PlaceViewModel.반경_원(lat: 37.5665, lng: 126.978, radiusMeters: 200))
    }

    @Test("아이 위치를 모르면 한반도 전체(36.5, 127.8, 배율 6)로 열고, 지도를 안 만진 채 저장하면 막고 안내한다(:48-51, :526-529, :594-614)")
    func 위치_모름() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        #expect(vm.카메라_요청 == PlaceViewModel.카메라(lat: 36.5, lng: 127.8, zoom: 6, 번호: 1))
        #expect(vm.지도_안내가_보이나)
        #expect(vm.원 == nil)
        vm.이름을_바꾼다("학교")
        await vm.저장을_눌렀다()
        #expect(vm.편집_줄 == "아이 폰 위치를 아직 몰라서 지도가 넓게 열렸어요. 손으로 옮겨 찾아주세요.")
        #expect(await f.log.저장한_장소.isEmpty)
    }

    @Test("늦게 도착한 아이 위치는 부모가 아직 지도를 안 만진 편집기에만 들어간다 — (0,0)은 위치가 아니다(:421-437)")
    func 늦게_온_위치() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5, 127.0), 위치가_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        await f.위치_문.open()
        await vm.아이_위치_읽기?.value
        #expect(vm.좌표를_골랐나)
        #expect(vm.카메라_요청 == PlaceViewModel.카메라(lat: 37.5, lng: 127.0, zoom: 16, 번호: 2))

        let g = PlaceFakes()
        let 만진 = 만든다(g, 아이_위치: (37.5, 127.0), 위치가_기다린다: true)
        만진.시작한다()
        만진.편집을_연다(nil)
        만진.지도를_만졌다(centerLat: 36.0, centerLng: 127.5)
        await g.위치_문.open()
        await 만진.아이_위치_읽기?.value
        #expect(만진.원 == PlaceViewModel.반경_원(lat: 36.0, lng: 127.5, radiusMeters: 200))
        #expect(만진.카메라_요청?.번호 == 1)

        let h = PlaceFakes()
        let 영점 = 만든다(h, 아이_위치: (0, 0))
        await 시작하고_위치를_읽는다(영점)
        #expect(영점.아이_위치 == nil)
    }

    @Test("손이 닿는 순간의 가운데가 좌표이고, 그 뒤로는 사람이 옮긴 멈춤만 좌표를 바꾼다(:242-257, :274-283, 판정 기록 8)")
    func 지도_좌표() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        vm.지도가_멈췄다(centerLat: 36.5, centerLng: 127.8, 사람이_옮겼나: false)   // 한반도로 여는 프로그램 이동
        #expect(!vm.좌표를_골랐나)

        vm.지도를_만졌다(centerLat: 35.1, centerLng: 129.0)
        #expect(vm.좌표를_골랐나)
        #expect(vm.원 == PlaceViewModel.반경_원(lat: 35.1, lng: 129.0, radiusMeters: 200))

        vm.지도가_멈췄다(centerLat: 35.2, centerLng: 129.1, 사람이_옮겼나: true)
        #expect(vm.원?.lat == 35.2)
        vm.지도가_멈췄다(centerLat: 1, centerLng: 2, 사람이_옮겼나: false)
        #expect(vm.원?.lat == 35.2)
        vm.지도가_멈췄다(centerLat: 91, centerLng: 0, 사람이_옮겼나: true)
        #expect(vm.원?.lat == 35.2)
        vm.반경 = 450
        #expect(vm.원?.radiusMeters == 450)
        #expect(vm.반경_문구 == "반경 450m")
    }

    @Test("반경은 50m 눈금에 맞추고 100~1000 으로 자르며, 0 은 '안 정해짐'이라 기본 200 으로 연다(:476, :538-549)")
    func 반경_눈금() {
        #expect(PlaceViewModel.반경을_눈금에(175) == 200)
        #expect(PlaceViewModel.반경을_눈금에(174) == 150)
        #expect(PlaceViewModel.반경을_눈금에(125) == 150)
        #expect(PlaceViewModel.반경을_눈금에(25) == 100)
        #expect(PlaceViewModel.반경을_눈금에(5000) == 1000)

        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.편집을_연다(장소("p", "학교", radius: 175))
        #expect(vm.반경 == 200)
        #expect(vm.좌표를_골랐나)
        vm.취소를_눌렀다()
        vm.편집을_연다(장소("q", "학원", radius: 0))
        #expect(vm.반경 == 200)
    }

    @Test("이름은 20자에서 멈추고, 공백뿐이면 저장을 막는다 — 알림 문구에 그대로 들어가는 이름이다(:588-609, fragment_place.xml:187)")
    func 이름() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5, 127))
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        vm.이름을_바꾼다(String(repeating: "가", count: 25))
        #expect(vm.이름.count == 20)
        vm.이름을_바꾼다("   ")
        await vm.저장을_눌렀다()
        #expect(vm.이름_경고)
        #expect(await f.log.저장한_장소.isEmpty)
    }

    @Test("저장은 다듬은 이름과 편집 좌표·반경·스위치로 쓰고, 끝나야 닫고, sync_rules 를 보내 깃발을 내린다(:658-694, :620-656)")
    func 저장_흐름() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5665, 126.978), 저장이_기다린다: true)
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        vm.이름을_바꾼다("  학교 ")
        vm.반경 = 300
        vm.나섬_알림 = false
        #expect(vm.알림_없음_안내가_보이나 == false)
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        #expect(vm.편집_줄 == "저장 중…")
        #expect(vm.pendingSync)

        await f.저장_문.open()
        await 저장.value
        #expect(!vm.편집_중)
        #expect(await f.log.저장한_장소 == [PlaceDoc(id: "new-1", name: "학교", lat: 37.5665, lng: 126.978, radiusMeters: 300, notifyEnter: true, notifyExit: false)])
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
        #expect(!vm.pendingSync)
    }

    @Test("쓰기가 거부되면 편집기가 열린 채 이유를 말하고, 저장 중에 뒤로 갔으면 그 이유는 목록 줄로 간다(:688-692, 판정 기록 3)")
    func 쓰기_실패와_뒤로_가기() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5, 127), 저장이_기다린다: true)
        await f.log.쓰기_오류를_둔다(가짜_오류())
        await 시작하고_위치를_읽는다(vm)

        vm.편집을_연다(nil)
        vm.이름을_바꾼다("학교")
        let 첫_저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        await f.저장_문.open()
        await 첫_저장.value
        #expect(vm.편집_중)
        #expect(!vm.저장_중)
        #expect(vm.편집_줄 == errorMessage(가짜_오류()))

        let g = PlaceFakes()
        let 떠난 = 만든다(g, 아이_위치: (37.5, 127), 저장이_기다린다: true)
        await g.log.쓰기_오류를_둔다(가짜_오류())
        await 시작하고_위치를_읽는다(떠난)
        떠난.편집을_연다(nil)
        떠난.이름을_바꾼다("학원")
        let 두번째_저장 = Task { await 떠난.저장을_눌렀다() }
        await eventually { 떠난.저장_중 }
        떠난.뒤로_갔다()
        떠난.편집을_연다(nil)
        await g.저장_문.open()
        await 두번째_저장.value
        #expect(떠난.편집_중)
        #expect(떠난.편집_줄 == nil)
        #expect(떠난.상태_줄 == errorMessage(가짜_오류()))
    }

    @Test("삭제는 요약을 대고 물은 뒤 지우고 알린다. 알림이 실패하면 깃발이 남고, 다시 알리면 내린다(:696-721, :723-787)")
    func 삭제와_재시도() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.시작한다()
        let 학교 = 장소("school", "학교")
        vm.삭제를_눌렀다(학교)
        #expect(vm.삭제_확인 == 학교)
        #expect(vm.삭제_확인_문구 == "학교 (반경 200m)\n\n지우면 이곳에 도착하거나 나서도 알림이 오지 않아요.")
        vm.삭제_확인 = nil

        await f.log.명령_오류를_둔다(가짜_오류())
        await vm.삭제를_확인했다(학교)
        #expect(await f.log.지운_ID == ["school"])
        #expect(vm.상태_줄 == String(format: String(localized: "place_sync_failed_format"), errorMessage(가짜_오류())))
        #expect(vm.pendingSync)

        await f.log.명령_오류를_둔다(nil)
        await vm.다시_알린다()?.value
        #expect(!vm.pendingSync)
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
    }

    @Test("정리하면 리스너를 떼고, 늦게 도착한 아이 위치로 지도를 옮기지 않으며, 다시 구독하지 않는다(:899-919, 4단계 통합 검토 M1)")
    func 정리() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5, 127.0), 위치가_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        let 읽기 = vm.아이_위치_읽기
        vm.정리한다()
        #expect(f.목록_등록.removed)
        await f.위치_문.open()
        await 읽기?.value
        #expect(!vm.좌표를_골랐나)
        #expect(vm.카메라_요청?.번호 == 1)
        #expect(vm.다시_알린다() == nil)

        let g = PlaceFakes()
        let 먼저_닫힘 = 만든다(g)
        먼저_닫힘.정리한다()
        먼저_닫힘.시작한다()
        #expect(g.목록.value == nil)
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/PlaceTextTests -only-testing:KidCareTests/PlaceViewModelTests`
Expected: 컴파일 실패. `PlaceText`·`PlaceViewModel` 이 없다.

- [ ] **Step 4: 문구**

`ios/KidCare/Guardian/PlaceText.swift`:

```swift
import Foundation

/// 장소를 사람이 읽는 문장으로. 정본은 안드로이드 `PlaceText`(PlaceAdapter.kt:96-120)와 스티커(:58-88).
/// 목록 줄과 삭제 확인이 같은 이름으로 장소를 가리켜야 해서 조립은 여기 한 곳이다.
enum PlaceText {

    /// 반경은 문서에 실수로 있지만 화면에는 정수로만(:102-107). 반올림은 `Math.round`(판정 기록 10).
    static func radiusMeters(_ doc: PlaceDoc) -> Int {
        KotlinMath.roundToInt(doc.radiusMeters)
    }

    /// `도착·이탈 알림` / `도착 알림만` / `이탈 알림만` / `알림 꺼둠`(:109-115).
    static func notifyText(_ doc: PlaceDoc) -> String {
        switch (doc.notifyEnter, doc.notifyExit) {
        case (true, true): return String(localized: "place_notify_both")
        case (true, false): return String(localized: "place_notify_enter")
        case (false, true): return String(localized: "place_notify_exit")
        case (false, false): return String(localized: "place_notify_none")
        }
    }

    /// 목록 줄의 둘째 줄(PlaceAdapter.kt:43-47).
    static func rowDetail(_ doc: PlaceDoc) -> String {
        String(format: String(localized: "place_row_detail"), notifyText(doc), radiusMeters(doc))
    }

    /// 대화상자에서 장소 하나를 가리키는 한 줄(:117-119).
    static func summary(_ doc: PlaceDoc) -> String {
        String(format: String(localized: "place_summary"), doc.name, radiusMeters(doc))
    }

    /// 스티커 글자 — 이름의 첫 **글자**(판정 기록 11). 코틀린은 `name.trim().firstOrNull()`(:68).
    static func stickerLetter(_ doc: PlaceDoc) -> String {
        doc.name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? ""
    }

    /// 스티커 색 번호 0..<4. 색은 **문서 ID** 로 정한다 — 자리로 정하면 하나를 지울 때 아래 색이 전부
    /// 밀린다(:58-72). 자바 `hashCode` 와 `floorMod` 그대로라 안드로이드 폰과 같은 색이 나온다.
    static func stickerIndex(_ doc: PlaceDoc) -> Int {
        let key = doc.id.isEmpty ? doc.name : doc.id
        return KotlinMath.floorMod(KotlinMath.javaHashCode(key), 4)
    }
}
```

- [ ] **Step 5: 뷰모델**

`ios/KidCare/Guardian/PlaceViewModel.swift`:

```swift
import FirebaseFirestore
import Foundation
import Observation

/// 장소 탭의 두뇌. 정본은 안드로이드 `guardian/PlaceFragment.kt` — 줄 번호는 각 주석에 적었다.
///
/// ## 좌표는 숫자로 넣게 하지 않는다(:40-51)
/// 지도 **한가운데가 좌표다.** 지도는 아이의 마지막 확인 위치에서 열린다. 그 위치를 모르면 한반도 전체로
/// 열고 그 사실을 적는다 — 그럴듯한 기본 좌표를 찍어두면 부모가 그 자리를 "확인된 어딘가"로 읽는다.
///
/// ## 장소가 바뀌면 반드시 아이 폰에 알린다(:53-66)
/// 쓰기 갈래는 저장(만들기·고치기 공용)과 삭제 **둘뿐**이고, 둘 다 `쓰고_알린다` 한 곳을 지난다.
/// 특히 위험한 것은 삭제다 — 아이 폰이 모르면 지운 장소의 지오펜스가 계속 운다.
///
/// 세대 번호·뒤로 가기·깃발 규율은 `ScheduleViewModel` 과 같다(:98).
@Observable
@MainActor
final class PlaceViewModel {

    // MARK: - 상수 (PlaceFragment.kt:921-953, fragment_place.xml:187)

    /// 자녀 `PlaceWatcher.MAX_GEOFENCES`(child/PlaceWatcher.kt:217)와 같아야 한다.
    nonisolated static let maxPlaces = 20
    nonisolated static let minRadiusMeters = 100.0
    nonisolated static let maxRadiusMeters = 1000.0
    nonisolated static let radiusStepMeters = 50.0
    /// 학교·학원 한 채와 그 앞마당(:935-936).
    nonisolated static let defaultRadiusMeters = 200.0
    nonisolated static let placeZoom = 16.0
    nonisolated static let countryZoom = 6.0
    nonisolated static let countryLat = 36.5
    nonisolated static let countryLng = 127.8
    nonisolated static let writeTimeoutMillis: Int64 = 15_000
    nonisolated static let nameMaxLength = 20

    struct 좌표: Equatable {
        let lat: Double
        let lng: Double
    }

    /// 지도에게 보내는 카메라 요청. [번호] 가 바뀔 때만 지도가 움직인다 — 같은 요청을 그리기마다 다시
    /// 적용하면 부모가 옮겨 둔 지도를 도로 빼앗는다.
    struct 카메라: Equatable {
        let lat: Double
        let lng: Double
        let zoom: Double
        let 번호: Int
    }

    struct 반경_원: Equatable {
        let lat: Double
        let lng: Double
        let radiusMeters: Double
    }

    // MARK: - 목록 판

    let familyId: String
    let childUid: String?
    private(set) var places: [PlaceDoc] = []
    private(set) var listLoad: ListLoad = .loading
    private(set) var 상태_줄: String?
    private(set) var pendingSync = false
    /// 아이의 마지막 확인 위치. 한 번만 읽는다 — "그 동네"만 필요하다(:91-96).
    private(set) var 아이_위치: 좌표?
    var 삭제_확인: PlaceDoc?

    // MARK: - 편집 판 (:111-146)

    private(set) var 편집_중 = false
    private(set) var editorPlaceId: String?
    private(set) var editorNewDocId: String?
    private(set) var 이름 = ""
    private(set) var editorLat = 0.0
    private(set) var editorLng = 0.0
    var 반경 = PlaceViewModel.defaultRadiusMeters
    var 도착_알림 = true
    var 나섬_알림 = true
    /// 지금 좌표가 **뜻이 있는 값인가**(:130-144). (0,0)인지로 판단하지 않는다.
    private(set) var 좌표를_골랐나 = false
    private(set) var 저장_중 = false
    private(set) var 편집_줄: String?
    private(set) var 이름_경고 = false
    private(set) var 카메라_요청: 카메라?

    /// 테스트가 기다릴 수 있게 둔다.
    @ObservationIgnored private(set) var 아이_위치_읽기: Task<Void, Never>?
    @ObservationIgnored private var 카메라_번호 = 0
    @ObservationIgnored private var writeGeneration = 0
    @ObservationIgnored private var 떠난_저장_세대: Int?
    @ObservationIgnored private var 시작함 = false
    /// `정리한다()` 뒤에는 새 구독·새 명령·늦은 카메라 이동을 만들지 않는다(4단계 통합 검토 M1).
    @ObservationIgnored private var 닫힘 = false
    @ObservationIgnored private var placeListener: ListenerRegistration?
    @ObservationIgnored private var syncRetryTask: Task<Void, Never>?

    private let syncStore: RuleSyncStore
    private let placesObserve: @Sendable (String, String, @escaping ([PlaceDoc], Bool) -> Void, @escaping (Error) -> Void) -> ListenerRegistration
    private let placeSave: @Sendable (String, String, PlaceDoc) async throws -> String
    private let placeDelete: @Sendable (String, String, String) async throws -> Void
    private let statusFetch: @Sendable (String, String) async throws -> ChildStatusDoc?
    private let commandSend: @Sendable (String, String, String, [String: String]) async throws -> String
    private let writeSleep: @Sendable (Int64) async -> Void
    private let newId: () -> String

    init(
        familyId: String,
        childUid: String?,
        syncStore: RuleSyncStore = RuleSyncStore(kind: .place),
        placesObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping ([PlaceDoc], Bool) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = PlaceRepository.observePlaces,
        placeSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ doc: PlaceDoc) async throws -> String = PlaceRepository.savePlace,
        placeDelete: @escaping @Sendable (_ familyId: String, _ childUid: String, _ id: String) async throws -> Void = PlaceRepository.deletePlace,
        statusFetch: @escaping @Sendable (_ familyId: String, _ childUid: String) async throws -> ChildStatusDoc? = FamilyRepository.fetchChildStatus,
        commandSend: @escaping @Sendable (_ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]) async throws -> String = CommandRepository.send,
        writeSleep: @escaping @Sendable (_ millis: Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        },
        newId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.syncStore = syncStore
        self.placesObserve = placesObserve
        self.placeSave = placeSave
        self.placeDelete = placeDelete
        self.statusFetch = statusFetch
        self.commandSend = commandSend
        self.writeSleep = writeSleep
        self.newId = newId
    }

    // MARK: - 구독 (:357-455)

    func 시작한다() {
        guard !시작함, !닫힘 else { return }
        시작함 = true
        guard let childUid else {
            listLoad = .loaded
            상태_줄 = String(localized: "map_no_child")
            return
        }
        pendingSync = syncStore.pendingSync(childUid: childUid)
        아이_위치_읽기 = Task { [weak self] in await self?.아이_위치를_읽는다(childUid) }
        placeListener = placesObserve(familyId, childUid, { [weak self] docs, fromCache in
            Task { @MainActor in self?.장소가_바뀌었다(docs, fromCache: fromCache) }
        }, { [weak self] error in
            Task { @MainActor in
                self?.listLoad = .failed
                self?.상태_줄 = String(format: String(localized: "place_error_format"), errorMessage(error))
            }
        })
    }

    func 정리한다() {
        닫힘 = true
        placeListener?.remove()
        placeListener = nil
        syncRetryTask?.cancel()
        syncRetryTask = nil
        아이_위치_읽기?.cancel()
        writeGeneration += 1
    }

    /// 편의를 위한 한 번 읽기다. 실패해도 아무 말도 하지 않는다(:410-444).
    private func 아이_위치를_읽는다(_ childUid: String) async {
        guard let status = try? await statusFetch(familyId, childUid) else { return }
        // await 사이에 정리됐으면 아무것도 바꾸지 않는다(4단계 통합 검토 M1).
        guard !닫힘, !Task.isCancelled else { return }
        guard Self.유효한_좌표(status.lat, status.lng), !(status.lat == 0 && status.lng == 0) else { return }
        아이_위치 = 좌표(lat: status.lat, lng: status.lng)
        // 편집을 연 채 기다리고 있었고 부모가 아직 지도를 안 만졌을 때만 옮긴다 — 정해 둔 자리를 뒤늦게
        // 뺏으면 안 된다(:428-436).
        if 편집_중 && !좌표를_골랐나 {
            editorLat = status.lat
            editorLng = status.lng
            좌표를_골랐나 = true
            지도를_편집_좌표로_옮긴다()
        }
    }

    /// 이름순 — 자녀 폰이 지오펜스 20개를 자르는 기준도 이름순이라 두 화면이 같은 순서를 본다(:447-450).
    private func 장소가_바뀌었다(_ docs: [PlaceDoc], fromCache: Bool) {
        places = docs.sorted { a, b in
            a.name == b.name ? KotlinMath.precedes(a.id, b.id) : KotlinMath.precedes(a.name, b.name)
        }
        listLoad = ListLoad.after(fromCache: fromCache)
    }

    var 추가할_수_있나: Bool { places.count < Self.maxPlaces }

    /// 추가 버튼을 잠그면서 이유를 안 적으면 부모는 고장인 줄 안다(:70-71, :798-803).
    var 상한_안내: String? {
        추가할_수_있나 ? nil : String(format: String(localized: "place_limit_notice"), Self.maxPlaces)
    }

    // MARK: - 편집 판 (:457-616)

    func 편집을_연다(_ doc: PlaceDoc?) {
        if doc == nil && !추가할_수_있나 { return }
        editorPlaceId = doc?.id
        editorNewDocId = doc == nil ? newId() : nil
        이름 = doc?.name ?? ""
        editorLat = doc?.lat ?? 아이_위치?.lat ?? 0
        editorLng = doc?.lng ?? 아이_위치?.lng ?? 0
        좌표를_골랐나 = (doc != nil || 아이_위치 != nil) && Self.유효한_좌표(editorLat, editorLng)
        let 문서_반경 = doc?.radiusMeters ?? 0
        반경 = Self.반경을_눈금에(문서_반경 > 0 ? 문서_반경 : Self.defaultRadiusMeters)
        도착_알림 = doc?.notifyEnter ?? true
        나섬_알림 = doc?.notifyExit ?? true
        저장_중 = false
        편집_줄 = nil
        이름_경고 = false
        상태_줄 = nil
        편집_중 = true
        지도를_편집_좌표로_옮긴다()
    }

    func 취소를_눌렀다() {
        guard !저장_중 else { return }
        writeGeneration += 1
        편집기를_닫는다()
    }

    /// 시스템 뒤로 가기(판정 기록 3). `ScheduleViewModel.뒤로_갔다` 와 같다.
    func 뒤로_갔다() {
        guard 편집_중 else { return }
        if 저장_중 { 떠난_저장_세대 = writeGeneration }
        writeGeneration += 1
        편집기를_닫는다()
    }

    private func 편집기를_닫는다() {
        편집_중 = false
        저장_중 = false
        editorPlaceId = nil
        editorNewDocId = nil
        편집_줄 = nil
    }

    func 이름을_바꾼다(_ text: String) {
        이름 = String(text.prefix(Self.nameMaxLength))
    }

    var 편집기_제목: String {
        editorPlaceId == nil
            ? String(localized: "place_editor_title_new")
            : String(localized: "place_editor_title_edit")
    }

    var 반경_문구: String {
        String(format: String(localized: "place_editor_radius_value"), Int(반경))
    }

    /// 둘 다 끄면 이 장소로는 알림이 안 온다는 안내(:846-850).
    var 알림_없음_안내가_보이나: Bool { !도착_알림 && !나섬_알림 }

    /// 아이 위치를 몰라 넓게 열었다는 안내. 지도를 만지면 사라진다(:852-856).
    var 지도_안내가_보이나: Bool { !좌표를_골랐나 }

    /// 지도에 그릴 반경 원. 편집 중이고 좌표를 골랐을 때만(:560-568).
    var 원: 반경_원? {
        guard 편집_중, 좌표를_골랐나, Self.유효한_좌표(editorLat, editorLng) else { return nil }
        return 반경_원(lat: editorLat, lng: editorLng, radiusMeters: 반경)
    }

    /// 사람이 지도에 손을 댔다(:245-252). 그 순간의 가운데를 곧바로 좌표로 삼는다(판정 기록 8).
    func 지도를_만졌다(centerLat: Double, centerLng: Double) {
        guard 편집_중, !좌표를_골랐나, Self.유효한_좌표(centerLat, centerLng) else { return }
        editorLat = centerLat
        editorLng = centerLng
        좌표를_골랐나 = true
    }

    /// 카메라가 멈췄다. 사람이 옮긴 멈춤만 좌표로 받는다(:274-283, 판정 기록 8).
    func 지도가_멈췄다(centerLat: Double, centerLng: Double, 사람이_옮겼나: Bool) {
        guard 사람이_옮겼나, 편집_중, Self.유효한_좌표(centerLat, centerLng) else { return }
        editorLat = centerLat
        editorLng = centerLng
    }

    /// 편집 좌표로, 모르면 한반도 전체로(:504-536). 카메라는 가운데와 배율만 정하므로 지도 크기와 무관하다 —
    /// 안드로이드가 레이아웃을 기다린 것(:510-512)은 GONE 이던 `MapView` 사정이라 여기에는 없다.
    private func 지도를_편집_좌표로_옮긴다() {
        if 좌표를_골랐나 && !Self.유효한_좌표(editorLat, editorLng) { 좌표를_골랐나 = false }
        카메라_번호 += 1
        카메라_요청 = 좌표를_골랐나
            ? 카메라(lat: editorLat, lng: editorLng, zoom: Self.placeZoom, 번호: 카메라_번호)
            : 카메라(lat: Self.countryLat, lng: Self.countryLng, zoom: Self.countryZoom, 번호: 카메라_번호)
    }

    /// 50m 눈금에 맞추고 범위로 자른다(:538-549). 콘솔에서 손으로 고친 문서도 화면을 못 열게 만들면 안 된다.
    nonisolated static func 반경을_눈금에(_ meters: Double) -> Double {
        let steps = KotlinMath.roundToInt((meters - minRadiusMeters) / radiusStepMeters)
        return min(max(minRadiusMeters + Double(steps) * radiusStepMeters, minRadiusMeters), maxRadiusMeters)
    }

    nonisolated static func 유효한_좌표(_ lat: Double, _ lng: Double) -> Bool {
        lat.isFinite && lng.isFinite && (-90.0...90.0).contains(lat) && (-180.0...180.0).contains(lng)
    }

    /// 관문 둘 — 이름이 비면 막고, 좌표를 한 번도 안 골랐으면 막는다(:588-616).
    func 저장을_눌렀다() async {
        guard !저장_중 else { return }
        let 다듬은_이름 = 이름.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !다듬은_이름.isEmpty else {
            이름_경고 = true
            return
        }
        이름_경고 = false
        guard 좌표를_골랐나 else {
            편집_줄 = String(localized: "place_editor_no_child_location")
            return
        }
        await 장소를_저장한다(이름: 다듬은_이름)
    }

    // MARK: - 쓰기 (:618-721)

    private func 장소를_저장한다(이름 name: String) async {
        guard let childUid else {
            편집_줄 = String(localized: "place_no_family")
            return
        }
        let doc = PlaceDoc(id: editorPlaceId ?? editorNewDocId ?? newId(), name: name,
                           lat: editorLat, lng: editorLng, radiusMeters: 반경,
                           notifyEnter: 도착_알림, notifyExit: 나섬_알림)
        저장_중 = true
        let (fid, save) = (familyId, placeSave)
        await 쓰고_알린다(
            바쁨_문구: String(localized: "place_saving"),
            쓰기: { _ = try await save(fid, childUid, doc) },
            끝나면: { 늦음 in
                편집기를_닫는다()
                상태_줄 = 늦음 ? String(localized: "place_save_slow") : nil
            },
            실패하면: { 이유 in
                저장_중 = false
                편집_줄 = 이유
            }
        )
    }

    func 삭제를_눌렀다(_ doc: PlaceDoc) {
        삭제_확인 = doc
    }

    var 삭제_확인_문구: String {
        guard let 삭제_확인 else { return "" }
        return String(format: String(localized: "place_delete_message"), PlaceText.summary(삭제_확인))
    }

    func 삭제를_확인했다(_ doc: PlaceDoc) async {
        guard let childUid else {
            상태_줄 = String(localized: "place_no_family")
            return
        }
        상태_줄 = String(localized: "place_deleting")
        let (fid, delete, id) = (familyId, placeDelete, doc.id)
        await 쓰고_알린다(
            바쁨_문구: nil,
            쓰기: { try await delete(fid, childUid, id) },
            끝나면: { 늦음 in 상태_줄 = 늦음 ? String(localized: "place_save_slow") : nil },
            실패하면: { 이유 in 상태_줄 = 이유 }
        )
    }

    /// 장소를 쓰는 **유일한 두 갈래**가 지나는 자리(:620-656). 쓰기 뒤에 반드시 `sync_rules` 를 보낸다.
    private func 쓰고_알린다(
        바쁨_문구: String?,
        쓰기: @escaping @Sendable () async throws -> Void,
        끝나면: (_ 늦음: Bool) -> Void,
        실패하면: (_ 이유: String) -> Void
    ) async {
        writeGeneration += 1
        let generation = writeGeneration
        if let 바쁨_문구 { 편집_줄 = 바쁨_문구 }
        깃발을_바꾼다(true)
        do {
            let done: Void? = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep, operation: 쓰기)
            if generation == writeGeneration {
                끝나면(done == nil)
            } else if 목록이_이어받았나(generation), done == nil {
                상태_줄 = String(localized: "place_save_slow")
            }
            await 아이에게_알린다(generation)
        } catch {
            if generation == writeGeneration {
                실패하면(errorMessage(error))
            } else if 목록이_이어받았나(generation) {
                상태_줄 = errorMessage(error)
            }
        }
    }

    // MARK: - 아이 폰에 알리기 (:723-787)

    /// 예약 규칙과 **같은** 명령을 쓴다 — 자녀 쪽이 그 하나로 둘 다 다시 읽는다(:727-730).
    private func 아이에게_알린다(_ generation: Int) async {
        guard let childUid else {
            깃발을_바꾼다(false)
            if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "place_sync_no_child") }
            return
        }
        let (fid, send) = (familyId, commandSend)
        do {
            let commandId = try await firstToFinish(timeoutMillis: Self.writeTimeoutMillis, sleep: writeSleep) {
                try await send(fid, childUid, CommandType.syncRules, [:])
            }
            guard commandId != nil else {
                if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "place_sync_slow") }
                return
            }
            깃발을_바꾼다(false)
        } catch {
            if 글자를_쓸_수_있나(generation) {
                상태_줄 = String(format: String(localized: "place_sync_failed_format"), errorMessage(error))
            }
        }
    }

    @discardableResult
    func 다시_알린다() -> Task<Void, Never>? {
        guard pendingSync, childUid != nil, syncRetryTask == nil, !닫힘 else { return nil }
        let generation = writeGeneration
        let task = Task { [weak self] in
            await self?.아이에게_알린다(generation)
            self?.syncRetryTask = nil
        }
        syncRetryTask = task
        return task
    }

    private func 깃발을_바꾼다(_ value: Bool) {
        guard let childUid else { return }
        syncStore.setPendingSync(childUid: childUid, value)
        pendingSync = value
    }

    private func 목록이_이어받았나(_ generation: Int) -> Bool {
        떠난_저장_세대 == generation && writeGeneration == generation + 1
    }

    private func 글자를_쓸_수_있나(_ generation: Int) -> Bool {
        generation == writeGeneration || 목록이_이어받았나(generation)
    }
}
```

`쓰고_알린다` 의 `끝나면`·`실패하면` 은 탈출하지 않는 클로저라 `await` 뒤에 불러도 되고, 암시적 `self` 를 쓸 수 있다.

- [ ] **Step 6: 편집 지도**

`ios/KidCare/Guardian/PlacePickerMapView.swift`:

```swift
import NMapsGeometry
import NMapsMap
import SwiftUI
import UIKit

/// 장소 편집의 지도. 정본은 안드로이드 `PlaceFragment` 의 지도 부분(:235-283, :504-580)과
/// `fragment_place.xml:228-249`. 지도 뷰는 `makeUIView` 에서 한 번만 만들고, `updateUIView` 는 카메라
/// 요청(번호가 바뀔 때만)과 반경 원만 손댄다.
struct PlacePickerMapView: UIViewRepresentable {

    var camera: PlaceViewModel.카메라?
    var circle: PlaceViewModel.반경_원?
    /// 손가락이 닿은 순간. 그때의 지도 가운데를 준다(판정 기록 8).
    var onTouchDown: (_ centerLat: Double, _ centerLng: Double) -> Void
    var onTouchEnd: () -> Void
    /// 카메라가 멈췄다. [byUser] 는 마지막 움직임이 제스처였는가.
    var onIdle: (_ centerLat: Double, _ centerLng: Double, _ byUser: Bool) -> Void

    /// PlaceFragment.kt:949-953 — 채움 `0x333D6DF5`, 테두리 `0xBB3D6DF5`, 4dp. 정확도 원(지도 탭)보다
    /// 진하다 — 저건 번짐이고 이건 부모가 지금 정하는 값이다.
    static let fillColor = UIColor(red: 0x3D / 255.0, green: 0x6D / 255.0, blue: 0xF5 / 255.0, alpha: 0x33 / 255.0)
    static let strokeColor = UIColor(red: 0x3D / 255.0, green: 0x6D / 255.0, blue: 0xF5 / 255.0, alpha: 0xBB / 255.0)
    static let strokeWidth: Double = 4

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlacePickerMapView
        weak var mapView: NMFMapView?
        var circleOverlay: NMFCircleOverlay?
        var lastCameraNumber: Int?
        /// 마지막 카메라 움직임의 원인. `NMFMapChangedByGesture`(-1)일 때만 사람이 옮긴 것이다.
        var lastReason = NMFMapChangedByDeveloper

        init(parent: PlacePickerMapView) {
            self.parent = parent
        }

        /// 지속시간 0 누르기 — 손이 닿는 순간 `.began`. 안드로이드 `ACTION_DOWN`(:249) 자리다.
        @objc func touched(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard let mapView else { return }
                let target = mapView.cameraPosition.target
                parent.onTouchDown(target.lat, target.lng)
            case .ended, .cancelled, .failed:
                parent.onTouchEnd()
            default:
                break
            }
        }

        /// 지도 자신의 이동·확대 제스처와 함께 인식한다 — 안드로이드 리스너가 `false` 를 돌려 지도 처리를
        /// 잇게 한 것과 같다(:253-254).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> NMFNaverMapView {
        let view = NMFNaverMapView(frame: .zero)
        // PlaceFragment.kt:262-267 — 줌·위치·축척 버튼 끔, 로고 여백 왼쪽 8·아래 8.
        view.showZoomControls = false
        view.showLocationButton = false   // 보호자 앱은 위치 권한을 쓰지 않는다(설계서 §1)
        view.showScaleBar = false
        view.mapView.logoMargin = UIEdgeInsets(top: 0, left: 8, bottom: 8, right: 0)
        view.mapView.addCameraDelegate(delegate: context.coordinator)

        let touch = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.touched(_:)))
        touch.minimumPressDuration = 0
        touch.cancelsTouchesInView = false
        touch.delegate = context.coordinator
        view.mapView.addGestureRecognizer(touch)

        context.coordinator.mapView = view.mapView
        return view
    }

    func updateUIView(_ view: NMFNaverMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if let camera, camera.번호 != coordinator.lastCameraNumber {
            coordinator.lastCameraNumber = camera.번호
            // 개발자 이동이라 뒤따르는 멈춤은 `byUser == false` 로 온다 — 뷰모델이 버린다.
            view.mapView.moveCamera(NMFCameraUpdate(scrollTo: NMGLatLng(lat: camera.lat, lng: camera.lng), zoomTo: camera.zoom))
        }

        guard let circle else {
            coordinator.circleOverlay?.mapView = nil
            coordinator.circleOverlay = nil
            return
        }
        let center = NMGLatLng(lat: circle.lat, lng: circle.lng)
        if let overlay = coordinator.circleOverlay {
            overlay.center = center
            overlay.radius = circle.radiusMeters
        } else {
            // 중심과 반경을 넣은 **뒤에** 지도에 붙인다(NMFCircleOverlay.h:22-24, 안드로이드 :573-575).
            let overlay = NMFCircleOverlay(center, radius: circle.radiusMeters)
            overlay.fillColor = Self.fillColor
            overlay.outlineColor = Self.strokeColor
            overlay.outlineWidth = Self.strokeWidth
            overlay.mapView = view.mapView
            coordinator.circleOverlay = overlay
        }
    }

    static func dismantleUIView(_ view: NMFNaverMapView, coordinator: Coordinator) {
        view.mapView.removeCameraDelegate(delegate: coordinator)
        coordinator.circleOverlay?.mapView = nil
        coordinator.circleOverlay = nil
    }
}

/// 네이버 SDK 헤더는 동시성 주석이 없다. 콜백은 메인 스레드에서 오므로 `@preconcurrency` 준수로
/// 메인 액터 격리를 런타임에 확인하게 둔다(`nonisolated(unsafe)` 를 쓰지 않는다).
extension PlacePickerMapView.Coordinator: @preconcurrency NMFMapViewCameraDelegate {

    func mapView(_ mapView: NMFMapView, cameraWillChangeByReason reason: Int, animated: Bool) {
        lastReason = reason
    }

    func mapViewCameraIdle(_ mapView: NMFMapView) {
        let target = mapView.cameraPosition.target
        parent.onIdle(target.lat, target.lng, lastReason == NMFMapChangedByGesture)
        lastReason = NMFMapChangedByDeveloper
    }
}

/// 지도 한가운데 고정 십자(`ic_map_crosshair.xml`). 48 격자에 흰 밑획 6 을 먼저 깔고 잉크 윗획 2.5 를
/// 얹는다 — 흰 도로·초록 공원·파란 물 어느 바닥에서도 한쪽은 보인다. 색은 XML 값 `#4A4038`(판정 기록 13).
/// 가운데를 비워 찍으려는 지점을 가리지 않는다.
struct PlaceCrosshair: View {

    private static let 잉크 = Color(.sRGB, red: 0x4A / 255.0, green: 0x40 / 255.0, blue: 0x38 / 255.0, opacity: 1)

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 48
            var 획 = Path()
            for (from, to) in [(CGPoint(x: 24, y: 6), CGPoint(x: 24, y: 18)),
                               (CGPoint(x: 24, y: 30), CGPoint(x: 24, y: 42)),
                               (CGPoint(x: 6, y: 24), CGPoint(x: 18, y: 24)),
                               (CGPoint(x: 30, y: 24), CGPoint(x: 42, y: 24))] {
                획.move(to: from)
                획.addLine(to: to)
            }
            let 고리 = Path(ellipseIn: CGRect(x: 15, y: 15, width: 18, height: 18))
            let 크기 = CGAffineTransform(scaleX: scale, y: scale)
            let 선 = 획.applying(크기)
            let 원 = 고리.applying(크기)
            context.stroke(선, with: .color(.white), style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round))
            context.stroke(원, with: .color(.white), lineWidth: 6 * scale)
            context.stroke(선, with: .color(Self.잉크), style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round))
            context.stroke(원, with: .color(Self.잉크), lineWidth: 2.5 * scale)
        }
    }
}
```

- [ ] **Step 7: 화면**

`ios/KidCare/Guardian/PlaceView.swift`:

```swift
import SwiftUI

/// 장소 탭 목록 판. 정본은 `fragment_place.xml` 목록 판(:16-144)과 `item_place.xml`. 위에서 아래로
/// 상태 줄 → 못 보낸 알림 줄 → 상한 안내 → 장소 목록(비면 마스코트) → 추가 버튼.
struct PlaceView: View {

    let viewModel: PlaceViewModel

    var body: some View {
        NavigationStack {
            목록_판
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: Binding(
                    get: { viewModel.편집_중 },
                    set: { if !$0 { viewModel.뒤로_갔다() } }
                )) {
                    PlaceEditorView(viewModel: viewModel)
                }
        }
        .alert(String(localized: "place_delete_title"), isPresented: Binding(
            get: { viewModel.삭제_확인 != nil },
            set: { if !$0 { viewModel.삭제_확인 = nil } }
        ), presenting: viewModel.삭제_확인) { doc in
            Button(String(localized: "place_delete_confirm"), role: .destructive) {
                Task { await viewModel.삭제를_확인했다(doc) }
            }
            Button(String(localized: "place_delete_cancel"), role: .cancel) {}
        } message: { _ in
            Text(verbatim: viewModel.삭제_확인_문구)
        }
    }

    private var 목록_판: some View {
        VStack(spacing: 0) {
            if let 줄 = viewModel.상태_줄 {
                RuleStateLine(text: 줄)
            }
            if viewModel.pendingSync {
                SyncPendingBar(text: String(localized: "place_sync_pending"),
                               retryTitle: String(localized: "place_sync_retry")) {
                    viewModel.다시_알린다()
                }
            }
            if let 안내 = viewModel.상한_안내 {
                // colorSurfaceVariant 바탕, 좌우 20·위아래 10(:72-81).
                Text(verbatim: 안내)
                    .font(.system(size: 15))
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(KidCarePalette.paperFold)
            }
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.places, id: \.id) { place in
                            PlaceRowView(
                                place: place,
                                onEdit: { viewModel.편집을_연다(place) },
                                onDelete: { viewModel.삭제를_눌렀다(place) }
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .clipped()
                if let 빈_문구 = viewModel.listLoad.emptyText(isEmpty: viewModel.places.isEmpty,
                                                          loaded: String(localized: "place_empty")) {
                    // 이 탭은 처음 켰을 때 늘 비어 있다 — 눈이 먼저 갈 곳이 있어야 "고장인가"가 아니라
                    // "아직 없구나"로 읽힌다(:96-99).
                    VStack(spacing: 0) {
                        Image("Mascot3D")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 104, height: 104)
                            .opacity(0.9)
                            .accessibilityHidden(true)
                        Text(verbatim: 빈_문구)
                            .font(.system(size: 15))
                            .lineSpacing(3)
                            .foregroundStyle(KidCarePalette.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .frame(maxHeight: .infinity)
            RuleAddButton(title: String(localized: "place_add"), enabled: viewModel.추가할_수_있나) {
                viewModel.편집을_연다(nil)
            }
        }
        .background(KidCarePalette.paper)
    }
}

/// 장소 한 장(item_place.xml). 스티커든 글자든 누르면 고치기, 오른쪽 끝은 삭제다.
struct PlaceRowView: View {
    let place: PlaceDoc
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// (진한 색, 옅은 색) 짝 넷 — 순서가 곧 번호다(PlaceAdapter.kt:80-88).
    private static let 스티커_색: [(strong: Color, soft: Color)] = [
        (KidCarePalette.sky, KidCarePalette.skySoft),
        (KidCarePalette.apricot, KidCarePalette.apricotSoft),
        (KidCarePalette.grass, KidCarePalette.grassSoft),
        (KidCarePalette.berryInk, KidCarePalette.berrySoft),
    ]

    var body: some View {
        let 색 = Self.스티커_색[PlaceText.stickerIndex(place)]
        HStack(spacing: 0) {
            Button(action: onEdit) {
                HStack(spacing: 0) {
                    Text(verbatim: PlaceText.stickerLetter(place))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(색.strong)
                        .frame(width: 40, height: 40)
                        .background(색.soft, in: Circle())
                        .padding(.trailing, 11)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: place.name)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(KidCarePalette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(verbatim: PlaceText.rowDetail(place))
                            .font(.system(size: 13))
                            .foregroundStyle(KidCarePalette.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
                // 알림을 둘 다 꺼둔 장소는 쉬는 것 — 흐리게만(PlaceAdapter.kt:49-52).
                .opacity(place.notifyEnter || place.notifyExit ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            RowDeleteButton(label: String(localized: "place_delete"), action: onDelete)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .ruleCard()
    }
}
```

`ios/KidCare/Guardian/PlaceEditorView.swift`:

```swift
import SwiftUI

/// 장소 편집 판. 정본은 `fragment_place.xml` 편집 판(:146-364) — 제목, 이름, 지도(십자·원), 반경, 알림
/// 스위치 둘, 진행 줄, 취소·저장. 안쪽 여백 16(:159). 시스템 뒤로 버튼이 늘 보인다 — 지도가 가장자리
/// 밀기를 삼켜도 이 버튼으로 나갈 수 있다(Global Constraints).
struct PlaceEditorView: View {

    let viewModel: PlaceViewModel

    /// 지도에 손가락이 닿아 있는 동안 스크롤을 잠근다 — 세로로 끌면 스크롤이 먼저 먹어 지도를 위아래로
    /// 못 옮기던 문제의 자리(PlaceFragment.kt:238-246, 판정 기록 8).
    @State private var 지도를_만지는_중 = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: viewModel.편집기_제목)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)

                항목_제목("place_editor_name_label").padding(.top, 20)
                TextField("place_editor_name_hint", text: Binding(
                    get: { viewModel.이름 },
                    set: { viewModel.이름을_바꾼다($0) }
                ))
                .font(.system(size: 17))
                .foregroundStyle(KidCarePalette.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                // Widget.KidCare.TextField — 외곽선 상자, 모서리 12, 테두리 colorOutline(line) 1(themes.xml:196-198).
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(KidCarePalette.line, lineWidth: 1))
                .padding(.top, 8)
                if viewModel.이름_경고 {
                    Text("place_editor_name_required")
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.berryInk)
                        .padding(.top, 6)
                }

                항목_제목("place_editor_map_label").padding(.top, 20)
                Text("place_editor_map_hint")
                    .font(.system(size: 13))
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .padding(.top, 4)
                if viewModel.지도_안내가_보이나 {
                    Text("place_editor_no_child_location")
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.berryInk)
                        .padding(.top, 4)
                }
                ZStack {
                    PlacePickerMapView(
                        camera: viewModel.카메라_요청,
                        circle: viewModel.원,
                        onTouchDown: { lat, lng in
                            지도를_만지는_중 = true
                            viewModel.지도를_만졌다(centerLat: lat, centerLng: lng)
                        },
                        onTouchEnd: { 지도를_만지는_중 = false },
                        onIdle: { lat, lng, byUser in
                            viewModel.지도가_멈췄다(centerLat: lat, centerLng: lng, 사람이_옮겼나: byUser)
                        }
                    )
                    // 십자는 누를 수 없어야 한다 — 정확히 좌표를 정하는 자리에서 터치를 먹으면 안 된다(:228-230).
                    PlaceCrosshair()
                        .frame(width: 48, height: 48)
                        .allowsHitTesting(false)
                        .accessibilityLabel(Text("place_editor_map_hint"))
                }
                .frame(height: 260)
                .clipped()
                .padding(.top, 8)

                항목_제목("place_editor_radius_label").padding(.top, 20)
                // 슬라이더 손잡이 위 말풍선은 손가락에 가려서 숫자로도 적는다(:258-259).
                Text(verbatim: viewModel.반경_문구)
                    .font(.system(size: 17))
                    .foregroundStyle(KidCarePalette.ink)
                    .padding(.top, 4)
                Slider(
                    value: Binding(get: { viewModel.반경 }, set: { viewModel.반경 = $0 }),
                    in: PlaceViewModel.minRadiusMeters...PlaceViewModel.maxRadiusMeters,
                    step: PlaceViewModel.radiusStepMeters
                )
                .tint(KidCarePalette.sky)
                .padding(.top, 4)

                항목_제목("place_editor_notify_label").padding(.top, 12)
                Toggle(isOn: Binding(get: { viewModel.도착_알림 }, set: { viewModel.도착_알림 = $0 })) {
                    Text("place_editor_notify_enter").font(.system(size: 17)).foregroundStyle(KidCarePalette.ink)
                }
                .tint(KidCarePalette.sky)
                .frame(minHeight: 52)
                .padding(.top, 8)
                Toggle(isOn: Binding(get: { viewModel.나섬_알림 }, set: { viewModel.나섬_알림 = $0 })) {
                    Text("place_editor_notify_exit").font(.system(size: 17)).foregroundStyle(KidCarePalette.ink)
                }
                .tint(KidCarePalette.sky)
                .frame(minHeight: 52)
                if viewModel.알림_없음_안내가_보이나 {
                    Text("place_editor_notify_none_hint")
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.top, 4)
                }

                HStack(spacing: 10) {
                    if viewModel.저장_중 {
                        ProgressView().frame(width: 20, height: 20)
                    }
                    if let 줄 = viewModel.편집_줄 {
                        Text(verbatim: 줄).font(.system(size: 15)).foregroundStyle(KidCarePalette.ink)
                    }
                }
                .padding(.top, 20)

                HStack(spacing: 8) {
                    // 장소 편집의 취소는 글자 버튼이다(:346-352 — 예약 편집과 다르다, XML 그대로).
                    Button { viewModel.취소를_눌렀다() } label: {
                        Text("place_editor_cancel")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(KidCarePalette.sky)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { Task { await viewModel.저장을_눌렀다() } } label: {
                        Text("place_editor_save")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(KidCarePalette.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(KidCarePalette.sky, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(viewModel.저장_중)
                .opacity(viewModel.저장_중 ? 0.38 : 1)
                .padding(.top, 16)
            }
            .padding(16)
        }
        .scrollDisabled(지도를_만지는_중)
        .clipped()
        .background(KidCarePalette.paper)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func 항목_제목(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(KidCarePalette.ink)
    }
}
```

- [ ] **Step 8: 마스코트 자산**

`app/` 의 파일은 읽기만 한다(판정 기록 12).

```bash
cd /Users/com/work/KidCare
mkdir -p ios/KidCare/Assets.xcassets/Mascot3D.imageset
cp app/src/main/res/drawable-nodpi/mascot_3d.png ios/KidCare/Assets.xcassets/Mascot3D.imageset/mascot_3d.png
cat > ios/KidCare/Assets.xcassets/Mascot3D.imageset/Contents.json <<'EOF'
{
  "images" : [
    {
      "filename" : "mascot_3d.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
git status --short app   # 비어 있어야 한다
```

- [ ] **Step 9: 탭에 붙인다**

`ios/KidCare/Guardian/GuardianRootView.swift`(Task 2 가 끝난 모양):

1. `scheduleViewModel` 아래에 `@State private var placeViewModel: PlaceViewModel` 을 더한다.
2. `init` 끝에 `_placeViewModel = State(initialValue: PlaceViewModel(familyId: familyId, childUid: childUid))` 를 더한다.
3. `TabPlaceholderView(tab: .place)` 로 시작하는 세 줄을 바꾼다:

```swift
                PlaceView(viewModel: placeViewModel)
                    // PlaceFragment.kt:232(subscribe), :290-294(onResume), :317-320(onHiddenChanged).
                    .onAppear {
                        placeViewModel.시작한다()
                        placeViewModel.다시_알린다()
                    }
                    .tabItem { Label(GuardianTab.place.title, systemImage: GuardianTab.place.systemImage) }
                    .tag(GuardianTab.place)
```

4. Task 2 가 더한 `.onChange(of: scenePhase)` 안에 `if selectedTab == .place { placeViewModel.다시_알린다() }` 를 더한다.
5. `.onDisappear` 안에 `placeViewModel.정리한다()` 를 더한다.
6. `TabPlaceholderView` 타입 주석을 "아직 이 앱에 없는 탭(알림 6단계)의 자리"로 고친다.

- [ ] **Step 10: 카탈로그**

공통 절차 A:

```
KEYS="place_add place_delete place_delete_cancel place_delete_confirm place_delete_message place_delete_title place_deleting place_editor_cancel place_editor_map_hint place_editor_map_label place_editor_name_hint place_editor_name_label place_editor_name_required place_editor_no_child_location place_editor_notify_enter place_editor_notify_exit place_editor_notify_label place_editor_notify_none_hint place_editor_radius_label place_editor_radius_value place_editor_save place_editor_title_edit place_editor_title_new place_empty place_error_format place_limit_notice place_no_family place_notify_both place_notify_enter place_notify_exit place_notify_none place_row_detail place_save_slow place_saving place_summary place_sync_failed_format place_sync_no_child place_sync_pending place_sync_retry place_sync_slow"
```

- [ ] **Step 11: 통과 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS. `PlaceTextTests` 3개, `PlaceViewModelTests` 12개가 새로 들어간다. 그리고 앱 코드에 금지 표현이 없는지 본다:

```bash
grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|navigationBarBackButtonHidden" ios/KidCare   # 비어 있어야 한다
```

- [ ] **Step 12: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Guardian/PlaceText.swift ios/KidCare/Guardian/PlaceViewModel.swift ios/KidCare/Guardian/PlaceView.swift \
  ios/KidCare/Guardian/PlaceEditorView.swift ios/KidCare/Guardian/PlacePickerMapView.swift \
  ios/KidCare/Assets.xcassets/Mascot3D.imageset ios/KidCare/Guardian/GuardianRootView.swift ios/KidCare/Localizable.xcstrings \
  ios/KidCareTests/PlaceTextTests.swift ios/KidCareTests/PlaceViewModelTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 5단계 Task 3: 장소 탭 — 지도 한가운데 십자와 반경 원으로 고르고, 지우면 아이 폰에 반드시 알린다"
```

---
## 단계 마무리 — 통합 리뷰 한 번, 시뮬레이터 확인 한 번

Task 1~3 은 단위 테스트만 돌리고 넘어간다(4단계와 같은 빠른 방식). 여기서 한 번에 본다.

- [ ] **Step 1: 기계 검사**

Task 1 을 시작하기 **전에** 한 번 `swift tools/check-i18n-keys.swift > /tmp/p5-i18n-before.txt; echo $?` 로 기준을 남겨 둔다. 그리고 여기서:

```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
cd /Users/com/work/KidCare
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'; cd ..
swift tools/check-i18n-keys.swift > /tmp/p5-i18n-after.txt; diff /tmp/p5-i18n-before.txt /tmp/p5-i18n-after.txt   # 비어 있어야 한다 — i18n 원본에 키를 더하지 않았다
grep -rn "^import" ios/KidCare/Logic | grep -v "import Foundation$"                          # 비어 있어야 한다
grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|navigationBarBackButtonHidden" ios/KidCare  # 비어 있어야 한다
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew                                # 비어 있어야 한다
git diff ios/KidCare/KidCareApp.swift                                                       # 비어 있어야 한다
grep -rn "TabPlaceholderView(tab: .schedule)\|TabPlaceholderView(tab: .place)" ios/KidCare   # 비어 있어야 한다
```

테스트 개수를 적어 둔다(Task 4 개발일지). 기대값은 4단계 끝(수정 라운드 포함)보다 **51개** 많다. Task 1 이 17(`KotlinMath` 4, `RuleDocuments` 4, `ListLoad` 2, `RuleSyncStore` 2, `RuleRepository` 5), Task 2 가 19(`ScheduleText` 4, `ScheduleViewModel` 15), Task 3 이 15(`PlaceText` 3, `PlaceViewModel` 12)다.

- [ ] **Step 2: 통합 리뷰** — superpowers:requesting-code-review 로 5단계 첫 커밋의 부모부터 HEAD 까지를 한 번 리뷰받는다. 리뷰어에게 이 계획서의 "판정 기록" 열네 줄과 "Pre-flight conflict table" 을 함께 준다. 특히 네 가지를 봐 달라고 적는다.
  1. 판정 기록 3(뒤로 가기 중 저장)의 세대 규칙에 틈이 없는가.
  2. `PlacePickerMapView` 의 `@preconcurrency` 준수와 제스처 동시 인식이 Swift 6 에서 경고 없이 도는가.
  3. 두 뷰모델의 `정리한다()` 뒤에 쓰기·구독이 새로 생기는 길이 없는가(4단계 통합 검토 M1 과 같은 종류).
  4. 섭동 확인. `목록이_이어받았나` 를 늘 `false` 로 바꾸면 `뒤로_가기_중_실패` 두 곳이 빨개지는가. `깃발을_바꾼다(true)` 를 쓰기 **뒤로** 옮기면 `저장_흐름` 이 빨개지는가. `KotlinMath.precedes` 를 `<` 로 바꾸면 `정렬과_캐시`(장소)가 빨개지는가.

  반려 항목은 고친 뒤 한국어 커밋(`iOS 5단계 Fix round N: …`)으로 남긴다.

- [ ] **Step 3: 시뮬레이터 확인 준비 — 에뮬레이터에만 쓴다**

4단계 단계 마무리 Step 3 과 같다. 순서는 이렇다.
1. 다른 터미널에서 `firebase emulators:start --only auth,firestore --project kidcare-emulator` 를 띄운다.
2. `ios/KidCare/KidCareApp.swift` 를 **잠시** `configureForEmulator(projectId: "kidcare-emulator")` 로 바꾸고 새로 설치한다.
3. 앱에서 보호자 → 새 가족 만들기로 가족을 만든다.
4. owner 토큰으로 `sim-child` 멤버와 상태 문서를 넣는다. 상태 문서는 서울시청 좌표 `37.5665, 126.978` 이다.

```bash
EMU="http://127.0.0.1:8080/v1/projects/kidcare-emulator/databases/(default)/documents"
AUTH="Authorization: Bearer owner"
FAMILY=$(curl -s -H "$AUTH" "$EMU/families" | python3 -c 'import json,sys; print(json.load(sys.stdin)["documents"][-1]["name"].split("/")[-1])')
NOW=$(python3 -c 'import time; print(int(time.time()*1000))')
curl -s -X PATCH -H "$AUTH" -H "Content-Type: application/json" "$EMU/families/$FAMILY/members/sim-child" \
  -d "{\"fields\":{\"role\":{\"stringValue\":\"child\"},\"displayName\":{\"stringValue\":\"민준\"},\"fcmToken\":{\"stringValue\":\"\"},\"appVersion\":{\"stringValue\":\"\"},\"joinCode\":{\"stringValue\":\"\"},\"updatedAt\":{\"integerValue\":\"$NOW\"},\"joinedAt\":{\"integerValue\":\"$NOW\"}}}" > /dev/null
curl -s -X PATCH -H "$AUTH" -H "Content-Type: application/json" "$EMU/families/$FAMILY/children/sim-child" \
  -d "{\"fields\":{\"lat\":{\"doubleValue\":37.5665},\"lng\":{\"doubleValue\":126.978},\"battery\":{\"integerValue\":\"77\"},\"ringerMode\":{\"stringValue\":\"normal\"},\"dnd\":{\"stringValue\":\"off\"},\"network\":{\"stringValue\":\"wifi\"},\"wifiOn\":{\"booleanValue\":true},\"lastSeenAt\":{\"integerValue\":\"$NOW\"}}}" > /dev/null
# 문서 보기 도우미: show schedules | show places | show commands | show settings/ringer
show() { curl -s -H "$AUTH" "$EMU/families/$FAMILY/children/sim-child/$1" | python3 -m json.tool | head -80; }
```

- [ ] **Step 4: 시뮬레이터에서 본다** — 항목마다 `xcrun simctl io booted screenshot /tmp/p5-<번호>.png` 로 남기고, 가능하면 안드로이드 보호자 폰의 같은 화면과 나란히 둔다.

1. **예약 탭 첫 화면.** 기본 모드 카드('그대로 두기'가 회색 선택), 공휴일 카드(자두빛, "쉬는 날에는 아래 규칙을 하나도 켜지 않아요."), 가운데 "아직 정해둔 시간대가 없어요…", 맨 아래 하늘색 '규칙 추가'. 화면 제목은 없다. 스크롤한 글이 상태 표시줄 밑으로 비치지 않는다.
2. **규칙 추가.** 편집 화면이 push 되고 **왼쪽 위에 시스템 뒤로 버튼**이 보인다. 기본값은 평일 다섯 칸이 하늘색, 21:00 – 07:00, 그 아래 "21:00 ~ 다음 날 07:00", 진동이 라벤더로 선택된 상태다. 21:00 을 누르면 시트에 "시작 시각"과 24시간 바퀴가 뜬다. 저장 → 목록에 카드 한 장(라벤더 스티커, "평일", "21:00 ~ 다음 날 07:00", 띠 **양 끝**이 참). `show schedules` 의 필드가 일곱 개(`id` 는 빈 값)다. `show commands` 에 `sync_rules` pending 이 하나 생긴다.
3. **관문.** 요일을 다 끄고 저장하면 빨간 안내가 뜨고, 한 칸 켜면 사라진다. 시작=끝이면 "하루 종일로 저장할까요?"가 뜬다. 평일 22:00~06:00 을 하나 더 저장하면 "겹치는 규칙이 있어요"가 뜨고 문장에 첫 규칙 이름이 들어 있다.
4. **켬끔·삭제.** 스위치를 끄면 카드가 흐려지고 "(꺼둠)"이 붙는다. 휴지통 → "이 규칙을 지울까요?" → 지우기. 둘 다 `sync_rules` 가 하나씩 는다.
5. **기본 모드·공휴일.** '무음'을 누르면 풀빛으로 차고 "규칙이 끝나면 무음(으)로 돌아가요."가 뜬다. 공휴일 스위치를 켜면 둘째 줄이 "다음 쉬는 날은 …"으로 바뀐다. 이 문장이 **안드로이드 보호자 폰의 같은 줄과 글자 하나 다르지 않은지** 본다(음력 환산 검산). `show settings/ringer` 에 `lockEnabled`(관리 탭에서 켰으면)·`defaultMode`·`holidayOff` 가 함께 있다.
6. **뒤로 가기.** 편집 화면에서 뒤로 버튼과 왼쪽 가장자리 밀기가 둘 다 목록으로 돌아가고, 아무것도 저장되지 않는다(`show schedules` 그대로).
7. **장소 탭.** 가운데 마스코트와 "아직 정해둔 장소가 없어요…". '장소 추가' → 편집 화면(뒤로 버튼 보임). 지도가 서울시청 근처 배율 16 으로 열리고, 가운데 흰 테두리 십자와 반경 200m 파란 원이 보인다. 이름 없이 저장하면 빨간 안내가 뜬다. 지도를 **위아래로** 끌면 화면이 스크롤되지 않고 지도가 움직이며, 손을 떼면 원이 새 가운데로 옮겨진다. 슬라이더를 끌면 "반경 450m" 처럼 숫자와 원이 함께 바뀐다. 나섬 스위치를 끄고 저장하면 목록 카드에 첫 글자 스티커와 "도착 알림만 · 반경 450m" 가 뜬다. `show places` 가 일곱 필드이고 `sync_rules` 가 하나 는다.
8. **아이 위치를 모를 때.** `curl -s -X DELETE -H "$AUTH" "$EMU/families/$FAMILY/children/sim-child"` 로 상태 문서를 지우고 앱을 다시 띄운다(아이 위치는 탭을 처음 열 때 한 번 읽는다). 새 장소를 열면 한반도 전체가 보이고 빨간 "아이 폰 위치를 아직 몰라서…"가 뜬다. 지도를 손가락으로 **톡 건드리기만** 하면 안내가 사라지고 원이 생긴다(판정 기록 8). 그대로 저장한 장소의 좌표가 (0,0)이 아니라 그 순간 지도 가운데인지 `show places` 로 본다.
9. **20개 상한.** 에뮬레이터에 장소를 20개 채운다.

   ```bash
   for i in $(seq 1 20); do curl -s -X PATCH -H "$AUTH" -H "Content-Type: application/json" "$EMU/families/$FAMILY/children/sim-child/places/fill$i" -d "{\"fields\":{\"id\":{\"stringValue\":\"\"},\"name\":{\"stringValue\":\"장소$i\"},\"lat\":{\"doubleValue\":37.5},\"lng\":{\"doubleValue\":127.0},\"radiusMeters\":{\"doubleValue\":200},\"notifyEnter\":{\"booleanValue\":true},\"notifyExit\":{\"booleanValue\":true}}}" > /dev/null; done
   ```

   추가 버튼이 흐려지고 목록 위 옅은 보라 바탕에 "장소는 20개까지…"가 뜬다.
10. **오프라인 깃발.** 에뮬레이터 터미널을 `Ctrl+C` 로 멈춘다. 예약 탭에서 규칙 하나를 저장하면 15초 뒤 편집기가 닫히고 "저장 요청은 보냈지만…"과 자두빛 "아직 애기폰에 전달되지 않았어요…" 줄이 뜬다. 앱을 끄고 다시 켜도 그 줄이 남아 있다. 에뮬레이터를 다시 띄운 뒤(데이터는 사라진다 — 3단계부터 해 온 방식대로 가족을 다시 만든다) 다른 탭을 봤다가 예약 탭으로 돌아오거나 '다시 알리기'를 누르면 줄이 사라진다. 이 항목은 에뮬레이터 재시작 때문에 **맨 마지막**에 한다.
11. **탭 수명.** 장소 편집 화면을 연 채 지도 탭을 봤다 돌아오면 편집 화면과 지도 위치가 그대로다. 관리 탭의 잠금·소리 버튼이 예약·장소 작업 뒤에도 그대로 동작한다.

- [ ] **Step 5: 되돌리고 확인** — `KidCareApp.swift` 를 `configureForApp()` 로 되돌리고 `git diff ios/KidCare/KidCareApp.swift` 가 비어 있는지 확인한다. 시뮬레이터에서 앱을 지운다. 여기서 찾은 결함은 고친 뒤 테스트를 다시 돌리고 `iOS 5단계 Fix round N: …` 으로 커밋한다.

---

### Task 4: 실기기에서 목록만 열어 보기, 그리고 개발일지

**Files:**
- Modify: `README.md` (개발일지 절, "함께 고쳐야 하는 짝")

**진짜 가족에 쓰는 동작은 실기기에서 하지 않는다.** 규칙·장소·기본 모드·공휴일 쓰기와 `sync_rules` 발행은 위 단계 마무리에서 **에뮬레이터로만** 확인했다. 실기기는 운영 Firebase 에 붙은 진짜 가족이므로 **목록만 열어 본다.** 구체적으로 이렇다.
- **누르지 않는 것:** '규칙 추가'·'장소 추가', 규칙·장소 카드(편집 화면 자체는 쓰지 않지만 저장을 잘못 누를 위험을 없앤다), 규칙 켬끔 스위치, 기본 모드 네 칸, 공휴일 스위치, 휴지통, '다시 알리기'.
- **탭을 여는 것은 안전하다.** 여는 순간 하는 일은 읽기(규칙·장소 구독, 설정 구독, 장소 탭의 아이 상태 한 번 읽기)와 `다시_알린다()` 다. `다시_알린다()` 는 이 기기에 "못 보낸 알림" 깃발이 있을 때만 명령을 쓴다. 이 기기에서는 5단계 빌드로 한 번도 저장한 적이 없고 깃발 키(`schedule_sync_pending_sync_…`)가 5단계에서 새로 생긴 이름이라, 깃발은 `false` 다.
- 관리 탭·지도 탭의 명령 버튼도 누르지 않는다(4단계 Task 6 과 같다). 앱을 지우거나 역할을 다시 고르지 않는다.

- [ ] **Step 1: 실기기 연결 확인** — `xcrun devicectl list devices`. `unavailable` 이면 **여기서 멈추고 보고한다.** 케이블은 사람이 꽂아야 한다.

- [ ] **Step 2: 운영 설정으로 설치** — `configureForApp()` 그대로 둔다. 기존 앱 위에 덮어 설치해야 가족 합류가 유지된다.

```bash
cd /Users/com/work/KidCare/ios
xcodebuild -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS,id=<UDID>' -derivedDataPath /tmp/kidcare-dd-device -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> /tmp/kidcare-dd-device/Build/Products/Debug-iphoneos/KidCare.app
xcrun devicectl device process launch --device <UDID> com.kidcare.family
```

- [ ] **Step 3: 보기만 한다** — 안드로이드 보호자 폰을 옆에 두고 같은 탭을 연다. 스크린샷은 사람이 기기에서 찍는다.
  1. **예약 탭:** 규칙 순서, 요일 문구, 시각 문구, 하루 띠 모양(밤 규칙은 양 끝), 스티커 색이 안드로이드와 같다. 기본 모드 선택 칸, 공휴일 스위치 상태, 공휴일 둘째 줄(켜져 있으면 "다음 쉬는 날은 …")도 **글자까지** 같은지 본다.
  2. **장소 탭:** 장소 순서(이름순), 첫 글자, **스티커 색**, "도착·이탈 알림 · 반경 200m" 줄이 안드로이드와 같다. 스티커 색이 하나라도 다르면 `KotlinMath.javaHashCode` 가 틀린 것이다(판정 기록 10). 멈추고 보고한다.
  3. 두 탭 모두 "아직 애기폰에 전달되지 않았어요" 줄이 **없다**(이 기기의 깃발은 false 여야 한다). 줄이 보이면 아무것도 누르지 말고 보고한다.
  4. 탭을 오가도 목록이 깜빡이며 다시 읽히지 않는다.

- [ ] **Step 4: 개발일지를 쓴다** — `README.md` 에 절 하나를 더한다. 자리는 4단계 절(`### 아이폰 4단계 …`) 바로 다음이다. 4단계 Task 6 이 아직 그 절을 쓰지 않았으면 `### 아이폰 3단계 …` 절 다음, `## 아이가 앱을 강제 종료하면` 앞에 두고 커밋 메시지에 그 사실을 적는다. 앞 절들과 같은 말투(부모·다음 개발자가 읽는 한국어 설명문)로 아래 내용을 **다 담는다.**

```markdown
### 아이폰 5단계 — 예약 탭과 장소 탭 (2026-09-13)

안드로이드 예약 탭(`ScheduleFragment`)과 장소 탭(`PlaceFragment`)을 옮겼습니다. 예약 탭에는 기본 모드 카드, 공휴일 스위치와 '다음 쉬는 날' 한 줄, 하루 띠가 달린 규칙 목록, 요일·시각·모드 편집이 있습니다. 장소 탭에는 이름 첫 글자 스티커 목록, 지도 한가운데 십자와 반경 원으로 고르는 편집, 20개 상한이 있습니다. 두 탭 모두 저장·켬끔·삭제 뒤에 아이 폰에 `sync_rules` 를 보내고, 못 보냈으면 목록 위에 그렇게 적습니다.

#### 안드로이드에는 '추가 화면'이 없습니다

안드로이드는 한 화면 안에서 목록 판과 편집 판을 바꿔 끼우고 뒤로 가기를 가로챕니다. 아이폰에서는 같은 흐름을 편집 화면을 밀어 넣는(push) 방식으로 옮겼고, 주인이 요구한 대로 왼쪽 위 뒤로 버튼이 늘 보입니다. 대가가 하나 있습니다. 안드로이드는 저장이 도는 동안 뒤로 가기를 막지만 아이폰의 뒤로 버튼은 숨기지 않고는 막을 수 없습니다. 그래서 막지 않는 대신, 뒤로 간 뒤에 늦게 도착한 저장 실패는 목록 위 한 줄로 알려줍니다. 조용히 사라지는 실패가 이 앱에서 가장 나쁘기 때문입니다. (Fix round 가 있었다면 한 줄로)

#### 두 폰이 같은 색·같은 순서를 보게

장소 스티커 색은 문서 ID 의 자바 `hashCode` 로 정하고, 목록 순서는 코틀린 문자열 비교(UTF-16)로, 반경 표기는 `Math.round` 로 정합니다. Swift 에서 가장 가까운 함수들은 이모지 이름이나 음수 .5 같은 입력에서 조금씩 다른 답을 내서, 그대로 썼다면 같은 장소가 엄마 폰과 아빠 폰에서 다른 색으로 보였을 것입니다. 세 함수를 `Logic/KotlinMath.swift` 에 모으고 자바에서 알려진 값으로 테스트했습니다. 실기기에서 안드로이드 보호자 폰과 나란히 놓고 색과 순서가 같은 것을 확인했습니다. (실제 결과로 바꿔 쓴다)

#### 지도에 손을 대는 순간

장소 편집 지도는 세로로 끌어도 화면이 스크롤되지 않게, 손가락이 닿는 동안 스크롤을 잠급니다(안드로이드 `requestDisallowInterceptTouchEvent` 자리). 프로그램이 지도를 옮긴 것과 사람이 옮긴 것은 네이버 SDK 가 알려주는 이동 원인으로 가릅니다. 그리고 손이 닿는 그 순간의 지도 가운데를 곧바로 좌표로 적어, 끌지 않고 건드리기만 한 뒤 저장해도 좌표가 비지 않게 했습니다.

#### 안드로이드에서 찾은 것 (고치지 않았습니다)

- `ScheduleRepository.saveSchedule`·`PlaceRepository.savePlace` 주석은 "id 는 본문에 담지 않는다"고 하지만, `doc.copy(id = "")` 를 통째로 넘기고 `@Exclude` 가 없어서 **본문에 `"id": ""` 가 실립니다.** 동작에는 해가 없지만(읽을 때 문서 ID 로 덮음) 주석이 틀렸고, 나중에 규칙에 `hasOnly` 를 걸 사람이 이 주석을 믿으면 모든 저장이 거부됩니다. 아이폰은 코드가 실제로 쓰는 일곱 필드를 그대로 씁니다.
- `Documents.kt` 의 `ScheduleDoc`·`PlaceDoc` 문서 주석은 경로를 `families/{familyId}/schedules`·`places` 로 적었지만, N:N 이후 실제 경로는 `families/{f}/children/{childUid}/…` 입니다.
- `ic_map_crosshair.xml` 주석은 바닥이 "OSM 타일"이고 잉크 색이 `@color/ink` 와 같다고 적었지만, 지금 지도는 네이버이고 값 `#4A4038` 은 `ink`(`#342D3F`)와 다릅니다.
- 장소 편집 지도에 손가락을 대기만 하고 끌지 않은 채 저장하면, 카메라 멈춤 이벤트가 오지 않는 한 편집 좌표가 (0,0)으로 남을 수 있습니다(`PlaceFragment.kt:245-255` 는 깃발만 세우고 좌표는 `onMapMoved` 를 기다립니다). **코드로만 본 것이고 실기기로 확인하지 않았습니다.**
- 이모지로 시작하는 장소 이름은 스티커에 반쪽 글자가 그려집니다(`PlaceAdapter.kt:68` 의 `firstOrNull()` 이 UTF-16 한 칸).

#### 그래서 지금

iOS 테스트 N개(4단계 끝 M개). 규칙·장소 쓰기와 `sync_rules` 는 에뮬레이터에서만 확인했고, 실기기(운영)에서는 두 탭의 목록만 열어 보았습니다. **안드로이드 `app/`·`firestore.rules` 는 한 줄도 안 바뀌었습니다.**
```

N 은 단계 마무리 Step 1 의 테스트 개수, M 은 Task 1 을 시작하기 전에 적어 둔 개수다. 괄호 안 지시문은 실제 문장으로 바꾼다.

"함께 고쳐야 하는 짝"(`README.md` 의 `### 함께 고쳐야 하는 짝`)을 이렇게 고친다:

```markdown
- **장소를 바꾸는 경로** → 반드시 `guardian/PlaceFragment.kt`의 `writeThenNotify`를 지나야 합니다. 그 함수가 쓰기 뒤에 `SYNC_RULES`를 보냅니다. 안 지나면 아이 폰이 지오펜스를 다시 걸지 않아, **지운 장소의 알림이 계속 울립니다.** 아이폰은 `ios/KidCare/Guardian/PlaceViewModel.swift`의 `쓰고_알린다`가 같은 자리입니다.
- **예약 규칙·기본 모드·공휴일을 바꾸는 경로** → 안드로이드 `ScheduleFragment.notifyChild`, 아이폰 `ScheduleViewModel.아이에게_알린다`. 새 쓰기 갈래를 만들면 둘 다 그 함수를 지나야 합니다.
- **장소 개수 상한 20** → `guardian/PlaceFragment.kt`의 `MAX_PLACES` + `child/PlaceWatcher.kt`의 `MAX_GEOFENCES` + 아이폰 `PlaceViewModel.maxPlaces`. 셋 다.
- **목록 순서·스티커 색·반경 반올림** → 아이폰은 `ios/KidCare/Logic/KotlinMath.swift`로 코틀린과 같은 답을 냅니다. 안드로이드에서 정렬 기준이나 색 고르는 식을 바꾸면 이 파일과 `PlaceText`·`ScheduleViewModel.목록_순서`도 함께 바꿉니다.
```

- [ ] **Step 5: 커밋**

```bash
cd /Users/com/work/KidCare
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew   # 비어 있어야 한다
git add README.md
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 5단계 Task 4: 실기기에서 예약·장소 목록만 열어 보고 개발일지를 쓴다"
```

---

## 5단계 완료 기준

- [ ] 예약 탭이 안드로이드와 같은 순서·색·치수로 뜬다. 기본 모드 카드, 공휴일 카드와 '다음 쉬는 날', 규칙 카드(스티커·하루 띠·스위치·삭제), 추가 버튼이다.
- [ ] 규칙 저장이 요일 → 하루 종일 → 겹침 관문을 지나고, 새 규칙은 나중에 만든 것이 이기며, 편집 문서 ID 는 열 때 정해진다.
- [ ] 장소 탭이 아이 마지막 위치(모르면 한반도)에서 열리는 지도·십자·반경 원으로 좌표와 반경을 정하고, 20개에서 추가를 막고 이유를 말한다.
- [ ] 두 탭의 모든 쓰기가 에뮬레이터에서 안드로이드와 같은 필드로 쓰이고 뒤따라 `sync_rules` 를 보낸다. 못 보냈으면 깃발이 앱 재시작을 넘겨 남고, 탭을 다시 열거나 '다시 알리기'로 내려간다.
- [ ] 편집 화면마다 시스템 뒤로 버튼이 보이고, 저장 중에 뒤로 가도 실패가 조용히 사라지지 않는다.
- [ ] 두 뷰모델의 리스너가 `GuardianRootView.onDisappear` 경로로 떨어지고, `정리한다()` 뒤에는 새 구독도 새 쓰기도 생기지 않는다.
- [ ] 실기기에서 두 탭 목록의 순서·문구·스티커 색이 안드로이드 보호자 폰과 같다(쓰기 없음).
- [ ] `i18n/*.json` 이 바뀌지 않았고, `LocalizableCatalogTests` 가 초록이다.
- [ ] `ios/KidCare/Logic/` 이 Foundation 만 import 하고, 앱 코드에 `@unchecked Sendable`·`nonisolated(unsafe)`·`navigationBarBackButtonHidden` 이 없다.
- [ ] `git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew` 가 비어 있다.

---

## 자기 검토 결과 (writing-plans self-review)

**설계서 대응.**
- §4 대응표 `ScheduleFragment` → `ScheduleView` + 뷰모델(Task 2). "하루 띠 UI"는 `DayRibbon`·`DayRibbonView`, "공휴일 스위치"는 `공휴일_안내`·`공휴일을_바꾼다`, "저장 후 `SYNC_RULES` 전송"은 `아이에게_알린다` 가 맡는다.
- §4 대응표 `PlaceFragment` → `PlaceView` + 뷰모델(Task 3). "지도 한가운데를 좌표로 삼는 방식 그대로"는 `PlacePickerMapView`·`PlaceCrosshair`·`지도가_멈췄다` 가 맡는다.
- §4 "색과 치수는 안드로이드 리소스에서" → 각 뷰 주석에 XML 줄과 값을 적었고, 새 색 일곱은 `colors.xml` 값이다.
- §4 "탭을 바꿔도 지도를 다시 만들지 않는다" → 판정 기록 9, 단계 마무리 Step 4-11.
- §5 손 매핑·`hasOnly` → `ScheduleDoc`·`PlaceDoc.firestoreData` 가 손으로 적은 일곱 필드이고, 설정은 한 필드씩 병합한다(Task 1 규칙 확인).
- §1 권한 0개 → 편집 지도는 `showLocationButton = false`, 위치 API 호출 없음. §1 푸시 없음 → 알림 표시는 만들지 않는다.
- §8 오류 → 모든 실패 문구가 `errorMessage(_:)` 를 지나고, 안드로이드 `*_error_format`·`*_sync_failed_format` 을 쓴다.
- §9 5단계 "예약 탭 · 장소 탭 — 하루 띠 UI와 지도 위 반경 고르기" → Task 1~3. 브리프 요구도 모두 대응했다. 보이는 뒤로 가기는 판정 2·4 와 Global Constraints, 진짜 가족 보호는 단계 마무리 Step 3 과 Task 4, 푸시 없음은 "다루지 않는 것", 코틀린 `file:line` 은 모든 코드 주석과 테스트 이름, 판정 기록은 열네 줄, 지어낸 화면 없음은 판정 2 가 맡는다.

**자리표시 검사.** "TBD/적절히/나중에"는 없다. Task 4 Step 4 의 개발일지 틀에만 괄호 지시문 셋과 N·M 이 있다. 실행해야 알 수 있는 값(테스트 개수, 실기기 비교 결과, Fix round 유무)이다.

**타입·이름 일관성(고친 것 포함).**
- 테스트와 구현 대조:
  - `ScheduleViewModelTests` 가 쓰는 이름은 Step 5 구현에 모두 있다. `시작한다`·`편집을_연다`·`요일을_누른다`·`저장을_눌렀다`·`하루_종일을_확인했다`·`겹쳐도_저장한다`·`취소를_눌렀다`·`뒤로_갔다`·`켬끔을_바꾼다(_:enabled:)`·`삭제를_눌렀다`·`삭제를_확인했다`·`기본_모드를_고른다`·`공휴일을_바꾼다`·`다시_알린다`·`정리한다` 와 `rules`·`listLoad`·`상태_줄`·`pendingSync`·`holidayOff`·`defaultMode`·`설정_잠김`·`확인창`·`편집_중`·`editorNewDocId`·`요일`·`시작분`·`끝분`·`저장_중`·`편집_줄`·`요일_경고`·`공휴일_안내`, 그리고 `enum 확인` 의 세 case 다.
  - `PlaceViewModelTests` 도 같다. `아이_위치_읽기`·`아이_위치`·`카메라_요청`·`카메라(lat:lng:zoom:번호:)`·`반경_원`·`원`·`지도를_만졌다(centerLat:centerLng:)`·`지도가_멈췄다(centerLat:centerLng:사람이_옮겼나:)`·`반경을_눈금에`·`이름을_바꾼다`·`이름`·`이름_경고`·`반경`·`반경_문구`·`나섬_알림`·`알림_없음_안내가_보이나`·`지도_안내가_보이나`·`추가할_수_있나`·`상한_안내`·`삭제_확인`·`삭제_확인_문구` 가 구현에 있다.
- 초안에서 고친 이름: `확인` 프로퍼티와 `enum 확인` 이 같은 이름이라 컴파일되지 않아 프로퍼티를 `확인창` 으로 바꿨다. 가짜 저장소의 메서드 `기본_모드` 가 기록 배열과 이름이 겹쳐 `기본_모드를_쓴다`/`저장한_기본_모드` 로 나눴다. `@Observable` 의 `didSet` 에 기대던 이름 자르기를 `이름을_바꾼다(_:)` 메서드로 바꿨다. 튜플을 옵셔널 바인딩에서 분해하던 `guard let (date, holiday)` 를 `next.0`/`next.1` 로 바꿨다.
- 4단계에서 실제로 커밋된 이름을 썼다(HEAD `5209a6e` 에서 grep 으로 확인). `ScheduleRepository.ringerSettingsRef(familyId:childUid:)`·`private static var db`·`observeRingerSettings(familyId:childUid:onChange:onError:)`, `firstToFinish(timeoutMillis:sleep:operation:)`, `ControlInput.date(minuteOfDay:calendar:)`·`minuteOfDay(_:calendar:)`, `RingerMode.normal/vibrate/silent`, `RingerSettingsDoc.init(_:)`, `EmulatorHarness.freshChildSession()`·`joinAsChild(_:familyId:joinCode:)`, 관리 탭 그림 이름 셋이다.
- `WriteSleepFake` 가 가르는 순서는 "매달린 저장의 sleep 이 첫 번째"라는 사실에만 기댄다. 저장이 매달리지 않는 테스트는 `첫_번째` 를 열지 않으므로 순서와 무관하다.
- 테스트 수 기대값(17·19·15)은 각 코드 블록의 `@Test` 개수를 센 값이다.

---

## Pre-flight conflict table

| 짝 | 함께 만지는 것 | 충돌 여부와 처리 |
|---|---|---|
| 4단계 Task 3(`8e9ebc6`) ↔ 5단계 Task 1 | `Core/ScheduleRepository.swift` — 4단계가 만든 `private static var db`, `private static func ringerSettingsRef(familyId:childUid:)`, `setRingerLock`, `observeRingerSettings` | HEAD `5209a6e` 에서 이름을 확인했다. 5단계는 enum 본문 **끝에 더하기만** 하고 기존 함수는 안 건드린다. 4단계 `ScheduleRepositoryTests` 3개가 그대로 초록이어야 한다(Task 1 Step 10) |
| 4단계 Task 3 ↔ Task 1 | `Core/Documents.swift` — `CommandType`(4단계가 12개 더함), `RingerMode`, `RingerSettingsDoc` | `CommandType` 끝에 `syncRules` 하나를 더하고 파일 끝에 두 구조체를 더한다. `RingerMode` 상수는 다시 적지 않고 쓴다 |
| 4단계 Task 3 ↔ Task 2·3 | `Guardian/FirstToFinish.swift` 의 `firstToFinish<T: Sendable>(timeoutMillis:sleep:operation:) async throws -> T?` | 시그니처를 확인했다. `T == Void` 로도 쓴다(`let done: Void? = …`) |
| 4단계 Task 3 ↔ Task 1 테스트 | `KidCareTests/EmulatorHarness.swift` 의 `ChildSession`·`freshChildSession()`·`joinAsChild` | 확인했다. `RuleRepositoryTests` 가 그대로 쓴다 |
| 4단계 Task 3 ↔ Task 2 | 카탈로그 `schedule_time_format` — 4단계 보고서에 따르면 계획서의 "이미 있다"와 달리 Task 3 이 새로 넣었다 | 이미 있으므로 공통 절차 A 명령이 건너뛴다. `ScheduleText.timeText` 가 쓴다 |
| 4단계 Task 4(`0b0a5f1`) ↔ Task 2 | `Guardian/ControlView.swift` 의 `enum ControlInput`(`date(minuteOfDay:)`·`minuteOfDay(_:)`) | 확인했다. 예약 편집의 시각 시트가 그대로 쓴다(판정 기록 5). 알람 줄처럼 로캘은 고르기 하나에만 건다(4단계 보고서의 변경점) |
| 4단계 Task 4 ↔ Task 2 | 소리 모드 SF Symbol — 관리 탭은 `speaker.wave.2.fill`·`iphone.radiowaves.left.and.right`·`speaker.slash.fill` 을 골랐다 | `ScheduleModeLook` 이 같은 이름을 쓴다(판정 기록 13) |
| 4단계 Task 4 보완(`5209a6e`) ↔ Task 2·3 | 스크롤한 글이 상태 표시줄 밑으로 비치던 겹침을 `ScrollView.clipped()` 로 고침 | 예약·장소의 목록 `ScrollView` 둘과 편집 `ScrollView` 둘에 같은 `.clipped()` 를 붙였다 |
| 4단계 Task 4 ↔ Task 2 | 모서리 — 4단계 보고서에 따르면 관리 탭 카드는 Small 12, 버튼은 Medium 18 | 예약·장소 카드는 XML 이 `ShapeAppearance.KidCare.Medium` 을 적었으므로(`item_schedule.xml:22`, `fragment_schedule.xml:40`, `item_place.xml:16`) 18 이다. 기본 모드 칸만 Small 12(`:85`) |
| 4단계 Task 4 ↔ Task 2·3 | `Guardian/GuardianRootView.swift`(`controlViewModel`, `.onAppear { 시작한다() }`, `.task(id: scenePhase)`, `.onDisappear`) | Task 2 는 예약 자리표시 한 덩어리를 바꾸고 `.onChange(of: scenePhase)` 를 새로 둔다. Task 3 은 장소 자리표시를 바꾸고 그 `onChange` 에 한 줄을 더한다. 알림 자리표시는 남는다 |
| 4단계 통합 검토 수정 라운드 ↔ 5단계 전체 | 원장(`progress.md`) 판정: I1(늦은 완료를 무응답이 덮음) 고침, I2(실시간 스냅샷 대답 규칙) 삭제, **M1(정리 뒤 시작 닫기, `GuardianRootView` 에 `.id(familyId+childUid)`)**, M2(잠금 스위치 비활성), **M3(고친 카탈로그 명령을 `tools/` 스크립트로)** | **5단계 Task 1 전에 이 수정 라운드가 커밋돼 있어야 한다**(`git log --oneline \| grep "4단계 Fix round"`). M1: 5단계 두 뷰모델도 `정리한다()` 가 `닫힘` 을 세워 그 뒤의 `시작한다`·`다시_알린다`·늦은 아이 위치 적용을 막는다(Task 2·3 코드). `.id(...)` 가 붙으면 `GuardianRootView` 가 다시 만들어질 때 `@State` 뷰모델도 새로 생기므로 5단계는 따로 할 일이 없다. M3: `tools/` 에 스크립트가 생겼으면 공통 절차 A 는 그 스크립트를 부르고, 위 python 은 대조용으로만 쓴다. I1·I2·M2 는 5단계 코드와 겹치지 않는다(5단계 제한시간은 `firstToFinish` 결과만 보고, 늦게 깨는 타이머가 없다) |
| 4단계 Task 1 ↔ Task 2 | `Guardian/KidCarePalette.swift` | `onBerrySoft` 아래에 일곱 줄을 더하기만 한다 |
| 4단계 Task 6(README, 아직 안 씀) ↔ Task 4 | `README.md` 개발일지 자리 | 4단계 절이 있으면 그 다음, 없으면 3단계 절 다음(Task 4 Step 4) |
| Task 1 ↔ Task 2 | `ListLoad`, `RuleSyncStore`, `KotlinMath.precedes`, `ScheduleDoc.asRule`, `ScheduleRepository` 새 함수 | 순서 의존 — Task 2 는 Task 1 이 커밋된 뒤에 컴파일된다 |
| Task 1 ↔ Task 3 | `PlaceDoc`, `PlaceRepository`, `KotlinMath` 셋 | 순서 의존 |
| Task 2 ↔ Task 3 | `RuleListParts.swift`, `RuleTestDoubles.swift`(`WriteSleepFake`), `KidCarePalette` 새 색, `GuardianRootView` 의 `.onChange(of: scenePhase)` | Task 3 은 쓰기만 하고 이 파일들을 고치지 않는다(`GuardianRootView` 만 한 줄씩 더함) |
| Task 2·3 ↔ `LocalizableCatalogTests` | 코드 리터럴 키 전부 | 각 Task 의 KEYS 목록을 코드 블록의 `String(localized:)`·`Text("…")`·`TextField("…")`·`머리말("…")`·`항목_제목("…")` 리터럴에서 뽑았다. 빠진 키가 있으면 그 Task 끝의 전체 테스트가 빨개진다 |
| Task 4 ↔ 전체 | `README.md` 만 | 코드 충돌 없음 |

| Task | 테스트가 코드와 맞는가 |
|---|---|
| Task 1 | `RuleDocumentsTests` 는 `ScheduleDoc(id:days:startMinute:endMinute:mode:enabled:priority:)`·`init(id:_:)`·`firestoreData`·`asRule` 과 `PlaceDoc` 의 같은 셋을 쓴다. `ListLoadTests` 는 `after(fromCache:)`·`emptyText(isEmpty:loaded:)` 를, `RuleSyncStoreTests` 는 `init(kind:defaults:)`·`pendingSync(childUid:)`·`setPendingSync(childUid:_:)` 를 쓴다. `RuleRepositoryTests` 는 Step 7 의 다섯 함수와 4단계 `setRingerLock`·`EmulatorHarness` 도우미를 쓴다. `KotlinMathTests` 의 기대값은 파이썬으로 자바 `hashCode` 를 재현해 계산했다(`학교` → 1,737,495, UUID 예 → 1,153,660,321, `polygenelubricants` → `Int32.min`) |
| Task 2 | `ScheduleTextTests` 의 한국어 기대값은 `i18n/ko.json` 원문으로 조립했다. `ScheduleViewModelTests` 의 `만든다` 가 넘기는 인자 이름·순서(`familyId`·`childUid`·`syncStore`·`schedulesObserve`·`settingsObserve`·`scheduleSave`·`scheduleDelete`·`defaultModeSave`·`holidayOffSave`·`commandSend`·`writeSleep`·`today`·`holidayNext`·`newId`)는 구현 `init` 과 같다. 겹침 테스트의 기대 문장은 정렬된 목록(eve 20:00 → off → night)에서 꺼둔 규칙이 빠진 첫 이름으로 만든 것이다 |
| Task 3 | `PlaceViewModelTests` 의 `만든다` 인자(`familyId`·`childUid`·`syncStore`·`placesObserve`·`placeSave`·`placeDelete`·`statusFetch`·`commandSend`·`writeSleep`·`newId`)는 구현 `init` 과 같다. `ChildStatusDoc(_:)` 는 `lat`·`lng` 만 있으면 만들어진다(`Documents.swift` 1단계). 스티커 번호 기대값은 Task 1 해시 값의 `floorMod(…, 4)` 다 |
| Task 4 | 코드 변경 없음 — 확인 절차뿐 |
