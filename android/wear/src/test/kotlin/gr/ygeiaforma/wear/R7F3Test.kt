package gr.ygeiaforma.wear

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
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
import java.time.ZonedDateTime

/**
 * Έλεγχος 13/11, round 7 (f3, ρολόι): οι καθαροί κανόνες. Κάθε δοκιμή αποτυγχάνει χωρίς τη διόρθωσή της· οι τιμές που
 * περιμένουμε βγαίνουν από τον γραμμένο κανόνα, όχι από τον κώδικα. Όλα τα νούμερα είναι δοκιμαστικά.
 */
class R7F3Test {
    private val t0 = 1_700_000_000_000L
    private val none = ZoneAlarm.Buzz.NONE
    private val up = ZoneAlarm.Buzz.UP

    private fun source(name: String): String = File("src/main/kotlin/gr/ygeiaforma/wear/$name").readText()

    private fun set(reps: Int, done: Boolean = false, at: Long = 0) =
        JSONObject().put("label", "10,3 kg").put("load", 10.3).put("reps", reps).also { if (done) it.put("done", true).put("at", at) }

    /** Η προπόνηση του κινητού ([Paths.SESSION]) με μία άσκηση. */
    private fun phoneJson(id: String, vararg sets: JSONObject): String =
        JSONObject().put("v", 1).put("active", true).put("id", id).put("w", "A").put("name", "Α").put("start", t0)
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

    /** «Παλμοί εδώ» στην προπόνηση [id] του κινητού, από τις [t0]. */
    private fun runningPhone(id: String) {
        Repo.running = "strength"
        Repo.runningPhone = true
        Repo.runningSid = id
        Repo.startedAt = t0
        Repo.hr = HrStats(t0)
    }

    // ------------------------------------------------------------------ R7-A8-1
    /** ✓, επαναλήψεις και ρεζέρβα του ρολογιού που το κινητό δεν είδε: μένουν μετά από απότομο κλείσιμο της εφαρμογής. */
    @Test
    fun phonePendingTicksSurviveProcessDeath() {
        val phone = phoneJson("sA", set(10, done = true, at = t0 + 60_000), set(10), set(10))
        Repo.applyPhone(LiveSession.parsePhone(phone))
        runningPhone("sA")
        val p = Repo.phone!!
        // Στο ρολόι: ✓ του 2ου σετ, 7 αντί για 10 στο 3ο, ✓ του 3ου και ρεζέρβα 2. Το κινητό (κλειστή εφαρμογή) δεν τα είδε.
        assertEquals(LiveSession.Next.REST, p.tick(t0 + 200_000))
        p.items[0].sets[2].edit(7)
        assertEquals(LiveSession.Next.ASK_RIR, p.tick(t0 + 400_000))
        assertEquals(0, p.answer(2, t0 + 410_000).second)
        assertEquals(listOf(0 to 1, 0 to 2), Repo.pendingTicks)
        val snap = Repo.captureRun(t0 + 420_000)!!
        assertTrue(snap.has("pp"))
        assertEquals(1, snap.getInt("v"))
        val text = snap.toString()
        // Η εφαρμογή του ρολογιού κλείνει απότομα: η μνήμη χάνεται.
        Repo.phone = null
        Repo.lastPhone = null
        Repo.resetExercise()
        // Νέο άνοιγμα: πρώτα η κατάσταση του κινητού (ακόμα ένα σετ), μετά το στιγμιότυπο.
        Repo.applyPhone(LiveSession.parsePhone(phone))
        assertTrue(Repo.pendingTicks.isEmpty())
        assertTrue(Repo.restoreRun(JSONObject(text), t0 + 600_000, 9_000_000))
        // Τα ✓ του ρολογιού εκκρεμούν ξανά (ξαναστέλνονται), με την ώρα τους, τις επαναλήψεις και τη ρεζέρβα του ρολογιού.
        assertEquals(listOf(0 to 1, 0 to 2), Repo.pendingTicks)
        val item = Repo.phone!!.items[0]
        assertEquals(t0 + 200_000, item.sets[1].at)
        assertEquals(t0 + 400_000, item.sets[2].at)
        assertEquals(7, item.sets[2].reps)
        assertEquals(setOf(10), item.sets[2].trail)
        assertEquals(2, item.rir)
        // Και πάνε στο αποτέλεσμα των παλμών (μερικό, όπως γράφεται όταν η άσκηση δεν συνεχίζει).
        val r = Results.build(t0 + 600_000, partialAt = snap.getLong("saved"))!!
        assertEquals("hrsA-$t0", r.first)
        val out = r.second.getJSONArray("items").getJSONObject(0)
        val log = out.getJSONArray("log")
        assertEquals(1, log.getJSONObject(1).getInt("d"))
        assertEquals(t0 + 200_000, log.getJSONObject(1).getLong("t"))
        assertEquals(1, log.getJSONObject(2).getInt("d"))
        assertEquals(7, log.getJSONObject(2).getInt("r"))
        assertEquals(2, out.getInt("ra"))
    }

    /** Το ίδιο όταν το κινητό, στο μεταξύ, έκλεισε την προπόνηση ή ξεκίνησε άλλη: τα ✓ του ρολογιού πάνε στο αποτέλεσμα. */
    @Test
    fun phoneTicksReachTheResultAfterARestartEvenIfThePhoneMovedOn() {
        for (next in listOf<String?>(null, "sB")) {
            clean()
            Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", set(10, done = true, at = t0 + 60_000), set(10))))
            runningPhone("sA")
            Repo.phone!!.tick(t0 + 200_000)
            val text = Repo.captureRun(t0 + 210_000)!!.toString()
            Repo.phone = null
            Repo.lastPhone = null
            Repo.resetExercise()
            Repo.applyPhone(if (next == null) null else LiveSession.parsePhone(phoneJson(next, set(8))))
            assertTrue(Repo.restoreRun(JSONObject(text), t0 + 600_000, 9_000_000))
            val r = Results.build(t0 + 600_000, partialAt = t0 + 210_000)!!
            assertEquals("$next", "sA", r.second.getString("sid"))
            val log = r.second.getJSONArray("items").getJSONObject(0).getJSONArray("log")
            assertEquals("$next", 1, log.getJSONObject(1).getInt("d"))
            assertEquals("$next", t0 + 200_000, log.getJSONObject(1).getLong("t"))
            // Η νέα προπόνηση του κινητού δεν παίρνει ✓ από την παλιά.
            if (next != null) assertTrue(Repo.pendingTicks.isEmpty())
        }
    }

    /** Στιγμιότυπο χωρίς «pp» (έκδοση ως #104) ή με «pp» άλλης προπόνησης: διαβάζεται όπως πριν, τίποτα δεν μπαίνει. */
    @Test
    fun snapshotWithoutOrWithForeignPhoneStateStillRestores() {
        val old = JSONObject().put("v", 1).put("kind", "strength").put("phone", true).put("start", t0).put("saved", t0 + 1_000).put("sid", "sA")
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", set(10), set(10))))
        assertTrue(Repo.restoreRun(old, t0 + 5_000, 9_000_000))
        assertTrue(Repo.pendingTicks.isEmpty())
        val other = LiveSession.parsePhone(phoneJson("sZ", set(10, done = true, at = t0 + 1)))!!
        other.items[0].sets[0].confirmed = false
        old.put("pp", LiveSession.phoneWatchState(other))
        assertTrue(Repo.restoreRun(old, t0 + 5_000, 9_000_000))
        assertTrue(Repo.pendingTicks.isEmpty())
        // Η μορφή: «c» μόνο για ✓ που το κινητό είχε δει, «rb» μόνο με διόρθωση που εκκρεμεί.
        val s = LiveSession.parsePhone(phoneJson("sA", set(10, done = true, at = t0 + 1), set(10)))!!
        s.items[0].sets[0].confirmed = true
        s.items[0].sets[1].edit(9)
        val sets = LiveSession.phoneWatchState(s).getJSONArray("items").getJSONObject(0).getJSONArray("sets")
        assertEquals(1, sets.getJSONObject(0).getInt("c"))
        assertFalse(sets.getJSONObject(0).has("rb"))
        assertFalse(sets.getJSONObject(1).has("c"))
        assertEquals(10, sets.getJSONObject(1).getJSONArray("rb").getInt(0))
        val back = LiveSession.phoneFromWatchState(LiveSession.phoneWatchState(s))!!
        assertTrue(back.phone)
        assertTrue(back.items[0].sets[0].confirmed)
        assertEquals(setOf(10), back.items[0].sets[1].trail)
        assertNull(LiveSession.phoneFromWatchState(JSONObject().put("x", 1)))
    }

    /** Η οθόνη γράφει στιγμιότυπο σε κάθε ✓, ρεζέρβα και διόρθωση και στην προπόνηση του κινητού. */
    @Test
    fun watchActivitySnapshotsPhoneWorkoutsToo() {
        val act = source("WatchActivity.kt")
        assertFalse(act.contains("if (!s.phone) saveRun()"))
        assertFalse(Regex("else saveRun\\(\\)").containsMatchIn(act))
        assertTrue(source("Repo.kt").contains("if (runningPhone) phoneById(runningSid)?.let { o.put(\"pp\", LiveSession.phoneWatchState(it)) }"))
    }

    // ------------------------------------------------------------------ R7-A8-2
    /** Το κινητό τελειώνει την Α και ξεκινά τη Β πριν το δει το ρολόι: τα ✓ του ρολογιού στην Α δεν χάνονται. */
    @Test
    fun endedPhoneWorkoutKeepsWatchTicksWhenNextStarts() {
        for (endedFirst in listOf(false, true)) {
            clean()
            Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", set(10, done = true, at = t0 + 60_000), set(10), set(10))))
            runningPhone("sA")
            Repo.phone!!.tick(t0 + 200_000)
            assertEquals(listOf(0 to 1), Repo.pendingTicks)
            if (endedFirst) Repo.applyPhone(null)
            Repo.applyPhone(LiveSession.parsePhone(phoneJson("sB", set(8))))
            val r = Results.build(t0 + 300_000)!!
            assertEquals("$endedFirst", "hrsA-$t0", r.first)
            assertEquals("$endedFirst", "sA", r.second.getString("sid"))
            val log = r.second.getJSONArray("items").getJSONObject(0).getJSONArray("log")
            assertEquals("$endedFirst", 3, log.length())
            assertEquals("$endedFirst", 1, log.getJSONObject(1).getInt("d"))
            assertEquals("$endedFirst", t0 + 200_000, log.getJSONObject(1).getLong("t"))
            // Μια τρίτη (Γ) δεν διώχνει την Α όσο μετράει ακόμα.
            Repo.applyPhone(LiveSession.parsePhone(phoneJson("sC", set(8))))
            assertEquals("sA", Repo.endedPhone!!.id)
            assertEquals("sA", Repo.phoneById("sA")!!.id)
        }
        // Χωρίς άσκηση που μετράει: κρατιέται απλώς η προηγούμενη.
        clean()
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("s1", set(8))))
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("s2", set(8))))
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("s3", set(8))))
        assertEquals("s2", Repo.endedPhone!!.id)
        // «Ξέχνα την τελευταία» ξεχνά και την προηγούμενη.
        Repo.lastPhone = null
        assertNull(Repo.endedPhone)
    }

    // ------------------------------------------------------------------ R7-A8-3 (αίτημα του f2)
    /** Ξεχασμένη προπόνηση του κινητού: τελευταία κίνηση (✓ με ώρα, αλλιώς η αρχή) πριν από 3 ώρες και πάνω. */
    @Test
    fun forgottenPhoneWorkoutIsRecognised() {
        val hour = 3_600_000L
        val s = LiveSession.parsePhone(phoneJson("sA", set(10, done = true, at = t0 + hour), set(10)))!!
        assertEquals(t0 + hour, phoneLastActivity(s))
        assertFalse(phoneStale(s, t0 + 4 * hour - 1))
        assertTrue(phoneStale(s, t0 + 4 * hour))
        // Χωρίς ✓ με ώρα: από την αρχή.
        val fresh = LiveSession.parsePhone(phoneJson("sB", set(10)))!!
        assertEquals(t0, phoneLastActivity(fresh))
        assertFalse(phoneStale(fresh, t0 + 3 * hour - 1))
        assertTrue(phoneStale(fresh, t0 + 3 * hour))
        assertEquals(Forgotten.LONG_MS, 3 * hour)
        // «από πότε», στη ζώνη του ρολογιού.
        val athens = ZoneId.of("Europe/Athens")
        fun at(d: Int, h: Int, m: Int) = ZonedDateTime.of(2026, 11, d, h, m, 0, 0, athens).toInstant().toEpochMilli()
        assertEquals("από τις 14:05", staleSinceText(at(17, 14, 5), at(17, 18, 0), athens))
        assertEquals("από χθες", staleSinceText(at(16, 17, 0), at(17, 9, 0), athens))
        assertEquals("από Δευτέρα", staleSinceText(at(16, 17, 0), at(19, 9, 0), athens))
        assertEquals("από 9/11", staleSinceText(at(9, 17, 0), at(17, 9, 0), athens))
        // Το κινητό δεν προτείνεται σε ξεχασμένη (ούτε με άνοιγμα από το κινητό).
        assertTrue(source("WatchActivity.kt").contains("if (phoneStale(p0, System.currentTimeMillis())) return"))
    }

    // ------------------------------------------------------------------ R7-A6-6 (αίτημα του f2)
    /** Πριν από την έναρξη του προγράμματος καμία «σημερινή» προπόνηση, όπως στο κινητό. */
    @Test
    fun noWorkoutBeforeTheProgrammeStarts() {
        val plan = Plan.parse(
            """{"v":1,"at":1,"from":"2026-11-16","days":{"6":"LB","1":"walk"},
               "workouts":[{"id":"LB","name":"Κάτω μέρος 2","minutes":50,"items":[{"ex":"rdl","name":"R","sets":[{"label":"","reps":8}]}]},
                 {"id":"walk","name":"Περπάτημα","minutes":30,"cardio":{"activity":"walk","name":"Περπάτημα","minutes":30}}]}""",
        )!!
        assertNull(plan.forDay(LocalDate.of(2026, 11, 14)))
        assertEquals("LB", plan.forDay(LocalDate.of(2026, 11, 21))!!.id)
        assertEquals("walk", plan.forDay(LocalDate.of(2026, 11, 16))!!.id)
        assertNull(plan.forDay(LocalDate.of(2026, 11, 9)))
        // Το περπάτημα που έγινε πριν από την έναρξη δεν παίρνει το όνομα του προγράμματος.
        val athens = ZoneId.of("Europe/Athens")
        assertNull(plan.walkOn(ZonedDateTime.of(2026, 11, 9, 10, 0, 0, 0, athens).toInstant().toEpochMilli(), athens))
        assertEquals("walk", plan.walkOn(ZonedDateTime.of(2026, 11, 23, 10, 0, 0, 0, athens).toInstant().toEpochMilli(), athens)!!.id)
        // Παλιό κινητό (χωρίς «from»): όπως πριν.
        val old = Plan.parse("""{"v":1,"at":1,"days":{"6":"LB"},"workouts":[{"id":"LB","name":"Κ","minutes":50,"items":[]}]}""")!!
        assertEquals("LB", old.forDay(LocalDate.of(2026, 11, 14))!!.id)
    }

    // ------------------------------------------------------------------ R7-A8-5
    @Test
    fun endScreenSaysSavedOnlyWhenTheResultWasWritten() {
        assertFalse(endScreenSaved(saved = false, put = false))
        assertTrue(endScreenSaved(saved = true, put = false))
        assertTrue(endScreenSaved(saved = false, put = true))
        assertTrue(endScreenSaved(saved = true, put = true))
        val service = source("ExerciseService.kt")
        assertTrue(service.contains("if (!endScreenSaved(saved, put)) {"))
        assertTrue(service.contains("Repo.unsaved[result.first] = result.second"))
        assertTrue(service.contains("Repo.endUnsaved = unsaved"))
        // Στο άνοιγμα: πρώτα όσα δεν γράφτηκαν, μετά η ανάκτηση του στιγμιότυπου (που αλλιώς θα έστελνε μερικό).
        val act = source("WatchActivity.kt")
        val retry = act.indexOf("                retryUnsaved()\n")
        val recover = act.indexOf("                recoverIfNeeded()\n")
        assertTrue("$retry / $recover", retry in 1 until recover)
    }

    // ------------------------------------------------------------------ R7-A8-6
    /** Περπάτημα που ξεκίνησε Κυριακή και γράφεται Δευτέρα: το όνομα/id της Κυριακής. */
    @Test
    fun walkNameComesFromTheDayItStarted() {
        val plan = Plan.parse(
            """{"v":1,"at":1,"days":{"7":"C","1":"A"},
               "workouts":[{"id":"A","name":"Προπόνηση Α","minutes":50,"items":[{"ex":"db_press","name":"Π","sets":[{"label":"","reps":8}]}]},
                 {"id":"C","name":"Περπάτημα ζώνης 2","minutes":40,"cardio":{"activity":"walk","name":"Περπάτημα ζώνης 2","minutes":40}}]}""",
        )!!
        val athens = ZoneId.of("Europe/Athens")
        // Κυριακή 22/11/2026 23:45 → το περπάτημα της Κυριακής· Δευτέρα 00:30 → καμία αερόβια (βάρη).
        val sun = ZonedDateTime.of(2026, 11, 22, 23, 45, 0, 0, athens).toInstant().toEpochMilli()
        val mon = ZonedDateTime.of(2026, 11, 23, 0, 30, 0, 0, athens).toInstant().toEpochMilli()
        assertEquals("C", plan.walkOn(sun, athens)!!.id)
        assertNull(plan.walkOn(mon, athens))
        assertEquals(LocalDate.of(2026, 11, 22), plan.dayOf(sun, athens))
        assertEquals(LocalDate.of(2026, 11, 23), plan.dayOf(mon, athens))
        // Το αποτέλεσμα: αρχή Κυριακή 12:00 UTC (Κυριακή σε κάθε ζώνη από −11 ως +11), γράφεται 24 ώρες μετά.
        Repo.plan = plan
        Repo.running = "walk"
        Repo.startedAt = ZonedDateTime.of(2026, 11, 22, 12, 0, 0, 0, ZoneId.of("UTC")).toInstant().toEpochMilli()
        Repo.hr = HrStats(Repo.startedAt)
        val r = Results.build(Repo.startedAt + 24 * 3_600_000L)!!.second
        assertEquals("C", r.getString("w"))
        assertEquals("Περπάτημα ζώνης 2", r.getString("name"))
        assertTrue(source("ExerciseService.kt").contains("val c = p.walkOn(Repo.startedAt)?.cardio ?: return 0"))
    }

    // ------------------------------------------------------------------ R7-A7-1
    @Test
    fun doNotDisturbAlsoMutesTheZoneBuzzAndSaysSo() {
        assertFalse(zoneBuzzFelt(powerSave = false, ringerSilent = false, dnd = true))
        assertTrue(zoneBuzzFelt(powerSave = false, ringerSilent = false, dnd = false))
        assertTrue(zoneMutedNow(zoneActive = true, hasDoctorLimit = false, powerSave = false, ringerSilent = false, dnd = true))
        // Με όριο γιατρού η ζώνη δεν μιλά έτσι κι αλλιώς· χωρίς ζώνη τίποτα.
        assertFalse(zoneMutedNow(zoneActive = true, hasDoctorLimit = true, powerSave = false, ringerSilent = false, dnd = true))
        assertFalse(zoneMutedNow(zoneActive = false, hasDoctorLimit = false, powerSave = false, ringerSilent = false, dnd = true))
        assertEquals("Μην ενοχλείτε: χωρίς δόνηση ζώνης", zoneMutedNotice(powerSave = false, ringerSilent = false, dnd = true))
        // Στη «Μόνο ξυπνητήρια» το Android βάζει και τον ήχο σε σίγαση: η αιτία που λέμε είναι το «Μην ενοχλείτε».
        assertEquals("Μην ενοχλείτε: χωρίς δόνηση ζώνης", zoneMutedNotice(powerSave = true, ringerSilent = true, dnd = true))
        assertEquals("Σίγαση: χωρίς δόνηση ζώνης", zoneMutedNotice(powerSave = false, ringerSilent = true))
        assertFalse(isBriefNotice(zoneMutedNotice(powerSave = false, ringerSilent = false, dnd = true)))
        val service = source("ExerciseService.kt")
        assertTrue(service.contains("getSystemService(NotificationManager::class.java)?.currentInterruptionFilter"))
        for (f in listOf("INTERRUPTION_FILTER_PRIORITY", "INTERRUPTION_FILTER_ALARMS", "INTERRUPTION_FILTER_NONE")) {
            assertTrue(f, service.contains("NotificationManager.$f"))
        }
        assertTrue(service.contains("zoneMutedNow(Repo.zoneAlarm.active, Repo.alarm.limit != null, powerSave, silent, dnd)"))
        // Απόφαση: η δόνηση ζώνης μένει δόνηση ειδοποίησης (απαλή), μόνο ανιχνεύεται.
        assertTrue(service.contains("vibrate(if (b == ZoneAlarm.Buzz.UP) longArrayOf(0, 110, 120, 110) else longArrayOf(0, 260), alarm = false)"))
    }

    // ------------------------------------------------------------------ R7-A7-2
    @Test
    fun gapCountsOnlyDeliveriesWithUsableValues() {
        assertTrue(hrValueUsable(HrQuality.OK, 118))
        assertTrue(hrValueUsable(HrQuality.LOW, 26))
        assertTrue(hrValueUsable(HrQuality.OK, 249))
        assertFalse(hrValueUsable(HrQuality.BAD, 118))
        assertFalse(hrValueUsable(HrQuality.OK, 0))
        assertFalse(hrValueUsable(HrQuality.OK, 25))
        assertFalse(hrValueUsable(HrQuality.OK, 250))
        // Περπάτημα, παράδοση ανά 5″· από τα 20″ ως τα 140″ μόνο «χωρίς επαφή» (το λουρί χαλάρωσε 2 λεπτά).
        val g = GapMeter()
        g.start(0)
        for (t in 0..200 step 5) {
            val lost = t in 20 until 140
            if (hrValueUsable(if (lost) HrQuality.BAD else HrQuality.OK, if (lost) 0 else 118)) g.mark(t * 1000L)
        }
        g.close(200_000)
        // Τελευταία καλή τιμή στα 15″, επόμενη στα 140″: 125″ (πριν από τη διόρθωση: 5″, «έφταναν κάθε λίγα δευτερόλεπτα»).
        assertEquals(125, g.maxGapSec)
        val service = source("ExerciseService.kt")
        assertTrue(service.contains("if (!hrValueUsable(quality, bpm)) continue"))
        assertTrue(service.contains("if (usable > 0) Repo.hrGaps.mark(now)"))
        assertFalse(service.contains("if (points.isNotEmpty()) Repo.hrGaps.mark(now)"))
    }

    // ------------------------------------------------------------------ R7-A7-3
    @Test
    fun warmupCountsFromTheStartOfTheWalkAfterARestart() {
        val nowEl = 5_000_000L
        val nowWall = t0 + 20 * 60_000L
        assertEquals(nowEl - 20 * 60_000L, zoneWarmupStartEl(nowEl, nowWall, t0))
        // Η ώρα του ρολογιού πήγε πίσω (αρχή «στο μέλλον»): από τη συνέχεια, ποτέ πιο πέρα.
        assertEquals(nowEl, zoneWarmupStartEl(nowEl, t0 - 1_000, t0))
        // Ζώνη 107–130, 20′ μετά την αρχή, παλμοί 140 από τη συνέχεια: δόνηση στα 20″ (όχι 5′ μετά).
        val z = ZoneAlarm(holdMs = 20_000L)
        z.start(WalkZone(107, 130), zoneWarmupStartEl(nowEl, nowWall, t0))
        for (k in 0..19) assertEquals("$k″", none, z.feed(140, nowEl + k * 1000L))
        assertEquals(up, z.feed(140, nowEl + 20_000))
        // Με αρχή τη στιγμή της συνέχειας (πριν από τη διόρθωση): τίποτα για 5′.
        val before = ZoneAlarm(holdMs = 20_000L)
        before.start(WalkZone(107, 130), nowEl)
        assertEquals(none, before.feed(140, nowEl))
        assertEquals(none, before.feed(140, nowEl + 20_000))
        val service = source("ExerciseService.kt")
        assertTrue(service.contains("originEl = zoneWarmupStartEl(Repo.startedEl, now, Repo.startedAt)"))
        assertEquals(2, Regex("Repo\\.zoneAlarm\\.start\\(if \\(walk\\) Repo\\.zoneNow\\(\\) else null, originEl\\)").findAll(service).count())
        assertTrue(service.contains("Forgotten.why(kind, originEl, lastActionEl,"))
    }

    // ------------------------------------------------------------------ R7-A12-8
    /** Παλιότερη τιμή από την άλλη πηγή, ΜΕΣΑ στη ζώνη: αγνοείται (δεν μηδενίζει τα 20″ πάνω). */
    @Test
    fun zoneAlarmIgnoresAnOlderValueFromTheOtherSource() {
        val z = ZoneAlarm(holdMs = 20_000L)
        z.start(WalkZone(108, 131), 0)
        assertEquals(none, z.feed(140, 400_000))
        assertEquals(none, z.feed(140, 415_000))
        assertEquals(none, z.feed(125, 405_000))
        assertEquals(up, z.feed(140, 421_000))
        // «Σταθεροί» παλμοί με χρόνο πριν από την τελευταία τιμή: τίποτα.
        assertEquals(none, z.steady(140, 420_000))
    }

    /** Οι επαναλήψεις ακριβώς στα όριά τους: πάνω ανά 2′, κάτω (ανοιχτή) ανά 5′. */
    @Test
    fun zoneAlarmRepeatsExactlyOnTheirIntervals() {
        val s = 400_000L
        val z = ZoneAlarm(holdMs = 20_000L)
        z.start(WalkZone(108, 131), 0)
        for (k in 0..19) assertEquals("$k″", none, z.feed(140, s + k * 1000L))
        assertEquals(up, z.feed(140, s + 20_000))
        for (k in 21..139) assertEquals("$k″", none, z.feed(140, s + k * 1000L))
        assertEquals(up, z.feed(140, s + 140_000))
        val d = ZoneAlarm(holdMs = 20_000L)
        d.start(WalkZone(108, 131, up = true, down = true), 0)
        assertEquals(none, d.feed(100, s))
        assertEquals(none, d.feed(100, s + 50_000))
        assertEquals(ZoneAlarm.Buzz.DOWN, d.feed(100, s + 61_000))
        assertEquals(none, d.feed(100, s + 360_000))
        assertEquals(ZoneAlarm.Buzz.DOWN, d.feed(100, s + 361_000))
        assertEquals(2, d.downs)
    }

    // ------------------------------------------------------------------ R7-U3-01
    @Test
    fun finishNoticesStartWithTheInstruction() {
        for (phone in listOf(true, false)) for (sets in listOf(0, 2)) for (hr in listOf(true, false)) {
            val n = finishNotice(phone, sets, hr)
            assertTrue(n, n.startsWith("Πάτα ξανά"))
            assertTrue(n, isBriefNotice(n))
        }
        assertEquals("Πάτα ξανά: στο κινητό μένουν μόνο οι παλμοί", finishNotice(true, 0, true))
        assertEquals("Πάτα ξανά: δεν μένει τίποτα", finishNotice(true, 0, false))
        assertEquals("Πάτα ξανά όσο περπατάς", WALK_FINISH_NOTICE)
        assertTrue(isBriefNotice(WALK_FINISH_NOTICE))
    }

    // ------------------------------------------------------------------ R7-U3-04
    @Test
    fun rirUnknownLeavesNoAnswer() {
        fun session() = LiveSession(
            "w1", "A", "Α", t0,
            listOf(ItemT("db_press", "Πιεστικό", 90, 8, 12, 3, mutableListOf(SetT(10.3, "10,3 kg", 8)))),
        )
        val s = session()
        assertEquals(LiveSession.Next.ASK_RIR, s.tick(t0 + 1_000))
        assertTrue(s.rirPending)
        assertEquals(LiveSession.Next.END to 0, s.answer(-1, t0 + 2_000))
        assertNull(s.items[0].rir)
        assertFalse(s.rirPending)
        assertFalse(s.resultJson(t0 + 3_000, HrStats(t0)).getJSONArray("items").getJSONObject(0).has("ra"))
        // Με αριθμό: όπως πριν.
        val n = session()
        n.tick(t0 + 1_000)
        n.answer(3, t0 + 2_000)
        assertEquals(3, n.resultJson(t0 + 3_000, HrStats(t0)).getJSONArray("items").getJSONObject(0).getInt("ra"))
        // Προπόνηση του κινητού: «Δεν ξέρω» στο ρολόι, και η επόμενη κατάσταση του κινητού δεν ξαναρωτά.
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", set(10))))
        val p = Repo.phone!!
        assertEquals(LiveSession.Next.ASK_RIR, p.tick(t0 + 1_000))
        p.answer(-1, t0 + 2_000)
        Repo.applyPhone(LiveSession.parsePhone(phoneJson("sA", set(10, done = true, at = t0 + 1_000))))
        assertNull(Repo.phone!!.items[0].rir)
        assertFalse(Repo.phone!!.rirPending)
        // Καμία εντολή «rir» προς το κινητό για το «Δεν ξέρω» (εκεί το −1 θα γραφόταν 0).
        assertTrue(source("WatchActivity.kt").contains("if (s.phone && rir >= 0) cmd(JSONObject().put(\"op\", \"rir\")"))
    }

    // ------------------------------------------------------------------ R7-U3-05
    @Test
    fun waitingForTheFirstHeartRateOnlyInTheFirstHalfMinute() {
        val start = t0
        assertTrue(hrWaiting(silent = false, bpmAt = 0, startedAt = start, now = start))
        assertTrue(hrWaiting(silent = false, bpmAt = 0, startedAt = start, now = start + 29_999))
        assertFalse(hrWaiting(silent = false, bpmAt = 0, startedAt = start, now = start + 30_000))
        // Είχαν έρθει παλμοί σε αυτή την άσκηση και χάθηκαν: «δεν μετριούνται».
        assertFalse(hrWaiting(silent = false, bpmAt = start + 5_000, startedAt = start, now = start + 20_000))
        // Κρίθηκε ήδη «δεν έρχονται»: όχι.
        assertFalse(hrWaiting(silent = true, bpmAt = 0, startedAt = start, now = start + 1_000))
        // Καμία άσκηση: όχι.
        assertFalse(hrWaiting(silent = false, bpmAt = 0, startedAt = 0, now = start))
        assertEquals("♥ περιμένω παλμούς", HR_WAIT_TEXT)
    }

    // ------------------------------------------------------------------ R7-U3-07
    @Test
    fun forgottenScreenTextHasNoOnTheWatch() {
        for (why in Forgotten.Why.values()) {
            val t = Forgotten.screenText(why)
            assertFalse(t, t.contains("στο ρολόι"))
            assertTrue(t, t.startsWith(Forgotten.title(why) + "\n"))
        }
        assertEquals("Τρέχει ακόμα η προπόνηση;\nΑν τελείωσες: κλείσε αυτό και πάτα «Τέλος».", Forgotten.screenText(Forgotten.Why.STRENGTH_IDLE))
        // Η ειδοποίηση μένει όπως ήταν (εκεί το «στο ρολόι» λέει πού).
        assertEquals("Αν τελείωσες, πάτα «Τέλος» στο ρολόι.", Forgotten.text(Forgotten.Why.STRENGTH_IDLE))
        // Round 8 (R8-U3-03): με το αν από κάτω είναι η ερώτηση ρεζέρβας (εκεί δεν υπάρχει «Τέλος»).
        assertTrue(source("ExerciseService.kt").contains("val shown = if (kind == \"walk\") title else Forgotten.screenText(why, onRir, rirEnds)"))
    }

    // ------------------------------------------------------------------ R7-U3-08
    @Test
    fun durationsInFullWords() {
        assertEquals("1 δευτερόλεπτο", agoText(1_000))
        assertEquals("40 δευτερόλεπτα", agoText(40_000))
        assertEquals("59 δευτερόλεπτα", agoText(59_999))
        assertEquals("1 λεπτό", agoText(60_000))
        assertEquals("2 λεπτά", agoText(130_000))
        assertEquals("0 δευτερόλεπτα", agoText(-5))
        assertEquals("", ageText(19_999))
        assertEquals(" (πριν 20 δευτερόλεπτα)", ageText(20_000))
        assertEquals(" (πριν 3 λεπτά)", ageText(180_000))
        // Πουθενά στην οθόνη διάρκεια με «′» (τα «+30″» και η αντίστροφη μέτρηση είναι ετικέτα/χρονόμετρο).
        val view = source("WatchView.kt")
        assertFalse(view, Regex("\\}′\"").containsMatchIn(view))
        assertFalse(view.contains("clockAgo("))
    }
}

/**
 * Έλεγχος 13/11, round 7 (f3, ρολόι): οι οθόνες, ζωγραφισμένες από τον πραγματικό κώδικα (WatchView) όπως στο R1F7ViewTest.
 * Τα στιγμιότυπα γράφονται κι αυτά στο build/watch-shots/ (όνομα «R7_…»).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class R7F3ViewTest {
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

    private fun newView(acts: WatchView.Actions = noop, ambient: Boolean = false): WatchView {
        val v = WatchView(RuntimeEnvironment.getApplication(), acts)
        v.drawnSizes = mutableMapOf()
        v.ambient = ambient
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

    private fun bounds(v: WatchView, label: String): Rect = buttons(v).first { it.first == label }.second

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

    // ------------------------------------------------------------------ R7-U3-04
    @Test
    fun rirScreenHasDontKnowWithItsOwnTouchArea() {
        val now = System.currentTimeMillis()
        val min = (40f * u).toInt() - 1
        val did = mutableListOf<Int>()
        val acts = object : WatchView.Actions by noop {
            override fun answer(rir: Int) {
                did.add(rir)
            }
        }
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            startSet(now)
            Repo.screen = Repo.Screen.RIR
            val v = newView(acts)
            val bmp = draw(v, if (scale == 1f) "R7_W4_rir_unknown" else "R7_W4b_rir_unknown_font13")
            assertTrue(labels(v).toString(), RIR_UNKNOWN in labels(v))
            assertEquals(6, buttons(v).size)
            for ((_, r) in buttons(v)) assertTrue("$scale× $r", r.height() >= min && r.width() >= min)
            assertNoOverlaps(v)
            assertTrue("$scale× ${v.clipped}", v.clipped.isEmpty())
            assertTrue("$scale× ${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            // «με καλή τεχνική» μένει (κάτω από την ερώτηση), ολόκληρο.
            assertTrue("$scale× ${v.drawnSizes}", "με καλή τεχνική" in v.drawnSizes!!)
            // Η περιοχή του «Δεν ξέρω» κάτω από τη 2η σειρά, ως την άκρη.
            val unknown = bounds(v, RIR_UNKNOWN)
            assertTrue("$unknown", unknown.top >= bounds(v, "Τρεις").bottom - 1 && unknown.bottom >= size - 1)
            assertTrue(v.a11yClick(labels(v).indexOf(RIR_UNKNOWN)))
        }
        assertEquals(listOf(-1, -1), did)
    }

    // ------------------------------------------------------------------ R7-U3-02
    @Test
    fun nextExerciseNameIsNeverCut() {
        val now = System.currentTimeMillis()
        val names = listOf(
            "Πίεση ώμων με αλτήρες, καθιστός", "Τρικέφαλοι ξαπλωτός με αλτήρες", "Κάμψεις με τα χέρια στον πάγκο",
            "Κάμψεις δικεφάλων με αλτήρες", "Ρόδα κοιλιακών από τα γόνατα", "Κωπηλασία με αλτήρα",
        )
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            for (name in names) {
                Repo.local = LiveSession(
                    "w1", "A", "Προπόνηση Α", now - 600_000,
                    listOf(
                        ItemT("db_press", "Πιεστικό με αλτήρες", 120, 8, 12, 2, mutableListOf(SetT(10.3, "10,3 kg", 8, done = true, at = now - 5_000))),
                        ItemT("next", name, 90, 8, 12, 2, mutableListOf(SetT(14.3, "14,3 kg", 11))),
                    ),
                    idx = 1, restEnd = now + 60_000, restLen = 90_000,
                )
                Repo.running = "strength"
                Repo.startedAt = now - 600_000
                Repo.bpm = 118
                Repo.bpmAt = now
                Repo.screen = Repo.Screen.REST
                val v = newView()
                draw(v, if (scale == 1f && name == names[0]) "R7_W3f_rest_next_long_name" else null)
                assertTrue("$scale× «$name»: ${v.clipped}", v.clipped.isEmpty())
                // Το TalkBack λέει πάντα «επόμενο: …» ολόκληρο.
                assertTrue(labels(v).first(), labels(v).first().contains("επόμενο: $name, 14,3 kg × 11"))
                assertNoOverlaps(v)
            }
        }
    }

    // ------------------------------------------------------------------ R7-U3-03
    @Test
    fun walkDayButtonNeverCutsTheNote() {
        val plan = planJson.replace("\"today\":\"A\"", "\"today\":\"walk\"").replace("\"note\":\"χαλαρά\"", "\"note\":\"ζωηρά, μέσα στη ζώνη σου\"")
        Repo.applyPlan(Plan.parse(plan))
        Repo.screen = Repo.Screen.HOME
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            val v = newView()
            draw(v, if (scale == 1f) "R7_W1f_home_walk_day_long_note" else null)
            assertTrue("$scale× ${v.clipped}", v.clipped.isEmpty())
            // Το TalkBack λέει ολόκληρο το κουμπί, με τη σημείωση.
            assertTrue(labels(v).toString(), "Περπάτημα, 30 λεπτά · ζωηρά, μέσα στη ζώνη σου" in labels(v))
            assertNoOverlaps(v)
        }
        // Η σύντομη σημείωση γράφεται όπως πριν.
        RuntimeEnvironment.setFontScale(1f)
        Repo.applyPlan(Plan.parse(planJson.replace("\"today\":\"A\"", "\"today\":\"walk\"")))
        val short = newView()
        draw(short)
        assertTrue(labels(short).toString(), "Περπάτημα, 30 λεπτά · χαλαρά" in labels(short))
        assertTrue(short.clipped.isEmpty())
    }

    // ------------------------------------------------------------------ R7-U3-05
    @Test
    fun waitingForTheFirstHeartRateIsNotAFault() {
        val now = System.currentTimeMillis()
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            startSet(now)
            // Μόλις ξεκίνησε, κανένας παλμός ακόμα.
            Repo.startedAt = now - 5_000
            Repo.bpm = 0
            Repo.bpmAt = 0
            val v = newView()
            draw(v, if (scale == 1f) "R7_W2e_set_waiting_hr" else null)
            assertTrue(labels(v).first(), labels(v).first().startsWith("Περιμένω παλμούς"))
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue(v.drawnSizes.toString(), HR_WAIT_TEXT in v.drawnSizes!!)
            // Μετά τα 30″ χωρίς κανέναν: «δεν μετριούνται».
            Repo.startedAt = now - 40_000
            val late = newView()
            draw(late)
            assertTrue(labels(late).first(), labels(late).first().startsWith("Δεν μετριούνται"))
            // Είχαν έρθει και χάθηκαν: «δεν μετριούνται», και στα πρώτα 30″.
            Repo.startedAt = now - 25_000
            Repo.bpm = 118
            Repo.bpmAt = now - 20_000
            val lost = newView()
            draw(lost)
            assertTrue(labels(lost).first(), labels(lost).first().startsWith("Δεν μετριούνται"))
            // Περπάτημα χωρίς όριο: το ίδιο.
            Repo.local = null
            Repo.resetExercise()
            startWalk(now)
            Repo.startedAt = now - 5_000
            Repo.activeSec = 5
            Repo.bpm = 0
            Repo.bpmAt = 0
            val walk = newView()
            draw(walk)
            assertTrue(labels(walk).first(), labels(walk).first().contains("Περιμένω παλμούς"))
            assertTrue(walk.clipped.toString(), walk.clipped.isEmpty())
            Repo.resetExercise()
        }
    }

    // ------------------------------------------------------------------ R7-U3-06
    @Test
    fun walkFinishNoticeIsWrittenLargeEnough() {
        val now = System.currentTimeMillis()
        startWalk(now)
        Repo.notice = WALK_FINISH_NOTICE
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            val v = newView()
            draw(v, if (scale == 1f) "R7_W7h_walk_finish_notice" else "R7_W7h_walk_finish_notice_font13")
            val sz = v.drawnSizes!![WALK_FINISH_NOTICE]
            assertTrue("$scale× ${v.drawnSizes}", sz != null && sz >= (if (scale == 1f) 10f else 12f))
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue(labels(v).toString(), WALK_FINISH_NOTICE in labels(v) && "Παύση" in labels(v))
        }
    }

    // ------------------------------------------------------------------ R7-U3-07
    @Test
    fun forgottenWorkoutScreenTextOpensWholeAndCloses() {
        val now = System.currentTimeMillis()
        val text = Forgotten.screenText(Forgotten.Why.STRENGTH_IDLE)
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            startSet(now)
            Repo.notice = text
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R7_W2c_set_forgotten_screen_text" else null)
            assertEquals(listOf(text, "Κλείσιμο"), labels(v))
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            assertTrue(v.a11yClick(1))
            assertNull(Repo.notice)
        }
    }

    // ------------------------------------------------------------------ R7-U3-08
    @Test
    fun noPrimeMarkDurationsOnTheWatch() {
        val now = System.currentTimeMillis()
        val prime = Regex("\\d+′")
        // Ambient περπάτημα: ο αριθμός και η λέξη (από 14/11 στην ίδια γραμμή, «24 λεπτά»).
        startWalk(now)
        val walk = newView(ambient = true)
        draw(walk, "R7_W10_walk_ambient")
        val ws = walk.drawnSizes!!.keys
        assertFalse(ws.toString(), ws.any { prime.containsMatchIn(it) })
        assertTrue(ws.toString(), "24" in ws && "λεπτά" in ws)
        // Ambient σε προπόνηση.
        Repo.resetExercise()
        startSet(now)
        val set = newView(ambient = true)
        draw(set)
        val ss = set.drawnSizes!!.keys
        assertFalse(ss.toString(), ss.any { prime.containsMatchIn(it) })
        assertTrue(ss.toString(), "1 λεπτό" in ss)
        // Κόκκινη οθόνη ορίου με παλιό αριθμό: «παλμοί πριν 40 δευτερόλεπτα», ολόκληρο και με γράμματα 1,3×.
        RuntimeEnvironment.setFontScale(1f)
        Repo.alarm.limit = 140
        Repo.alarm.reset()
        Repo.alarm.feed(143, 1_000)
        Repo.alarm.feed(143, 7_000)
        Repo.bpm = 143
        Repo.bpmAt = now - 40_300
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            val v = newView()
            draw(v, if (scale == 1f) "R7_W5b_alarm_stale_words" else null)
            val keys = v.drawnSizes!!.keys
            assertTrue(keys.toString(), keys.any { it.startsWith("παλμοί πριν ") && it.endsWith(" δευτερόλεπτα") })
            assertFalse(keys.toString(), keys.any { prime.containsMatchIn(it) || it.contains("″") })
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
        }
    }

    // ------------------------------------------------------------------ R7-U3-10
    @Test
    fun endOnTheSetScreenHasAWideTouchArea() {
        val now = System.currentTimeMillis()
        val wide = (100f * u).toInt() - 1
        startSet(now)
        for (note in listOf(null, finishNotice(false, 0, false))) {
            Repo.notice = note
            val v = newView()
            draw(v)
            val end = bounds(v, "Τέλος")
            assertTrue("$note: $end", end.width() >= wide)
            assertTrue("$note: $end", end.top >= (169f * u).toInt() - 1)
            assertNoOverlaps(v)
        }
    }

    // ------------------------------------------------------------------ R7-U3 Β-Α1 / Β-Α3
    @Test
    fun setLineShowsTheIntensityTargetAndTheNoHrLineKeepsTheVerb() {
        val now = System.currentTimeMillis()
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            startSet(now)
            val v = newView()
            draw(v, if (scale == 1f) "R7_W2_set_rir_target" else "R7_W2b_set_rir_target_font13")
            assertTrue(labels(v).toString(), labels(v).any { it.contains("σετ 1 από 2, άφησε 2") })
            assertTrue(v.drawnSizes.toString(), v.drawnSizes!!.keys.any { it.startsWith("ΣΕΤ 1/2 · άφησε 2") })
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            // «Δεν έρχονται παλμοί» με όριο: «Το όριο 140» / «δεν σε προσέχει τώρα».
            Repo.alarm.limit = 140
            Repo.bpmAt = now - 60_000
            Repo.hrSilent = HrSilence.Silence.LOST
            val no = newView()
            draw(no, if (scale == 1f) "R7_W6b_no_hr_lines" else null)
            assertTrue(no.drawnSizes.toString(), "Το όριο 140" in no.drawnSizes!! && "δεν σε προσέχει τώρα" in no.drawnSizes!!)
            assertTrue(no.clipped.toString(), no.clipped.isEmpty())
            Repo.alarm.limit = null
            Repo.hrSilent = null
        }
    }

    // ------------------------------------------------------------------ R7-A8-5
    @Test
    fun unsavedEndDoesNotSaySaved() {
        val white = Color.WHITE
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.screen = Repo.Screen.END
            Repo.endUnsaved = true
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R7_W8d_end_unsaved" else "R7_W8e_end_unsaved_font13")
            val first = labels(v).first()
            assertTrue(first, first.startsWith("$UNSAVED_TITLE. "))
            assertFalse(first, first.contains("Περνάει στο κινητό"))
            assertTrue(labels(v).toString(), "Εντάξει" in labels(v))
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            // Το κείμενο τελειώνει πάνω από το «ΟΚ» (που αρχίζει στα 158u).
            val rows = ((70f * u).toInt() until (158f * u).toInt()).filter { y -> (0 until size).any { x -> bmp.getPixel(x, y) == white } }
            assertTrue("$scale×", rows.isNotEmpty() && rows.last() < (156f * u).toInt())
            // Αποθηκεύτηκε κανονικά: όπως πριν.
            Repo.endUnsaved = false
            val ok = newView()
            draw(ok)
            assertTrue(labels(ok).first(), labels(ok).first().startsWith("Αποθηκεύτηκε"))
        }
    }

    // ------------------------------------------------------------------ R7-A8-3 (αίτημα του f2)
    @Test
    fun forgottenPhoneWorkoutDoesNotHideTodaysHome() {
        val now = System.currentTimeMillis()
        val hour = 3_600_000L
        fun phone(start: Long, at: Long) = LiveSession.parsePhone(
            """{"active":true,"id":"s7","w":"A","name":"Προπόνηση Α","start":$start,"idx":0,
                "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"sets":[{"label":"10,3 kg","reps":8,"done":true,"at":$at},{"label":"10,3 kg","reps":8}]}]}""",
        )
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.applyPlan(Plan.parse(planJson))
            Repo.screen = Repo.Screen.HOME
            // Χθες, 25 ώρες πριν, και το τελευταίο ✓ πριν από 24,9 ώρες: η κανονική αρχική, χωρίς «Παλμοί εδώ».
            Repo.applyPhone(phone(now - 25 * hour, now - 24 * hour - 54 * 60_000L))
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R7_W1g_home_forgotten_phone" else "R7_W1h_home_forgotten_phone_font13")
            val l = labels(v)
            assertFalse(l.toString(), "Παλμοί εδώ" in l)
            assertTrue(l.toString(), l.any { it.startsWith("Προπόνηση Α, ") } && "Περπάτημα" in l)
            assertTrue(l.first(), l.first().startsWith("$STALE_PHONE_LINE1 από "))
            assertTrue(v.drawnSizes.toString(), STALE_PHONE_LINE1 in v.drawnSizes!!)
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue("${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
            assertNoOverlaps(v)
            // Πρόσφατη (τελευταίο ✓ πριν από 10 λεπτά): όπως πριν, «Παλμοί εδώ».
            Repo.applyPhone(null)
            Repo.applyPhone(phone(now - hour, now - 10 * 60_000L))
            val live = newView()
            draw(live)
            assertTrue(labels(live).toString(), "Παλμοί εδώ" in labels(live))
            Repo.applyPhone(null)
            Repo.lastPhone = null
        }
    }

    // ------------------------------------------------------------------ R7-A7-1
    @Test
    fun doNotDisturbNoticeFitsOnTheWalkScreen() {
        val now = System.currentTimeMillis()
        startWalk(now)
        Repo.zoneAlarm.start(WalkZone(108, 131), Repo.startedEl)
        val text = zoneMutedNotice(powerSave = false, ringerSilent = false, dnd = true)!!
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.notice = text
            Repo.zoneMuted = true
            val v = newView()
            draw(v, if (scale == 1f) "R7_W7s_walk_dnd" else null)
            assertTrue(labels(v).toString(), text in labels(v) && "Παύση" in labels(v))
            assertTrue(labels(v).first(), labels(v).first().contains(ZONE_MUTED_SAY))
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
        }
    }
}
