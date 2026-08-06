package com.kidcare.family.guardian

import android.view.LayoutInflater
import android.view.ViewGroup
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
            )

            binding.iconText.text = context.getString(
                if (stay) R.string.timeline_icon_stay else R.string.timeline_icon_move
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
            binding.root.setOnClickListener { onRowClick(doc) }
        }
    }

    private object Diff : DiffUtil.ItemCallback<SegmentDoc>() {
        override fun areItemsTheSame(old: SegmentDoc, new: SegmentDoc) =
            old.startAt == new.startAt && old.type == new.type
        override fun areContentsTheSame(old: SegmentDoc, new: SegmentDoc) = old == new
    }
}
