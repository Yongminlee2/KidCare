package com.kidcare.family.onboarding

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.R
import com.kidcare.family.RouterActivity
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.PairingException
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityChildPairingBinding
import com.kidcare.family.logic.InviteCode
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 아이 쪽 페어링. 코드가 6자리로 유효해질 때만 버튼이 켜진다.
 * 성공하면 권한 온보딩으로 넘어간다 (Task 7 에서 PermissionActivity 로 바꾼다).
 */
class ChildPairingActivity : AppCompatActivity() {

    private lateinit var binding: ActivityChildPairingBinding

    // join() 이 시작한 코루틴의 Job. GuardianPairingActivity 와 같은 이유로 필요하다:
    // "역할 다시 고르기"를 누른 시점에 joinFamily() 의 네트워크 응답을 기다리는 중이면,
    // clear() 이후에 코루틴이 깨어나 지워진 RoleStore 에 familyId 를 도로 써넣을 수 있다.
    // 그래서 clear() 전에 이 Job 을 먼저 취소한다.
    private var joinJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityChildPairingBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val store = RoleStore(this)

        binding.codeInput.doAfterTextChanged { text ->
            binding.joinButton.isEnabled = InviteCode.isValid(text?.toString().orEmpty())
            binding.errorText.visibility = View.GONE
        }
        binding.joinButton.setOnClickListener { join() }

        binding.resetRoleButton.setOnClickListener {
            // 순서가 중요하다: 코루틴을 먼저 취소해야 store.clear() 뒤에 코루틴이 깨어나
            // familyId 를 다시 써넣는 경합을 막을 수 있다. cancel → clear → navigate.
            joinJob?.cancel()
            store.clear()
            startActivity(
                Intent(this, RouterActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            )
            finish()
        }
    }

    private fun join() {
        val code = binding.codeInput.text?.toString().orEmpty()
        binding.joinButton.isEnabled = false
        joinJob = lifecycleScope.launch {
            try {
                val uid = AuthGateway.signIn()
                val familyId = FamilyRepository.joinFamily(code, uid)
                RoleStore(this@ChildPairingActivity).familyId = familyId
                startActivity(Intent(this@ChildPairingActivity, PermissionActivity::class.java))
                finish()
            } catch (e: CancellationException) {
                // 화면 이탈(되돌리기 버튼, onDestroy)로 인한 정상 취소다. 실패로 취급해
                // errorText 를 덮어쓰면 안 되므로 그대로 다시 던져 코루틴 취소를 완성시킨다.
                throw e
            } catch (e: PairingException) {
                showError(
                    when (e.reason) {
                        PairingException.Reason.NOT_FOUND -> getString(R.string.pairing_not_found)
                        PairingException.Reason.EXPIRED -> getString(R.string.pairing_expired)
                        PairingException.Reason.ALREADY_FULL -> getString(R.string.pairing_full)
                        PairingException.Reason.OFFLINE -> getString(R.string.pairing_offline)
                    }
                )
            } catch (e: Exception) {
                showError(getString(R.string.pairing_failed, e.message ?: ""))
            }
        }
    }

    private fun showError(message: String) {
        binding.errorText.text = message
        binding.errorText.visibility = View.VISIBLE
        binding.joinButton.isEnabled = true
    }
}
