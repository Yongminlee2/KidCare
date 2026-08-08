package com.kidcare.family.child

import android.content.Context
import android.util.Log
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.ScheduleRepository
import com.kidcare.family.core.model.CommandDoc
import com.kidcare.family.core.model.CommandType
import com.kidcare.family.core.toRule
import com.kidcare.family.logic.ScheduleResolver
import kotlinx.coroutines.CancellationException
import java.time.ZoneId

/**
 * 받은 명령 하나를 실행하고 결과를 되돌려 적는다.
 *
 * 같은 명령을 두 번 실행하지 않도록 최근 처리한 ID 를 기억한다. Firestore 스냅샷은
 * 캐시분과 서버분이 잇달아 오거나 재연결 시 다시 흘러올 수 있어서, 이게 없으면
 * 폰찾기 벨이 두 번 울린다(계약은 [CommandRepository.observePending] 참고).
 *
 * [context] 는 [RingerController]·[RingerStateStore] 같은 안드로이드 API 를 쓰는
 * 컨트롤러를 만드는 데 쓴다(Task 4). Task 5~6 이 같은 이유로 컨트롤러를 더 붙일 수 있다.
 *
 * [onLocateNow] 는 "지금 위치와 오늘 경로를 올려라"를 실제로 수행하는 곳
 * ([TrackingService.uploadNow])이다. 이 클래스가 직접 하지 않는 이유: 올릴 재료
 * (오늘 점 버퍼, 마지막 fix)가 전부 그 서비스 안에 있다. 여기서 서비스를 붙들면
 * 죽은 서비스 참조를 들고 있게 되고, 반대로 재료를 여기로 옮기면 위치 수집과
 * 명령 실행이 한 클래스에 뒤섞인다.
 *
 * [placeWatcher] 를 새로 만들지 않고 **서비스가 쓰는 그 인스턴스를 받는** 이유도
 * 같다(5단계 Task 3). 읽어 둔 장소 목록이 그 인스턴스 안에 있어서, 여기서 따로 하나
 * 만들어 refresh 하면 OS 지오펜스만 새것이 되고 위치 점마다 도는 판정은 옛 목록을
 * 계속 쓴다 — 부모가 지운 장소의 도착 알림이 그대로 올라온다.
 */
class CommandHandler(
    private val context: Context,
    private val onLocateNow: suspend (familyId: String, childUid: String) -> Unit,
    private val placeWatcher: PlaceWatcher,
) {

    private val handled = object : LinkedHashSet<String>() {
        override fun add(element: String): Boolean {
            val added = super.add(element)
            while (size > MAX_REMEMBERED) remove(first())
            return added
        }
    }

    // SET_RINGER 가 쓰는 두 협력자. 명령마다 새로 만들지 않고 필드로 두는 이유는
    // RingerStateStore 가 SharedPreferences 를 감싸므로 매번 열고 닫을 필요가 없어서다.
    private val ringer = RingerController(context)
    private val state = RingerStateStore(context)

    // SYNC_RULES 가 쓴다(Task 8). ScheduleApplier 는 상태가 없으므로(협력자 두 개를
    // 그때그때 새로 만들 뿐) 매번 새로 만들어도 비용이 크지 않다 — 그래도 다른
    // 협력자들과 통일해 필드로 둔다.
    private val scheduleApplier = ScheduleApplier(context)

    suspend fun handle(familyId: String, childUid: String, command: CommandDoc) {
        if (!handled.add(command.id)) {
            Log.d(TAG, "이미 처리한 명령이라 건너뛴다: ${command.id}")
            return
        }

        // markDelivered 가 실제로(예외 없이) 성공해야만 아래에서 명령을 실행한다.
        //
        // 계획서 초안은 이 호출을 runCatching 으로 감싸 실패를 삼키고 그냥
        // 실행으로 넘어갔는데, Task 1 이 굳힌 전이 규칙(pending->delivered|failed,
        // delivered->done|failed, 종료 상태 이후 불가) 아래에서는 그게 사고로
        // 이어진다: 문서가 여전히 pending 인 채로 명령이 실행되고, 뒤이은
        // markDone 이 규칙상 pending->done 을 거부해 PERMISSION_DENIED 로 튕긴다.
        // 그 예외를 "명령 자체가 실패했다"로 잘못 해석해 markFailed 를 부르면
        // (pending->failed 는 허용되므로 이건 성공한다) 실제로는 실행된 명령이
        // "실패"로 보고된다 — 부모 화면에 거짓 실패가 뜬다. 게다가 문서가
        // pending 그대로 남은 채 프로세스가 재시작하면 observePending 이 이
        // 명령을 다시 통째로 넘겨줘 같은 명령(폰찾기 벨 등)이 두 번 실행될 수 있다.
        //
        // 그래서 delivered 표시가 실패하면 아무것도 실행하지 않고 여기서 멈춘다.
        // 문서는 pending 그대로 남고, CommandTransport.observePending 은 다음
        // 스냅샷(재연결 포함)에 같은 명령을 다시 통째로 넘겨준다 — 그때 다시
        // 시도된다. 여기서 자체 재시도 루프(대기 후 재호출)를 돌리지 않기로 했다:
        // 재전달 자체가 이미 관찰 계층의 계약이라(재연결마다 pending 문서 전체를
        // 다시 훑어 콜백) 같은 일을 이 함수 안에서 또 하면 중복일 뿐이고, 오프라인이
        // 길어질 때 이 코루틴을 얼마나 오래 붙들고 있을지 정할 근거도 마땅치 않다.
        // 실패 시 handled 에서 이 ID 를 지우는 이유: 위에서 이미 add 를 해 뒀으므로,
        // 지우지 않으면 다음 재전달이 "이미 처리한 명령"으로 걸러져 영영 재시도되지
        // 못한다.
        try {
            CommandRepository.markDelivered(familyId, childUid, command.id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "delivered 표시 실패 — 명령을 실행하지 않고 다음 재전달을 기다린다: ${command.id}", e)
            handled.remove(command.id)
            return
        }

        try {
            when (command.type) {
                CommandType.SET_RINGER -> {
                    val mode = command.payload["mode"].orEmpty()
                    // 즉시 변경은 다음 예약 경계까지만 유효하다(설계서 §4.3). "until"은
                    // 부모 폰이 보낸 값이 아니라 지금부터 자녀 폰이 직접 계산한다 — 두
                    // 폰의 시계·시간대가 다를 수 있고, 이 값을 실제로 강제하는(=이 즉시
                    // 변경을 끝내는) 쪽은 자녀 폰이므로 그 경계도 자녀 폰이 정해야 한다.
                    //
                    // 경계 계산을 소리 모드 변경 **앞**으로 옮긴 이유(Task 10 리뷰):
                    // 이 계산은 Firestore 를 한 번 다녀오는 suspend 함수다. 예전에는
                    //     state.overrideMode = mode          // 즉시
                    //     state.overrideUntil = 계산결과      // 왕복 뒤
                    // 순서라, 그 왕복이 도는 동안 저장소에 "새 모드 + 지나간 옛 해제
                    // 시각"이 남아 있었다. 그 사이에 예약 경계 알람이 자기 IO 코루틴에서
                    // 깨어나면(ScheduleAlarmReceiver → ScheduleApplier.applyNow →
                    // RingerController.desiredMode) 그 조합을 "만료된 즉시 변경"으로 읽어
                    // 방금 만든 변경을 지우고 예약 모드를 다시 씌운다 — markDone 이
                    // 부모에게 이미 "완료"라고 말한 뒤에.
                    //
                    // 이제 왕복이 먼저 끝나고, 모드와 해제 시각이 setOverride 한 번으로
                    // 함께 보이게 된다(RingerStateStore.setOverride 주석). 두 값이 따로
                    // 보이는 순간 자체가 없어진 것이라, 그 사이에 경계 알람이 아무리
                    // 여러 번 깨어나도 옛 상태 아니면 새 상태 둘 중 하나만 본다.
                    val until = nextRuleBoundaryMillis(familyId)
                    if (!ringer.apply(mode)) {
                        // 권한이 없거나(무음·진동은 방해 금지 접근이 필요) 모드 값이
                        // 이상하면 조용히 무시하지 않고 실패로 남긴다 — 부모가 눌렀는데
                        // 왜 안 바뀌는지 알 길이 없어지는 상황(Task 4 설계 의도)을 막는다.
                        // 여기서 돌아가면 저장소는 손도 대지 않은 상태 그대로다.
                        CommandRepository.markFailed(familyId, childUid, command.id, "ringer_denied")
                        return
                    }
                    state.setOverride(mode, until)
                }
                CommandType.FIND_PHONE -> FindPhoneController.start(context)
                CommandType.STOP_FIND -> FindPhoneController.stop(context)
                // 규칙이 바뀌었으니 다시 읽어 알람을 새로 건다(Task 8). refresh() 안에서
                // 이미 네트워크 실패를 잡아 재시도 알람으로 물러나므로, 여기서 실패해도
                // (아래 catch 로 내려가) 예약이 완전히 멈추지는 않는다.
                //
                // 같은 명령이 장소도 다시 읽는다(5단계 Task 3). 부모 화면은 예약과 장소
                // 양쪽에서 이 하나의 신호를 보내고, 자녀 폰은 둘 다 다시 읽는다 —
                // 명령 종류를 나누면 부모 쪽에서 어느 쪽을 보낼지 고르는 갈래가 하나
                // 늘고, 그 갈래를 잘못 고르면 조용히 옛 상태로 돈다. 장소 쪽 실패는
                // 예약까지 같이 죽이지 않도록 순서를 예약 뒤로 둔다.
                CommandType.SYNC_RULES -> {
                    scheduleApplier.refresh(familyId)
                    placeWatcher.refresh(familyId)
                }
                // "지금 위치와 오늘 경로를 올려라". 무료 한도 때문에 자녀 폰은 더 이상
                // 주기적으로 아무것도 올리지 않으므로(docs/known-issues.md 12번), 부모의
                // 이 물음이 상태·경로 문서가 쓰이는 주된 순간이다. 아직 위치를 못 잡았으면
                // 아래 catch 가 그 사유(locate_no_fix)를 명령 문서에 적어 부모에게 알린다 —
                // 조용히 done 으로 끝내면 부모는 지도의 옛 위치를 방금 확인한 것으로 읽는다.
                CommandType.LOCATE_NOW -> onLocateNow(familyId, childUid)
                // 부모의 한마디를 띄운다(5단계 Task 5). **여기서 done 을 적지 않고
                // return 하는 것이 이 명령의 전부다** — done 은 아이가 '확인했어요'를
                // 눌렀다는 뜻이고 그걸 적는 쪽은 MessageActivity 다. 아래 markDone 까지
                // 흘러가면 아이가 화면을 보기도 전에 부모 화면이 '읽음'이 된다.
                //
                // 그래서 이 명령만 delivered 에서 오래 머무를 수 있다. 그건 고장이 아니라
                // "전해졌지만 아직 안 읽음"이고, 부모 화면이 그렇게 말한다
                // (CommandType.MESSAGE 주석 참고).
                CommandType.MESSAGE -> {
                    val text = command.payload[CommandType.PAYLOAD_TEXT].orEmpty().trim()
                    if (text.isEmpty()) {
                        // 보내는 쪽이 빈 문장을 막지만(ControlFragment), 빈 화면을 띄우고
                        // 아이에게 확인을 누르라고 하느니 실패로 끝내는 편이 정직하다.
                        CommandRepository.markFailed(familyId, childUid, command.id, "message_empty")
                        return
                    }
                    if (!MessageActivity.show(context, familyId, childUid, command.id, text)) {
                        CommandRepository.markFailed(
                            familyId, childUid, command.id, CommandType.ERROR_NOTIFICATION_OFF,
                        )
                    }
                    return
                }
                else -> {
                    // 모르는 종류를 조용히 무시하면 보호자 화면에 "전달 중"으로
                    // 영원히 멈춰 보인다. delivered 는 이미 성공했으니
                    // delivered->failed 로 명확히 끝낸다.
                    Log.w(TAG, "모르는 명령 종류: ${command.type}")
                    CommandRepository.markFailed(familyId, childUid, command.id, "unknown type")
                    return
                }
            }
            CommandRepository.markDone(familyId, childUid, command.id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // 이 시점의 실패는 markDelivered 가 이미 성공한 뒤라 문서는 최소
            // delivered 상태다 — pending->failed 든 delivered->failed 든 규칙이
            // 허용하므로 markFailed 를 여기서 불러도 안전하다.
            Log.w(TAG, "명령 실행 실패: ${command.type}", e)
            try {
                CommandRepository.markFailed(familyId, childUid, command.id, e.message.orEmpty())
            } catch (e2: CancellationException) {
                throw e2
            } catch (e2: Exception) {
                // failed 표시마저 실패하면 문서는 delivered 로 멈춘 채 남는다.
                // observePending 은 pending 문서만 훑으므로 이 명령이 다시
                // 실행되는 일은 없다 — 다만 부모 화면에는 "전달 중"으로 멈춰
                // 보일 수 있다는 점은 알려 둔다.
                Log.w(TAG, "failed 표시 실패 — 문서가 delivered 로 멈춰 있을 수 있다: ${command.id}", e2)
            }
        }
    }

    /**
     * SET_RINGER 의 즉시 변경이 풀리는 시각(설계서 §4.3). 지금 규칙을 읽어 다음 경계를
     * 구한다 — 규칙이 하나도 없으면(활성·비활성 통틀어) [ScheduleResolver.resolveAt] 의
     * nextBoundaryMillis 가 null 이고, 그걸 0(해제 시각 없음, [RingerStateStore.overrideUntil]
     * 문서 참고)으로 바꿔 돌려준다.
     *
     * 규칙을 못 읽으면(오프라인 등)도 0 으로 물러난다: 즉시 변경이 무기한으로 남을 뿐이고,
     * 그 뒤 SYNC_RULES 나 재부팅·시각변경으로 [ScheduleApplier.refresh] 가 다시 돌면
     * (state.ruleMode 가 갱신되고) [RingerController.desiredMode] 가 다시 규칙을 반영한다 —
     * 명령 자체를 실패로 되돌리는 것보다, 즉시 변경만은 확실히 적용하고 경계 계산을
     * 나중으로 미루는 쪽이 부모의 의도("지금 당장 이 모드로")에 더 가깝다.
     */
    private suspend fun nextRuleBoundaryMillis(familyId: String): Long = try {
        val rules = ScheduleRepository.fetchSchedules(familyId).map { it.toRule() }
        ScheduleResolver.resolveAt(rules, System.currentTimeMillis(), ZoneId.systemDefault())
            .nextBoundaryMillis ?: 0L
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Log.w(TAG, "예약 규칙을 못 읽어 즉시 변경 해제 시각을 못 정함 — 무기한으로 둔다", e)
        0L
    }

    private companion object {
        const val TAG = "CommandHandler"
        const val MAX_REMEMBERED = 100
    }
}
