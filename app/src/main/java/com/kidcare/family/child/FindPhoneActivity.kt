package com.kidcare.family.child

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.databinding.ActivityFindPhoneBinding

/**
 * 알림을 눌러(전체화면 승인이 있으면 자동으로) 뜨는 화면. 문구 하나와 중지
 * 버튼 하나만 보여준다 — 아이가 당황하지 않게, 겁주지 않는 말투로.
 *
 * 소리·진동은 [FindPhoneController] 가 이미 울리고 있다 — 이 화면은 그걸
 * 끄는 손잡이일 뿐, 소리 자체를 시작하지 않는다. 그래서 이 화면이 전체화면
 * 승인 부족으로 아예 안 떠도(안드로이드 14+, FindPhoneController 주석 참고)
 * 벨소리 자체는 영향을 받지 않는다.
 */
class FindPhoneActivity : AppCompatActivity() {

    private lateinit var binding: ActivityFindPhoneBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()

        binding = ActivityFindPhoneBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.findPhoneStopButton.setOnClickListener {
            FindPhoneController.stop(this)
            finish()
        }
    }

    /**
     * 잠금화면 위에 뜨고 화면을 켠다. API 27(O_MR1)부터는 전용 API가 있다.
     * minSdk 가 26 이라 그 아래로는 API 26 한 버전만 남는데, 거기서는 옛
     * 윈도우 플래그로 같은 효과를 낸다.
     */
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        }
    }
}
