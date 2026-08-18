package com.kidcare.family.guardian

import android.content.Context
import android.content.res.ColorStateList
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.kidcare.family.R
import com.kidcare.family.core.model.ScheduleDoc
import com.kidcare.family.databinding.ItemScheduleBinding

/**
 * 예약 규칙을 한 줄씩 보여준다.
 *
 * 한 줄에 동작이 셋(고치기·켬끔·삭제)이라 콜백도 셋이다. 문구 조립은 전부
 * [ScheduleText] 가 맡고 여기서는 꽂아 넣기만 한다 — [ScheduleFragment] 의
 * 확인 대화상자도 같은 문구로 규칙을 가리켜야 해서(“'평일 09:00 ~ 15:00 진동'
 * 규칙과 겹칩니다”) 조립을 두 곳에 적을 수 없다.
 */
class ScheduleAdapter(
    private val onEdit: (ScheduleDoc) -> Unit,
    private val onToggle: (ScheduleDoc, Boolean) -> Unit,
    private val onDelete: (ScheduleDoc) -> Unit,
) : ListAdapter<ScheduleDoc, ScheduleAdapter.Holder>(Diff) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Holder(
        ItemScheduleBinding.inflate(LayoutInflater.from(parent.context), parent, false)
    )

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(getItem(position))

    inner class Holder(private val binding: ItemScheduleBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(doc: ScheduleDoc) {
            val context = binding.root.context
            binding.titleText.text = context.getString(
                R.string.schedule_row_title,
                ScheduleText.daysText(context, doc.days),
                ScheduleText.rangeText(context, doc.startMinute, doc.endMinute),
            )
            val mode = ScheduleText.modeText(context, doc.mode)
            binding.detailText.text = context.getString(
                if (doc.enabled) R.string.schedule_row_detail else R.string.schedule_row_detail_off,
                mode,
            )
            // 꺼둔 규칙은 지워진 것이 아니라 잠깐 쉬는 것이다. 글자를 흐리게만 해서
            // "있긴 한데 지금은 안 도는 규칙"으로 읽히게 한다.
            binding.rowBody.alpha = if (doc.enabled) 1f else 0.5f

            // isChecked 대입이 리스너를 부르지 않도록 setOnCheckedChangeListener 가
            // 아니라 setOnClickListener 를 쓴다 — 사람이 누를 때만 불린다.
            // RecyclerView 는 줄을 재활용하므로 이 구분이 없으면 스크롤만 해도
            // 남의 규칙을 껐다 켜는 쓰기가 나간다(ControlFragment 의 잠금 스위치와
            // 같은 이유이지만, 여기서는 재활용 때문에 훨씬 잘 터진다).
            binding.enabledSwitch.setOnClickListener(null)
            binding.enabledSwitch.isChecked = doc.enabled
            binding.enabledSwitch.setOnClickListener {
                onToggle(doc, binding.enabledSwitch.isChecked)
            }

            bindSticker(doc)
            bindRibbon(doc)

            binding.rowBody.setOnClickListener { onEdit(doc) }
            binding.deleteButton.setOnClickListener { onDelete(doc) }
        }

        /** 모드마다 색과 그림이 다른 동그란 스티커. 색만으로 나누지 않는 이유는 레이아웃 주석 참고. */
        private fun bindSticker(doc: ScheduleDoc) {
            val context = binding.root.context
            val (iconRes, colorRes, softRes) = ScheduleText.modeLook(doc.mode)
            binding.modeIcon.setImageResource(iconRes)
            binding.modeIcon.imageTintList =
                ColorStateList.valueOf(ContextCompat.getColor(context, colorRes))
            binding.modeSticker.backgroundTintList =
                ColorStateList.valueOf(ContextCompat.getColor(context, softRes))
        }

        /**
         * 하루 띠를 채운다. 자정부터 자정까지를 1440분으로 펴 놓고 규칙이 도는 분만
         * 색을 준다.
         *
         * 조각이 셋인 이유는 자정 넘김 때문이다. 낮 규칙(09:00~15:00)은 가운데만 차고,
         * 밤 규칙(22:00~07:00)은 **양 끝**이 찬다 — 하루를 자른 자리가 눈에 그대로
         * 보인다. 시작과 끝이 같은 '하루 종일'은 셋 다 채운다.
         */
        private fun bindRibbon(doc: ScheduleDoc) {
            val context = binding.root.context
            val (_, colorRes, _) = ScheduleText.modeLook(doc.mode)
            val fill = ContextCompat.getColor(context, colorRes)
            val start = doc.startMinute.coerceIn(0, MINUTES_PER_DAY)
            val end = doc.endMinute.coerceIn(0, MINUTES_PER_DAY)

            // 자정을 넘거나(끝 <= 시작) 하루 종일이면 양 끝이 차고 가운데가 빈다.
            val overnight = end <= start
            val heads = if (overnight) intArrayOf(end, start - end, MINUTES_PER_DAY - start)
                        else intArrayOf(start, end - start, MINUTES_PER_DAY - end)
            val filled = if (overnight) booleanArrayOf(true, false, true)
                         else booleanArrayOf(false, true, false)
            // 시작 == 끝은 24시간 규칙이다(ScheduleResolver 와 같은 해석). 위 식으로는
            // 첫 조각이 0 이 되어 사라지므로 통째로 채운다.
            val allDay = start == end

            val views = arrayOf(binding.ribbonHead, binding.ribbonMiddle, binding.ribbonTail)
            views.forEachIndexed { i, view ->
                val params = view.layoutParams as LinearLayout.LayoutParams
                params.weight = if (allDay) (if (i == 1) 1f else 0f) else heads[i].toFloat()
                view.layoutParams = params
                val on = if (allDay) i == 1 else filled[i]
                view.setBackgroundColor(if (on) fill else android.graphics.Color.TRANSPARENT)
            }
            // 조각은 네모라 바탕의 둥근 모서리 밖으로 삐져나온다. 바탕 모양대로 자른다.
            binding.dayRibbon.clipToOutline = true
            binding.dayRibbon.alpha = if (doc.enabled) 1f else 0.45f
            binding.dayRibbon.visibility = View.VISIBLE
        }
    }

    private companion object {
        const val MINUTES_PER_DAY = 24 * 60
    }

    private object Diff : DiffUtil.ItemCallback<ScheduleDoc>() {
        override fun areItemsTheSame(old: ScheduleDoc, new: ScheduleDoc) = old.id == new.id
        override fun areContentsTheSame(old: ScheduleDoc, new: ScheduleDoc) = old == new
    }
}

/**
 * 규칙을 사람이 읽는 한국어로 옮긴다.
 *
 * [com.kidcare.family.logic] 에 두지 않은 이유: 저 패키지는 안드로이드를 몰라야 하는
 * 순수 판정 로직 자리인데(JVM 단위 테스트 대상) 이 조립은 [Context] 와 strings.xml 이
 * 있어야 한다. 화면 쪽 파일에 두는 것이 맞다.
 */
object ScheduleText {

    /**
     * child/RingerMode 와 같아야 하는 값이다. guardian 은 child 를 import 하지 않는
     * 것이 모듈 경계(설계서 §3)라 여기 다시 적는다 — 바꿀 일이 생기면
     * `child/RingerStateStore.kt` 의 `object RingerMode`, `guardian/ControlFragment`
     * 의 companion 과 **함께** 고쳐야 한다.
     */
    const val MODE_NORMAL = "normal"
    const val MODE_VIBRATE = "vibrate"
    const val MODE_SILENT = "silent"

    /** 1=월 … 7=일. [com.kidcare.family.logic.ScheduleRule.days] 와 같은 규칙이다
     *  (`java.time.DayOfWeek.value`). 인덱스는 요일값 - 1. */
    private val DAY_NAME_RES = intArrayOf(
        R.string.schedule_day_mon,
        R.string.schedule_day_tue,
        R.string.schedule_day_wed,
        R.string.schedule_day_thu,
        R.string.schedule_day_fri,
        R.string.schedule_day_sat,
        R.string.schedule_day_sun,
    )

    private val EVERYDAY = (1..7).toSet()
    private val WEEKDAYS = (1..5).toSet()
    private val WEEKEND = setOf(6, 7)

    /** "평일" / "주말" / "매일" / "월·수·금". 자주 쓰는 조합은 이름으로 부르는 편이 빨리 읽힌다. */
    fun daysText(context: Context, days: Collection<Int>): String {
        val set = days.filter { it in 1..7 }.toSet()
        return when (set) {
            emptySet<Int>() -> context.getString(R.string.schedule_days_none)
            EVERYDAY -> context.getString(R.string.schedule_days_everyday)
            WEEKDAYS -> context.getString(R.string.schedule_days_weekday)
            WEEKEND -> context.getString(R.string.schedule_days_weekend)
            else -> set.sorted().joinToString("·") { context.getString(DAY_NAME_RES[it - 1]) }
        }
    }

    fun timeText(context: Context, minuteOfDay: Int): String =
        context.getString(R.string.schedule_time_format, minuteOfDay / 60, minuteOfDay % 60)

    /**
     * 시간대 한 토막. 세 가지가 서로 다르게 읽혀야 한다.
     *
     * - 같은 날 안에서 끝남: `09:00 ~ 15:00`
     * - 자정을 넘김: `22:00 ~ 다음 날 07:00`. "22:00 ~ 07:00" 이라고만 쓰면 끝이
     *   시작보다 앞이라 부모 눈에는 잘못 넣은 값처럼 보인다. 밤 무음은 흔한 요구라
     *   (설계서 §4.3) 이 표기가 특히 중요하다.
     * - 시작과 끝이 같음: `하루 종일 (00:00부터 24시간)`. [ScheduleResolver]
     *   [com.kidcare.family.logic.ScheduleResolver] 가 이 경우를 24시간 구간으로
     *   해석하므로 화면도 그렇게 말해야 한다.
     */
    fun rangeText(context: Context, startMinute: Int, endMinute: Int): String = when {
        startMinute == endMinute ->
            context.getString(R.string.schedule_range_allday, timeText(context, startMinute))
        endMinute < startMinute -> context.getString(
            R.string.schedule_range_overnight,
            timeText(context, startMinute),
            timeText(context, endMinute),
        )
        else -> context.getString(
            R.string.schedule_range,
            timeText(context, startMinute),
            timeText(context, endMinute),
        )
    }

    /**
     * 모드 하나의 생김새: (그림, 진한 색, 연한 색).
     *
     * 색을 여기 한 곳에 모으는 이유는 같은 색이 세 자리에 나와야 하기 때문이다 —
     * 스티커 바탕, 스티커 그림, 하루 띠. 세 곳에 따로 적으면 하나를 바꿀 때 반드시
     * 하나를 빠뜨린다.
     */
    fun modeLook(mode: String): Triple<Int, Int, Int> = when (mode) {
        // 벨소리는 소리가 나는 상태라 팔레트에서 가장 따뜻한 살구빛을 준다.
        MODE_NORMAL -> Triple(R.drawable.ic_volume_up, R.color.apricot, R.color.apricot_soft)
        // 진동은 소리와 무음 사이라 중간 성격의 라벤더.
        MODE_VIBRATE -> Triple(R.drawable.ic_vibration, R.color.sky, R.color.sky_soft)
        // 무음은 조용한 상태라 가장 가라앉은 풀빛.
        MODE_SILENT -> Triple(R.drawable.ic_volume_off, R.color.grass, R.color.grass_soft)
        // 모르는 값이면 색으로 아는 척하지 않는다(modeText 와 같은 태도).
        else -> Triple(R.drawable.ic_alarm, R.color.ink_soft, R.color.line_soft)
    }

    fun modeText(context: Context, mode: String): String = when (mode) {
        MODE_NORMAL -> context.getString(R.string.schedule_mode_normal)
        MODE_VIBRATE -> context.getString(R.string.schedule_mode_vibrate)
        MODE_SILENT -> context.getString(R.string.schedule_mode_silent)
        // 셋 중 어느 것도 아닌 값이 문서에 들어 있는 경우다(이 화면으로는 만들 수
        // 없다). 셋 중 하나로 넘겨짚으면 부모가 실제와 다른 모드를 믿게 되므로,
        // 아는 척하지 않고 저장된 값을 그대로 보여준다.
        else -> mode
    }

    /** 대화상자에서 규칙 하나를 가리킬 때 쓰는 한 줄 이름. */
    fun summary(context: Context, doc: ScheduleDoc): String = context.getString(
        R.string.schedule_summary,
        daysText(context, doc.days),
        rangeText(context, doc.startMinute, doc.endMinute),
        modeText(context, doc.mode),
    )
}
