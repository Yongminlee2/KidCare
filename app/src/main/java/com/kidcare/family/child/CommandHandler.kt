package com.kidcare.family.child

import android.content.Context
import android.util.Log
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.model.CommandDoc
import com.kidcare.family.core.model.CommandType
import kotlinx.coroutines.CancellationException

/**
 * 받은 명령 하나를 실행하고 결과를 되돌려 적는다.
 *
 * 같은 명령을 두 번 실행하지 않도록 최근 처리한 ID 를 기억한다. Firestore 스냅샷은
 * 캐시분과 서버분이 잇달아 오거나 재연결 시 다시 흘러올 수 있어서, 이게 없으면
 * 폰찾기 벨이 두 번 울린다(계약은 [CommandRepository.observePending] 참고).
 *
 * [context] 는 [RingerController]·[RingerStateStore] 같은 안드로이드 API 를 쓰는
 * 컨트롤러를 만드는 데 쓴다(Task 4). Task 5~6 이 같은 이유로 컨트롤러를 더 붙일 수 있다.
 */
class CommandHandler(private val context: Context) {

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
                    if (!ringer.apply(mode)) {
                        // 권한이 없거나(무음·진동은 방해 금지 접근이 필요) 모드 값이
                        // 이상하면 조용히 무시하지 않고 실패로 남긴다 — 부모가 눌렀는데
                        // 왜 안 바뀌는지 알 길이 없어지는 상황(Task 4 설계 의도)을 막는다.
                        CommandRepository.markFailed(familyId, childUid, command.id, "ringer_denied")
                        return
                    }
                    // 즉시 변경은 다음 예약 경계까지만 유효하다(설계서 §4.3). "until"은
                    // 지금은 부모 폰이 보낸 값을 그대로 쓰는 임시값이다 — Task 8 이 이걸
                    // 자녀 폰이 직접 계산한 경계로 바꾼다. 두 폰의 시계·시간대가 다를 수
                    // 있어서, 규칙을 실제로 강제하는(=지금 이) 폰이 끝나는 시각도 직접
                    // 정해야 하기 때문이다.
                    state.overrideMode = mode
                    state.overrideUntil = command.payload["until"]?.toLongOrNull() ?: 0L
                }
                CommandType.FIND_PHONE -> FindPhoneController.start(context)
                CommandType.STOP_FIND -> FindPhoneController.stop(context)
                CommandType.SYNC_RULES -> Log.i(TAG, "SYNC_RULES 수신 (Task 8 에서 구현)")
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

    private companion object {
        const val TAG = "CommandHandler"
        const val MAX_REMEMBERED = 100
    }
}
