package com.kidcare.family.guardian

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.kidcare.family.R
import com.kidcare.family.core.model.EventDoc
import com.kidcare.family.core.model.EventType
import com.kidcare.family.databinding.ItemAlertBinding
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * 알림 한 줄씩 보여준다. [PlaceAdapter] 와 같은 모양이되 누를 것이 없다 — 이 목록은
 * 읽는 것이지 고치는 것이 아니다.
 *
 * [unreadIds] 는 "이번에 화면을 열었을 때 안 읽은 상태였던" 줄들이다. 문서의
 * [EventDoc.read] 를 직접 보지 않는 이유가 여기 있다: 화면을 여는 순간
 * [AlertFragment] 가 곧바로 읽음 표시를 쓰므로, 문서만 보면 부모가 눈으로 보기도 전에
 * 살구빛이 전부 사라진다. 무엇이 새로 온 것인지 보여주는 것이 이 색의 유일한 목적이다.
 */
class AlertAdapter : ListAdapter<EventDoc, AlertAdapter.Holder>(Diff) {

    private var unreadIds: Set<String> = emptySet()

    /** 강조할 줄이 바뀌면 목록을 다시 그린다. 줄 수가 적어 통째로 다시 그려도 된다. */
    @Suppress("NotifyDataSetChanged")
    fun setUnread(ids: Set<String>) {
        if (unreadIds == ids) return
        unreadIds = ids
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Holder(
        ItemAlertBinding.inflate(LayoutInflater.from(parent.context), parent, false)
    )

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(getItem(position))

    inner class Holder(private val binding: ItemAlertBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(doc: EventDoc) {
            val context = binding.root.context
            binding.titleText.text = AlertText.line(context, doc)
            binding.eventIcon.setImageResource(AlertText.icon(doc))

            // detail 은 Task 7 이 채우는 자리다(배터리 몇 %, 어떤 권한이 꺼졌는지).
            // 비어 있으면 줄 자체를 없앤다 — 빈 줄이 남으면 줄 높이만 들쭉날쭉해진다.
            val hasDetail = doc.detail.isNotBlank()
            binding.detailText.visibility = if (hasDetail) View.VISIBLE else View.GONE
            binding.detailText.text = doc.detail

            val unread = doc.id in unreadIds
            binding.root.setCardBackgroundColor(
                ContextCompat.getColor(
                    context,
                    if (unread) R.color.apricot_soft else R.color.paper_card,
                )
            )
        }
    }

    private object Diff : DiffUtil.ItemCallback<EventDoc>() {
        override fun areItemsTheSame(old: EventDoc, new: EventDoc) = old.id == new.id
        override fun areContentsTheSame(old: EventDoc, new: EventDoc) = old == new
    }
}

/**
 * 사건 문서를 부모가 읽는 한국어 한 줄로 옮긴다. [PlaceText]·[ScheduleText] 와 같은
 * 자리에 같은 이유로 둔다 — `logic` 은 안드로이드를 몰라야 하는데 이 조립은 [Context]
 * 와 strings.xml 이 필요하다.
 *
 * 목록과 알림줄이 **같은 함수**를 쓴다([AlertService.postAlert]). 두 곳이 다른 문장을
 * 쓰면 부모는 알림을 누르고 들어와서 같은 사건을 못 찾는다.
 */
object AlertText {

    // java.time 은 minSdk 26 에서 그대로 쓸 수 있고 SimpleDateFormat 과 달리 스레드
    // 안전하다. 'a h시 m분' 의 한글은 패턴 문자(A-Z,a-z)가 아니라 그대로 찍힌다.
    private val timeFormat: DateTimeFormatter =
        DateTimeFormatter.ofPattern("a h시 m분", Locale.KOREA)
    private val dateTimeFormat: DateTimeFormatter =
        DateTimeFormatter.ofPattern("M월 d일 a h시 m분", Locale.KOREA)

    /** `🏫 학교에 도착했어요 · 오후 3시 12분` */
    fun line(context: Context, doc: EventDoc, nowMillis: Long = System.currentTimeMillis()): String =
        context.getString(R.string.alert_row, title(context, doc), timeText(doc.at, nowMillis))

    fun title(context: Context, doc: EventDoc): String = when (doc.type) {
        EventType.PLACE_ENTER -> context.getString(R.string.alert_place_enter, placeName(context, doc))
        EventType.PLACE_EXIT -> context.getString(R.string.alert_place_exit, placeName(context, doc))
        EventType.LOW_BATTERY -> context.getString(R.string.alert_low_battery)
        EventType.PERMISSION_OFF -> context.getString(R.string.alert_permission_off)
        EventType.SIGNAL_LOST -> context.getString(R.string.alert_signal_lost)
        EventType.COMMAND_FAILED -> context.getString(R.string.alert_command_failed)
        // 규칙이 type 을 값 목록으로 잠그지 않으므로(EventType 주석) 모르는 값이 올 수
        // 있다. 줄을 통째로 버리지 않는 이유: 뜻은 몰라도 "무슨 일이 언제 있었다"는
        // 사실은 남는데, 버리면 부모 화면에서 그 사건이 아예 없던 일이 된다.
        else -> context.getString(R.string.alert_unknown)
    }

    /** UI-only icon mapping; event wording and delivery behavior remain unchanged. */
    fun icon(doc: EventDoc): Int = when (doc.type) {
        EventType.PLACE_ENTER -> R.drawable.ic_tab_place
        EventType.PLACE_EXIT -> R.drawable.ic_route
        EventType.LOW_BATTERY -> R.drawable.ic_battery
        EventType.PERMISSION_OFF -> R.drawable.ic_shield_alert
        EventType.SIGNAL_LOST -> R.drawable.ic_signal_off
        EventType.COMMAND_FAILED -> R.drawable.ic_error
        else -> R.drawable.ic_tab_alert
    }

    /**
     * 오늘이면 시각만, 아니면 날짜까지. 규칙이 `at` 을 하루 창으로 묶으므로 대부분
     * 오늘이지만, 자정을 막 넘긴 새벽에 어제 저녁 사건을 보는 경우가 실제로 있다 —
     * 그때 시각만 보이면 부모는 그 일이 방금 일어난 줄로 읽는다.
     */
    fun timeText(atMillis: Long, nowMillis: Long = System.currentTimeMillis()): String {
        val zone = ZoneId.systemDefault()
        val at = Instant.ofEpochMilli(atMillis).atZone(zone)
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        return if (at.toLocalDate() == now.toLocalDate()) {
            timeFormat.format(at)
        } else {
            dateTimeFormat.format(at)
        }
    }

    /** 장소 이름이 비어 있는 옛 문서를 위한 물러섬. 타임라인의 같은 처리와 문구를 맞춘다. */
    private fun placeName(context: Context, doc: EventDoc): String =
        doc.placeName.ifBlank { context.getString(R.string.timeline_unknown_place) }
}
