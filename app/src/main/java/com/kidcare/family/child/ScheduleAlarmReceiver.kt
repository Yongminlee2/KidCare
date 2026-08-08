package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * 예약 경계 알람과, 그 경계 계산을 무효로 만드는 세 가지 시스템 신호를 받아
 * [ScheduleApplier] 를 다시 돌린다.
 *
 * 넷을 한 리시버에 모은 이유: 넷 다 처방이 같다("규칙을 다시 읽고 지금부터 다시
 * 계산해 걸어라"). 특히 재부팅은 절대 빠뜨리면 안 된다 — **AlarmManager 의 예약은
 * 재부팅으로 통째로 사라진다.** 여기서 다시 걸지 않으면 폰을 껐다 켠 날부터
 * 예약이 아무 로그도 남기지 않고 조용히 멈춘다. 시각·시간대 변경도 마찬가지다:
 * 이미 걸어 둔 경계 시각(절대 밀리초)은 시계가 바뀌는 순간 더 이상 "그 규칙이
 * 뜻하던 시각"이 아니게 된다.
 *
 * [android.content.BroadcastReceiver.goAsync] 를 쓰는 이유: [ScheduleApplier.refresh]
 * 는 Firestore 읽기라 즉시 끝나지 않는데 onReceive 는 짧게 끝나야 한다(길어지면
 * 시스템이 ANR 로 본다). goAsync() 로 받은 PendingResult 를 코루틴이 끝난 뒤 반드시
 * finish() 해야 시스템이 이 리시버를 "아직 처리 중"으로 오래 붙들지 않는다.
 */
class ScheduleAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val store = RoleStore(context)
        val familyId = store.familyId
        if (store.role != Role.CHILD || familyId == null) {
            // 보호자 폰이거나 아직 페어링 전이면 강제할 규칙 자체가 없다. BootReceiver
            // 와 같은 판단 기준이다.
            return
        }

        Log.i(TAG, "예약 재계산 트리거 수신: action=${intent.action}")

        val appContext = context.applicationContext

        // 원격 알람(5단계 Task 6)도 이 셋에 똑같이 무너진다. 재부팅은 AlarmManager 예약을
        // 통째로 지우고, 시각·시간대가 바뀌면 걸어 둔 절대 밀리초는 더 이상 부모가 고른
        // 그 "07:00"이 아니다. 처방만 서로 다르다 — 재부팅은 같은 순간을 그대로 다시 걸고,
        // 시계가 바뀐 것은 분 단위로 처음부터 다시 푼다(RemoteAlarmController 주석).
        //
        // 리시버를 새로 만들지 않고 여기 몇 줄을 더하는 이유는 BootReceiver 클래스 주석과
        // 같다: BOOT_COMPLETED 는 매니페스트에 등록된 리시버마다 따로 깨어나므로, 나누면
        // "부팅 뒤에 무엇을 다시 거는가"라는 하나의 판단이 파일 둘로 갈라진다 — 한쪽만
        // 고치고 잊는 사고가 이 저장소에서 이미 여러 번 났다. 예약 경계 알람 자신
        // (action 이 null 인 인텐트)은 이 when 의 어느 가지에도 안 걸린다.
        //
        // 아래 goAsync() 밖에서 동기로 하는 이유: SharedPreferences 읽기와 AlarmManager
        // 등록뿐이라 즉시 끝나고, 코루틴 안에 넣으면 Firestore 읽기가 실패해 그 블록이
        // 일찍 빠져나갈 때 알람 재등록까지 같이 못 하게 된다.
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> RemoteAlarmController.recoverIfNeeded(appContext)
            Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED ->
                RemoteAlarmController.reresolve(appContext)
        }

        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                ScheduleApplier(appContext).refresh(familyId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // ScheduleApplier.refresh 자신이 이미 네트워크 실패를 잡아 재시도
                // 알람으로 물러나므로(내부 주석 참고), 여기까지 올라오는 예외는 그
                // 방어망 밖의 예상 못 한 오류다 — 조용히 삼키지 않고 남긴다.
                Log.w(TAG, "예약 재적용 실패", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        const val TAG = "ScheduleAlarmReceiver"
    }
}
