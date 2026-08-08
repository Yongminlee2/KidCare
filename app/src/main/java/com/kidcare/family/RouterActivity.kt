package com.kidcare.family

import android.content.Intent
import android.os.Bundle
import android.view.View
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * 런처. 익명 로그인을 끝낸 뒤 저장된 상태에 따라 갈라 보낸다.
 *
 *   역할 없음        → 역할 선택
 *   역할만 있음      → 그 역할의 페어링 화면
 *   역할 + 가족 있음 → 그 역할의 본 화면
 *
 * ## 로그인이 실패하면 여기가 막다른 골목이었다 (6단계 Task 3)
 *
 * 예전에는 실패 문구를 한 줄 적고 코루틴이 그대로 끝났다. 이 화면에는 다른 글자도
 * 버튼도 없으므로 **앱을 강제로 껐다 켜는 것 말고는 나갈 길이 없었다.** 비행기 모드
 * 첫 실행이 정확히 그 모양이다 — 부모는 새싹이와 "연결 실패" 두 글자를 보고 앱이
 * 고장났다고 판단한다.
 *
 * 그래서 실패하면 '다시 시도' 버튼을 띄운다. 이 화면에서 할 수 있는 일이 그것뿐이라
 * 버튼도 그것 하나다 — 페어링 화면의 '역할 다시 고르기'는 여기 필요 없다. 로그인은
 * 역할과 아무 상관이 없고, 역할을 지워도 다음 화면에서 같은 로그인을 다시 하다가
 * 같은 자리에서 막힌다.
 *
 * ## 제한시간을 두는 이유
 *
 * Firestore 쓰기와 달리 익명 로그인은 요청-응답 HTTP 왕복이라 **보통은** 실패로
 * 끝난다(그래서 위 실패 경로가 실제로 돈다). 그래도 제한시간을 둔 것은, 그 "보통"이
 * SDK 안쪽 사정이라 코드에서 보이지 않기 때문이다. 만에 하나 안 끝나면 화면은
 * "연결 중…"에 영원히 멈추고, 그때는 **실패 문구도 버튼도 안 뜬다** — 위에서 없앤
 * 막다른 골목이 모양만 바꿔 돌아온다. 15초는 이 저장소가 이미 쓰는 값과 같다
 * ([com.kidcare.family.core.FamilyRepository] 의 `MEASURE_TIMEOUT_MILLIS`).
 */
class RouterActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRouterBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRouterBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.retryButton.setOnClickListener { signInAndGo() }
        signInAndGo()
    }

    private fun signInAndGo() {
        binding.statusText.text = getString(R.string.connecting)
        binding.retryButton.visibility = View.GONE

        lifecycleScope.launch {
            try {
                withTimeout(SIGN_IN_TIMEOUT_MILLIS) { AuthGateway.signIn() }
            } catch (e: TimeoutCancellationException) {
                // TimeoutCancellationException 은 CancellationException 의 하위 타입이라
                // 반드시 아래 catch 보다 **먼저** 와야 한다. 순서가 바뀌면 이 시간 초과가
                // "정상적인 화면 이탈"로 오인돼 그대로 다시 던져지고, 화면은 "연결 중…"
                // 인 채로 남는다(GuardianPairingActivity 에 같은 주석이 있다).
                showFailure(getString(R.string.pairing_offline))
                return@launch
            } catch (e: CancellationException) {
                // 화면 이탈로 인한 정상 취소다. 예전에는 아래 일반 catch 가 이것까지
                // 삼켰고, 그때는 뒤에 아무 일도 없어서 관측 가능한 오작동이 없었다
                // (docs/known-issues.md "남겨두기로 판단한 것"). 이제는 다르다 —
                // 삼키면 사라지는 화면에 "다시 시도" 버튼을 띄우게 된다.
                throw e
            } catch (e: Exception) {
                showFailure(errorMessage(this@RouterActivity, e))
                return@launch
            }
            startActivity(Intent(this@RouterActivity, destination()))
            finish()
        }
    }

    private fun showFailure(reason: String) {
        binding.statusText.text = getString(R.string.connect_failed, reason)
        binding.retryButton.visibility = View.VISIBLE
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

    private companion object {
        /** 값의 근거는 클래스 주석 "제한시간을 두는 이유" 참고. */
        const val SIGN_IN_TIMEOUT_MILLIS = 15_000L
    }
}
