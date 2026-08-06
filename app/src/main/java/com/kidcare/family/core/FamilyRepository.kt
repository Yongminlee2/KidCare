package com.kidcare.family.core

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.core.model.FamilyDoc
import com.kidcare.family.core.model.MemberDoc
import com.kidcare.family.logic.InviteCode
import kotlinx.coroutines.tasks.await

/**
 * 가족 문서 하나가 이 앱의 모든 데이터의 뿌리다.
 *
 *   families/{familyId}
 *     ├ inviteCode, inviteExpiresAt
 *     └ members/{uid}  role = guardian | child
 *
 * 초대 코드는 10분 뒤 만료된다. 아이가 연결되는 즉시 무효화한다.
 */
object FamilyRepository {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private const val INVITE_TTL_MILLIS = 10 * 60 * 1000L

    /** 가족 문서를 만들고 보호자를 첫 멤버로 넣는다. familyId 를 돌려준다. */
    suspend fun createFamily(guardianUid: String): String {
        val now = System.currentTimeMillis()
        val familyRef = db.collection("families").document()
        familyRef.set(
            FamilyDoc(
                name = "우리 가족",
                createdAt = now,
                inviteCode = InviteCode.generate(),
                inviteExpiresAt = now + INVITE_TTL_MILLIS,
            )
        ).await()
        familyRef.collection("members").document(guardianUid).set(
            MemberDoc(role = "guardian", displayName = "보호자", updatedAt = now)
        ).await()
        return familyRef.id
    }

    /** 코드가 만료됐으면 새로 발급하고, 아니면 현재 코드를 준다. */
    suspend fun inviteCodeOf(familyId: String): String {
        val ref = db.collection("families").document(familyId)
        val doc = ref.get().await().toObject(FamilyDoc::class.java)
            ?: error("가족 문서가 없다: $familyId")
        if (doc.inviteExpiresAt > System.currentTimeMillis() && doc.inviteCode.isNotEmpty()) {
            return doc.inviteCode
        }
        val fresh = InviteCode.generate()
        ref.update(
            mapOf(
                "inviteCode" to fresh,
                "inviteExpiresAt" to System.currentTimeMillis() + INVITE_TTL_MILLIS,
            )
        ).await()
        return fresh
    }

    /** 자녀가 members 에 들어오는 순간을 감시한다. 붙인 리스너는 화면이 사라질 때 remove 해야 한다. */
    fun observeChildJoined(familyId: String, onJoined: (childUid: String) -> Unit): ListenerRegistration =
        db.collection("families").document(familyId).collection("members")
            .whereEqualTo("role", "child")
            .addSnapshotListener { snapshot, _ ->
                val childUid = snapshot?.documents?.firstOrNull()?.id ?: return@addSnapshotListener
                onJoined(childUid)
            }

    /**
     * 코드로 가족을 찾아 자녀로 들어간다.
     *
     * 코드는 families 컬렉션 전체에서 찾는다. 6자리 31진수라 충돌 확률이 낮고,
     * 만료된 코드는 걸러내므로 같은 코드가 동시에 두 가족에 살아있을 일은 사실상 없다.
     * 그래도 여러 개가 나오면 만료가 가장 늦은 것을 고른다.
     *
     * 멤버 문서 쓰기와 코드 무효화 쓰기는 두 번의 별도 요청이라 완전한 원자성은 없다.
     * 두 번째(무효화) 쓰기가 실패해도 절반 가입 상태로 위험해지지 않는다: 코드가 살아있는
     * 채로 남아도 ALREADY_FULL 검사가 같은 가족에 대한 재가입을 막고, 같은 아이가 재시도하면
     * document(childUid).set() 이 멱등이라 그대로 다시 성공한다. 최악의 경우도 TTL(10분) 안에
     * 코드가 자연 만료되는 것뿐이라 트랜잭션으로 묶지 않았다.
     */
    suspend fun joinFamily(code: String, childUid: String): String {
        val normalized = InviteCode.normalize(code)
        val now = System.currentTimeMillis()

        val matches = db.collection("families")
            .whereEqualTo("inviteCode", normalized)
            .get().await()

        if (matches.isEmpty) throw PairingException(PairingException.Reason.NOT_FOUND)

        val alive = matches.documents
            .filter { (it.getLong("inviteExpiresAt") ?: 0L) > now }
            .maxByOrNull { it.getLong("inviteExpiresAt") ?: 0L }
            ?: throw PairingException(PairingException.Reason.EXPIRED)

        val familyRef = alive.reference
        // 두 아이가 거의 동시에 같은 코드를 넣으면 이 조회와 아래 쓰기 사이에 경합이 생길 수 있다.
        // 두 폰짜리 가족 앱에서 실제로 부딪힐 확률은 극히 낮고, 부딪혀도 결과는 멤버 문서가
        // 하나 더 느슨하게 생기는 정도라 트랜잭션으로 막지 않았다.
        val existingChildren = familyRef.collection("members")
            .whereEqualTo("role", "child").get().await()
        if (existingChildren.documents.any { it.id != childUid }) {
            throw PairingException(PairingException.Reason.ALREADY_FULL)
        }

        familyRef.collection("members").document(childUid).set(
            MemberDoc(role = "child", displayName = "아이", updatedAt = now)
        ).await()

        // 코드를 즉시 무효화한다. 한 번 쓴 코드가 계속 살아 있으면 안 된다.
        familyRef.update("inviteExpiresAt", 0L).await()

        return familyRef.id
    }
}

class PairingException(val reason: Reason) : Exception(reason.name) {
    enum class Reason { NOT_FOUND, EXPIRED, ALREADY_FULL }
}
