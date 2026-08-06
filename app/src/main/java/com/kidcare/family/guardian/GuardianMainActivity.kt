package com.kidcare.family.guardian

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.R

/**
 * 보호자 메인 컨테이너. 지금은 지도 하나뿐이다.
 * 4단계에서 하단 탭(지도·관리·예약·알림)이 붙는다.
 */
class GuardianMainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_guardian_main)

        if (savedInstanceState == null) {
            supportFragmentManager.beginTransaction()
                .replace(R.id.fragment_container, MapTimelineFragment())
                .commit()
        }
    }
}
