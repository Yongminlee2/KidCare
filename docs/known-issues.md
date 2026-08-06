# 알려진 문제와 다음 단계 숙제

1~2단계(뼈대·페어링·권한·위치 수집·지도) 완료 시점(2026-08-07)의 미해결 항목이다.
전수 리뷰에서 확인된 것만 적었다. 추측이나 "언젠가 하면 좋을 것"은 넣지 않았다.

## 3단계 계획에 반드시 넣을 것

### 1. 재설치하면 가족이 영영 깨진다 (양쪽 다)

익명 로그인은 앱을 지우면 uid가 바뀐다. 그런데 양쪽 다 되돌릴 길이 없다.

- **아이 폰 재설치** — 새 uid가 되지만, 부모 폰은 이미 페어링이 끝나서 초대 코드 화면으로
  돌아갈 수 없다. 새 코드를 발급할 방법이 없어 아이가 다시 못 들어온다.
- **부모 폰 재설치** — 저장된 값이 사라져 `보호자`를 고르면 **새 가족**이 만들어진다.
  아이는 옛 가족에 계속 위치를 올리고 있으므로, 부모 화면은 영원히
  "아직 아이 폰이 연결되지 않았어요"다. 아이 쪽은 `RouterActivity`가
  `CHILD + isPaired`를 곧장 홈으로 보내서 페어링 화면에 평생 못 간다.

고치려면 양쪽에 "다시 연결" 경로가 필요한데, **아이 폰에 그 버튼을 다는 것은 설계 판단이
필요하다** — 아이가 스스로 감시를 풀 수 있게 되기 때문이다. 확인 절차를 두든, 부모에게
알림을 보내든, 결정하고 나서 만들 것.

### 2. 초대 코드 만료를 부모 폰 시계로 계산한다 — 3단계에서 처리함

`FamilyRepository`는 `System.currentTimeMillis() + 10분`으로 만료 시각을 쓰는데,
보안 규칙은 **서버 시각**(`request.time`)으로 검사한다. 부모 폰 시계가 15분 느리면
만들자마자 죽은 코드가 되고, 재발급해도 같은 시계를 쓰므로 계속 죽은 코드만 나온다.
아이 화면에는 "만료됐어요"만 뜨고 원인은 아무 데도 안 남는다.

처리: `members/{uid}`는 본인이 `updatedAt`만 바꾸는 update를 규칙이 이미 허용한다는
점을 이용해, `FieldValue.serverTimestamp()`를 그 필드에 쓰고 즉시 다시 읽어 기기·서버
시계 차이를 앱 실행당 한 번 잰다(`FamilyRepository.serverNow`). `createFamily`·
`inviteCodeOf`·`joinFamily`의 만료 계산이 전부 이 보정된 시각을 쓴다. 아직 그 가족의
멤버가 아닌 아이(페어링 전)는 측정할 자기 문서가 없어 오프셋 0(기기 시계 그대로)으로
물러나는데, 실제 보안 경계는 어차피 서버 쪽 규칙(`request.time`)이라 문제되지 않는다.
규칙은 손대지 않았다.

### 3. 지도가 아이 uid를 한 번만 찾는다 — 3단계에서 처리함

`MapTimelineFragment`는 `onViewCreated`에서 `findChildUid`를 한 번 부르고 끝이다.
부모가 지도 화면을 켜 둔 채로 아이가 페어링을 끝내면, 화면을 다시 만들기 전까지
"아직 아이 폰이 연결되지 않았어요"가 유지된다. `members`를 구독하도록 바꿀 것.

처리: `FamilyRepository.observeChildJoined` 구독으로 바꿨다. `onJoined`이 오면
`childUid`를 갱신하고 상태·구간 리스너를 다시 건다 — 화면에 리스너가 세 개
(`joinedListener`·`statusListener`·`segmentListener`) 떠 있고 전부 `onDestroyView`에서
지운다.

### 4. 30일 지난 위치를 지우는 주체가 없다 — 3단계에서 처리함

설계서 §3의 `dailyCleanup` Cloud Function이 유일한 삭제 경로였는데, 무료(Spark) 요금제로
가면서 Cloud Functions를 안 쓰기로 했다. **지금은 `points/`가 무한히 쌓인다.**
자녀 폰이 직접 오래된 문서를 지우게 하거나(보안 규칙상 자기 데이터라 가능하다),
부모 폰이 앱을 열 때 정리하게 할 것.

처리: `child/PointsCleaner`가 자녀 폰에서(`TrackingService`가 구간 재계산과 같은
방식으로 하루 한 번만) 30일 지난 점을 최대 200개씩 지운다. 한 번에 다 지우지
않으므로 오래 꺼져 있던 폰도 며칠에 걸쳐 따라잡을 뿐 실패하지 않는다.

## 4단계(원격 명령·폰찾기) 시작 전에 먼저 해야 할 것

### 5. 보안 규칙이 보호자의 명령 쓰기를 막는다

`firestore.rules`의 `match /children/{childUid}/{document=**}`는 쓰기를 그 아이 본인으로
제한한다. 4단계에서 부모가 `commands/`에 명령을 써야 하는데 지금 규칙으로는 막힌다.
`commands/` 전용 규칙을 따로 파야 한다. 규칙 파일 안에도 주석으로 적어뒀다.

**FCM 푸시가 아니라 Firestore 스냅샷 리스너로 명령을 전달하기로 했기 때문에 이건
미룰 수 없다** — 부모가 문서를 직접 써야 전달이 시작된다.

### 6. 명령 전달 계층은 인터페이스로 감쌀 것

무료 요금제로 가는 대신, 실사용에서 명령 유실이 관측되면 Blaze + Cloud Functions 또는
Cloudflare Workers 중계로 올릴 수 있어야 한다. 전송 수단을 바꿔도 호출하는 쪽 코드가
그대로이도록 처음부터 감싸 둘 것. 설계서 §2에 근거가 적혀 있다.

## 남겨두기로 판단한 것 (고치지 않음)

전수 리뷰에서 확인했지만 **실제 피해가 없어서 그대로 두기로** 한 것들이다.
다시 발견해서 시간 쓰지 말 것.

- `activity_guardian_pairing.xml`의 `ProgressBar`에 id가 없어 계속 돈다. 대부분의 상태에서는
  실제로 기다리는 중이라 맞는 표시이고, 틀린 경우(오류)에도 바로 위에 오류 문구가 보인다.
- `RouterActivity`의 `catch (Exception)`이 `CancellationException`도 먹는다. 그 뒤에
  아무것도 안 하고 끝나서 관측 가능한 오작동이 없다. (다른 네 곳은 전부 고쳤다.)
- `RoleStore`가 `apply()`(비동기)를 `startActivity` 직전에 쓴다. 1ms 미만의 창에서
  강제 종료돼야 하고, 그래도 역할 선택 화면으로 되돌아갈 뿐이다.
- 로그인만 하면 아무나 빈 가족 문서를 만들 수 있다. 무료 요금제 한도를 스스로 깎아먹는
  자해일 뿐이고, Cloud Functions 없이는 막을 방법이 없다.
- `Documents.kt`에 아직 쓰는 데가 없는 필드들(`fcmToken`, `appVersion`, `ringerMode`,
  `charging`, `lastSeenAt`). 다음 단계에서 쓴다.
  `PointDoc.speed`는 3단계 Task 3에서 고쳤다 — `LocationCollector`가 `loc.speed`를
  `Fix`에 담고 `StatusReporter`가 그대로 저장한다. 단, **이 수정 이전에 이미 저장된
  points 문서는 speed 가 0으로 남아 있다** — 옛 데이터를 다룰 때 0을 "정지"로
  해석하면 안 된다.
- `MapLifeCycleCallback.onMapDestroy()`가 비어 있다. `onDestroyView`에서 이미 정리한다.
- `FamilyRepository.createFamily`가 family 문서 쓰기와 보호자 member 문서 쓰기를 마친
  뒤에 크래시하면(서버 시각 보정을 하려고 그 사이 순서를 바꿨다 — 3단계 Task 8),
  `GuardianPairingActivity.kt`는 `store.familyId`를 `createFamily`가 **반환한 뒤에만**
  대입하므로 다음 실행은 그 familyId를 모른 채 `createFamily`를 다시 불러 새 auto-ID로
  가족을 또 만든다. 옛 `families/{id}` + `members/{uid}` 쌍은 아무도 다시 안 건드리는
  고아로 영원히 남는다. 고치지 않기로 한 이유: 사용자 입장에서는 새 가족이 정상적으로
  만들어져 페어링이 그대로 진행되므로 체감 피해가 없고(부모가 빈 코드에 갇히는 시나리오가
  아니다), 대안(가족 문서 참조를 쓰기 전에 미리 `store.familyId`에 대입)은 더 나쁘다 —
  크래시가 member 문서 쓰기 전에 나면 `inviteCodeOf`의 family update가 규칙(guardian이
  `memberOf`여야 함)에 막혀 부모가 진짜로 빈 코드에 갇힌다. 드문 크래시 1회당 고아 문서
  하나를 남기는 쪽이 확실히 더 안전한 트레이드오프다.

## 아직 실기기에서 한 번도 안 돌려봤다

1~2단계 전체가 **빌드와 단위 테스트로만 검증됐다.** 카카오 앱키가 없어서 지도는 한 번도
그려본 적이 없고, 두 폰 페어링도 실행해본 적이 없다. `docs/setup.md`에 단계별 확인 절차를
적어뒀으니 그대로 따라가면서 확인할 것.

특히 실기기에서만 드러날 수 있는 것:
- 삼성 절전 정책이 포그라운드 서비스를 죽이는지
- 권한 화면에서 OEM 대화상자가 `shouldShowRequestPermissionRationale` 타이밍을 바꾸는지
- 카카오 지도 마커의 앵커 위치와 카메라 동작
