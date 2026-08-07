package com.kidcare.family.core

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.kidcare.family.core.model.CommandDoc
import com.kidcare.family.core.model.CommandState
import kotlinx.coroutines.tasks.await

/**
 * 자녀 폰은 위치 수집 때문에 어차피 포그라운드 서비스가 상시 돌고 있다.
 * 그 서비스 안에 이 리스너를 얹으면 명령이 1~3초 안에 닿는다 — FCM 이 사주는
 * "잠든 앱 깨우기"가 여기서는 필요 없는 이유다(설계서 §2 Firebase 요금제).
 */
class FirestoreCommandTransport : CommandTransport {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private fun commands(familyId: String, childUid: String) =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("commands")

    private fun toDoc(id: String, data: Map<String, Any?>): CommandDoc {
        @Suppress("UNCHECKED_CAST")
        val payload = (data["payload"] as? Map<String, Any?>)
            ?.mapValues { it.value?.toString().orEmpty() } ?: emptyMap()
        return CommandDoc(
            id = id,
            type = data["type"] as? String ?: "",
            payload = payload,
            state = data["state"] as? String ?: "",
            createdAt = (data["createdAt"] as? Number)?.toLong() ?: 0L,
            deliveredAt = (data["deliveredAt"] as? Number)?.toLong() ?: 0L,
            doneAt = (data["doneAt"] as? Number)?.toLong() ?: 0L,
            error = data["error"] as? String ?: "",
        )
    }

    override fun observePending(
        familyId: String,
        childUid: String,
        onCommand: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        commands(familyId, childUid)
            .whereEqualTo("state", CommandState.PENDING)
            .orderBy("createdAt", Query.Direction.ASCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    // FAILED_PRECONDITION(복합 색인 없음)의 생성 URL 은 e.message 를
                    // 잘라 찍으면 사라진다. 예외 객체를 통째로 넘겨야 logcat 에 남는다 —
                    // 이 색인 하나로 이미 두 번 시간을 잡아먹었다.
                    Log.w(TAG, "명령 구독 실패: familyId=$familyId", error)
                    onError(error)
                    return@addSnapshotListener
                }
                snapshot?.documents?.forEach { d ->
                    d.data?.let { onCommand(toDoc(d.id, it)) }
                }
            }

    override fun observeOne(
        familyId: String,
        childUid: String,
        commandId: String,
        onChange: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        commands(familyId, childUid).document(commandId)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.w(TAG, "명령 상태 구독 실패: commandId=$commandId", error)
                    onError(error)
                    return@addSnapshotListener
                }
                snapshot?.data?.let { onChange(toDoc(snapshot.id, it)) }
            }

    override suspend fun send(
        familyId: String,
        childUid: String,
        type: String,
        payload: Map<String, String>,
    ): String {
        val ref = commands(familyId, childUid).document()
        // state 는 반드시 pending 으로 시작해야 한다. 규칙이 그것만 허용한다 —
        // 아이를 거치지 않고 done 으로 위조된 명령이 "완료"로 보이는 것을 막는다.
        ref.set(
            mapOf(
                "type" to type,
                "payload" to payload,
                "state" to CommandState.PENDING,
                "createdAt" to System.currentTimeMillis(),
                "deliveredAt" to 0L,
                "doneAt" to 0L,
                "error" to "",
            )
        ).await()
        return ref.id
    }

    override suspend fun markState(
        familyId: String,
        childUid: String,
        commandId: String,
        state: String,
        error: String,
    ) {
        // 규칙이 자녀에게 이 네 키만 허용한다(hasOnly). 다른 키를 섞으면 통째로 거부된다.
        val update = mutableMapOf<String, Any>("state" to state, "error" to error)
        when (state) {
            CommandState.DELIVERED -> update["deliveredAt"] = System.currentTimeMillis()
            CommandState.DONE, CommandState.FAILED -> update["doneAt"] = System.currentTimeMillis()
        }
        commands(familyId, childUid).document(commandId).update(update).await()
    }

    private companion object {
        const val TAG = "CommandTransport"
    }
}
