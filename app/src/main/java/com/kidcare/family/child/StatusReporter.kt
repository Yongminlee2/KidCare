package com.kidcare.family.child

import com.google.firebase.firestore.FirebaseFirestore
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.core.model.PointDoc
import com.kidcare.family.logic.Fix
import kotlinx.coroutines.tasks.await

/**
 * 위치 한 점을 Firestore 두 곳에 쓴다.
 *
 *   status  — 항상 덮어쓴다. 보호자 화면의 '지금 위치'가 이걸 구독한다.
 *   points  — 계속 쌓는다. 3단계에서 구간 요약의 재료가 된다.
 *
 * status 는 설계서에는 children/{childUid}/status 하위 문서로 그려져 있지만,
 * Firestore 는 문서 아래에 바로 필드를 둘 수 있으므로 children/{childUid} 문서
 * 자체를 status 로 쓴다. 문서 하나를 아끼고 읽기도 한 번 줄어든다.
 *
 * firestore.rules 의 `match /children/{childUid}/{document=**}` 는 rules_version
 * '2' 아래에서 재귀 와일드카드가 0개 이상의 경로 세그먼트에 매치되므로(버전 1은
 * 1개 이상만 매치), children/{childUid} 문서 자체도 이 규칙의 적용을 받는다 —
 * 즉 이 set() 은 규칙에서 허용된다.
 */
class StatusReporter {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    suspend fun report(
        familyId: String,
        childUid: String,
        fix: Fix,
        battery: Int,
        charging: Boolean,
        ringerMode: String,
    ) {
        val childRef = db.collection("families").document(familyId)
            .collection("children").document(childUid)

        childRef.set(
            ChildStatusDoc(
                lat = fix.lat,
                lng = fix.lng,
                accuracy = fix.accuracy,
                at = fix.at,
                battery = battery,
                charging = charging,
                ringerMode = ringerMode,
                // 옛 필드는 그대로 계속 쓴다 — 아직 새 버전을 못 깐 보호자 폰이 있을 수
                // 있고, 이 값 하나가 없으면 그 화면은 "마지막 신호"를 아예 못 만든다.
                lastSeenAt = System.currentTimeMillis(),
                // lastSeenServerAt 은 **일부러 넘기지 않는다.** 기본값 null 인 채로
                // 나가면 Firestore 가 `FieldValue.serverTimestamp()` 로 바꿔 보내고
                // 서버가 자기 시각으로 채운다(@ServerTimestamp, ChildStatusDoc 주석).
                // 여기서 System.currentTimeMillis() 로 값을 채워 넣으면 아이 폰 시계가
                // 그대로 들어가 새 필드를 만든 이유가 사라진다. 쓰기는 여전히 한 번이다.
            )
        ).await()

        childRef.collection("points").add(
            PointDoc(
                lat = fix.lat,
                lng = fix.lng,
                accuracy = fix.accuracy,
                speed = fix.speed,
                at = fix.at,
                battery = battery,
            )
        ).await()
    }
}
