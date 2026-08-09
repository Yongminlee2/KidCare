package com.kidcare.family.logic

/** 보호자 화면이 선택할 자녀 한 명. 서버 종류와 무관하게 uid와 표시 이름만 쓴다. */
data class SelectableChild(
    val uid: String,
    val displayName: String,
    val joinedAt: Long = 0L,
)

/**
 * N명의 자녀 중 현재 선택을 안정적으로 고른다.
 *
 * - 저장해 둔 uid가 아직 가족에 있으면 그대로 유지한다.
 * - 삭제됐거나 첫 실행이면 가입 시각, 이름, uid 순으로 가장 앞선 자녀를 고른다.
 * - 자녀가 없으면 null이다.
 *
 * Firestore나 Android에 의존하지 않아 자체 서버로 바꿔도 이 규칙은 그대로 쓸 수 있다.
 */
object ChildSelector {
    fun select(children: List<SelectableChild>, preferredUid: String?): SelectableChild? {
        children.firstOrNull { it.uid == preferredUid }?.let { return it }
        return children.minWithOrNull(
            compareBy<SelectableChild> { if (it.joinedAt > 0L) it.joinedAt else Long.MAX_VALUE }
                .thenBy { it.displayName }
                .thenBy { it.uid }
        )
    }
}
