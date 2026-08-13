package com.kidcare.family.guardian

import android.content.res.ColorStateList
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.core.widget.ImageViewCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.kidcare.family.R
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.databinding.ItemTimelineBinding
import com.kidcare.family.logic.Segment
import com.kidcare.family.logic.SegmentSummarizer
import com.kidcare.family.logic.SegmentType
import java.time.ZoneId

/**
 * 하루 요약을 한 줄씩 보여준다. 누르면 지도가 그 지점으로 움직인다.
 *
 * 문구 조립은 strings.xml 의 서식 문자열이 하고, 여기서는 SegmentSummarizer 가 만든
 * 조각을 꽂아 넣기만 한다 — 문구를 고칠 때 코드를 건드리지 않게 하려는 것이다.
 */
class TimelineAdapter(
    private val zone: ZoneId,
    private val onRowClick: (SegmentDoc) -> Unit,
) : ListAdapter<SegmentDoc, TimelineAdapter.Holder>(Diff) {

    private var hiddenMoveStarts: Set<Long> = emptySet()

    @Suppress("NotifyDataSetChanged")
    fun setHiddenMoveStarts(hidden: Set<Long>) {
        if (hiddenMoveStarts == hidden) return
        hiddenMoveStarts = hidden
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Holder(
        ItemTimelineBinding.inflate(LayoutInflater.from(parent.context), parent, false)
    )

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(getItem(position))

    inner class Holder(private val binding: ItemTimelineBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(doc: SegmentDoc) {
            val context = binding.root.context
            val stay = doc.type == SegmentType.STAY.name
            // SegmentSummarizer 는 logic/Segment 를 받으므로 문서를 값 객체로 옮겨 담는다.
            val segment = Segment(
                type = if (stay) SegmentType.STAY else SegmentType.MOVE,
                startAt = doc.startAt, endAt = doc.endAt,
                lat = doc.lat, lng = doc.lng,
                distanceMeters = doc.distanceMeters, pointCount = doc.pointCount,
                // 이름 좌표는 자녀 폰이 역지오코딩할 때만 쓰고 저장되지 않는다
                // (SegmentDoc 에 그 필드가 없다 — 스키마를 늘리지 않았다). 보호자
                // 화면은 이미 완성된 placeName 을 읽을 뿐이라 여기서 쓸 일이 없으므로
                // 표시 좌표를 그대로 넣는다. SegmentSummarizer 도 이 값을 안 본다.
                nameLat = doc.lat, nameLng = doc.lng,
            )

            binding.iconText.setImageResource(
                if (stay) R.drawable.ic_tab_place else R.drawable.ic_route
            )
            binding.iconText.backgroundTintList = ColorStateList.valueOf(
                ContextCompat.getColor(
                    context,
                    if (stay) R.color.apricot_soft else R.color.berry_soft,
                ),
            )
            ImageViewCompat.setImageTintList(
                binding.iconText,
                ColorStateList.valueOf(
                    ContextCompat.getColor(
                        context,
                        if (stay) R.color.apricot else R.color.berry,
                    ),
                ),
            )
            binding.titleText.text = if (stay) {
                doc.placeName.ifEmpty { context.getString(R.string.timeline_unknown_place) }
            } else {
                context.getString(
                    R.string.timeline_move_title,
                    SegmentSummarizer.distanceText(doc.distanceMeters),
                )
            }
            binding.detailText.text = context.getString(
                R.string.timeline_detail,
                SegmentSummarizer.timeRange(segment, zone),
                SegmentSummarizer.durationText(doc.endAt - doc.startAt),
            )
            val routeHidden = !stay && doc.startAt in hiddenMoveStarts
            binding.routeState.visibility = if (stay) View.GONE else View.VISIBLE
            binding.routeState.setText(
                if (routeHidden) R.string.timeline_route_hidden
                else R.string.timeline_route_visible,
            )
            binding.root.alpha = if (routeHidden) 0.62f else 1f
            binding.root.setOnClickListener { onRowClick(doc) }
        }
    }

    private object Diff : DiffUtil.ItemCallback<SegmentDoc>() {
        override fun areItemsTheSame(old: SegmentDoc, new: SegmentDoc) =
            old.startAt == new.startAt && old.type == new.type
        override fun areContentsTheSame(old: SegmentDoc, new: SegmentDoc) = old == new
    }
}
