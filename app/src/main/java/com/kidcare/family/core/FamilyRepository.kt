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
}
