package com.kidcare.family

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.child.ChildHomeActivity
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
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
                binding.statusText.text = getString(R.string.connect_failed, e.message ?: "")
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
            Role.GUARDIAN -> if (store.isPaired) GuardianMainActivity::class.java
                             else GuardianPairingActivity::class.java
            Role.CHILD -> if (store.isPaired) ChildHomeActivity::class.java
                          else ChildPairingActivity::class.java
        }
    }
}
