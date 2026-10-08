package com.kidcare.family.core

import android.content.Context
import android.util.Log
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import com.kidcare.family.logic.DayPicker
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Instant
import java.time.ZoneId

/**
 * 30일 지난 기록을 지운다. **`families/{id}.keepHistory == true` 인 가족은 건드리지 않는다.**
 *
 * ## 왜 있나
 *
 * 무료 요금제 저장 한도가 1GB 인데, 아이 하나가 하루 50~200KB 의 하루 기록을 남긴다.
 * 지우는 쪽이 없으면 100가족이면 몇 달 안에 차고, 그 순간 모든 가족의 앱이 멈춘다.
 * 위치는 민감한 정보이기도 해서 필요 이상 오래 두지 않는다(처리방침에 30일로 적는다).
 *
 * ## 개발자 가족만 영구 보관
 *
 * 두 갈래로 지킨다. 어느 하나라도 해당하면 지우지 않는다.
 *
 * 1. **이 기능이 생기기 전에 만든 가족**([KEEP_FAMILIES_CREATED_BEFORE]). 콘솔에서 표시를
 *    달기 전에 이 버전이 아이 폰에 깔려도, 그 순간 개발자 가족의 몇 달치 기록이 지워지지
 *    않게 하는 안전판이다. `createdAt` 이 없거나 0 이면 언제 만든 가족인지 모르므로 역시
 *    지우지 않는다.
 * 2. **`keepHistory == true`.** 앱을 다시 깔아 가족을 새로 만들었을 때를 위한 것이다.
 *
 * `keepHistory` 는 **Firebase 콘솔에서 사람이 직접** 켠다. 앱은 이 필드를 쓸 수 없다 —
 * 가족 문서 update 규칙이 바꿀 수 있는 필드를 `hasOnly([...])` 로 잠가 두었고 이 필드는
 * 거기 없다. 그래서 사용자가 스스로 "영구 보관"을 켜서 저장 한도를 먹을 길이 없다.
 *
 * **이 값을 서버에서 확인하지 못하면 아무것도 지우지 않는다.** 캐시로 읽으면 오프라인일 때
 * "필드 없음"으로 보일 수 있고, 지우기는 대기열에 남았다가 연결되는 순간 나간다 —
 * 영구 보관해야 할 가족의 기록이 그렇게 사라진다. 틀리는 두 방향의 대가가 비대칭이라
 * (하루 늦게 지움 vs 영영 잃음) 의심스러우면 지우지 않는다.
 *
 * ## 누가 무엇을 지우나
 *
 * 보안 규칙이 정한 대로 나눈다(규칙은 그대로다).
 * - 하루 기록(`trails`)은 아이만 쓸 수 있으므로 **아이 폰**이 지운다.
 * - 명령(`commands`)과 사건(`events`)은 보호자만 지울 수 있으므로 **보호자 폰**이 지운다.
 *
 * 하루에 한 번만 돈다. 지우는 것도 쓰기라 돌 때마다 무료 한도를 먹는다.
 */
object HistoryCleaner {

    const val KEEP_DAYS = 30L
    const val KEEP_FIELD = "keepHistory"

    private const val TAG = "HistoryCleaner"
    private const val PREFS = "kidcare_cleanup"
    private const val KEY_LAST_DAY = "last_day"
    private const val DAY_MILLIS = 24 * 60 * 60 * 1000L

    /** 한 번에 지우는 최대 개수. 오래 꺼져 있던 폰은 며칠에 걸쳐 따라잡는다. */
    private const val BATCH_LIMIT = 100L
    private const val TIMEOUT_MILLIS = 15_000L

    /** 2026-10-09 00:00 (서울). 이보다 먼저 만든 가족은 영구 보관(클래스 주석 1번). */
    private val KEEP_FAMILIES_CREATED_BEFORE =
        Instant.parse("2026-10-08T15:00:00Z").toEpochMilli()

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    /** 아이 폰: 30일 지난 하루 기록. */
    suspend fun cleanChildTrails(context: Context, familyId: String, childUid: String) {
        if (!claimToday(context)) return
        if (!shouldDelete(familyId)) return
        val zone = ZoneId.systemDefault()
        val cutoff = DayPicker.shift(DayPicker.todayKey(zone, System.currentTimeMillis()), -KEEP_DAYS)
        val trails = db.collection("families").document(familyId)
            .collection("children").document(childUid).collection("trails")
            .whereLessThan(FieldPath.documentId(), cutoff)
        deleteAll(trails, "하루 기록")
    }

    /** 보호자 폰: 30일 지난 명령과 사건. */
    suspend fun cleanGuardianSide(context: Context, familyId: String, childUids: List<String>) {
        if (!claimToday(context)) return
        if (!shouldDelete(familyId)) return
        val cutoff = System.currentTimeMillis() - KEEP_DAYS * DAY_MILLIS
        val family = db.collection("families").document(familyId)
        deleteAll(family.collection("events").whereLessThan("at", cutoff), "사건")
        childUids.forEach { uid ->
            deleteAll(
                family.collection("children").document(uid).collection("commands")
                    .whereLessThan("createdAt", cutoff),
                "명령",
            )
        }
    }

    /** 오늘 이미 돌았으면 false. 실패해도 오늘은 다시 안 돈다 — 재시도가 쓰기를 문다. */
    private fun claimToday(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val today = DayPicker.todayKey(ZoneId.systemDefault(), System.currentTimeMillis())
        if (prefs.getString(KEY_LAST_DAY, null) == today) return false
        prefs.edit().putString(KEY_LAST_DAY, today).apply()
        return true
    }

    /** 서버가 "영구 보관 아님"을 확인해 줄 때만 true. 클래스 주석의 비대칭 참고. */
    private suspend fun shouldDelete(familyId: String): Boolean {
        val family = runCatching {
            withTimeoutOrNull(TIMEOUT_MILLIS) {
                db.collection("families").document(familyId).get(Source.SERVER).await()
            }
        }.getOrNull()
        if (family == null || !family.exists()) {
            Log.i(TAG, "가족 문서를 서버에서 확인하지 못해 오늘은 지우지 않는다")
            return false
        }
        if ((family.getLong("createdAt") ?: 0L) < KEEP_FAMILIES_CREATED_BEFORE) {
            Log.i(TAG, "기록 정리 기능 이전에 만든 가족이라 지우지 않는다")
            return false
        }
        if (family.getBoolean(KEEP_FIELD) == true) {
            Log.i(TAG, "영구 보관 가족이라 지우지 않는다")
            return false
        }
        return true
    }

    private suspend fun deleteAll(query: Query, label: String) {
        val docs = runCatching {
            withTimeoutOrNull(TIMEOUT_MILLIS) {
                query.limit(BATCH_LIMIT).get(Source.SERVER).await().documents
            }
        }.onFailure { Log.w(TAG, "$label 조회 실패", it) }.getOrNull()
        if (docs.isNullOrEmpty()) return
        val batch = db.batch()
        docs.forEach { batch.delete(it.reference) }
        // 시간이 넘어도 지우기는 대기열에 남아 연결되면 나간다. 이미 서버에서 "영구 보관
        // 아님"을 확인했으므로 늦게 나가도 괜찮다.
        runCatching { withTimeoutOrNull(TIMEOUT_MILLIS) { batch.commit().await() } }
            .onFailure { Log.w(TAG, "$label 삭제 실패", it) }
        Log.i(TAG, "$label ${docs.size}건 정리")
    }
}
