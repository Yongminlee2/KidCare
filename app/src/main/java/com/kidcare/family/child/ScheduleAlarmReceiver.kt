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

        val pendingResult = goAsync()
        val appContext = context.applicationContext
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
