package com.kidcare.family

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.child.ChildHomeActivity
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.errorMessage
import com.kidcare.family.databinding.ActivityRouterBinding
import com.kidcare.family.guardian.GuardianMainActivity
import com.kidcare.family.onboarding.ChildPairingActivity
import com.kidcare.family.onboarding.GuardianPairingActivity
import com.kidcare.family.onboarding.RoleSelectActivity
import kotlinx.coroutines.launch

/**
 * 런처. 익명 로그인을 끝낸 뒤 저장된 상태에 따라 갈라 보낸다.
 *
 *   역할 없음        → 역할 선택
 *   역할만 있음      → 그 역할의 페어링 화면
 *   역할 + 가족 있음 → 그 역할의 본 화면
 */
class RouterActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val binding = ActivityRouterBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.statusText.text = getString(R.string.connecting)

        lifecycleScope.launch {
            try {
                AuthGateway.signIn()
            } catch (e: Exception) {
                binding.statusText.text = getString(R.string.connect_failed, errorMessage(this@RouterActivity, e))
                return@launch
            }
            startActivity(Intent(this@RouterActivity, destination()))
            finish()
        }
    }

    private fun destination(): Class<*> {
        val store = RoleStore(this)
        return when (store.role) {
            null -> RoleSelectActivity::class.java
            // isPaired(role+familyId) 만으로는 부족하다: 보호자는 코드를 만든
            // 순간 familyId 가 생기지만, 그 시점엔 아직 아무 아이도 안 들어왔을
            // 수 있다. childUid 까지 있어야 진짜로 아이가 연결된 것이다 — 아니면
            // GuardianPairingActivity 로 돌려보내 코드를 다시 보여준다(코드는
            // 그 화면이 재진입 시 기존 familyId 로 이어서 처리한다).
            Role.GUARDIAN -> if (store.familyId != null && store.childUid != null)
                                 GuardianMainActivity::class.java
                             else GuardianPairingActivity::class.java
            // 자녀 쪽은 Task 7 의 권한 복구 흐름이 이 분기에 그대로 의존하므로
            // 손대지 않는다 — isPaired 그대로 쓴다.
            Role.CHILD -> if (store.isPaired) ChildHomeActivity::class.java
                          else ChildPairingActivity::class.java
        }
    }
}
