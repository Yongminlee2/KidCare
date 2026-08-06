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
    };

    abstract fun isGranted(context: Context): Boolean

    companion object {
        /** 아직 안 받은 첫 번째 단계. 전부 받았으면 null. */
        fun firstMissing(context: Context): PermissionStep? =
            entries.firstOrNull { !it.isGranted(context) }
    }
}
