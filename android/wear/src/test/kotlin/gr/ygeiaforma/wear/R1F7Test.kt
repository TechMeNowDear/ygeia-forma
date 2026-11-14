package gr.ygeiaforma.wear

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.view.MotionEvent
import android.view.View
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
 * Έλεγχος 13/11 (round 1), ρολόι: οι καθαροί κανόνες. Κάθε δοκιμή αποτυγχάνει χωρίς τη διόρθωσή της. Οι τιμές που
 * περιμένουμε βγαίνουν από τον γραμμένο κανόνα, όχι από τον κώδικα. Όλα τα νούμερα είναι δοκιμαστικά.
 */
class R1F7Test {
    private val hour = 60 * 60_000L
    private val minute = 60_000L

    private fun source(name: String): String = File("src/main/kotlin/gr/ygeiaforma/wear/$name").readText()

    // ------------------------------------------------------------------ S8-01
    @Test
    fun recoveryMinuteEndsWithABuzzButNotWhenSkipped() {
        assertFalse(recoveryEndBuzz(1000, 999, false))
        assertTrue(recoveryEndBuzz(1000, 1000, false))
        assertTrue(recoveryEndBuzz(1000, 70_000, false))
        // «Παράλειψη»: καμία δόνηση. Χωρίς λεπτό αποκατάστασης: καμία.
        assertFalse(recoveryEndBuzz(1000, 1000, true))
        assertFalse(recoveryEndBuzz(0, 5000, false))
        // Η υπηρεσία δονεί (ως ξυπνητήρι: χωρίς «alarm = false») ακριβώς στο τέλος του λεπτού, πριν από το «τέλος».
        val service = source("ExerciseService.kt")
        val at = service.indexOf("if (recoveryEndBuzz(Repo.recoveryUntil, now, skipped = false)) {")
        assertTrue(at > 0)
        // 14/11: πριν από το «τέλος» και η φωνή «Οι παλμοί σου έπεσαν …» (γι' αυτό πιο μεγάλο κομμάτι).
        val branch = service.substring(at, at + 520)
        assertTrue(branch, branch.contains("vibrate(longArrayOf(0, 250, 150, 250))"))
        assertTrue(branch, branch.indexOf("vibrate(") < branch.indexOf("finish()"))
    }

    // ------------------------------------------------------------------ S8-02
    @Test
    fun zoneBuzzIsCutBySilentModeAndPowerSaving() {
        assertTrue(zoneBuzzFelt(powerSave = false, ringerSilent = false))
        assertFalse(zoneBuzzFelt(powerSave = true, ringerSilent = false))
        assertFalse(zoneBuzzFelt(powerSave = false, ringerSilent = true))
        assertFalse(zoneBuzzFelt(powerSave = true, ringerSilent = true))
        // Η οθόνη το γράφει μόνο όταν υπάρχει ζώνη με ανοιχτή δόνηση και δεν υπάρχει όριο γιατρού.
        assertTrue(zoneMutedNow(zoneActive = true, hasDoctorLimit = false, powerSave = true, ringerSilent = false))
        assertTrue(zoneMutedNow(zoneActive = true, hasDoctorLimit = false, powerSave = false, ringerSilent = true))
        assertFalse(zoneMutedNow(zoneActive = true, hasDoctorLimit = false, powerSave = false, ringerSilent = false))
        assertFalse(zoneMutedNow(zoneActive = true, hasDoctorLimit = true, powerSave = true, ringerSilent = true))
        assertFalse(zoneMutedNow(zoneActive = false, hasDoctorLimit = false, powerSave = true, ringerSilent = true))
        assertNull(zoneMutedNotice(powerSave = false, ringerSilent = false))
        assertEquals("Σίγαση: χωρίς δόνηση ζώνης", zoneMutedNotice(powerSave = false, ringerSilent = true))
        assertEquals("Εξοικονόμηση: χωρίς δόνηση ζώνης", zoneMutedNotice(powerSave = true, ringerSilent = false))
        assertEquals("Σίγαση: χωρίς δόνηση ζώνης", zoneMutedNotice(powerSave = true, ringerSilent = true))
        assertEquals("χωρίς δόνηση", ZONE_MUTED_TAG)
        // Απόφαση του χρήστη: η δόνηση ζώνης ΜΕΝΕΙ δόνηση ειδοποίησης· το όριο γιατρού μένει ξυπνητήρι.
        val service = source("ExerciseService.kt")
        assertTrue(service.contains("vibrate(if (b == ZoneAlarm.Buzz.UP) longArrayOf(0, 110, 120, 110) else longArrayOf(0, 260), alarm = false)"))
        assertTrue(service.contains("        vibrate(longArrayOf(0, 500, 200, 500, 200, 500))\n"))
        assertTrue(service.contains("VibrationAttributes.createForUsage(if (alarm) VibrationAttributes.USAGE_ALARM else VibrationAttributes.USAGE_NOTIFICATION)"))
    }

    // ------------------------------------------------------------------ S8-04
    @Test
    fun noRestBuzzForARestThatEndedBeforeMeasuringOrDuringAWalk() {
        assertFalse(restBuzzDue(1000, 5000, buzzedFor = 1000, walking = false))
        assertTrue(restBuzzDue(9000, 9000, buzzedFor = 1000, walking = false))
        assertFalse(restBuzzDue(9000, 8999, buzzedFor = 1000, walking = false))
        assertFalse(restBuzzDue(9000, 9500, buzzedFor = 0, walking = true))
        assertFalse(restBuzzDue(0, 5000, buzzedFor = 0, walking = false))
        // Στην αρχή της μέτρησης: ό,τι έληξε ήδη μετρά ως «δονήθηκε»· ό,τι λήγει αργότερα όχι.
        assertEquals(4000L, restAlreadyOver(4000, 5000))
        assertEquals(5000L, restAlreadyOver(5000, 5000))
        assertEquals(0L, restAlreadyOver(6000, 5000))
        assertEquals(0L, restAlreadyOver(0, 5000))
        assertEquals(0L, restAlreadyOver(null, 5000))
        // Το σενάριο του ευρήματος: «Παλμοί εδώ» στις 5000, με παλιό διάλειμμα που έληξε στις 4400 → καμία δόνηση·
        // το επόμενο διάλειμμα (ως τις 9000) δονείται κανονικά.
        val buzzed = restAlreadyOver(4400, 5000)
        assertFalse(restBuzzDue(4400, 5000, buzzed, walking = false))
        assertFalse(restBuzzDue(9000, 6000, buzzed, walking = false))
        assertTrue(restBuzzDue(9000, 9000, buzzed, walking = false))
    }

    // ------------------------------------------------------------------ S8-05
    @Test
    fun tapsAreIgnoredRightAfterTheScreenChangedByItself() {
        assertFalse(tapAllowed(1000, 500))
        assertFalse(tapAllowed(1099, 500))
        assertTrue(tapAllowed(1100, 500))
        assertTrue(tapAllowed(5, -1))
        assertEquals(600L, TAP_GUARD_MS)
        // Μόνο όταν άλλαξε μόνη της, μπροστά στα μάτια του χρήστη.
        assertTrue(screenAutoChanged(hadScreen = true, byTap = false, sinceLastDrawMs = 0))
        assertTrue(screenAutoChanged(hadScreen = true, byTap = false, sinceLastDrawMs = 1500))
        assertFalse(screenAutoChanged(hadScreen = true, byTap = false, sinceLastDrawMs = 1501))
        assertFalse(screenAutoChanged(hadScreen = true, byTap = true, sinceLastDrawMs = 0))
        assertFalse(screenAutoChanged(hadScreen = false, byTap = false, sinceLastDrawMs = 0))
    }

    // ------------------------------------------------------------------ S8-06
    @Test
    fun forgottenExerciseIsOnlyAReminder() {
        assertEquals(3 * hour, Forgotten.LONG_MS)
        // Περπάτημα 30′ στο πρόγραμμα: πάνω από 3 ώρες.
        assertFalse(forgottenDue("walk", 0, 0, -1, 30, 2 * hour))
        assertFalse(forgottenDue("walk", 0, 0, -1, 30, 3 * hour))
        assertTrue(forgottenDue("walk", 0, 0, -1, 30, 3 * hour + 1000))
        assertEquals(Forgotten.Why.WALK_LONG, Forgotten.why("walk", 0, 0, -1, 30, 3 * hour + 1000))
        // Περπάτημα 120′ στο πρόγραμμα: πάνω από το διπλάσιο (4 ώρες).
        assertFalse(forgottenDue("walk", 0, 0, -1, 120, 3 * hour + 1000))
        assertTrue(forgottenDue("walk", 0, 0, -1, 120, 4 * hour + 1000))
        // Παύση πάνω από 10 λεπτά.
        assertFalse(forgottenDue("walk", 0, 0, 0, 30, 9 * minute))
        assertFalse(forgottenDue("walk", 0, 0, 0, 30, 10 * minute))
        assertTrue(forgottenDue("walk", 0, 0, 0, 30, 10 * minute + 1000))
        assertEquals(Forgotten.Why.WALK_PAUSED, Forgotten.why("walk", 0, 0, 0, 30, 10 * minute + 1000))
        // Βάρη: 3 ώρες από το τελευταίο ✓ (όχι από την αρχή).
        assertFalse(forgottenDue("strength", 0, 3 * hour - 10 * minute, -1, 0, 3 * hour + 1000))
        assertTrue(forgottenDue("strength", 0, 0, -1, 0, 3 * hour + 1000))
        assertEquals(Forgotten.Why.STRENGTH_IDLE, Forgotten.why("strength", 0, 0, -1, 0, 3 * hour + 1000))
        assertFalse(forgottenDue(null, 0, 0, -1, 0, 9 * hour))
        // Μία υπενθύμιση, και ξανά ανά 30 λεπτά.
        assertFalse(Forgotten.remindNow(null, 0, 5 * hour))
        assertTrue(Forgotten.remindNow(Forgotten.Why.WALK_LONG, 0, 3 * hour + 1000))
        assertFalse(Forgotten.remindNow(Forgotten.Why.WALK_LONG, 3 * hour, 3 * hour + 30 * minute - 1))
        assertTrue(Forgotten.remindNow(Forgotten.Why.WALK_LONG, 3 * hour, 3 * hour + 30 * minute))
        assertEquals("Τρέχει ακόμα το περπάτημα;", Forgotten.title(Forgotten.Why.WALK_LONG))
        assertEquals("Το περπάτημα είναι σε παύση", Forgotten.title(Forgotten.Why.WALK_PAUSED))
        assertEquals("Τρέχει ακόμα η προπόνηση;", Forgotten.title(Forgotten.Why.STRENGTH_IDLE))
        assertEquals("Πάτα «Συνέχεια» ή «Τέλος» στο ρολόι.", Forgotten.text(Forgotten.Why.WALK_PAUSED))
        assertEquals("Αν τελείωσες, πάτα «Τέλος» στο ρολόι.", Forgotten.text(Forgotten.Why.WALK_LONG))
        // Ποτέ αυτόματο τέλος: η υπενθύμιση δεν καλεί «finish».
        val service = source("ExerciseService.kt")
        val from = service.indexOf("private fun checkForgotten(nowEl: Long) {")
        val to = service.indexOf("// ------------------------------------------------------------------ ζώνη περπατήματος")
        assertTrue(from in 1 until to)
        assertFalse(service.substring(from, to).contains("finish("))
    }

    // ------------------------------------------------------------------ S8-07
    @Test
    fun lostHeartRateCheckWakesTheWatch() {
        assertEquals(26_000L, silenceWakeAt(10_000, 15_000))
        assertEquals(46_000L, silenceWakeAt(0, lostAfterMs(walk = false)))
        assertEquals(1_016_000L, silenceWakeAt(1_000_000, lostAfterMs(walk = true)))
        val service = source("ExerciseService.kt")
        // Οπλίζεται σε κάθε παράδοση παλμών (Health Services και αισθητήρας)· ακυρώνεται στο τέλος και στο κλείσιμο.
        assertTrue(service.contains("if (Repo.bpmEl > hrElBefore) armSilenceAlarm(Repo.bpmEl)"))
        assertTrue(service.contains("armSilenceAlarm(atEl)"))
        assertTrue(Regex("\\n\\s+cancelSilenceAlarm\\(\\)\\n").findAll(service).count() >= 2)
        assertTrue(service.contains("am.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, \"ygeia:silence\", silenceAlarm, silenceHandler)"))
    }

    // ------------------------------------------------------------------ S8-08
    @Test
    fun snapshotIsClearedOnlyWhenTheResultWasStored() {
        val order = mutableListOf<String>()
        assertFalse(Repo.storeResultThenClear({ order.add("save"); false }, { order.add("clear") }))
        assertEquals(listOf("save"), order)
        order.clear()
        assertTrue(Repo.storeResultThenClear({ order.add("save"); true }, { order.add("clear") }))
        assertEquals(listOf("save", "clear"), order)
        // Και οι τρεις θέσεις περνούν από εδώ: πουθενά «savePending» με «clearRun» χωρίς έλεγχο από κάτω.
        for (name in listOf("ExerciseService.kt", "WatchActivity.kt", "Repo.kt")) {
            assertFalse(name, Regex("savePending\\([^\\n]*\\)\\n\\s*(Repo\\.)?clearRun\\(").containsMatchIn(source(name)))
        }
        assertTrue(source("ExerciseService.kt").contains("saved = Repo.storeResultThenClear({ Repo.savePending(this, result.first, result.second) }, { Repo.clearRun(this) })"))
        assertTrue(source("WatchActivity.kt").contains("val saved = Repo.storeResultThenClear({ Repo.savePending(this, s.id, o) }, { Repo.clearRun(this) })"))
    }

    // ------------------------------------------------------------------ S8-09
    @Test
    fun everyQuestionToHealthServicesAtOpeningHasATimeLimit() {
        val act = source("WatchActivity.kt")
        val calls = Regex("getCurrentExerciseInfoAsync\\(\\)").findAll(act).toList()
        assertEquals(3, calls.size)
        for (c in calls) {
            val before = act.substring(maxOf(0, c.range.first - 200), c.range.first)
            assertTrue(before, before.contains("withTimeoutOrNull(FinishTimes.HS_CALL_MS) {"))
        }
        assertTrue(source("Link.kt").contains("withTimeoutOrNull(LOAD_TIMEOUT_MS) { Wearable.getDataClient(ctx.applicationContext).dataItems.await() }"))
        assertEquals(5_000L, Link.LOAD_TIMEOUT_MS)
    }

    // ------------------------------------------------------------------ S10-5
    @Test
    fun noHeartRateValuesInLogcat() {
        val dir = File("src/main/kotlin/gr/ygeiaforma/wear")
        val files = dir.listFiles()!!.filter { it.name.endsWith(".kt") }
        assertTrue(files.size >= 8)
        for (f in files) {
            for (line in f.readLines()) {
                if (!line.contains("Log.")) continue
                for (bad in listOf("\$bpm", "\$buzz", "lastBpm", "Repo.bpm}")) assertFalse("${f.name}: $line", line.contains(bad))
            }
        }
    }

    // ------------------------------------------------------------------ S6-10
    @Test
    fun everyTickNamesItsExercise() {
        val plain = tickCmd(1, 0, 5L, "db_row", null)
        assertEquals("db_row", plain.getString("ex"))
        assertFalse(plain.has("r"))
        assertEquals(5L, plain.getLong("at"))
        val late = tickCmd(2, 1, 0, "db_press", null, late = true)
        assertEquals("db_press", late.getString("ex"))
        assertTrue(late.getBoolean("late"))
        val edited = tickCmd(2, 1, 9L, "db_press", 7)
        assertEquals("db_press", edited.getString("ex"))
        assertEquals(7, edited.getInt("r"))
    }

    // ------------------------------------------------------------------ S12-17 (β)
    @Test
    fun jsonNullTextsFallBackToTheirDefaults() {
        val plan = Plan.parse(
            """{"v":1,"today":"A","at":1,"workouts":[
                 {"id":"A","name":null,"minutes":40,"items":[{"ex":"db_press","name":null,"sets":[{"label":null,"reps":8}]}]},
                 {"id":"walk","name":"Περπάτημα","minutes":30,"cardio":{"activity":null,"name":null,"minutes":30}}]}""",
        )!!
        val a = plan.workout("A")!!
        assertEquals("A", a.name)
        assertEquals("db_press", a.items[0].name)
        assertEquals("", a.items[0].sets[0].label)
        val c = plan.workout("walk")!!.cardio!!
        assertEquals("walk", c.activity)
        assertEquals("Περπάτημα", c.name)
        val phone = LiveSession.parsePhone("""{"active":true,"id":"s1","w":null,"name":null,"start":1,"idx":0,"items":[]}""")!!
        assertEquals("", phone.workout)
        assertEquals("", phone.name)
        // Στο Android το optString(k, προεπιλογή) δίνει «null» για τιμή JSON null: αυτά τα κείμενα δεν περνούν πια από εκεί.
        assertFalse(Regex("optString\\(\"(name|label|w|activity)\"").containsMatchIn(source("Protocol.kt")))
    }

    // ------------------------------------------------------------------ S6-11 / S11-7
    private fun walkPlan(top: String = "", cardio: String = "") = """
        {"v":1,"today":"walk","at":1$top,
         "workouts":[{"id":"walk","name":"Περπάτημα","minutes":20,
           "cardio":{"activity":"walk","name":"Περπάτημα","minutes":20$cardio}}]}
    """.trimIndent()

    @Test
    fun walkingMinutesFollowTheWeekOfTheProgramme() {
        val p = Plan.parse(walkPlan(top = ",\"from\":\"2026-11-16\"", cardio = ",\"plan\":[20,25,30,35]"))!!
        val walk = p.workout("walk")!!.cardio!!
        assertEquals(LocalDate.of(2026, 11, 16), p.from)
        assertEquals(listOf(20, 25, 30, 35), walk.plan)
        // Πριν από την έναρξη: 1η εβδομάδα. Μέρες 0–6: 1η· 7–13: 2η· 14–20: 3η· από 21: 4η και μετά η τελευταία.
        assertEquals(20, p.cardioMinutes(walk, LocalDate.of(2026, 11, 10)))
        assertEquals(20, p.cardioMinutes(walk, LocalDate.of(2026, 11, 16)))
        assertEquals(20, p.cardioMinutes(walk, LocalDate.of(2026, 11, 22)))
        assertEquals(25, p.cardioMinutes(walk, LocalDate.of(2026, 11, 23)))
        assertEquals(25, p.cardioMinutes(walk, LocalDate.of(2026, 11, 24)))
        assertEquals(30, p.cardioMinutes(walk, LocalDate.of(2026, 12, 6)))
        assertEquals(35, p.cardioMinutes(walk, LocalDate.of(2026, 12, 7)))
        assertEquals(35, p.cardioMinutes(walk, LocalDate.of(2027, 3, 2)))
        // Το παράδειγμα του S11-7: [30,35,40,45] από 16/11.
        assertEquals(30, planMinutes(30, listOf(30, 35, 40, 45), LocalDate.of(2026, 11, 16), LocalDate.of(2026, 11, 15)))
        assertEquals(35, planMinutes(30, listOf(30, 35, 40, 45), LocalDate.of(2026, 11, 16), LocalDate.of(2026, 11, 24)))
        assertEquals(40, planMinutes(30, listOf(30, 35, 40, 45), LocalDate.of(2026, 11, 16), LocalDate.of(2026, 12, 1)))
        assertEquals(45, planMinutes(30, listOf(30, 35, 40, 45), LocalDate.of(2026, 11, 16), LocalDate.of(2026, 12, 8)))
        // Μέρες ημερολογίου: η αλλαγή ώρας (25/10/2026) δεν αλλάζει την εβδομάδα.
        assertEquals(20, planMinutes(9, listOf(20, 25), LocalDate.of(2026, 10, 19), LocalDate.of(2026, 10, 25)))
        assertEquals(25, planMinutes(9, listOf(20, 25), LocalDate.of(2026, 10, 19), LocalDate.of(2026, 10, 26)))
    }

    @Test
    fun withoutPlanOrStartTheSentMinutesStay() {
        val day = LocalDate.of(2026, 11, 24)
        // Παλιό κινητό: κανένα από τα δύο πεδία.
        val old = Plan.parse(walkPlan())!!
        assertNull(old.from)
        assertTrue(old.workout("walk")!!.cardio!!.plan.isEmpty())
        assertEquals(20, old.cardioMinutes(old.workout("walk")!!.cardio!!, day))
        // Πλάνο χωρίς μέρα έναρξης, ή μέρα που δεν διαβάζεται: τα λεπτά που στάλθηκαν.
        val noFrom = Plan.parse(walkPlan(cardio = ",\"plan\":[20,25,30,35]"))!!
        assertEquals(20, noFrom.cardioMinutes(noFrom.workout("walk")!!.cardio!!, day))
        val badFrom = Plan.parse(walkPlan(top = ",\"from\":\"16/11/2026\"", cardio = ",\"plan\":[40,45]"))!!
        assertNull(badFrom.from)
        assertEquals(20, badFrom.cardioMinutes(badFrom.workout("walk")!!.cardio!!, day))
        // Πλάνο με τιμή εκτός 1–600 ή όχι αριθμό: αγνοείται ολόκληρο.
        for (bad in listOf("[0,25]", "[20,601]", "[\"x\",25]", "[]")) {
            val p = Plan.parse(walkPlan(top = ",\"from\":\"2026-11-16\"", cardio = ",\"plan\":$bad"))!!
            assertTrue(bad, p.workout("walk")!!.cardio!!.plan.isEmpty())
            assertEquals(bad, 20, p.cardioMinutes(p.workout("walk")!!.cardio!!, day))
        }
        // Η μέρα έναρξης μέσα στο «cardio» γίνεται δεκτή και κερδίζει.
        val inner = Plan.parse(walkPlan(top = ",\"from\":\"2026-11-02\"", cardio = ",\"plan\":[20,25,30,35],\"from\":\"2026-11-23\""))!!
        assertEquals(20, inner.cardioMinutes(inner.workout("walk")!!.cardio!!, day))
        assertEquals(LocalDate.of(2026, 11, 16), dayOrNull("2026-11-16"))
        assertEquals(LocalDate.of(2026, 11, 16), dayOrNull("2026-11-16T00:00:00.000"))
        assertNull(dayOrNull("2026-13-40"))
        assertNull(dayOrNull(null))
    }

    // ------------------------------------------------------------------ S12-11 (Τ9)
    private val none = ZoneAlarm.Buzz.NONE
    private val up = ZoneAlarm.Buzz.UP

    @Test
    fun zoneAlarmFirstBuzzExactlyAfterWarmup() {
        val z = ZoneAlarm(holdMs = 20_000L, upGapMs = 0L, backHoldMs = 0L)
        z.start(WalkZone(108, 131), 0)
        for (t in 0..299) assertEquals("$t″", none, z.feed(150, t * 1000L))
        assertEquals(up, z.feed(150, 300_000))
        for (t in 301..419) assertEquals("$t″", none, z.feed(150, t * 1000L))
        assertEquals(up, z.feed(150, 420_000))
        assertEquals(2, z.ups)
    }

    @Test
    fun zoneAlarmRearmNeedsThreeBelowTop() {
        val t0 = 400_000L
        fun after(dip: Int): List<ZoneAlarm.Buzz> {
            val z = ZoneAlarm(holdMs = 20_000L, upGapMs = 0L, backHoldMs = 0L)
            z.start(WalkZone(108, 131), 0)
            for (k in 0..19) assertEquals(none, z.feed(140, t0 + k * 1000L))
            assertEquals(up, z.feed(140, t0 + 20_000))
            // 14/11: γύρισμα 3 παλμούς κάτω από το πάνω όριο μετά από δόνηση = «Πάλι στη ζώνη» (μόνο φωνή).
            assertEquals(if (dip <= 131 - ZoneAlarm.REARM) ZoneAlarm.Buzz.BACK else none, z.feed(dip, t0 + 21_000))
            return (22..42).map { k -> z.feed(140, t0 + k * 1000L) }
        }
        // 129 = μόνο 2 κάτω από το πάνω όριο: δεν ξαναοπλίζει, και δεν πέρασαν 2 λεπτά → καμία δόνηση.
        assertTrue(after(129).all { it == none })
        // 128 = 3 κάτω: ξαναοπλίζει· 20″ συνεχώς πάνω (από τα 22″ ως τα 42″) → δόνηση ακριβώς στα 42″.
        val again = after(128)
        assertTrue(again.dropLast(1).all { it == none })
        assertEquals(up, again.last())
        assertEquals(3, ZoneAlarm.REARM)
    }

    @Test
    fun zoneAlarmBoundsAreInsideTheZone() {
        val t0 = 400_000L
        val z = ZoneAlarm(holdMs = 20_000L, upGapMs = 0L, backHoldMs = 0L)
        z.start(WalkZone(108, 131, up = true, down = true), 0)
        // Ακριβώς στο πάνω όριο: μέσα στη ζώνη.
        for (k in 0..60) assertEquals(none, z.feed(131, t0 + k * 1000L))
        // Ένας παλμός πάνω: 20″.
        for (k in 61..80) assertEquals("$k", none, z.feed(132, t0 + k * 1000L))
        assertEquals(up, z.feed(132, t0 + 81_000))
        val d = ZoneAlarm(holdMs = 20_000L, upGapMs = 0L, backHoldMs = 0L)
        d.start(WalkZone(108, 131, up = true, down = true), 0)
        // Ακριβώς στο κάτω όριο: μέσα στη ζώνη.
        for (k in 0..120) assertEquals(none, d.feed(108, t0 + k * 1000L))
        // Ένας παλμός κάτω: 1 λεπτό.
        for (k in 121..180) assertEquals("$k", none, d.feed(107, t0 + k * 1000L))
        assertEquals(ZoneAlarm.Buzz.DOWN, d.feed(107, t0 + 181_000))
    }

    @Test
    fun alarmAtExactlyTheLimit() {
        val a = HrAlarm(140)
        for (t in 0..4) assertFalse("$t″", a.feed(140, t * 1000L))
        assertTrue(a.feed(140, 5000))
        a.feed(135, 6000)
        assertTrue(a.on)
        a.feed(134, 7000)
        assertFalse(a.on)
    }

    @Test
    fun alarmRepeatsEvery30s() {
        val a = HrAlarm(140)
        for (t in 0..4) assertFalse(a.feed(141, t * 1000L))
        assertTrue(a.feed(141, 5000))
        for (t in 6..34) assertFalse("$t″", a.feed(141, t * 1000L))
        assertFalse(a.feed(141, 34_999))
        assertTrue(a.feed(141, 35_000))
    }

    @Test
    fun alarmNeedsFourOfFiveSeconds() {
        val a = HrAlarm(140)
        val bpm = listOf(141, 141, 139, 139, 141, 141)
        // 3″ πάνω στα τελευταία 5″: όχι.
        for ((t, v) in bpm.withIndex()) assertFalse("$t″", a.feed(v, t * 1000L))
        assertFalse(a.on)
        // 4″ πάνω στα τελευταία 5″ (141, 139, 141, 141, 141, 141): ναι.
        val b = HrAlarm(140)
        var fired = false
        for ((t, v) in listOf(141, 139, 141, 141, 141, 141).withIndex()) fired = b.feed(v, t * 1000L) || fired
        assertTrue(fired)
    }

    @Test
    fun hrPlausibleRange() {
        val h = HrStats(0)
        h.add(26, 1000)
        h.add(249, 2000)
        h.add(25, 3000)
        h.add(250, 4000)
        assertEquals(2, h.samples.size)
        assertEquals(249, h.max)
        assertEquals(138, h.avg)
    }

    @Test
    fun zoneAndSilenceDecisionsOfTheService() {
        fun speak(walk: Boolean = true, paused: Boolean = false, recovery: Boolean = false, stopping: Boolean = false, limit: Boolean = false, age: Long = 0) =
            zoneMaySpeak(walk, paused, recovery, stopping, limit, age)
        assertTrue(speak())
        // Το όριο του γιατρού νικά τη ζώνη.
        assertFalse(speak(limit = true))
        // Τιμή παλιότερη από 30″ δεν κρίνεται.
        assertEquals(30_000L, ZONE_LATE_MS)
        assertTrue(speak(age = 30_000))
        assertFalse(speak(age = 30_001))
        assertFalse(speak(paused = true))
        assertFalse(speak(recovery = true))
        assertFalse(speak(walk = false))
        assertFalse(speak(stopping = true))
        // Η ζώνη «κρατιέται» (οι 20″ ξαναρχίζουν) σε παύση, αποκατάσταση, τέλος, ή εκτός περπατήματος· ΟΧΙ επειδή υπάρχει όριο.
        assertFalse(zoneOnHold(walk = true, paused = false, recovery = false, stopping = false))
        assertTrue(zoneOnHold(walk = true, paused = true, recovery = false, stopping = false))
        assertTrue(zoneOnHold(walk = true, paused = false, recovery = true, stopping = false))
        assertTrue(zoneOnHold(walk = true, paused = false, recovery = false, stopping = true))
        assertTrue(zoneOnHold(walk = false, paused = false, recovery = false, stopping = false))
        // Ηλικία τιμής: νέα τιμή = τώρα − ο χρόνος της· «σταθεροί» = από την τελευταία πραγματική, εκτός αν ο αισθητήρας
        // έχει ακόμα επαφή και ίδια τιμή (τότε 0).
        assertEquals(4000L, zoneValueAgeMs(steady = false, steadyUntilEl = 0, bpmEl = 500, atEl = 1000, nowEl = 5000))
        assertEquals(4500L, zoneValueAgeMs(steady = true, steadyUntilEl = 0, bpmEl = 500, atEl = 5000, nowEl = 5000))
        assertEquals(0L, zoneValueAgeMs(steady = true, steadyUntilEl = 6000, bpmEl = 500, atEl = 5000, nowEl = 5000))
        // «Χάθηκαν παλμοί»: 15″ στο περπάτημα, 45″ στα βάρη.
        assertEquals(15_000L, lostAfterMs(walk = true))
        assertEquals(45_000L, lostAfterMs(walk = false))
        val s = HrSilence()
        assertFalse(s.check(now = 114_999, startedAt = 1, lastAt = 100_000, live = false, hasLimit = true, paused = false, lostMs = lostAfterMs(true)))
        assertTrue(s.check(now = 115_000, startedAt = 1, lastAt = 100_000, live = false, hasLimit = true, paused = false, lostMs = lostAfterMs(true)))
        val w = HrSilence()
        assertFalse(w.check(now = 144_999, startedAt = 1, lastAt = 100_000, live = false, hasLimit = true, paused = false, lostMs = lostAfterMs(false)))
        assertTrue(w.check(now = 145_000, startedAt = 1, lastAt = 100_000, live = false, hasLimit = true, paused = false, lostMs = lostAfterMs(false)))
        // Η υπηρεσία παίρνει τις αποφάσεις από εδώ (όχι δικά της νούμερα).
        val service = source("ExerciseService.kt")
        assertTrue(service.contains("if (!zoneMaySpeak(walk, Repo.paused, recovery, stopping, Repo.alarm.limit != null, age)) return"))
        assertTrue(service.contains("val lostAfter = lostAfterMs(Repo.running == \"walk\")"))
        assertFalse(service.contains("45_000L"))
    }

    // ------------------------------------------------------------------ S12-16: οι κοινοί κανόνες, όπως τους έχει το ρολόι
    @Test
    fun contractConstants() {
        fun zone(lo: Int, hi: Int) = WalkZone.parse(JSONObject().put("lo", lo).put("hi", hi))
        assertEquals(WalkZone(50, 220, up = true, down = false), zone(50, 220))
        assertNull(zone(49, 131))
        assertNull(zone(108, 221))
        assertNull(zone(120, 120))
        assertEquals(30_000L, HrSilence.FIRST_MS)
        // «Μέσα σε παύση» = [αρχή, τέλος): η τιμή ακριβώς στο τέλος της παύσης μετρά, η τιμή ακριβώς στην αρχή όχι.
        val h = HrStats(0)
        h.pause(10_000)
        h.resume(20_000)
        h.add(100, 9_000)
        h.add(200, 10_000)
        h.add(200, 19_000)
        h.add(120, 20_000)
        assertEquals(110, h.avg)
        assertEquals(120, h.max)
        assertEquals(1, Proto.MAJOR)
    }

    // ------------------------------------------------------------------ οθόνη: καθαροί κανόνες
    @Test
    fun chordOfTheRoundScreen() {
        // 2·√((100 − 3)² − d²), d = η πιο μακρινή από το κέντρο άκρη της γραμμής (0,86 πάνω, 0,24 κάτω από τη βάση).
        assertEquals(95.62f, chordAt(182f, 10f), 0.05f)
        assertEquals(79.86f, chordAt(186f, 10f), 0.05f)
        assertEquals(126.83f, chordAt(171f, 10f), 0.05f)
        assertEquals(106.37f, chordAt(178f, 13f), 0.05f)
        assertEquals(199.26f, chordAt(100f, 10f, edge = 0f), 0.05f)
        assertEquals(0f, chordAt(200f, 10f), 0f)
        // Συμμετρία πάνω/κάτω: η ίδια απόσταση της πιο μακρινής άκρης από το κέντρο δίνει το ίδιο πλάτος.
        assertEquals(chordAt(182f, 10f), chordAt(100f - 84.4f + 8.6f, 10f), 0.05f)
    }

    @Test
    fun briefNoticesAreOnlyTheTwoTapOnes() {
        assertTrue(isBriefNotice(WALK_FINISH_NOTICE))
        assertTrue(isBriefNotice("Πάτα ξανά: επόμενη άσκηση"))
        for (phone in listOf(true, false)) for (sets in listOf(0, 2)) for (hr in listOf(true, false)) {
            assertTrue(isBriefNotice(finishNotice(phone, sets, hr)))
        }
        assertFalse(isBriefNotice(null))
        assertFalse(isBriefNotice("Χωρίς GPS: η απόσταση από τα βήματα."))
        assertFalse(isBriefNotice(SLOW_ALARM_TEXT))
        assertFalse(isBriefNotice(Forgotten.title(Forgotten.Why.STRENGTH_IDLE)))
        assertFalse(isBriefNotice(zoneMutedNotice(powerSave = true, ringerSilent = false)))
        assertTrue(noticeInline(0))
        assertTrue(noticeInline(7_999))
        assertFalse(noticeInline(8_000))
        assertEquals("30 λεπτά", countText(30, "λεπτό", "λεπτά"))
        assertEquals("1 λεπτό", countText(1, "λεπτό", "λεπτά"))
    }
}

/**
 * Έλεγχος 13/11 (round 1), ρολόι: οι οθόνες, ζωγραφισμένες από τον πραγματικό κώδικα (WatchView) όπως στο WatchShotsTest.
 * Τα νέα στιγμιότυπα γράφονται κι αυτά στο build/watch-shots/ (όνομα «R1_…»).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class R1F7ViewTest {
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

    // Round 7 (R7-A8-3): με αρχή «τώρα»· μια προπόνηση του κινητού με αρχή το 1970 μετρά πια ως ξεχασμένη (όχι «Παλμοί εδώ»).
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

    /** Το [Repo] είναι κοινό για όλες τις δοκιμές της ίδιας εκτέλεσης: καθαρό και πριν, όχι μόνο μετά (S12-15). */
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

    private fun newView(acts: WatchView.Actions = noop): WatchView {
        val v = WatchView(RuntimeEnvironment.getApplication(), acts)
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

    /** Οι περιοχές πατήματος όλων των κουμπιών με όνομα, όπως τις βλέπει το TalkBack. */
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

    /** Δύο περιοχές πατήματος πέφτουν η μία πάνω στην άλλη (πάνω από 1 px, που είναι η στρογγύλευση). */
    private fun overlap(a: Rect, b: Rect): Boolean =
        minOf(a.right, b.right) - maxOf(a.left, b.left) > 1 && minOf(a.bottom, b.bottom) - maxOf(a.top, b.top) > 1

    private fun assertNoOverlaps(v: WatchView) {
        val all = buttons(v)
        for (i in all.indices) for (k in i + 1 until all.size) {
            assertFalse("${all[i]} / ${all[k]}", overlap(all[i].second, all[k].second))
        }
    }

    private fun tap(v: WatchView, x: Float, y: Float) {
        val t0 = android.os.SystemClock.uptimeMillis()
        v.dispatchTouchEvent(MotionEvent.obtain(t0, t0, MotionEvent.ACTION_DOWN, x, y, 0))
        v.dispatchTouchEvent(MotionEvent.obtain(t0, t0 + 50, MotionEvent.ACTION_UP, x, y, 0))
    }

    private fun isBlack(p: Int): Boolean = (p and 0x00FFFFFF) == 0

    /** Πόσα pixel της ζώνης [top]–[bottom] (σε u) ταιριάζουν στο [match]. */
    private fun count(bmp: Bitmap, top: Float, bottom: Float, match: (Int) -> Boolean): Int {
        var n = 0
        for (y in (top * u).toInt() until (bottom * u).toInt()) for (x in 0 until size) if (match(bmp.getPixel(x, y))) n++
        return n
    }

    /** Πορτοκαλί γράμματα (#EA580C) πάνω σε μαύρο, και στις εξομαλυμένες άκρες τους (κάλυψη από 50%). */
    private fun orangeText(p: Int): Boolean = Color.red(p) >= 110 && Color.red(p) > Color.green(p) + 40 && Color.blue(p) <= 40

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

    private fun startSet(now: Long): LiveSession {
        Repo.applyPlan(Plan.parse(planJson))
        val s = LiveSession.fromPlan(Repo.plan!!.workout("A")!!, now - 60_000)
        Repo.local = s
        Repo.running = "strength"
        Repo.startedAt = now - 60_000
        Repo.bpm = 118
        Repo.bpmAt = now
        Repo.screen = Repo.Screen.SET
        return s
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

    // ------------------------------------------------------------------ S8-03 / U7-01
    @Test
    fun updateMessageIsNotCoveredByAButton() {
        val third = Color.parseColor("#1C2028")
        Repo.applyPlan(Plan.parse(planJson))
        Repo.screen = Repo.Screen.HOME
        // Χωρίς «ενημέρωσε»: το τρίτο κουμπί υπάρχει.
        val before = newView()
        val plain = draw(before)
        assertTrue(labels(before).toString(), "Προπόνηση Β" in labels(before))
        assertTrue(count(plain, 142f, 170f) { it == third } > 500)
        assertEquals(0, count(plain, 138f, 172f, ::orangeText))
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            Repo.updateNeeded = true
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R1_W12_home_update_needed" else "R1_W12c_home_update_needed_font13")
            val l = labels(v)
            assertTrue(l.toString(), l.first().contains("Ενημέρωσε την εφαρμογή στο ρολόι"))
            // Στη θέση του τρίτου κουμπιού γράφεται το μήνυμα: κανένα κουμπί από πάνω του, και τα δύο κύρια κουμπιά μένουν.
            assertFalse(l.toString(), "Προπόνηση Β" in l)
            assertTrue(l.toString(), l.any { it.startsWith("Προπόνηση Α") } && "Περπάτημα" in l)
            assertEquals(0, count(bmp, 136f, 176f) { it == third })
            assertTrue(count(bmp, 138f, 172f, ::orangeText) > 100)
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue(maxRadius(bmp) <= 98.5f)
            // Με προπόνηση του κινητού ανοιχτή: το μήνυμα πάνω, τα δύο κουμπιά ακάλυπτα.
            Repo.applyPhone(LiveSession.parsePhone(phoneJson))
            val w = newView()
            val bmp2 = draw(w, if (scale == 1f) "R1_W12b_home_phone_update_needed" else null)
            assertTrue(labels(w).toString(), "Παλμοί εδώ" in labels(w) && "Περπάτημα" in labels(w))
            assertTrue(count(bmp2, 22f, 60f, ::orangeText) > 100)
            assertTrue(w.clipped.toString(), w.clipped.isEmpty())
            Repo.applyPhone(null)
            Repo.updateNeeded = false
        }
    }

    // ------------------------------------------------------------------ S8-10 / U7-09, S6-11 / S11-7
    @Test
    fun minutesAreWrittenInFullAndFollowTheProgrammeWeek() {
        val short = Regex("\\d+ λ( |$)")
        Repo.applyPlan(Plan.parse(planJson))
        Repo.screen = Repo.Screen.HOME
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            val v = newView()
            draw(v, if (scale == 1f) "R1_W1_home" else null)
            assertTrue(labels(v).toString(), "Προπόνηση Α, 2 ασκήσεις · 50 λεπτά" in labels(v))
            assertFalse(labels(v).toString(), labels(v).any { short.containsMatchIn(it) })
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
        }
        RuntimeEnvironment.setFontScale(1f)
        // Μέρα περπατήματος, παλιό κινητό (χωρίς πλάνο): τα λεπτά που στάλθηκαν.
        Repo.applyPlan(Plan.parse(planJson.replace("\"today\":\"A\"", "\"today\":\"walk\"")))
        val walkDay = newView()
        draw(walkDay, "R1_W1e_home_walk_day")
        assertTrue(labels(walkDay).toString(), "Περπάτημα, 30 λεπτά · χαλαρά" in labels(walkDay))
        // Με πλάνο ανά εβδομάδα: τα λεπτά της εβδομάδας που τρέχει ΣΗΜΕΡΑ, όχι της εβδομάδας που έγινε η αποστολή (30).
        fun withPlan(from: String) = planJson.replace("\"today\":\"A\"", "\"today\":\"walk\",\"from\":\"$from\"")
            .replace("\"minutes\":30,\"note\"", "\"minutes\":30,\"plan\":[20,25,40,45],\"note\"")
        Repo.applyPlan(Plan.parse(withPlan("2020-01-06")))
        val late = newView()
        draw(late)
        assertTrue(labels(late).toString(), "Περπάτημα, 45 λεπτά · χαλαρά" in labels(late))
        // Round 7 (R7-A6-6): πριν από την έναρξη του προγράμματος δεν υπάρχει «σημερινή» προπόνηση (όπως στο κινητό): κανένα
        // κουμπί «μέρας περπατήματος», μόνο το απλό «Περπάτημα». Τα λεπτά της 1ης εβδομάδας ελέγχονται στο planMinutes.
        Repo.applyPlan(Plan.parse(withPlan("2999-01-01")))
        val early = newView()
        draw(early)
        assertFalse(labels(early).toString(), labels(early).any { it.startsWith("Περπάτημα, ") })
        assertTrue(labels(early).toString(), "Περπάτημα" in labels(early))
    }

    // ------------------------------------------------------------------ U7-02
    @Test
    fun zoneDotDoesNotTouchItsCaption() {
        val now = System.currentTimeMillis()
        startWalk(now)
        Repo.zoneAlarm.start(WalkZone(108, 131), Repo.startedEl)
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            for ((bpm, word) in listOf(118 to "στη ζώνη 108–131", 136 to "πάνω · κόψε λίγο", 98 to "κάτω από τη ζώνη")) {
                Repo.bpm = bpm
                val v = newView()
                val bmp = draw(v, if (scale == 1f && bpm == 136) "R1_W7n_walk_zone_above" else null)
                assertTrue(labels(v).first(), labels(v).first().contains(word))
                assertTrue(v.clipped.toString(), v.clipped.isEmpty())
                // Ανάμεσα στην κουκκίδα (ως 126u) και στη λεζάντα (από ≈ 128u) υπάρχει τουλάχιστον μία ολόμαυρη γραμμή.
                val rows = ((124.5f * u).toInt()..(132f * u).toInt()).filter { y ->
                    ((60f * u).toInt()..(140f * u).toInt()).all { x -> isBlack(bmp.getPixel(x, y)) }
                }
                assertTrue("$scale× $bpm: καμία μαύρη γραμμή ανάμεσα σε κουκκίδα και λεζάντα", rows.isNotEmpty())
            }
        }
    }

    // ------------------------------------------------------------------ U7-03 / U7-04
    @Test
    fun twoLineNoticeStaysInsideTheCircleAndIsNeverCut() {
        val now = System.currentTimeMillis()
        Repo.applyPhone(LiveSession.parsePhone(phoneJson))
        Repo.running = "strength"
        Repo.runningPhone = true
        Repo.bpm = 118
        Repo.bpmAt = now
        Repo.screen = Repo.Screen.SET
        val texts = listOf(finishNotice(true, 0, true), finishNotice(true, 0, false), finishNotice(true, 2, true), finishNotice(false, 0, false), "Πάτα ξανά: επόμενη άσκηση")
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            for ((i, text) in texts.withIndex()) {
                Repo.notice = text
                val v = newView()
                val bmp = draw(v, if (scale == 1f) "R1_W13_notice_$i" else if (i == 0) "R1_W13_notice_0_font13" else null)
                assertTrue("$scale× «$text»: ${v.clipped}", v.clipped.isEmpty())
                assertTrue("$scale× «$text»: ${maxRadius(bmp)}", maxRadius(bmp) <= 98.5f)
                // Το «Τέλος» μένει πατήσιμο όσο φαίνεται το δικό του μήνυμα, και το ✓ δεν ακουμπά το μήνυμα.
                assertTrue(labels(v).toString(), "Τέλος" in labels(v) && text in labels(v))
                // Το μήνυμα διαβάζεται (TalkBack) αλλά δεν είναι δεύτερο κουμπί πάνω στο «Τέλος».
                assertFalse(buttons(v).toString(), buttons(v).any { it.first == text })
                assertNoOverlaps(v)
                val check = bounds(v, "Έγινε το σετ")
                assertTrue("$check", check.top >= (136f * u).toInt() - 1 && check.bottom <= (168f * u).toInt() + 1)
            }
        }
        // Το μακρύ μήνυμα πιάνει δύο γραμμές: τότε το ✓ τελειώνει στα 161u, πάνω από την πρώτη γραμμή.
        RuntimeEnvironment.setFontScale(1f)
        Repo.notice = finishNotice(true, 0, true)
        val two = newView()
        draw(two)
        assertTrue(bounds(two, "Έγινε το σετ").bottom <= (162f * u).toInt())
        Repo.notice = null
        val none = newView()
        draw(none)
        assertTrue(bounds(none, "Έγινε το σετ").bottom >= (168f * u).toInt() - 1)
    }

    @Test
    fun walkNoticesShrinkInsteadOfBeingCut() {
        val now = System.currentTimeMillis()
        startWalk(now)
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            for (text in listOf(WALK_FINISH_NOTICE, "Χωρίς GPS: η απόσταση από τα βήματα.", "Μόνο παλμοί σε αυτό το περπάτημα.", "Τρέχει ακόμα το περπάτημα;", "Το περπάτημα είναι σε παύση", "Σίγαση: χωρίς δόνηση ζώνης", "Εξοικονόμηση: χωρίς δόνηση ζώνης", "Δεν έγινε παύση.")) {
                Repo.notice = text
                val v = newView()
                draw(v, if (text == WALK_FINISH_NOTICE) "R1_W7h_walk_finish_notice${if (scale == 1f) "" else "_font13"}" else null)
                // Μέσα στην οθόνη (όχι σε όλη την οθόνη) και ολόκληρο.
                assertTrue("$scale× «$text»: ${labels(v)}", "Παύση" in labels(v) && text in labels(v))
                assertTrue("$scale× «$text»: ${v.clipped}", v.clipped.isEmpty())
            }
        }
        RuntimeEnvironment.setFontScale(1f)
        // Κείμενο που δεν χωρά ούτε μικρό (η αιτία ενός σφάλματος): ανοίγει ολόκληρο, δεν κόβεται· το κλείσιμο το σβήνει.
        val tooLong = "Δεν ξεκίνησε η μέτρηση: SecurityException: λείπει η άδεια android.permission.health.READ_HEART_RATE"
        Repo.notice = tooLong
        val v = newView()
        draw(v)
        assertEquals(listOf(tooLong, "Κλείσιμο"), labels(v))
        assertTrue(v.a11yClick(1))
        assertNull(Repo.notice)
        draw(v)
        assertTrue(labels(v).toString(), "Παύση" in labels(v))
        // Η μέτρηση του πλάτους είναι πραγματική: ένα όνομα άσκησης που δεν χωρά με τίποτα κόβεται (και το ξέρουμε).
        Repo.resetExercise()
        val s = startSet(now)
        val huge = "Πιεστικό σε κλίση με αλτήρες και λάστιχο αντίστασης μαζί με παύση δύο δευτερολέπτων"
        Repo.local = LiveSession(s.id, s.workout, s.name, s.start, listOf(ItemT("x", huge, 90, 8, 12, 2, mutableListOf(SetT(10.0, "10 kg", 8)))))
        val cut = newView()
        draw(cut)
        assertEquals(listOf(huge), cut.clipped)
    }

    /** U7-04: σε καμία οθόνη, ούτε με γράμματα 1,3×, δεν κόβεται με «…» ένα σταθερό κείμενο της εφαρμογής. */
    @Test
    fun noFixedTextIsCutOnAnyScreen() {
        val now = System.currentTimeMillis()
        for (scale in listOf(1f, 1.3f)) {
            fun check(name: String) {
                val v = newView()
                draw(v)
                assertTrue("$scale× $name: ${v.clipped}", v.clipped.isEmpty())
                assertNoOverlaps(v)
            }
            reset()
            RuntimeEnvironment.setFontScale(scale)
            // Αρχική χωρίς πρόγραμμα, και με το τελευταίο όριο που ήρθε.
            check("αρχική χωρίς πρόγραμμα")
            Repo.knownLimit = 130
            check("αρχική με όριο")
            Repo.knownLimit = null
            // Ρεζέρβα.
            startSet(now)
            Repo.screen = Repo.Screen.RIR
            check("ρεζέρβα")
            // «Δεν έρχονται παλμοί» με όριο γιατρού, και το σετ μετά το «Εντάξει».
            Repo.screen = Repo.Screen.SET
            Repo.alarm.limit = 140
            Repo.bpmAt = now - 60_000
            Repo.hrSilent = HrSilence.Silence.LOST
            check("δεν έρχονται παλμοί")
            WatchView.noHrSeenNow = true
            check("σετ χωρίς παλμούς")
            WatchView.noHrSeenNow = false
            Repo.hrSilent = null
            Repo.alarm.limit = null
            // Λεπτό αποκατάστασης και «Αποθηκεύτηκε».
            Repo.local = null
            Repo.resetExercise()
            startWalk(now)
            Repo.endAt = now
            Repo.recoveryUntil = now + 47_000
            Repo.screen = Repo.Screen.RECOVER
            check("αποκατάσταση")
            Repo.resetExercise()
            Repo.screen = Repo.Screen.END
            check("αποθηκεύτηκε")
            // Προπόνηση του κινητού: «διάλεξε άσκηση», «διάλεξε επόμενη», «όλα τα σετ έγιναν».
            Repo.running = "strength"
            Repo.runningPhone = true
            Repo.bpm = 118
            Repo.bpmAt = now
            Repo.screen = Repo.Screen.SET
            Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s2","w":"_free","name":"Ελεύθερη άσκηση","start":1,"idx":0,"items":[]}"""))
            check("διάλεξε άσκηση")
            Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s3","w":"_free","name":"Ελεύθερη άσκηση","start":1,"idx":0,
                "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"ra":2,"sets":[{"label":"10,3 kg","reps":8,"done":true}]}]}"""))
            check("διάλεξε επόμενη")
            Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s4","w":"A","name":"Προπόνηση Α","start":1,"idx":0,
                "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"ra":2,"sets":[{"label":"10,3 kg","reps":8,"done":true}]}]}"""))
            check("όλα τα σετ έγιναν")
            Repo.notice = finishNotice(true, 1, true)
            check("όλα τα σετ έγιναν, πάτα ξανά")
            Repo.notice = null
            // Αρχική με την «Ελεύθερη άσκηση» του κινητού (μεγάλο όνομα με γράμματα 1,3×).
            Repo.resetExercise()
            Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s2","w":"_free","name":"Ελεύθερη άσκηση","start":$now,"idx":0,"items":[]}"""))
            Repo.screen = Repo.Screen.HOME
            check("αρχική, ελεύθερη άσκηση στο κινητό")
        }
    }

    // ------------------------------------------------------------------ U7-05
    @Test
    fun restBeforeANewExerciseShowsNameAndLoadInFull() {
        val now = System.currentTimeMillis()
        val s = startSet(now)
        s.tick(now - 20_000)
        assertEquals(LiveSession.Next.ASK_RIR, s.tick(now - 1_000))
        s.answer(2, now)
        assertEquals(1, s.idx)
        Repo.screen = Repo.Screen.REST
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            val v = newView()
            draw(v, if (scale == 1f) "R1_W3d_rest_next_exercise" else "R1_W3e_rest_next_exercise_font13")
            assertTrue(labels(v).first(), labels(v).first().contains("επόμενο: Κωπηλασία με αλτήρα, 14,3 kg × 11"))
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertNoOverlaps(v)
        }
        // Μέσα στην ίδια άσκηση μένει η μία γραμμή.
        RuntimeEnvironment.setFontScale(1f)
        s.restEnd = 0
        s.tick(now)
        val same = newView()
        draw(same)
        assertTrue(labels(same).first(), labels(same).first().contains("επόμενο: σετ 2 · 14,3 kg × 11"))
        assertTrue(same.clipped.toString(), same.clipped.isEmpty())
    }

    // ------------------------------------------------------------------ U7-06
    @Test
    fun serviceNoticeGivesTheZoneCaptionBackAfterEightSeconds() {
        val now = System.currentTimeMillis()
        startWalk(now)
        Repo.zoneAlarm.start(WalkZone(108, 131), Repo.startedEl)
        Repo.bpm = 136
        val text = "Χωρίς GPS: η απόσταση από τα βήματα."
        Repo.notice = text
        var t = 50_000L
        val v = newView()
        v.clockEl = { t }
        draw(v)
        assertFalse(labels(v).first(), labels(v).first().contains("πάνω · κόψε λίγο"))
        assertTrue(labels(v).toString(), text in labels(v))
        t += 7_900
        draw(v)
        assertTrue(labels(v).toString(), text in labels(v))
        t += 200
        draw(v)
        assertTrue(labels(v).first(), labels(v).first().contains("πάνω · κόψε λίγο"))
        assertFalse(labels(v).toString(), text in labels(v))
        assertNull(Repo.notice)
    }

    // ------------------------------------------------------------------ U7-07
    @Test
    fun serviceNoticeNeverHidesEndOnTheSetScreen() {
        val now = System.currentTimeMillis()
        startSet(now)
        val text = "Χωρίς άδεια παλμών: η προπόνηση γράφεται, οι παλμοί όχι."
        Repo.notice = text
        val v = newView()
        draw(v)
        // Ανοίγει ολόκληρο, σε όλη την οθόνη· ένα πάτημα το κλείνει και ξαναφαίνεται το «Τέλος».
        assertEquals(listOf(text, "Κλείσιμο"), labels(v))
        assertTrue(v.a11yClick(1))
        assertNull(Repo.notice)
        draw(v)
        assertTrue(labels(v).toString(), "Τέλος" in labels(v) && "Έγινε το σετ" in labels(v))
        // Η υπενθύμιση «τρέχει ακόμα;» το ίδιο (δεν κρύβει το «Τέλος» που ζητά να πατήσεις).
        Repo.notice = Forgotten.title(Forgotten.Why.STRENGTH_IDLE) + " " + Forgotten.text(Forgotten.Why.STRENGTH_IDLE)
        draw(v)
        assertEquals("Κλείσιμο", labels(v).last())
        assertEquals(2, labels(v).size)
    }

    // ------------------------------------------------------------------ U7-08
    @Test
    fun touchAreasAreLargeAndNeverShared() {
        val now = System.currentTimeMillis()
        val min = (40f * u).toInt() - 1
        // Διάλειμμα.
        val s = startSet(now)
        s.tick(now - 5_000)
        Repo.screen = Repo.Screen.REST
        val rest = newView()
        draw(rest)
        assertNoOverlaps(rest)
        val plus = bounds(rest, "Τριάντα δευτερόλεπτα ακόμα")
        val go = bounds(rest, "Τέλος διαλείμματος")
        assertTrue("$plus / $go", go.left - plus.right >= (3f * u).toInt())
        for (r in listOf(plus, go, bounds(rest, "Έκανες μία λιγότερη"), bounds(rest, "Έκανες μία παραπάνω"))) {
            assertTrue("$r", r.height() >= min && r.width() >= min)
        }
        // Ρεζέρβα: δύο σειρές που δεν πατούν η μία την άλλη.
        Repo.screen = Repo.Screen.RIR
        val rir = newView()
        draw(rir)
        assertNoOverlaps(rir)
        // Round 7 (R7-U3-04): και «Δεν ξέρω» (160–200u).
        assertEquals(6, buttons(rir).size)
        for ((_, r) in buttons(rir)) assertTrue("$r", r.height() >= min && r.width() >= min)
        assertTrue(bounds(rir, "Τρεις").top >= bounds(rir, "Μία").bottom - 1)
        // Σετ.
        Repo.screen = Repo.Screen.SET
        s.restEnd = 0
        val set = newView()
        draw(set)
        assertNoOverlaps(set)
        assertTrue(bounds(set, "Επόμενη άσκηση").height() >= min)
        // Περπάτημα, και με μήνυμα πάνω από τα κουμπιά.
        Repo.local = null
        Repo.resetExercise()
        startWalk(now)
        for (note in listOf(null, "Δεν έγινε παύση.")) {
            Repo.notice = note
            val walk = newView()
            draw(walk)
            assertNoOverlaps(walk)
            val pause = bounds(walk, "Παύση")
            val end = bounds(walk, "Τέλος περπατήματος")
            assertTrue("$pause / $end", end.left - pause.right >= (1f * u).toInt())
            assertTrue(pause.height() >= min && end.height() >= min && pause.width() >= min && end.width() >= min)
            if (note != null) assertTrue(bounds(walk, note).bottom <= pause.top + 1)
        }
        Repo.notice = null
        // Αρχική με προπόνηση του κινητού: δύο κουμπιά, 40u το καθένα.
        Repo.resetExercise()
        Repo.applyPhone(LiveSession.parsePhone(phoneJson))
        Repo.screen = Repo.Screen.HOME
        val home = newView()
        draw(home)
        assertNoOverlaps(home)
        assertTrue(bounds(home, "Παλμοί εδώ").height() >= min && bounds(home, "Περπάτημα").height() >= min)
    }

    // ------------------------------------------------------------------ S8-05
    @Test
    fun aTapAimedAtThePreviousScreenIsNotExecuted() {
        val now = System.currentTimeMillis()
        val s = startSet(now)
        s.tick(now - 60_000)
        Repo.screen = Repo.Screen.REST
        val did = mutableListOf<String>()
        val acts = object : WatchView.Actions by noop {
            override fun tick() {
                did.add("tick")
                Repo.screen = Repo.Screen.REST
            }
            override fun restPlus() { did.add("plus") }
            override fun restStop() { did.add("go") }
            override fun finishWorkout() { did.add("end") }
        }
        var t = 100_000L
        val v = newView(acts)
        v.clockEl = { t }
        draw(v)
        // Το διάλειμμα λήγει μόνο του: η οθόνη γίνεται «σετ» ενώ το δάχτυλο πηγαίνει στο «Πάμε» (124u, 160u = πάνω στο ✓).
        t += 500
        s.restEnd = 0
        Repo.screen = Repo.Screen.SET
        draw(v)
        t += 100
        tap(v, 124f * u, 160f * u)
        tap(v, 100f * u, 185f * u)
        assertEquals(emptyList<String>(), did)
        // 600 ms μετά την αλλαγή τα πατήματα δουλεύουν κανονικά.
        t += 500
        tap(v, 124f * u, 160f * u)
        assertEquals(listOf("tick"), did)
        // Αλλαγή από πάτημα (✓ → διάλειμμα): το επόμενο πάτημα δεν περιμένει.
        draw(v)
        s.restEnd = now + 60_000
        t += 50
        tap(v, 73f * u, 168f * u)
        assertEquals(listOf("tick", "plus"), did)
        // Η οθόνη ήταν σβηστή/αχνή όταν άλλαξε (καμία εικόνα για πάνω από 1,5″): καμία αναμονή όταν σηκώνεις τον καρπό.
        draw(v)
        t += 10_000
        s.restEnd = 0
        Repo.screen = Repo.Screen.SET
        draw(v)
        t += 50
        tap(v, 124f * u, 160f * u)
        assertEquals(listOf("tick", "plus", "tick"), did)
        // Ενώ η ίδια αλλαγή μπροστά στα μάτια του χρήστη (εικόνα πριν από 1″) το κρατά.
        draw(v)
        t += 1_000
        draw(v)
        t += 400
        s.restEnd = 0
        Repo.screen = Repo.Screen.SET
        draw(v)
        t += 300
        tap(v, 124f * u, 160f * u)
        assertEquals(3, did.size)
    }

    // ------------------------------------------------------------------ S8-02
    @Test
    fun mutedZoneBuzzIsWrittenNextToTheHeartRate() {
        val now = System.currentTimeMillis()
        startWalk(now)
        Repo.zoneAlarm.start(WalkZone(108, 131), Repo.startedEl)
        // Round 7 (R7-A7-1): και «Μην ενοχλείτε».
        val say = "Σίγαση, Μην ενοχλείτε ή εξοικονόμηση ενέργειας: χωρίς δόνηση ζώνης"
        val plain = newView()
        draw(plain)
        assertFalse(labels(plain).first(), labels(plain).first().contains(say))
        Repo.zoneMuted = true
        for (scale in listOf(1f, 1.3f)) {
            RuntimeEnvironment.setFontScale(scale)
            val v = newView()
            val bmp = draw(v, if (scale == 1f) "R1_W7q_walk_zone_muted" else "R1_W7r_walk_zone_muted_font13")
            assertTrue(labels(v).first(), labels(v).first().contains(say))
            // Η λεζάντα της ζώνης μένει από κάτω, τίποτα δεν κόβεται, και όλα μένουν μέσα στον κύκλο.
            assertTrue(labels(v).first(), labels(v).first().contains("στη ζώνη 108–131"))
            assertTrue(v.clipped.toString(), v.clipped.isEmpty())
            assertTrue(maxRadius(bmp) <= 98.5f)
        }
        RuntimeEnvironment.setFontScale(1f)
        // Με όριο γιατρού μιλά μόνο εκείνο: καμία ένδειξη για τη ζώνη.
        Repo.alarm.limit = 150
        val limit = newView()
        draw(limit)
        assertFalse(labels(limit).first(), labels(limit).first().contains(say))
        assertTrue(labels(limit).first(), labels(limit).first().contains("όριο 150"))
    }

    // ------------------------------------------------------------------ U7-19
    @Test
    fun whiteOnOrangeButtonsHaveEnoughContrast() {
        fun lum(c: Int): Double {
            fun ch(v: Int): Double {
                val x = v / 255.0
                return if (x <= 0.03928) x / 12.92 else Math.pow((x + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * ch(Color.red(c)) + 0.7152 * ch(Color.green(c)) + 0.0722 * ch(Color.blue(c))
        }
        fun contrast(a: Int, b: Int): Double = (maxOf(lum(a), lum(b)) + 0.05) / (minOf(lum(a), lum(b)) + 0.05)
        Repo.applyPlan(Plan.parse(planJson))
        Repo.screen = Repo.Screen.HOME
        val v = newView()
        val bmp = draw(v)
        // Το φόντο του πρώτου κουμπιού (αριστερά από τα γράμματα): λευκά γράμματα πάνω του ≥ 4,5:1 (WCAG 2.1, 1.4.3).
        val fill = bmp.getPixel((40f * u).toInt(), (64f * u).toInt())
        assertEquals(Color.parseColor("#C2410C"), fill)
        assertTrue(contrast(Color.WHITE, fill) >= 4.5)
        assertTrue(contrast(Color.WHITE, Color.parseColor("#EA580C")) < 4.5)
        assertTrue(contrast(Color.parseColor("#FECACA"), Color.parseColor("#991B1B")) >= 4.5)
        // Η κόκκινη οθόνη του ορίου με γράμματα 1,3×: το «πάτα για να κλείσει» χωρά (μικραίνει), δεν κόβεται.
        Repo.running = "strength"
        Repo.bpm = 143
        Repo.bpmAt = System.currentTimeMillis()
        Repo.alarm.limit = 140
        Repo.alarm.reset()
        Repo.alarm.feed(143, 1_000)
        Repo.alarm.feed(143, 7_000)
        RuntimeEnvironment.setFontScale(1.3f)
        val alarm = newView()
        draw(alarm, "R1_W5d_alarm_font13")
        assertEquals("Κλείσιμο για ένα λεπτό", labels(alarm).last())
        assertTrue(alarm.clipped.toString(), alarm.clipped.isEmpty())
    }
}
