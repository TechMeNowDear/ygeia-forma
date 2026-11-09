package gr.ygeiaforma.wear

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import android.view.HapticFeedbackConstants
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
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
        fun finish()
        fun pauseWalk(on: Boolean)
        fun muteAlarm()
        fun doneOk()
    }

    private val orange = Color.parseColor("#EA580C")
    private val green = Color.parseColor("#16A34A")
    private val red = Color.parseColor("#EF4444")
    private val alarmBg = Color.parseColor("#991B1B")
    private val gray = Color.parseColor("#9CA3AF")
    private val dim = Color.parseColor("#374151")
    private val card = Color.parseColor("#1F2937")

    private val text = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }

    private class Hit(val r: RectF, val run: () -> Unit)
    private val hits = mutableListOf<Hit>()

    /** Η προπόνηση που δείχνει η αρχική (μπορεί να αλλάξει με πάτημα στο όνομα). */
    var chosen: String? = null

    private var u = 1f
    private var cx = 0f
    private var cy = 0f

    init {
        isFocusable = true
        isFocusableInTouchMode = true
    }

    override fun onDraw(c: Canvas) {
        hits.clear()
        u = width / 200f
        cx = width / 2f
        cy = height / 2f
        val now = System.currentTimeMillis()
        val alarm = Repo.alarm.on && Repo.running != null && now >= Repo.alarmMutedUntil
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
        // Πάτημα στο μήνυμα: ολόκληρο (π.χ. η αιτία όταν δεν ξεκινά η μέτρηση· 9/11). Πρώτο στη λίστα, ώστε τα
        // κουμπιά της οθόνης να κερδίζουν όπου ακουμπούν.
        if (note != null) hits.add(Hit(RectF(cx - 60 * u, 176 * u, cx + 60 * u, 198 * u)) { noticeOpen = true; invalidate() })
        when (Repo.screen) {
            Repo.Screen.HOME -> drawHome(c)
            Repo.Screen.SET -> drawSet(c, now)
            Repo.Screen.RIR -> drawRir(c)
            Repo.Screen.REST -> drawRest(c, now)
            Repo.Screen.WALK -> drawWalk(c, now)
            Repo.Screen.RECOVER -> drawRecover(c, now)
            Repo.Screen.END -> drawEnd(c)
        }
        if (note != null) small(c, note, 186f, gray, 8f, 120f)
    }

    private var noticeOpen = false

    /** Ολόκληρο το μήνυμα, σε πολλές γραμμές· πάτημα οπουδήποτε κλείνει. */
    private fun drawNotice(c: Canvas, note: String) {
        text.color = Color.WHITE
        text.textSize = 10f * u
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
        hits.add(Hit(RectF(0f, 0f, width.toFloat(), height.toFloat())) { noticeOpen = false; invalidate() })
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

    private fun pill(c: Canvas, label: String, y: Float, w: Float, h: Float, bg: Int, fg: Int, size: Float = 12f, run: () -> Unit) {
        val r = RectF(cx - w * u / 2, (y - h / 2) * u, cx + w * u / 2, (y + h / 2) * u)
        fill.color = bg
        c.drawRoundRect(r, h * u / 2, h * u / 2, fill)
        text.color = fg
        text.textSize = size * u
        text.typeface = Typeface.DEFAULT_BOLD
        c.drawText(label, cx, r.centerY() - (text.descent() + text.ascent()) / 2, text)
        // Λίγο μεγαλύτερη περιοχή πατήματος από το σχήμα (δάχτυλο σε μικρή οθόνη).
        hits.add(Hit(RectF(r.left - 6 * u, r.top - 6 * u, r.right + 6 * u, r.bottom + 6 * u), run))
    }

    private fun pillAt(c: Canvas, label: String, x: Float, y: Float, w: Float, h: Float, bg: Int, fg: Int, size: Float, run: () -> Unit) {
        val r = RectF((x - w / 2) * u, (y - h / 2) * u, (x + w / 2) * u, (y + h / 2) * u)
        fill.color = bg
        c.drawRoundRect(r, h * u / 2, h * u / 2, fill)
        text.color = fg
        text.textSize = size * u
        text.typeface = Typeface.DEFAULT_BOLD
        c.drawText(label, r.centerX(), r.centerY() - (text.descent() + text.ascent()) / 2, text)
        hits.add(Hit(RectF(r.left - 4 * u, r.top - 6 * u, r.right + 4 * u, r.bottom + 6 * u), run))
    }

    private fun heart(c: Canvas, y: Float, now: Long, size: Float = 12f) {
        val fresh = Repo.hrLive(now)
        val over = fresh && Repo.alarm.limit != null && Repo.bpm >= Repo.alarm.limit!!
        if (!fresh && Repo.running != null) {
            // Δεν φτάνουν τιμές: να φαίνεται, όχι μια παύλα που μοιάζει με «όλα καλά».
            t(c, "♥ δεν μετριούνται", y, if (Repo.alarm.limit != null) orange else gray, size * 0.75f, true)
            // Με όριο γιατρού (έλεγχος 9/11, V-A-04): ξεκάθαρα ότι το όριο δεν προσέχει τώρα.
            if (Repo.alarm.limit != null) t(c, "το όριο δεν σε προσέχει", y + size * 0.85f, orange, size * 0.62f, false, 120f)
            return
        }
        val s = if (fresh) "♥ ${Repo.bpm}" else "♥ —"
        t(c, s, y, if (over) red else if (fresh) Color.WHITE else gray, size, true)
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

    // ------------------------------------------------------------------ Α. έναρξη
    private fun drawHome(c: Canvas) {
        val plan = Repo.plan
        val phone = Repo.phone
        if (phone != null && !phone.ended) {
            small(c, "ΣΤΟ ΚΙΝΗΤΟ", 52f, gray, 9f, 120f)
            t(c, phone.name, 74f, Color.WHITE, 15f, true)
            small(c, "${phone.setsDone} σετ ως τώρα", 92f, gray, 9f, 130f)
            pill(c, "Παλμοί εδώ", 122f, 96f, 30f, orange, Color.WHITE) { actions.joinPhone() }
            small(c, "και ✓ στον καρπό", 150f, gray, 9f, 120f)
            return
        }
        if (plan != null) {
            // Το όριο που ισχύει, πριν ξεκινήσεις (έλεγχος 8/11).
            val lim = plan.hrLimit
            small(c, if (lim != null) "όριο παλμών $lim" else "χωρίς όριο παλμών", 34f, if (lim != null) orange else gray, 8f, 96f)
        }
        val strength = plan?.workouts?.filter { !it.isCardio && it.items.isNotEmpty() }.orEmpty()
        val today = plan?.todayWorkout
        val shown = plan?.workout(chosen) ?: today?.takeIf { !it.isCardio } ?: strength.firstOrNull()
        when {
            plan == null -> {
                small(c, "ΥΓΕΙΑ & ΦΟΡΜΑ", 56f, gray, 9f, 120f)
                t(c, "Άνοιξε την εφαρμογή", 80f, Color.WHITE, 12f, true)
                t(c, "στο κινητό", 96f, Color.WHITE, 12f, true)
                pill(c, "Περπάτημα", 132f, 96f, 30f, card, Color.WHITE) { actions.startWalk() }
            }
            today?.isCardio == true && chosen == null -> {
                small(c, "ΣΗΜΕΡΑ", 52f, gray, 9f, 120f)
                t(c, today.cardio?.name ?: "Περπάτημα", 74f, Color.WHITE, 15f, true)
                small(c, "${today.cardio?.minutes ?: 30}′ ${today.cardio?.note ?: ""}".trim(), 92f, gray, 9f, 140f)
                pill(c, "Ξεκίνα", 122f, 90f, 30f, orange, Color.WHITE) { actions.startWalk() }
                if (strength.isNotEmpty()) {
                    val w = strength.first()
                    hits.add(Hit(RectF(cx - 60 * u, 142 * u, cx + 60 * u, 162 * u)) { chosen = w.id; invalidate() })
                    small(c, "Προπόνηση με βάρη ›", 154f, gray, 9f, 120f)
                }
            }
            shown != null -> {
                small(c, if (shown.id == today?.id) "ΣΗΜΕΡΑ" else "ΑΛΛΗ ΠΡΟΠΟΝΗΣΗ", 50f, gray, 9f, 120f)
                t(c, shown.name, 72f, Color.WHITE, 15f, true)
                small(c, "${shown.items.size} ασκήσεις · ~${shown.minutes}′", 90f, gray, 9f, 140f)
                if (strength.size > 1) {
                    // Πάτημα στο όνομα: η επόμενη προπόνηση του προγράμματος.
                    hits.add(Hit(RectF(cx - 70 * u, 56 * u, cx + 70 * u, 96 * u)) {
                        val i = strength.indexOfFirst { it.id == shown.id }
                        chosen = strength[(i + 1) % strength.size].id
                        invalidate()
                    })
                }
                pill(c, "Ξεκίνα", 120f, 90f, 30f, orange, Color.WHITE) { actions.startWorkout(shown.id) }
                hits.add(Hit(RectF(cx - 60 * u, 140 * u, cx + 60 * u, 164 * u)) { actions.startWalk() })
                small(c, "↓ Περπάτημα", 154f, gray, 9f, 120f)
            }
            else -> {
                small(c, "ΣΗΜΕΡΑ", 56f, gray, 9f, 120f)
                t(c, "Ξεκούραση", 80f, Color.WHITE, 15f, true)
                pill(c, "Περπάτημα", 122f, 96f, 30f, card, Color.WHITE) { actions.startWalk() }
            }
        }
    }

    // ------------------------------------------------------------------ Β. σετ
    private fun drawSet(c: Canvas, now: Long) {
        val s = Repo.session ?: return drawHome(c)
        // «Ελεύθερη άσκηση» του κινητού χωρίς ασκήσεις ακόμα (9/11): οι παλμοί μετράνε, η άσκηση διαλέγεται στο κινητό.
        if (s.phone && s.items.isEmpty()) return drawPickOnPhone(c, now)
        val it = s.current ?: return drawEnd(c)
        heart(c, 40f, now)
        val si = it.nextSet.let { n -> if (n < 0) it.sets.size - 1 else n }
        val set = it.sets.getOrNull(si)
        // Όνομα άσκησης: πάτημα = επόμενη άσκηση.
        small(c, it.name, 62f, Color.WHITE, 10f, 140f)
        small(c, "ΣΕΤ ${si + 1}/${it.sets.size}" + if (s.items.size > 1) "  ›" else "", 74f, gray, 8.5f, 120f)
        hits.add(Hit(RectF(cx - 75 * u, 50 * u, cx + 75 * u, 78 * u)) { actions.nextExercise() })
        if (set != null) {
            if (set.label.isNotEmpty()) fit(c, set.label, 104f, Color.WHITE, 26f, 150f)
            // Επαναλήψεις με − / + (και με την περιστροφή).
            text.typeface = Typeface.DEFAULT_BOLD
            t(c, "× ${set.reps}", if (set.label.isEmpty()) 104f else 124f, Color.WHITE, if (set.label.isEmpty()) 26f else 15f, true)
            val ry = if (set.label.isEmpty()) 96f else 119f
            pillAt(c, "−", 54f, ry, 24f, 20f, card, Color.WHITE, 14f) { actions.reps(-1) }
            pillAt(c, "+", 146f, ry, 24f, 20f, card, Color.WHITE, 14f) { actions.reps(1) }
        }
        pill(c, "✓", 152f, 80f, 30f, green, Color.WHITE, 18f) { actions.tick() }
        hits.add(Hit(RectF(cx - 30 * u, 172 * u, cx + 30 * u, 196 * u)) { actions.finish() })
        small(c, "Τέλος", 182f, gray, 8.5f, 60f)
    }

    private fun drawPickOnPhone(c: Canvas, now: Long) {
        heart(c, 52f, now)
        t(c, "Διάλεξε άσκηση", 92f, Color.WHITE, 14f, true)
        t(c, "στο κινητό", 112f, Color.WHITE, 14f, true)
        small(c, if (Repo.bpmFresh(now)) "οι παλμοί ήδη μετράνε" else "περιμένω παλμούς", 134f, gray, 8.5f, 140f)
        hits.add(Hit(RectF(cx - 30 * u, 172 * u, cx + 30 * u, 196 * u)) { actions.finish() })
        small(c, "Τέλος", 182f, gray, 8.5f, 60f)
    }

    // ------------------------------------------------------------------ ρεζέρβα
    private fun drawRir(c: Canvas) {
        t(c, "Πόσες ακόμα", 62f, Color.WHITE, 12f, true)
        t(c, "θα έβγαζες;", 78f, Color.WHITE, 12f, true)
        val labels = listOf("0", "1", "2", "3", "4+")
        // Δύο σειρές: 0 1 2 / 3 4+ (μεγάλα κουμπιά για τον καρπό).
        val row1 = listOf(62f, 100f, 138f)
        for (i in 0..2) pillAt(c, labels[i], row1[i], 104f, 32f, 28f, card, Color.WHITE, 14f) { actions.answer(i) }
        pillAt(c, labels[3], 81f, 138f, 32f, 28f, card, Color.WHITE, 14f) { actions.answer(3) }
        pillAt(c, labels[4], 119f, 138f, 32f, 28f, card, Color.WHITE, 14f) { actions.answer(4) }
        small(c, "με καλή τεχνική", 168f, gray, 8.5f, 120f)
    }

    // ------------------------------------------------------------------ Γ. διάλειμμα
    private fun drawRest(c: Canvas, now: Long) {
        val s = Repo.session ?: return drawHome(c)
        val left = ((s.restEnd - now) / 1000L).coerceAtLeast(0)
        val total = (s.items.getOrNull(s.idx)?.rest ?: 90).coerceAtLeast(1)
        val p = (left.toFloat() / total).coerceIn(0f, 1f)
        val pad = 6 * u
        ring.strokeWidth = 5 * u
        ring.color = dim
        val box = RectF(pad, pad, width - pad, height - pad)
        c.drawArc(box, -90f, 360f, false, ring)
        ring.color = orange
        c.drawArc(box, -90f, 360f * p, false, ring)
        small(c, "ΔΙΑΛΕΙΜΜΑ", 58f, gray, 9f, 120f)
        t(c, clock(left), 96f, Color.WHITE, 32f, true)
        heart(c, 116f, now, 11f)
        val it = s.current
        val si = it?.nextSet ?: -1
        if (it != null && si >= 0) {
            val set = it.sets[si]
            small(c, "επόμενο: σετ ${si + 1} · ${set.label.ifEmpty { "" }}${if (set.label.isEmpty()) "" else " "}× ${set.reps}", 136f, gray, 8.5f, 150f)
            if (si == 0) small(c, it.name, 147f, gray, 8.5f, 140f)
        }
        pillAt(c, "+30″", 76f, 164f, 40f, 24f, card, Color.WHITE, 10f) { actions.restPlus() }
        pillAt(c, "Πάμε", 124f, 164f, 40f, 24f, Color.WHITE, Color.BLACK, 10f) { actions.restStop() }
    }

    // ------------------------------------------------------------------ Δ. όριο παλμών
    private fun drawAlarm(c: Canvas) {
        small(c, "ΠΑΝΩ ΑΠΟ ΤΟ ΟΡΙΟ", 60f, Color.WHITE, 9f, 130f)
        t(c, "♥ ${Repo.bpm}", 98f, Color.WHITE, 30f, true)
        if (Repo.running == "walk") {
            t(c, "Κόψε ρυθμό", 122f, Color.WHITE, 13f, true)
        } else {
            t(c, "Ξεκουράσου", 120f, Color.WHITE, 13f, true)
        }
        small(c, if (Repo.running == "walk") "όριο γιατρού ${Repo.alarm.limit ?: ""}" else "μέχρι κάτω από ${Repo.alarm.limit ?: ""}", 140f, Color.WHITE, 9f, 130f)
        small(c, "πάτα για να κλείσει", 166f, Color.parseColor("#FCA5A5"), 8f, 120f)
        hits.add(Hit(RectF(0f, 0f, width.toFloat(), height.toFloat())) { actions.muteAlarm() })
    }

    // ------------------------------------------------------------------ Ε. περπάτημα
    private fun drawWalk(c: Canvas, now: Long) {
        small(c, if (Repo.paused) "ΠΑΥΣΗ" else "ΠΕΡΠΑΤΗΜΑ", 50f, if (Repo.paused) orange else gray, 9f, 120f)
        val sec = if (Repo.activeSec > 0) Repo.activeSec else (now - Repo.startedAt) / 1000
        t(c, clock(sec), 88f, if (Repo.paused) gray else Color.WHITE, 30f, true)
        val dist = if (Repo.meters > 0) "${km(Repo.meters)} km · ${pace(Repo.meters, sec)}" else if (Repo.steps > 0) "${Repo.steps} βήματα" else "—"
        small(c, dist, 108f, Color.WHITE, 11f, 150f)
        heart(c, 128f, now, 11f)
        if (!Repo.gps) small(c, "χωρίς GPS", 146f, gray, 8f, 100f)
        // Παύση/Συνέχεια αριστερά, Τέλος δεξιά (δύο πατήματα, όπως πριν).
        pillAt(c, if (Repo.paused) "Συνέχεια" else "Παύση", 72f, 166f, 54f, 26f, if (Repo.paused) orange else card, Color.WHITE, 10f) {
            actions.pauseWalk(!Repo.paused)
        }
        pillAt(c, "Τέλος", 128f, 166f, 50f, 26f, card, Color.WHITE, 10f) { actions.finish() }
    }

    /**
     * Λεπτό αποκατάστασης μετά το «Τέλος» (9/11): κάθισε, χέρι ακίνητο, χωρίς ομιλία· στο τέλος του μετράμε πόσο έπεσαν
     * οι παλμοί. «Παράλειψη»: τέλος αμέσως, χωρίς μέτρηση.
     */
    private fun drawRecover(c: Canvas, now: Long) {
        small(c, "ΑΠΟΚΑΤΑΣΤΑΣΗ", 46f, green, 9f, 120f)
        t(c, "Κάθισε", 68f, Color.WHITE, 15f, true)
        small(c, "χέρι ακίνητο, μη μιλάς", 84f, Color.WHITE, 9.5f, 150f)
        val left = ((Repo.recoveryUntil - now + 999) / 1000).coerceAtLeast(0)
        t(c, "$left″", 116f, Color.WHITE, 26f, true)
        heart(c, 138f, now, 11f)
        pill(c, "Παράλειψη", 166f, 80f, 24f, card, Color.WHITE, 10f) { actions.finish() }
    }

    // ------------------------------------------------------------------ τέλος
    private fun drawEnd(c: Canvas) {
        t(c, "✓", 82f, green, 32f, true)
        t(c, "Αποθηκεύτηκε", 108f, Color.WHITE, 13f, true)
        small(c, "Περνάει στο κινητό", 126f, gray, 9f, 140f)
        small(c, "όταν είναι κοντά.", 138f, gray, 9f, 140f)
        pill(c, "ΟΚ", 164f, 60f, 24f, card, Color.WHITE, 11f) { actions.doneOk() }
    }

    // ------------------------------------------------------------------ αφή και περιστροφή
    private var downX = 0f
    private var downY = 0f

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
                    if (h.r.contains(e.x, e.y)) {
                        performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        h.run()
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
            if (Repo.screen != Repo.Screen.SET) return true
            rotary += -e.getAxisValue(MotionEvent.AXIS_SCROLL)
            // Ένα «κλικ» της περιστροφής = μία επανάληψη.
            val step = 1f
            while (abs(rotary) >= step) {
                val d = if (rotary > 0) 1 else -1
                rotary -= d * step
                actions.reps(d)
            }
            invalidate()
            return true
        }
        return super.onGenericMotionEvent(e)
    }
}
