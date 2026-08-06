package com.kidcare.family.child

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import kotlinx.coroutines.tasks.await

/**
 * 30일 지난 위치 점을 지운다.
 *
 * 원래는 Cloud Function 이 매일 새벽에 하기로 했는데(설계서 §3), 무료(Spark)
 * 요금제로 가면서 Cloud Functions 를 쓰지 않게 됐다(known-issues 4). 자녀 폰은
 * 보안 규칙상 자기 데이터를 지울 수 있으므로(children/{childUid}/{document=**}
 * 쓰기가 그 아이 본인에게만 허용된다) 여기서 대신한다 — 그래서 이 클래스는
 * TrackingService(자녀 폰)에서만 부른다. 보호자 폰에서 부르면 규칙에 그대로
 * 막힌다.
 *
 * 한 번에 다 지우지 않고 [BATCH_LIMIT] 개씩 배치로 지운다 — 배치 하나가 실패해도
 * 전부를 다시 시도할 필요가 없게 하려는 것이다. 다만 하루 [BATCH_LIMIT] 개
 * 딱 한 번으로 끝내면(Fix 5 이전 방식), 아이가 하루 약 270개를 올리는 이 앱에서는
 * 지우는 속도(200/일)가 쌓이는 속도(270/일)를 못 따라잡아 30일 보관 약속이
 * 영원히 깨진다. 그래서 여기서는 한 번 부를 때 배치를 반복해서, 그 패스가
 * [BATCH_LIMIT] 개 미만을 지웠을 때(더 지울 게 없다는 뜻)까지, 또는
 * [RUN_LIMIT] 개에 닿을 때까지 계속 지운다. [RUN_LIMIT] 은 폰이 몇 달 꺼져
 * 있다가 켜져도 하루 만에 무리하게 전부 지우려다 실패하지 않도록 두는 상한이다.
 */
class PointsCleaner {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    /** 지운 개수를 돌려준다. */
    suspend fun cleanOldPoints(familyId: String, childUid: String): Int {
        val cutoff = System.currentTimeMillis() - RETENTION_MILLIS
        val collection = db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("points")

        var totalDeleted = 0
        while (totalDeleted < RUN_LIMIT) {
            val stale = collection
                .whereLessThan("at", cutoff)
                .orderBy("at", Query.Direction.ASCENDING)
                .limit(BATCH_LIMIT)
                .get().await()

            if (stale.isEmpty) break

            val batch = db.batch()
            stale.documents.forEach { batch.delete(it.reference) }
            batch.commit().await()
            totalDeleted += stale.size()

            // 이번 패스가 상한보다 적게 지웠다면 그 뒤로는 지울 게 안 남았다는
            // 뜻이다 — 굳이 빈 쿼리를 한 번 더 날릴 필요가 없다.
            if (stale.size() < BATCH_LIMIT) break
        }

        if (totalDeleted > 0) Log.i(TAG, "오래된 위치 점 ${totalDeleted}개 삭제")
        return totalDeleted
    }

    private companion object {
        const val TAG = "PointsCleaner"
        const val RETENTION_MILLIS = 30L * 24 * 60 * 60 * 1000L
        const val BATCH_LIMIT = 200L

        // 하루 한 번 부르는 호출 하나가 최악의 경우에도 이 개수를 넘어 지우지
        // 않는다(=15번의 배치). 하루 업로드량(약 270개)의 10배가 넘어 정상적인
        // 하루치 밀림은 한 번에 전부 따라잡고도 여유가 있고, 그럼에도 한 번의
        // 호출이 무한정 커지지는 않는다.
        const val RUN_LIMIT = 3000
    }
}
