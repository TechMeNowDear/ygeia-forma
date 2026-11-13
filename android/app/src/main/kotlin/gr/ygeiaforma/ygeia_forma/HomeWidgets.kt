package gr.ygeiaforma.ygeia_forma

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Widgets αρχικής οθόνης (απόφαση χρήστη 7/11): Ύπνος, Κίνηση, Φαγητό, Σώμα.
 *
 * - Τιμές: το στιγμιότυπο που γράφει η εφαρμογή (widget_snapshot.dart → [SNAPSHOT]) όταν διαβάζει δεδομένα ή
 *   γράφεις φαγητό. Η Κίνηση ανανεώνεται και από την ανάγνωση στο παρασκήνιο (RefreshWorker, κάθε 3 ώρες).
 * - Εμφάνιση: οι ρυθμίσεις κάθε widget ([PREFS], JSON του WidgetStyle) και ο [WidgetRenderer].
 * - Τίποτα συνεχές: δεν ζητάμε περιοδική ανανέωση από το Android (updatePeriodMillis = 0).
 */
object HomeWidgets {
    const val PREFS = "home_widgets"
    const val SNAPSHOT = "widget_data.json"
    const val EXTRA_OPEN = "ygeia_open"

    /** Μεσάνυχτα: ξαναζωγραφίζονται τα widgets με τον κανόνα της ημέρας (καμία ανάγνωση δεδομένων). */
    const val ACTION_DAY = "gr.ygeiaforma.widgets.DAY"

    private val providers = mapOf(
        SleepWidget::class.java.name to "sleep",
        MoveWidget::class.java.name to "move",
        FoodWidget::class.java.name to "food",
        BodyWidget::class.java.name to "body",
        // 13/11: δύο απλά widgets με γράμματα (QuickWidgets.kt), χωρίς ρυθμίσεις εμφάνισης.
        WorkoutWidget::class.java.name to QuickWidgets.WORKOUT,
        QuickFoodWidget::class.java.name to QuickWidgets.QUICK_FOOD,
    )

    /** Πάτημα σε widget που περιμένει να το πάρει η εφαρμογή (takeOpen). */
    @Volatile
    var pendingOpen: String? = null

    fun kindOf(ctx: Context, id: Int): String? =
        AppWidgetManager.getInstance(ctx).getAppWidgetInfo(id)?.provider?.className?.let { providers[it] }

    fun allIds(ctx: Context): List<Int> {
        val mgr = AppWidgetManager.getInstance(ctx)
        return providers.keys.flatMap { cls ->
            try {
                mgr.getAppWidgetIds(ComponentName(ctx, cls)).toList()
            } catch (_: Throwable) {
                emptyList()
            }
        }
    }

    fun count(ctx: Context) = allIds(ctx).size

    // ---------------------------------------------------------------- ρυθμίσεις ανά widget
    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun styleJson(ctx: Context, id: Int): String? = prefs(ctx).getString("w$id", null)

    fun style(ctx: Context, id: Int): JSONObject? = try {
        styleJson(ctx, id)?.let { JSONObject(it) }
    } catch (_: Throwable) {
        null
    }

    fun saveStyle(ctx: Context, id: Int, json: String) {
        prefs(ctx).edit().putString("w$id", json).apply()
    }

    /** «Ίδια εμφάνιση σε όλα»: μόνο τα κλειδιά εμφάνισης· το περιεχόμενο κάθε widget μένει δικό του. */
    private val lookKeys = listOf("theme", "c1", "c2", "acc", "text", "gradient", "dir", "op", "rad", "fs", "glow", "border", "shadow", "title", "src", "dot")

    fun applyLookToAll(ctx: Context, from: JSONObject) {
        for (id in allIds(ctx)) {
            val s = style(ctx, id) ?: continue
            for (k in lookKeys) if (from.has(k)) s.put(k, from.get(k)) else s.remove(k)
            saveStyle(ctx, id, s.toString())
        }
    }

    fun forget(ctx: Context, ids: IntArray) {
        val e = prefs(ctx).edit()
        for (id in ids) e.remove("w$id")
        e.apply()
    }

    // ---------------------------------------------------------------- στιγμιότυπο
    private fun snapFile(ctx: Context) = File(ctx.filesDir, SNAPSHOT)

    fun snapshot(ctx: Context): JSONObject? = try {
        val f = snapFile(ctx)
        if (f.exists()) JSONObject(f.readText()) else null
    } catch (_: Throwable) {
        null
    }

    private fun writeSnapshot(ctx: Context, text: String) {
        val f = snapFile(ctx)
        val tmp = File(f.parentFile, "$SNAPSHOT.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(f)) {
            f.delete()
            tmp.renameTo(f)
        }
    }

    fun saveSnapshot(ctx: Context, text: String) {
        JSONObject(text) // μόνο έγκυρο JSON
        writeSnapshot(ctx, text)
        updateAll(ctx)
    }

    /**
     * «Διαγραφή όλων των δεδομένων» (έλεγχος 9/11, E3-05): πριν σβηστούν τα δεδομένα της εφαρμογής, κάθε widget
     * ξαναζωγραφίζεται ΧΩΡΙΣ τιμές. Αλλιώς η αρχική οθόνη θα έδειχνε για πάντα την τελευταία εικόνα (π.χ. ύπνο, βάρος),
     * αφού μετά τη διαγραφή η εφαρμογή δεν ξέρει πια ποιο widget είναι ποιο. Το ξυπνητήρι των μεσανύχτων ακυρώνεται.
     */
    fun wipe(ctx: Context) {
        try {
            snapFile(ctx).delete()
        } catch (_: Throwable) {}
        val mgr = AppWidgetManager.getInstance(ctx)
        for (id in allIds(ctx)) {
            try {
                update(ctx, mgr, id)
            } catch (_: Throwable) {}
        }
        try {
            val am = ctx.getSystemService(AlarmManager::class.java)
            val pi = PendingIntent.getBroadcast(
                ctx, 7400, Intent(ctx, MoveWidget::class.java).setAction(ACTION_DAY),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE,
            )
            if (am != null && pi != null) am.cancel(pi)
        } catch (_: Throwable) {}
    }

    fun kindData(ctx: Context, kind: String): JSONObject? = snapshot(ctx)?.optJSONObject("kinds")?.optJSONObject(kind)

    fun hasData(ctx: Context, kind: String): Boolean = (kindData(ctx, kind)?.optJSONObject("m")?.length() ?: 0) > 0

    // ---------------------------------------------------------------- ζωγραφική
    fun updateAll(ctx: Context, only: String? = null) {
        scheduleMidnight(ctx)
        val mgr = AppWidgetManager.getInstance(ctx)
        for (id in allIds(ctx)) {
            if (only != null && kindOf(ctx, id) != only) continue
            try {
                update(ctx, mgr, id)
            } catch (e: Throwable) {
                ErrorQueue.report(e, "widget")
            }
        }
    }

    /** Τα μεγέθη που δίνει η αρχική οθόνη (dp): Android 12+ ακριβώς, αλλιώς κάθετη και οριζόντια θέση. */
    private fun sizes(opts: Bundle): List<SizeF> {
        if (Build.VERSION.SDK_INT >= 31) {
            @Suppress("DEPRECATION")
            val list = opts.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            if (!list.isNullOrEmpty()) return list.distinct().take(2)
        }
        val minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        val maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
        val maxW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
        val minH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
        if (minW <= 0 || maxH <= 0) return listOf(SizeF(180f, 190f))
        return listOf(SizeF(minW.toFloat(), maxH.toFloat()), SizeF(maxW.toFloat(), minH.toFloat())).distinct()
    }

    fun sizeOf(ctx: Context, id: Int): SizeF? {
        val opts = AppWidgetManager.getInstance(ctx).getAppWidgetOptions(id)
        val minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        val maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
        return if (minW > 0 && maxH > 0) SizeF(minW.toFloat(), maxH.toFloat()) else null
    }

    /**
     * Έλεγχος 8/11 (DATA-02): τιμές «σήμερα» (κίνηση, φαγητό) άλλης μέρας δεν φαίνονται σαν σημερινές.
     * Μένουν τα ονόματα και το γράφημα, οι τιμές γίνονται «—» ώσπου να ανοίξει η εφαρμογή ή να διαβαστούν ξανά.
     * Round 1 (U7-12): ο κανόνας είναι στο [WidgetText.forToday] (ελέγχεται σε JVM).
     */
    fun forToday(data: JSONObject?, today: LocalDate = LocalDate.now()): JSONObject? = WidgetText.forToday(data, today)

    fun ensureMidnight(ctx: Context) = scheduleMidnight(ctx)

    /** Ένα ξυπνητήρι στα μεσάνυχτα, μόνο όσο υπάρχουν widgets (ανακριβές, χωρίς άδεια, χωρίς να ξυπνά τη συσκευή). */
    private fun scheduleMidnight(ctx: Context) {
        try {
            val am = ctx.getSystemService(AlarmManager::class.java) ?: return
            val pi = PendingIntent.getBroadcast(
                ctx, 7400, Intent(ctx, MoveWidget::class.java).setAction(ACTION_DAY),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            if (count(ctx) == 0) {
                am.cancel(pi)
                return
            }
            val zone = ZoneId.systemDefault()
            val next = LocalDate.now(zone).plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli() + 60_000
            am.set(AlarmManager.RTC, next, pi)
        } catch (e: Throwable) {
            ErrorQueue.report(e, "widget")
        }
    }

    fun update(ctx: Context, mgr: AppWidgetManager, id: Int) {
        val kind = kindOf(ctx, id) ?: return
        if (QuickWidgets.handles(kind)) {
            mgr.updateAppWidget(id, QuickWidgets.views(ctx, id, kind))
            return
        }
        val style = style(ctx, id)
        val data = forToday(kindData(ctx, kind))
        val list = sizes(mgr.getAppWidgetOptions(id))
        val multi = Build.VERSION.SDK_INT >= 31 && list.size > 1
        // Android 17 (targetSdk 37): όριο για ΟΛΕΣ τις εικόνες μαζί (WidgetBudget). Μετράμε 2 εικόνες ανά μέγεθος
        // (ημέρας, νύχτας). Αν το Android απαντήσει «όχι», ξανά με μικρότερες εικόνες· ποτέ κενό widget χωρίς λόγο.
        val dm = ctx.resources.displayMetrics
        val budget = WidgetBudget.systemBudget(dm.widthPixels, dm.heightPixels)
        val images = 2 * (if (multi) list.size else 1)
        var last: Throwable? = null
        for (share in WidgetBudget.SHARES) {
            val cap = WidgetBudget.imageCap(budget, images, share)
            val views = if (multi) {
                RemoteViews(list.associateWith { views(ctx, id, kind, style, data, it, cap) })
            } else {
                views(ctx, id, kind, style, data, list.first(), cap)
            }
            try {
                mgr.updateAppWidget(id, views)
                return
            } catch (e: IllegalArgumentException) {
                if (!WidgetBudget.isBitmapLimit(e)) throw e
                last = e
            }
        }
        throw last ?: IllegalStateException("widget")
    }

    private fun views(
        ctx: Context,
        id: Int,
        kind: String,
        style: JSONObject?,
        data: JSONObject?,
        size: SizeF,
        cap: Long,
    ): RemoteViews {
        val v = RemoteViews(ctx.packageName, R.layout.home_widget)
        val shape = WidgetRenderer.shapeOf(size.width, size.height)
        // Δύο εικόνες: ημέρας και νύχτας. Η αρχική οθόνη δείχνει τη σωστή (layout και layout-night) όταν αλλάζει το θέμα
        // του κινητού, χωρίς να ξυπνήσει η εφαρμογή. Ίδιο bitmap όταν το θέμα δεν εξαρτάται από τη νύχτα.
        val wallpaper = style?.optString("theme") == "wallpaper"
        val auto = style == null || !style.has("text")
        val day = WidgetRenderer.render(ctx, kind, style, data ?: emptyData(), size.width, size.height, dark = false, capBytes = cap)
        val night = if (wallpaper || auto) {
            WidgetRenderer.render(ctx, kind, style, data ?: emptyData(), size.width, size.height, dark = true, capBytes = cap)
        } else {
            day
        }
        v.setImageViewBitmap(R.id.widget_image_day, day)
        v.setImageViewBitmap(R.id.widget_image_night, night)
        val label = describe(kind, data)
        v.setContentDescription(R.id.widget_image_day, label)
        v.setContentDescription(R.id.widget_image_night, label)
        val tap = style?.optString("tap") ?: if (kind == "food") "add" else "section"
        val hero = style?.optString("hero") ?: ""
        // Το πάτημα στο widget: ό,τι ορίστηκε· με το «+», το υπόλοιπο widget ανοίγει την ενότητα.
        val plus = WidgetRenderer.showsPlus(kind, style, shape)
        val main = if (plus) "section" else tap
        v.setOnClickPendingIntent(R.id.widget_root, open(ctx, id, 0, "w:$kind:$main:$hero"))
        if (plus) {
            v.setViewVisibility(R.id.widget_plus, View.VISIBLE)
            v.setOnClickPendingIntent(R.id.widget_plus, open(ctx, id, 1, "w:$kind:add:$hero"))
        } else {
            v.setViewVisibility(R.id.widget_plus, View.GONE)
        }
        return v
    }

    private fun emptyData() = JSONObject().put("m", JSONObject())

    /** Για τον αναγνώστη οθόνης: τίτλος και οι τιμές με λέξεις. */
    private fun describe(kind: String, data: JSONObject?): String {
        val title = when (kind) { "sleep" -> "Ύπνος"; "move" -> "Κίνηση"; "food" -> "Φαγητό"; else -> "Σώμα" }
        val m = data?.optJSONObject("m") ?: return "$title: χωρίς τιμές ακόμα"
        val parts = m.keys().asSequence().take(6).mapNotNull { k ->
            val e = m.optJSONObject(k) ?: return@mapNotNull null
            "${e.optString("l")} ${e.optString("v")}${e.optString("u")}"
        }.toList()
        return if (parts.isEmpty()) "$title: χωρίς τιμές ακόμα" else "$title: ${parts.joinToString(", ")}"
    }

    internal fun open(ctx: Context, id: Int, part: Int, target: String): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java).apply {
            // Χωρίς data URI: η Flutter παίρνει κάθε data URI ως σελίδα (deep link) και, χωρίς τέτοια σελίδα, βγάζει
            // σφάλμα (Sentry YGEIA-FORMA-3). Κάθε πάτημα ξεχωρίζει από τον requestCode του PendingIntent.
            action = "gr.ygeiaforma.WIDGET_OPEN.$id.$part"
            putExtra(EXTRA_OPEN, target)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(ctx, id * 2 + part, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    // ---------------------------------------------------------------- Κίνηση από την ανάγνωση στο παρασκήνιο
    private fun thousands(v: Long): String {
        val s = kotlin.math.abs(v).toString().reversed().chunked(3).joinToString(".").reversed()
        return if (v < 0) "−$s" else s
    }

    private fun dec1(v: Double): String = String.format(java.util.Locale.ROOT, "%.1f", v).replace('.', ',')

    /**
     * Μετά από ανάγνωση στο παρασκήνιο (RefreshWorker): βήματα, θερμίδες, ενεργός χρόνος, απόσταση και όροφοι της
     * σημερινής μέρας από το νέο βοηθητικό αρχείο, μόνο αν είναι νεότερο από το στιγμιότυπο. Ό,τι δεν βρεθεί μένει.
     */
    fun refreshMoveFromDashboard(ctx: Context, dashboard: JSONObject) {
        if (count(ctx) == 0) return
        val snap = snapshot(ctx) ?: return
        val kinds = snap.optJSONObject("kinds") ?: return
        val move = kinds.optJSONObject("move") ?: JSONObject().put("m", JSONObject())
        val readAt = dashboard.optLong("readAt", 0L)
        if (readAt <= move.optLong("at", 0L)) return
        val m = move.optJSONObject("m") ?: JSONObject().also { move.put("m", it) }
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        // Έλεγχος 9/11 (D2-05a): ό,τι ήταν «χθες» στο στιγμιότυπο άλλης μέρας (π.χ. «Παλμοί χθες») δεν ξαναγράφεται εδώ·
        // δεν μένει με τη σημερινή ημερομηνία.
        if (move.optString("day", "") != today.toString()) m.remove("dayHr")
        fun dayOf(ms: Long) = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
        fun perDay(key: String, sum: Boolean): Map<LocalDate, Double> {
            val out = HashMap<LocalDate, Double>()
            val arr = dashboard.optJSONArray(key) ?: return out
            for (i in 0 until arr.length()) {
                val e = arr.optJSONArray(i) ?: continue
                if (e.length() < 2) continue
                val day = dayOf(e.optLong(0))
                val v = e.optDouble(1)
                if (v.isNaN()) continue
                out[day] = if (sum) (out[day] ?: 0.0) + v else v
            }
            return out
        }

        fun put(key: String, label: String, value: String, unit: String) {
            val e = m.optJSONObject(key) ?: JSONObject()
            e.put("l", label).put("v", value).put("u", unit)
            m.put(key, e)
        }
        val steps = perDay("steps", sum = false)
        // Χωρίς βήματα σήμερα ακόμα: όχι τα χθεσινά με σημερινή ώρα.
        if (steps[today] == null) m.optJSONObject("steps")?.put("v", "—")?.remove("cap")
        if (perDay("floors", sum = true)[today] == null) m.remove("floors")
        steps[today]?.let { s ->
            val e = m.optJSONObject("steps") ?: JSONObject()
            e.put("l", "Βήματα").put("v", thousands(s.toLong())).put("u", "")
            val y = steps[today.minusDays(1)]
            e.put("cap", if (y == null) "βήματα σήμερα" else "χθες ${thousands(y.toLong())}")
            e.put("s", JSONArray((6 downTo 0).map { steps[today.minusDays(it.toLong())] ?: JSONObject.NULL }))
            m.put("steps", e)
        }
        perDay("floors", sum = true)[today]?.let { put("floors", "Όροφοι", "${it.toLong()}", "") }
        dashboard.optJSONObject("activity")?.let { a ->
            if (a.has("activeCalories")) put("activeKcal", "Ενεργές", thousands(a.optDouble("activeCalories").toLong()), " kcal")
            if (a.has("calories")) put("totalKcal", "Σύνολο", thousands(a.optDouble("calories").toLong()), " kcal")
            // Round 1 (U7-13): ολόκληρη λέξη, όπως το στιγμιότυπο της εφαρμογής (widget_snapshot.dart).
            if (a.has("activeMinutes")) put("activeMin", "Ενεργός", "${a.optLong("activeMinutes")}", " λεπτά")
            if (a.has("distance")) put("distance", "Απόσταση", dec1(a.optDouble("distance") / 1000), " km")
        }
        val t = Instant.ofEpochMilli(readAt).atZone(zone).toLocalTime()
        // Locale.ROOT (τελικός έλεγχος, Συμβούλιο 4, W-5): πάντα ψηφία 0–9, σε όποια γλώσσα κι αν είναι το κινητό.
        move.put("src", "ρολόι · %02d:%02d".format(java.util.Locale.ROOT, t.hour, t.minute)).put("at", readAt).put("day", today.toString())
        kinds.put("move", move)
        writeSnapshot(ctx, snap.toString())
        updateAll(ctx, only = "move")
    }
}

abstract class HomeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ErrorQueue.install(context)
        // Έλεγχος 9/11 (D2-05b): το ξυπνητήρι των μεσανύχτων χάνεται στην επανεκκίνηση· μετά από αυτήν έρχεται onUpdate.
        HomeWidgets.ensureMidnight(context)
        for (id in ids) {
            try {
                HomeWidgets.update(context, manager, id)
            } catch (e: Throwable) {
                ErrorQueue.report(e, "widget")
            }
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle) {
        try {
            HomeWidgets.update(context, manager, id)
        } catch (e: Throwable) {
            ErrorQueue.report(e, "widget")
        }
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        HomeWidgets.forget(context, ids)
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Νέα μέρα, ή άλλαξε η ώρα / η ζώνη ώρας (D2-05b): ξανά όλα, με τον κανόνα «άλλη μέρα = —».
        if (intent.action == HomeWidgets.ACTION_DAY || intent.action == Intent.ACTION_TIME_CHANGED ||
            intent.action == Intent.ACTION_TIMEZONE_CHANGED
        ) {
            HomeWidgets.updateAll(context)
            return
        }
        super.onReceive(context, intent)
    }
}

class SleepWidget : HomeWidgetProvider()
class MoveWidget : HomeWidgetProvider()
class FoodWidget : HomeWidgetProvider()
class BodyWidget : HomeWidgetProvider()
class WorkoutWidget : HomeWidgetProvider()
class QuickFoodWidget : HomeWidgetProvider()
