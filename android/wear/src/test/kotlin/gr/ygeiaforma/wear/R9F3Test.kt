package gr.ygeiaforma.wear

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import org.json.JSONArray
import org.json.JSONObject
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
import java.time.LocalDate

/**
 * Έλεγχος 14/11, round 9 (f3, ρολόι): οι κανόνες, καλώντας τον ίδιο τον κώδικα (όχι έλεγχο κειμένου). Οι τιμές που
 * περιμένουμε βγαίνουν από τον γραμμένο κανόνα, όχι από τον κώδικα. Όλα τα νούμερα είναι δοκιμαστικά.
 */
class R9F3Test {
    private val t0 = 1_700_000_000_000L
    private val day = 86_400_000L

    private fun set(reps: Int, done: Boolean = false, at: Long = 0) =
        JSONObject().put("label", "10,3 kg").put("load", 10.3).put("reps", reps).also { if (done) it.put("done", true).put("at", at) }

    /** Μία άσκηση της προπόνησης του κινητού· [first]: «f»: 1 (εκκρεμεί η ερώτηση «Πρώτο σετ»). */
    private fun item(ex: String, first: Boolean, vararg sets: JSONObject): JSONObject =
        JSONObject().put("ex", ex).put("name", ex).put("rest", 90).put("lo", 8).put("hi", 12).put("rir", 2)
            .put("sets", JSONArray(sets.toList())).also { if (first) it.put("f", 1) }

    /** Η προπόνηση του κινητού ([Paths.SESSION]) [id], που ξεκίνησε στις [t0]. */
    private fun phone(id: String, vararg items: JSONObject): LiveSession =
        LiveSession.parsePhone(
            JSONObject().put("v", 1).put("active", true).put("id", id).put("w", "A").put("name", "Α").put("start", t0)
                .put("idx", 0).put("restEnd", 0).put("items", JSONArray(items.toList())).toString(),
        )!!

    private fun clean() {
        Repo.phone = null
        Repo.lastPhone = null
        Repo.local = null
        Repo.plan = null
        Repo.unsaved.clear()
        Repo.endUnsaved = false
        Repo.resetExercise()
    }

    @Before
    fun before() {
        clean()
    }

    @After
    fun after() {
        clean()
    }

    /** «Παλμοί εδώ» στην προπόνηση [id] του κινητού, από τις [t0], με παλμούς 110 για 30″. */
    private fun runningPhone(id: String) {
        Repo.running = "strength"
        Repo.runningPhone = true
        Repo.runningSid = id
        Repo.startedAt = t0
        Repo.hr = HrStats(t0).also { for (k in 0..30) it.add(110, t0 + k * 1000L) }
    }

    // ------------------------------------------------------------------ R9-A12-2 (ρολόι)
    /**
     * Το πάτημα της οθόνης ([LiveSession.answerAny], αυτό που καλεί η WatchActivity): η απάντηση στο «Πρώτο σετ» ΚΛΕΙΝΕΙ την
     * ερώτηση εδώ, χωρίς να περιμένει νέα κατάσταση από το κινητό (που ακόμα λέει «f»), και δίνει την εντολή «rir1». Μετά το
     * τελευταίο σετ η απάντηση πάει στη ρεζέρβα της άσκησης (όχι ξανά στο «Πρώτο σετ»), χωρίς δεύτερη «rir1».
     */
    @Test
    fun firstSetAnswerClosesTheQuestionThenTheExerciseRirIsWritten() {
        Repo.applyPhone(phone("sA", item("db_press", true, set(10), set(10), set(10))))
        runningPhone("sA")
        val p = Repo.phone!!
        assertEquals(LiveSession.Next.REST, p.tick(t0 + 60_000))
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        val a = p.answerAny(2, t0 + 65_000)
        assertTrue(a.first)
        assertNull(a.next)
        assertEquals(0, a.i)
        val c = a.rir1!!
        assertEquals("rir1", c.getString("op"))
        assertEquals(0, c.getInt("i"))
        assertEquals(0, c.getInt("s"))
        assertEquals("db_press", c.getString("ex"))
        assertEquals(2, c.getInt("v"))
        assertEquals(t0 + 60_000, c.getLong("at"))
        // Η ερώτηση έκλεισε εδώ· το κινητό (χωρίς νέα κατάσταση) ζητά ακόμα «f».
        assertEquals(-1, p.firstIdx)
        assertFalse(p.firstPending)
        assertTrue(p.items[0].first)
        assertEquals(2, p.firstAns["db_press"])
        assertNull(p.items[0].rir)
        assertFalse(p.rirPending)
        // Τα επόμενα σετ, πάλι χωρίς νέα κατάσταση από το κινητό: καμία νέα ερώτηση 1ου σετ.
        assertEquals(LiveSession.Next.REST, p.tick(t0 + 200_000))
        assertFalse(p.askFirst(0, 1, LiveSession.Next.REST))
        assertEquals(LiveSession.Next.ASK_RIR, p.tick(t0 + 400_000))
        assertTrue(p.rirPending)
        // Η απάντηση τώρα είναι η ρεζέρβα της άσκησης: γράφεται, χωρίς δεύτερη «rir1», και η προπόνηση (μία άσκηση) τελείωσε.
        val b = p.answerAny(3, t0 + 410_000)
        assertFalse(b.first)
        assertNull(b.rir1)
        assertEquals(0, b.i)
        assertEquals(LiveSession.Next.END, b.next)
        assertEquals(3, p.items[0].rir)
        assertFalse(p.rirPending)
        assertEquals(2, p.firstAns["db_press"])
    }

    /** «Δεν ξέρω» (−1) στο «Πρώτο σετ»: −1 στην εντολή και στη μνήμη· η ρεζέρβα της άσκησης μένει χωρίς απάντηση. */
    @Test
    fun firstSetDontKnowIsMinusOne() {
        Repo.applyPhone(phone("sB", item("db_row", true, set(10), set(10))))
        runningPhone("sB")
        val q = Repo.phone!!
        q.tick(t0 + 60_000)
        assertTrue(q.askFirst(0, 0, LiveSession.Next.REST))
        val a = q.answerAny(-1, t0 + 61_000)
        assertTrue(a.first)
        assertEquals(-1, a.rir1!!.getInt("v"))
        assertEquals(-1, q.firstAns["db_row"])
        assertEquals(-1, q.firstIdx)
        assertNull(q.items[0].rir)
        // Ανοιχτή ερώτηση που το κινητό δεν ζητά πια (απαντήθηκε εκεί, χωρίς «f»): κλείνει, χωρίς εντολή και χωρίς απάντηση.
        clean()
        Repo.applyPhone(phone("sC", item("db_row", false, set(10), set(10))))
        runningPhone("sC")
        val n = Repo.phone!!
        n.tick(t0 + 60_000)
        n.firstIdx = 0
        val b = n.answerAny(4, t0 + 61_000)
        assertTrue(b.first)
        assertNull(b.rir1)
        assertEquals(-1, b.i)
        assertEquals(-1, n.firstIdx)
        assertTrue(n.firstAns.isEmpty())
        assertNull(n.items[0].rir)
    }

    // ------------------------------------------------------------------ R9-A8-3 (ρολόι)
    /**
     * Η «rir1» δεν έφτασε (κινητό που δεν άκουγε): ξαναστέλνεται όσο η κατάσταση του κινητού ζητά ακόμα την ερώτηση («f») και
     * έχει ήδη το ✓ του 1ου σετ· πριν από αυτό ξαναστέλνεται το ✓. Μόλις το κινητό τη δεχτεί (χωρίς «f»), τίποτα.
     */
    @Test
    fun firstSetAnswerIsResentUntilThePhoneHasIt() {
        Repo.applyPhone(phone("sA", item("db_press", true, set(10), set(10), set(10))))
        runningPhone("sA")
        val p = Repo.phone!!
        p.tick(t0 + 60_000)
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        p.answerAny(4, t0 + 62_000)
        // Το κινητό δεν έχει δει ακόμα ούτε το ✓: πρώτα ξαναστέλνεται το ✓ (με τις επαναλήψεις του), όχι η απάντηση.
        assertEquals(listOf(0 to 0), Repo.pendingTicks)
        assertTrue(Repo.pendingFirst.isEmpty())
        // Το κινητό είδε το ✓ αλλά όχι την απάντηση («f» ακόμα): ξαναστέλνεται, ίδια με την πρώτη.
        Repo.applyPhone(phone("sA", item("db_press", true, set(10, done = true, at = t0 + 60_000), set(10), set(10))))
        assertTrue(Repo.pendingTicks.isEmpty())
        assertEquals(listOf(Triple(0, "db_press", 4)), Repo.pendingFirst)
        val (i, ex, v) = Repo.pendingFirst.single()
        val c = rir1Cmd(i, ex, Repo.phone!!.items[i].sets[0].at, v)
        assertEquals(t0 + 60_000, c.getLong("at"))
        assertEquals(4, c.getInt("v"))
        assertEquals("db_press", c.getString("ex"))
        // Ξανά η ίδια κατάσταση (το κινητό δεν την επεξεργάστηκε ακόμα): ακόμα εκκρεμεί.
        Repo.applyPhone(phone("sA", item("db_press", true, set(10, done = true, at = t0 + 60_000), set(10), set(10))))
        assertEquals(listOf(Triple(0, "db_press", 4)), Repo.pendingFirst)
        // Το κινητό τη δέχτηκε (χωρίς «f»): τίποτα πια· η απάντηση μένει για το αποτέλεσμα.
        Repo.applyPhone(phone("sA", item("db_press", false, set(10, done = true, at = t0 + 60_000), set(10), set(10))))
        assertTrue(Repo.pendingFirst.isEmpty())
        assertEquals(4, Repo.phone!!.firstAns["db_press"])
        // Το κινητό είχε δει το ✓ και ο χρήστης το έβγαλε εκεί («f» ακόμα, σετ 0 χωρίς ✓): καμία επανάληψη.
        clean()
        Repo.applyPhone(phone("sB", item("db_press", true, set(10), set(10))))
        runningPhone("sB")
        Repo.phone!!.tick(t0 + 60_000)
        assertTrue(Repo.phone!!.askFirst(0, 0, LiveSession.Next.REST))
        Repo.phone!!.answerAny(1, t0 + 61_000)
        Repo.applyPhone(phone("sB", item("db_press", true, set(10, done = true, at = t0 + 60_000), set(10))))
        assertEquals(listOf(Triple(0, "db_press", 1)), Repo.pendingFirst)
        Repo.applyPhone(phone("sB", item("db_press", true, set(10), set(10))))
        assertFalse(Repo.phone!!.items[0].sets[0].done)
        assertTrue(Repo.pendingFirst.isEmpty())
        // Καμία απάντηση εδώ (π.χ. απαντήθηκε στο κινητό): ποτέ.
        clean()
        Repo.applyPhone(phone("sC", item("db_press", true, set(10, done = true, at = t0 + 60_000), set(10))))
        runningPhone("sC")
        assertTrue(Repo.pendingFirst.isEmpty())
    }

    /**
     * Η απάντηση μένει και μετά από απότομο κλείσιμο της εφαρμογής του ρολογιού («fr» στο στιγμιότυπο): ξαναστέλνεται, και
     * πάει στο αποτέλεσμα των παλμών ως «fr» μόνο στην άσκηση που απαντήθηκε (αντίγραφο της «rir1», όπως το «ra»).
     */
    @Test
    fun firstSetAnswerSurvivesARestartAndGoesToTheResult() {
        Repo.applyPhone(phone("sA", item("db_press", true, set(10), set(10), set(10)), item("db_row", true, set(11), set(11))))
        runningPhone("sA")
        val p = Repo.phone!!
        p.tick(t0 + 60_000)
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        p.answerAny(1, t0 + 62_000)
        // Η κατάσταση του κινητού αφού είδε το ✓ (χωρίς την απάντηση: «f» ακόμα). Νέο αντικείμενο κάθε φορά: το applyPhone
        // γράφει μέσα του ό,τι ξέρει το ρολόι.
        fun seen() = phone("sA", item("db_press", true, set(10, done = true, at = t0 + 60_000), set(10), set(10)), item("db_row", true, set(11), set(11)))
        Repo.applyPhone(seen())
        val snap = Repo.captureRun(t0 + 70_000)!!
        assertEquals(1, snap.getJSONObject("pp").getJSONObject("fr").getInt("db_press"))
        assertFalse(snap.getJSONObject("pp").getJSONObject("fr").has("db_row"))
        val text = snap.toString()
        // Η εφαρμογή κλείνει απότομα: η μνήμη χάνεται. Νέο άνοιγμα: πρώτα η κατάσταση του κινητού, μετά το στιγμιότυπο.
        Repo.phone = null
        Repo.lastPhone = null
        Repo.resetExercise()
        Repo.applyPhone(seen())
        assertTrue(Repo.pendingFirst.isEmpty())
        assertTrue(Repo.restoreRun(JSONObject(text), t0 + 600_000, 9_000_000))
        assertEquals(listOf(Triple(0, "db_press", 1)), Repo.pendingFirst)
        // Στο αποτέλεσμα (μερικό): «fr» μόνο στην άσκηση που απαντήθηκε.
        val r = Results.build(t0 + 600_000, partialAt = snap.getLong("saved"))!!
        val items = r.second.getJSONArray("items")
        assertEquals("db_press", items.getJSONObject(0).getString("ex"))
        assertEquals(1, items.getJSONObject(0).getInt("fr"))
        assertFalse(items.getJSONObject(1).has("fr"))
        // Στιγμιότυπο χωρίς «fr» (έκδοση ως #107): καμία απάντηση, καμία επανάληψη, κανένα «fr».
        clean()
        val old = JSONObject(text)
        old.getJSONObject("pp").remove("fr")
        Repo.applyPhone(seen())
        assertTrue(Repo.restoreRun(old, t0 + 600_000, 9_000_000))
        assertTrue(Repo.phone!!.firstAns.isEmpty())
        assertTrue(Repo.pendingFirst.isEmpty())
        assertFalse(Results.build(t0 + 600_000, partialAt = t0 + 70_000)!!.second.getJSONArray("items").getJSONObject(0).has("fr"))
        // Τιμές εκτός −1…4 στο στιγμιότυπο αγνοούνται· το −1 («Δεν ξέρω») κρατιέται.
        val pp = LiveSession.phoneWatchState(seen()).put("fr", JSONObject().put("db_press", 7).put("db_row", -1))
        val back = LiveSession.phoneFromWatchState(pp)!!
        assertNull(back.firstAns["db_press"])
        assertEquals(-1, back.firstAns["db_row"])
        // Χωρίς καμία απάντηση εδώ: κανένα «fr» στο στιγμιότυπο.
        assertFalse(LiveSession.phoneWatchState(seen()).has("fr"))
    }

    // ------------------------------------------------------------------ R9-A7-2
    /**
     * Περπάτημα με ζώνη 108–131 που η εφαρμογή του ρολογιού έκλεισε απότομα· το μερικό αποτέλεσμα γράφεται μέρες μετά, όταν
     * το πρόγραμμα έχει άλλη ζώνη (110–133): γράφεται με τη ζώνη που ίσχυε στο περπάτημα. Παλιό στιγμιότυπο: όπως πριν.
     */
    @Test
    fun walkZoneIsKeptInTheSnapshotAndThePartialResult() {
        Repo.running = "walk"
        Repo.startedAt = t0
        Repo.hr = HrStats(t0).also { h -> for (k in 0 until 600) h.add(118, t0 + k * 1000L) }
        Repo.zoneAlarm.start(WalkZone(108, 131), 0)
        val snap = Repo.captureRun(t0 + 600_000)!!
        val z = snap.getJSONObject("zone")
        assertEquals(108, z.getInt("lo"))
        assertEquals(131, z.getInt("hi"))
        assertTrue(z.getBoolean("up"))
        assertFalse(z.getBoolean("down"))
        val text = snap.toString()
        Repo.resetExercise()
        assertNull(Repo.zoneAlarm.zone)
        Repo.plan = Plan.parse("""{"v":1,"at":1,"workouts":[],"zone":{"lo":110,"hi":133}}""")
        assertTrue(Repo.restoreRun(JSONObject(text), t0 + 3 * day, 9_000_000))
        assertEquals(WalkZone(108, 131), Repo.zoneAlarm.zone)
        val r = Results.build(t0 + 3 * day, partialAt = snap.getLong("saved"))!!
        assertEquals(1, r.second.getInt("partial"))
        val cz = r.second.getJSONObject("cardio").getJSONObject("zone")
        assertEquals(108, cz.getInt("lo"))
        assertEquals(131, cz.getInt("hi"))
        // Στιγμιότυπο χωρίς «zone» (έκδοση ως #107): χωρίς ζώνη, όπως πριν (το κινητό βάζει τη δική του).
        Repo.resetExercise()
        val old = JSONObject(text)
        old.remove("zone")
        assertTrue(Repo.restoreRun(old, t0 + 3 * day, 9_000_000))
        assertNull(Repo.zoneAlarm.zone)
        assertFalse(Results.build(t0 + 3 * day, partialAt = t0 + 600_000)!!.second.getJSONObject("cardio").has("zone"))
        // Ζώνη που δεν μοιάζει σωστή: καμία (όχι λάθος ζώνη).
        Repo.resetExercise()
        assertTrue(Repo.restoreRun(JSONObject(text).put("zone", JSONObject().put("lo", 140).put("hi", 120)), t0 + 3 * day, 9_000_000))
        assertNull(Repo.zoneAlarm.zone)
        // Προπόνηση με βάρη: καμία ζώνη, ακόμα κι αν το στιγμιότυπο έχει.
        Repo.resetExercise()
        assertTrue(Repo.restoreRun(JSONObject(text).put("kind", "strength"), t0 + 3 * day, 9_000_000))
        assertNull(Repo.zoneAlarm.zone)
    }

    /** Συνέχεια περπατήματος (ATTACH): η ζώνη του προγράμματος αν υπάρχει πρόγραμμα, αλλιώς αυτή του στιγμιότυπου. */
    @Test
    fun resumedWalkZone() {
        val kept = WalkZone(108, 131)
        assertEquals(kept, resumeZone(null, kept))
        assertNull(resumeZone(null, null))
        assertEquals(WalkZone(110, 133), resumeZone(Plan.parse("""{"v":1,"at":1,"workouts":[],"zone":{"lo":110,"hi":133}}"""), kept))
        // Πρόγραμμα χωρίς ζώνη (το κινητό την έβγαλε): καμία, όπως με ένα νέο πρόγραμμα στη μέση του περπατήματος.
        assertNull(resumeZone(Plan.parse("""{"v":1,"at":1,"workouts":[]}"""), kept))
    }

    // ------------------------------------------------------------------ R9-U3-09
    /** «Η άσκηση σταμάτησε …»: για το όριο μόνο με όριο γιατρού· με δόνηση ζώνης, ότι σταμάτησε η δόνηση. */
    @Test
    fun endedElsewhereSpeaksOfTheLimitOnlyWithALimit() {
        val none = endedElsewhereText(hasLimit = false, zoneBuzz = false)
        assertEquals("Ό,τι μετρήθηκε σώθηκε.", none)
        val zone = endedElsewhereText(hasLimit = false, zoneBuzz = true)
        assertEquals("Ό,τι μετρήθηκε σώθηκε. Η δόνηση της ζώνης σταμάτησε.", zone)
        for (t in listOf(none, zone)) assertFalse(t, t.contains("όριο"))
        // Με όριο γιατρού (και με ζώνη: τότε η ζώνη δεν δονείται έτσι κι αλλιώς): όπως πριν.
        for (zb in listOf(false, true)) {
            assertEquals("Ό,τι μετρήθηκε σώθηκε. Το όριο παλμών δεν σε προσέχει πια.", endedElsewhereText(hasLimit = true, zoneBuzz = zb))
        }
    }
}

/**
 * Έλεγχος 14/11, round 9 (f3, ρολόι): οι οθόνες, ζωγραφισμένες από τον πραγματικό κώδικα (WatchView), όπως στο R8F3ViewTest.
 * Τα στιγμιότυπα γράφονται στο build/watch-shots/ (όνομα «R9_…»).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class R9F3ViewTest {
    private val size = 454
    private val u = size / 200f

    private val planJson = """
        {"v":1,"today":"A","at":1,
         "workouts":[
          {"id":"A","name":"Προπόνηση Α","minutes":50,"items":[
            {"ex":"db_press","name":"Πιεστικό με αλτήρες","rest":120,"lo":8,"hi":12,"rir":2,
             "sets":[{"load":10.3,"label":"10,3 kg","reps":8},{"load":10.3,"label":"10,3 kg","reps":8}]}]},
          {"id":"B","name":"Προπόνηση Β","minutes":45,"items":[
            {"ex":"db_row","name":"Κωπηλασία με αλτήρα","rest":90,"lo":8,"hi":12,"rir":2,
             "sets":[{"load":14.3,"label":"14,3 kg","reps":11}]}]},
          {"id":"walk","name":"Περπάτημα","minutes":30,"cardio":{"activity":"walk","name":"Περπάτημα","minutes":30,"note":"χαλαρά"}}]}
    """.trimIndent()

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

    /** Το [Repo] είναι κοινό για όλες τις δοκιμές της ίδιας εκτέλεσης: καθαρό και πριν, και μετά. */
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
        Repo.unsaved.clear()
        Repo.endUnsaved = false
        Repo.resetExercise()
        Repo.alarm.limit = null
        Repo.alarm.reset()
        WatchView.noHrSeenNow = false
    }

    private fun newView(acts: WatchView.Actions = noop): WatchView {
        val v = WatchView(RuntimeEnvironment.getApplication(), acts)
        v.drawnSizes = mutableMapOf()
        val spec = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
        v.measure(spec, spec)
        v.layout(0, 0, size, size)
        return v
    }

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

    private fun isBlack(p: Int): Boolean = (p and 0x00FFFFFF) == 0

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

    /** Πλάτος (u) ό,τι ζωγραφίστηκε πάνω από το ύψος [below] u (από το αριστερότερο ως το δεξιότερο φωτεινό σημείο). */
    private fun inkWidthAbove(bmp: Bitmap, below: Float): Float {
        var lo = Int.MAX_VALUE
        var hi = -1
        for (y in 0 until (below * u).toInt()) for (x in 0 until size) {
            if (isBlack(bmp.getPixel(x, y))) continue
            if (x < lo) lo = x
            if (x > hi) hi = x
        }
        return if (hi < 0) 0f else (hi - lo + 1) / u
    }

    // ------------------------------------------------------------------ R9-U3-01
    /** Μέρα ξεκούρασης με πρόγραμμα: «Σήμερα» μία φορά (η κεφαλίδα), όχι ξανά «ΣΗΜΕΡΑ» από κάτω. */
    @Test
    fun restDayWritesTodayOnlyOnce() {
        val walkOnly = """{"v":1,"at":1,"workouts":[{"id":"walk","name":"Περπάτημα","minutes":30,"cardio":{"activity":"walk","name":"Περπάτημα","minutes":30}}]}"""
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.applyPlan(Plan.parse(walkOnly))
            Repo.screen = Repo.Screen.HOME
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R9_W1l_home_rest_today_once" else null)
            val keys = v.drawnSizes!!.keys
            assertTrue(keys.toString(), "Σήμερα · χωρίς όριο" in keys)
            assertFalse(keys.toString(), "ΣΗΜΕΡΑ" in keys)
            assertEquals(keys.toString(), 1, keys.count { it.contains("Σήμερα") || it.contains("ΣΗΜΕΡΑ") })
            assertTrue(keys.toString(), "Ξεκούραση" in keys)
            assertTrue(labels(v).toString(), labels(v).first().contains("Σήμερα ξεκούραση"))
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            // Με «Ενημέρωσε την εφαρμογή» δεν γράφεται η κεφαλίδα: τότε μένει η ετικέτα «ΣΗΜΕΡΑ».
            Repo.updateNeeded = true
            val upd = newView()
            draw(upd)
            val k2 = upd.drawnSizes!!.keys
            assertTrue(k2.toString(), "ΣΗΜΕΡΑ" in k2)
            assertFalse(k2.toString(), k2.any { it.startsWith("Σήμερα · ") })
            Repo.updateNeeded = false
        }
    }

    // ------------------------------------------------------------------ R9-U3-02
    /** Περπάτημα ΜΕ όριο γιατρού: στα πρώτα 30″ «περιμένω παλμούς» (όπως στο σετ)· μετά, όπως πριν, «δεν σε προσέχει». */
    @Test
    fun walkWithADoctorLimitWaitsForTheFirstHeartRateToo() {
        val now = System.currentTimeMillis()
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.resetExercise()
            Repo.alarm.limit = 140
            Repo.running = "walk"
            Repo.startedAt = now - 5_000
            Repo.activeSec = 5
            Repo.gps = true
            Repo.bpm = 0
            Repo.bpmAt = 0
            Repo.screen = Repo.Screen.WALK
            val v = newView()
            draw(v, if (scale == 1f) "R9_W7d_walk_limit_waiting_hr" else null)
            val first = labels(v).first()
            assertTrue(first, first.startsWith("Περιμένω παλμούς"))
            assertFalse(first, first.contains("δεν σε προσέχει"))
            assertTrue(v.drawnSizes.toString(), HR_WAIT_TEXT in v.drawnSizes!!)
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            // Μετά τα 30″ χωρίς κανέναν παλμό: ότι το όριο δεν σε προσέχει (ίδια στιγμή με τη δόνηση και με το κινητό).
            Repo.startedAt = now - 40_000
            Repo.activeSec = 40
            val late = newView()
            draw(late)
            assertTrue(labels(late).first(), labels(late).first().contains("το όριο δεν σε προσέχει"))
            assertFalse(late.drawnSizes.toString(), HR_WAIT_TEXT in late.drawnSizes!!)
        }
    }

    // ------------------------------------------------------------------ R9-U3-10
    /**
     * Πρόγραμμα που ξεκινά αύριο (σήμερα καμία προπόνηση): η κεφαλίδα «Άλλη προπόνηση · …» χωρά ολόκληρη στη χορδή του κύκλου
     * στο ύψος της (3u από την άκρη, U7-03), με και χωρίς όριο, με γράμματα 1× και 1,3×.
     */
    @Test
    fun otherWorkoutHeaderStaysInsideTheCircle() {
        val tomorrow = LocalDate.now().plusDays(1).toString()
        for (lim in listOf<Int?>(null, 140)) for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            val json = JSONObject(planJson).put("from", tomorrow)
            if (lim != null) json.put("hrLimit", lim)
            Repo.applyPlan(Plan.parse(json.toString()))
            Repo.screen = Repo.Screen.HOME
            val v = newView()
            val bmp = draw(v, if (scale == 1f && lim == null) "R9_W1m_home_other_header" else null)
            val header = "Άλλη προπόνηση · " + (if (lim != null) "όριο $lim" else "χωρίς όριο")
            val sz = v.drawnSizes!![header]
            assertTrue("$scale× $lim: ${v.drawnSizes}", sz != null && sz >= 8.5f)
            // Πάνω από τα κουμπιά (που αρχίζουν στα 44u) είναι μόνο η κεφαλίδα.
            val ink = inkWidthAbove(bmp, 40f)
            val chord = chordAt(33f, sz!!)
            assertTrue("$scale× $lim: $ink > $chord", ink > 0f && ink <= chord + 1f)
            assertTrue("$scale× $lim: ${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            Repo.alarm.limit = null
        }
    }

    // ------------------------------------------------------------------ R9-A7-2 (η πραγματική διαδρομή, με αρχεία)
    /** Μερικό περπάτημα από στιγμιότυπο ([Repo.finalizeRun]): με τη ζώνη που ίσχυε, όχι με τη ζώνη του τωρινού προγράμματος. */
    @Test
    fun partialWalkKeepsItsZoneThroughFinalizeRun() {
        val ctx = RuntimeEnvironment.getApplication()
        val t0 = 1_700_000_000_000L
        Repo.running = "walk"
        Repo.startedAt = t0
        Repo.hr = HrStats(t0).also { h -> for (k in 0 until 300) h.add(118, t0 + k * 1000L) }
        Repo.zoneAlarm.start(WalkZone(108, 131), 0)
        val snap = JSONObject(Repo.captureRun(t0 + 300_000)!!.toString())
        Repo.resetExercise()
        Repo.applyPlan(Plan.parse("""{"v":1,"at":1,"workouts":[],"zone":{"lo":110,"hi":133}}"""))
        val r = Repo.finalizeRun(ctx, snap, t0 + 2 * 86_400_000L, 9_000_000)!!
        try {
            assertEquals("walk$t0", r.first)
            assertEquals(1, r.second.getInt("partial"))
            val z = r.second.getJSONObject("cardio").getJSONObject("zone")
            assertEquals(108, z.getInt("lo"))
            assertEquals(131, z.getInt("hi"))
            // Μετά: τίποτα δεν τρέχει, καμία ζώνη στη μνήμη.
            assertNull(Repo.running)
            assertNull(Repo.zoneAlarm.zone)
        } finally {
            Repo.removePending(ctx, r.first)
        }
    }
}
