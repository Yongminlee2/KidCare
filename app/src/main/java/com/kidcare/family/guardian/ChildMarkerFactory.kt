package com.kidcare.family.guardian

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.content.ContextCompat
import com.kidcare.family.R

/** Builds the approved 3D mascot marker at a map-safe size with a soft lavender ring. */
object ChildMarkerFactory {
    fun create(context: Context): Bitmap {
        val resources = context.resources
        val density = resources.displayMetrics.density
        val size = (64f * density).toInt()
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val center = size / 2f
        val ringRadius = 27f * density
        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ContextCompat.getColor(context, R.color.paper_card)
            setShadowLayer(4f * density, 0f, 2f * density, 0x33000000)
        }
        canvas.drawCircle(center, center - density, ringRadius, ringPaint)
        ringPaint.clearShadowLayer()
        ringPaint.style = Paint.Style.STROKE
        ringPaint.strokeWidth = 3f * density
        ringPaint.color = ContextCompat.getColor(context, R.color.sky_soft)
        canvas.drawCircle(center, center - density, ringRadius, ringPaint)

        val mascot = BitmapFactory.decodeResource(resources, R.drawable.mascot_3d)
        val inset = 7f * density
        canvas.drawBitmap(
            mascot,
            null,
            RectF(inset, 3f * density, size - inset, size - 4f * density),
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
        )
        mascot.recycle()
        return output
    }
}
