package com.kidcare.family.guardian

import android.content.Context
import android.view.LayoutInflater
import android.view.ViewGroup
import android.content.res.ColorStateList
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.kidcare.family.R
import com.kidcare.family.core.model.PlaceDoc
import com.kidcare.family.databinding.ItemPlaceBinding
import kotlin.math.roundToInt

/**
 * 장소를 한 줄씩 보여준다. [ScheduleAdapter] 와 같은 모양이되 켬/끔 스위치가 없다
 * (그 이유는 item_place.xml 주석).
 *
 * 문구 조립은 전부 [PlaceText] 가 맡는다 — [PlaceFragment] 의 삭제 확인 대화상자도
 * 같은 이름으로 장소를 가리켜야 해서 조립을 두 곳에 적을 수 없다.
 */
class PlaceAdapter(
    private val onEdit: (PlaceDoc) -> Unit,
    private val onDelete: (PlaceDoc) -> Unit,
) : ListAdapter<PlaceDoc, PlaceAdapter.Holder>(Diff) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Holder(
        ItemPlaceBinding.inflate(LayoutInflater.from(parent.context), parent, false)
    )

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(getItem(position))

    inner class Holder(private val binding: ItemPlaceBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(doc: PlaceDoc) {
            val context = binding.root.context
            // 이름은 첫 줄에 혼자 둔다. 예전에는 "학교 · 반경 200m"를 한 줄에 넣었는데,
            // 긴 이름에서 반경이 밀려 잘렸다. 예약 줄과 같은 규칙이다 — 부모가 찾을 때
            // 먼저 보는 것이 이름이다.
            binding.titleText.text = doc.name
            binding.detailText.text = context.getString(
                R.string.place_row_detail,
                PlaceText.notifyText(context, doc),
                PlaceText.radiusMeters(doc),
            )
            bindSticker(doc)
            // 알림을 둘 다 꺼둔 장소는 지워진 것이 아니라 잠깐 쉬는 것이다. 꺼둔 예약
            // 규칙과 같은 방식으로 흐리게만 해서 "있긴 한데 지금은 안 우는 장소"로
            // 읽히게 한다.
            binding.rowBody.alpha = if (doc.notifyEnter || doc.notifyExit) 1f else 0.5f

            binding.rowBody.setOnClickListener { onEdit(doc) }
            binding.deleteButton.setOnClickListener { onDelete(doc) }
        }

        /**
         * 장소 이름의 첫 글자를 색 동그라미에 넣는다.
         *
         * 핀 그림 하나를 다섯 줄에 똑같이 반복하는 것보다 훨씬 빨리 구분된다 —
         * 목록을 훑는 부모가 찾는 것은 "장소"가 아니라 "학교"다. 색은 문서 ID 로
         * 정하므로 목록 순서가 바뀌어도 같은 장소는 같은 색을 유지한다. 위치로
         * 정하면 하나를 지웠을 때 아래 것들의 색이 전부 밀린다.
         */
        private fun bindSticker(doc: PlaceDoc) {
            val context = binding.root.context
            val letter = doc.name.trim().firstOrNull()?.toString().orEmpty()
            val key = doc.id.ifEmpty { doc.name }
            val (strong, soft) = STICKER_COLORS[
                Math.floorMod(key.hashCode(), STICKER_COLORS.size)
            ]
            binding.placeSticker.text = letter
            binding.placeSticker.setTextColor(ContextCompat.getColor(context, strong))
            binding.placeSticker.backgroundTintList =
                ColorStateList.valueOf(ContextCompat.getColor(context, soft))
        }
    }

    private companion object {
        /** (진한 색, 연한 색) 짝. 앱 팔레트에서 서로 잘 구분되는 넷만 골랐다. */
        val STICKER_COLORS = listOf(
            R.color.sky to R.color.sky_soft,
            R.color.apricot to R.color.apricot_soft,
            R.color.grass to R.color.grass_soft,
            R.color.berry_ink to R.color.berry_soft,
        )
    }

    private object Diff : DiffUtil.ItemCallback<PlaceDoc>() {
        override fun areItemsTheSame(old: PlaceDoc, new: PlaceDoc) = old.id == new.id
        override fun areContentsTheSame(old: PlaceDoc, new: PlaceDoc) = old == new
    }
}

/**
 * 장소를 사람이 읽는 한국어로 옮긴다. [ScheduleText] 와 같은 자리에 같은 이유로 둔다 —
 * `logic` 패키지는 안드로이드를 몰라야 하는데 이 조립은 [Context] 와 strings.xml 이 필요하다.
 */
object PlaceText {

    /**
     * 반경은 문서에 Double 로 있지만(지오펜스 API 가 실수를 받는다) 화면에는 정수로만
     * 보여준다. 슬라이더가 50m 단위라 소수점이 나올 일이 없고, 혹시 손으로 넣은 문서가
     * 있어도 "반경 200.00001m"은 부모에게 아무 뜻이 없다.
     */
    fun radiusMeters(doc: PlaceDoc): Int = doc.radiusMeters.roundToInt()

    /** `도착·이탈 알림` / `도착 알림만` / `이탈 알림만` / `알림 꺼둠`. */
    fun notifyText(context: Context, doc: PlaceDoc): String = when {
        doc.notifyEnter && doc.notifyExit -> context.getString(R.string.place_notify_both)
        doc.notifyEnter -> context.getString(R.string.place_notify_enter)
        doc.notifyExit -> context.getString(R.string.place_notify_exit)
        else -> context.getString(R.string.place_notify_none)
    }

    /** 대화상자에서 장소 하나를 가리킬 때 쓰는 한 줄 이름. */
    fun summary(context: Context, doc: PlaceDoc): String =
        context.getString(R.string.place_summary, doc.name, radiusMeters(doc))
}
