package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.kidcare.family.core.Role
import com.kidcare.family.core.RoleStore
import com.kidcare.family.guardian.AlertService

/**
 * 재부팅 후 역할에 맞는 상시 서비스를 다시 띄운다 — 자녀 폰은 위치 수집
 * ([TrackingService]), 보호자 폰은 알림 상시 수신
 * ([com.kidcare.family.guardian.AlertService]).
 *
 * 이 파일이 `child` 패키지에 있으면서 보호자 서비스를 켜는 것이 어색해 보이지만,
 * 리시버를 둘로 나누는 쪽이 더 나쁘다. `BOOT_COMPLETED` 는 매니페스트에 등록된
 * 리시버가 여럿이면 각각 따로 깨어나고, 그러면 "부팅 뒤에 무엇을 켜는가"라는 하나의
 * 판단이 파일 둘에 갈라진다 — 한쪽만 고치고 잊는 사고가 이 저장소에서 이미 여러 번
 * 났다. 한 기기는 자녀 아니면 보호자 둘 중 하나라 분기는 여기 한 줄이면 끝난다.
 *
 * 여기서는 위치 권한을 따로 확인하지 않는다 — BOOT_COMPLETED 를 처리하는 도중의
 * startForegroundService() 호출은 안드로이드의 "백그라운드 포그라운드서비스 시작 제한"
 * 예외 목록에 있어(문서화된 예외: 부팅 직후 브로드캐스트 수신 중) 허용되지만, 권한
 * 자체가 없을 때 startForeground(location 타입)를 부르면 API 34+ 에서 여전히
 * SecurityException 이 날 수 있다. 그 확인과 안전한 종료는 TrackingService.onCreate
 * 한 곳에서만 하도록 몰아뒀다 — 두 군데서 따로 확인하면 나중에 하나만 고치고 잊는
 * 사고가 나기 쉽다.
 *
 * **장소 지오펜스 재등록도 여기서 따로 하지 않는다.** OS 는 재부팅 때 등록된 지오펜스를
 * 전부 지우므로 다시 걸어야 하는 것은 맞는데(설계서 §4.6), 그 일은 아래에서 띄우는
 * [TrackingService] 의 onStartCommand 가 이미 한다
 * ([TrackingService.refreshPlaces]). 여기에 같은 등록을 한 번 더 적으면 두 곳이
 * 갈라지고 — 위 권한 확인을 한 곳에 몰아둔 것과 정확히 같은 이유다 — 재부팅마다
 * 지오펜스를 두 번 걸게 된다.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val store = RoleStore(context)
        if (!store.isPaired) return
        when (store.role) {
            Role.CHILD -> TrackingService.start(context)
            // 보호자 쪽은 부모가 켜 뒀을 때만이다. 재부팅했다고 꺼둔 스위치가 저절로
            // 켜지면 그건 부모가 정한 것을 앱이 뒤집는 것이다 — 그 판단은
            // AlertService.startIfEnabled 안에 있다.
            Role.GUARDIAN -> AlertService.startIfEnabled(context)
            null -> Unit
        }
    }
}
