package com.kidcare.family.core.model

/**
 * Firestore 문서와 1:1 로 대응하는 데이터 클래스들.
 *
 * Firestore 의 toObject() 는 인자 없는 생성자를 요구하므로 모든 필드에 기본값을 준다.
 * 시각은 전부 UTC 밀리초다 (설계서 Global Constraints).
 */

data class FamilyDoc(
    val name: String = "",
    val createdAt: Long = 0L,
    val inviteCode: String = "",
    val inviteExpiresAt: Long = 0L,
    // 이 가족을 만든 보호자의 uid. Firestore 규칙이 "보호자 자리를 만든 사람만
    // 가져간다"를 검증할 때 대조하는 값이다 (Task 6 fix round 1, 보안 리뷰 반영).
    val ownerUid: String = "",
)

data class MemberDoc(
    val role: String = "",          // "guardian" | "child"
    val displayName: String = "",
    val fcmToken: String = "",
    val appVersion: String = "",
    val updatedAt: Long = 0L,
    // 자녀가 자기 멤버 문서를 만들 때 실제로 입력한 초대 코드. 규칙이 이 값을
    // families/{id}.inviteCode 와 대조해 "코드를 정말 아는 사람만 자녀가 된다"를
    // 서버에서 검증한다 (Task 6 fix round 1). 보호자 멤버 문서에는 빈 채로 둔다.
    val joinCode: String = "",
)

/**
 * inviteCodes/{code} — 문서 ID 자체가 정규화된 6자리 코드다.
 *
 * families 컬렉션을 필드 조건(whereEqualTo)으로 query 하게 열어두면 Firestore
 * 규칙에서는 그 query 를 막을 방법이 read 를 완전히 잠그는 것뿐이라, 결과적으로
 * 누구나 families 컬렉션 전체를 list 해서 초대 코드를 긁어갈 수 있었다(보안 리뷰
 * Critical 1). 이 컬렉션은 문서 ID 로 정확히 아는 코드만 get 할 수 있고 list 는
 * 규칙에서 아예 금지하므로, "코드를 아는 것" 자체가 접근 권한이 된다.
 */
data class InviteCodeDoc(
    val familyId: String = "",
    val expiresAt: Long = 0L,
)

data class ChildStatusDoc(
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val accuracy: Float = 0f,
    val at: Long = 0L,
    val battery: Int = -1,
    val charging: Boolean = false,
    val ringerMode: String = "normal",
    val lastSeenAt: Long = 0L,
)

data class PointDoc(
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val accuracy: Float = 0f,
    val speed: Float = 0f,
    val at: Long = 0L,
    val battery: Int = -1,
)

/**
 * children/{childUid}/segments/{autoId} — 하루를 머무름·이동으로 요약한 한 토막.
 *
 * 자녀 폰이 자기 points 를 읽어 계산해 올린다. 보호자 폰이 하루치 원시 점(하루 최대
 * 수백 개)을 매번 내려받으면 느리고 Firestore 읽기 사용량도 커지는데, 요약본은
 * 하루 20~30건이면 끝난다.
 *
 * [dayKey] 는 "2026-08-07" 꼴로, 그 구간이 **시작한 날**을 자녀 폰의 시간대 기준으로
 * 박아둔 값이다. startAt 범위로 쿼리하면 자정을 걸친 구간이 어느 날에 속하는지 매번
 * 계산해야 하고 시간대가 바뀌면 어긋난다.
 */
data class SegmentDoc(
    val type: String = "",          // "STAY" | "MOVE"
    val startAt: Long = 0L,
    val endAt: Long = 0L,
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val distanceMeters: Double = 0.0,
    val pointCount: Int = 0,
    /** 머무른 곳 이름. Task 4 가 채운다. 비어 있으면 화면이 "머무른 곳"으로 표시한다. */
    val placeName: String = "",
    val dayKey: String = "",
)
