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
    /** 2부터 보호자·자녀 N:N 및 자녀별 설정 경로를 쓴다. 0은 기존 1:1 문서다. */
    val schemaVersion: Int = 0,
    /** 1:1 시절 가족 공용 설정을 처음 어느 자녀에게 옮겼는지 남기는 마이그레이션 기록. */
    val primaryChildUid: String = "",
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
    /** 가족 화면 정렬과 가입 전후 구분에 쓰는 가입 시각(UTC 밀리초). */
    val joinedAt: Long = 0L,
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
    /** 이 코드로 들어올 역할. "guardian" 또는 "child"다. 빈 값은 옛 자녀 코드다. */
    val role: String = "child",
    /** 코드를 만든 보호자 uid. 자체 서버로 옮겨도 감사 기록으로 유지할 필드다. */
    val createdByUid: String = "",
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

/**
 * children/{childUid}/trails/{dayKey} — **하루가 문서 하나다.**
 *
 * ## 왜 문서 하나인가
 *
 * 예전에는 위치 한 점마다 `points/{autoId}` 문서를 하나씩 만들고(하루 약 520개),
 * 그때마다 상태 문서도 함께 덮어썼다. 거기에 15분마다 도는 구간 재계산이
 * `segments/` 를 통째로 갈아끼웠다 — 가족 하나가 하루에 약 1,100번을 쓴다.
 * Spark 무료 한도는 **프로젝트 전체**에서 하루 2만 쓰기라, 1,000가족이면 55배
 * 초과다(docs/known-issues.md 12번). 문서를 하루 하나로 합치면 그 부분이
 * 520+ 에서 1 이 된다.
 *
 * 문서 ID 는 dayKey("2026-08-07", 자녀 폰 시간대 기준)다. 보호자 화면이 날짜를
 * 넘길 때마다 쿼리가 아니라 **문서 ID 로 곧장 한 건**을 읽으므로 복합 색인도
 * 필요 없다(옛 segments 는 dayKey+startAt 색인이 없어 타임라인이 영영 비었던
 * 사고가 있었다 — known-issues 실기기 검증 절).
 *
 * ## 왜 요약(segments)까지 같은 문서에 담나
 *
 * 구간 요약을 별도 컬렉션으로 두면 하루 20~30 문서를 지우고 다시 쓰게 되는데,
 * 그것만으로 하루 50쓰기가 되어 가족당 20쓰기 예산을 혼자 넘긴다. 같은 문서 안의
 * 배열이면 쓰기도 읽기도 1 이다.
 *
 * [points] 는 원시 점, [segments] 는 그것을 머무름·이동으로 묶은 요약이다. 둘 다
 * 자녀 폰이 계산해 넣는다 — 머무른 곳 이름(역지오코딩)은 자녀 폰만 매길 수 있고,
 * 보호자 폰이 하루치 점을 다시 묶으면 그 이름이 통째로 사라진다.
 *
 * [points] 개수 상한과 넘칠 때의 처리는 [com.kidcare.family.logic.TrailCodec] 참고.
 */
data class TrailDoc(
    val dayKey: String = "",
    val points: List<TrailPoint> = emptyList(),
    val segments: List<SegmentDoc> = emptyList(),
    /** 자녀 폰이 이 문서를 마지막으로 올린 시각(자녀 폰 시계). */
    val updatedAt: Long = 0L,
)

/**
 * [TrailDoc.points] 의 원소. 옛 `PointDoc` 을 대신한다.
 *
 * `battery` 를 뺐다: 옛 PointDoc 에 있었지만 읽는 곳이 한 군데도 없었고, 배열
 * 원소마다 필드 이름이 같이 저장되므로 안 쓰는 필드 하나가 하루 문서 크기를
 * 그대로 키운다. 배터리는 상태 문서([ChildStatusDoc.battery])에 있다.
 */
data class TrailPoint(
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val accuracy: Float = 0f,
    val speed: Float = 0f,
    val at: Long = 0L,
)

/**
 * 하루를 머무름·이동으로 요약한 한 토막. [TrailDoc.segments] 의 원소다.
 *
 * 예전에는 `children/{childUid}/segments/{autoId}` 문서였다. 하루치를 갈아끼울
 * 때마다 20~30번 지우고 20~30번 쓰는 구조라 무료 한도에서 가장 비싼 조각이었고,
 * 지금은 하루 문서([TrailDoc]) 안의 배열로 들어간다. 그래서 `dayKey` 필드도
 * 없앴다 — 어느 날인지는 담고 있는 문서의 ID 가 이미 말한다.
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

    /**
     * "지금 위치와 오늘 경로를 올려라."
     *
     * 무료 한도 때문에 자녀 폰은 이제 주기적으로 아무것도 올리지 않는다
     * (docs/known-issues.md 12번). 부모가 이 명령을 보낼 때와 하루 한 번 안전
     * 업로드, 그 두 순간에만 상태 문서와 그날의 trails 문서가 쓰인다.
     *
     * 자녀 폰이 아직 위치를 한 번도 못 잡았으면 [ERROR_NO_FIX] 로 실패한다 —
     * 올릴 위치가 없는데 "완료"라고 적으면 부모는 지도에 뜬 옛 위치를 방금 확인한
     * 것으로 읽는다.
     */
    const val LOCATE_NOW = "locate_now"

    /** [LOCATE_NOW] 가 위치를 못 잡았을 때 자녀 폰이 error 필드에 적는 코드. */
    const val ERROR_NO_FIX = "locate_no_fix"

    /**
     * "이 한마디를 아이 폰 화면에 띄워라"(5단계 Task 5). 본문은 [PAYLOAD_TEXT] 에 담는다.
     *
     * 5단계 계획서는 이 상수가 4단계에 이미 있다고 적었지만 실제로는 없었다 — 여기가
     * 처음이다. 값이 `"message"` 인 것은 계획서가 부르던 이름 그대로다.
     *
     * 다른 명령과 **결정적으로 다른 점**: 자녀 폰이 받자마자 done 으로 끝내지 않는다.
     * 여기서 done 은 "아이가 '확인했어요'를 눌렀다"는 뜻이고, 그게 부모 화면의 '읽음'이
     * 된다([com.kidcare.family.child.MessageActivity]). 그래서 이 명령은 delivered 에서
     * 몇 시간이고 머무를 수 있는데, 그 상태는 고장이 아니라 "전해졌지만 아직 안 읽음"
     * 이다. 부모 화면은 그것과 "애기폰이 응답하지 않아요"를 **다른 문장으로** 말해야
     * 한다 — 둘을 한 문장으로 뭉개면 부모가 아이 폰이 죽은 줄 안다
     * (guardian/ControlFragment.onCommandChanged).
     */
    const val MESSAGE = "message"

    /**
     * [MESSAGE] 본문이 담기는 페이로드 키.
     *
     * SET_RINGER 의 `"mode"` 는 보내는 쪽(guardian/ControlFragment)과 받는 쪽
     * (child/CommandHandler)이 각자 자기 파일에 문자열을 다시 적어 두는데, 그건 guardian
     * 이 child 를 import 할 수 없어서 생긴 모양이다(설계서 §3 모듈 경계). 반면 이
     * 오브젝트는 양쪽이 이미 함께 import 하는 자리라 한 번만 적는다 — 키 하나가 어긋나면
     * 아이 폰이 빈 문장을 받고, 그건 화면에 아무 표시도 없이 조용히 실패하는 모양이다.
     */
    const val PAYLOAD_TEXT = "text"

    /**
     * [MESSAGE] 를 아이 폰이 띄우지 **못했을** 때 error 에 적는 코드. 알림이 꺼져 있다는 뜻.
     *
     * 이 경우 조용히 done 으로 끝내면 부모는 아이가 읽었다고 읽는다. 아이 폰에서 실제로
     * 벌어진 일(아무것도 안 떴다)을 그대로 부모에게 옮기려고 실패 코드를 따로 둔다.
     */
    const val ERROR_NOTIFICATION_OFF = "message_notification_off"

    /**
     * "이 시각에 아이 폰에서 알람을 울려라"(5단계 Task 6).
     *
     * 계획서는 이 상수가 4단계에 이미 있다고 적었지만 [MESSAGE] 와 똑같이 실제로는
     * 없었다 — 여기가 처음이다. 값은 계획서가 부르던 이름 그대로다.
     *
     * ## 절대 시각(epoch)을 페이로드에 담지 않는다
     *
     * 담는 것은 [PAYLOAD_AT_MINUTE_OF_DAY](하루 안의 분)와 [PAYLOAD_LABEL] 둘뿐이고,
     * "오늘 그 시각, 이미 지났으면 내일"은 **자녀 폰이 푼다**
     * ([com.kidcare.family.child.RemoteAlarmController]). 두 폰은 시간대도 시계도 다를
     * 수 있고, 그 시각을 실제로 지키는 쪽은 자녀 폰이다 — 4단계에서 즉시 변경의 해제
     * 시각을 같은 이유로 자녀 폰으로 옮겼다([com.kidcare.family.child.CommandHandler]
     * 의 SET_RINGER 분기 주석).
     *
     * 이 명령은 [MESSAGE] 와 달리 자녀 폰이 곧바로 done 을 적는다. 여기서 done 은
     * "알람을 걸었다"는 뜻이지 "아이가 그 시각에 일어났다"가 아니다.
     */
    const val SET_ALARM = "set_alarm"

    /**
     * 걸어 둔 원격 알람을 지운다. 지금 울리고 있으면 함께 멈춘다.
     *
     * 걸린 알람이 없을 때 와도 조용히 지나가고 done 이 된다([STOP_FIND] 와 같은 규율) —
     * "취소할 게 없다"를 실패로 적으면 부모 화면에 빨간 문구가 뜨는데, 부모가 원한 상태
     * (알람 없음)는 이미 이뤄져 있다.
     */
    const val CANCEL_ALARM = "cancel_alarm"

    /**
     * [SET_ALARM] 이 울릴 시각. **하루 안의 분**(0~1439)을 열 자리 문자열로 담는다.
     *
     * 페이로드가 `Map<String,String>` 이라 숫자도 문자열로 간다([CommandDoc.payload]).
     * 받는 쪽은 `toIntOrNull()` 로 풀고 0..1439 밖이면 실패로 끝낸다 — 부모 화면은
     * `MaterialTimePicker` 로만 고르게 해서 그 범위를 벗어날 길이 없지만, 이 앱의 위협
     * 모델에는 아이 본인이 들어 있어 Firestore 를 직접 두드릴 수 있다(firestore.rules 주석).
     */
    const val PAYLOAD_AT_MINUTE_OF_DAY = "atMinuteOfDay"

    /**
     * [SET_ALARM] 에 붙는 짧은 이름("학원 가야 해"). 울릴 때 아이 폰 알림의 제목이 된다.
     *
     * 비어 있어도 된다 — 그때는 아이 폰이 기본 문구를 쓴다. 이름이 없다고 알람을 거절하면
     * 부모가 급할 때 한 손으로 못 건다.
     */
    const val PAYLOAD_LABEL = "label"

    /**
     * [SET_ALARM] 을 정확한 알람으로 걸 수 없을 때 자녀 폰이 적는 코드.
     *
     * 매니페스트에 `USE_EXACT_ALARM` 이 있어 정상적인 기기라면 나올 수 없다. 그래도
     * 부정확한 알람으로 조용히 물러나지 않고 **실패로 끝내는** 이유: 알람시계에서 "몇십 분
     * 늦게 울림"은 안 울린 것과 같고, 조용히 물러나면 부모는 아이가 깨워졌다고 믿는다.
     */
    const val ERROR_ALARM_EXACT_DENIED = "alarm_exact_denied"

    /** [PAYLOAD_AT_MINUTE_OF_DAY] 가 없거나 0..1439 밖일 때. 화면으로는 만들 수 없는 값이다. */
    const val ERROR_ALARM_BAD_TIME = "alarm_bad_time"
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
 * families/{familyId}/places/{id} — 부모가 정한 장소 하나(설계서 §4.6).
 *
 * 필드 이름·의미는 [com.kidcare.family.logic.Place] 와 같다. 두 클래스를 따로 두는
 * 이유는 [ScheduleDoc]/[com.kidcare.family.logic.ScheduleRule] 과 똑같다 — 저쪽은
 * 안드로이드·Firestore 를 몰라야 하는 순수 판정 모델이고 이쪽은 그 문서 표현이다.
 * 변환은 `core/PlaceRepository.kt` 의 `PlaceDoc.toPlace()` 한 곳에만 있다.
 *
 * [radiusMeters] 의 기본값이 0 인 것은 "안 정해졌다"는 뜻이고, 그런 장소는 지오펜스로
 * 걸지 않는다(`child/PlaceWatcher.registerGeofences`). 200 같은 그럴듯한 값을 기본으로
 * 넣으면 필드가 빠진 문서가 **부모가 정하지 않은 반경으로 조용히 동작한다** — 이 앱에서
 * 조용히 지어낸 값이 제일 나쁘다.
 *
 * 쓰기는 보호자만이다(firestore.rules 의 places 블록). 아이에게 쓰기를 열면 학교 반경을
 * 0 으로 만들어 도착 알림을 없앨 수 있다. 읽기는 아이도 필요하다 — 자기 폰의 지오펜스를
 * 걸려면 좌표와 반경을 알아야 한다.
 */
data class PlaceDoc(
    val id: String = "",
    val name: String = "",
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val radiusMeters: Double = 0.0,
    val notifyEnter: Boolean = true,
    val notifyExit: Boolean = true,
)

/**
 * families/{familyId}/events/{id} — 아이 폰이 만들고 부모가 읽는 사건 하나.
 *
 * ## [at] 은 반드시 Long 밀리초다. Firestore Timestamp 로 바꾸면 안 된다.
 *
 * firestore.rules 의 events create 규칙이 이 값을 `request.time.toMillis()` 와 직접
 * 비교한다(과거 24시간 ~ 미래 1시간). 타입을 `Timestamp` 로 바꾸면 그 비교가 절대
 * 성립하지 않아 **모든 이벤트 쓰기가 조용히 거부된다** — 부모 화면에는 그냥 사건이
 * 하나도 안 일어난 것으로 보인다. 5단계 Task 1 이 이 지뢰를 명시적으로 남겼다.
 *
 * ## [read] 는 만들 때 반드시 false 다
 *
 * 같은 규칙이 `request.resource.data.read == false` 를 강제한다. 아이가 이벤트를
 * 만들면서 미리 읽음 표시를 해 두면 부모의 '안 읽음' 목록에서 그대로 사라진다.
 * 기본값이 false 이므로 [EventRepository][com.kidcare.family.core.EventRepository] 는
 * 이 필드를 아예 건드리지 않는다.
 *
 * [childUid] 도 규칙이 `request.auth.uid` 와 대조한다 — 남의 이름으로 사건을 지어내지
 * 못하게 하는 검사라, 쓰는 쪽은 반드시 지금 로그인된 uid 를 그대로 넣어야 한다.
 *
 * [id] 는 Firestore 문서 ID 라 본문에는 없다. 읽어올 때 채운다([CommandDoc.id] 와 같다).
 */
data class EventDoc(
    val id: String = "",
    val type: String = "",
    val at: Long = 0L,
    val childUid: String = "",
    val placeName: String = "",
    val detail: String = "",
    val read: Boolean = false,
)

/**
 * [EventDoc.type] 값들.
 *
 * firestore.rules 는 이 목록을 **일부러 강제하지 않는다**(events 블록 주석 참고) —
 * 값 목록으로 잠그면 종류가 하나 늘 때마다 사람이 콘솔에 규칙을 다시 게시해야 하고,
 * 잊으면 그 종류만 조용히 죽는다. 그러니 이 목록이 곧 약속이고, 지키는 쪽은 앱 코드다.
 */
object EventType {
    const val PLACE_ENTER = "place_enter"
    const val PLACE_EXIT = "place_exit"

    // 아래 넷은 **아직 아무도 쓰지 않는다.** 만드는 쪽은 5단계 Task 7(상황 경고)이고,
    // 여기 미리 두는 이유는 읽는 쪽(알림 탭)이 이미 이 값들을 한국어 한 줄로 옮길 수
    // 있어야 하기 때문이다. 값 이름을 나중에 정하게 두면 만드는 쪽과 읽는 쪽이 다른
    // 문자열을 쓰게 되고, 그러면 이벤트는 멀쩡히 올라오는데 부모 화면에는 "새로운
    // 알림이 있어요"라는 뜻 없는 한 줄만 뜬다 — 조용히 고장 나는 모양이다.

    /** 배터리가 처음 15% 아래로 내려갔을 때. detail 에 남은 퍼센트를 적는다. */
    const val LOW_BATTERY = "low_battery"

    /** 위치·방해금지 같은 권한이 켜져 있다가 꺼졌을 때. detail 에 어떤 권한인지 적는다. */
    const val PERMISSION_OFF = "permission_off"

    /** 아이 폰이 한동안 아무 대답도 하지 않았을 때. */
    const val SIGNAL_LOST = "signal_lost"

    /** 부모가 보낸 명령이 아이 폰에서 실패했을 때. detail 에 이유를 적는다. */
    const val COMMAND_FAILED = "command_failed"
}

/**
 * families/{familyId}/settings/ringer — "아이가 되돌리면 다시 바꾸기" 스위치(설계서 §4.4).
 *
 * settings 컬렉션 자체는 Task 1 이 규칙과 함께 추가했다(가족 단위 설정을 담는
 * 자리). ringer 문서 하나만 지금은 쓴다.
 */
data class RingerSettingsDoc(
    val lockEnabled: Boolean = false,
)
