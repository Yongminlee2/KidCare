# 개인정보 처리방침 원고 — 우리아이 지킴이

이 파일은 **원고**다. 주인이 웹에 게시하고 그 https 주소를 App Store Connect 와 `ios/project.yml` 의 `KidCarePrivacyPolicyURL` 에 넣는다.
**게시 전에 주인이 법률 검토를 한다.** 특히 만 14세 미만 아동의 개인정보(개인정보 보호법 제22조의2 법정대리인 동의)와 국외 이전 항목을 확인한다.
`【주인이 채움】` / `【OWNER】` 이 남아 있으면 게시하지 않는다.

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
