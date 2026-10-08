package com.kidcare.family.child

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.firestore.FirebaseFirestore
import com.kidcare.family.R
import com.kidcare.family.logic.DayPicker
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date

/**
 * 보호자가 아이 위치를 받아 갈 때마다 **아이 폰에 알린다** — 누가, 언제, 왜.
 *
 * 위치정보법 제19조 제3항: 개인위치정보를 지정한 제3자에게 제공하면 "매회 개인위치정보
 * 주체에게 제공받는 자, 제공일시 및 제공목적을 즉시 통보"해야 한다. 이 앱의 제3자는
 * 보호자이고, 제공하는 순간은 '지금 위치 확인'과 '실시간 보기'다. 목적은 하나뿐이라
 * (아이의 안전) 문구에 함께 적는다.
 *
 * 알림을 하나만 두고 덮어쓴다(같은 ID). 보호자가 하루 다섯 번 확인하면 알림 다섯 개가
 * 쌓이는 대신 "오늘 5번 · 마지막 14:32" 한 줄이 된다. 소리·진동은 없다 — 알리는 것이
 * 목적이지 아이를 놀라게 하는 것이 아니다.
 *
 * 서버에 아무것도 쓰지 않는다. 보호자 이름을 모를 때만 멤버 문서를 한 번 읽고,
 * 프로세스가 살아 있는 동안 기억한다.
 */
class LocationShareNotice(private val context: Context) {

    enum class Kind { LOCATE, LIVE }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val names = HashMap<String, String>()

    suspend fun show(familyId: String, requestedBy: String, kind: Kind) {
        try {
            val who = nameOf(familyId, requestedBy)
            val today = DayPicker.todayKey(ZoneId.systemDefault(), System.currentTimeMillis())
            val count =
                if (prefs.getString(KEY_DAY, null) == today) prefs.getInt(KEY_COUNT, 0) + 1 else 1
            prefs.edit().putString(KEY_DAY, today).putInt(KEY_COUNT, count).apply()

            val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())
            val title = context.getString(
                if (kind == Kind.LIVE) R.string.location_shared_live_title
                else R.string.location_shared_title,
                who,
            )
            val text = context.getString(R.string.location_shared_text, time, count)
            ensureChannel()
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOnlyAlertOnce(true)
                .build()
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (e: CancellationException) {
            throw e
        } catch (e: SecurityException) {
            // 알림 권한이 꺼져 있다. 위치 공유 상시 알림도 같은 권한이라 권한 화면이 다시 묻는다.
            Log.w(TAG, "알림 권한이 없어 위치 확인 알림을 못 띄웠다", e)
        } catch (e: Exception) {
            Log.w(TAG, "위치 확인 알림 실패", e)
        }
    }

    /** 보호자 표시 이름. 비었거나(기본값은 빈칸이다) 못 읽으면 "보호자". */
    private suspend fun nameOf(familyId: String, uid: String): String {
        val fallback = context.getString(R.string.guardian_default_name)
        if (uid.isBlank()) return fallback
        names[uid]?.let { return it }
        val name = runCatching {
            withTimeoutOrNull(NAME_TIMEOUT_MILLIS) {
                FirebaseFirestore.getInstance().collection("families").document(familyId)
                    .collection("members").document(uid).get().await().getString("displayName")
            }
        }.getOrNull()?.trim().orEmpty()
        if (name.isEmpty()) return fallback
        names[uid] = name
        return name
    }

    private fun ensureChannel() {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.location_shared_channel),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private companion object {
        const val TAG = "LocationShareNotice"
        const val CHANNEL_ID = "location_shared"
        const val NOTIFICATION_ID = 1201
        const val PREFS = "kidcare_location_notice"
        const val KEY_DAY = "day"
        const val KEY_COUNT = "count"
        const val NAME_TIMEOUT_MILLIS = 5_000L
    }
}
