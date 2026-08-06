package com.kidcare.family.onboarding

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.R
import com.kidcare.family.child.ChildHomeActivity
import com.kidcare.family.databinding.ActivityPermissionBinding

/**
 * 자녀 폰 권한 온보딩. 한 번에 하나씩만 보여주고, 받을 때까지 다음으로 안 넘어간다.
 *
 * 화면에 돌아올 때마다(onResume) 다시 검사하므로, 설정 앱에 다녀오면 자동으로 다음 단계가 뜬다.
 */
class PermissionActivity : AppCompatActivity() {

    private lateinit var binding: ActivityPermissionBinding

    // 모든 단계를 다 받아 ChildHomeActivity 로 넘어가는 시점을 한 번만 타게 막는 플래그.
    // startActivity() 뒤 finish() 가 실제로 화면을 없애기 전에 onResume 이 다시 불리는
    // 경우가 있을 수 있는데, 그때 render() 가 또 돌면 ChildHomeActivity 가 두 번 뜬다.
    private var navigatedToHome = false

    // 방금 어떤 단계의 런타임 권한을 요청했는지 기억해둔다. 콜백은 "허용/거부"만 알려줘서,
    // 어느 permission 문자열의 rationale 을 확인해야 하는지는 따로 들고 있어야 한다.
    private var pendingStep: PermissionStep? = null

    // 사용자가 "다시 묻지 않음"까지 눌러서 시스템 다이얼로그가 다시는 안 뜨게 된 단계.
    // 이 상태에서 켜기 버튼을 또 눌러도 requestPermission.launch() 는 콜백조차 없이
    // 조용히 아무 일도 안 하므로, 버튼 동작 자체를 앱 설정 화면으로 바꿔야 한다.
    private var permanentlyDeniedStep: PermissionStep? = null

    private val requestPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val step = pendingStep
            pendingStep = null
            if (!granted && step != null) {
                val permission = step.runtimePermission()
                // 요청 직후인데도 rationale 을 보여줄 필요가 없다고 시스템이 판단했다면,
                // "다시 묻지 않음"을 눌렀거나 시스템이 스스로 그렇게 정한 것이다 — 영구 거부.
                if (permission != null && !shouldShowRequestPermissionRationale(permission)) {
                    permanentlyDeniedStep = step
                }
            }
            render()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPermissionBinding.inflate(layoutInflater)
        setContentView(binding.root)
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    private fun render() {
        if (navigatedToHome) return // 이미 다음 화면으로 넘어가는 중이면 다시 그리지 않는다.

        val step = PermissionStep.firstMissing(this)
        if (step == null) {
            navigatedToHome = true
            startActivity(Intent(this, ChildHomeActivity::class.java))
            finish()
            return
        }

        binding.stepTitle.setText(step.titleRes)

        if (permanentlyDeniedStep == step) {
            // 영구 거부 상태에서는 원래 이유 대신, 설정으로 가야 한다는 안내로 바꿔 보여준다.
            binding.stepReason.text = getString(R.string.perm_denied_permanently)
            binding.grantButton.setText(R.string.perm_open_settings)
        } else {
            binding.stepReason.setText(step.reasonRes)
            binding.grantButton.setText(R.string.perm_grant)
        }

        if (step == PermissionStep.BATTERY_UNRESTRICTED) {
            // 배터리 예외는 목록 화면만 열릴 뿐 이 앱이 자동으로 골라지지 않는다.
            // 아이가 직접 찾아야 하므로 화면에 구체적으로 적어준다.
            binding.stepHint.setText(R.string.perm_battery_hint)
            binding.stepHint.visibility = View.VISIBLE
        } else {
            binding.stepHint.visibility = View.GONE
        }

        // setOnClickListener 는 매번 이전 리스너를 새 것으로 교체할 뿐 쌓이지 않으므로,
        // render() 가 onResume 마다 다시 불려도(같은 단계에 머물러 있어도) 리스너가
        // 중복되거나 설정 화면이 저절로 다시 열리지 않는다 — ask() 는 클릭에서만 호출된다.
        binding.grantButton.setOnClickListener { ask(step) }
    }

    private fun ask(step: PermissionStep) {
        when (step) {
            PermissionStep.LOCATION_FINE ->
                requestOrOpenSettings(step, Manifest.permission.ACCESS_FINE_LOCATION)

            PermissionStep.LOCATION_BACKGROUND ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // 안드로이드 11+ 는 시스템 설정에서만 '항상 허용'을 고를 수 있다.
                    openAppSettings()
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // 안드로이드 10 은 런타임 다이얼로그로 바로 '항상 허용'을 받을 수 있다.
                    requestOrOpenSettings(step, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                }
            // Q 미만은 PermissionStep.isGranted() 가 항상 true 라 이 단계 자체가 안 뜬다.

            PermissionStep.NOTIFICATION ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    requestOrOpenSettings(step, Manifest.permission.POST_NOTIFICATIONS)
                }
            // TIRAMISU 미만은 PermissionStep.isGranted() 가 항상 true 라 이 단계 자체가 안 뜬다.

            PermissionStep.BATTERY_UNRESTRICTED ->
                // 목록 화면. ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS(자동 요청 다이얼로그)
                // 대신 이 목록 화면을 쓴다 — 전자는 플레이 정책상 특정 앱만 쓸 수 있다.
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    /** 이미 영구 거부된 단계면 설정 화면으로, 아니면 런타임 다이얼로그로. */
    private fun requestOrOpenSettings(step: PermissionStep, permission: String) {
        if (permanentlyDeniedStep == step) {
            openAppSettings()
        } else {
            pendingStep = step
            requestPermission.launch(permission)
        }
    }

    private fun openAppSettings() {
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null)
            )
        )
    }

    /** 이 단계가 런타임 다이얼로그로 요청하는 permission 문자열. 설정 화면 전용 단계는 null. */
    private fun PermissionStep.runtimePermission(): String? = when (this) {
        PermissionStep.LOCATION_FINE -> Manifest.permission.ACCESS_FINE_LOCATION
        PermissionStep.LOCATION_BACKGROUND ->
            if (Build.VERSION.SDK_INT in Build.VERSION_CODES.Q until Build.VERSION_CODES.R) {
                Manifest.permission.ACCESS_BACKGROUND_LOCATION
            } else {
                null
            }
        PermissionStep.NOTIFICATION ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Manifest.permission.POST_NOTIFICATIONS
            } else {
                null
            }
        PermissionStep.BATTERY_UNRESTRICTED -> null
    }
}
