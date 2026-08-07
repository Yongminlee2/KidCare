package com.kidcare.family.core

import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.core.model.CommandDoc

/**
 * 명령이 부모 폰에서 아이 폰으로 건너가는 수단.
 *
 * 지금 구현체는 Firestore 스냅샷 리스너 하나뿐이다([FirestoreCommandTransport]).
 * 무료(Spark) 요금제로 가느라 Cloud Functions·FCM 을 안 쓰기로 했기 때문이다(설계서 §2).
 * 실사용에서 명령 유실이 관측되면 FCM 이나 Cloudflare Workers 중계로 올려야 하는데,
 * 그때 부르는 쪽 코드가 그대로이도록 이 인터페이스 하나로 감싼다 —
 * docs/known-issues.md 6번이 요구하는 제약이다.
 */
interface CommandTransport {

    /**
     * 아직 실행되지 않은 명령을 실시간으로 받는다. 자녀 폰에서만 쓴다.
     *
     * [onCommand] 는 같은 명령에 대해 **여러 번** 불릴 수 있다: 첫 스냅샷(캐시 →
     * 서버로 두 번 오는 경우 포함)뿐 아니라 리스너가 재연결될 때마다 그 시점에
     * 아직 `pending` 인 문서 전부를 다시 통째로 훑어 콜백한다. 이 함수는 "새로
     * 생긴 명령"만 골라주는 스트림이 아니라 "지금 pending 인 명령들"의 스냅샷을
     * 그대로 반복해서 넘겨주는 구조다. 같은 명령을 두 번 실행하면 안 되는 호출부
     * (예: find_phone 벨 울리기)는 [CommandDoc.id] 로 직접 중복 제거를 해야 한다 —
     * 이 계층은 중복을 걸러주지 않는다. 미래의 FCM·중계 구현체도 재전송·재연결
     * 시나리오에서 같은 명령이 다시 올 수 있으므로 이 계약은 구현체를 갈아끼워도
     * 그대로 유지돼야 한다.
     */
    fun observePending(
        familyId: String,
        childUid: String,
        onCommand: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration

    /** 명령 하나의 상태 변화를 따라간다. 보호자 화면이 "전달 중… → 완료"를 보여줄 때 쓴다. */
    fun observeOne(
        familyId: String,
        childUid: String,
        commandId: String,
        onChange: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration

    /** 명령을 발행하고 문서 ID 를 돌려준다. 보호자 폰에서만 쓴다. */
    suspend fun send(
        familyId: String,
        childUid: String,
        type: String,
        payload: Map<String, String>,
    ): String

    /**
     * 자녀 폰이 진행 상태를 적는다.
     *
     * 허용되는 전이는 `pending → delivered|failed`, `delivered → done|failed` 뿐이고
     * `done`·`failed` 는 종료 상태라 그 이후로는 어떤 전이도 없다. **이 함수 자신은
     * 그 순서를 확인하거나 막지 않는다** — 검사는 전부 firestore.rules 의 `commands`
     * update 규칙이 서버에서 한다. 규칙에 맞지 않는 전이(예: 아직 `pending` 인
     * 문서에 `done`을 쓰는 것)를 시도하면 이 suspend 함수는 그 자리에서 값을 돌려주지
     * 않고 예외(Firestore 구현체라면 `FirebaseFirestoreException(PERMISSION_DENIED)`)를
     * 던진다 — 실패가 미리 걸러지는 게 아니라 기기에서 그대로 터진다는 뜻이다.
     * 호출부는 이걸 반드시 잡아서 처리해야 한다.
     *
     * 따라서 `state = DONE`(또는 `FAILED` 를 `delivered` 이후 단계로 쓰고 싶을 때)을
     * 부르기 전에는 같은 commandId 로 `state = DELIVERED` 쓰기가 **먼저 성공**해
     * 있어야 한다 — 건너뛸 수 없다. 배달 표시가 실패한 채로 다음 단계를 시도하면
     * 서버가 거부하고, 그 예외를 "명령 자체가 실패했다"로 잘못 해석하면 실제로는
     * 실행된 명령이 실패로 보고되고, 그 사이 문서가 여전히 `pending` 이라 프로세스가
     * 재시작하면 같은 명령(find_phone 이면 벨 울림)이 다시 전달된다 — 이 순서를
     * 지키는 책임은 호출부(Task 3 의 자녀 수신 루프)에 있다.
     *
     * 이 계약은 지금의 Firestore 구현체만이 아니라, 나중에 이 인터페이스를 대신할
     * FCM·중계 구현체도 똑같이 지켜야 한다 — 서버 쪽 상태 기계는 전달 수단이
     * 바뀌어도 그대로이기 때문이다.
     */
    suspend fun markState(
        familyId: String,
        childUid: String,
        commandId: String,
        state: String,
        error: String = "",
    )
}
