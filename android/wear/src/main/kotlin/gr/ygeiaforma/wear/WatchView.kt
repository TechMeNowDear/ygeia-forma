package gr.ygeiaforma.wear

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import android.view.HapticFeedbackConstants
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import kotlin.math.abs

/**
 * Όλες οι οθόνες του ρολογιού σε ένα View (στρογγυλή οθόνη, ζωγραφισμένη με Canvas: καμία βιβλιοθήκη UI).
 * Μεγέθη σε «u» = πλάτος/200, ώστε να ταιριάζει σε κάθε ρολόι.
 * Σχέδια Α–Ε (8/11): έναρξη, σετ, διάλειμμα, όριο παλμών, περπάτημα.
 */
class WatchView(context: Context, private val actions: Actions) : View(context) {

    interface Actions {
        fun startWorkout(id: String)
        fun startWalk()
        fun joinPhone()
        fun tick()
        fun answer(rir: Int)
        fun reps(delta: Int)
        fun nextExercise()
        fun restPlus()
        fun restStop()
        /** «Τέλος» της άσκησης (όχι Activity.finish(): το «Πίσω» δεν τελειώνει την άσκηση, V-A-17). */
        fun finishWorkout()
        fun pauseWalk(on: Boolean)
        fun muteAlarm()
        fun doneOk()
        /** Διόρθωση των επαναλήψεων του σετ που μόλις έγινε (στο διάλειμμα, RT-13). */
        fun lastReps(delta: Int)
    }

    private val orange = Color.parseColor("#EA580C")
    private val green = Color.parseColor("#16A34A")
    private val red = Color.parseColor("#EF4444")
    private val alarmBg = Color.parseColor("#991B1B")
    private val gray = Color.parseColor("#9CA3AF")
    private val dim = Color.parseColor("#374151")
    private val card = Color.parseColor("#1F2937")

    // Σχέδια 9/11 (7α–7γ): κουμπιά αρχικής, ανοιχτό «Τέλος», κεχριμπάρι «προσοχή», απαλό κόκκινο-σομόν για την καρδιά.
    private val button2 = Color.parseColor("#2B303B")
    private val button3 = Color.parseColor("#1C2028")
    private val light = Color.parseColor("#E8ECF4")
    private val ink = Color.parseColor("#0F172A")
    private val amber = Color.parseColor("#F2B13C")
    private val amberSoft = Color.parseColor("#F7D9A0")
    private val amberInk = Color.parseColor("#2A1A04")
    private val salmon = Color.parseColor("#F28B6C")
    private val soft = Color.parseColor("#C7CDD8")

    /**
     * Μέγεθος γραμμάτων του ρολογιού (σχέδια 9/11): τα κείμενα της αρχικής, του περπατήματος και της οθόνης «δεν
     * έρχονται παλμοί» ακολουθούν τη ρύθμιση του ρολογιού, ως 1,3×.
     */
    private val fs: Float get() = resources.configuration.fontScale.coerceIn(1f, 1.3f)

    /**
     * Ελάχιστο μέγεθος για ό,τι χρειάζεται για ασφάλεια ή ενέργεια (έλεγχος γ2, W3-09): 10u ≈ 12 sp στο Ultra 2, και
     * μεγαλύτερο με το μέγεθος γραμμάτων του ρολογιού.
     */
    private fun ess(size: Float): Float = maxOf(size, 10f) * fs

    /**
     * «Δεν έρχονται παλμοί» με όριο γιατρού (σχέδια 9/11, 7γ): όλη η οθόνη, μία φορά για κάθε σιωπή. Μετά το
     * «Εντάξει» μένει «♥ —» σε κεχριμπάρι ώσπου να ξαναέρθουν παλμοί. Μόνο εμφάνιση· η δόνηση είναι όπως πριν.
     */
    var noHrSeen: Boolean
        get() = noHrSeenNow
        set(v) {
            noHrSeenNow = v
        }

    companion object {
        /** Κρατιέται και αν ξαναφτιαχτεί η οθόνη (π.χ. αλλαγή μεγέθους γραμμάτων), για να μη ξαναβγεί (N3). */
        @JvmStatic
        internal var noHrSeenNow = false
    }

    private val text = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }

    /**
     * Κάτι που πατιέται ([run]) ή μόνο διαβάζεται από το TalkBack ([run] = null), με την περιγραφή του ([label]).
     * Έλεγχος γ2 (W3-09): πριν, το TalkBack δεν έβρισκε τίποτα στην οθόνη (ζωγραφισμένη σε ένα View).
     */
    private class Hit(val r: RectF, val label: String, val run: (() -> Unit)?)
    private val hits = mutableListOf<Hit>()

    /** Για το TalkBack: οι περιοχές της τελευταίας εικόνας (η πρώτη = τι δείχνει η οθόνη, μετά τα κουμπιά). */
    internal val a11yItems: List<Pair<String, Boolean>> get() = a11y.map { it.label to (it.run != null) }
    private var a11y: List<Hit> = emptyList()

    /** Τι δείχνει η οθόνη, σε μία φράση για το TalkBack (η πρώτη περιοχή). */
    private var say = ""

    /** Ένα κουμπί για το TalkBack ([index] στη σειρά του [a11yItems]): «πάτημα». */
    internal fun a11yClick(index: Int): Boolean {
        val h = a11y.getOrNull(index)?.run ?: return false
        h()
        invalidate()
        return true
    }

    /** Η προπόνηση που δείχνει η αρχική (μπορεί να αλλάξει με πάτημα στο όνομα). */
    var chosen: String? = null

    /**
     * Ambient (αχνή οθόνη «πάντα ανοιχτή», έλεγχος 9/11, W3-08): μαύρο φόντο, μόνο λευκά/γκρι γράμματα χωρίς εξομάλυνση
     * (οθόνες με λίγα bit), καθόλου γεμάτα σχήματα ή κουμπιά, χρόνος σε λεπτά (ανανέωση μία φορά το λεπτό).
     */
    var ambient = false
        set(v) {
            if (field == v) return
            field = v
            text.isAntiAlias = !v
            invalidate()
        }

    private var u = 1f
    private var cx = 0f
    private var cy = 0f

    init {
        isFocusable = true
        isFocusableInTouchMode = true
    }

    override fun onDraw(c: Canvas) {
        hits.clear()
        say = ""
        drawScreen(c)
        // Η πρώτη περιοχή για το TalkBack: τι δείχνει η οθόνη· μετά τα κουμπιά με τη σειρά που ζωγραφίστηκαν.
        val next = buildList {
            if (say.isNotEmpty()) add(Hit(RectF(0f, 0f, width.toFloat(), height * 0.3f), say, null))
            addAll(hits.filter { it.label.isNotEmpty() })
        }
        val changed = next.map { it.label } != a11y.map { it.label }
        a11y = next
        if (changed) {
            try {
                sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
            } catch (_: Exception) {
            }
        }
    }

    private fun drawScreen(c: Canvas) {
        u = width / 200f
        cx = width / 2f
        cy = height / 2f
        val now = System.currentTimeMillis()
        if (ambient) {
            c.drawColor(Color.BLACK)
            drawAmbient(c, now)
            return
        }
        val alarm = Repo.alarmShown(now)
        c.drawColor(if (alarm) alarmBg else Color.BLACK)
        if (alarm) {
            drawAlarm(c)
            return
        }
        val note = Repo.notice
        if (noticeOpen && note != null) {
            drawNotice(c, note)
            return
        }
        noticeOpen = false
        if (Repo.hrSilent == null) noHrSeen = false
        if (!noHrSeen && Repo.running != null && Repo.alarm.limit != null && Repo.hrSilent != null &&
            Repo.screen != Repo.Screen.HOME && Repo.screen != Repo.Screen.END && Repo.screen != Repo.Screen.RECOVER
        ) {
            drawNoHr(c)
            return
        }
        // Πάτημα στο μήνυμα: ολόκληρο (π.χ. η αιτία όταν δεν ξεκινά η μέτρηση· 9/11). Πρώτο στη λίστα, ώστε τα
        // κουμπιά της οθόνης να κερδίζουν όπου ακουμπούν.
        val noteY = if (Repo.screen == Repo.Screen.WALK) 135f else 186f
        if (note != null) hits.add(Hit(RectF(cx - 60 * u, (noteY - 10) * u, cx + 60 * u, (noteY + 12) * u), note) { noticeOpen = true; invalidate() })
        when (Repo.screen) {
            Repo.Screen.HOME -> drawHome(c)
            Repo.Screen.SET -> drawSet(c, now)
            Repo.Screen.RIR -> drawRir(c)
            Repo.Screen.REST -> drawRest(c, now)
            Repo.Screen.WALK -> drawWalk(c, now)
            Repo.Screen.RECOVER -> drawRecover(c, now)
            Repo.Screen.END -> drawEnd(c)
        }
        // Στο «Αποθηκεύτηκε» το μήνυμα (π.χ. «σώθηκε ως τις…») γράφεται ολόκληρο μέσα στην οθόνη (drawEnd). Στο
        // περπάτημα πιο ψηλά, στη θέση του «χωρίς GPS» (κάτω είναι τα κουμπιά, έλεγχος γ2, Μ3/RT-18).
        if (note != null && Repo.screen == Repo.Screen.WALK) small(c, note, 135f, amber, ess(10f), 160f)
        else if (note != null && Repo.screen != Repo.Screen.END) noteLines(c, note)
    }

    private var noticeOpen = false

    /**
     * Μήνυμα κάτω στη στρογγυλή οθόνη, σε ως δύο γραμμές (η κάτω πιο στενή): ολόκληρο το «Πάτα ξανά: τέλος και στο
     * κινητό» κ.λπ., όχι κομμένο στις άκρες (W3-09). Πάτημα: ολόκληρο, σε όλη την οθόνη.
     */
    private fun noteLines(c: Canvas, note: String) {
        val sz = ess(10f)
        text.textSize = sz * u
        text.typeface = Typeface.DEFAULT
        // Δύο γραμμές μόνο στην οθόνη του σετ (εκεί κάτω είναι μόνο το «Τέλος», που κρύβεται όσο φαίνεται το μήνυμα).
        if (Repo.screen != Repo.Screen.SET || text.measureText(note) <= 96f * u) {
            small(c, note, 186f, soft, sz, 100f)
            return
        }
        val words = note.split(' ')
        var best = 1
        var bestDiff = Float.MAX_VALUE
        for (k in 1 until words.size) {
            val a = text.measureText(words.take(k).joinToString(" "))
            val b = text.measureText(words.drop(k).joinToString(" "))
            // η πάνω γραμμή χωρά πιο πολύ (πιο φαρδιά εκεί η οθόνη)
            val diff = maxOf(a - 120f * u, b - 96f * u)
            if (diff < bestDiff) {
                bestDiff = diff
                best = k
            }
        }
        small(c, words.take(best).joinToString(" "), 176f, soft, sz, 124f)
        small(c, words.drop(best).joinToString(" "), 176f + sz * 1.1f, soft, sz, 98f)
    }

    /** Ambient: τα βασικά μόνο, λευκό/γκρι σε μαύρο, χωρίς δευτερόλεπτα. Δεν πατιέται τίποτα. */
    private fun drawAmbient(c: Canvas, now: Long) {
        val light = Color.WHITE
        val dimText = Color.parseColor("#8A8A8A")
        when {
            Repo.running == "walk" -> {
                small(c, if (Repo.paused) "ΠΑΥΣΗ" else "ΠΕΡΠΑΤΗΜΑ", 56f, dimText, 9f, 120f)
                val sec = Repo.activeSecNow(now).let { if (it > 0) it else (now - Repo.startedAt) / 1000 }
                t(c, "${sec / 60}′", 100f, light, 30f, true)
                if (Repo.meters > 0) small(c, "${km(Repo.meters)} km", 124f, light, 11f, 150f)
                Repo.alarm.limit?.let { small(c, "όριο παλμών $it", 146f, dimText, 9f, 130f) }
            }
            Repo.session != null && Repo.running != null -> {
                val s = Repo.session!!
                val it = s.current
                small(c, s.name, 64f, dimText, 9f, 140f)
                if (it != null) {
                    t(c, it.name, 96f, light, 12f, true)
                    val si = it.nextSet.let { n -> if (n < 0) it.sets.size - 1 else n }
                    small(c, "ΣΕΤ ${si + 1}/${it.sets.size}", 118f, dimText, 9f, 120f)
                }
                if (Repo.startedAt > 0) small(c, "${(now - Repo.startedAt) / 60_000}′", 142f, light, 11f, 120f)
            }
            else -> {
                t(c, "Υγεία & Φόρμα", 100f, dimText, 11f, true)
            }
        }
    }

    /** Ολόκληρο το μήνυμα, σε πολλές γραμμές· πάτημα οπουδήποτε κλείνει. */
    private fun drawNotice(c: Canvas, note: String) {
        text.color = Color.WHITE
        text.textSize = ess(10f) * u
        text.typeface = Typeface.DEFAULT
        val w = (150f * u).toInt()
        val tp = android.text.TextPaint(text).apply { textAlign = Paint.Align.LEFT }
        val layout = android.text.StaticLayout.Builder.obtain(note, 0, note.length, tp, w)
            .setAlignment(android.text.Layout.Alignment.ALIGN_CENTER)
            .setMaxLines(9)
            .build()
        c.save()
        c.translate(cx - w / 2f, cy - layout.height / 2f)
        layout.draw(c)
        c.restore()
        say = note
        hits.add(Hit(RectF(0f, 0f, width.toFloat(), height.toFloat()), "Κλείσιμο") { noticeOpen = false; invalidate() })
    }

    // ------------------------------------------------------------------ βοηθητικά
    private fun t(c: Canvas, s: String, y: Float, color: Int, size: Float, bold: Boolean = false, maxW: Float = 150f) {
        text.color = color
        text.textSize = size * u
        text.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        val shown = TextUtils.ellipsize(s, text, maxW * u, TextUtils.TruncateAt.END).toString()
        c.drawText(shown, cx, y * u, text)
    }

    /** Κείμενο που μικραίνει ώσπου να χωρέσει (π.χ. «πράσινο + μπλε (50 lb)» στη θέση των κιλών). */
    private fun fit(c: Canvas, s: String, y: Float, color: Int, size: Float, maxW: Float) {
        text.typeface = Typeface.DEFAULT_BOLD
        text.color = color
        var sz = size
        text.textSize = sz * u
        while (text.measureText(s) > maxW * u && sz > 9f) {
            sz -= 1f
            text.textSize = sz * u
        }
        c.drawText(s, cx, y * u, text)
    }

    private fun small(c: Canvas, s: String, y: Float, color: Int, size: Float, maxW: Float) = t(c, s, y, color, size, false, maxW)

    private fun pill(
        c: Canvas, label: String, y: Float, w: Float, h: Float, bg: Int, fg: Int, size: Float = 12f,
        desc: String = label, padTop: Float = 6f, padBottom: Float = 6f, run: () -> Unit,
    ) {
        val r = RectF(cx - w * u / 2, (y - h / 2) * u, cx + w * u / 2, (y + h / 2) * u)
        fill.color = bg
        c.drawRoundRect(r, h * u / 2, h * u / 2, fill)
        text.color = fg
        text.textSize = size * u
        text.typeface = Typeface.DEFAULT_BOLD
        c.drawText(label, cx, r.centerY() - (text.descent() + text.ascent()) / 2, text)
        // Λίγο μεγαλύτερη περιοχή πατήματος από το σχήμα (δάχτυλο σε μικρή οθόνη).
        hits.add(Hit(RectF(r.left - 6 * u, r.top - padTop * u, r.right + 6 * u, r.bottom + padBottom * u), desc, run))
    }

    private fun pillAt(c: Canvas, label: String, x: Float, y: Float, w: Float, h: Float, bg: Int, fg: Int, size: Float, desc: String = label, run: () -> Unit) {
        val r = RectF((x - w / 2) * u, (y - h / 2) * u, (x + w / 2) * u, (y + h / 2) * u)
        fill.color = bg
        c.drawRoundRect(r, h * u / 2, h * u / 2, fill)
        text.color = fg
        text.textSize = size * u
        text.typeface = Typeface.DEFAULT_BOLD
        c.drawText(label, r.centerX(), r.centerY() - (text.descent() + text.ascent()) / 2, text)
        hits.add(Hit(RectF(r.left - 4 * u, r.top - 6 * u, r.right + 4 * u, r.bottom + 6 * u), desc, run))
    }

    /**
     * Κουμπί − / + (έλεγχος γ2, W3-09): κύκλος [d] u και περιοχή πατήματος [hw]×[hh] u (≥ 40u ≈ 48 dp), ως την άκρη της
     * οθόνης προς τα έξω, ώστε να μην ακουμπά το ✓.
     */
    private fun roundKey(c: Canvas, label: String, x: Float, y: Float, d: Float, hw: Float, hh: Float, desc: String, run: () -> Unit) {
        fill.color = card
        c.drawCircle(x * u, y * u, d * u / 2, fill)
        text.color = Color.WHITE
        text.textSize = d * 0.62f * u
        text.typeface = Typeface.DEFAULT_BOLD
        c.drawText(label, x * u, y * u - (text.descent() + text.ascent()) / 2, text)
        val left = if (x < 100f) 0f else (x - hw / 2) * u
        val right = if (x < 100f) (x + hw / 2) * u else width.toFloat()
        hits.add(Hit(RectF(left, (y - hh / 2) * u, right, (y + hh / 2) * u), desc, run))
    }

    private fun heart(c: Canvas, y: Float, now: Long, size: Float = 12f) {
        val fresh = Repo.hrLive(now)
        val over = fresh && Repo.alarm.limit != null && Repo.bpm >= Repo.alarm.limit!!
        if (!fresh && Repo.running != null) {
            // Δεν φτάνουν τιμές: να φαίνεται, όχι μια παύλα που μοιάζει με «όλα καλά».
            t(c, "♥ δεν μετριούνται", y, if (Repo.alarm.limit != null) amber else gray, ess(size * 0.75f), true)
            // Με όριο γιατρού (έλεγχος 9/11, V-A-04): ξεκάθαρα ότι το όριο δεν σε προσέχει τώρα. Μόνο μετά την αναμονή (ίδια
            // στιγμή με τη δόνηση και με το κινητό), όχι στα πρώτα δευτερόλεπτα κάθε έναρξης.
            val off = Repo.alarm.limit != null && Repo.hrSilent != null
            if (off) t(c, "το όριο δεν σε προσέχει", y + ess(10f) * 1.05f, amber, ess(10f), false, 150f)
            sayAdd(if (off) "Δεν μετριούνται παλμοί. Το όριο δεν σε προσέχει." else "Δεν μετριούνται παλμοί.")
            return
        }
        val s = if (fresh) "♥ ${Repo.bpm}" else "♥ —"
        t(c, s, y, if (over) red else if (fresh) Color.WHITE else gray, size * fs, true)
        if (fresh) sayAdd("Παλμοί ${Repo.bpm}" + (Repo.alarm.limit?.let { ", όριο $it" } ?: ""))
        if (fresh) {
            // Μικρή γραμμή με το όριο του γιατρού κάτω από τους παλμούς.
            val lim = Repo.alarm.limit ?: return
            val w = 60f
            val x0 = cx - w * u / 2
            val yy = (y + 4) * u
            fill.color = dim
            c.drawRoundRect(RectF(x0, yy, x0 + w * u, yy + 2.4f * u), u, u, fill)
            val lo = 60f
            val hi = lim + 20f
            val p = ((Repo.bpm - lo) / (hi - lo)).coerceIn(0f, 1f)
            fill.color = if (over) red else orange
            c.drawRoundRect(RectF(x0, yy, x0 + w * u * p, yy + 2.4f * u), u, u, fill)
            val lp = ((lim - lo) / (hi - lo)).coerceIn(0f, 1f)
            fill.color = Color.WHITE
            c.drawRect(RectF(x0 + w * u * lp - 0.6f * u, yy - 1.5f * u, x0 + w * u * lp + 0.6f * u, yy + 3.9f * u), fill)
        }
    }

    /** Προσθήκη στη φράση του TalkBack για αυτή την οθόνη. */
    private fun sayAdd(x: String) {
        say = if (say.isEmpty()) x else "$say. $x"
    }

    // ------------------------------------------------------------------ Α. έναρξη
    private fun drawHome(c: Canvas) {
        val plan = Repo.plan
        val phone = Repo.phone
        if (Repo.updateNeeded) {
            // Πρόγραμμα από νεότερη έκδοση του κινητού (V-A-08): δεν διαβάστηκε. Κάτω, εκεί που δεν πέφτει πάνω σε τίποτα.
            small(c, "Ενημέρωσε την εφαρμογή", 170f, orange, ess(10f), 130f)
            small(c, "στο ρολόι", 170f + ess(10f) * 1.1f, orange, ess(10f), 90f)
            sayAdd("Ενημέρωσε την εφαρμογή στο ρολόι")
        }
        if (phone != null && !phone.ended) {
            small(c, "ΣΤΟ ΚΙΝΗΤΟ", 50f, gray, ess(10f), 120f)
            t(c, phone.name, 72f, Color.WHITE, 15f * fs, true)
            small(c, "${phone.setsDone} σετ ως τώρα", 90f, gray, ess(10f), 130f)
            sayAdd("Στο κινητό: ${phone.name}, ${phone.setsDone} σετ ως τώρα")
            pill(c, "Παλμοί εδώ", 118f, 110f, 34f, orange, Color.WHITE, 13f * fs, padBottom = 2f) { actions.joinPhone() }
            // Και περπάτημα από εδώ, ακόμα κι αν η προπόνηση του κινητού έμεινε ανοιχτή (έλεγχος 9/11, V-A-09). Κουμπί
            // (έλεγχος γ2, W3-09), όχι σκέτο κείμενο.
            pill(c, "Περπάτημα", 157f, 96f, 30f, button2, Color.WHITE, 11.5f * fs, padTop = 2f) { actions.startWalk() }
            return
        }
        if (plan != null || Repo.knownLimit != null) {
            // Το όριο που ισχύει, πριν ξεκινήσεις (έλεγχος 8/11)· και χωρίς πρόγραμμα, το τελευταίο που ήρθε (V-A-06).
            val lim = Repo.limitNow()
            // «Σήμερα» μόνο όταν το πρώτο κουμπί είναι η σημερινή· αλλιώς «Άλλη» (N5).
            val isToday = chosen == null || chosen == plan?.todayWorkout?.id
            if (!Repo.updateNeeded) twoTone(c, if (isToday) "Σήμερα · " else "Άλλη προπόνηση · ", if (lim != null) "όριο $lim" else "χωρίς όριο", 33f, if (lim != null) salmon else gray, 10.5f * fs)
        }
        val strength = plan?.workouts?.filter { !it.isCardio && it.items.isNotEmpty() }.orEmpty()
        val today = plan?.todayWorkout
        val shown = plan?.workout(chosen) ?: today?.takeIf { !it.isCardio } ?: strength.firstOrNull()
        when {
            plan == null -> {
                small(c, "ΥΓΕΙΑ & ΦΟΡΜΑ", 56f, gray, ess(10f), 120f)
                t(c, "Άνοιξε την εφαρμογή", 80f, Color.WHITE, 12f * fs, true)
                t(c, "στο κινητό", 80f + 16f * fs, Color.WHITE, 12f * fs, true)
                sayAdd("Άνοιξε την εφαρμογή στο κινητό")
                pill(c, "Περπάτημα", 136f, 104f, 34f, card, Color.WHITE, 12f * fs) { actions.startWalk() }
            }
            today?.isCardio == true && chosen == null -> {
                // Μέρα περπατήματος: πρώτο το περπάτημα, δεύτερη η προπόνηση με βάρη.
                val w = strength.firstOrNull()
                homeButton(c, today.cardio?.name ?: "Περπάτημα", "${today.cardio?.minutes ?: 30} λ${today.cardio?.note?.let { " · $it" } ?: ""}",
                    44f, orange, Color.WHITE) { actions.startWalk() }
                if (w != null) homeButton(c, w.name, null, 92f, button2, Color.WHITE) { actions.startWorkout(w.id) }
            }
            shown != null -> {
                // Σχέδια 9/11 (7α): δύο ίσα κουμπιά ~48 dp και η άλλη προπόνηση τρίτη, χωρίς κρυφή χειρονομία.
                homeButton(c, shown.name, "${countText(shown.items.size, "άσκηση", "ασκήσεις")} · ${shown.minutes} λ", 44f, orange, Color.WHITE) {
                    actions.startWorkout(shown.id)
                }
                homeButton(c, "Περπάτημα", null, 92f, button2, Color.WHITE) { actions.startWalk() }
                val otherId = nextStrength(strength.map { it.id }, shown.id)
                val other = strength.firstOrNull { it.id == otherId }
                if (other != null) {
                    // Πάτημα: έρχεται πρώτη (δεν ξεκινά αμέσως· μία απόφαση ανά οθόνη). Η επόμενη στη σειρά του
                    // προγράμματος, κυκλικά: με 3+ προπονήσεις φτάνεις σε όλες (έλεγχος premium, M4).
                    homeButton(c, other.name, null, 138f, button3, soft, h = 36f, w = 116f, size = 11f) { chosen = other.id; invalidate() }
                }
            }
            else -> {
                small(c, "ΣΗΜΕΡΑ", 56f, gray, ess(10f), 120f)
                t(c, "Ξεκούραση", 80f, Color.WHITE, 15f * fs, true)
                sayAdd("Σήμερα ξεκούραση")
                pill(c, "Περπάτημα", 124f, 104f, 34f, card, Color.WHITE, 12f * fs) { actions.startWalk() }
            }
        }
    }

    // ------------------------------------------------------------------ Β. σετ
    /**
     * Έλεγχος γ2 (W3-09): − / + με περιοχή ≥ 40u (≈ 48 dp) ως την άκρη, που δεν ακουμπά το ✓· το ✓ πατιέται μόνο από το
     * σχήμα του και κάτω· «Τέλος» κουμπί-χάπι· γράμματα ≥ 10u και με το μέγεθος του ρολογιού.
     */
    private fun drawSet(c: Canvas, now: Long) {
        val s = Repo.session ?: return drawHome(c)
        // «Ελεύθερη άσκηση» του κινητού χωρίς ασκήσεις ακόμα (9/11): οι παλμοί μετράνε, η άσκηση διαλέγεται στο κινητό.
        if (s.phone && s.items.isEmpty()) return drawPickOnPhone(c, now)
        // Όλες οι ασκήσεις έγιναν (W3-13): όχι ένα ✓ που δεν κάνει τίποτα.
        if (s.phone && s.allDone) return if (s.workout == "_free") drawPickOnPhone(c, now, next = true) else drawAllDone(c, now)
        val it = s.current ?: return drawEnd(c)
        heart(c, 34f, now, 11f)
        val si = it.nextSet.let { n -> if (n < 0) it.sets.size - 1 else n }
        val set = it.sets.getOrNull(si)
        // Όνομα άσκησης: πάτημα = επόμενη άσκηση (δύο πατήματα).
        small(c, it.name, 52f, Color.WHITE, 10.5f * fs, 140f)
        small(c, "ΣΕΤ ${si + 1}/${it.sets.size}" + if (s.items.size > 1) "  ›" else "", 52f + 12.5f * fs, gray, ess(10f), 120f)
        sayAdd("${it.name}, σετ ${si + 1} από ${it.sets.size}" + (set?.let { x -> (if (x.label.isNotEmpty()) ", ${x.label}" else "") + ", ${x.reps} επαναλήψεις" } ?: ""))
        if (s.items.size > 1) hits.add(Hit(RectF(cx - 75 * u, 42 * u, cx + 75 * u, 70 * u), "Επόμενη άσκηση") { actions.nextExercise() })
        if (set != null) {
            val noLabel = set.label.isEmpty()
            if (!noLabel) fit(c, set.label, 92f, Color.WHITE, 24f, 150f)
            // Επαναλήψεις με − / + (και με την περιστροφή).
            text.typeface = Typeface.DEFAULT_BOLD
            val ry = if (noLabel) 100f else 114f
            t(c, "× ${set.reps}", ry + (if (noLabel) 9f else 5.5f) * fs, Color.WHITE, (if (noLabel) 26f else 16f) * fs, true)
            roundKey(c, "−", 42f, ry, 26f, 44f, 40f, "Μία επανάληψη λιγότερη") { actions.reps(-1) }
            roundKey(c, "+", 158f, ry, 26f, 44f, 40f, "Μία επανάληψη παραπάνω") { actions.reps(1) }
        }
        // Το ✓ πατιέται από το σχήμα του και κάτω (όχι πάνω από αυτό, όπου είναι τα − / +).
        // (κενό 2u από την περιοχή των − / +, ώστε κανένα σημείο να μην είναι και των δύο).
        pill(c, "✓", 152f, 84f, 32f, green, Color.WHITE, 18f, desc = "Έγινε το σετ", padTop = 0f, padBottom = 0f) { actions.tick() }
        if (Repo.notice == null) pill(c, "Τέλος", 182f, 56f, 22f, button3, soft, ess(10f), padTop = 2f, padBottom = 8f) { actions.finishWorkout() }
        else hits.add(Hit(RectF(cx - 30 * u, 170 * u, cx + 30 * u, 198 * u), "Τέλος") { actions.finishWorkout() })
    }

    private fun drawPickOnPhone(c: Canvas, now: Long, next: Boolean = false) {
        heart(c, 50f, now)
        if (next) {
            small(c, "Διάλεξε επόμενη", 82f, Color.WHITE, 13f * fs, 150f)
            small(c, "άσκηση στο κινητό", 82f + 16f * fs, Color.WHITE, 13f * fs, 150f)
            small(c, "${s0()} σετ ως τώρα", 82f + 32f * fs, gray, ess(10f), 140f)
            sayAdd("Διάλεξε επόμενη άσκηση στο κινητό. ${s0()} σετ ως τώρα")
        } else {
            t(c, "Διάλεξε άσκηση", 90f, Color.WHITE, 14f * fs, true)
            t(c, "στο κινητό", 90f + 19f * fs, Color.WHITE, 14f * fs, true)
            sayAdd("Διάλεξε άσκηση στο κινητό")
        }
        small(c, if (Repo.bpmFresh(now)) "οι παλμοί ήδη μετράνε" else "περιμένω παλμούς", 140f, gray, ess(10f), 150f)
        if (Repo.notice == null) pill(c, "Τέλος", 172f, 64f, 26f, button3, soft, ess(10f), padTop = 4f, padBottom = 8f) { actions.finishWorkout() }
        else hits.add(Hit(RectF(cx - 30 * u, 170 * u, cx + 30 * u, 198 * u), "Τέλος") { actions.finishWorkout() })
    }

    private fun s0(): Int = Repo.session?.setsDone ?: 0

    /** Προπόνηση του κινητού με όλα τα σετ ✓: τέλος εδώ ή στο κινητό. */
    private fun drawAllDone(c: Canvas, now: Long) {
        heart(c, 50f, now)
        t(c, "✓", 86f, green, 22f, true)
        t(c, "Όλα τα σετ έγιναν", 106f, Color.WHITE, 12f * fs, true)
        small(c, "Τέλος εδώ ή στο κινητό", 106f + 15f * fs, gray, ess(10f), 150f)
        sayAdd("Όλα τα σετ έγιναν. Τέλος εδώ ή στο κινητό")
        pill(c, "Τέλος", 158f, 88f, 34f, card, Color.WHITE, 12f * fs) { actions.finishWorkout() }
    }

    // ------------------------------------------------------------------ ρεζέρβα
    private fun drawRir(c: Canvas) {
        t(c, "Πόσες ακόμα", 54f, Color.WHITE, 12f * fs, true)
        t(c, "θα έβγαζες;", 54f + 15f * fs, Color.WHITE, 12f * fs, true)
        sayAdd("Πόσες επαναλήψεις ακόμα θα έβγαζες με καλή τεχνική;")
        val labels = listOf("0", "1", "2", "3", "4+")
        val descs = listOf("Καμία", "Μία", "Δύο", "Τρεις", "Τέσσερις ή περισσότερες")
        // Δύο σειρές: 0 1 2 / 3 4+ (μεγάλα κουμπιά για τον καρπό· περιοχή ~40u ≈ 48 dp).
        val row1 = listOf(60f, 100f, 140f)
        for (i in 0..2) pillAt(c, labels[i], row1[i], 100f, 34f, 30f, card, Color.WHITE, 14f * fs, descs[i]) { actions.answer(i) }
        pillAt(c, labels[3], 80f, 138f, 34f, 30f, card, Color.WHITE, 14f * fs, descs[3]) { actions.answer(3) }
        pillAt(c, labels[4], 120f, 138f, 34f, 30f, card, Color.WHITE, 14f * fs, descs[4]) { actions.answer(4) }
        small(c, "με καλή τεχνική", 170f, gray, ess(10f), 110f)
    }

    // ------------------------------------------------------------------ Γ. διάλειμμα
    private fun drawRest(c: Canvas, now: Long) {
        val s = Repo.session ?: return drawHome(c)
        val left = ((s.restEnd - now) / 1000L).coerceAtLeast(0)
        // Το δαχτυλίδι με όλο το διάλειμμα που ξεκίνησε (έλεγχος γ2, W2-20), όχι με της άσκησης που ακολουθεί.
        val p = s.restLeft(now)
        val pad = 6 * u
        ring.strokeWidth = 5 * u
        ring.color = dim
        val box = RectF(pad, pad, width - pad, height - pad)
        c.drawArc(box, -90f, 360f, false, ring)
        ring.color = orange
        c.drawArc(box, -90f, 360f * p, false, ring)
        small(c, "ΔΙΑΛΕΙΜΜΑ", 44f, gray, ess(10f), 120f)
        t(c, clock(left), 78f, Color.WHITE, 30f * fs, true)
        sayAdd("Διάλειμμα, μένουν ${clock(left)}")
        heart(c, 96f, now, 11f)
        // Το σετ που μόλις έγινε, με διόρθωση (έλεγχος γ2, RT-13): το ✓ γράφει τον στόχο· αν έκανες άλλες, άλλαξέ το εδώ.
        val done = s.lastDone(now)
        if (done != null) {
            val reps = s.items[done.first].sets[done.second].reps
            small(c, "έκανες × $reps", 119f, Color.WHITE, 12f * fs, 80f)
            sayAdd("Έκανες $reps επαναλήψεις")
            roundKey(c, "−", 46f, 115f, 22f, 44f, 34f, "Έκανες μία λιγότερη") { actions.lastReps(-1) }
            roundKey(c, "+", 154f, 115f, 22f, 44f, 34f, "Έκανες μία παραπάνω") { actions.lastReps(1) }
        }
        val it = s.current
        val si = it?.nextSet ?: -1
        if (it != null && si >= 0) {
            val set = it.sets[si]
            val nextText = "επόμενο: ${if (si == 0) it.name else "σετ ${si + 1}"} · ${set.label.ifEmpty { "" }}${if (set.label.isEmpty()) "" else " "}× ${set.reps}"
            small(c, nextText, 141f, gray, ess(10f), 160f)
            sayAdd(nextText)
        }
        pillAt(c, "+30″", 76f, 168f, 44f, 26f, card, Color.WHITE, 11f * fs, "Τριάντα δευτερόλεπτα ακόμα") { actions.restPlus() }
        pillAt(c, "Πάμε", 124f, 168f, 44f, 26f, Color.WHITE, Color.BLACK, 11f * fs, "Τέλος διαλείμματος") { actions.restStop() }
    }

    // ------------------------------------------------------------------ Δ. όριο παλμών
    private fun drawAlarm(c: Canvas) {
        val now = System.currentTimeMillis()
        val walk = Repo.running == "walk"
        val rec = Repo.recoveryUntil > 0
        small(c, "ΠΑΝΩ ΑΠΟ ΤΟ ΟΡΙΟ", 56f, Color.WHITE, ess(10f), 140f)
        t(c, "♥ ${Repo.bpm}", 94f, Color.WHITE, 30f, true)
        // Παλιός αριθμός (δεν έρχονται παλμοί): με την ηλικία του, όχι σαν τωρινός (W2-16).
        val stale = !Repo.bpmFresh(now) && Repo.bpmAt > 0
        if (stale) small(c, "παλμοί πριν ${clockAgo(now - Repo.bpmAt)}", 108f, Color.parseColor("#FCA5A5"), ess(10f), 140f)
        t(c, alarmHeadline(walk, rec), 126f, Color.WHITE, 14f * fs, true)
        // Όχι «μέχρι κάτω από 140»: η κόκκινη οθόνη σβήνει λίγο πιο κάτω (W2-16).
        small(c, "όριο γιατρού ${Repo.alarm.limit ?: ""}", 126f + 15f * fs, Color.WHITE, ess(10.5f), 140f)
        small(c, "πάτα για να κλείσει", 166f + 4f * (fs - 1f) * 10f, Color.parseColor("#FCA5A5"), ess(10f), 120f)
        sayAdd("Πάνω από το όριο. Παλμοί ${Repo.bpm}. ${alarmHeadline(walk, rec)}. Όριο γιατρού ${Repo.alarm.limit ?: ""}")
        hits.add(Hit(RectF(0f, 0f, width.toFloat(), height.toFloat()), "Κλείσιμο για ένα λεπτό") { actions.muteAlarm() })
    }

    /** «40″» / «3′» για «παλμοί πριν …». */
    private fun clockAgo(ms: Long): String = if (ms < 60_000) "${ms / 1000}″" else "${ms / 60_000}′"

    // ------------------------------------------------------------------ Ε. περπάτημα
    private fun drawWalk(c: Canvas, now: Long) {
        // Σχέδια 9/11 (7β): μεγάλος χρόνος, «2,18 km · 11:15 /km», παλμοί με όριο, «Παύση» σκούρο και «Τέλος» ανοιχτό.
        text.letterSpacing = 0.08f
        small(c, if (Repo.paused) "ΠΑΥΣΗ" else "ΠΕΡΠΑΤΗΜΑ", 33f, if (Repo.paused) orange else soft, 9.5f * fs, 120f)
        text.letterSpacing = 0f
        // Ο χρόνος προχωρά κάθε δευτερόλεπτο από το σημείο ελέγχου του Health Services (W3-12).
        val sec = Repo.activeSecNow(now).let { if (it > 0 || Repo.cpWall > 0) it else (now - Repo.startedAt) / 1000 }
        fit(c, clock(sec), 78f, if (Repo.paused) gray else Color.WHITE, 40f * fs, 150f)
        val dist = if (Repo.meters > 0) "${km(Repo.meters)} km · ${pace(Repo.meters, sec)}" else if (Repo.steps > 0) "${Repo.steps} βήματα" else "—"
        text.typeface = Typeface.DEFAULT_BOLD
        fitPlain(c, dist, 96f, Color.WHITE, 10.5f * fs, 150f)
        walkHeart(c, 117f, now)
        sayAdd("${if (Repo.paused) "Παύση" else "Περπάτημα"}, ${clock(sec)}, $dist")
        // Χωρίς όριο ή χωρίς GPS: να φαίνεται (W3-18), όχι σιωπηλά. Αν υπάρχει μήνυμα, γράφεται εδώ στη θέση τους.
        val tags = listOfNotNull(if (!Repo.gps) "χωρίς GPS" else null, if (Repo.alarm.limit == null) "χωρίς όριο παλμών" else null)
        if (tags.isNotEmpty() && Repo.notice == null) {
            small(c, tags.joinToString(" · "), 135f, gray, ess(10f), 160f)
            sayAdd(tags.joinToString(", "))
        }
        // Παύση/Συνέχεια αριστερά, Τέλος δεξιά (δύο πατήματα, όπως πριν). ~40 u ≈ 48 dp ύψος.
        pillAt(c, if (Repo.paused) "Συνέχεια" else "Παύση", 69f, 158f, 60f, 36f, if (Repo.paused) orange else button2, Color.WHITE, 11.5f * fs) {
            actions.pauseWalk(!Repo.paused)
        }
        pillAt(c, "Τέλος", 133f, 158f, 60f, 36f, light, ink, 11.5f * fs, "Τέλος περπατήματος") { actions.finishWorkout() }
    }

    /** «♥ 104  όριο 140» και γραμμή ως το όριο· χωρίς παλμούς «♥ —» (κεχριμπάρι με όριο). */
    private fun walkHeart(c: Canvas, y: Float, now: Long) {
        val fresh = Repo.hrLive(now)
        val lim = Repo.alarm.limit
        val over = fresh && lim != null && Repo.bpm >= lim
        if (!fresh && Repo.running != null && lim == null) {
            t(c, "♥ δεν μετριούνται", y, gray, ess(10f), true)
            sayAdd("Δεν μετριούνται παλμοί")
            return
        }
        sayAdd(if (fresh) "Παλμοί ${Repo.bpm}" + (lim?.let { ", όριο $it" } ?: "") else "Δεν μετριούνται παλμοί, το όριο δεν σε προσέχει")
        val heartC = if (!fresh) amber else if (over) red else salmon
        val num = if (fresh) "${Repo.bpm}" else "—"
        val tail = if (lim != null) "   όριο $lim" else ""
        text.textSize = 15f * fs * u
        text.typeface = Typeface.DEFAULT_BOLD
        val wHeart = text.measureText("♥ ")
        val wNum = text.measureText(num)
        text.textSize = 9.5f * fs * u
        text.typeface = Typeface.DEFAULT
        val wTail = text.measureText(tail)
        var x = cx - (wHeart + wNum + wTail) / 2
        val old = text.textAlign
        text.textAlign = Paint.Align.LEFT
        text.textSize = 15f * fs * u
        text.typeface = Typeface.DEFAULT_BOLD
        text.color = heartC
        c.drawText("♥ ", x, y * u, text)
        x += wHeart
        text.color = if (over) red else if (fresh) Color.WHITE else amber
        c.drawText(num, x, y * u, text)
        x += wNum
        text.textSize = 9.5f * fs * u
        text.typeface = Typeface.DEFAULT
        text.color = gray
        c.drawText(tail, x, y * u, text)
        text.textAlign = old
        if (!fresh || lim == null) return
        val w = 100f
        val x0 = cx - w * u / 2
        val yy = (y + 6) * u
        fill.color = dim
        c.drawRoundRect(RectF(x0, yy, x0 + w * u, yy + 3.5f * u), 2 * u, 2 * u, fill)
        val lo = 60f
        val hi = lim + 20f
        val p = ((Repo.bpm - lo) / (hi - lo)).coerceIn(0f, 1f)
        fill.color = if (over) red else salmon
        c.drawRoundRect(RectF(x0, yy, x0 + w * u * p, yy + 3.5f * u), 2 * u, 2 * u, fill)
        val lp = ((lim - lo) / (hi - lo)).coerceIn(0f, 1f)
        fill.color = Color.WHITE
        c.drawRect(RectF(x0 + w * u * lp - 0.7f * u, yy - 2f * u, x0 + w * u * lp + 0.7f * u, yy + 5.5f * u), fill)
    }

    /** Σχέδια 9/11 (7γ): «Δεν έρχονται παλμοί» με όριο γιατρού, σε όλη την οθόνη, με «Εντάξει». */
    private fun drawNoHr(c: Canvas) {
        fill.shader = RadialGradient(cx, cy * 0.85f, width * 0.62f, Color.parseColor("#5A3A0A"), Color.parseColor("#1E1404"), Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fill)
        fill.shader = null
        // Τρίγωνο προσοχής.
        val tri = Path().apply {
            moveTo(cx, 24f * u)
            lineTo(cx + 11f * u, 43f * u)
            lineTo(cx - 11f * u, 43f * u)
            close()
        }
        ring.color = amber
        ring.strokeWidth = 2.4f * u
        ring.strokeJoin = Paint.Join.ROUND
        c.drawPath(tri, ring)
        fill.color = amber
        c.drawRect(cx - 1.1f * u, 30f * u, cx + 1.1f * u, 37f * u, fill)
        c.drawCircle(cx, 40f * u, 1.3f * u, fill)
        val lim = Repo.alarm.limit
        t(c, "Δεν έρχονται", 62f, Color.WHITE, 15f * fs, true, 160f)
        t(c, "παλμοί", 80f, Color.WHITE, 15f * fs, true, 160f)
        // Ίδια ελεγμένη φράση με το κινητό και την ειδοποίηση (V-A-04/05): «δεν σε προσέχει».
        t(c, "Το όριο $lim δεν σε", 99f, amberSoft, 11.5f * fs, true, 170f)
        t(c, "προσέχει τώρα", 115f, amberSoft, 11.5f * fs, true, 170f)
        t(c, "Σφίξε λίγο το λουράκι", 131f, soft, 10f * fs, false, 160f)
        sayAdd("Δεν έρχονται παλμοί. Το όριο $lim δεν σε προσέχει τώρα. Σφίξε λίγο το λουράκι")
        pill(c, "Εντάξει", 160f, 100f, 38f, amber, amberInk, 13f * fs) { noHrSeen = true; invalidate() }
    }

    /** Κουμπί της αρχικής: τίτλος (και μικρή γραμμή) μέσα σε στρογγυλεμένο ορθογώνιο, από το [top] σε u. */
    private fun homeButton(
        c: Canvas, title: String, sub: String?, top: Float, bg: Int, fg: Int,
        h: Float = 40f, w: Float = 144f, size: Float = 13f, run: () -> Unit,
    ) {
        val r = RectF(cx - w * u / 2, top * u, cx + w * u / 2, (top + h) * u)
        fill.color = bg
        c.drawRoundRect(r, h * u / 2, h * u / 2, fill)
        if (sub == null) {
            text.typeface = Typeface.DEFAULT_BOLD
            fitPlain(c, title, (top + h / 2) / 1f + 0.36f * size * fs, fg, size * fs, w - 16f)
        } else {
            text.typeface = Typeface.DEFAULT_BOLD
            fitPlain(c, title, top + h * 0.46f, fg, 12.5f * fs, w - 16f)
            text.typeface = Typeface.DEFAULT
            fitPlain(c, sub, top + h * 0.82f, fg, 9.5f * fs, w - 16f)
        }
        hits.add(Hit(RectF(r.left - 2 * u, r.top - 3 * u, r.right + 2 * u, r.bottom + 3 * u), if (sub == null) title else "$title, $sub", run))
    }

    /** Σαν το [fit] αλλά με όποια γραμματοσειρά έχει ήδη το [text]. */
    private fun fitPlain(c: Canvas, s: String, y: Float, color: Int, size: Float, maxW: Float) {
        text.color = color
        var sz = size
        text.textSize = sz * u
        while (text.measureText(s) > maxW * u && sz > 8f) {
            sz -= 0.5f
            text.textSize = sz * u
        }
        c.drawText(s, cx, y * u, text)
    }

    /** Δύο χρώματα σε μία κεντραρισμένη γραμμή («Σήμερα · » γκρι + «όριο 140» χρώμα). */
    private fun twoTone(c: Canvas, a: String, b: String, y: Float, colorB: Int, size0: Float) {
        // Μικραίνει ώσπου να χωρά στον κύκλο (π.χ. «Άλλη προπόνηση · όριο 140» με γράμματα 1,3×).
        var size = size0
        var wa: Float
        var wb: Float
        while (true) {
            text.textSize = size * u
            text.typeface = Typeface.DEFAULT
            wa = text.measureText(a)
            text.typeface = Typeface.DEFAULT_BOLD
            wb = text.measureText(b)
            if (wa + wb <= 136f * u || size <= 8f) break
            size -= 0.5f
        }
        val old = text.textAlign
        text.textAlign = Paint.Align.LEFT
        val x = cx - (wa + wb) / 2
        text.typeface = Typeface.DEFAULT
        text.color = soft
        c.drawText(a, x, y * u, text)
        text.typeface = Typeface.DEFAULT_BOLD
        text.color = colorB
        c.drawText(b, x + wa, y * u, text)
        text.textAlign = old
    }

    /**
     * Λεπτό αποκατάστασης μετά το «Τέλος» (9/11): κάθισε, χέρι ακίνητο, χωρίς ομιλία· στο τέλος του μετράμε πόσο έπεσαν
     * οι παλμοί. «Παράλειψη»: τέλος αμέσως, χωρίς μέτρηση.
     */
    private fun drawRecover(c: Canvas, now: Long) {
        small(c, "ΑΠΟΚΑΤΑΣΤΑΣΗ", 42f, green, ess(10f), 120f)
        t(c, "Κάθισε", 64f, Color.WHITE, 15f * fs, true)
        small(c, "χέρι ακίνητο, μη μιλάς", 64f + 16f * fs, Color.WHITE, ess(10.5f), 150f)
        val left = ((Repo.recoveryUntil - now + 999) / 1000).coerceAtLeast(0)
        t(c, "$left″", 114f, Color.WHITE, 26f, true)
        sayAdd("Αποκατάσταση. Κάθισε, χέρι ακίνητο, μη μιλάς. Μένουν $left δευτερόλεπτα")
        heart(c, 134f, now, 11f)
        pill(c, "Παράλειψη", 168f, 92f, 30f, card, Color.WHITE, 11f * fs, desc = "Παράλειψη της αποκατάστασης") { actions.finishWorkout() }
    }

    // ------------------------------------------------------------------ τέλος
    private fun drawEnd(c: Canvas) {
        t(c, "✓", 76f, green, 32f, true)
        t(c, "Αποθηκεύτηκε", 100f, Color.WHITE, 13f * fs, true)
        val note = Repo.notice
        if (note != null) {
            // Π.χ. «Σώθηκε ως τις 18:42: η εφαρμογή έκλεισε πριν το «Τέλος».» (V-A-03): ολόκληρο, σε ως 3 γραμμές.
            text.color = orange
            text.textSize = ess(10f) * u
            text.typeface = Typeface.DEFAULT
            val w = (140f * u).toInt()
            val tp = android.text.TextPaint(text).apply { textAlign = Paint.Align.LEFT }
            val layout = android.text.StaticLayout.Builder.obtain(note, 0, note.length, tp, w)
                .setAlignment(android.text.Layout.Alignment.ALIGN_CENTER)
                .setMaxLines(3)
                .setEllipsize(TextUtils.TruncateAt.END)
                .build()
            c.save()
            c.translate(cx - w / 2f, 106f * u)
            layout.draw(c)
            c.restore()
            sayAdd("Αποθηκεύτηκε. $note")
        } else {
            small(c, "Περνάει στο κινητό", 118f, gray, ess(10f), 150f)
            small(c, "όταν είναι κοντά.", 118f + 12f * fs, gray, ess(10f), 150f)
            sayAdd("Αποθηκεύτηκε. Περνάει στο κινητό όταν είναι κοντά")
        }
        pill(c, "ΟΚ", 166f, 72f, 32f, card, Color.WHITE, 12f * fs, desc = "Εντάξει") { actions.doneOk() }
    }

    // ------------------------------------------------------------------ αφή και περιστροφή
    private var downX = 0f
    private var downY = 0f

    // ------------------------------------------------------------------ TalkBack (έλεγχος γ2, W3-09)
    /**
     * Κάθε περιοχή της οθόνης ως «εικονικό» στοιχείο για το TalkBack, χωρίς βιβλιοθήκη: πρώτη η φράση με ό,τι δείχνει η
     * οθόνη, μετά τα κουμπιά με την περιγραφή τους· διπλό πάτημα = πάτημα του κουμπιού.
     */
    private val provider = object : AccessibilityNodeProvider() {
        override fun createAccessibilityNodeInfo(virtualViewId: Int): AccessibilityNodeInfo? {
            if (virtualViewId == View.NO_ID) {
                val info = AccessibilityNodeInfo.obtain(this@WatchView)
                onInitializeAccessibilityNodeInfo(info)
                for (i in a11y.indices) info.addChild(this@WatchView, i)
                return info
            }
            val h = a11y.getOrNull(virtualViewId) ?: return null
            val info = AccessibilityNodeInfo.obtain(this@WatchView, virtualViewId)
            info.packageName = context.packageName
            info.className = if (h.run != null) "android.widget.Button" else "android.widget.TextView"
            info.setParent(this@WatchView)
            info.contentDescription = h.label
            val r = android.graphics.Rect()
            h.r.roundOut(r)
            r.intersect(0, 0, width, height)
            @Suppress("DEPRECATION")
            info.setBoundsInParent(r)
            val loc = IntArray(2)
            getLocationOnScreen(loc)
            r.offset(loc[0], loc[1])
            info.setBoundsInScreen(r)
            info.isVisibleToUser = true
            info.isEnabled = true
            info.isFocusable = true
            if (h.run != null) {
                info.isClickable = true
                info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
            }
            return info
        }

        override fun performAction(virtualViewId: Int, action: Int, arguments: android.os.Bundle?): Boolean {
            if (virtualViewId == View.NO_ID) return performAccessibilityAction(action, arguments)
            return when (action) {
                AccessibilityNodeInfo.ACTION_CLICK -> a11yClick(virtualViewId)
                AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS, AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS -> true
                else -> false
            }
        }
    }

    override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = provider

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.x
                downY = e.y
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (abs(e.x - downX) > 20 * u || abs(e.y - downY) > 20 * u) return true
                // Το τελευταίο που ζωγραφίστηκε είναι από πάνω.
                for (h in hits.asReversed()) {
                    val run = h.run ?: continue
                    if (h.r.contains(e.x, e.y)) {
                        performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        run()
                        invalidate()
                        return true
                    }
                }
                return true
            }
        }
        return super.onTouchEvent(e)
    }

    private var rotary = 0f

    override fun onGenericMotionEvent(e: MotionEvent): Boolean {
        if (e.action == MotionEvent.ACTION_SCROLL && e.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)) {
            // Σετ: οι επαναλήψεις του επόμενου σετ· διάλειμμα: του σετ που μόλις έγινε (RT-13).
            val rest = Repo.screen == Repo.Screen.REST
            if (Repo.screen != Repo.Screen.SET && !rest) return true
            rotary += -e.getAxisValue(MotionEvent.AXIS_SCROLL)
            // Ένα «κλικ» της περιστροφής = μία επανάληψη.
            val step = 1f
            while (abs(rotary) >= step) {
                val d = if (rotary > 0) 1 else -1
                rotary -= d * step
                if (rest) actions.lastReps(d) else actions.reps(d)
            }
            invalidate()
            return true
        }
        return super.onGenericMotionEvent(e)
    }
}

/**
 * Η επόμενη προπόνηση βαρών μετά την [shownId], κυκλικά στη σειρά του προγράμματος (null αν υπάρχει μόνο μία).
 * Το τρίτο κουμπί της αρχικής: πατώντας το ξανά και ξανά φτάνεις σε όλες.
 */
internal fun nextStrength(ids: List<String>, shownId: String): String? {
    if (ids.size < 2) return null
    val i = ids.indexOf(shownId)
    return ids[(i + 1).mod(ids.size)].takeIf { it != shownId }
}

/** «1 άσκηση» / «4 ασκήσεις». */
internal fun countText(n: Int, one: String, many: String): String = if (n == 1) "1 $one" else "$n $many"
