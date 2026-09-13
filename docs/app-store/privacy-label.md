# App Store 개인정보 영양 라벨 답 — 우리아이 지킴이 (iOS)

붙여 넣는 곳: App Store Connect → 앱 → 앱 개인정보 보호(App Privacy) → 시작하기.
근거: `docs/superpowers/plans/2026-09-13-kidcare-ios-phase7.md` 판정 기록 2. 앱 매니페스트(`ios/KidCare/PrivacyInfo.xcprivacy`, Task 1 이 만든다)의 여섯 항목과 같고,
Firebase SDK 가 스스로 신고하는 진단 데이터 하나를 더했다. `ReleaseConfigTests.신고한_수집_항목` 을 바꾸면 이 파일도 같이 바꾼다.

**이 문서를 쓴 시점(Task 3)에는 Task 1 이 아직 이 저장소에 없다.** 여섯 항목은 계획서 판정 기록 2 의 표를 그대로 옮겼고, Task 1 이 합쳐진 뒤 `PrivacyInfo.xcprivacy` 와 `ReleaseConfigTests.신고한_수집_항목` 으로 다시 대조해야 한다(아래 "대조 필요" 참고).

## 기본 질문

| 질문 | 답 |
|---|---|
| 이 앱에서 데이터를 수집합니까? | **예** |
| 추적(다른 회사 앱·웹사이트 데이터와 연결하거나 데이터 브로커와 공유)에 사용합니까? | **아니요**(모든 항목) |

## 수집하는 데이터

넓게 신고하는 이유: 안드로이드 아이 앱이 모은 데이터라도 **같은 개발자·같은 서버**에 저장되고 이 앱이 보여준다. 적게 신고하는 쪽이 거부 사유가 된다.

| App Store Connect 분류 | 사용자에게 연결 | 추적 | 목적 | 이 앱에서의 실체 | 매니페스트 키 | 근거(firestore.rules) |
|---|---|---|---|---|---|---|
| 위치 → 정확한 위치 | 예 | 아니요 | 앱 기능 | 아이 폰 위치·경로(표시), 보호자가 고른 장소 좌표(저장) | `NSPrivacyCollectedDataTypePreciseLocation` | `children/{childUid}/trails/{dayKey}`, `families/{familyId}/places/{id}` |
| 연락처 정보 → 이름 | 예 | 아니요 | 앱 기능 | 가족 안 표시 이름(아이 이름은 안드로이드 페어링에서 입력) | `NSPrivacyCollectedDataTypeName` | `families/{familyId}/members/{uid}.displayName` |
| 식별자 → 사용자 ID | 예 | 아니요 | 앱 기능 | Firebase 익명 uid | `NSPrivacyCollectedDataTypeUserID` | `members/{uid}` 문서 ID, `inviteCodes/{code}.createdByUid` |
| 사용자 콘텐츠 → 이메일 또는 문자 메시지 | 예 | 아니요 | 앱 기능 | 아이 폰에 보내는 짧은 메시지 | `NSPrivacyCollectedDataTypeEmailsOrTextMessages` | `children/{childUid}/commands/{commandId}`(`CommandType.message`, `payloadText`) |
| 사용자 콘텐츠 → 기타 사용자 콘텐츠 | 예 | 아니요 | 앱 기능 | 알람 이름, 예약·장소 이름 | `NSPrivacyCollectedDataTypeOtherUserContent` | `commands`(`payloadLabel`), `schedules/{id}`, `places/{id}` |
| 기타 데이터 → 기타 데이터 유형 | 예 | 아니요 | 앱 기능 | 아이 폰 배터리·소리 모드·연결 상태, 도착·이탈 사건 | `NSPrivacyCollectedDataTypeOtherDataTypes` | `children/{childUid}`, `families/{familyId}/events/{id}` |
| 진단 → 기타 진단 데이터 | **아니요** | 아니요 | 분석 | Firebase Auth·Firestore SDK 가 스스로 신고하는 항목(`FirebaseAuth`·`Firestore` 의 `PrivacyInfo.xcprivacy`) | SDK 매니페스트(앱 자신의 `PrivacyInfo.xcprivacy` 에는 없음) | firebase-ios-sdk 12.19.1, 계획서 판정 기록 2 |

## 수집하지 않는 데이터 (체크하지 않는다)

- 연락처 정보 중 이메일 주소·전화번호·실제 주소 — 이 앱은 묻지 않는다(로그인 없음)
- 건강 및 피트니스, 금융 정보, 민감한 정보
- 연락처(주소록), 사진 또는 비디오, 오디오 데이터, 게임 플레이 콘텐츠, 고객 지원
- 검색 기록, 방문 기록
- 식별자 중 기기 ID — `members.fcmToken` 은 iOS 에서 늘 빈 값이다(`Documents.swift` `MemberDoc`, 푸시·FCM 미사용)
- 구매 내역 — 인앱 결제 없음
- 사용 데이터(제품 상호 작용, 광고 데이터) — 분석·광고 SDK 없음
- 진단 중 충돌 데이터·성능 데이터 — Crashlytics·Performance 미사용
- 위치 중 대략적인 위치 — 정확한 위치로 신고했다

## 데이터 삭제 안내(심사에서 물으면)

앱 메뉴 → "이 아이폰을 가족에서 빼기"(`ios_leave_family_menu`, Task 2 가 만든다): 서버의 이 아이폰 멤버 기록 → Firebase 익명 계정 → 기기에 저장된 가족 정보 순으로 지운다.
아이 폰이 올린 기록과 가족 공용 예약·장소는 규칙상 이 아이폰이 지울 수 없어 남는다. 처리방침의 연락처로 요청하면 운영자가 지운다.

## 대조 필요 (Task 1·2 가 합쳐진 뒤)

- [ ] `ios/KidCare/PrivacyInfo.xcprivacy` 의 여섯 `NSPrivacyCollectedDataType*` 키가 위 표의 매니페스트 키 열과 정확히 같다(`ReleaseConfigTests.신고한_수집_항목`).
- [ ] `ios_leave_family_menu`(`i18n/ko.json`·`i18n/en.json`)이 "이 아이폰을 가족에서 빼기" / "Remove this iPhone from the family" 그대로다.
