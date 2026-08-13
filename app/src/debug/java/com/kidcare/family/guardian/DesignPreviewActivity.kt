package com.kidcare.family.guardian

import android.graphics.PointF
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.MarginLayoutParams
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.kidcare.family.R
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.databinding.FragmentMapTimelineBinding
import com.kidcare.family.logic.DayPicker
import com.naver.maps.geometry.LatLng
import com.naver.maps.geometry.LatLngBounds
import com.naver.maps.map.CameraAnimation
import com.naver.maps.map.CameraUpdate
import com.naver.maps.map.NaverMap
import com.naver.maps.map.OnMapReadyCallback
import com.naver.maps.map.overlay.CircleOverlay
import com.naver.maps.map.overlay.Marker
import com.naver.maps.map.overlay.OverlayImage
import java.time.ZoneId
import java.time.ZonedDateTime

/** Debug-only deterministic screen used for design comparison without touching Firebase. */
class DesignPreviewActivity : AppCompatActivity(), OnMapReadyCallback {

    private lateinit var binding: FragmentMapTimelineBinding
    private var naverMap: NaverMap? = null
    private var routeOverlay: GradientRouteOverlay? = null
    private var expanded = false
    private val zone = ZoneId.systemDefault()
    private var dayKey = DayPicker.todayKey(zone, System.currentTimeMillis())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = FragmentMapTimelineBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.mapView.onCreate(savedInstanceState)

        val baseTopMargin = (binding.statusCard.layoutParams as MarginLayoutParams).topMargin
        ViewCompat.setOnApplyWindowInsetsListener(binding.statusCard) { view, insets ->
            val top = insets.getInsets(WindowInsetsCompat.Type.systemBars()).top
            view.updateLayoutParams<MarginLayoutParams> { topMargin = baseTopMargin + top }
            insets
        }

        binding.childName.text = "하린"
        binding.statusBar.text = "배터리 83%\n방금 전 기준"
        binding.locateProgress.visibility = View.GONE
        binding.timelineList.layoutManager = LinearLayoutManager(
            this, LinearLayoutManager.HORIZONTAL, false,
        )
        val adapter = TimelineAdapter(zone) { focusOn(it.lat, it.lng) }
        binding.timelineList.adapter = adapter
        adapter.submitList(previewSegments())
        binding.timelineEmpty.visibility = View.GONE
        binding.routeSummary.text = getString(R.string.timeline_summary_today, "1.1km")
        renderDay()
        renderPanel()

        binding.timelineToggleButton.setOnClickListener {
            expanded = !expanded
            renderPanel()
        }
        binding.prevDayButton.setOnClickListener { dayKey = DayPicker.shift(dayKey, -1); renderDay() }
        binding.nextDayButton.setOnClickListener { dayKey = DayPicker.shift(dayKey, 1); renderDay() }
        binding.statusDetails.setOnClickListener {
            MaterialAlertDialogBuilder(this)
                .setTitle(R.string.map_battery_info_title)
                .setMessage(R.string.map_battery_info_message)
                .setPositiveButton(R.string.map_battery_info_confirm, null)
                .show()
        }

        binding.mapView.getMapAsync(this)
    }

    override fun onMapReady(map: NaverMap) {
        naverMap = map
        map.uiSettings.apply {
            isZoomControlEnabled = false
            isLocationButtonEnabled = false
            isScaleBarEnabled = false
            logoGravity = Gravity.START or Gravity.BOTTOM
        }
        updateLogoMargin()

        val points = previewRoute()
        CircleOverlay(points.last(), 42.0).apply {
            color = 0x269B7DE2
            outlineColor = 0x669B7DE2
            outlineWidth = dp(2)
            this.map = map
        }
        routeOverlay = GradientRouteOverlay(this, listOf(points)).also { it.attach(map) }
        Marker().apply {
            icon = OverlayImage.fromBitmap(ChildMarkerFactory.create(this@DesignPreviewActivity))
            anchor = PointF(0.5f, 1f)
            position = points.last()
            this.map = map
        }
        map.moveCamera(CameraUpdate.scrollAndZoomTo(LatLng(37.5668, 126.9744), 15.4))
    }

    private fun renderPanel() {
        binding.timelineContent.visibility = if (expanded) View.VISIBLE else View.GONE
        binding.timelineToggleButton.setText(
            if (expanded) R.string.timeline_collapse else R.string.timeline_view_records,
        )
        binding.timelineToggleButton.contentDescription = getString(
            if (expanded) R.string.timeline_collapse else R.string.timeline_expand,
        )
        binding.locateButton.updateLayoutParams<FrameLayout.LayoutParams> {
            bottomMargin = dp(if (expanded) 320 else 150)
        }
        binding.liveTrackingButton.updateLayoutParams<FrameLayout.LayoutParams> {
            bottomMargin = dp(if (expanded) 320 else 150)
        }
        updateLogoMargin()
        if (expanded) binding.mapView.post { fitRoute() }
    }

    private fun updateLogoMargin() {
        naverMap?.uiSettings?.setLogoMargin(dp(14), 0, 0, dp(if (expanded) 326 else 136))
    }

    private fun fitRoute() {
        val map = naverMap ?: return
        val bounds = LatLngBounds.Builder().apply { previewRoute().forEach { include(it) } }.build()
        map.moveCamera(
            CameraUpdate.fitBounds(bounds, dp(48), dp(112), dp(48), dp(340))
                .animate(CameraAnimation.Easing, 350),
        )
    }

    private fun renderDay() {
        binding.dayHeader.text = DayPicker.headerText(dayKey, zone, System.currentTimeMillis())
        binding.nextDayButton.isEnabled =
            !DayPicker.isFuture(DayPicker.shift(dayKey, 1), zone, System.currentTimeMillis())
    }

    private fun focusOn(lat: Double, lng: Double) {
        naverMap?.moveCamera(CameraUpdate.scrollAndZoomTo(LatLng(lat, lng), 18.0))
    }

    private fun previewSegments(): List<SegmentDoc> {
        val start = ZonedDateTime.now(zone).withHour(8).withMinute(20).withSecond(0)
            .toInstant().toEpochMilli()
        return listOf(
            SegmentDoc("STAY", start, start + 90 * 60_000, 37.5547, 126.9707, placeName = "△△초등학교"),
            SegmentDoc("MOVE", start + 90 * 60_000, start + 130 * 60_000, 37.5655, 126.9740, 1_100.0, 120),
            SegmentDoc("STAY", start + 130 * 60_000, start + 180 * 60_000, 37.5788, 126.9770, placeName = "○○학원"),
        )
    }

    private fun previewRoute(): List<LatLng> = listOf(
        LatLng(37.5547, 126.9707),
        LatLng(37.5570, 126.9710),
        LatLng(37.5600, 126.9721),
        LatLng(37.5630, 126.9742),
        LatLng(37.5665, 126.9740),
        LatLng(37.5700, 126.9750),
        LatLng(37.5733, 126.9764),
        LatLng(37.5760, 126.9761),
        LatLng(37.5788, 126.9770),
    )

    override fun onStart() {
        super.onStart()
        binding.mapView.onStart()
    }

    override fun onResume() {
        super.onResume()
        binding.mapView.onResume()
    }

    override fun onPause() {
        binding.mapView.onPause()
        super.onPause()
    }

    override fun onStop() {
        binding.mapView.onStop()
        super.onStop()
    }

    override fun onLowMemory() {
        binding.mapView.onLowMemory()
        super.onLowMemory()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        binding.mapView.onSaveInstanceState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        routeOverlay?.remove()
        binding.mapView.onDestroy()
        super.onDestroy()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
