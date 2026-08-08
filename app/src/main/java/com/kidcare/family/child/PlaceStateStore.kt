package com.kidcare.family.child

import android.content.Context
import com.kidcare.family.logic.PlaceState

/**
 * "이 장소 안에 있었다"는 사실을 프로세스 밖에 남긴다.
 *
 * ## 왜 메모리에 두면 안 되나
 *
 * [com.kidcare.family.logic.GeofenceEvaluator] 는 **직전 상태와 지금이 다를 때만**
 * 알린다. 그 직전 상태를 메모리에만 두면 아이가 앱을 강제 종료하거나 폰이 재부팅될
 * 때 함께 사라지고, 다음에 서비스가 뜰 때 그 장소는 "처음 보는 장소"가 된다.
 *
 * 지금의 판정기는 처음 보는 장소에서 조용히 상태만 심으므로(Task 2) 그 순간 가짜
 * 도착 알림이 나가지는 않는다. 대신 **반대쪽이 사라진다**: 아침에 학교에 도착한 뒤
 * 아이가 앱을 강제 종료하면 "안에 있었다"가 지워지고, 오후에 서비스가 다시 떠서
 * 상태를 심을 때 아이는 이미 학교 밖이라 `inside=false` 로 심긴다 — 그날의 하교
 * 이탈 알림은 영영 안 나간다. 침묵이 이 앱에서 제일 나쁜 고장이다.
 * `FindPhoneStateStore` 가 같은 이유(프로세스가 죽어도 남아야 하는 사실)로 있다.
 *
 * ## 저장 형식
 *
 * 값이 세 개짜리 줄 목록이라 JSON 파서를 끌어올 것도 없이 줄바꿈·탭으로 나눈다.
 * 두 구분자가 안전한 이유: [PlaceState.placeId] 는 Firestore 자동 ID(영숫자)라
 * 탭도 줄바꿈도 들어갈 수 없다. 그래도 읽는 쪽은 칸 수와 숫자 변환을 확인하고,
 * 이상한 줄은 통째로 버린다 — 저장소가 깨졌을 때 예외로 서비스를 죽이는 것보다
 * 그 장소만 "처음 보는 장소"로 되돌리는 쪽이 안전하다.
 */
class PlaceStateStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_places", Context.MODE_PRIVATE)

    /**
     * 쓰기는 commit()(동기)이다. apply() 는 디스크 반영을 뒤로 미루는데, 이 저장소가
     * 막으려는 사고가 바로 "그 사이에 프로세스가 사라지는 것"이다
     * (`FindPhoneStateStore.markRinging`·`ScheduleSyncStore` 와 같은 판단). 장소는 최대
     * 20개이고 이 쓰기는 위치 한 점에 한 번뿐이라 동기 비용은 무시할 만하다.
     */
    var states: List<PlaceState>
        get() = prefs.getString(KEY_STATES, null).orEmpty()
            .split(RECORD_SEPARATOR)
            .mapNotNull(::decode)
        set(value) {
            prefs.edit()
                .putString(KEY_STATES, value.joinToString(RECORD_SEPARATOR, transform = ::encode))
                .commit()
        }

    private fun encode(state: PlaceState): String =
        listOf(
            state.placeId,
            if (state.inside) "1" else "0",
            state.lastEventAt.toString(),
        ).joinToString(FIELD_SEPARATOR)

    private fun decode(row: String): PlaceState? {
        val parts = row.split(FIELD_SEPARATOR)
        if (parts.size != 3) return null
        val id = parts[0]
        if (id.isEmpty()) return null
        val lastEventAt = parts[2].toLongOrNull() ?: return null
        return PlaceState(placeId = id, inside = parts[1] == "1", lastEventAt = lastEventAt)
    }

    private companion object {
        const val KEY_STATES = "states"
        const val RECORD_SEPARATOR = "\n"
        const val FIELD_SEPARATOR = "\t"
    }
}
