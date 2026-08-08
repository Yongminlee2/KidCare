package com.kidcare.family.guardian

import android.content.Context
import com.kidcare.family.core.model.CommandType

/**
 * "장소를 바꿨는데 아직 아이 폰에 알리지 못했다"는 사실을 부모 폰에 남긴다.
 *
 * 존재 이유와 저장 방식(SharedPreferences·commit)은 [ScheduleSyncStore] 와 글자 그대로
 * 같다 — 그 클래스 주석에 근거를 적어뒀다(번들로는 뒤로 가기를 못 넘긴다).
 *
 * 파일을 나눠 둔 이유는 **깃발이 서로 다른 사실을 가리키기 때문**이다. 예약 깃발이
 * 켜졌다고 장소가 밀린 것은 아니고 그 반대도 아니다. 한 키를 같이 쓰면 예약 쪽에서
 * [CommandType.SYNC_RULES] 를 성공적으로 보내는 순간 장소 쪽의 못 보낸 사실까지 함께
 * 지워진다 — 그 뒤로는 이미 지운 장소의 지오펜스가 아이 폰에 남아 계속 우는데 화면에는
 * 아무 표시가 없다.
 *
 * (같은 명령이 예약과 장소를 **둘 다** 다시 읽게 하므로 실제로는 한쪽 성공이 다른 쪽도
 * 해결해 준다. 그래도 깃발을 합치지 않는 것은, 그 사실이 자녀 폰 CommandHandler 의
 * 구현 세부라 나중에 갈라질 수 있고 그때 조용히 고장 나는 쪽이 삭제 경로이기 때문이다.
 * 헛 명령 한 번은 무해하다.)
 */
class PlaceSyncStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_place_sync", Context.MODE_PRIVATE)

    /** commit()(동기)으로 쓰는 이유는 [ScheduleSyncStore.pendingSync] 와 같다. */
    var pendingSync: Boolean
        get() = prefs.getBoolean(KEY_PENDING, false)
        set(value) {
            prefs.edit().putBoolean(KEY_PENDING, value).commit()
        }

    private companion object {
        const val KEY_PENDING = "pending_sync"
    }
}
