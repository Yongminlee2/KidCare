package com.kidcare.family.child

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.kidcare.family.core.HolidayCalendar
import com.kidcare.family.core.ScheduleRepository
import com.kidcare.family.core.model.ScheduleDoc
import com.kidcare.family.core.toRule
import com.kidcare.family.logic.ScheduleResolver
import com.kidcare.family.logic.ScheduleRule
import kotlinx.coroutines.CancellationException
import java.time.LocalDate
import java.time.ZoneId

/**
 * 예약 규칙을 실제로 적용한다(설계서 §4.3, Task 8).
 *
 * 하는 일은 [refresh] 한 번으로 요약된다: 규칙과 잠금 설정을 읽고, 지금 강제할
 * 모드를 계산해 적용하고, 다음 경계에 깨어날 알람을 다시 건다. [ScheduleAlarmReceiver]
 * 가 경계 알람·재부팅·시각변경마다 이 함수를 부른다.
 *
 * [applyNow] 를 [refresh] 와 분리한 이유: 규칙을 읽는 것(네트워크)과 그걸로 무엇을 할지
 * 정하는 것(순수 계산)을 나누면, 네트워크가 실패했을 때 그 실패를 [refresh] 안에서만
 * 다루면 되고(아래 주석), 나중에 규칙 편집 화면이 "방금 로컬에서 바꾼 규칙을 저장 전에
 * 미리 적용해 보기" 같은 걸 하려 할 때도 fetch 없이 바로 쓸 수 있다.
 */
class ScheduleApplier(private val context: Context) {

    private val ringerController = RingerController(context)
    private val state = RingerStateStore(context)

    /**
     * Firestore 에서 규칙·잠금 설정을 읽어 적용한다.
     *
     * 읽기가 실패하면(오프라인 등) [state.ruleMode] 는 지난 [refresh] 가 남긴 값
     * 그대로 유지된다 — [RingerController.desiredMode] 와 되돌리기(RingerModeReceiver)는
     * 계속 그 값을 강제하므로 "마지막으로 알려진 올바른 모드"는 오프라인 중에도 안
     * 끊긴다. 다만 지금 이 순간의 알람은 이미 소모됐고(AlarmManager 는 한 번 울리면
     * 그 예약이 사라진다) 다음 경계를 다시 계산할 재료(규칙 목록)가 없으므로, 그대로
     * 두면 알람이 다시 걸릴 때까지(재부팅·시각변경·SYNC_RULES) 예약이 멈춘 채로
     * 남는다. 그래서 짧은 간격으로 재시도 알람을 대신 건다.
     */
    suspend fun refresh(familyId: String, childUid: String) {
        val schedules: List<ScheduleDoc>
        try {
            schedules = ScheduleRepository.fetchSchedules(familyId, childUid)
            val settings = ScheduleRepository.fetchRingerSettings(familyId, childUid)
            state.lockEnabled = settings.lockEnabled
            state.holidayOff = settings.holidayOff
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(
                TAG,
                "예약 규칙을 못 읽어 새로 적용하지 못했다 — 마지막으로 적용된 모드를 유지하고 " +
                    "${RETRY_DELAY_MILLIS}ms 뒤 재시도한다",
                e,
            )
            scheduleBoundaryAlarm(System.currentTimeMillis() + RETRY_DELAY_MILLIS)
            return
        }

        applyNow(schedules.map { it.toRule() })
    }

    /**
     * 이미 갖고 있는 규칙 목록으로 지금을 판정하고 적용한다(네트워크 없음, 순수 계산 +
     * 부수효과). [ScheduleResolver.resolveAt] 이 돌려주는 모드와 다음 경계를 그대로 쓴다.
     */
    fun applyNow(rules: List<ScheduleRule>) {
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val resolution = ScheduleResolver.resolveAt(rules, now, zone, holidays(zone))

        // 규칙이 지금 강제하는 모드를 캐시한다 — RingerController.desiredMode 가 즉시
        // 변경이 없을 때 이 값을 읽는다(RingerStateStore.ruleMode 주석 참고).
        state.ruleMode = resolution.mode

        val current = ringerController.currentMode()
        val rememberedOverride = state.overrideMode
        // 잠금이 꺼진 동안 아이가 폰에서 직접 모드를 바꿨다면 그 선택을 존중한다.
        // 즉시 변경값은 다음 예약 경계까지 로컬에 남는데, 예전에는 앱/서비스가 다시
        // 시작될 때 이 오래된 값을 무조건 재적용해 벨소리를 다시 무음으로 만들었다.
        // 현재 모드가 기억값과 다르면 앱 밖에서 바뀐 것이므로 즉시 변경을 끝낸다.
        // 잠금이 켜져 있으면 기존 의미대로 부모가 정한 모드를 계속 강제한다.
        if (!state.lockEnabled && rememberedOverride != null && current != rememberedOverride) {
            state.clearOverride()
            Log.i(TAG, "잠금이 꺼진 동안 바뀐 현재 소리 모드를 유지한다: $current")
        }

        val desired = ringerController.desiredMode(state, now)
        if (desired != null && current != desired) {
            ringerController.apply(desired)
        }

        scheduleNextBoundary(resolution.nextBoundaryMillis)
    }

    /**
     * 공휴일 집합. 스위치가 꺼져 있으면 빈 집합이라 예전과 똑같이 요일만 본다.
     *
     * 앞뒤 해까지 함께 받는 이유는 [HolidayCalendar.around] 주석 참고 — 다음 경계를
     * 찾을 때 열흘 앞까지 훑으므로 연말에는 다음 해 공휴일이 필요하다.
     */
    private fun holidays(zone: ZoneId): Set<LocalDate> =
        if (state.holidayOff) HolidayCalendar.around(LocalDate.now(zone)) else emptySet()

    /**
     * [nextBoundaryMillis] 가 null 이면(=활성·비활성을 통틀어 규칙이 하나도 없으면)
     * 예약할 다음 경계 자체가 없다는 뜻이라 알람을 취소한다. 걸려 있지 않은 알람을
     * cancel() 해도 조용히 아무 일도 안 하므로 "취소할 게 있었는지" 미리 따질 필요는
     * 없다.
     */
    private fun scheduleNextBoundary(nextBoundaryMillis: Long?) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        if (alarmManager == null) {
            Log.w(TAG, "AlarmManager 서비스를 못 얻어 예약을 걸지 못했다")
            return
        }
        if (nextBoundaryMillis == null) {
            alarmManager.cancel(alarmPendingIntent())
            Log.i(TAG, "적용 중인 예약 규칙이 없어 알람을 걸지 않는다(기존 알람은 취소)")
            return
        }
        scheduleBoundaryAlarm(nextBoundaryMillis, alarmManager)
    }

    /**
     * API 31+ 는 정확한 알람에 SCHEDULE_EXACT_ALARM 또는 USE_EXACT_ALARM 권한이 필요하다.
     * 이 앱은 매니페스트에 USE_EXACT_ALARM 을 선언해 뒀고(사용자가 지정한 시각에 소리를
     * 바꾸는 용도라 승인 절차 없이 부여된다) 정상적인 기기라면 [AlarmManager.canScheduleExactAlarms]
     * 가 항상 true 를 준다. 그래도 미리 확인하는 이유는 그 전제가 깨지는 경우(제조사
     * 배터리 최적화 정책, OS 버그, 미래의 정책 변경 등)를 방어하기 위해서다 — 그때
     * 조용히 부정확한 알람으로 물러나면 "예약이 가끔 몇 분 늦게 반영된다"는, 재현이
     * 안 돼서 진단이 거의 불가능한 증상이 된다. 그래서 물러날 때는 반드시 로그를 남긴다.
     */
    private fun scheduleBoundaryAlarm(triggerAtMillis: Long, alarmManager: AlarmManager? = null) {
        val manager = alarmManager ?: context.getSystemService(AlarmManager::class.java) ?: run {
            Log.w(TAG, "AlarmManager 서비스를 못 얻어 예약을 걸지 못했다")
            return
        }
        val pendingIntent = alarmPendingIntent()
        val canScheduleExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        if (canScheduleExact) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        } else {
            Log.w(
                TAG,
                "USE_EXACT_ALARM 권한이 없어(canScheduleExactAlarms=false) 정확한 알람을 못 건다 — " +
                    "setAndAllowWhileIdle 로 물러난다. 경계 시각이 늦게 반영될 수 있다: triggerAt=$triggerAtMillis",
            )
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }

    /**
     * 고정 요청 코드로 만든다 — 매번 같은 PendingIntent 를 얻어야 재예약이 새 알람을
     * 쌓지 않고 기존 것을 교체한다(FLAG_UPDATE_CURRENT). 이 알람은 데이터를 채워
     * 넣지 않는 순수 신호라 FLAG_MUTABLE 이 필요 없다 — FLAG_IMMUTABLE 이 맞다
     * (ActivityTransitionReceiver 의 PendingIntent 와 반대인 이유는 그쪽은 시스템이
     * fill-in 으로 extra 를 채워 넣지만 이 알람은 그럴 필요가 없어서다).
     */
    private fun alarmPendingIntent(): PendingIntent {
        val intent = Intent(context, ScheduleAlarmReceiver::class.java)
        return PendingIntent.getBroadcast(
            context, REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private companion object {
        const val TAG = "ScheduleApplier"
        const val REQUEST_CODE = 4001
        const val RETRY_DELAY_MILLIS = 15 * 60 * 1000L
    }
}
