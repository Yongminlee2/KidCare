package com.kidcare.family.child

import android.util.Log
import com.kidcare.family.core.SegmentRepository
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.logic.Fix
import com.kidcare.family.logic.SegmentBuilder
import com.kidcare.family.logic.SegmentType
import kotlinx.coroutines.sync.Mutex
import java.time.Instant
import java.time.ZoneId

/**
 * 오늘치 위치 점을 읽어 구간으로 묶고 Firestore 에 반영한다.
 *
 * 위치 한 점이 올라갈 때마다 부르지 않는다 — 하루 점을 매번 다시 읽으면 Firestore
 * 읽기가 점 개수의 제곱으로 늘어난다. [TrackingService] 가 일정 간격으로만 부른다.
 *
 * 그것만으로는 부족하다: 부를 때마다 [SegmentRepository.pointsOfDay] 로 하루 전체를
 * 매번 다시 읽으면, 하루 안에서 재계산이 반복될수록(하루 최대 수십~백여 회) 누적
 * 읽기 횟수가 삼각수로 자라 Spark 무료 한도(하루 50,000 읽기, 프로젝트 전체 공유)를
 * 태울 수 있다(리뷰에서 실측 추정 하루 1만~3만6천). 그래서 이 클래스가 [onUploaded]
 * 로 자신이 실제로 올린 점을 메모리에 직접 쌓아 두고, Firestore 읽기는 이 서비스
 * 인스턴스가 살아있는 동안 그 날 딱 한 번(버퍼가 비어 있거나 날짜가 바뀌었을 때)만
 * 한다. 그 뒤로는 재계산이 몇 번을 돌든 추가 읽기가 없다.
 */
class SegmentUploader(
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val placeNamer: PlaceNamer = PlaceNamer(),
) {

    /** 이 서비스 인스턴스가 지금까지 확보한 오늘 점들. */
    private val buffer = mutableListOf<Fix>()

    // Fix 4: TrackingService 는 lastSegmentRebuildAt 을 "부르기 전"에 갱신해 다음
    // 예약이 겹치는 것만 막는다 — 이미 시작된 호출이 실제로 얼마나 오래 도는지는
    // 모른다. PlaceNamer 타임아웃(점당 최대 5초)이 여러 번 겹치거나 Firestore 가
    // 느리면 한 번의 rebuildToday 가 15분(다음 예약 간격)을 넘길 수 있고, 그러면
    // 두 번째 호출이 첫 번째가 끝나기 전에 시작된다. 둘 다 replaceSegmentsOfDay 로
    // 같은 하루를 통째로 갈아끼우는데, 두 번째가 삭제 대상 목록을 첫 번째의 쓰기가
    // 반영되기 전에 읽으면 그 날에 구간 두 벌이 겹쳐 쌓인다(타임라인 중복 행, 경로선
    // 두 겹, DiffUtil 키 충돌). tryLock 으로 "이미 도는 중이면 이번 호출은 건너뛴다"
    // 만 막는다 — Mutex.lock()(대기)을 쓰면 두 번째가 큐에 쌓였다가 뒤늦게 또
    // 실행되는데, 그건 이미 최신 상태를 반영한 뒤에 하는 불필요한 재계산일 뿐이다.
    private val rebuildMutex = Mutex()

    /**
     * [buffer] 가 어느 날짜의 점들인지. null 이면(서비스가 막 떴을 때) 아직 한 번도
     * 채워진 적이 없다는 뜻이라 rebuildToday 가 반드시 한 번은 Firestore 를 읽는다.
     */
    private var bufferedDayKey: String? = null

    /**
     * 업로드에 성공한 점만 버퍼에 쌓는다.
     *
     * LocationFilter 가 거절한 점(SKIP_TOO_CLOSE/REJECT_INACCURATE/REJECT_IMPOSSIBLE)은
     * 애초에 Firestore 에 안 올라가므로 pointsOfDay 로도 절대 안 읽힌다 — 여기서도
     * 넣으면 버퍼가 실제 저장된 것과 어긋난다. [TrackingService] 는 fix 를 받을
     * 때마다가 아니라 reporter.report(...) 가 성공한 뒤(lastUploaded 를 갱신하는
     * 바로 그 자리)에만 이 함수를 부른다 — decide() 가 UPLOAD 를 준 것 중에서도
     * 실제 Firestore 쓰기가 성공한 것만 들어온다.
     *
     * 날짜가 바뀌는 것은 여기서 신경 쓰지 않는다. 자정을 걸쳐 버퍼에 어제·오늘 점이
     * 섞여도, 다음 rebuildToday 호출이 dayKey 불일치를 보고 버퍼를 통째로 비운 뒤
     * 오늘 범위만 다시 읽어 오므로 결국 올바른 상태로 정리된다.
     */
    fun onUploaded(fix: Fix) {
        buffer += fix
    }

    suspend fun rebuildToday(familyId: String, childUid: String) {
        if (!rebuildMutex.tryLock()) {
            Log.d(TAG, "구간 재계산 생략: 이전 재계산이 아직 진행 중이다")
            return
        }
        try {
            rebuildTodayLocked(familyId, childUid)
        } finally {
            rebuildMutex.unlock()
        }
    }

    private suspend fun rebuildTodayLocked(familyId: String, childUid: String) {
        val now = System.currentTimeMillis()
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val dayStart = today.atStartOfDay(zone).toInstant().toEpochMilli()
        // 다음 날 자정까지를 오늘로 본다. 여기에 고정 24시간(예: DAY_MILLIS 상수)을
        // 더하는 방식은 서머타임이 있는 시간대에서 틀린다 — 봄에는 하루가 23시간이라
        // 다음 날 새벽 점까지 오늘 범위에 끌려 들어와 같은 점이 두 dayKey 에 겹쳐
        // 쓰이고, 가을에는 하루가 25시간이라 마지막 한 시간이 어느 재계산의 범위에도
        // 안 걸려 영영 빠진다. 지금은 zone 이 Asia/Seoul(서머타임 없음)이라 우연히
        // 안 터질 뿐이므로, 반드시 달력에서 다음 날 자정을 구해야 여행 등으로 시간대가
        // 바뀌어도 안전하다.
        val dayEnd = today.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        val dayKey = SegmentRepository.dayKeyOf(now, zone)

        if (buffer.isEmpty() || dayKey != bufferedDayKey) {
            // 버퍼가 비어 있다(서비스가 막 떠서 아직 한 번도 안 채워졌다) 거나 날짜가
            // 넘어갔다(자정을 지났거나 서비스가 전날부터 떠 있었다) — 이 두 경우에만
            // Firestore 를 읽는다. 재시작 전에 이미 올라가 있던 점도 이 한 번의 읽기로
            // 다시 확보된다. 그 외에는 이 인스턴스가 onUploaded 로 직접 쌓아 온 값을
            // 그대로 쓰고 추가 읽기를 하지 않는다.
            buffer.clear()
            buffer += SegmentRepository.pointsOfDay(familyId, childUid, dayStart, dayEnd)
            bufferedDayKey = dayKey
        }

        // 버퍼(=지금 우리가 아는 오늘 점 전부)를 먼저 보고 판단한다. 옛 코드는
        // pointsOfDay 를 무조건 부른 뒤에야 개수를 봤는데, 그러면 하루 시작처럼
        // 점이 1개뿐인 상황에서도 매번 읽기 비용을 이미 다 치른 뒤였다. 지금은
        // 바로 위 조건에서 이미 필요한 경우에만 읽었으므로, 이 검사는 새 읽기를
        // 유발하지 않고 그저 "지금 가진 것으로 구간을 만들 수 있는가"만 본다.
        if (buffer.size < 2) {
            Log.d(TAG, "구간 계산 생략: 오늘 점이 ${buffer.size}개뿐이다")
            return
        }

        // map 의 람다는 suspend 가 아니라서 그 안에서 placeNamer.nameOf(suspend) 를
        // 부를 수 없다 — for 루프로 풀어서 buildList 로 모은다.
        val docs = buildList {
            for (segment in SegmentBuilder.build(buffer)) {
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
                        dayKey = dayKey,
                    )
                )
            }
        }
        SegmentRepository.replaceSegmentsOfDay(familyId, childUid, dayKey, docs)
        Log.i(TAG, "구간 ${docs.size}개 반영 완료: dayKey=$dayKey 점 ${buffer.size}개")
    }

    private companion object {
        const val TAG = "SegmentUploader"
    }
}
