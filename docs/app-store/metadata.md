# App Store Connect 원고 — 우리아이 지킴이 (아이폰 보호자 앱)

붙여 넣는 곳: App Store Connect → 앱 → 우리아이 지킴이 → 배포(Distribution) → iOS 앱 → 버전 1.0.
기본 언어는 **한국어**, 추가 현지화는 **영어(미국)** 하나다. 나머지 12개 언어는 앱 안에만 있다(스토어 문구 번역을 지어내지 않는다).
`【주인이 채움】` 이 남아 있으면 제출하지 않는다.

## 주인 전용 메모 — 이 섹션은 붙여넣지 않는다

App Store 정식 출시의 선결 과제(7단계 계획 판정 기록 12): 아이 폰용 안드로이드 앱은 지금 **가족끼리 APK 직접 설치(사이드로드) 전용**이고 플레이스토어에 올라가 있지 않다(`README.md:43` "배포 방식: 가족끼리 APK 직접 설치. 플레이스토어에 올리지 않습니다."). 이 아이폰 앱은 안드로이드 아이 앱과 페어링해야만 쓸모가 있으므로, 아이 앱이 일반인이 구할 수 없는 상태로는 App Store 심사를 통과해도 구매한 사람이 실제로 쓸 수 없다. 심사관도 페어링할 아이 폰을 구하지 못하면 막힐 수 있다(그래서 아래 심사 메모에 시연 영상과 데모 가족 연락처를 둔다). **TestFlight 가족 배포에는 문제가 없다.** App Store 정식 제출 전에 주인이 이 선결 과제(안드로이드 앱을 플레이스토어에 올리거나, 다른 배포 계획을 정하는 것)를 처리해야 한다. 이 문단은 App Store Connect 어디에도 붙여 넣지 않는다.

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

**이름** (8자 / 22바이트, 한도 30자)
```
우리아이 지킴이
```
같은 이름이 이미 있으면 App Store Connect 가 거부한다. 그때 대안(12자 / 32바이트): `우리아이 지킴이 보호자`

**부제** (18자 / 46바이트, 한도 30자)
```
아이 폰의 하루를 부모가 확인해요
```

**프로모션 텍스트** (64자 / 160바이트, 한도 170자)
```
아이 폰(안드로이드)이 오늘 어디에 머물렀고 어떻게 움직였는지, 소리 모드와 배터리는 어떤지 아이폰에서 확인하세요.
```

**설명** (830자, 한도 4,000자)
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

**키워드** (41자 / 99바이트, 한도 100바이트, 쉼표 뒤 공백 없음)
```
위치,가족,자녀,보호자,안심,경로,무음,예약,장소,도착,배터리,폰찾기,알림
```
브리프 초안(`타임라인`·`도착알림`·`핸드폰찾기`를 포함한 13개 단어, 117바이트)은 100바이트 한도를 넘어서 줄였다. `타임라인`은 삭제, `도착알림`은 `도착`으로, `핸드폰찾기`는 `폰찾기`로 줄이고 `알림`을 남겨 뜻을 크게 잃지 않게 했다.

## English (U.S.)

**Name** (7 characters, limit 30)
```
KidCare
```
If taken (23 characters): `KidCare Family Guardian`

**Subtitle** (30 characters, limit 30 — at the limit)
```
See your child's phone and day
```

**Promotional Text** (122 characters, limit 170)
```
Check where your child's Android phone stayed today, how it moved, and its sound mode and battery, right from your iPhone.
```

**Description** (1,506 characters, limit 4,000)
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

**Keywords** (94 characters / 94 bytes, limit 100 bytes)
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
