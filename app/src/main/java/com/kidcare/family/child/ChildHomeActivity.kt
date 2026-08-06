package com.kidcare.family.child

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.R
import com.kidcare.family.databinding.ActivityChildHomeBinding
import com.kidcare.family.onboarding.PermissionStep

/**
 * 아이가 보는 화면. 몰래 감시하지 않는다는 원칙에 따라
 * "지금 위치를 부모님과 공유 중"이라는 사실을 숨기지 않고 보여준다.
 *
 * 권한이 빠졌다고 여기서 PermissionActivity 로 다시 돌려보내지는 않는다 — 페어링이
 * 끝난 아이 폰은 재실행 시 RouterActivity 가 곧장 이 화면으로 보내므로(Task 4 설계),
 * 대신 상태 문구로만 정직하게 알려준다.
 *
 * Task 9 에서 여기서 TrackingService 를 시작한다.
 */
class ChildHomeActivity : AppCompatActivity() {

    private lateinit var binding: ActivityChildHomeBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityChildHomeBinding.inflate(layoutInflater)
        setContentView(binding.root)
    }

    override fun onResume() {
        super.onResume()
        val missing = PermissionStep.firstMissing(this)
        binding.childStatus.text = if (missing == null) {
            getString(R.string.child_sharing_on)
        } else {
            getString(R.string.child_permission_missing, getString(missing.titleRes))
        }
    }
}
