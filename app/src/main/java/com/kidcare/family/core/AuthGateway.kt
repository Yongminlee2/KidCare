package com.kidcare.family.core

import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.tasks.await

/**
 * Firebase 익명 로그인 창구.
 *
 * 부모도 아이도 계정을 만들지 않는다. 기기마다 익명 uid 를 하나 받아서
 * 그걸 가족 문서의 멤버 식별자로 쓴다. 앱을 지웠다 깔면 uid 가 바뀌므로
 * 페어링을 다시 해야 한다 — 이건 의도한 동작이다.
 */
object AuthGateway {

    private val auth: FirebaseAuth get() = FirebaseAuth.getInstance()

    fun currentUid(): String? = auth.currentUser?.uid

    /** 이미 로그인돼 있으면 그 uid 를, 아니면 익명 로그인 후 새 uid 를 준다. */
    suspend fun signIn(): String {
        auth.currentUser?.uid?.let { return it }
        val result = auth.signInAnonymously().await()
        return requireNotNull(result.user?.uid) { "익명 로그인은 성공했는데 uid 가 없다" }
    }
}
