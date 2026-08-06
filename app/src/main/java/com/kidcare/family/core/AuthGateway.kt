package com.kidcare.family.core

import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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

    // 두 화면이나 서비스가 동시에 로그인하면 익명 계정이 두 개 생기고,
    // 화면이 든 uid 와 실제 세션 uid 가 어긋나 Firestore 규칙에 막힌다.
    private val signInMutex = Mutex()

    fun currentUid(): String? = auth.currentUser?.uid

    /** 이미 로그인돼 있으면 그 uid 를, 아니면 익명 로그인 후 새 uid 를 준다. */
    suspend fun signIn(): String {
        auth.currentUser?.uid?.let { return it }
        signInMutex.withLock {
            // 락을 기다리는 동안 다른 호출이 이미 로그인을 끝냈을 수 있다.
            auth.currentUser?.uid?.let { return it }
            auth.signInAnonymously().await()
            return requireNotNull(auth.currentUser?.uid) { "익명 로그인은 성공했는데 uid 가 없다" }
        }
    }
}
