package gr.ygeiaforma.ygeia_forma

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Ο ΕΝΑΣ ζωγράφος των widgets (απόφαση 7/11): ίδια εικόνα στην αρχική οθόνη και στην προεπισκόπηση της ρύθμισης.
 * Ζωγραφίζει σε Bitmap (το Android δεν επιτρέπει θόλωμα ταπετσαρίας ή δικά μας σχήματα σε widget με άλλο τρόπο).
 *
 * Τέσσερις διατάξεις, από το μέγεθος σε dp: στήλη μίας θέσης (< 120 πλάτος), στήλη δύο θέσεων (ψηλή), φαρδιά,
 * μικρή. Πάνω ο τίτλος, μετά η κεντρική τιμή, το γράφημα 7 ημερών όπου χωρά, και κάτω τα κουτάκια τιμών.
 */
object WidgetRenderer {
    enum class Shape { COLUMN1, COLUMN2, SMALL, WIDE }

    fun shapeOf(wDp: Float, hDp: Float): Shape = when {
        wDp < 120f -> Shape.COLUMN1
        hDp >= wDp * 1.45f -> Shape.COLUMN2
        wDp >= hDp * 1.7f -> Shape.WIDE
        else -> Shape.SMALL
    }

    fun maxValues(shape: Shape) = when (shape) {
        Shape.COLUMN1 -> 5
        Shape.COLUMN2 -> 6
        else -> 4
    }

    /** Αν φαίνεται το «+» (Φαγητό, όχι στη στενή στήλη). Η HomeWidgets βάζει εκεί την περιοχή πατήματος. */
    fun showsPlus(kind: String, style: JSONObject?, shape: Shape) =
        kind == "food" && shape != Shape.COLUMN1 && (style?.optString("tap", "add") ?: "add") == "add"

    // ---------------------------------------------------------------- γραμματοσειρές
    private val faces = HashMap<String, Typeface>()

    fun face(ctx: Context, weight: String): Typeface = synchronized(faces) {
        faces.getOrPut(weight) {
            try {
                Typeface.createFromAsset(ctx.assets, "flutter_assets/assets/fonts/Inter-$weight.ttf")
            } catch (_: Throwable) {
                if (weight == "Regular" || weight == "Medium") Typeface.DEFAULT else Typeface.DEFAULT_BOLD
            }
        }
    }

    // ---------------------------------------------------------------- χρώματα
    private fun lum(c: Int): Double {
        fun ch(v: Int): Double {
            val x = v / 255.0
            return if (x <= 0.03928) x / 12.92 else Math.pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch(Color.red(c)) + 0.7152 * ch(Color.green(c)) + 0.0722 * ch(Color.blue(c))
    }

    private fun mix(a: Int, b: Int, t: Float): Int = Color.rgb(
        (Color.red(a) * (1 - t) + Color.red(b) * t).roundToInt(),
        (Color.green(a) * (1 - t) + Color.green(b) * t).roundToInt(),
        (Color.blue(a) * (1 - t) + Color.blue(b) * t).roundToInt(),
    )

    private fun alpha(c: Int, a: Float) = Color.argb((a * 255).roundToInt().coerceIn(0, 255), Color.red(c), Color.green(c), Color.blue(c))

    private fun col(o: JSONObject?, key: String, def: Long): Int = (o?.optLong(key, def) ?: def).toInt()

    /** Χρώματα της «Ταπετσαρίας» (Material You, Android 12+). */
    private fun wallpaperColors(ctx: Context, dark: Boolean): Triple<Int, Int, Int>? {
        if (Build.VERSION.SDK_INT < 31) return null
        return try {
            if (dark) Triple(
                ctx.getColor(android.R.color.system_accent1_800),
                ctx.getColor(android.R.color.system_neutral1_900),
                ctx.getColor(android.R.color.system_accent1_200),
            ) else Triple(
                ctx.getColor(android.R.color.system_accent1_100),
                ctx.getColor(android.R.color.system_neutral1_50),
                ctx.getColor(android.R.color.system_accent1_600),
            )
        } catch (_: Throwable) {
            null
        }
    }

    fun isNight(ctx: Context) =
        (ctx.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    // ---------------------------------------------------------------- ζωγραφική
    /**
     * [kindData]: το είδος από το στιγμιότυπο ({src, m, bar}). [dark]: το θέμα του κινητού (για την «Ταπετσαρία» και
     * για τα αυτόματα χρώματα γραμμάτων με διαφανές φόντο).
     */
    fun render(
        ctx: Context,
        kind: String,
        style: JSONObject?,
        kindData: JSONObject?,
        wDp: Float,
        hDp: Float,
        dark: Boolean,
        capBytes: Long = WidgetBudget.MAX_IMAGE_BYTES,
    ): Bitmap {
        // Όριο μνήμης ανά εικόνα (Android 17: όλες οι εικόνες ενός widget μαζί έχουν όριο· βλ. WidgetBudget).
        val d = WidgetBudget.density(wDp, hDp, ctx.resources.displayMetrics.density, capBytes)
        val (wPx, hPx) = WidgetBudget.pixels(wDp, hDp, d)
        val bmp = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ARGB_8888)
        val cv = Canvas(bmp)
        Painter(ctx, cv, kind, style, kindData, wPx.toFloat(), hPx.toFloat(), d, shapeOf(wDp, hDp), dark).draw()
        return bmp
    }

    private class Painter(
        val ctx: Context,
        val cv: Canvas,
        val kind: String,
        val s: JSONObject?,
        val data: JSONObject?,
        val W: Float,
        val H: Float,
        val d: Float,
        val shape: Shape,
        val dark: Boolean,
    ) {
        val fs = (s?.optDouble("fs", 1.0) ?: 1.0).toFloat().coerceIn(0.8f, 1.3f)
        fun dp(v: Float) = v * d
        fun sp(v: Float) = v * d * fs

        // Χρώματα
        val theme = s?.optString("theme", "bordeaux") ?: "bordeaux"
        val wall = if (theme == "wallpaper") wallpaperColors(ctx, dark) else null
        val c1 = wall?.first ?: col(s, "c1", 0xFF4A070CL)
        val c2 = wall?.second ?: col(s, "c2", 0xFF050203L)
        val acc = wall?.third ?: col(s, "acc", 0xFFFF9C8AL)
        val op = if (wall != null) 0.94f else ((s?.optInt("op", 92) ?: 92) / 100f).coerceIn(0f, 1f)
        val gradient = s?.optBoolean("gradient", true) ?: true
        val dir = s?.optInt("dir", 0) ?: 0
        val radius = dp((s?.optInt("rad", 22) ?: 22).toFloat())
        val glow = s?.optBoolean("glow", true) ?: true
        val border = s?.optBoolean("border", true) ?: true
        val shadow = s?.optBoolean("shadow", false) ?: false
        val fg: Int
        val muted: Int
        val chipBg: Int

        init {
            val manual = if (s != null && s.has("text")) s.optLong("text").toInt() else null
            val textColor = manual ?: run {
                // Τι βλέπει πραγματικά το μάτι: το φόντο ανακατεμένο με μια υποθετική ταπετσαρία κατά τη διαφάνεια.
                val mid = if (gradient) mix(c1, c2, 0.55f) else c1
                val seen = mix(if (dark) 0xFF1A1A1E.toInt() else 0xFFE9E6E2.toInt(), mid, op)
                if (lum(seen) > 0.33) 0xFF17141F.toInt() else 0xFFF7F4FF.toInt()
            }
            fg = textColor
            val darkText = lum(textColor) < 0.2
            muted = alpha(textColor, 0.70f)
            chipBg = if (darkText) alpha(0xFF17141F.toInt(), 0.07f) else alpha(0xFFFFFFFF.toInt(), 0.09f)
        }

        val m = if (shadow) dp(4f) else 0f // περιθώριο για τη σκιά
        val box = RectF(m, m, W - m, H - m - (if (shadow) dp(2f) else 0f))
        val pad = dp(if (shape == Shape.COLUMN1) 8f else 11f)

        fun paint(weight: String, size: Float, color: Int) = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            typeface = WidgetRenderer.face(ctx, weight)
            textSize = size
            this.color = color
        }

        /** Κείμενο που χωρά στο [maxW]: μικραίνει ως 75% και μετά κόβεται με «…». */
        fun fit(text: String, p: Paint, maxW: Float): String {
            if (maxW <= 0) return ""
            val base = p.textSize
            while (p.measureText(text) > maxW && p.textSize > base * 0.75f) p.textSize -= base * 0.05f
            if (p.measureText(text) <= maxW) return text
            var t = text
            while (t.isNotEmpty() && p.measureText("$t…") > maxW) t = t.dropLast(1)
            return if (t.isEmpty()) "" else "$t…"
        }

        fun metrics(): JSONObject = data?.optJSONObject("m") ?: JSONObject()

        fun entry(key: String): JSONObject? = metrics().optJSONObject(key)

        fun draw() {
            background()
            var y = box.top + pad
            val left = box.left + pad
            val right = box.right - pad
            val plus = showsPlus(kind, s, shape)

            // Τίτλος και πηγή
            val showTitle = s?.optBoolean("title", true) ?: true
            val showSrc = (s?.optBoolean("src", true) ?: true) && !plus
            val showDot = s?.optBoolean("dot", true) ?: true
            if (showTitle || showSrc) {
                val tp = paint("Bold", sp(10.5f), muted).apply { letterSpacing = 0.05f }
                val title = when (kind) { "sleep" -> "ΥΠΝΟΣ"; "move" -> "ΚΙΝΗΣΗ"; "food" -> "ΦΑΓΗΤΟ"; else -> "ΣΩΜΑ" }
                val src = data?.optString("src", "") ?: ""
                val base = y - tp.ascent()
                var x = left
                if (showTitle) {
                    if (showDot) {
                        cv.drawCircle(x + dp(3.5f), base + tp.ascent() / 2.6f, dp(3.5f), Paint(Paint.ANTI_ALIAS_FLAG).apply { color = acc })
                        x += dp(11f)
                    }
                    val t = fit(title, tp, right - x)
                    cv.drawText(t, x, base, tp)
                }
                if (showSrc && src.isNotEmpty()) {
                    val sp2 = paint("Medium", sp(10f), muted)
                    if (shape == Shape.COLUMN1 && showTitle) {
                        y = base + dp(3f)
                        val b2 = y - sp2.ascent()
                        cv.drawText(fit(src, sp2, right - left), left, b2, sp2)
                        y = b2 + sp2.descent()
                    } else {
                        val used = if (showTitle) tp.measureText(title) + (x - left) + dp(8f) else 0f
                        val t = fit(src, sp2, right - left - used)
                        cv.drawText(t, right - sp2.measureText(t), base, sp2)
                        y = base + tp.descent()
                    }
                } else {
                    y = base + tp.descent()
                }
                y += dp(6f)
            }

            // Τα κουτάκια (από κάτω): πόσα χωράνε
            val showVals = s?.optBoolean("vals", true) ?: true
            val heroKey = s?.optString("hero", defaultHero()) ?: defaultHero()
            val wanted = if (!showVals) emptyList() else valueKeys().filter { it != heroKey }
            val maxN = maxValues(shape)
            val cols = when (shape) { Shape.COLUMN1 -> 1; Shape.WIDE -> 4; else -> 2 }
            val chipH = sp(13f) + sp(11f) + dp(9f)
            val gap = dp(4f)
            var n = min(wanted.size, maxN)
            // Χρόνος για την κεντρική τιμή: τουλάχιστον ~1 γραμμή μεγάλου αριθμού + λεζάντα.
            val heroMin = sp(bigSize()) + sp(12f)
            fun chipsHeight(k: Int) = if (k == 0) 0f else ((k + cols - 1) / cols) * chipH + ((k + cols - 1) / cols - 1) * gap
            while (n > 0 && (box.bottom - pad) - chipsHeight(n) - dp(6f) < y + heroMin) n--
            val chipsTop = box.bottom - pad - chipsHeight(n)

            // Κεντρική τιμή
            y = hero(heroKey, left, right, y, plus)

            // Γράφημα 7 ημερών, όπου χωρά (≥ 22 dp)
            val showSpark = s?.optBoolean("spark", true) ?: true
            val room = chipsTop - dp(8f) - y
            if (showSpark && room >= dp(22f)) {
                val arr = entry(heroKey)?.optJSONArray("s")
                if (arr != null) spark(arr, left, right, y + dp(4f), min(chipsTop - dp(8f), y + dp(4f) + dp(if (shape == Shape.COLUMN2) 56f else 40f)))
            }

            // Κουτάκια
            if (n > 0) chips(wanted.take(n), cols, left, right, chipsTop, chipH, gap)

            if (plus) plusButton()
        }

        fun defaultHero() = when (kind) { "sleep" -> "sleepMin"; "move" -> "steps"; "food" -> "kcal"; else -> "weight" }

        fun valueKeys(): List<String> {
            val arr = s?.optJSONArray("values") ?: return defaults()
            return (0 until arr.length()).map { arr.optString(it) }.filter { it.isNotEmpty() }
        }

        fun defaults() = when (kind) {
            "sleep" -> listOf("energy", "sleepScore", "hrv", "ringSpo2", "sleepHr", "breath")
            "move" -> listOf("activeKcal", "totalKcal", "activeMin", "floors", "distance", "dayHr")
            "food" -> listOf("protein", "carbs", "fat", "fiber", "salt", "sugars")
            else -> listOf("fatPct", "smm", "ffm", "bmr", "bmi", "water")
        }

        fun bigSize() = when (shape) {
            Shape.COLUMN1 -> 22f
            Shape.COLUMN2 -> 34f
            Shape.WIDE -> 30f
            Shape.SMALL -> 27f
        }

        fun background() {
            val r = radius
            if (shadow) {
                val sh = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.argb(70, 0, 0, 0)
                    maskFilter = BlurMaskFilter(dp(4f), BlurMaskFilter.Blur.NORMAL)
                }
                cv.drawRoundRect(RectF(box.left, box.top + dp(2f), box.right, box.bottom + dp(2f)), r, r, sh)
            }
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            if (gradient) {
                val (x0, y0, x1, y1) = when (dir) {
                    1 -> listOf(box.left, box.top, box.right, box.bottom)
                    2 -> listOf(box.left, box.top, box.right, box.top)
                    3 -> listOf(box.left, box.bottom, box.right, box.top)
                    else -> listOf(box.left, box.top, box.left, box.bottom)
                }
                p.shader = LinearGradient(x0, y0, x1, y1, alpha(c1, op), alpha(c2, op), Shader.TileMode.CLAMP)
            } else {
                p.color = alpha(c1, op)
            }
            cv.drawRoundRect(box, r, r, p)
            if (glow) {
                val gr = max(box.width(), box.height()) * 0.7f
                val g = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    shader = RadialGradient(box.right, box.top, gr, alpha(acc, 0.38f * op), alpha(acc, 0f), Shader.TileMode.CLAMP)
                }
                cv.save()
                val path = android.graphics.Path().apply { addRoundRect(box, r, r, android.graphics.Path.Direction.CW) }
                cv.clipPath(path)
                cv.drawRect(box, g)
                cv.restore()
            }
            if (border) {
                val b = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = dp(1f)
                    color = if (lum(fg) < 0.2) Color.argb(28, 0, 0, 0) else Color.argb(38, 255, 255, 255)
                }
                val inset = RectF(box.left + dp(0.5f), box.top + dp(0.5f), box.right - dp(0.5f), box.bottom - dp(0.5f))
                cv.drawRoundRect(inset, r, r, b)
            }
        }

        fun arrow(dir: Int) = when (dir) { 1 -> "▲"; -1 -> "▼"; else -> "=" }

        /** Μεγάλος αριθμός, μονάδα, λεζάντα και (αν ζητήθηκε) «συνήθως»/εύρος. Επιστρέφει πού τελείωσε. */
        fun hero(key: String, left: Float, right: Float, top: Float, plus: Boolean): Float {
            val e = entry(key)
            val value = e?.optString("v", "—") ?: "—"
            val unit = e?.optString("u", "")?.trim() ?: ""
            val maxW = right - left - (if (plus) dp(38f) else 0f)
            val big = paint("ExtraBold", sp(bigSize()), fg).apply { letterSpacing = -0.03f }
            val up = paint("SemiBold", sp(bigSize() * 0.42f), muted)
            // Μικραίνει μαζί με τη μονάδα ώστε να χωρούν και τα δύο.
            val unitW = if (unit.isEmpty()) 0f else up.measureText(" $unit")
            val base = big.textSize
            while (big.measureText(value) + unitW > maxW && big.textSize > base * 0.6f) big.textSize -= base * 0.05f
            val vText = fit(value, big, maxW - unitW)
            val by = top - big.ascent() * 0.92f
            cv.drawText(vText, left, by, big)
            if (unit.isNotEmpty() && unitW + big.measureText(vText) <= maxW) cv.drawText(" $unit", left + big.measureText(vText), by, up)
            var y = by + big.descent() * 0.6f

            val capP = paint("Medium", sp(10.5f), muted)
            val cap = e?.optString("cap", "") ?: ""
            if (cap.isNotEmpty()) {
                y += dp(2f)
                val b = y - capP.ascent()
                cv.drawText(fit(cap, capP, right - left), left, b, capP)
                y = b + capP.descent()
            }
            // Αναλογία θρεπτικών (μόνο Φαγητό, όταν κεντρική τιμή είναι οι θερμίδες)
            if (kind == "food" && key == "kcal") {
                val bar = data?.optJSONArray("bar")
                if (bar != null && bar.length() == 3) {
                    val vals = (0 until 3).map { bar.optDouble(it, 0.0).toFloat() }
                    val sum = vals.sum()
                    if (sum > 0f) {
                        y += dp(5f)
                        val h = dp(5f)
                        val colors = intArrayOf(acc, 0xFF9FE3F2.toInt(), 0xFFF7C59A.toInt())
                        var x = left
                        val w = right - left - dp(4f)
                        for (i in 0 until 3) {
                            val seg = w * vals[i] / sum
                            if (seg > 0.5f) {
                                cv.drawRoundRect(RectF(x, y, x + seg, y + h), h / 2, h / 2, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = colors[i] })
                            }
                            x += seg + dp(2f)
                        }
                        y += h
                    }
                }
            }
            val showUsual = s?.optBoolean("usual", true) ?: true
            if (showUsual && e != null) {
                val parts = mutableListOf<String>()
                if (e.has("d") && e.has("us")) parts += "${arrow(e.optInt("d"))} ${e.optString("us")}"
                else if (e.has("us")) parts += e.optString("us")
                if (e.has("r")) parts += e.optString("r")
                if (parts.isNotEmpty()) {
                    y += dp(2f)
                    val b = y - capP.ascent()
                    val p2 = paint("SemiBold", sp(10.5f), alpha(acc, 0.95f))
                    cv.drawText(fit(parts.joinToString(" · "), p2, right - left), left, b, p2)
                    y = b + capP.descent()
                }
            }
            return y
        }

        fun spark(arr: JSONArray, left: Float, right: Float, top: Float, bottom: Float) {
            val vals = (0 until arr.length()).map { if (arr.isNull(it)) null else arr.optDouble(it).toFloat() }
            val real = vals.filterNotNull()
            if (real.isEmpty() || bottom - top < dp(14f)) return
            val hi = real.max()
            val lo0 = real.min()
            // Βάση λίγο κάτω από το χαμηλότερο, ώστε να φαίνονται οι διαφορές (π.χ. βάρος 82–84).
            val lo = if (hi == lo0) lo0 - 1f else lo0 - (hi - lo0) * 0.6f
            val n = vals.size
            val gap = dp(if (shape == Shape.COLUMN1) 2f else 3f)
            val bw = (right - left - gap * (n - 1)) / n
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            for ((i, v) in vals.withIndex()) {
                val x = left + i * (bw + gap)
                if (v == null) {
                    p.color = alpha(fg, 0.12f)
                    cv.drawRoundRect(RectF(x, bottom - dp(3f), x + bw, bottom), dp(1.5f), dp(1.5f), p)
                    continue
                }
                val f = ((v - lo) / (hi - lo)).coerceIn(0.08f, 1f)
                p.color = alpha(acc, if (i == n - 1) 1f else 0.5f)
                cv.drawRoundRect(RectF(x, bottom - (bottom - top) * f, x + bw, bottom), dp(3f), dp(3f), p)
            }
        }

        fun chips(keys: List<String>, cols: Int, left: Float, right: Float, top: Float, chipH: Float, gap: Float) {
            val colors = s?.optJSONObject("valueColors")
            val showUsual = s?.optBoolean("usual", true) ?: true
            val cw = (right - left - gap * (cols - 1)) / cols
            val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = chipBg }
            val r = max(dp(4f), radius * 0.42f)
            val lp = paint("Medium", sp(9.5f), muted)
            for ((i, k) in keys.withIndex()) {
                val x = left + (i % cols) * (cw + gap)
                val y = top + (i / cols) * (chipH + gap)
                cv.drawRoundRect(RectF(x, y, x + cw, y + chipH), r, r, bg)
                val e = entry(k)
                val label = e?.optString("l") ?: labelOf(k)
                val ip = dp(6f)
                val lb = y + dp(4f) - lp.ascent()
                cv.drawText(fit(label, lp, cw - ip * 2), x + ip, lb, lp)
                val color = when {
                    colors != null && colors.has(k) -> colors.optLong(k).toInt()
                    i == 0 -> acc
                    else -> fg
                }
                val vp = paint("ExtraBold", sp(13f), color)
                val up = paint("SemiBold", sp(9f), muted)
                val v = e?.optString("v", "—") ?: "—"
                val u = e?.optString("u", "")?.trim() ?: ""
                val a = if (showUsual && e != null && e.has("d")) " " + arrow(e.optInt("d")) else ""
                val vb = lb + lp.descent() + dp(1f) - vp.ascent()
                val avail = cw - ip * 2
                val tail = (if (u.isEmpty()) "" else " $u") + a
                val vt = fit(v, vp, avail - up.measureText(tail))
                cv.drawText(vt, x + ip, vb, vp)
                if (tail.isNotEmpty() && vp.measureText(vt) + up.measureText(tail) <= avail) {
                    cv.drawText(tail, x + ip + vp.measureText(vt), vb, up)
                }
            }
        }

        fun labelOf(k: String) = when (k) {
            "energy" -> "Ετοιμότητα"; "sleepScore" -> "Σκορ"; "hrv" -> "HRV"; "sleepHr" -> "Παλμοί"; "lowHr" -> "Χαμηλότεροι"
            "ringSpo2" -> "Οξυγόνο"; "breath" -> "Αναπνοές"; "skinTemp" -> "Θερμοκρ."; "sleepMin" -> "Ύπνος"
            "steps" -> "Βήματα"; "activeKcal" -> "Ενεργές"; "totalKcal" -> "Σύνολο"; "activeMin" -> "Ενεργός"; "floors" -> "Όροφοι"
            "distance" -> "Απόσταση"; "dayHr" -> "Παλμοί χθες"; "kcal" -> "Θερμίδες"; "protein" -> "Πρωτεΐνη"; "carbs" -> "Υδατ."
            "fat" -> "Λιπαρά"; "fiber" -> "Ίνες"; "salt" -> "Αλάτι"; "sugars" -> "Σάκχαρα"; "weight" -> "Βάρος"; "fatPct" -> "Λίπος"
            "smm" -> "Μύες"; "ffm" -> "Άλιπη"; "bmr" -> "Μεταβολ."; "bmi" -> "Δείκτης"; "water" -> "Νερό"
            else -> k
        }

        /** Το «+» στο πάνω δεξί μέρος· η περιοχή πατήματος (56 dp) στο home_widget.xml είναι στο ίδιο σημείο. */
        fun plusButton() {
            val cx = box.right - dp(28f)
            val cy = box.top + dp(28f)
            val rr = dp(15f)
            cv.drawCircle(cx, cy, rr, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = acc })
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = if (lum(acc) > 0.4) 0xFF17141F.toInt() else Color.WHITE
                strokeWidth = dp(2.4f)
                strokeCap = Paint.Cap.ROUND
            }
            cv.drawLine(cx - dp(6f), cy, cx + dp(6f), cy, p)
            cv.drawLine(cx, cy - dp(6f), cx, cy + dp(6f), p)
        }
    }

    /** Παράδειγμα τιμών για την προεπισκόπηση, όταν δεν έχει ανοίξει ακόμα η εφαρμογή (σημειώνεται στη ρύθμιση). */
    fun sample(kind: String): JSONObject {
        fun e(l: String, v: String, u: String = "", cap: String? = null, d: Int? = null, us: String? = null, r: String? = null, s: List<Double?>? = null) =
            JSONObject().apply {
                put("l", l); put("v", v); put("u", u)
                cap?.let { put("cap", it) }; d?.let { put("d", it) }; us?.let { put("us", it) }; r?.let { put("r", it) }
                s?.let { put("s", JSONArray(it)) }
            }
        val m = JSONObject()
        val o = JSONObject().put("m", m)
        when (kind) {
            "sleep" -> {
                o.put("src", "Oura · Σάβ 7/11")
                m.put("sleepMin", e("Ύπνος", "7:16", cap = "00:37–08:15", d = 1, us = "συνήθως 6:58", r = "μέσα στο εύρος", s = listOf(6.9, 7.4, 6.5, 7.1, 6.8, 7.6, 7.3)))
                m.put("energy", e("Ετοιμότητα", "71", d = 0, us = "συνήθως 71", s = listOf(68.0, 74.0, 66.0, 70.0, 72.0, 69.0, 71.0)))
                m.put("sleepScore", e("Σκορ", "84", d = 1, us = "συνήθως 79"))
                m.put("hrv", e("HRV", "41", " ms", d = 1, us = "συνήθως 39 ms", s = listOf(38.0, 40.0, 35.0, 39.0, 44.0, 39.0, 41.0)))
                m.put("sleepHr", e("Παλμοί", "60", " bpm", d = 1, us = "συνήθως 59 bpm"))
                m.put("lowHr", e("Χαμηλότεροι", "53", " bpm"))
                m.put("ringSpo2", e("Οξυγόνο", "96", "%"))
                m.put("breath", e("Αναπνοές", "14,0", "", d = 0))
                m.put("skinTemp", e("Θερμοκρ.", "+0,2", "°"))
            }
            "move" -> {
                o.put("src", "ρολόι · 10:20")
                m.put("steps", e("Βήματα", "6.389", cap = "χθες 8.012", r = "χθες μέσα στο εύρος", s = listOf(7200.0, 9100.0, 5400.0, 8000.0, 10200.0, 8012.0, 6389.0)))
                m.put("activeKcal", e("Ενεργές", "288", " kcal")); m.put("totalKcal", e("Σύνολο", "1.930", " kcal"))
                m.put("activeMin", e("Ενεργός", "34′")); m.put("floors", e("Όροφοι", "6"))
                m.put("distance", e("Απόσταση", "4,6", " km")); m.put("dayHr", e("Παλμοί χθες", "72", " bpm"))
            }
            "food" -> {
                o.put("src", "3 γεύματα")
                o.put("bar", JSONArray(listOf(248.0, 512.0, 396.0)))
                m.put("kcal", e("Θερμίδες", "1.240", " kcal", cap = "3 γεύματα σήμερα", s = listOf(1900.0, 2200.0, 2000.0, 1700.0, 2400.0, 2100.0, 1240.0)))
                m.put("protein", e("Πρωτεΐνη", "62", " g")); m.put("carbs", e("Υδατ.", "128", " g")); m.put("fat", e("Λιπαρά", "44", " g"))
                m.put("fiber", e("Ίνες", "17", " g")); m.put("salt", e("Αλάτι", "4,1", " g")); m.put("sugars", e("Σάκχαρα", "38", " g"))
            }
            else -> {
                o.put("src", "InBody · Παρ 6/11")
                m.put("weight", e("Βάρος", "82,2", " kg", cap = "Παρ 6/11 · −0,4 kg", d = -1, r = "πάνω από το εύρος", s = listOf(83.9, 83.6, 83.4, 83.1, 82.9, 82.6, 82.2)))
                m.put("fatPct", e("Λίπος", "25,4", "%")); m.put("smm", e("Μύες", "34,3", " kg")); m.put("ffm", e("Άλιπη", "61,3", " kg"))
                m.put("bmr", e("Μεταβολ.", "1.695", " kcal")); m.put("bmi", e("Δείκτης", "26,8")); m.put("water", e("Νερό", "44,9", " L"))
            }
        }
        return o
    }
}
