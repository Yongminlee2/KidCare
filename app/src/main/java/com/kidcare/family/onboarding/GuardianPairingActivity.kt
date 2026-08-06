package com.kidcare.family.onboarding

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.RouterActivity
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityGuardianPairingBinding
import com.kidcare.family.guardian.GuardianMainActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 보호자 쪽 페어링. 가족을 만들고 코드를 띄운 뒤, 아이가 들어올 때까지 기다린다.
 *
 * 이미 가족을 만든 뒤 앱을 껐다 켠 경우에는 새로 만들지 않고 기존 가족의 코드를 다시 띄운다.
 * (RoleStore.familyId 가 남아 있으면 그것을 쓴다)
 */
class GuardianPairingActivity : AppCompatActivity() {

    private lateinit var binding: ActivityGuardianPairingBinding
    private var listener: ListenerRegistration? = null

    // observeChildJoined 는 스냅샷을 두 번(캐시→서버) 돌려줄 수 있다.
    // 두 번째 콜백이 첫 번째의 remove() 보다 먼저 큐에 올라와 있었다면
    // 화면을 두 번 띄우고 겹쳐 쌓을 수 있어서, 한 번만 넘어가도록 플래그로 막는다.
    private var navigated = false

    // onCreate 에서 시작하는 코루틴의 Job. onDestroy 가 알아서 취소해줄 거라고 믿으면 안 된다 —
    // "역할 다시 고르기"는 화면이 살아있는 채로 store.clear() 를 부르므로, 그 시점에 코루틴이
    // 아직 createFamily() 응답을 기다리는 중이면 clear() 이후에 재개돼 지워진 RoleStore 에
    // familyId 를 도로 써넣을 수 있다. 그래서 clear() 전에 이 Job 을 직접 취소한다.
    private var pairingJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityGuardianPairingBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val store = RoleStore(this)

        binding.resetRoleButton.setOnClickListener {
            // 페어링이 끝나기 전까지만 보이는 되돌리기 버튼.
            // 이미 만들어진 가족 문서는 그대로 버려둔다(멤버가 보호자 하나뿐인 빈 문서라 해가 없다).
            //
            // 순서가 중요하다: 코루틴을 먼저 취소해야 store.clear() 뒤에 코루틴이 깨어나
            // familyId 를 다시 써넣는 경합을 막을 수 있다. cancel → clear → navigate.
            pairingJob?.cancel()
            listener?.remove()
            listener = null
            store.clear()
            startActivity(
                Intent(this, RouterActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            )
            finish()
        }

        pairingJob = lifecycleScope.launch {
            try {
                val uid = AuthGateway.signIn()
                val familyId = store.familyId ?: FamilyRepository.createFamily(uid).also {
                    store.familyId = it
                }
                binding.codeText.text = FamilyRepository.inviteCodeOf(familyId)
                listener = FamilyRepository.observeChildJoined(familyId) { goToMain() }
            } catch (e: CancellationException) {
                // 화면 이탈(되돌리기 버튼, onDestroy)로 인한 정상 취소다. 실패로 취급해
                // hintText 를 덮어쓰면 안 되므로 그대로 다시 던져 코루틴 취소를 완성시킨다.
                throw e
            } catch (e: Exception) {
                binding.hintText.text = getString(R.string.pairing_failed, e.message ?: "")
            }
        }
    }

    private fun goToMain() {
        // 화면이 이미 사라지는 중이면 죽은 Activity 로 startActivity 하지 않는다.
        if (navigated || isFinishing || isDestroyed) return
        navigated = true
        listener?.remove()
        listener = null
        startActivity(Intent(this, GuardianMainActivity::class.java))
        finish()
    }

    override fun onDestroy() {
        listener?.remove()
        super.onDestroy()
    }
}
