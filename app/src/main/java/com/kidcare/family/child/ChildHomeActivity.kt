package com.kidcare.family.child

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.kidcare.family.R
import com.kidcare.family.RouterActivity
import com.kidcare.family.core.LanguagePicker
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.databinding.ActivityChildHomeBinding
import com.kidcare.family.onboarding.PermissionActivity
import com.kidcare.family.onboarding.PermissionStep
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

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
 * ## 이 화면이 거짓말할 수 있는 두 자리 (6단계 Task 3)
 *
 * 권한이 다 켜져 있으면 이 화면은 무조건 "위치를 공유하고 있어요"라고 말했다. 그런데
 * 그 말이 참이 아닌 상태가 둘 더 있고, 둘 다 **아이 폰에서는 아무 증상이 없다.**
 *
 * 1. **Google Play 서비스가 없거나 너무 낡았다.** 위치 수집(FusedLocationProvider)과
 *    지오펜스가 통째로 그 위에서 돈다([LocationCollector], [PlaceWatcher]). 없으면
 *    콜백이 한 번도 안 오는데 예외도 안 난다 — 서비스는 멀쩡히 떠 있고 상시 알림도
 *    그대로다. 부모 지도의 마커만 영원히 안 움직인다.
 * 2. **가족에서 빠졌다**(부모가 정리했거나 멤버 문서가 사라졌다). 쓰기가 전부
 *    PERMISSION_DENIED 로 거부되지만 그 거부는 logcat 에만 남는다.
 *
 * 둘 다 부모 쪽에서는 한참 뒤에야 보인다 — 연결 끊김 배너는 부모가 명령을 한 번
 * 보내고 30분을 기다려야 뜬다([com.kidcare.family.logic.DisconnectRule]). 그래서
 * **증상이 처음 생기는 폰**인 여기서 말한다.
 *
 * 상태는 한 번에 하나만 보여준다. 순서는 "이걸 고쳐야 다음이 의미가 있는가"다 —
 * 가족에서 빠졌으면 권한을 다 켜도 아무 데도 안 가고, Play 서비스가 없으면 권한을
 * 켜도 위치가 안 잡힌다.
 */
class ChildHomeActivity : AppCompatActivity() {

    private lateinit var binding: ActivityChildHomeBinding

    /**
     * 가족 멤버 확인 코루틴. 화면에 다시 들어올 때마다 새로 던지므로, 앞의 것이
     * 아직 응답을 기다리는 중이면 취소한다 — 안 그러면 뒤늦게 도착한 옛 답이
     * 방금 그린 화면을 덮어쓴다.
     */
    private var memberCheckJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityChildHomeBinding.inflate(layoutInflater)
        setContentView(binding.root)
    }

    override fun onResume() {
        super.onResume()

        binding.homeTitle.setText(R.string.child_home_title)
        val playServices = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this)
        val missing = PermissionStep.firstMissing(this)

        when {
            playServices != ConnectionResult.SUCCESS -> showPlayServicesBroken(playServices)
            missing != null -> showPermissionMissing(missing)
            else -> showSharing()
        }
    }

    override fun onPause() {
        // 화면을 벗어나면 확인 결과를 그릴 곳이 없다. 그대로 두면 죽은 화면에
        // setText 를 하게 된다.
        memberCheckJob?.cancel()
        memberCheckJob = null
        super.onPause()
    }

    private fun showSharing() {
        TrackingService.start(this)
        binding.childStatus.text = getString(R.string.child_sharing_on)
        binding.actionButton.visibility = View.GONE
        checkStillInFamily()
    }

    private fun showPermissionMissing(missing: PermissionStep) {
        binding.childStatus.text =
            getString(R.string.child_permission_missing, getString(missing.titleRes))
        binding.actionButton.setText(R.string.child_go_to_permission)
        binding.actionButton.visibility = View.VISIBLE
        // 여기서 finish() 하지 않는다: 아이가 PermissionActivity 에서 뒤로가기로
        // 취소할 수도 있는데, 그때는 (finish() 했다면 텅 빈 태스크만 남아 앱 밖으로
        // 튕겨나가는 대신) 이 화면으로 그대로 돌아와야 하기 때문이다. 남은 권한을
        // 끝까지 다 받으면 PermissionActivity 가 CLEAR_TOP 으로 이 낡은 인스턴스를
        // 정리하고 새 화면을 띄우므로 둘이 겹쳐 쌓이지 않는다(PermissionActivity 쪽 확인).
        binding.languageButton.setOnClickListener { LanguagePicker.show(this) }
        binding.actionButton.setOnClickListener {
            startActivity(Intent(this, PermissionActivity::class.java))
        }
    }

    /**
     * Play 서비스가 없거나 낡았다. 고칠 수 있는 상태(설치·업데이트·사용 설정)면
     * 구글이 만든 대화상자를 그대로 띄운다 — 어느 안내를 보여줄지는 그 라이브러리가
     * 상태 코드를 보고 정한다. 우리가 분기하면 코드 목록을 따라다녀야 하고, 새 코드가
     * 생기면 조용히 빠진다.
     *
     * 고칠 수 없는 상태(플레이 서비스가 아예 없는 롬 등)에서는 버튼을 감춘다. 누를
     * 것이 없는 자리에 버튼을 두면 눌러도 아무 일이 없어 그게 더 나쁘다 — 대신 문구가
     * "이 화면을 엄마 아빠께 보여주세요"라는 다음 행동을 댄다.
     */
    private fun showPlayServicesBroken(status: Int) {
        val api = GoogleApiAvailability.getInstance()
        val fixable = api.isUserResolvableError(status)
        binding.childStatus.setText(
            if (fixable) R.string.child_play_services_fixable
            else R.string.child_play_services_unfixable
        )
        binding.actionButton.visibility = if (fixable) View.VISIBLE else View.GONE
        if (!fixable) return
        binding.actionButton.setText(R.string.child_play_services_fix)
        binding.actionButton.setOnClickListener { api.makeGooglePlayServicesAvailable(this) }
    }

    /**
     * 여기까지 왔으면 폰 쪽은 다 정상이다. 마지막으로 **서버가 아직 나를 이 가족의
     * 멤버로 아는지**를 확인한다([FamilyRepository.isStillMember]).
     *
     * 읽기 하나를 더 쓴다. 이 화면은 아이가 어쩌다 한 번 여는 곳이라 하루 몇 번
     * 수준이고(무료 한도 예산은 가족당 하루 50 읽기, docs/known-issues.md 12번),
     * 이 값을 안 물어보면 "공유 중"이라는 문장이 참인지 아무도 모른다.
     *
     * 답이 null(모른다 — 오프라인이거나 읽기가 실패했다)이면 **아무 말도 바꾸지
     * 않는다.** 확실하지 않은 것으로 화면을 겁주지 않는다.
     */
    private fun checkStillInFamily() {
        val familyId = RoleStore(this).familyId ?: return
        val uid = AuthGateway.currentUid() ?: return
        memberCheckJob?.cancel()
        memberCheckJob = lifecycleScope.launch {
            if (FamilyRepository.isStillMember(familyId, uid) != false) return@launch
            showFamilyGone()
        }
    }

    private fun showFamilyGone() {
        binding.homeTitle.setText(R.string.child_home_title_gone)
        binding.childStatus.setText(R.string.child_family_gone)
        binding.actionButton.setText(R.string.child_repair)
        binding.actionButton.visibility = View.VISIBLE
        binding.actionButton.setOnClickListener {
            // 페어링 화면의 '역할 다시 고르기'와 똑같은 탈출구다(RoleStore 를 비우고
            // 처음으로 돌려보낸다).
            //
            // **아이 폰에 이 버튼을 다는 것은 원래 설계 판단이 필요한 일이었다**
            // (docs/known-issues.md 1번 — 아이가 스스로 감시를 풀 수 있게 되기
            // 때문이다). 여기서는 그 걱정이 성립하지 않는다: 이 버튼은 서버가
            // "이 기기는 이 가족의 멤버가 아니다"라고 확답했을 때에만 뜬다. 그
            // 시점에는 이미 아무것도 공유되고 있지 않으므로, 눌러서 풀 감시가
            // 남아 있지 않다.
            RoleStore(this).clear()
            startActivity(
                Intent(this, RouterActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            )
            finish()
        }
    }
}
