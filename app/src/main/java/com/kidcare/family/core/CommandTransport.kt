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

    /** 아직 실행되지 않은 명령을 실시간으로 받는다. 자녀 폰에서만 쓴다. */
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

    /** 자녀 폰이 진행 상태를 적는다. */
    suspend fun markState(
        familyId: String,
        childUid: String,
        commandId: String,
        state: String,
        error: String = "",
    )
}
