package com.kidcare.family.guardian

import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import com.google.firebase.firestore.TransactionOptions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

/**
 * "이 폰을 가족에서 빼기" — 보호자 폰이 스스로 가족에서 나가고 계정을 지운다.
 *
 * 아이폰 보호자 앱과 같은 순서다: **서버의 멤버 기록 → 익명 계정 → 이 폰의 기록.**
 * 서버가 멤버 기록 삭제를 확인해 주지 않으면 아무것도 지우지 않는다. 규칙은 고치지
 * 않는다 — 보호자는 자기 멤버 문서를 지울 수 있다(firestore.rules members delete).
 *
 * **아이 폰에는 이 기능을 두지 않는다.** 아이가 스스로 감시를 풀 수 있게 되기 때문이다
 * (README "재설치하면 가족이 깨집니다" 와 같은 판단).
 */
object LeaveFamily {

    enum class AuthOutcome {
        /** 익명 계정까지 서버에서 지웠다. */
        DELETED,

        /** 계정 삭제를 확인하지 못해 로그아웃만 했다. 남은 계정에는 uid 와 만든 시각뿐이다. */
        SIGNED_OUT_ONLY,
    }

    private const val TAG = "LeaveFamily"
    private const val AUTH_TIMEOUT_MILLIS = 10_000L

    /** 보호자 폰이 쓰는 저장소 전부. 언어 설정은 AppCompat 이 따로 두므로 여기 없다. */
    private val LOCAL_STORES = listOf(
        "kidcare",
        "kidcare_alert",
        "kidcare_alarm_memo",
        "kidcare_place_sync",
        "kidcare_requests",
        "kidcare_schedule_sync",
    )

    /**
     * `families/{familyId}/members/{uid}` 를 지운다. **이미 빠진 상태면 성공으로 본다.**
     *
     * 보통 `delete()` 가 아니라 한 번만 시도하는 트랜잭션을 쓴다. `delete()` 는 오프라인이면
     * 대기열에 들어가 나중에 올라가므로, "확인하지 못해 아무것도 안 지웠어요"라고 말한 뒤
     * 몇 시간 뒤 몰래 빠질 수 있다. 트랜잭션은 대기열에 남지 않는다.
     *
     * 앞 시도가 시간 초과로 끝났는데 서버에는 닿았다면 지금은 멤버가 아니라 거부된다.
     * 그때 가족 문서를 서버에서 읽어 본다 — 그것도 거부되면 정말 빠진 것이고, 읽히면
     * 아직 멤버이므로 원래 오류를 던진다.
     */
    suspend fun removeMember(familyId: String, uid: String) {
        val db = FirebaseFirestore.getInstance()
        val family = db.collection("families").document(familyId)
        val member = family.collection("members").document(uid)
        try {
            val once = TransactionOptions.Builder().setMaxAttempts(1).build()
            db.runTransaction(once) { tx -> tx.delete(member) }.await()
        } catch (e: FirebaseFirestoreException) {
            if (e.code != FirebaseFirestoreException.Code.PERMISSION_DENIED) throw e
            try {
                family.get(Source.SERVER).await()
            } catch (read: FirebaseFirestoreException) {
                if (read.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) return
                throw read
            }
            throw e
        }
    }

    /**
     * 익명 계정을 지운다. 못 지우면 로그아웃만 하고 그렇게 알린다.
     *
     * 던지지 않는다: 멤버 기록을 지운 **뒤에만** 불리므로, 여기서 실패를 올리면 "가족에서는
     * 빠졌는데 실패했다"는 모순된 안내가 된다. 익명 계정은 로그아웃하면 다시 들어갈 길이 없다.
     */
    suspend fun deleteAccount(): AuthOutcome {
        val auth = FirebaseAuth.getInstance()
        auth.currentUser?.let { user ->
            try {
                withTimeout(AUTH_TIMEOUT_MILLIS) { user.delete().await() }
                return AuthOutcome.DELETED
            } catch (e: TimeoutCancellationException) {
                Log.w(TAG, "계정 삭제가 제시간에 안 끝나 로그아웃만 한다", e)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "계정 삭제 실패 — 로그아웃만 한다", e)
            }
        }
        auth.signOut()
        return AuthOutcome.SIGNED_OUT_ONLY
    }

    /**
     * 이 폰의 가족 연결을 지운다.
     *
     * 파일을 지우지(`deleteSharedPreferences`) 않고 내용을 비운다. 안드로이드는 한 번 연
     * 저장소를 메모리에 붙들고 있어서, 파일만 지우면 곧바로 뜨는 첫 화면이 **옛 역할과
     * 가족을 그대로 읽는다.**
     */
    fun clearLocal(context: Context) {
        AlertService.setEnabled(context, false)
        LOCAL_STORES.forEach {
            context.getSharedPreferences(it, Context.MODE_PRIVATE).edit().clear().commit()
        }
    }
}
