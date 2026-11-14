package gr.ygeiaforma.wear

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.view.MotionEvent
import android.view.View
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.io.FileOutputStream

/**
 * Έλεγχος 13/11 (round 2), ρολόι: πού σπάει ένα μήνυμα σε δύο γραμμές (R2-U3-03). Οι τιμές που περιμένουμε βγαίνουν από
 * τον γραμμένο κανόνα με ένα απλό μοντέλο πλάτους (κάθε χαρακτήρας 4,5u), όχι από τον κώδικα (fix/round2/h2.md). Με τον
 * παλιό κανόνα («η πιο μικρή 2η γραμμή») οι δύο πρώτοι έλεγχοι αποτυγχάνουν.
 */
class R2H2Test {
    /** Τα πλάτη των δύο γραμμών του σετ στα 10u: πάνω min(124, χορδή στα 171u), κάτω η χορδή στα 182u (95,6u). */
    private val w1 = minOf(124f, chordAt(171f, 10f))
    private val w2 = chordAt(182f, 10f)
    private val perChar: (String) -> Float = { it.length * 4.5f }

    private fun lines(note: String): Triple<String, String, Boolean> {
        val words = note.split(' ')
        val (k, fits) = twoLineSplit(words, perChar, w1, w2)
        return Triple(words.take(k).joinToString(" "), words.drop(k).joinToString(" "), fits)
    }

    @Test
    fun twoLineSplitBreaksAfterTheColonWhenItFits() {
        // Πριν: «Πάτα ξανά: επόμενη» / «άσκηση» (81u / 27u) και «Πάτα ξανά: τέλος και» / «στο κινητό».
        assertEquals(Triple("Πάτα ξανά:", "επόμενη άσκηση", true), lines("Πάτα ξανά: επόμενη άσκηση"))
        assertEquals(Triple("Πάτα ξανά:", "τέλος και στο κινητό", true), lines("Πάτα ξανά: τέλος και στο κινητό"))
        assertEquals(Triple("Κανένα σετ ούτε παλμοί:", "δεν αποθηκεύεται", true), lines("Κανένα σετ ούτε παλμοί: δεν αποθηκεύεται"))
        // Το σπάσιμο μετά το «:» δεν χωρά (2η γραμμή 144u > 95,6u): το μόνο που χωρά (99u / 94,5u), όπως πριν.
        assertEquals(
            Triple("Κανένα σετ: στο κινητό", "μένουν μόνο οι παλμοί", true),
            lines("Κανένα σετ: στο κινητό μένουν μόνο οι παλμοί"),
        )
        // Δύο «:» που χωράνε: το πιο ισορροπημένο από αυτά (22,5u / 13,5u, όχι 9u / 27u).
        assertEquals(Triple("α: β:", "γ δ", true), lines("α: β: γ δ"))
    }

    @Test
    fun twoLineSplitOtherwiseBalancesTheLinesOrReportsThatNothingFits() {
        // Χωρίς «:»: οι δύο γραμμές γεμίζουν παρόμοιο ποσοστό του πλάτους τους (81u / 76,5u)· πριν 99u / 58,5u.
        assertEquals(Triple("Η άσκηση σταμάτησε", "από άλλη εφαρμογή", true), lines("Η άσκηση σταμάτησε από άλλη εφαρμογή"))
        // Τίποτα δεν χωρά: αυτό που ξεπερνά λιγότερο (184,5u / 153u), με «δεν χωρά» (τα γράμματα μικραίνουν και ξαναδοκιμάζεται).
        assertEquals(
            Triple("Χωρίς άδεια παλμών: η προπόνηση γράφεται,", "οι παλμοί όχι, και τίποτα άλλο εδώ", false),
            lines("Χωρίς άδεια παλμών: η προπόνηση γράφεται, οι παλμοί όχι, και τίποτα άλλο εδώ"),
        )
        // Μία λέξη: όλη πάνω, «δεν χωρά» (όπως πριν).
        assertEquals(1 to false, twoLineSplit(listOf("Μία"), perChar, w1, w2))
    }
}

/**
 * Έλεγχος 13/11 (round 2), ρολόι: οι οθόνες ζωγραφισμένες από τον πραγματικό κώδικα (WatchView), όπως στο R1F7ViewTest.
 * Τα στιγμιότυπα γράφονται κι αυτά στο build/watch-shots/ (όνομα «R2_…»).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class R2H2ViewTest {
    private val size = 454
    private val u = size / 200f

    private val planJson = """
        {"v":1,"today":"A","at":1,
         "workouts":[
          {"id":"A","name":"Προπόνηση Α","minutes":50,"items":[
            {"ex":"db_press","name":"Πιεστικό με αλτήρες","rest":120,"lo":8,"hi":12,"rir":2,
             "sets":[{"load":10.3,"label":"10,3 kg","reps":8},{"load":10.3,"label":"10,3 kg","reps":8}]},
            {"ex":"db_row","name":"Κωπηλασία με αλτήρα","rest":90,"lo":8,"hi":12,"rir":2,
             "sets":[{"load":14.3,"label":"14,3 kg","reps":11},{"load":14.3,"label":"14,3 kg","reps":11}]}]},
          {"id":"B","name":"Προπόνηση Β","minutes":56,"items":[
            {"ex":"incline_press","name":"Πιεστικό σε κλίση","rest":120,"lo":8,"hi":12,"rir":2,"sets":[{"load":7.8,"label":"7,8 kg","reps":8}]}]},
          {"id":"walk","name":"Περπάτημα","minutes":30,"cardio":{"activity":"walk","name":"Περπάτημα","minutes":30,"note":"χαλαρά"}}]}
    """.trimIndent()

    // Round 7 (R7-A8-3): με αρχή «τώρα»· μια προπόνηση του κινητού με αρχή το 1970 μετρά πια ως ξεχασμένη.
    private val phoneJson = """{"active":true,"id":"s5","w":"A","name":"Προπόνηση Α","start":${System.currentTimeMillis()},"idx":0,
        "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"sets":[{"label":"10,3 kg","reps":8},{"label":"10,3 kg","reps":8}]}]}"""

    private val noop = object : WatchView.Actions {
        override fun startWorkout(id: String) {}
        override fun startWalk() {}
        override fun joinPhone() {}
        override fun tick() {}
        override fun answer(rir: Int) {}
        override fun reps(delta: Int) {}
        override fun nextExercise() {}
        override fun restPlus() {}
        override fun restStop() {}
        override fun finishWorkout() {}
        override fun pauseWalk(on: Boolean) {}
        override fun muteAlarm() {}
        override fun doneOk() {}
        override fun lastReps(delta: Int) {}
    }

    /** Το [Repo] είναι κοινό για όλες τις δοκιμές της ίδιας εκτέλεσης: καθαρό και πριν, όχι μόνο μετά. */
    @Before
    fun clean() {
        reset()
    }

    @After
    fun reset() {
        RuntimeEnvironment.setFontScale(1f)
        Repo.plan = null
        Repo.applyPhone(null)
        Repo.lastPhone = null
        Repo.local = null
        Repo.notice = null
        Repo.openNotice = false
        Repo.knownLimit = null
        Repo.updateNeeded = false
        Repo.screen = Repo.Screen.HOME
        Repo.resetExercise()
        Repo.alarm.limit = null
        Repo.alarm.reset()
        WatchView.noHrSeenNow = false
    }

    /** Νέα οθόνη, που κρατά και το μέγεθος κάθε γραμμής που ζωγραφίζει ([WatchView.drawnSizes]). */
    private fun newView(): WatchView {
        val v = WatchView(RuntimeEnvironment.getApplication(), noop)
        v.drawnSizes = mutableMapOf()
        val spec = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
        v.measure(spec, spec)
        v.layout(0, 0, size, size)
        return v
    }

    /** Ζωγραφίζει την οθόνη· με [name] γράφει και στιγμιότυπο. */
    private fun draw(v: WatchView, name: String? = null): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        v.draw(Canvas(bmp))
        if (name != null) {
            val dir = File("build/watch-shots").apply { mkdirs() }
            FileOutputStream(File(dir, "$name.png")).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        return bmp
    }

    private fun labels(v: WatchView): List<String> = v.a11yItems.map { it.first }

    private fun tap(v: WatchView, x: Float, y: Float) {
        val t0 = android.os.SystemClock.uptimeMillis()
        v.dispatchTouchEvent(MotionEvent.obtain(t0, t0, MotionEvent.ACTION_DOWN, x, y, 0))
        v.dispatchTouchEvent(MotionEvent.obtain(t0, t0 + 50, MotionEvent.ACTION_UP, x, y, 0))
    }

    private fun isBlack(p: Int): Boolean = (p and 0x00FFFFFF) == 0

    /** Γράμματα του «πάτα για να κλείσει» (#9CA3AF πάνω σε μαύρο, και οι εξομαλυμένες άκρες τους από ≈ 35%). */
    private fun hintPx(p: Int): Boolean = Color.blue(p) - Color.red(p) >= 6 && Color.blue(p) >= 60

    /** Λευκά γράμματα του μηνύματος (και οι άκρες τους από 50%): ίδια τιμή στα τρία κανάλια. */
    private fun whitePx(p: Int): Boolean = Color.red(p) >= 128 && Color.red(p) == Color.green(p) && Color.green(p) == Color.blue(p)

    /** Οι γραμμές pixel (από πάνω προς τα κάτω) που έχουν έστω ένα pixel που ταιριάζει στο [match]. */
    private fun rows(bmp: Bitmap, match: (Int) -> Boolean): List<Int> =
        (0 until size).filter { y -> (0 until size).any { x -> match(bmp.getPixel(x, y)) } }

    /** Η μεγαλύτερη απόσταση από το κέντρο (σε u) που έχει οτιδήποτε ζωγραφισμένο (όχι μαύρο). */
    private fun maxRadius(bmp: Bitmap): Float {
        var best = 0.0
        val c = size / 2.0
        for (y in 0 until size) for (x in 0 until size) {
            if (isBlack(bmp.getPixel(x, y))) continue
            val d = Math.hypot(x + 0.5 - c, y + 0.5 - c)
            if (d > best) best = d
        }
        return (best / u).toFloat()
    }

    private fun startSet(now: Long) {
        Repo.applyPlan(Plan.parse(planJson))
        Repo.local = LiveSession.fromPlan(Repo.plan!!.workout("A")!!, now - 60_000)
        Repo.running = "strength"
        Repo.startedAt = now - 60_000
        Repo.bpm = 118
        Repo.bpmAt = now
        Repo.screen = Repo.Screen.SET
    }

    private fun startWalk(now: Long) {
        Repo.running = "walk"
        Repo.startedAt = now - 1471_000
        Repo.activeSec = 1471
        Repo.meters = 2180.0
        Repo.steps = 3104
        Repo.gps = true
        Repo.bpm = 118
        Repo.bpmAt = now
        Repo.screen = Repo.Screen.WALK
    }

    // ------------------------------------------------------------------ R2-U3-01
    /**
     * «Ενημέρωσε την εφαρμογή / στο ρολόι»: οι δύο γραμμές με ΕΝΑ μέγεθος, και με γράμματα 1,3×, σε κάθε θέση (στη θέση
     * του τρίτου κουμπιού 150u, πάνω με προπόνηση του κινητού 36u, κάτω από το «Περπάτημα» χωρίς πρόγραμμα 170u). Πριν, με
     * 1,3× η 1η γραμμή μίκραινε μόνη της (≈ 11,5u) και η 2η έμενε 13u.
     */
    @Test
    fun updateMessageLinesShareOneSize() {
        val l1 = "Ενημέρωσε την εφαρμογή"
        val l2 = "στο ρολόι"
        for (scale in listOf(1f, 1.3f)) {
            for (case in listOf("plan", "phone", "noplan")) {
                reset()
                RuntimeEnvironment.setFontScale(scale)
                if (case != "noplan") Repo.applyPlan(Plan.parse(planJson))
                if (case == "phone") Repo.applyPhone(LiveSession.parsePhone(phoneJson))
                Repo.updateNeeded = true
                Repo.screen = Repo.Screen.HOME
                val v = newView()
                val bmp = draw(v, "R2_W12_update_$case${if (scale == 1f) "" else "_font13"}")
                val sizes = v.drawnSizes!!
                assertTrue("$scale× $case: $sizes", l1 in sizes && l2 in sizes)
                val s1 = sizes.getValue(l1)
                assertEquals("$scale× $case: $sizes", s1, sizes.getValue(l2), 0f)
                // 1,0×: χωράνε στα 10u όπως πριν. 1,3×: η 1η γραμμή δεν χωρά στα 13u (≈ 145u > 130u), άρα μικραίνουν και οι δύο.
                if (scale == 1f) assertEquals(10f, s1, 0f) else assertTrue("$scale× $case: $s1", s1 >= 8.5f && s1 < 13f)
                assertTrue("$scale× $case: ${v.clipped}", v.clipped.isEmpty())
                assertTrue("$scale× $case: ${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            }
        }
    }

    // ------------------------------------------------------------------ R2-U3-02
    /** Μήνυμα σε όλη την οθόνη: κάτω «πάτα για να κλείσει» (όπως στην κόκκινη οθόνη), που δεν ακουμπά το κείμενο. */
    private fun assertHintBelowText(v: WatchView, bmp: Bitmap, scale: Float, what: String) {
        assertTrue("$what: ${v.drawnSizes}", "πάτα για να κλείσει" in v.drawnSizes!!)
        assertTrue("$what: ${v.clipped}", v.clipped.isEmpty())
        assertTrue("$what: ${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
        val hint = rows(bmp, ::hintPx)
        val text = rows(bmp, ::whitePx)
        assertTrue("$what: φράση ${hint.size}, κείμενο ${text.size}", hint.isNotEmpty() && text.isNotEmpty())
        // Η φράση κάτω από το κείμενο, με τουλάχιστον μία ολόμαυρη γραμμή ανάμεσα.
        assertTrue("$what: κείμενο ως ${text.last()}, φράση από ${hint.first()}", text.last() < hint.first())
        val gap = (text.last() + 1 until hint.first()).filter { y -> (0 until size).all { x -> isBlack(bmp.getPixel(x, y)) } }
        assertTrue("$what: καμία μαύρη γραμμή ανάμεσα", gap.isNotEmpty())
        // Στη θέση της κόκκινης οθόνης: βάση 166u (1,3×: 178u), γράμματα από ≈ 0,86 × μέγεθος πάνω ως 0,24 × κάτω.
        val base = 166f + 40f * (scale - 1f)
        assertTrue("$what: ${hint.first() / u}–${hint.last() / u}", hint.first() >= ((base - 14f) * u).toInt() && hint.last() <= ((base + 5f) * u).toInt())
    }

    @Test
    fun fullScreenNoticeSaysHowItCloses() {
        val now = System.currentTimeMillis()
        val forgot = Forgotten.title(Forgotten.Why.STRENGTH_IDLE) + " " + Forgotten.text(Forgotten.Why.STRENGTH_IDLE)
        for (scale in listOf(1f, 1.3f)) {
            reset()
            RuntimeEnvironment.setFontScale(scale)
            // Σετ: κάθε μήνυμα της υπηρεσίας ανοίγει σε όλη την οθόνη (εδώ η υπενθύμιση «Τρέχει ακόμα η προπόνηση;»).
            startSet(now)
            Repo.notice = forgot
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R2_W2c_set_forgotten_notice" else "R2_W2d_set_forgotten_notice_font13")
            // Για το TalkBack ίδιο με πριν: το μήνυμα και ένα «Κλείσιμο».
            assertEquals(listOf(forgot, "Κλείσιμο"), labels(v))
            assertHintBelowText(v, bmp, scale, "$scale× σετ")
            // Πάτημα πάνω στη φράση: κλείνει· ξαναφαίνονται το «Τέλος» και το ✓.
            tap(v, size / 2f, (166f + 40f * (scale - 1f) - 4f) * u)
            assertNull(Repo.notice)
            draw(v)
            assertTrue(labels(v).toString(), "Τέλος" in labels(v) && "Έγινε το σετ" in labels(v))
            // Το πιο μακρύ μήνυμα (αργή δόνηση ορίου + GPS, ανοίγει μόνο του στο περπάτημα): δεν φτάνει ως τη φράση.
            Repo.local = null
            Repo.resetExercise()
            startWalk(now)
            Repo.notice = withSafety(SLOW_ALARM_TEXT, "Χωρίς GPS: η απόσταση από τα βήματα.")
            Repo.openNotice = true
            val w = newView()
            val wb = draw(w, if (scale == 1f) "R2_W7k_walk_slow_alarm" else "R2_W7l_walk_slow_alarm_font13")
            assertEquals("Κλείσιμο", labels(w).last())
            assertHintBelowText(w, wb, scale, "$scale× περπάτημα")
        }
    }

    // ------------------------------------------------------------------ R2-U3-03
    @Test
    fun twoLineNoticeBreaksAfterTheColon() {
        val now = System.currentTimeMillis()
        val expect = listOf(
            "Πάτα ξανά: επόμενη άσκηση" to ("Πάτα ξανά:" to "επόμενη άσκηση"),
            finishNotice(true, 2, true) to ("Πάτα ξανά:" to "τέλος και στο κινητό"),
            // Round 7 (R7-U3-01): η οδηγία πρώτη («Πάτα ξανά: …»).
            finishNotice(true, 0, true) to ("Πάτα ξανά: στο κινητό" to "μένουν μόνο οι παλμοί"),
            finishNotice(true, 0, false) to ("Πάτα ξανά:" to "δεν μένει τίποτα"),
        )
        for (scale in listOf(1f, 1.3f)) {
            reset()
            RuntimeEnvironment.setFontScale(scale)
            Repo.applyPhone(LiveSession.parsePhone(phoneJson))
            Repo.running = "strength"
            Repo.runningPhone = true
            Repo.bpm = 118
            Repo.bpmAt = now
            Repo.screen = Repo.Screen.SET
            for ((i, e) in expect.withIndex()) {
                val (note, two) = e
                Repo.notice = note
                val v = newView()
                val bmp = draw(v, if (i < 2) "R2_W13_notice_colon_$i${if (scale == 1f) "" else "_font13"}" else null)
                val sizes = v.drawnSizes!!
                assertTrue("$scale× «$note»: $sizes", two.first in sizes && two.second in sizes)
                // Ολόκληρες, με το ίδιο μέγεθος, μέσα στον κύκλο.
                assertEquals("$scale× «$note»", sizes.getValue(two.first), sizes.getValue(two.second), 0f)
                assertTrue("$scale× «$note»: ${v.clipped}", v.clipped.isEmpty())
                assertTrue("$scale× «$note»: ${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            }
            // Πριν: «Πάτα ξανά: επόμενη» / «άσκηση» (μία λέξη μόνη της στη 2η γραμμή).
            Repo.notice = "Πάτα ξανά: επόμενη άσκηση"
            val v = newView()
            draw(v)
            val sizes = v.drawnSizes!!
            assertFalse(sizes.toString(), "άσκηση" in sizes || "Πάτα ξανά: επόμενη" in sizes)
        }
    }
}
