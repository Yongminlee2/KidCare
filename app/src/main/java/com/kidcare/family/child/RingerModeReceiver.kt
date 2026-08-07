package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * 아이가 소리 모드를 바꾸면 되돌린다.
 *
 * 3초를 기다렸다 되돌리는 이유(설계서 §4.4): 즉시 되돌리면 아이 눈에는 버튼이
 * 안 먹는 것처럼 보이고 폰이 고장난 줄 안다. 잠깐 바뀌었다가 돌아가면
 * "부모가 정해둔 것"이라는 게 전달된다.
 *
 * 서비스가 코드로 등록한다 — 매니페스트에 정적 등록하면 앱이 안 떠 있을 때도
 * 깨어나 되돌리려 들어 배터리만 먹는다.
 *
 * 무한 루프가 안 생기는 이유: apply() 로 모드를 바꾸는 것 자체가 다시
 * RINGER_MODE_CHANGED_ACTION 을 발생시켜 onReceive 가 한 번 더 돈다. 하지만
 * 그때는 currentMode() 가 이미 desired 와 같으므로 두 번째 줄에서 바로
 * 돌아간다 — 여기가 루프를 끊는 지점이다.
 */
class RingerModeReceiver(
    private val controller: RingerController,
    private val state: RingerStateStore,
) : BroadcastReceiver() {

    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AudioManager.RINGER_MODE_CHANGED_ACTION) return
        if (!state.lockEnabled) return

        val desired = controller.desiredMode(state) ?: return
        if (controller.currentMode() == desired) return

        // 3초 안에 두 번 바뀌면(아이가 연달아 버튼을 누르는 경우) 먼저 걸어 둔
        // 예약을 취소하고 다시 건다 — 쌓아 두면 먼저 것이 나중에 터져 방금
        // 되돌린 모드를 또 덮어써 버린다.
        pending?.let { handler.removeCallbacks(it) }
        val task = Runnable {
            // 3초 사이에 상황이 바뀌었을 수 있으니(잠금이 꺼졌거나, 즉시 변경이
            // 만료됐거나, 그새 원하는 모드로 이미 돌아와 있거나) 다시 확인한다.
            val stillDesired = controller.desiredMode(state) ?: return@Runnable
            if (controller.currentMode() == stillDesired) return@Runnable
            if (controller.apply(stillDesired)) {
                Log.i(TAG, "아이가 바꾼 모드를 $stillDesired 로 되돌렸다")
            } else {
                // apply() 자체가 실패 사유(권한 없음/모드 값 이상)를 이미 로그로
                // 남기지만, 그 로그만 보면 "무슨 apply 호출이 실패했나"가
                // 안 보인다. 되돌리기 경로에서 실패했다는 걸 여기서 한 번 더
                // 남겨야, 부모가 "잠금을 켰는데 왜 안 먹히나" 물었을 때 사람이
                // 로그에서 원인(방해 금지 접근 취소 등)을 바로 찾을 수 있다.
                Log.w(TAG, "되돌리기 실패 — $stillDesired 로 못 바꿨다(권한 취소 등, 위 로그 참고)")
            }
        }
        pending = task
        handler.postDelayed(task, REVERT_DELAY_MILLIS)
    }

    /** 서비스가 죽을 때 부른다 — 안 부르면 죽은 서비스가 만든 컨트롤러를 붙든 Runnable 이 나중에 터진다. */
    fun cancelPending() {
        pending?.let { handler.removeCallbacks(it) }
        pending = null
    }

    private companion object {
        const val TAG = "RingerModeReceiver"
        const val REVERT_DELAY_MILLIS = 3000L
    }
}
