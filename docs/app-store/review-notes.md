# 심사 메모 — App Review / TestFlight Beta App Review

붙여 넣는 곳:
- App Store 제출: App Store Connect → 앱 → 배포 → 버전 1.0 → **앱 심사 정보**(App Review Information) → 메모. "로그인 필요" 체크는 **끈다**.
- TestFlight **외부** 테스트: TestFlight → 테스트 정보(Test Information) → 베타 앱 심사 정보 → 메모, 그리고 "테스트할 항목(What to Test)". 내부 테스트에는 필요 없다.

심사자는 영어로 읽는다. 영어를 붙여 넣고 한국어는 주인 확인용이다. `【주인이 채움】` / `【OWNER】` 이 남아 있으면 제출하지 않는다.
**데모 모드는 만들지 않는다**(7단계 판정 기록 11). 가짜 가족 데이터를 보여주는 화면은 안드로이드에 없는 지어낸 화면이라 만들지 않고, 대신 시연 영상과 실제 데모 가족(안드로이드 시험 폰) 연락처로 대신한다.

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

## What to Test (TestFlight 외부 테스트, English — paste this)

```
Join your family with a guardian invite code, then check the Map, Alerts, Control, Schedule and Places tabs for your child. Please report anything that looks different from the Android guardian app.
```

## 메모 (한국어 — 주인 확인용, 붙여넣지 않는다)

KidCare(iOS)는 두 기기 가족 서비스의 **보호자** 앱이다. 아이 폰은 안드로이드 아이 앱을 쓴다. 아이 역할은 iOS 에서 불가능한 기능(원격 소리 전환, 폰찾기 사이렌)이 있어 만들지 않았다.

- 로그인 없음(Firebase 익명 로그인). 줄 계정이 없다.
- 페어링에 아이 폰이 필요하고 초대 코드는 10분 만료다. 그래서 시연 영상 + 심사 기간 동안 켜 두는 데모 가족 + 연락하면 보호자 초대 코드를 보내는 방식으로 대신한다.
- 권한 요청 0개, 배경 모드 없음, 이 기기 위치 수집 없음, 푸시 없음.
- 아이 동의: 안드로이드 아이 앱은 아이콘과 "위치 공유 중" 알림을 늘 보인다. 페어링은 아이 폰에 직접 코드를 넣어야 된다. 키즈 카테고리 아님.
- 계정 삭제: 메뉴 → "이 아이폰을 가족에서 빼기".
- 처리방침: 같은 메뉴 → "개인정보 처리방침".
- 암호화: 표준 TLS 만.

**주인 전용 — 심사 전에 볼 것(App Store 정식 제출에만 해당, TestFlight 가족 배포에는 무관).** 아이 폰용 안드로이드 앱이 지금 가족끼리 APK 직접 설치(사이드로드) 전용이라 플레이스토어에 없다(`README.md:43`). 위 "Live demo family" 항목이 있어도, 심사관이 그 데모 가족 이상으로 실제 사용 가능성을 문제 삼으면(가이드라인 2.1, "리뷰어가 기능을 쓸 수 없다") 안드로이드 앱을 공개 배포하거나 다른 계획을 마련해야 한다(7단계 판정 기록 12). App Store 제출 전 사람이 할 일로 README 에도 적는다.

**버튼 이름 확인.** 위 영어 메모의 "Parent (mum or dad)"·"Join an existing family with a code"·"Create a new family" 는 `i18n/en.json` 의 `role_guardian`·`guardian_start_join_family`·`guardian_start_new_family` 값과 글자까지 같아야 한다. Task 3 Step 5 가 대조한다.
