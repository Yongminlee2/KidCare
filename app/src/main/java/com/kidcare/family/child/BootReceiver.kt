package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore

/**
 * 재부팅 후 자녀 폰이면 위치 서비스를 다시 띄운다.
 *
 * 여기서는 위치 권한을 따로 확인하지 않는다 — BOOT_COMPLETED 를 처리하는 도중의
 * startForegroundService() 호출은 안드로이드의 "백그라운드 포그라운드서비스 시작 제한"
 * 예외 목록에 있어(문서화된 예외: 부팅 직후 브로드캐스트 수신 중) 허용되지만, 권한
 * 자체가 없을 때 startForeground(location 타입)를 부르면 API 34+ 에서 여전히
 * SecurityException 이 날 수 있다. 그 확인과 안전한 종료는 TrackingService.onCreate
 * 한 곳에서만 하도록 몰아뒀다 — 두 군데서 따로 확인하면 나중에 하나만 고치고 잊는
 * 사고가 나기 쉽다.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val store = RoleStore(context)
        if (store.role == Role.CHILD && store.isPaired) {
            TrackingService.start(context)
        }
    }
}
