package com.kidcare.family.onboarding

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityRoleSelectBinding

/**
 * 첫 실행 화면. 한 번 고르면 페어링이 끝나는 즉시 잠긴다.
 * 바꾸려면 앱 데이터를 지우고 다시 페어링해야 한다.
 */
class RoleSelectActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val binding = ActivityRoleSelectBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val store = RoleStore(this)
        binding.guardianButton.setOnClickListener { choose(store, Role.GUARDIAN) }
        binding.childButton.setOnClickListener { choose(store, Role.CHILD) }
    }

    private fun choose(store: RoleStore, role: Role) {
        store.role = role
        val next = when (role) {
            Role.GUARDIAN -> GuardianPairingActivity::class.java
            Role.CHILD -> ChildPairingActivity::class.java
        }
        startActivity(Intent(this, next))
        finish()
    }
}
