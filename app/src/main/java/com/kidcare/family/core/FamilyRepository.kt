package com.kidcare.family.core

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.core.model.FamilyDoc
import com.kidcare.family.core.model.InviteCodeDoc
import com.kidcare.family.core.model.MemberDoc
import com.kidcare.family.logic.InviteCode
import kotlinx.coroutines.tasks.await

/**
 * 가족 문서 하나가 이 앱의 모든 데이터의 뿌리다.
 *
 *   families/{familyId}
 *     ├ inviteCode, inviteExpiresAt, ownerUid
 *     └ members/{uid}  role = guardian | child
 *   inviteCodes/{code}   문서 ID 가 코드 자체 — families 를 코드로 찾는 용도
 *
 * 초대 코드는 10분 뒤 만료된다. 아이가 연결되는 즉시 무효화한다.
 *
 * inviteCodes 는 별도 컬렉션이다. families 를 inviteCode 필드로 whereEqualTo
 * query 하게 열어두면, Firestore 규칙은 get 과 list 를 구분하지 못해 결국 회원이
 * 아닌 사람도 families 컬렉션 전체를 list 해서 모든 초대 코드를 긁어갈 수 있었다
 * (Task 6 보안 리뷰 Critical 1). inviteCodes 는 문서 ID 로 정확히 아는 코드만
 * get 하고 list 는 규칙에서 아예 막으므로, "코드를 아는 것"이 곧 접근 권한이 된다.
 */
object FamilyRepository {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private const val INVITE_TTL_MILLIS = 10 * 60 * 1000L

    /** 가족 문서를 만들고 보호자를 첫 멤버로 넣는다. familyId 를 돌려준다. */
    suspend fun createFamily(guardianUid: String): String {
        val now = System.currentTimeMillis()
        val familyRef = db.collection("families").document()
        val code = InviteCode.generate()
        val expiresAt = now + INVITE_TTL_MILLIS

        // 순서가 중요하다: members/{uid} 를 만들 때 규칙이 families/{id}.ownerUid 를
        // 대조하므로 family 문서가 먼저 있어야 하고, inviteCodes/{code} 를 만들 때
        // 규칙이 "이 가족의 보호자인가"를 대조하므로 guardian 멤버 문서가 먼저 있어야 한다.
        familyRef.set(
            FamilyDoc(
                name = "우리 가족",
                createdAt = now,
                inviteCode = code,
                inviteExpiresAt = expiresAt,
                ownerUid = guardianUid,
            )
        ).await()
        familyRef.collection("members").document(guardianUid).set(
            MemberDoc(role = "guardian", displayName = "보호자", updatedAt = now)
        ).await()
        db.collection("inviteCodes").document(code).set(
            InviteCodeDoc(familyId = familyRef.id, expiresAt = expiresAt)
        ).await()
        return familyRef.id
    }

    /** 코드가 만료됐으면 새로 발급하고, 아니면 현재 코드를 준다. */
    suspend fun inviteCodeOf(familyId: String): String {
        val ref = db.collection("families").document(familyId)
        val doc = ref.get().await().toObject(FamilyDoc::class.java)
            ?: error("가족 문서가 없다: $familyId")
        val now = System.currentTimeMillis()
        if (doc.inviteExpiresAt > now && doc.inviteCode.isNotEmpty()) {
            return doc.inviteCode
        }

        // 코드가 만료됐다 → 새로 발급한다. 한 가족에 살아있는 코드가 둘 이상
        // 존재하면 안 되므로, 새 inviteCodes 문서를 먼저 만들어 새 코드가 즉시
        // 조회 가능하게 한 뒤 옛 문서를 지운다 — 중간에 실패해도 "조회 가능한 코드가
        // 하나도 없는" 순간은 생기지 않는다(최악의 경우 옛 문서가 고아로 남을 뿐이고,
        // 그 문서로 조회해도 실제 검증은 families.inviteCode 대조에서 다시 걸러진다).
        val fresh = InviteCode.generate()
        val freshExpiresAt = now + INVITE_TTL_MILLIS
        ref.update(
            mapOf(
                "inviteCode" to fresh,
                "inviteExpiresAt" to freshExpiresAt,
            )
        ).await()
        db.collection("inviteCodes").document(fresh).set(
            InviteCodeDoc(familyId = familyId, expiresAt = freshExpiresAt)
        ).await()
        if (doc.inviteCode.isNotEmpty()) {
            db.collection("inviteCodes").document(doc.inviteCode).delete().await()
        }
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
     * 코드 → familyId 조회는 inviteCodes/{code} 문서를 ID로 한 번에 읽는다(위 오브젝트
     * 문서 참고 — families 를 query 로 찾지 않는 이유). 이 시점의 아이는 아직 멤버가
     * 아니므로 families/{id} 문서 자체는 읽을 수 없다(규칙상 get 이 memberOf 로 막혀
     * 있다). 그래서 진짜 검증(코드가 그 가족의 현재 코드와 일치하는지, 만료 전인지)은
     * members/{uid} 를 create 하는 순간 Firestore 규칙이 서버에서
     * families/{id}.inviteCode / inviteExpiresAt 를 직접 대조해 수행한다 — 규칙 안의
     * get() 은 호출자의 read 권한과 무관하게 항상 평가되므로 가능하다. 클라이언트는
     * 그 결과를 성공 아니면 PERMISSION_DENIED 로만 받는다.
     *
     * 두 번째 아이가 거의 동시에 같은 코드로 joinFamily 를 부르는 경합은 더 이상
     * ALREADY_FULL 로 사전 차단하지 않는다(그러려면 아직 멤버가 아닌 아이가 members
     * 를 read 해야 하는데, 그건 이 보안 수정으로 막혔다). 대신 첫 아이가 join 에
     * 성공하는 즉시 families.inviteExpiresAt 을 0 으로 만들어 코드를 죽이므로,
     * 뒤늦게 도착한 두 번째 아이는 members create 규칙의 만료 검사에서 그대로
     * PERMISSION_DENIED 를 받는다 — 아래에서 이를 EXPIRED 로 안내한다.
     *
     * 무효화(두 번째 쓰기)가 절반만 성공해도 위험하지 않다: family.inviteExpiresAt
     * 을 0 으로 만드는 쓰기가 실제 보안 경계이고 그것부터 먼저 하므로, 그 쓰기가
     * 끝난 순간 이미 이 코드로는 아무도 새로 join 할 수 없다. 뒤이은 inviteCodes
     * 문서 삭제는 조회 편의를 위한 뒷정리일 뿐이라 실패해도 고아 문서 하나가
     * 남는 것 외에는 아무 영향이 없다.
     */
    suspend fun joinFamily(code: String, childUid: String): String {
        val normalized = InviteCode.normalize(code)
        val now = System.currentTimeMillis()

        val codeDoc = db.collection("inviteCodes").document(normalized).get().await()
        if (!codeDoc.exists()) throw PairingException(PairingException.Reason.NOT_FOUND)

        val familyId = codeDoc.getString("familyId")
            ?: throw PairingException(PairingException.Reason.NOT_FOUND)
        val expiresAt = codeDoc.getLong("expiresAt") ?: 0L
        if (expiresAt <= now) throw PairingException(PairingException.Reason.EXPIRED)

        val familyRef = db.collection("families").document(familyId)

        try {
            familyRef.collection("members").document(childUid).set(
                MemberDoc(role = "child", displayName = "아이", updatedAt = now, joinCode = normalized)
            ).await()
        } catch (e: FirebaseFirestoreException) {
            if (e.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) {
                // 규칙이 거부했다는 것은 코드가 이미 다른 아이에게 소비됐거나 그 사이
                // 만료됐다는 뜻이 압도적으로 많다. 새 오류 문구를 만들지 않고 기존
                // "만료됨" 안내로 합친다.
                throw PairingException(PairingException.Reason.EXPIRED)
            }
            throw e
        }

        familyRef.update("inviteExpiresAt", 0L).await()
        db.collection("inviteCodes").document(normalized).delete().await()

        return familyId
    }

    /** 가족의 자녀 uid 를 찾는다. 아직 자녀가 안 붙었으면 null. */
    suspend fun findChildUid(familyId: String): String? =
        db.collection("families").document(familyId).collection("members")
            .whereEqualTo("role", "child").get().await()
            .documents.firstOrNull()?.id

    /**
     * 자녀의 현재 상태(children/{childUid} 문서 자체 — StatusReporter 주석 참고,
     * 설계서의 별도 status 하위 문서가 아니다)를 실시간 구독한다.
     * 붙인 리스너는 화면이 사라질 때 반드시 remove 해야 한다.
     */
    fun observeChildStatus(
        familyId: String,
        childUid: String,
        onChange: (ChildStatusDoc) -> Unit,
    ): ListenerRegistration =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .addSnapshotListener { snapshot, _ ->
                snapshot?.toObject(ChildStatusDoc::class.java)?.let(onChange)
            }
}

class PairingException(val reason: Reason) : Exception(reason.name) {
    // ALREADY_FULL 은 지금은 joinFamily 가 던지지 않지만, Task 4/6 UI 문구가 이미
    // 이 값을 참조하고 나중에 다자녀 지원이 들어오면 다시 쓸 것이므로 남겨둔다.
    enum class Reason { NOT_FOUND, EXPIRED, ALREADY_FULL }
}
