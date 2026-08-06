package com.kidcare.family.onboarding

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import androidx.core.content.ContextCompat
import com.kidcare.family.R

/**
 * 자녀 폰이 받아야 하는 권한들. 순서가 중요하다.
 *
 * 안드로이드 11 부터 '항상 허용'은 앱에서 바로 못 받는다. 먼저 '앱 사용 중 허용'을
 * 받은 뒤에야 시스템 설정으로 보낼 수 있다. 그래서 FINE 이 BACKGROUND 보다 앞에 있다.
 */
enum class PermissionStep(val titleRes: Int, val reasonRes: Int) {

    LOCATION_FINE(R.string.perm_location_title, R.string.perm_location_reason) {
        override fun isGranted(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
    },

    LOCATION_BACKGROUND(R.string.perm_background_title, R.string.perm_background_reason) {
        override fun isGranted(context: Context): Boolean =
            // ACCESS_BACKGROUND_LOCATION 자체가 안드로이드 10(Q, API 29)에 생겼다.
            // 그 이전 기기에서는 위치 권한 자체가 곧 '항상 허용'이라 이 단계가 필요 없다.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) true
            else ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
    },

    NOTIFICATION(R.string.perm_notification_title, R.string.perm_notification_reason) {
        override fun isGranted(context: Context): Boolean =
            // POST_NOTIFICATIONS 는 안드로이드 13(TIRAMISU, API 33)부터 런타임 권한이다.
            // 그 이전 기기에서는 알림 표시에 별도 권한이 필요 없다.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) true
            else ContextCompat.checkSelfPermission(
                context, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
    },

    BATTERY_UNRESTRICTED(R.string.perm_battery_title, R.string.perm_battery_reason) {
        override fun isGranted(context: Context): Boolean {
            // PowerManager.isIgnoringBatteryOptimizations 는 API 23부터 있어서
            // minSdk 26 전체에서 버전 분기 없이 그대로 쓸 수 있다.
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(context.packageName)
        }
    },

    // 맨 뒤에 둔다 — 위치가 없으면 활동 인식은 의미가 없고(다른 단계들과 달리),
    // 이 권한은 거부돼도 앱이 망가지지 않는다. LocationCollector 가 이동(1분) 주기로
    // 계속 동작할 뿐이다. '이 권한이 없으면 죽는다'가 아니라 '있으면 배터리를 아낀다'.
    ACTIVITY_RECOGNITION(R.string.perm_activity_title, R.string.perm_activity_reason) {
        override fun isGranted(context: Context): Boolean =
            // ACTIVITY_RECOGNITION 은 안드로이드 10(Q, API 29)부터 런타임 권한이다.
            // 그 이전 기기에서는 매니페스트 선언만으로 쓸 수 있어 항상 true 를 준다 —
            // 여기서 false 를 주면 이 단계 버튼을 눌러도(PermissionActivity.ask()가
            // API 29 미만에서는 아무 것도 안 하므로) 화면이 절대 안 넘어가 아이가
            // 갇힌다.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) true
            else ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
    };

    abstract fun isGranted(context: Context): Boolean

    companion object {
        /** 아직 안 받은 첫 번째 단계. 전부 받았으면 null. */
        fun firstMissing(context: Context): PermissionStep? =
            entries.firstOrNull { !it.isGranted(context) }
    }
}
