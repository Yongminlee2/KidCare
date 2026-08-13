package com.kidcare.family.guardian

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PointF
import androidx.core.content.ContextCompat
import com.kidcare.family.R
import com.naver.maps.geometry.LatLng
import com.naver.maps.map.NaverMap
import com.naver.maps.map.overlay.Marker
import com.naver.maps.map.overlay.MultipartPathOverlay
import com.naver.maps.map.overlay.OverlayImage
import kotlin.math.ceil
import kotlin.math.min

/**
 * 네이버 지도 위에 이동 경로를 살구색→분홍색→라벤더색 리본으로 표시한다.
 *
 * 경로점 하나마다 Overlay를 만들면 하루 2,000점에서 지도가 무거워진다. 네이버의
 * [MultipartPathOverlay] 하나를 최대 32개 색상 파트로 나눠 같은 그라데이션을 유지한다.
 */
class GradientRouteOverlay(
    context: Context,
    legs: List<List<LatLng>>,
) {
    private val density = context.resources.displayMetrics.density
    private val apricot = ContextCompat.getColor(context, R.color.route_apricot)
    private val pink = ContextCompat.getColor(context, R.color.route_pink)
    private val lavender = ContextCompat.getColor(context, R.color.route_lavender)
    private val halo = ContextCompat.getColor(context, R.color.route_halo)

    private val path: MultipartPathOverlay
    private val beads: List<Marker>

    init {
        val routeParts = buildParts(legs.filter { it.size >= 2 })
        path = MultipartPathOverlay(
            routeParts.map { it.coords },
            routeParts.map { part ->
                val color = colorAt(part.fraction)
                MultipartPathOverlay.ColorPart(color, halo, color, halo)
            },
        ).apply {
            width = (8f * density).toInt()
            outlineWidth = (4f * density).toInt()
            globalZIndex = ROUTE_Z_INDEX
        }

        val allPoints = legs.flatten()
        val beadIndexes = listOf(
            0,
            allPoints.lastIndex / 3,
            allPoints.lastIndex * 2 / 3,
            allPoints.lastIndex,
        ).distinct()
        beads = beadIndexes.mapIndexed { order, index ->
            val fraction = if (beadIndexes.size == 1) 0f else order.toFloat() / beadIndexes.lastIndex
            Marker().apply {
                position = allPoints[index]
                icon = OverlayImage.fromBitmap(beadBitmap(colorAt(fraction)))
                anchor = PointF(0.5f, 0.5f)
                globalZIndex = ROUTE_BEAD_Z_INDEX
            }
        }
    }

    fun attach(map: NaverMap) {
        path.map = map
        beads.forEach { it.map = map }
    }

    fun remove() {
        path.map = null
        beads.forEach { it.map = null }
    }

    private fun buildParts(legs: List<List<LatLng>>): List<RoutePart> {
        val totalEdges = legs.sumOf { it.lastIndex }.coerceAtLeast(1)
        val chunkEdges = ceil(totalEdges / MAX_COLOR_PARTS.toDouble()).toInt().coerceAtLeast(1)
        val result = mutableListOf<RoutePart>()
        var completedEdges = 0

        legs.forEach { leg ->
            var firstEdge = 0
            while (firstEdge < leg.lastIndex) {
                val lastEdgeExclusive = min(firstEdge + chunkEdges, leg.lastIndex)
                val midpoint = completedEdges + (firstEdge + lastEdgeExclusive) / 2f
                result += RoutePart(
                    coords = leg.subList(firstEdge, lastEdgeExclusive + 1),
                    fraction = (midpoint / totalEdges).coerceIn(0f, 1f),
                )
                firstEdge = lastEdgeExclusive
            }
            completedEdges += leg.lastIndex
        }
        return result
    }

    private fun beadBitmap(color: Int): Bitmap {
        val size = (14f * density).toInt().coerceAtLeast(1)
        return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { bitmap ->
            val canvas = Canvas(bitmap)
            val center = size / 2f
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.color = halo
            canvas.drawCircle(center, center, 6.5f * density, paint)
            paint.color = color
            canvas.drawCircle(center, center, 3.8f * density, paint)
        }
    }

    private fun colorAt(fraction: Float): Int = when {
        fraction <= 0.5f -> blend(apricot, pink, fraction * 2f)
        else -> blend(pink, lavender, (fraction - 0.5f) * 2f)
    }

    private fun blend(from: Int, to: Int, amount: Float): Int {
        val t = amount.coerceIn(0f, 1f)
        fun channel(shift: Int): Int {
            val a = from shr shift and 0xFF
            val b = to shr shift and 0xFF
            return (a + (b - a) * t).toInt().coerceIn(0, 255)
        }
        return (channel(24) shl 24) or
            (channel(16) shl 16) or
            (channel(8) shl 8) or
            channel(0)
    }

    private data class RoutePart(val coords: List<LatLng>, val fraction: Float)

    private companion object {
        const val MAX_COLOR_PARTS = 32
        const val ROUTE_Z_INDEX = -90_000
        const val ROUTE_BEAD_Z_INDEX = 100_000
    }
}
