# N:N 가족 구조와 서버 이전 기준

## 범위

한 `familyId` 안에 보호자 N명과 자녀 N명이 들어간다. 보호자는 상단 자녀 선택기에서
한 아이를 고르고, 지도·알림·관리·예약·장소 탭은 모두 그 자녀만 대상으로 동작한다.
아이 폰 한 대는 자기 uid에 해당하는 데이터만 읽고 쓴다.

현재 앱 한 설치본은 역할 하나와 가족 하나에 속한다. 한 사람이 서로 다른 두 가족을
동시에 오가는 기능은 이번 구조의 범위가 아니다.

## 데이터 모델

```text
families/{familyId}
├─ members/{uid}                    role = guardian | child
├─ children/{childUid}              현재 위치·배터리·소리 상태
│  ├─ trails/{dayKey}               하루 경로 문서 한 건
│  ├─ commands/{commandId}          해당 아이에게 보내는 명령
│  ├─ schedules/{scheduleId}        해당 아이의 소리 예약
│  ├─ places/{placeId}              해당 아이의 안심 장소
│  └─ settings/ringer               해당 아이의 소리 잠금 설정
└─ events/{eventId}                 childUid를 가진 가족 알림

inviteCodes/{code}
└─ familyId, role, createdByUid, expiresAt
```

초대 코드는 가족 문서의 단일 필드가 아니라 독립 문서다. 따라서 자녀용 코드와
보호자용 코드를 동시에 여러 개 발급할 수 있다. 코드를 입력한 사람은 코드 문서의
`role`과 같은 역할로만 가입할 수 있고, 만료 시각은 서버 규칙이 다시 검사한다.

## 권한 경계

| 작업 | 보호자 | 해당 자녀 | 다른 자녀 |
|---|---:|---:|---:|
| 가족 멤버 목록 읽기 | 가능 | 가능 | 가능 |
| 자녀 상태·경로 읽기 | 가능 | 가능 | 불가 |
| 자녀 상태·경로 쓰기 | 불가 | 가능 | 불가 |
| 명령 만들기 | 가능 | 불가 | 불가 |
| 명령 결과 쓰기 | 불가 | 가능 | 불가 |
| 자녀별 예약·장소·설정 쓰기 | 가능 | 불가 | 불가 |
| 보호자/자녀 초대 코드 만들기 | 가능 | 불가 | 불가 |

보호자끼리는 같은 권한을 가진다. 최초 생성자는 `ownerUid`로 남지만, 지금은 별도의
관리자 등급으로 사용하지 않는다. 멤버 제거·소유권 이전 UI는 아직 없다.

## 기존 1:1 데이터 이전

`schemaVersion`이 2보다 작은 가족은 보호자 앱이 처음 멤버 목록을 읽을 때 기존 가족
공용 `schedules/`, `places/`, `settings/ringer`를 당시 선택된 첫 자녀 아래로 한 번에
복사하고, `schemaVersion = 2`와 `primaryChildUid`를 기록한다. 배치가 끝나기 전 아이
폰은 구버전 경로로 물러나므로 예약과 장소가 갑자기 비지 않는다.

새 자녀를 초대할 때도 이 이전을 먼저 실행한다. 따라서 1:1 시절의 가족 공용 설정이
둘째 아이에게 잘못 적용되지 않는다.

## Firebase 무료 요금제에서의 비용

- 위치 후보는 계속 아이 폰 로컬 파일에만 쌓인다.
- 서버에는 보호자가 요청한 순간과 하루 한 번 안전 업로드 때 자녀별 하루 문서 한 건을 쓴다.
- 보호자가 늘어나면 각 보호자 폰이 화면을 열 때 읽기는 각각 발생한다. 보호자 수만큼
  읽기 비용이 늘지만, 위치 점 수만큼 쓰기가 늘지는 않는다.
- 알림 탭은 선택한 자녀의 최근 100건만 복합 인덱스로 읽는다.
- 자녀별 예약·장소는 소수 문서이며 실시간 구독도 해당 탭이 열려 있을 때만 유지한다.
- 서버에서 주기 작업을 돌리지 않으므로 Cloud Functions나 유료 서버가 필수는 아니다.

## 자체 서버로 옮길 때 지켜야 할 계약

Firestore 경로를 그대로 REST 자원으로 옮길 수 있다.

```text
POST   /families
POST   /families/{familyId}/invites
POST   /invites/{code}/join
GET    /families/{familyId}/members
GET    /families/{familyId}/children/{childUid}/trails/{dayKey}
POST   /families/{familyId}/children/{childUid}/commands
GET    /families/{familyId}/children/{childUid}/events
```

원격 명령과 알림은 WebSocket 또는 Server-Sent Events로 바꾸고, 하루 경로·설정은 일반
REST로 읽고 쓰면 된다. Android 화면은 `logic/`의 선택·경로 계산을 그대로 쓰고,
`core/` 저장소 구현만 Firestore에서 HTTP 구현으로 교체하는 방향이다.

자체 서버에서도 반드시 유지할 조건은 다음과 같다.

- 사용자 uid는 서버가 인증 토큰에서 결정하고 요청 본문 값을 믿지 않는다.
- 가입 역할은 초대 코드가 정하며 클라이언트가 임의로 고르지 못한다.
- 모든 자녀 자원은 `familyId + childUid` 복합 범위로 권한을 검사한다.
- 초대 만료, 이벤트 허용 시각, 마지막 신호는 서버 시각을 기준으로 한다.
- 명령 상태는 `pending → delivered → done|failed` 앞으로만 이동한다.
- 위치 업로드는 점 하나당 요청으로 바꾸지 않고 하루 문서 또는 압축 배치로 유지한다.

## 배포 순서

1. `firestore.rules`와 `firestore.indexes.json`을 먼저 게시한다.
2. 기존 보호자 폰을 0.7로 업데이트해 1:1 데이터를 자녀별 경로로 이전한다.
3. 기존 아이 폰을 0.7로 업데이트한다.
4. 그 뒤 새 보호자와 새 자녀 초대 코드를 발급한다.

0.6 앱은 새 자녀별 예약·장소 경로를 모르므로 N:N 가족에서는 모든 기기를 0.7로
맞추는 것이 안전하다. 앱 코드만 배포하고 보안 규칙·인덱스를 게시하지 않으면 새 가입과
자녀별 설정 쓰기가 `PERMISSION_DENIED`로 거부된다.
