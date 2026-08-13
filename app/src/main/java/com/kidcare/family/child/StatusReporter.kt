package com.kidcare.family.child

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.logic.Fix
import kotlinx.coroutines.tasks.await

/**
 * 아이 폰의 지금 상태(위치·배터리·소리 모드)를 Firestore 문서 하나에 덮어쓴다.
 *
 * **더 이상 위치가 들어올 때마다 부르지 않는다.** 부모가 '지금 위치 확인'을 눌러
 * `locate_now` 명령이 도착했을 때와, 하루 한 번 안전 업로드일 때만 부른다
 * ([TrackingService.uploadNow], docs/known-issues.md 12번). 옛 구조에서는 이 함수가
 * 하루 약 520번 불렸고, 부를 때마다 `points` 문서까지 하나씩 더 만들어 가족 하나가
 * 하루 1,100번을 썼다 — Spark 무료 한도(프로젝트 전체 하루 2만 쓰기)에서 1,000가족을
 * 담으려면 가족당 20번이어야 한다.
 *
 * 옛 `points` 하위 컬렉션 쓰기는 여기서 사라졌다. 그 자리를 하루 문서 하나
 * (`trails/{dayKey}`, [TrailUploader])가 대신한다.
 *
 * status 는 설계서에는 children/{childUid}/status 하위 문서로 그려져 있지만,
 * Firestore 는 문서 아래에 바로 필드를 둘 수 있으므로 children/{childUid} 문서
 * 자체를 status 로 쓴다. 문서 하나를 아끼고 읽기도 한 번 줄어든다.
 *
 * firestore.rules 의 `match /children/{childUid}` 블록이 이 문서를 직접 덮으며,
 * 쓰기를 그 아이 본인에게만 허용한다 — 즉 이 set() 은 규칙에서 허용된다.
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
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .set(
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
    }

    /**
     * 부모 명령으로 소리 모드만 바뀐 경우 위치 전체를 다시 올리지 않고 해당 필드만
     * 갱신한다. 명령 한 번당 쓰기 한 번이며, 부모가 관리 탭을 다시 열어도 마지막으로
     * 실제 적용된 모드를 확인할 수 있게 한다.
     */
    suspend fun reportRingerMode(familyId: String, childUid: String, ringerMode: String) {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            // 위치를 아직 한 번도 올리지 않아 status 문서가 없어도 소리 상태는
            // 확인할 수 있어야 한다. merge set은 문서가 있으면 이 필드만 바꾸고,
            // 없으면 최소 상태 문서를 만든다.
            .set(mapOf("ringerMode" to ringerMode), SetOptions.merge())
            .await()
    }
}
