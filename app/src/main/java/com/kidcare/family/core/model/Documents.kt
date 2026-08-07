package com.kidcare.family.core.model

import com.google.firebase.Timestamp
import com.google.firebase.firestore.ServerTimestamp

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

/**
 * children/{childUid} — 아이 폰의 현재 상태. 아이 폰이 위치를 올릴 때마다 덮어쓴다
 * (child/StatusReporter).
 *
 * ## 마지막 신호 시각이 왜 두 개인가
 *
 * [lastSeenAt] 은 **아이 폰 자기 시계**로 적은 값이다. 보호자 화면의 "마지막 신호 N분
 * 전"은 `지금 - lastSeenAt` 인데, 아이 폰 시계가 앞서 있으면 이 뺄셈이 음수가 되어
 * "애기폰이 응답하지 않아요" 바로 아래에 "마지막 신호 방금 전"이 찍힌다 — 두 줄이
 * 서로를 부정한다(docs/known-issues.md 7번).
 *
 * [lastSeenServerAt] 은 같은 순간을 **서버 시계**로 적는다. `@ServerTimestamp` 는
 * "이 필드가 null 인 채로 쓰기가 나가면 서버가 자기 시각으로 채운다"는 뜻이라
 * ([com.google.firebase.firestore.util.CustomClassMapper] 가 null 을
 * `FieldValue.serverTimestamp()` 로 바꿔 보낸다), StatusReporter 는 이 필드를 아예
 * 건드리지 않는다. 보호자 쪽 `serverNow` 도 서버 시각이므로 뺄셈의 양쪽이 같은 시계를
 * 쓰게 되어 스큐가 근본에서 사라진다.
 *
 * **[lastSeenAt] 을 없애지 않고 둘 다 쓰는 이유**: 이미 서버에 올라가 있는 문서와, 옛
 * 버전을 깔고 있는 아이 폰이 계속 쓰는 문서에는 [lastSeenServerAt] 이 없다. 타입을
 * `Long` → `Timestamp` 로 갈아치우면 그런 문서에서 `toObject()` 가 그 필드에서 깨지고,
 * 그러면 마지막 신호 한 줄이 아니라 **보호자 지도의 실시간 위치 구독까지 같이 죽는다**
 * (`FamilyRepository.observeChildStatus`). 그래서 새 필드를 따로 더하고 읽는 쪽이
 * "있으면 서버 값, 없으면 옛 값"으로 물러난다 — 마이그레이션 없이 굴러간다.
 *
 * 새 필드가 `Timestamp?` 라 [lastSeenAt] 과 단위가 다르다는 점에 주의할 것. 읽는 쪽은
 * 반드시 `guardian/GuardianMainActivity.kt` 의 `ChildStatusDoc.lastSignal()` 하나만
 * 지나가게 해서 이 판단을 여러 곳에 흩뿌리지 않는다.
 */
data class ChildStatusDoc(
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val accuracy: Float = 0f,
    val at: Long = 0L,
    val battery: Int = -1,
    val charging: Boolean = false,
    val ringerMode: String = "normal",
    val lastSeenAt: Long = 0L,
    // 사용처 지정(@get:)이 필요하다: 이 애노테이션은 자바 애노테이션이라 코틀린
    // 프로퍼티에는 못 붙고, 아무것도 안 적으면 private 백킹 필드로 간다. Firestore 가
    // 쓰기에서 실제로 읽는 것은 게터 쪽 애노테이션이므로(BeanMapper.applyGetterAnnotations)
    // 게터에 붙여야 의도가 코드에 그대로 드러난다.
    @get:ServerTimestamp val lastSeenServerAt: Timestamp? = null,
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

/**
 * children/{childUid}/commands/{autoId} — 보호자가 쓰고 자녀가 실행한다.
 *
 * [id] 는 Firestore 문서 ID 라 문서 본문에는 없다. 읽어올 때 채워 넣는다
 * (보호자 화면이 "이 명령"의 상태를 따라가려면 ID 가 필요하다).
 *
 * [payload] 를 Map<String,String> 으로 둔 이유: 명령 종류마다 필요한 값이 다른데
 * 타입마다 필드를 늘리면 Firestore 문서가 빈 필드 투성이가 된다. 값이 몇 개 안 되고
 * 전부 짧은 문자열이라 이 정도면 충분하다.
 *
 * 상태 전이는 pending -> delivered -> done|failed 한 방향뿐이다. 규칙이 자녀에게
 * state/deliveredAt/doneAt/error 만 갱신하도록 제한하므로 type·payload 는 불변이다.
 */
data class CommandDoc(
    val id: String = "",
    val type: String = "",
    val payload: Map<String, String> = emptyMap(),
    val state: String = "",
    val createdAt: Long = 0L,
    val deliveredAt: Long = 0L,
    val doneAt: Long = 0L,
    val error: String = "",
)

object CommandType {
    const val SET_RINGER = "set_ringer"
    const val FIND_PHONE = "find_phone"
    const val STOP_FIND = "stop_find"
    /** 예약 규칙이 바뀌었으니 다시 읽어 알람을 새로 걸라는 신호. */
    const val SYNC_RULES = "sync_rules"
}

object CommandState {
    const val PENDING = "pending"
    const val DELIVERED = "delivered"
    const val DONE = "done"
    const val FAILED = "failed"
}

/**
 * families/{familyId}/schedules/{id} — 시간대 규칙 하나(설계서 §4.3).
 *
 * 필드 이름·의미는 [com.kidcare.family.logic.ScheduleRule] 과 같다 — 저 클래스는
 * 순수 판정 로직(ScheduleResolver)이 쓰는 안드로이드 비의존 모델이고, 이 클래스는
 * 그 문서 표현이다. 굳이 하나로 합치지 않는 이유: ScheduleRule 은 [logic] 패키지
 * 소속이라 안드로이드·Firestore 를 몰라야 하는데(JVM 단위 테스트 대상), 이 클래스는
 * Firestore 의 toObject() 를 쓰려면 모든 필드에 기본값이 있는 빈 생성자가 필요하고
 * [days] 도 Set 이 아니라 List 여야 한다(Firestore 는 배열을 List 로 매핑한다).
 *
 * [id] 는 Firestore 문서 ID 라 문서 본문에는 없다. 읽어올 때 채운다
 * ([CommandDoc.id] 와 같은 이유).
 */
data class ScheduleDoc(
    val id: String = "",
    val days: List<Int> = emptyList(),
    val startMinute: Int = 0,
    val endMinute: Int = 0,
    val mode: String = "",
    val enabled: Boolean = true,
    val priority: Int = 0,
)

/**
 * families/{familyId}/settings/ringer — "아이가 되돌리면 다시 바꾸기" 스위치(설계서 §4.4).
 *
 * settings 컬렉션 자체는 Task 1 이 규칙과 함께 추가했다(가족 단위 설정을 담는
 * 자리). ringer 문서 하나만 지금은 쓴다.
 */
data class RingerSettingsDoc(
    val lockEnabled: Boolean = false,
)
