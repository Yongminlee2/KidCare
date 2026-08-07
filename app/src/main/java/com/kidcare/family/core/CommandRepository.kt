package com.kidcare.family.core

import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.core.model.CommandDoc
import com.kidcare.family.core.model.CommandState

/**
 * 명령의 단일 창구. 부르는 쪽은 전달 수단을 모른다 — [transport] 를 갈아끼우면
 * FCM 이든 중계 서버든 그대로 돌아간다(docs/known-issues.md 6번).
 */
object CommandRepository {

    private var transport: CommandTransport = FirestoreCommandTransport()

    /**
     * 전달 수단 교체 지점. 지금은 테스트/이관용으로만 쓴다 — 동기화가 없는 평범한
     * `var` 라 두 스레드가 동시에 부르면 경합이 생기고(AuthGateway 의 signInMutex 같은
     * 보호 장치가 없다), 교체 이전에 이미 [observePending]/[observeOne] 으로 나간
     * `ListenerRegistration` 은 옛 [transport] 인스턴스에 그대로 붙들려 있어 교체해도
     * 멈추지 않는다. 그래서 앱이 떠 있는 동안 실시간으로 전달 수단을 바꿔치기하는
     * 용도로는 안전하지 않다 — 테스트 셋업(단일 스레드, 리스너 없음)이나 프로세스를
     * 새로 띄우는 이관 시나리오처럼 "아직 아무도 옛 transport 를 쓰고 있지 않을 때"만
     * 쓰라고 의도적으로 이렇게 남겨뒀다.
     */
    fun useTransport(newTransport: CommandTransport) {
        transport = newTransport
    }

    suspend fun send(
        familyId: String,
        childUid: String,
        type: String,
        payload: Map<String, String> = emptyMap(),
    ): String =
        transport.send(familyId, childUid, type, payload)

    /** 반복 호출·중복 통지 관련 계약은 [CommandTransport.observePending] 참고. */
    fun observePending(
        familyId: String,
        childUid: String,
        onCommand: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        transport.observePending(familyId, childUid, onCommand, onError)

    fun observeOne(
        familyId: String,
        childUid: String,
        commandId: String,
        onChange: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        transport.observeOne(familyId, childUid, commandId, onChange, onError)

    // markDelivered/markDone/markFailed 세 개로 나눈 이유: 규칙의 상태 전이가
    // pending→delivered/failed, delivered→done/failed 로 방향이 정해져 있는데,
    // markState 를 그대로 노출하면 호출부가 pending→done 같은 이름만으로는
    // 알아채기 힘든 호출을 만들기 쉽다. 이 세 함수는 "다음으로 갈 수 있는 상태"만
    // 이름으로 준다 — 다만 이름을 나눴다고 순서 자체를 강제하지는 않는다. 실제
    // 검사와 실패 방식은 아래 각 함수 문서와 [CommandTransport.markState] 참고.

    /**
     * `pending → delivered` 전이를 적는다.
     *
     * 이 쓰기가 실제로 성공해야만(예외 없이 반환해야만) 아래 [markDone] 을 부를 자격이
     * 생긴다 — 규칙이 `delivered` 상태에서만 `done` 전이를 허용하기 때문이다
     * ([CommandTransport.markState] 참고). 호출부가 이 성공을 확인하지 않고 곧장
     * 명령을 실행한 뒤 [markDone] 으로 넘어가면, 이 쓰기가 실패했을 경우 [markDone] 이
     * 서버에서 거부되고 문서는 여전히 `pending` 으로 남는다.
     */
    suspend fun markDelivered(familyId: String, childUid: String, commandId: String) =
        transport.markState(familyId, childUid, commandId, CommandState.DELIVERED)

    /**
     * `delivered → done` 전이를 적는다.
     *
     * 같은 commandId 로 [markDelivered] 가 먼저 성공해 있어야 한다 — 문서가 아직
     * `pending` 이면 이 호출은 값을 돌려주지 않고 예외로 실패한다(서버 규칙 거부,
     * [CommandTransport.markState] 참고). 이 함수 자신은 그 선행 조건을 확인하지
     * 않으므로 순서를 지키는 책임은 호출부에 있다.
     */
    suspend fun markDone(familyId: String, childUid: String, commandId: String) =
        transport.markState(familyId, childUid, commandId, CommandState.DONE)

    /**
     * `pending → failed` 또는 `delivered → failed` 전이를 적는다(둘 다 규칙이 허용).
     * 문서가 이미 `done`/`failed` 로 종료된 뒤라면 이 호출도 예외로 실패한다.
     */
    suspend fun markFailed(familyId: String, childUid: String, commandId: String, error: String) =
        transport.markState(familyId, childUid, commandId, CommandState.FAILED, error.take(200))
}
