package gr.ygeiaforma.wear

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
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
import java.time.ZoneId

/**
 * Έλεγχος 14/11, round 8 (f3, ρολόι): οι καθαροί κανόνες. Οι τιμές που περιμένουμε βγαίνουν από τον γραμμένο κανόνα, όχι
 * από τον κώδικα. Όλα τα νούμερα είναι δοκιμαστικά.
 */
class R8F3Test {
    private val t0 = 1_700_000_000_000L
    private val hour = 3_600_000L

    private fun source(name: String): String = File("src/main/kotlin/gr/ygeiaforma/wear/$name").readText()

    private fun set(reps: Int, done: Boolean = false, at: Long = 0) =
        JSONObject().put("label", "10,3 kg").put("load", 10.3).put("reps", reps).also { if (done) it.put("done", true).put("at", at) }

    /** Η προπόνηση του κινητού ([Paths.SESSION]) με μία άσκηση, που ξεκίνησε στις [start]. */
    private fun phoneJson(id: String, start: Long, vararg sets: JSONObject): String =
        JSONObject().put("v", 1).put("active", true).put("id", id).put("w", "A").put("name", "Α").put("start", start)
            .put("idx", 0).put("restEnd", 0)
            .put(
                "items",
                JSONArray().put(
                    JSONObject().put("ex", "db_press").put("name", "Πιεστικό").put("rest", 90).put("lo", 8).put("hi", 12)
                        .put("rir", 2).put("sets", JSONArray(sets.toList())),
                ),
            )
            .toString()

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

    // ------------------------------------------------------------------ R8-A8-1
    /**
     * Το κινητό έκλεισε την προπόνηση και η μέτρηση κλείνει ([stopping]): ένα πάτημα «Περπάτημα» ή «προπόνηση» στο ρολόι
     * εκείνη τη στιγμή δεν την κάνει «όχι του κινητού». Το αποτέλεσμα των παλμών της γράφεται, με το ✓ του ρολογιού.
     */
    @Test
    fun beginWhileFinishingDoesNotTurnAPhoneSessionIntoNothing() {
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", t0, set(10, done = true, at = t0 + 60_000), set(10))))
        runningPhone("sA")
        // ✓ στο ρολόι που το κινητό δεν είδε.
        Repo.phone!!.tick(t0 + 120_000)
        // Το κινητό κλείνει την προπόνηση: η υπηρεσία τη γράφει (stopping).
        Repo.applyPhone(null)
        for ((kind, fromPhone) in listOf("walk" to false, "strength" to false, "strength" to true)) {
            assertFalse("$kind/$fromPhone", Repo.joinWhileRunning(kind, fromPhone, stopping = true))
            assertTrue("$kind/$fromPhone", Repo.runningPhone)
            assertEquals("$kind/$fromPhone", "sA", Repo.runningSid)
        }
        // Ούτε πριν κλείσει: μια έναρξη του ρολογιού δεν γίνεται ποτέ «όχι του κινητού».
        assertFalse(Repo.joinWhileRunning("walk", fromPhone = false, stopping = false))
        assertFalse(Repo.joinWhileRunning("strength", fromPhone = false, stopping = false))
        assertTrue(Repo.runningPhone)
        val r = Results.build(t0 + 300_000)!!
        assertEquals("hrsA-$t0", r.first)
        assertEquals("sA", r.second.getString("sid"))
        val log = r.second.getJSONArray("items").getJSONObject(0).getJSONArray("log")
        assertEquals(1, log.getJSONObject(1).getInt("d"))
        assertEquals(t0 + 120_000, log.getJSONObject(1).getLong("t"))
        assertEquals(110, r.second.getInt("hrAvg"))
    }

    /** Η περίπτωση για την οποία υπάρχει ο κλάδος: η προπόνηση του κινητού βρίσκει το ρολόι σε προπόνηση με βάρη. */
    @Test
    fun phoneWorkoutStillJoinsARunningStrengthWorkout() {
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sB", t0, set(10))))
        Repo.running = "strength"
        Repo.runningPhone = false
        assertTrue(Repo.joinWhileRunning("strength", fromPhone = true, stopping = false))
        assertTrue(Repo.runningPhone)
        assertEquals("sB", Repo.runningSid)
        // Περπάτημα: ποτέ (DP-10: θα τελείωνε μαζί με την προπόνηση του κινητού).
        Repo.resetExercise()
        Repo.running = "walk"
        assertFalse(Repo.joinWhileRunning("strength", fromPhone = true, stopping = false))
        assertFalse(Repo.runningPhone)
        assertNull(Repo.runningSid)
        // Ο κανόνας μόνος του.
        assertTrue(joinAllowedWhileRunning("strength", "strength", fromPhone = true, stopping = false))
        assertFalse(joinAllowedWhileRunning("strength", "strength", fromPhone = true, stopping = true))
        assertFalse(joinAllowedWhileRunning("strength", "walk", fromPhone = true, stopping = false))
        assertFalse(joinAllowedWhileRunning("strength", "strength", fromPhone = false, stopping = false))
        assertFalse(joinAllowedWhileRunning(null, "strength", fromPhone = true, stopping = false))
        // Η υπηρεσία και η οθόνη περνούν από εδώ: καμία έναρξη όσο τρέχει (ή κλείνει) κάτι.
        assertTrue(source("ExerciseService.kt").contains("Repo.joinWhileRunning(kind, phone, stopping)"))
        val act = source("WatchActivity.kt")
        assertEquals(3, Regex("if \\(busy\\(\\)\\) return@askOtherApp").findAll(act).count())
        assertEquals(3, Regex("\\n\\s+if \\(busy\\(\\)\\) return\\n").findAll(act).count())
    }

    // ------------------------------------------------------------------ R8-A8-2
    /** Στο αποτέλεσμα των παλμών: «c»: 1 μόνο στα ✓ που το κινητό είχε δει. */
    @Test
    fun confirmedTicksAreMarkedInTheHrResult() {
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", t0, set(10, done = true, at = t0 + 60_000), set(10), set(10))))
        runningPhone("sA")
        // Το 2ο σετ ✓ στο ρολόι (το κινητό δεν το είδε)· το 3ο δεν έγινε.
        Repo.phone!!.tick(t0 + 200_000)
        val r = Results.build(t0 + 300_000)!!
        val log = r.second.getJSONArray("items").getJSONObject(0).getJSONArray("log")
        assertEquals(1, log.getJSONObject(0).getInt("d"))
        assertEquals(1, log.getJSONObject(0).getInt("c"))
        assertEquals(1, log.getJSONObject(1).getInt("d"))
        assertFalse(log.getJSONObject(1).has("c"))
        assertFalse(log.getJSONObject(2).has("d"))
        assertFalse(log.getJSONObject(2).has("c"))
        // Το σενάριο: το ✓ του 1ου σετ βγήκε στο κινητό, αλλά το ρολόι δεν το έμαθε (Bluetooth) και το κινητό έκλεισε την
        // προπόνηση. Στο αποτέλεσμα πάει «d»: 1 ΜΑΖΙ με «c»: 1, ώστε το κινητό να μην το ξαναβάλει.
        Repo.applyPhone(null)
        val after = Results.build(t0 + 400_000)!!.second.getJSONArray("items").getJSONObject(0).getJSONArray("log")
        assertEquals(1, after.getJSONObject(0).getInt("c"))
        assertFalse(after.getJSONObject(1).has("c"))
        // Το κινητό είδε το ✓ του ρολογιού: από εκεί και πέρα «c» και σε αυτό.
        clean()
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", t0, set(10, done = true, at = t0 + 60_000), set(10, done = true, at = t0 + 200_000), set(10))))
        runningPhone("sA")
        val seen = Results.build(t0 + 300_000)!!.second.getJSONArray("items").getJSONObject(0).getJSONArray("log")
        assertEquals(1, seen.getJSONObject(1).getInt("c"))
        // Προπόνηση του ρολογιού: καμία αλλαγή (κανένα «c»).
        clean()
        val local = LiveSession(
            "w1", "A", "Α", t0,
            listOf(ItemT("db_press", "Πιεστικό", 90, 8, 12, 2, mutableListOf(SetT(10.3, "10,3 kg", 8), SetT(10.3, "10,3 kg", 8)))),
        )
        local.tick(t0 + 30_000)
        Repo.local = local
        Repo.running = "strength"
        Repo.startedAt = t0
        val own = Results.build(t0 + 60_000)!!.second.getJSONArray("items").getJSONObject(0).getJSONArray("log")
        assertEquals(1, own.getJSONObject(0).getInt("d"))
        assertFalse(own.getJSONObject(0).has("c"))
    }

    // ------------------------------------------------------------------ R8-A8-6
    /** Άνοιγμα από το κινητό: το «μπες» περιμένει την τωρινή κατάσταση και μια προπόνηση που ισχύει, και δεν σβήνει πριν. */
    @Test
    fun joinWaitsForTheCurrentPhoneWorkout() {
        val now = t0 + 10 * hour
        val stale = LiveSession.parsePhone(phoneJson("sX", now - 4 * hour, set(10)))!!
        val fresh = LiveSession.parsePhone(phoneJson("sY", now - 60_000, set(10)))!!
        assertFalse(joinNow(true, loaded = false, phone = fresh, now = now))
        assertFalse(joinNow(true, loaded = true, phone = stale, now = now))
        assertFalse(joinNow(true, loaded = true, phone = null, now = now))
        assertFalse(joinNow(false, loaded = true, phone = fresh, now = now))
        assertTrue(joinNow(true, loaded = true, phone = fresh, now = now))
        // Η ροή του redraw της οθόνης: πρώτα η παλιά (ξεχασμένη) προπόνηση στη μνήμη, μετά φτάνει η νέα.
        var flag = true
        val joined = mutableListOf<String>()
        fun redraw(loaded: Boolean, phone: LiveSession?) {
            flag = pendingJoin(flag, Repo.running, Repo.local != null)
            if (joinNow(flag, loaded, phone, now)) {
                flag = false
                joined.add(phone!!.id)
            }
        }
        redraw(loaded = false, phone = stale)
        redraw(loaded = true, phone = stale)
        assertTrue(flag)
        assertEquals(emptyList<String>(), joined)
        redraw(loaded = true, phone = fresh)
        assertFalse(flag)
        assertEquals(listOf("sY"), joined)
        // Μια προπόνηση που έκλεισε δεν μπαίνει ποτέ.
        val ended = LiveSession.parsePhone(phoneJson("sZ", now - 60_000, set(10)))!!
        ended.ended = true
        assertFalse(joinNow(true, loaded = true, phone = ended, now = now))
        // Η οθόνη: το «μπες» μόνο μετά την ανάγνωση στο άνοιγμα.
        val act = source("WatchActivity.kt")
        assertTrue(act.contains("if (joinNow(joinWhenReady, loaded, Repo.phone, System.currentTimeMillis())) {"))
        val loadAt = act.indexOf("            Link.load(this@WatchActivity)\n")
        val loadedAt = act.indexOf("            loaded = true\n")
        assertTrue("$loadAt / $loadedAt", loadAt in 1 until loadedAt)
        assertTrue(act.contains("        loaded = false\n"))
    }

    // ------------------------------------------------------------------ R8-A8-3 (αίτημα του f2)
    /** «Συνέχεια» στην «Ξεχασμένη προπόνηση;» του κινητού («res»): για το ρολόι η προπόνηση ισχύει ξανά από τότε. */
    @Test
    fun phoneResumeCountsAsActivity() {
        val resumed = LiveSession.parsePhone(JSONObject(phoneJson("sA", t0, set(10))).put("res", t0 + 4 * hour).toString())!!
        assertEquals(t0 + 4 * hour, resumed.res)
        assertEquals(t0 + 4 * hour, phoneLastActivity(resumed))
        assertFalse(phoneStale(resumed, t0 + 4 * hour + 60_000))
        assertTrue(phoneStale(resumed, t0 + 7 * hour))
        assertTrue(joinNow(true, loaded = true, phone = resumed, now = t0 + 4 * hour + 60_000))
        // Χωρίς «res» (παλιό κινητό, ή καμία «Συνέχεια»): όπως πριν, από την αρχή.
        val old = LiveSession.parsePhone(phoneJson("sB", t0, set(10)))!!
        assertEquals(0L, old.res)
        assertEquals(t0, phoneLastActivity(old))
        assertTrue(phoneStale(old, t0 + 4 * hour + 60_000))
        // Ένα ✓ μετά τη «Συνέχεια» μετρά από τη δική του ώρα· μια «Συνέχεια» πριν από το τελευταίο ✓ δεν το πάει πίσω.
        val later = LiveSession.parsePhone(JSONObject(phoneJson("sC", t0, set(10, done = true, at = t0 + 5 * hour))).put("res", t0 + 4 * hour).toString())!!
        assertEquals(t0 + 5 * hour, phoneLastActivity(later))
        // Κρατιέται και στο στιγμιότυπο της άσκησης (απότομο κλείσιμο της εφαρμογής του ρολογιού).
        assertEquals(t0 + 4 * hour, LiveSession.phoneFromWatchState(LiveSession.phoneWatchState(resumed))!!.res)
        assertFalse(LiveSession.phoneWatchState(old).has("res"))
        assertEquals(0L, LiveSession.phoneFromWatchState(LiveSession.phoneWatchState(old))!!.res)
    }

    // ------------------------------------------------------------------ R8-U3-01 (ρολόι)
    /** Η ίδια προπόνηση του κινητού με «f»: 1 στην άσκηση (εκκρεμεί η ερώτηση του 1ου σετ). */
    private fun withFirst(json: String): String =
        JSONObject(json).also { it.getJSONArray("items").getJSONObject(0).put("f", 1) }.toString()

    /** ✓ του 1ου σετ στο ρολόι, σε άσκηση με «f»: η ερώτηση ανοίγει· χωρίς «f», σε άλλο σετ ή χωρίς κινητό: όχι. */
    @Test
    fun firstSetQuestionOpensOnlyForTheFirstSetOfAFlaggedExercise() {
        Repo.applyPhone(LiveSession.parsePhone(withFirst(phoneJson("sA", t0, set(10), set(10), set(10)))))
        runningPhone("sA")
        val p = Repo.phone!!
        assertTrue(p.items[0].first)
        assertFalse(p.firstPending)
        // Το διάλειμμα ξεκινά όπως μετά από κάθε ✓.
        assertEquals(LiveSession.Next.REST, p.tick(t0 + 60_000))
        assertTrue(p.restEnd > t0 + 60_000)
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        assertEquals(0, p.firstIdx)
        assertTrue(p.firstPending)
        assertFalse(p.rirPending)
        // Το 2ο σετ: καμία ερώτηση· και η ίδια άσκηση δεν ξαναρωτιέται.
        assertFalse(p.askFirst(0, 1, LiveSession.Next.REST))
        assertFalse(p.askFirst(0, 0, LiveSession.Next.REST))
        // Χωρίς «f» (παλιό κινητό, ή όχι «πρώτη φορά»): όπως πριν.
        clean()
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sB", t0, set(10), set(10))))
        val plain = Repo.phone!!
        assertFalse(plain.items[0].first)
        assertEquals(LiveSession.Next.REST, plain.tick(t0 + 60_000))
        assertFalse(plain.askFirst(0, 0, LiveSession.Next.REST))
        assertEquals(-1, plain.firstIdx)
        // Τελευταίο σετ (ακολουθεί η ρεζέρβα της άσκησης): όχι η ερώτηση του 1ου σετ.
        assertFalse(LiveSession.parsePhone(withFirst(phoneJson("sC", t0, set(10))))!!.askFirst(0, 0, LiveSession.Next.ASK_RIR))
        // Προπόνηση του ρολογιού (χωρίς κινητό): ποτέ, ακόμα κι αν η άσκηση είχε «f».
        val own = LiveSession("w1", "A", "Α", t0, listOf(ItemT("db_press", "Π", 90, 8, 12, 2, mutableListOf(SetT(10.3, "10,3 kg", 8), SetT(10.3, "10,3 kg", 8)), first = true)))
        assertEquals(LiveSession.Next.REST, own.tick(t0 + 1_000))
        assertFalse(own.askFirst(0, 0, LiveSession.Next.REST))
        // Το «f» διαβάζεται και ως true.
        val asTrue = JSONObject(phoneJson("sD", t0, set(10), set(10))).also { it.getJSONArray("items").getJSONObject(0).put("f", true) }.toString()
        assertTrue(LiveSession.parsePhone(asTrue)!!.items[0].first)
        // Η οθόνη: ✓ → ερώτηση (ρεζέρβα με τίτλο «Πρώτο σετ»), η απάντηση → «rir1».
        val act = source("WatchActivity.kt")
        assertTrue(act.contains("val askFirst = si >= 0 && s.askFirst(i, si, next)"))
        assertTrue(act.contains("Repo.screen = if (askFirst) Repo.Screen.RIR else when (next) {"))
        assertTrue(act.contains("if (s.phone && item != null) cmd(rir1Cmd(fi, item.ex, item.sets.getOrNull(0)?.at ?: 0L, rir))"))
    }

    /** Η απάντηση: η εντολή «rir1» ακριβώς όπως τη δέχεται το κινητό (CROSS.md), και η ρεζέρβα της άσκησης δεν αλλάζει. */
    @Test
    fun firstSetAnswerSendsRir1() {
        val c = rir1Cmd(2, "db_press", t0 + 60_000, 3)
        assertEquals(setOf("op", "i", "s", "ex", "v", "at"), c.keys().asSequence().toSet())
        assertEquals("rir1", c.getString("op"))
        assertEquals(2, c.getInt("i"))
        assertEquals(0, c.getInt("s"))
        assertEquals("db_press", c.getString("ex"))
        assertEquals(3, c.getInt("v"))
        assertEquals(t0 + 60_000, c.getLong("at"))
        // «Δεν ξέρω» = −1· χωρίς ώρα ✓: χωρίς «at» (το κινητό κρίνει με το «τώρα»)· ποτέ πάνω από 4.
        val unknown = rir1Cmd(0, "db_row", 0L, -1)
        assertEquals(-1, unknown.getInt("v"))
        assertFalse(unknown.has("at"))
        assertEquals(4, rir1Cmd(0, "db_row", 0L, 7).getInt("v"))
        // Η ροή της οθόνης: η απάντηση κλείνει την ερώτηση και δίνει τη θέση της άσκησης.
        Repo.applyPhone(LiveSession.parsePhone(withFirst(phoneJson("sA", t0, set(10), set(10)))))
        runningPhone("sA")
        val p = Repo.phone!!
        p.tick(t0 + 60_000)
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        assertEquals(0, p.answerFirst())
        assertEquals(-1, p.firstIdx)
        assertFalse(p.firstPending)
        assertEquals(-1, p.answerFirst())
        assertNull(p.items[0].rir)
        assertFalse(p.rirPending)
        val sent = rir1Cmd(0, p.items[0].ex, p.items[0].sets[0].at, 2)
        assertEquals(t0 + 60_000, sent.getLong("at"))
        assertEquals("db_press", sent.getString("ex"))
    }

    /** Το κινητό απάντησε πρώτο (νέα κατάσταση χωρίς «f»): η ερώτηση κλείνει εδώ χωρίς αποστολή· με «f» ακόμα, μένει. */
    @Test
    fun firstSetQuestionClosesWhenThePhoneAnswered() {
        Repo.applyPhone(LiveSession.parsePhone(withFirst(phoneJson("sA", t0, set(10), set(10), set(10)))))
        runningPhone("sA")
        Repo.phone!!.tick(t0 + 60_000)
        assertTrue(Repo.phone!!.askFirst(0, 0, LiveSession.Next.REST))
        // Το κινητό είδε το ✓ αλλά δεν απαντήθηκε ακόμα: «f» ακόμα → η ερώτηση μένει ανοιχτή.
        Repo.applyPhone(LiveSession.parsePhone(withFirst(phoneJson("sA", t0, set(10, done = true, at = t0 + 60_000), set(10), set(10)))))
        assertTrue(Repo.phone!!.firstPending)
        assertEquals(0, Repo.phone!!.firstIdx)
        // Απαντήθηκε στο κινητό: χωρίς «f».
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", t0, set(10, done = true, at = t0 + 60_000), set(10), set(10))))
        val n = Repo.phone!!
        assertFalse(n.firstPending)
        assertEquals(-1, n.firstIdx)
        assertEquals(-1, n.answerFirst())
        assertTrue("db_press" in n.firstAsked)
        // Η οθόνη το κλείνει μόνη της (όπως τη ρεζέρβα που απαντήθηκε στο κινητό).
        assertTrue(source("WatchActivity.kt").contains("else if (s.phone && !s.rirPending && !s.firstPending) Repo.screen ="))
    }

    /** Ποτέ δεύτερη φορά: ούτε με νέο ✓ του 1ου σετ, ούτε μετά από απότομο κλείσιμο της εφαρμογής του ρολογιού. */
    @Test
    fun firstSetQuestionIsNeverAskedTwice() {
        val phone = withFirst(phoneJson("sA", t0, set(10), set(10), set(10)))
        Repo.applyPhone(LiveSession.parsePhone(phone))
        runningPhone("sA")
        val p = Repo.phone!!
        p.tick(t0 + 60_000)
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        assertEquals(0, p.answerFirst())
        // Το κινητό είδε το ✓, μετά το 1ο σετ βγήκε εκεί (χωρίς απάντηση, «f» ακόμα) και ξαναγίνεται ✓ στο ρολόι: καμία νέα ερώτηση.
        Repo.applyPhone(LiveSession.parsePhone(withFirst(phoneJson("sA", t0, set(10, done = true, at = t0 + 60_000), set(10), set(10)))))
        Repo.applyPhone(LiveSession.parsePhone(phone))
        val again = Repo.phone!!
        assertEquals(0, again.items[0].nextSet)
        assertEquals(LiveSession.Next.REST, again.tick(t0 + 120_000))
        assertFalse(again.askFirst(0, 0, LiveSession.Next.REST))
        // Στιγμιότυπο → απότομο κλείσιμο → συνέχεια: «fa» κρατά ότι ρωτήθηκε.
        val snap = Repo.captureRun(t0 + 130_000)!!
        assertEquals("[\"db_press\"]", snap.getJSONObject("pp").getJSONArray("fa").toString())
        val text = snap.toString()
        Repo.phone = null
        Repo.lastPhone = null
        Repo.resetExercise()
        Repo.applyPhone(LiveSession.parsePhone(phone))
        assertTrue(Repo.restoreRun(JSONObject(text), t0 + 140_000, 9_000_000))
        val back = Repo.phone!!
        assertTrue(back.firstAsked.toString(), "db_press" in back.firstAsked)
        assertFalse(back.firstPending)
        back.items[0].sets[0].done = false
        assertEquals(LiveSession.Next.REST, back.tick(t0 + 150_000))
        assertFalse(back.askFirst(0, 0, LiveSession.Next.REST))
        // Στιγμιότυπο χωρίς «fa» (έκδοση ως #105): τίποτα δεν αλλάζει.
        assertTrue(LiveSession.phoneFromWatchState(LiveSession.phoneWatchState(LiveSession.parsePhone(phone)!!))!!.firstAsked.isEmpty())
        assertFalse(LiveSession.phoneWatchState(LiveSession.parsePhone(phone)!!).has("fa"))
    }

    // ------------------------------------------------------------------ R8-U3-03
    /** Η υπενθύμιση «Τρέχει ακόμα η προπόνηση;» πάνω από την ερώτηση ρεζέρβας (εκεί δεν υπάρχει «Τέλος»). */
    @Test
    fun forgottenTextOnTheRirQuestionHasNoEndButton() {
        val idle = Forgotten.Why.STRENGTH_IDLE
        assertEquals("Τρέχει ακόμα η προπόνηση;\nΑν τελείωσες: κλείσε αυτό και πάτα «Τέλος».", Forgotten.screenText(idle))
        val ends = Forgotten.screenText(idle, onRir = true, rirEnds = true)
        assertEquals("Τρέχει ακόμα η προπόνηση;\nΑν τελείωσες: κλείσε αυτό και απάντησε στην ερώτηση.", ends)
        assertFalse(ends.contains("Τέλος"))
        assertEquals(
            "Τρέχει ακόμα η προπόνηση;\nΑν τελείωσες: κλείσε αυτό, απάντησε στην ερώτηση και πάτα «Τέλος».",
            Forgotten.screenText(idle, onRir = true, rirEnds = false),
        )
        // Το περπάτημα σε παύση δεν έχει ερώτηση ρεζέρβας: όπως πριν.
        assertEquals(Forgotten.screenText(Forgotten.Why.WALK_PAUSED), Forgotten.screenText(Forgotten.Why.WALK_PAUSED, onRir = true, rirEnds = true))
        for (why in Forgotten.Why.values()) for (onRir in listOf(false, true)) for (rirEnds in listOf(false, true)) {
            val t = Forgotten.screenText(why, onRir, rirEnds)
            assertTrue(t, t.startsWith(Forgotten.title(why) + "\n"))
            assertFalse(t, t.contains("στο ρολόι"))
        }
        // «Η απάντηση τελειώνει κιόλας την προπόνηση» = προπόνηση του ρολογιού με όλες τις ασκήσεις ✓ (ο κανόνας της
        // υπηρεσίας), όπως το answer() της οθόνης: END → τέλος.
        val one = LiveSession("w1", "A", "Α", t0, listOf(ItemT("db_press", "Πιεστικό", 90, 8, 12, 2, mutableListOf(SetT(10.3, "10,3 kg", 8)))))
        assertEquals(LiveSession.Next.ASK_RIR, one.tick(t0 + 1_000))
        assertTrue(!one.phone && one.allDone)
        assertEquals(LiveSession.Next.END, one.answer(2, t0 + 2_000).first)
        val two = LiveSession(
            "w2", "A", "Α", t0,
            listOf(
                ItemT("db_press", "Πιεστικό", 90, 8, 12, 2, mutableListOf(SetT(10.3, "10,3 kg", 8))),
                ItemT("db_row", "Κωπηλασία", 90, 8, 12, 2, mutableListOf(SetT(14.3, "14,3 kg", 10))),
            ),
        )
        assertEquals(LiveSession.Next.ASK_RIR, two.tick(t0 + 1_000))
        assertFalse(!two.phone && two.allDone)
        assertEquals(LiveSession.Next.REST, two.answer(2, t0 + 2_000).first)
        // Και η ειδοποίηση (εκεί με «στο ρολόι»).
        assertEquals("Αν τελείωσες, πάτα «Τέλος» στο ρολόι.", Forgotten.text(idle))
        assertEquals("Αν τελείωσες, απάντησε στην ερώτηση στο ρολόι.", Forgotten.text(idle, onRir = true, rirEnds = true))
        assertEquals("Αν τελείωσες, απάντησε στην ερώτηση και πάτα «Τέλος» στο ρολόι.", Forgotten.text(idle, onRir = true, rirEnds = false))
        assertEquals(Forgotten.text(Forgotten.Why.WALK_PAUSED), Forgotten.text(Forgotten.Why.WALK_PAUSED, onRir = true, rirEnds = false))
        val service = source("ExerciseService.kt")
        assertTrue(service.contains("val onRir = Repo.screen == Repo.Screen.RIR"))
        assertTrue(service.contains("val rirEnds = Repo.session?.let { !it.phone && it.allDone } == true"))
        assertTrue(service.contains("val text = Forgotten.text(why, onRir, rirEnds)"))
    }

    // ------------------------------------------------------------------ R8-U3-06
    @Test
    fun chosenWorkoutCountsOnlyOnItsDay() {
        val d = LocalDate.of(2026, 11, 20)
        assertEquals("LA", chosenToday("LA", d, d))
        assertNull(chosenToday("LA", d, d.plusDays(1)))
        assertNull(chosenToday("LA", d, d.minusDays(1)))
        assertNull(chosenToday("LA", null, d))
        assertNull(chosenToday(null, d, d))
        // Και μετά από μια έναρξη / το «ΟΚ» του τέλους η αρχική δείχνει πάλι τη σημερινή.
        assertEquals(2, Regex("view\\.chosen = null").findAll(source("WatchActivity.kt")).count())
    }

    // ------------------------------------------------------------------ R8-A12-3 (ρολόι)
    /** Πτώση παλμών στο 1′: «τουλάχιστον 5 τιμές» σε κάθε παράθυρο ([τέλος−10″, τέλος) και [τέλος+55″, τέλος+65″)). */
    @Test
    fun recoveryNeedsAtLeastFiveReadingsInEachWindow() {
        fun pts(vararg p: Pair<Int, Int>): List<IntArray> = p.map { intArrayOf(it.first, it.second) }
        val end = 100
        // Παράθυρο του τέλους γεμάτο (90″–99″): 150.
        val endFull = (90..99).map { it to 150 }.toTypedArray()
        // Στο 1′: 4 τιμές (155″–158″) και μία ακριβώς στα 65″ (εκτός) → καμία τιμή.
        assertNull(HrStats.recovery(pts(*endFull, 155 to 120, 156 to 121, 157 to 122, 158 to 123, 165 to 90), end))
        // 5 τιμές (155″–159″): 120, 121, 122, 123, 124 → μέσος 122.
        assertEquals(150 to 122, HrStats.recovery(pts(*endFull, 155 to 120, 156 to 121, 157 to 122, 158 to 123, 159 to 124), end))
        val oneFull = (155..164).map { it to 120 }.toTypedArray()
        // Στο τέλος: 4 τιμές (96″–99″) και μία ακριβώς στο «Τέλος» (εκτός) → καμία τιμή.
        assertNull(HrStats.recovery(pts(96 to 150, 97 to 151, 98 to 152, 99 to 153, 100 to 190, *oneFull), end))
        // 5 τιμές (95″–99″): 150…154 → μέσος 152.
        assertEquals(152 to 120, HrStats.recovery(pts(95 to 150, 96 to 151, 97 to 152, 98 to 153, 99 to 154, *oneFull), end))
        // Από την κανονική ροή (HrStats.add + «Τέλος»): 4 τιμές στο 1′ → τίποτα· με την 5η → τιμή.
        val hr = HrStats(0)
        for (t in 0..99) hr.add(150, t * 1000L)
        hr.markEnd(100_000)
        for (t in 155..158) hr.add(120, t * 1000L)
        assertNull(hr.recovery())
        hr.add(120, 159_000)
        assertEquals(150 to 120, hr.recovery())
    }
}

/**
 * Έλεγχος 14/11, round 8 (f3, ρολόι): οι οθόνες, ζωγραφισμένες από τον πραγματικό κώδικα (WatchView), όπως στο R7F3ViewTest.
 * Τα στιγμιότυπα γράφονται στο build/watch-shots/ (όνομα «R8_…»).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class R8F3ViewTest {
    private val size = 454
    private val u = size / 200f
    private val hour = 3_600_000L

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

    private fun buttons(v: WatchView): List<Pair<String, Rect>> {
        val p = v.accessibilityNodeProvider
        val out = mutableListOf<Pair<String, Rect>>()
        for ((i, item) in v.a11yItems.withIndex()) {
            if (!item.second) continue
            val r = Rect()
            @Suppress("DEPRECATION")
            p.createAccessibilityNodeInfo(i)!!.getBoundsInParent(r)
            out.add(item.first to r)
        }
        return out
    }

    private fun overlap(a: Rect, b: Rect): Boolean =
        minOf(a.right, b.right) - maxOf(a.left, b.left) > 1 && minOf(a.bottom, b.bottom) - maxOf(a.top, b.top) > 1

    private fun assertNoOverlaps(v: WatchView) {
        val all = buttons(v)
        for (i in all.indices) for (k in i + 1 until all.size) {
            assertFalse("${all[i]} / ${all[k]}", overlap(all[i].second, all[k].second))
        }
    }

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

    /**
     * Προπόνηση του κινητού που ξεκίνησε χθες στις 18:00 (στη ζώνη του ρολογιού) χωρίς κανένα ✓: ξεχασμένη, «από χθες»
     * (έτσι η 2η γραμμή είναι ίδια όποια ώρα κι αν τρέξει η δοκιμή).
     */
    private fun yesterdaysPhoneWorkout(): LiveSession {
        val start = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).minusHours(6).toInstant().toEpochMilli()
        return LiveSession.parsePhone(
            """{"active":true,"id":"s8","w":"A","name":"Προπόνηση Α","start":$start,"idx":0,
                "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"sets":[{"label":"10,3 kg","reps":8}]}]}""",
        )!!
    }

    // ------------------------------------------------------------------ R8-A8-4
    /** Μέρα χωρίς καμία προπόνηση με βάρη (π.χ. ελεύθερη χρήση) και ξεχασμένη προπόνηση στο κινητό: η σημείωση φαίνεται. */
    @Test
    fun forgottenPhoneWorkoutIsDrawnOnARestDay() {
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.applyPlan(Plan.parse("""{"v":1,"at":1,"workouts":[]}"""))
            Repo.screen = Repo.Screen.HOME
            Repo.applyPhone(yesterdaysPhoneWorkout())
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R8_W1i_home_rest_forgotten_phone" else "R8_W1j_home_rest_forgotten_phone_font13")
            val l = labels(v)
            assertTrue(l.toString(), l.first().startsWith("$STALE_PHONE_LINE1 από χθες· κλείσε την εκεί"))
            assertTrue(l.toString(), l.first().contains("Σήμερα ξεκούραση"))
            assertTrue(v.drawnSizes.toString(), STALE_PHONE_LINE1 in v.drawnSizes!! && "από χθες· κλείσε την εκεί" in v.drawnSizes!!)
            assertFalse(l.toString(), "Παλμοί εδώ" in l)
            assertTrue(l.toString(), "Περπάτημα" in l)
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            assertNoOverlaps(v)
            Repo.applyPhone(null)
            Repo.lastPhone = null
        }
    }

    /** Χωρίς πρόγραμμα στο ρολόι: η σημείωση στη θέση του «Άνοιξε την εφαρμογή στο κινητό». */
    @Test
    fun forgottenPhoneWorkoutIsDrawnWithoutAPlan() {
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.plan = null
            Repo.screen = Repo.Screen.HOME
            Repo.applyPhone(yesterdaysPhoneWorkout())
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R8_W1k_home_noplan_forgotten_phone" else null)
            val l = labels(v)
            assertTrue(l.toString(), l.first().startsWith("$STALE_PHONE_LINE1 από χθες"))
            assertFalse(l.toString(), l.first().contains("Άνοιξε την εφαρμογή"))
            assertTrue(v.drawnSizes.toString(), STALE_PHONE_LINE1 in v.drawnSizes!! && "από χθες· κλείσε την εκεί" in v.drawnSizes!!)
            assertFalse(v.drawnSizes.toString(), "Άνοιξε την εφαρμογή" in v.drawnSizes!!)
            assertTrue(l.toString(), "Περπάτημα" in l)
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            assertNoOverlaps(v)
            Repo.applyPhone(null)
            Repo.lastPhone = null
            // Χωρίς ξεχασμένη προπόνηση: όπως πριν.
            val plain = newView()
            draw(plain)
            assertTrue(labels(plain).toString(), labels(plain).first().contains("Άνοιξε την εφαρμογή στο κινητό"))
        }
    }

    // ------------------------------------------------------------------ R8-A8-1
    /** Η μέτρηση μιας προπόνησης του κινητού κλείνει ακόμα: καμία αρχική με κουμπιά έναρξης. */
    @Test
    fun closingWorkoutShowsNoStartButtons() {
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.applyPlan(Plan.parse(planJson))
            Repo.running = "strength"
            Repo.runningPhone = true
            Repo.runningSid = "sA"
            for (screen in listOf(Repo.Screen.SET, Repo.Screen.REST, Repo.Screen.HOME)) {
                Repo.screen = screen
                val v = newView()
                val bmp = draw(v, if (scale == 1f && screen == Repo.Screen.SET) "R8_W14_closing" else null)
                assertEquals("$scale× $screen", listOf("$CLOSING_TITLE. $CLOSING_SUB"), labels(v))
                assertTrue("$scale× $screen", buttons(v).isEmpty())
                assertTrue(v.clipped.toString(), v.clipped.isEmpty())
                assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            }
            // Τελείωσε: η κανονική αρχική.
            Repo.resetExercise()
            Repo.screen = Repo.Screen.HOME
            val home = newView()
            draw(home)
            assertTrue(labels(home).toString(), "Περπάτημα" in labels(home))
            // Περπάτημα: ο κανόνας δεν αφορά το περπάτημα (εκεί η δική του οθόνη, χωρίς κουμπιά έναρξης).
            Repo.running = "walk"
            val walk = newView()
            draw(walk)
            assertFalse(labels(walk).toString(), labels(walk).any { it.startsWith(CLOSING_TITLE) })
            Repo.resetExercise()
        }
    }

    // ------------------------------------------------------------------ R8-U3-06
    /** Η «άλλη προπόνηση» που διάλεξες χθες δεν μένει πρώτη σήμερα· σε μέρα περπατήματος πρώτο ξανά το περπάτημα. */
    @Test
    fun chosenWorkoutFromAnotherDayIsIgnored() {
        Repo.applyPlan(Plan.parse(planJson))
        Repo.screen = Repo.Screen.HOME
        val v = newView()
        v.chosen = "B"
        draw(v)
        assertTrue(buttons(v).toString(), buttons(v).first().first.startsWith("Προπόνηση Β, "))
        v.chosenDay = LocalDate.now().minusDays(1)
        draw(v)
        assertTrue(buttons(v).toString(), buttons(v).first().first.startsWith("Προπόνηση Α, "))
        // Μέρα περπατήματος: χθεσινή επιλογή → η αρχική του περπατήματος.
        Repo.applyPlan(Plan.parse(planJson.replace("\"today\":\"A\"", "\"today\":\"walk\"")))
        val w = newView()
        w.chosen = "A"
        draw(w)
        assertTrue(buttons(w).toString(), buttons(w).first().first.startsWith("Προπόνηση Α, "))
        w.chosenDay = LocalDate.now().minusDays(1)
        draw(w)
        assertTrue(buttons(w).toString(), buttons(w).first().first.startsWith("Περπάτημα, 30 λεπτά"))
        // Χωρίς επιλογή: καμία μέρα.
        w.chosen = null
        assertNull(w.chosenDay)
    }

    // ------------------------------------------------------------------ R8-U3-01 (ρολόι)
    /** «Πρώτο σετ: / πόσες ακόμα;» στην οθόνη της ρεζέρβας: ίδια κουμπιά (και «Δεν ξέρω»), ολόκληρο και με γράμματα 1,3×. */
    @Test
    fun firstSetQuestionScreen() {
        val now = System.currentTimeMillis()
        val did = mutableListOf<Int>()
        val acts = object : WatchView.Actions by noop {
            override fun answer(rir: Int) {
                did.add(rir)
            }
        }
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.applyPhone(
                LiveSession.parsePhone(
                    """{"active":true,"id":"s9","w":"A","name":"Προπόνηση Α","start":$now,"idx":0,
                        "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"f":1,"sets":[{"load":10.3,"label":"10,3 kg","reps":8},{"load":10.3,"label":"10,3 kg","reps":8}]}]}""",
                ),
            )
            Repo.running = "strength"
            Repo.runningPhone = true
            Repo.runningSid = "s9"
            Repo.startedAt = now - 60_000
            Repo.bpm = 118
            Repo.bpmAt = now
            val p = Repo.phone!!
            assertEquals(LiveSession.Next.REST, p.tick(now))
            assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
            Repo.screen = Repo.Screen.RIR
            val v = newView(acts)
            val bmp = draw(v, if (scale == 1f) "R8_W4d_first_set" else "R8_W4e_first_set_font13")
            assertEquals(FIRST_SET_SAY, labels(v).first())
            assertTrue(v.drawnSizes.toString(), FIRST_SET_LINE1 in v.drawnSizes!! && FIRST_SET_LINE2 in v.drawnSizes!!)
            assertFalse(v.drawnSizes.toString(), "Πόσες ακόμα" in v.drawnSizes!!)
            assertTrue(labels(v).toString(), RIR_UNKNOWN in labels(v))
            assertEquals(6, buttons(v).size)
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            assertNoOverlaps(v)
            assertTrue(v.a11yClick(labels(v).indexOf(RIR_UNKNOWN)))
            // Η κανονική ρεζέρβα (χωρίς ερώτηση 1ου σετ): ο παλιός τίτλος.
            p.answerFirst()
            val plain = newView(acts)
            draw(plain)
            assertTrue(plain.drawnSizes.toString(), "Πόσες ακόμα" in plain.drawnSizes!! && "θα έβγαζες;" in plain.drawnSizes!!)
            Repo.applyPhone(null)
            Repo.lastPhone = null
            Repo.resetExercise()
        }
        assertEquals(listOf(-1, -1), did)
    }

    // ------------------------------------------------------------------ R8-U3 Β2
    /** Λεπτό αποκατάστασης: η αντίστροφη μέτρηση όπως στο διάλειμμα («0:47»), όχι «47″». */
    @Test
    fun recoveryCountdownLooksLikeTheRest() {
        assertEquals("0:47", clock(47))
        assertEquals("1:05", clock(65))
        val now = System.currentTimeMillis()
        Repo.running = "walk"
        Repo.startedAt = now - 1471_000
        Repo.activeSec = 1471
        Repo.bpm = 118
        Repo.bpmAt = now
        Repo.endAt = now
        Repo.recoveryUntil = now + 47_000
        Repo.screen = Repo.Screen.RECOVER
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            val v = newView()
            draw(v, if (scale == 1f) "R8_W7c_recovery_clock" else null)
            val keys = v.drawnSizes!!.keys
            assertTrue(keys.toString(), keys.any { Regex("^0:4[5-7]$").matches(it) })
            assertFalse(keys.toString(), keys.any { it.contains("″") })
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue(labels(v).toString(), "Παράλειψη της αποκατάστασης" in labels(v))
        }
    }

    // ------------------------------------------------------------------ R8-U3-03
    /** Η υπενθύμιση πάνω από την ερώτηση ρεζέρβας: ολόκληρη, χωρίς «πάτα «Τέλος»» όταν η απάντηση κλείνει την προπόνηση. */
    @Test
    fun forgottenReminderOverTheRirQuestion() {
        val now = System.currentTimeMillis()
        Repo.applyPlan(Plan.parse(planJson))
        Repo.running = "strength"
        Repo.startedAt = now - 4 * hour
        Repo.bpm = 118
        Repo.bpmAt = now
        for (ends in listOf(true, false)) {
            val text = Forgotten.screenText(Forgotten.Why.STRENGTH_IDLE, onRir = true, rirEnds = ends)
            for (scale in listOf(1f, 1.3f)) {
                RuntimeEnvironment.setFontScale(scale)
                Repo.local = LiveSession.fromPlan(Repo.plan!!.workout("B")!!, now - 4 * hour)
                Repo.screen = Repo.Screen.RIR
                Repo.notice = text
                val v = newView()
                val bmp = draw(v, if (scale == 1f && ends) "R8_W4c_rir_forgotten" else null)
                assertEquals(listOf(text, "Κλείσιμο"), labels(v))
                assertTrue(v.clipped.toString(), v.clipped.isEmpty())
                assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
                // Κλείνει: από κάτω η ερώτηση με τις απαντήσεις.
                assertTrue(v.a11yClick(1))
                draw(v)
                assertTrue(labels(v).toString(), RIR_UNKNOWN in labels(v))
            }
        }
    }
}
