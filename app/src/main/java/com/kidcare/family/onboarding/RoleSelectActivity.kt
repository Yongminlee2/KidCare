package com.kidcare.family.onboarding

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.kidcare.family.R
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityRoleSelectBinding

/**
 * 첫 실행 화면. 페어링이 끝나면 역할이 잠긴다.
 * 페어링이 끝나기 전에는 연결 화면에서 되돌릴 수 있다(그 되돌리기 버튼은 Task 5·6 에서 붙는다).
 * 페어링이 끝난 뒤 바꾸려면 앱 데이터를 지우고 다시 페어링해야 한다.
 */
class RoleSelectActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val binding = ActivityRoleSelectBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val store = RoleStore(this)
        binding.guardianButton.setOnClickListener { chooseGuardianPath(store) }
        binding.childButton.setOnClickListener { choose(store, Role.CHILD) }
    }

    private fun chooseGuardianPath(store: RoleStore) {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.guardian_start_title)
            .setItems(
                arrayOf(
                    getString(R.string.guardian_start_new_family),
                    getString(R.string.guardian_start_join_family),
                )
            ) { _, which ->
                store.role = Role.GUARDIAN
                val next = if (which == 0) GuardianPairingActivity::class.java
                    else ChildPairingActivity::class.java
                startActivity(Intent(this, next))
                finish()
            }
            .setNegativeButton(R.string.dialog_cancel, null)
            .show()
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
