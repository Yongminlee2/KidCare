package com.kidcare.family.child

import android.content.Context
import android.util.Log
import com.kidcare.family.core.TrailRepository
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.core.model.TrailDoc
import com.kidcare.family.core.model.TrailPoint
import com.kidcare.family.logic.DayPicker
import com.kidcare.family.logic.Fix
import com.kidcare.family.logic.SegmentBuilder
import com.kidcare.family.logic.SegmentType
import com.kidcare.family.logic.TrailCodec
import kotlinx.coroutines.sync.Mutex
import java.time.ZoneId

/**
 * 오늘 위치 점을 모아 두었다가, **부를 때만** 하루 문서 하나로 올린다.
 * 옛 `SegmentUploader` 를 대신한다.
 *
 * ## 무엇이 바뀌었나
 *
 * 옛 구조: 점 하나가 들어올 때마다 `points/{autoId}` 문서를 만들고, 15분마다
 * 하루치를 다시 묶어 `segments/` 를 통째로 갈아끼웠다(하루 20~30개 삭제 + 같은 수
 * 쓰기). 가족 하나가 하루 약 1,100번을 쓴다.
 *
 * 지금: 점은 [onCollected] 로 메모리 버퍼와 [TrailStore] 파일에만 쌓인다. Firestore
 * 로는 [upload] 를 부를 때만, 그것도 **문서 하나**(`trails/{dayKey}`)로 나간다.
 * 그 문서 안에 원시 점 배열과 구간 요약 배열이 함께 들어 있다.
 *
 * 구간 요약을 여기서(자녀 폰에서) 계산해 함께 담는 이유는 그대로다: 머무른 곳
 * 이름은 역지오코딩([PlaceNamer])이 필요한데 보호자 폰이 하루치 점을 다시 묶으면
 * 그 이름이 통째로 사라진다. 요약을 별도 컬렉션에 두지 않는 이유는 하루 20~30개
 * 문서 교체만으로 가족당 하루 20쓰기 예산을 혼자 넘기기 때문이다.
 *
 * ## 자정 넘김
 *
 * 버퍼가 어느 날짜의 것인지([bufferDayKey])를 들고 있다가, 점의 시각이 다른 날로
 * 넘어가면 버퍼와 파일을 비우고 그 날짜로 새로 시작한다. 자정 직전의 마지막 업로드
 * 이후에 들어온 점 몇 개는 그대로 어제 문서에 안 담긴 채 버려지는데, 그건 의도된
 * 것이다 — 어제 문서를 다시 쓰려면 쓰기가 하나 더 들고, 자정 무렵 몇 분의 점을
 * 위해 예산을 쓸 이유가 없다.
 */
class TrailUploader(
    context: Context,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val placeNamer: PlaceNamer = PlaceNamer(),
) {

    private val store = TrailStore(context)

    /** 오늘 확보한 점들. [bufferDayKey] 가 null 이면 아직 한 점도 없다. */
    private val buffer = mutableListOf<Fix>()
    private var bufferDayKey: String? = null

    // 업로드가 겹치는 것을 막는다. PlaceNamer 는 점 하나당 최대 5초를 쓰고 Nominatim
    // 정책상 프로세스 전체가 초당 1건으로 직렬화되므로, 머무름이 여럿인 날의 한 번의
    // upload 가 수십 초를 넘길 수 있다. 그 사이 부모가 '지금 위치 확인'을 다시 누르면
    // 두 번째 호출이 같은 문서를 같은 내용으로 또 쓴다 — 쓰기 예산만 깎는 헛일이다.
    // tryLock 으로 "이미 도는 중이면 이번은 건너뛴다"만 한다. 대기(lock)를 쓰면
    // 큐에 쌓였다가 뒤늦게 또 한 번 나가는데, 그건 이미 최신인 문서를 다시 쓰는 것뿐이다.
    private val uploadMutex = Mutex()

    /**
     * 프로세스가 죽었다 살아난 경우 오늘 걸어온 길을 파일에서 되찾는다.
     * 서비스가 뜰 때 딱 한 번 부른다.
     *
     * 파일이 어제 것이면 아무것도 안 한다 — 다음 [onCollected] 가 날짜 불일치를 보고
     * 파일을 오늘 것으로 새로 만든다.
     */
    fun restore() {
        val saved = store.load() ?: return
        if (saved.dayKey != DayPicker.todayKey(zone, System.currentTimeMillis())) return
        buffer += saved.points
        bufferDayKey = saved.dayKey
        Log.i(TAG, "재시작 복구: ${saved.dayKey} 점 ${saved.points.size}개")
    }

    /**
     * 위치 한 점을 쌓는다. **Firestore 에는 아무것도 안 나간다.**
     *
     * [TrackingService] 는 `LocationFilter.decide()` 가 승인한 점만 여기로 넘긴다 —
     * 거절된 점을 넣으면 버퍼가 쓸데없이 커지고 구간 계산도 흔들린다.
     *
     * 파일 덧붙이기를 코루틴으로 빼지 않고 부른 스레드에서 그대로 한다. 50바이트
     * 한 줄을 30초에 한 번 붙이는 일이라 메인 스레드에서도 1ms 아래이고, 무엇보다
     * [buffer] 를 만지는 스레드가 하나로 유지되어 별도 잠금이 필요 없어진다.
     */
    fun onCollected(fix: Fix) {
        val dayKey = DayPicker.todayKey(zone, fix.at)
        if (dayKey != bufferDayKey) {
            buffer.clear()
            bufferDayKey = dayKey
            store.reset(dayKey)
        }
        buffer += fix
        store.append(fix)
    }

    /**
     * 오늘 문서를 통째로 덮어쓴다. 쓰기 **한 번**이다.
     *
     * 부를 자격이 있는 곳은 둘뿐이다 — `locate_now` 명령을 받았을 때와, 하루 한 번
     * 안전 업로드. 주기적으로 부르면 이 작업이 없애려던 비용이 그대로 돌아온다.
     */
    suspend fun upload(familyId: String, childUid: String) {
        if (!uploadMutex.tryLock()) {
            Log.d(TAG, "업로드 생략: 이전 업로드가 아직 진행 중이다")
            return
        }
        try {
            uploadLocked(familyId, childUid)
        } finally {
            uploadMutex.unlock()
        }
    }

    private suspend fun uploadLocked(familyId: String, childUid: String) {
        val dayKey = bufferDayKey
        if (dayKey == null) {
            Log.d(TAG, "업로드 생략: 오늘 확보한 점이 하나도 없다")
            return
        }
        // 상한을 넘으면 오래된 쪽을 버린다(TrailCodec.MAX_POINTS 주석 — 문서 1MB
        // 상한을 넘겨 그 날 기록이 통째로 안 올라가는 일을 막는 안전장치다).
        val points = TrailCodec.capped(buffer.toList())
        val segments = buildSegments(points)
        TrailRepository.save(
            familyId, childUid,
            TrailDoc(
                dayKey = dayKey,
                points = points.map {
                    TrailPoint(
                        lat = it.lat, lng = it.lng,
                        accuracy = it.accuracy, speed = it.speed, at = it.at,
                    )
                },
                segments = segments,
                updatedAt = System.currentTimeMillis(),
            )
        )
        Log.i(TAG, "하루 문서 반영: dayKey=$dayKey 점 ${points.size}개 구간 ${segments.size}개")
    }

    /**
     * 점 목록을 구간으로 묶고 머무름에 이름을 붙인다.
     *
     * map 의 람다는 suspend 가 아니라서 그 안에서 placeNamer.nameOf(suspend) 를
     * 부를 수 없다 — for 루프로 풀어서 buildList 로 모은다.
     */
    private suspend fun buildSegments(points: List<Fix>): List<SegmentDoc> = buildList {
        for (segment in SegmentBuilder.build(points)) {
            // 이동 구간에는 이름을 붙이지 않는다. 이동은 "어디서 어디로"가 앞뒤
            // 머무름 이름으로 이미 드러나고, 이동 중 좌표 하나를 주소로 바꿔봐야
            // 지나가던 길 이름이라 의미가 없다.
            //
            // 이름은 segment.lat/lng 가 아니라 segment.nameLat/nameLng 로 묻는다.
            // 앞의 둘은 지도에 찍는 좌표(단순 평균)고, 뒤의 둘은 오차로 가중한
            // 평균이다 — 좌표 하나를 건물 이름으로 바꾸는 일은 오차에 훨씬
            // 민감해서, 도착 순간 튄 fix 한 개가 머무름 전체에 옆 건물 이름을
            // 달아버릴 수 있다(SegmentBuilder.Segment.nameLat 주석). 저장하는
            // SegmentDoc.lat/lng 는 그대로 segment.lat/lng 다 — 화면에 찍히는
            // 위치는 하나도 안 바뀐다.
            val placeName = if (segment.type == SegmentType.STAY) {
                placeNamer.nameOf(segment.nameLat, segment.nameLng).orEmpty()
            } else {
                ""
            }
            add(
                SegmentDoc(
                    type = segment.type.name,
                    startAt = segment.startAt,
                    endAt = segment.endAt,
                    lat = segment.lat,
                    lng = segment.lng,
                    distanceMeters = segment.distanceMeters,
                    pointCount = segment.pointCount,
                    placeName = placeName,
                )
            )
        }
    }

    private companion object {
        const val TAG = "TrailUploader"
    }
}
