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

    /** 전달 수단 교체 지점. 지금은 테스트/이관용으로만 쓴다. */
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
    // markState 를 그대로 노출하면 호출부가 pending→done 같은 규칙 위반 호출을
    // 실수로 만들기 쉽다. 이 세 함수는 "다음으로 갈 수 있는 상태"만 이름으로 준다.

    suspend fun markDelivered(familyId: String, childUid: String, commandId: String) =
        transport.markState(familyId, childUid, commandId, CommandState.DELIVERED)

    suspend fun markDone(familyId: String, childUid: String, commandId: String) =
        transport.markState(familyId, childUid, commandId, CommandState.DONE)

    suspend fun markFailed(familyId: String, childUid: String, commandId: String, error: String) =
        transport.markState(familyId, childUid, commandId, CommandState.FAILED, error.take(200))
}
