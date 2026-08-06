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
 * 한 번에 다 지우지 않고 [BATCH_LIMIT] 개씩만 지운다. 오래 앱을 안 켰다가 수천 개가
 * 쌓였을 때 한 번에 지우려다 실패하면 영원히 못 지운다 — 매일 최대 200개씩,
 * 오래된 것부터 순서대로 지워 며칠에 걸쳐서라도 결국 따라잡는다.
 */
class PointsCleaner {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    /** 지운 개수를 돌려준다. */
    suspend fun cleanOldPoints(familyId: String, childUid: String): Int {
        val cutoff = System.currentTimeMillis() - RETENTION_MILLIS
        val stale = db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("points")
            .whereLessThan("at", cutoff)
            .orderBy("at", Query.Direction.ASCENDING)
            .limit(BATCH_LIMIT)
            .get().await()

        if (stale.isEmpty) return 0

        val batch = db.batch()
        stale.documents.forEach { batch.delete(it.reference) }
        batch.commit().await()
        Log.i(TAG, "오래된 위치 점 ${stale.size()}개 삭제")
        return stale.size()
    }

    private companion object {
        const val TAG = "PointsCleaner"
        const val RETENTION_MILLIS = 30L * 24 * 60 * 60 * 1000L
        const val BATCH_LIMIT = 200L
    }
}
