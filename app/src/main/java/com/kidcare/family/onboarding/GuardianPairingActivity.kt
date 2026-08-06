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
import com.kidcare.family.core.InviteCodeInfo
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityGuardianPairingBinding
import com.kidcare.family.guardian.GuardianMainActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * 보호자 쪽 페어링. 가족을 만들고 코드를 띄운 뒤, 아이가 들어올 때까지 기다린다.
 *
 * 이미 가족을 만든 뒤 앱을 껐다 켠 경우에는 새로 만들지 않고 기존 가족의 코드를 다시 띄운다.
 * (RoleStore.familyId 가 남아 있으면 그것을 쓴다)
 *
 * 페어링은 "코드를 보여줬다"가 아니라 "아이가 실제로 들어왔다"가 끝이다(childUid 가
 * RoleStore 에 채워지는 순간, goToMain 참고). RouterActivity.destination() 이 그
 * 값을 보고 판단하므로, 코드만 만들고 아무도 안 들어온 상태로 화면을 나갔다 와도
 * 다시 이 화면으로 돌아온다 — 사라진 코드 앞에 갇히는 일이 없다.
 */
class GuardianPairingActivity : AppCompatActivity() {

    private lateinit var binding: ActivityGuardianPairingBinding
    private lateinit var store: RoleStore
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

    // "새 번호 받기" 버튼이 시작하는 코루틴의 Job. familyId 를 쓰지는 않지만
    // 같은 이유로 화면을 나갈 때 정리해준다.
    private var refreshJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityGuardianPairingBinding.inflate(layoutInflater)
        setContentView(binding.root)

        store = RoleStore(this)

        // 코드가 아직 없는 동안(가족 생성 중)에는 "새 번호 받기"가 할 일이
        // 없다 — inviteCodeOf 는 이미 있는 가족의 코드를 갈아 끼우는 것이지
        // 첫 코드를 만드는 게 아니다. showCode()가 처음 불릴 때 켠다.
        binding.newCodeButton.isEnabled = false
        binding.newCodeButton.setOnClickListener { refreshCode() }

        binding.resetRoleButton.setOnClickListener {
            // 페어링이 끝나기 전까지만 보이는 되돌리기 버튼.
            // 이미 만들어진 가족 문서는 그대로 버려둔다(멤버가 보호자 하나뿐인 빈 문서라 해가 없다).
            //
            // 순서가 중요하다: 코루틴을 먼저 취소해야 store.clear() 뒤에 코루틴이 깨어나
            // familyId 를 다시 써넣는 경합을 막을 수 있다. cancel → clear → navigate.
            pairingJob?.cancel()
            refreshJob?.cancel()
            listener?.remove()
            listener = null
            store.clear()
            startActivity(
                Intent(this, RouterActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            )
            finish()
        }

        startPairing()
    }

    private fun startPairing() {
        pairingJob = lifecycleScope.launch {
            try {
                // 보호자가 오프라인이면 familyRef.set()/get() 이 서버 확인 없이는
                // 끝나지 않고 걸려 있을 수 있다 — 무한 스피너를 막으려고 시간을 자른다.
                withTimeout(SETUP_TIMEOUT_MILLIS) {
                    val uid = AuthGateway.signIn()
                    val familyId = store.familyId ?: FamilyRepository.createFamily(uid).also {
                        store.familyId = it
                    }
                    showCode(FamilyRepository.inviteCodeOf(familyId))
                    listener = FamilyRepository.observeChildJoined(
                        familyId,
                        onJoined = { childUid -> goToMain(childUid) },
                        onError = { e ->
                            binding.hintText.text = getString(R.string.pairing_failed, e.message ?: "")
                        },
                    )
                }
            } catch (e: TimeoutCancellationException) {
                // withTimeout 이 던지는 TimeoutCancellationException 은
                // CancellationException 의 하위 타입이다. 아래 CancellationException
                // catch 보다 반드시 먼저 와야 한다 — 순서가 바뀌면 이 타임아웃도
                // "정상적인 화면 이탈 취소"로 오인돼 그대로 다시 던져지고, 정작
                // 보여줘야 할 오프라인 안내가 삼켜진다.
                binding.hintText.text = getString(R.string.pairing_offline)
            } catch (e: CancellationException) {
                // 화면 이탈(되돌리기 버튼, onDestroy)로 인한 정상 취소다. 실패로 취급해
                // hintText 를 덮어쓰면 안 되므로 그대로 다시 던져 코루틴 취소를 완성시킨다.
                throw e
            } catch (e: Exception) {
                binding.hintText.text = getString(R.string.pairing_failed, e.message ?: "")
            }
        }
    }

    /** "새 번호 받기" 버튼. 만료 전이어도 무조건 새로 발급해 이전 코드를 죽인다. */
    private fun refreshCode() {
        val familyId = store.familyId ?: return
        binding.newCodeButton.isEnabled = false
        refreshJob = lifecycleScope.launch {
            try {
                withTimeout(SETUP_TIMEOUT_MILLIS) {
                    showCode(FamilyRepository.inviteCodeOf(familyId, forceNew = true))
                }
            } catch (e: TimeoutCancellationException) {
                // 위 startPairing() 과 같은 이유로 CancellationException 보다 먼저 잡는다.
                binding.hintText.text = getString(R.string.pairing_offline)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                binding.hintText.text = getString(R.string.pairing_failed, e.message ?: "")
            } finally {
                binding.newCodeButton.isEnabled = true
            }
        }
    }

    /** 코드와 남은 유효시간을 화면에 반영한다. 실시간 카운트다운이 아니라 호출 시점의 스냅샷이다. */
    private fun showCode(info: InviteCodeInfo) {
        binding.codeText.text = info.code
        val minutesLeft = ((info.expiresAt - System.currentTimeMillis() + 59_999L) / 60_000L)
            .coerceAtLeast(1L)
        binding.expiryText.text = getString(R.string.pairing_code_expiry_format, minutesLeft)
        binding.hintText.setText(R.string.pairing_guardian_hint)
        binding.newCodeButton.isEnabled = true
    }

    private fun goToMain(childUid: String) {
        // 화면이 이미 사라지는 중이면 죽은 Activity 로 startActivity 하지 않는다.
        if (navigated || isFinishing || isDestroyed) return
        navigated = true
        // familyId 만으로는 "코드를 만들었다"만 알 수 있다. 아이가 실제로 들어왔다는
        // 사실 자체를 저장해둬야 RouterActivity 가 다음부터 곧장 GuardianMainActivity
        // 로 보낼 수 있다(Fix 1).
        store.childUid = childUid
        listener?.remove()
        listener = null
        startActivity(Intent(this, GuardianMainActivity::class.java))
        finish()
    }

    override fun onDestroy() {
        listener?.remove()
        super.onDestroy()
    }

    private companion object {
        const val SETUP_TIMEOUT_MILLIS = 20_000L
    }
}
