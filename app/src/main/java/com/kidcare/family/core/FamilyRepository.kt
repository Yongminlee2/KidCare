package com.kidcare.family.core

import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Source
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.core.model.FamilyDoc
import com.kidcare.family.core.model.InviteCodeDoc
import com.kidcare.family.core.model.MemberDoc
import com.kidcare.family.logic.InviteCode
import kotlinx.coroutines.CancellationException
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
    private const val TAG = "FamilyRepository"

    /**
     * 기기 시계와 서버 시계의 차이(밀리초). 서버가 앞서면 양수다.
     *
     * inviteExpiresAt 은 기기 시계로 쓰는데 보안 규칙은 request.time(서버 시각)으로
     * 검사한다. 부모 폰 시계가 15분 느리면 만들자마자 죽은 코드가 되고, 재발급해도
     * 같은 시계를 쓰므로 영원히 죽은 코드만 나온다 — 화면에는 "만료됨"만 뜨고
     * 원인은 아무 데도 안 남는다. 앱 실행(프로세스)당 한 번만 재고 캐시한다.
     */
    @Volatile private var serverOffsetMillis: Long? = null

    /**
     * 서버 기준 "지금"(UTC 밀리초) = 기기 시계 + [serverOffsetMillis].
     *
     * 페어링 말고 화면에서도 필요해서 공개해 뒀다: 보호자의 관리 화면이 "마지막 신호
     * 12분 전"을 만들 때 [System.currentTimeMillis] 로 빼면, 부모 폰 시계가 뒤처져
     * 있는 만큼 그대로 어긋나 "마지막 신호 -3분 전" 같은 문구가 나온다
     * ([com.kidcare.family.guardian.ControlFragment] 참고).
     *
     * 첫 호출은 서버를 한 번 다녀오므로(measureServerOffset) 코루틴 안에서 부른다.
     * 그 뒤로는 프로세스가 살아 있는 동안 캐시된 오프셋만 더해 곧바로 돌려준다.
     */
    suspend fun serverNow(familyId: String?, uid: String?): Long {
        serverOffsetMillis?.let { return System.currentTimeMillis() + it }
        val offset = runCatching { measureServerOffset(familyId, uid) }.getOrElse { e ->
            if (e is CancellationException) throw e
            Log.w(TAG, "서버 시각 보정 실패 — 기기 시계를 그대로 쓴다", e)
            0L
        }
        serverOffsetMillis = offset
        return System.currentTimeMillis() + offset
    }

    /**
     * members/{uid} 문서는 본인이 updatedAt 필드만 바꾸는 update 를 규칙이 허용한다
     * (아래 members/{uid} update 규칙 참고: role 불변 + displayName·fcmToken·appVersion·
     * updatedAt 만 허용). FieldValue.serverTimestamp() 로 그 필드를 쓰고 즉시 서버에서
     * 다시 읽으면(Source.SERVER — 캐시로 읽으면 아직 추정치일 수 있다) 서버가 실제로
     * 기록한 시각을 알 수 있다.
     *
     * [uid] 가 아직 이 가족의 멤버가 아니면(예: 아이가 페어링을 끝내기 전) update 자체가
     * "자기 문서" 조건에 걸려 실패한다 — 그 문서가 없기 때문이다. 규칙을 고치지 않고는
     * 이 경우를 측정할 방법이 없으므로, 위 serverNow() 가 이 실패를 잡아 오프셋 0(기기
     * 시계 그대로)으로 물러난다.
     */
    private suspend fun measureServerOffset(familyId: String?, uid: String?): Long {
        if (familyId == null || uid == null) return 0L
        val ref = db.collection("families").document(familyId).collection("members").document(uid)
        val before = System.currentTimeMillis()
        ref.update("updatedAt", FieldValue.serverTimestamp()).await()
        val after = System.currentTimeMillis()
        // MemberDoc.updatedAt 은 Long 으로 선언돼 있지만 방금 쓴 값은 Firestore
        // Timestamp 다 — toObject(MemberDoc::class.java) 로 읽으면 타입이 안 맞아
        // 깨진다. 여기서는 raw snapshot 에서 getTimestamp 로만 읽는다.
        val serverMillis = ref.get(Source.SERVER).await()
            .getTimestamp("updatedAt")?.toDate()?.time ?: return 0L
        // 왕복 시간의 절반을 오차로 보고 중간값을 쓴다 — 네트워크 지연이 클수록
        // before 만 쓰면 오프셋을 과대평가한다.
        return serverMillis - (before + after) / 2
    }

    /** 가족 문서를 만들고 보호자를 첫 멤버로 넣는다. familyId 를 돌려준다. */
    suspend fun createFamily(guardianUid: String): String {
        val bootTime = System.currentTimeMillis()
        val familyRef = db.collection("families").document()

        // 순서가 중요하다: members/{uid} 를 만들 때 규칙이 families/{id}.ownerUid 를
        // 대조하므로 family 문서가 먼저 있어야 한다. 초대 코드·만료 시각은 아직
        // 정하지 않는다 — serverNow() 로 보정하려면 "자기 멤버 문서"가 있어야 하는데
        // (measureServerOffset 참고) 이 시점엔 그 문서가 없어 잴 수가 없다.
        familyRef.set(
            FamilyDoc(
                name = "우리 가족",
                createdAt = bootTime,
                inviteCode = "",
                inviteExpiresAt = 0L,
                ownerUid = guardianUid,
            )
        ).await()
        familyRef.collection("members").document(guardianUid).set(
            MemberDoc(role = "guardian", displayName = "보호자", updatedAt = bootTime)
        ).await()

        // 이제 이 uid 는 이 가족의 정식 멤버라 서버 시각을 잴 수 있다. 이 값으로
        // 코드와 만료 시각을 확정해 채워 넣는다 — 규칙은 guardian 이 이 두 필드를
        // update 하는 것을 허용한다(가족 문서 update 규칙 참고).
        val now = serverNow(familyRef.id, guardianUid)
        val code = InviteCode.generate()
        val expiresAt = now + INVITE_TTL_MILLIS
        familyRef.update(
            mapOf("inviteCode" to code, "inviteExpiresAt" to expiresAt)
        ).await()
        db.collection("inviteCodes").document(code).set(
            InviteCodeDoc(familyId = familyRef.id, expiresAt = expiresAt)
        ).await()
        return familyRef.id
    }

    /**
     * 코드가 만료됐으면 새로 발급하고, 아니면 현재 코드를 준다.
     *
     * [forceNew] 를 true 로 주면 만료 전이어도 무조건 새로 발급한다("새 번호 받기"
     * 버튼용). 기본값 false 는 옛 동작 그대로라 기존 호출부에 영향이 없다.
     */
    suspend fun inviteCodeOf(familyId: String, forceNew: Boolean = false): InviteCodeInfo {
        val ref = db.collection("families").document(familyId)
        val doc = ref.get().await().toObject(FamilyDoc::class.java)
            ?: error("가족 문서가 없다: $familyId")
        // 이 함수를 부르는 시점엔 호출자가 이미 이 가족의 보호자다(createFamily 직후거나,
        // 기존 가족의 코드를 다시 띄우는 화면이거나) — measureServerOffset 이 쓸 자기
        // 멤버 문서가 있다. createFamily 가 기기 시계로 임시로 써 둔 값이 실제로
        // 서버 기준 이미 만료돼 있었다면, 아래 비교가 그걸 잡아내 바로 재발급한다
        // (=known-issues 2 의 "만들자마자 죽은 코드"가 여기서 자연스럽게 복구된다).
        val now = serverNow(familyId, AuthGateway.currentUid())
        if (!forceNew && doc.inviteExpiresAt > now && doc.inviteCode.isNotEmpty()) {
            return InviteCodeInfo(doc.inviteCode, doc.inviteExpiresAt)
        }

        // 코드가 만료됐거나 forceNew 다 → 새로 발급한다. 한 가족에 살아있는 코드가
        // 둘 이상 존재하면 안 되므로, 새 inviteCodes 문서를 먼저 만들어 새 코드가
        // 즉시 조회 가능하게 한 뒤 옛 문서를 지운다 — 중간에 실패해도 "조회 가능한
        // 코드가 하나도 없는" 순간은 생기지 않는다(최악의 경우 옛 문서가 고아로
        // 남을 뿐이고, 그 문서로 조회해도 실제 검증은 families.inviteCode 대조에서
        // 다시 걸러진다).
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
        return InviteCodeInfo(fresh, freshExpiresAt)
    }

    /**
     * 자녀가 members 에 들어오는 순간을 감시한다. 붙인 리스너는 화면이 사라질 때 remove 해야 한다.
     *
     * [onError] 없이 에러를 그냥 삼키면(예전 코드) PERMISSION_DENIED 나 리스너가 끊기는
     * 사고가 나도 화면은 계속 스피너만 돌리고 아무 데도 로그가 안 남는다 — 이 앱에서
     * 가장 흔한 실패 유형인데 원인을 알 방법이 없었다. 그래서 로그(logcat)와 화면 표시를
     * 호출부가 고를 수 있게 콜백으로 넘긴다.
     */
    fun observeChildJoined(
        familyId: String,
        onJoined: (childUid: String) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        db.collection("families").document(familyId).collection("members")
            .whereEqualTo("role", "child")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.w(TAG, "observeChildJoined 리스너 실패: familyId=$familyId", error)
                    onError(error)
                    return@addSnapshotListener
                }
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

        val codeDoc = db.collection("inviteCodes").document(normalized).get().await()
        if (!codeDoc.exists()) {
            // 존재하지 않는 게 아니라 서버에 물어볼 수가 없었던 경우일 수 있다:
            // 오프라인이면 이 get() 은 캐시로 대답하는데, 이 코드는 캐시에 있을 리
            // 없으므로(아이가 이 코드를 처음 조회하는 것) exists()==false 가 그대로
            // 나온다 — 그러면 "코드가 틀렸다"가 아니라 "인터넷이 안 된다"고 안내해야
            // 한다. 안 그러면 아이는 멀쩡한 코드를 계속 다시 입력하게 된다.
            if (codeDoc.metadata.isFromCache) throw PairingException(PairingException.Reason.OFFLINE)
            throw PairingException(PairingException.Reason.NOT_FOUND)
        }

        val familyId = codeDoc.getString("familyId")
            ?: throw PairingException(PairingException.Reason.NOT_FOUND)
        val expiresAt = codeDoc.getLong("expiresAt") ?: 0L
        // 이 아이는 아직 이 가족의 멤버가 아니라 measureServerOffset 이 쓸 자기 멤버
        // 문서가 없다 — serverNow() 는 그 실패를 잡아 오프셋 0(기기 시계 그대로)으로
        // 물러난다. expiresAt 자체는(위 Step 이 고쳐진 뒤로는) 이미 서버 시각 기준으로
        // 정확히 쓰인 값이므로, 이 비교가 다소 부정확해도 진짜 보안 경계는 members
        // create 규칙의 request.time 대조다 — 여기는 헛걸음(오프라인 왕복)을 줄이는
        // 사전 안내일 뿐이다.
        val now = serverNow(familyId, childUid)
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
     * 자녀의 마지막 상태(children/{childUid} 문서 자체 — StatusReporter 주석 참고,
     * 설계서의 별도 status 하위 문서가 아니다)를 **한 번** 읽는다. 문서가 아직
     * 없으면(자녀 폰이 한 번도 안 올렸으면) null 이다.
     *
     * 옛 `observeChildStatus`(실시간 구독)를 이걸로 갈아치웠다. 구독을 없앤 이유는
     * 두 가지다.
     *
     * 1. **구독할 대상이 더 이상 안 바뀐다.** 자녀 폰이 위치를 올릴 때마다 이 문서를
     *    덮어쓰던 주기적 쓰기가 사라졌다(무료 한도, docs/known-issues.md 12번).
     *    이제 이 문서는 부모가 '지금 위치 확인'을 눌렀을 때와 하루 한 번만 바뀌므로,
     *    화면이 떠 있는 내내 리스너를 붙들고 있을 이유가 없다.
     * 2. **읽기가 언제 얼마나 일어나는지 코드에 보여야 한다.** 구독은 문서가 바뀔
     *    때마다 조용히 읽기를 만든다 — 한도를 지켜야 하는 앱에서 그건 계산할 수
     *    없는 비용이다.
     *
     * 자녀가 대답하는 순간을 화면이 알아야 하는 곳은 명령 문서 하나뿐이고, 그건
     * [CommandRepository.observeOne] 로 **명령이 끝날 때까지만** 짧게 붙인다.
     */
    suspend fun fetchChildStatus(familyId: String, childUid: String): ChildStatusDoc? =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .get().await().toObject(ChildStatusDoc::class.java)
}

/** [FamilyRepository.inviteCodeOf] 의 결과. 코드와 함께 만료 시각도 줘야 화면에 남은 시간을 보여줄 수 있다. */
data class InviteCodeInfo(val code: String, val expiresAt: Long)

class PairingException(val reason: Reason) : Exception(reason.name) {
    // ALREADY_FULL 은 지금은 joinFamily 가 던지지 않지만, Task 4/6 UI 문구가 이미
    // 이 값을 참조하고 나중에 다자녀 지원이 들어오면 다시 쓸 것이므로 남겨둔다.
    enum class Reason { NOT_FOUND, EXPIRED, ALREADY_FULL, OFFLINE }
}
