package com.kidcare.family.child

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.R
import com.kidcare.family.databinding.ActivityChildHomeBinding
import com.kidcare.family.onboarding.PermissionActivity
import com.kidcare.family.onboarding.PermissionStep

/**
 * 아이가 보는 화면. 몰래 감시하지 않는다는 원칙에 따라
 * "지금 위치를 부모님과 공유 중"이라는 사실을 숨기지 않고 보여준다.
 *
 * 페어링 직후, 권한을 다 받기 전에 앱이 죽었다 살아나는 일은 흔하다(전화, 화면 전환,
 * OEM의 백그라운드 강제 종료 등). RoleStore.isPaired 는 페어링이 끝난 순간 바로
 * true 가 되므로, 이런 경우 RouterActivity 는 곧장 이 화면으로 보낸다(Task 4 설계 —
 * 바꾸지 않음). 그래서 권한이 빠졌을 때 상태 문구만 보여주고 끝내면 아이가 고칠
 * 방법이 없는 채로 남는다 — 그래서 PermissionActivity 로 돌아갈 수 있는 버튼도
 * 함께 보여준다.
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
        if (missing == null) {
            TrackingService.start(this)
            binding.childStatus.text = getString(R.string.child_sharing_on)
            binding.goToPermissionButton.visibility = View.GONE
        } else {
            binding.childStatus.text =
                getString(R.string.child_permission_missing, getString(missing.titleRes))
            binding.goToPermissionButton.visibility = View.VISIBLE
            // 여기서 finish() 하지 않는다: 아이가 PermissionActivity 에서 뒤로가기로
            // 취소할 수도 있는데, 그때는 (finish() 했다면 텅 빈 태스크만 남아 앱 밖으로
            // 튕겨나가는 대신) 이 화면으로 그대로 돌아와야 하기 때문이다. 남은 권한을
            // 끝까지 다 받으면 PermissionActivity 가 CLEAR_TOP 으로 이 낡은 인스턴스를
            // 정리하고 새 화면을 띄우므로 둘이 겹쳐 쌓이지 않는다(PermissionActivity 쪽 확인).
            binding.goToPermissionButton.setOnClickListener {
                startActivity(Intent(this, PermissionActivity::class.java))
            }
        }
    }
}
