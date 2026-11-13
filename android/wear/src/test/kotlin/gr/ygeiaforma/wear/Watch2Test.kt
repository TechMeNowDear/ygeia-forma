package gr.ygeiaforma.wear

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Έλεγχος γ2 του ρολογιού (κλάδος fix-watch2): κάθε δοκιμή αποτυγχάνει χωρίς τη διόρθωσή της. Όλα τα νούμερα δοκιμαστικά.
 */
class Watch2Test {
    @After
    fun reset() {
        Repo.applyPhone(null)
        Repo.lastPhone = null
        Repo.local = null
        Repo.resetExercise()
        Repo.alarm.limit = null
        Repo.alarm.reset()
        Repo.watchingUntil = 0
        Repo.phoneKnowsWatching = false
    }

    /** W2-02: 4″ πάνω και 1″ κάτω, ξανά και ξανά (μέσος πάνω από το όριο): πριν, καμία δόνηση ποτέ. */
    @Test
    fun alarmBriefDipDoesNotReset() {
        val a = HrAlarm(130)
        var fired = false
        for (k in 0 until 60) {
            val bpm = if (k % 5 == 4) 129 else 133
            fired = fired or a.feed(bpm, k * 1000L)
        }
        assertTrue(fired)
        // Θόρυβος γύρω από όριο − 3 (κυρίως κάτω): όχι.
        val b = HrAlarm(130)
        var f2 = false
        for (k in 0 until 60) f2 = f2 or b.feed(if (k % 3 == 0) 131 else 126, k * 1000L)
        assertFalse(f2)
    }

    /** W2-02: τιμή μόνο όταν αλλάζει (142 μία φορά και μετά τίποτα): ισχύει ώσπου να έρθει άλλη. */
    @Test
    fun alarmSampleAndHold() {
        val a = HrAlarm(130)
        assertFalse(a.feed(128, 0))
        assertFalse(a.feed(142, 1_000))
        assertFalse(a.steady(142, 4_000))
        assertTrue(a.steady(142, 6_000))
    }

    /** W2-16: αλλαγή ορίου στη μέση (130 → 145 με 142): η κόκκινη οθόνη σβήνει· νέο επεισόδιο = νέα σίγαση. */
    @Test
    fun alarmLimitChangeAndMuteEpisode() {
        Repo.running = "strength"
        val a = Repo.alarm
        a.limit = 130
        a.reset()
        a.feed(142, 0)
        assertTrue(a.feed(142, 5_000))
        assertTrue(Repo.alarmShown(10_000))
        // «πάτα για να κλείσει»: 60″, και η δόνηση των 30″ ΔΕΝ τη σβήνει (πριν: ξανά κόκκινη στα 30″)
        Repo.muteAlarm(10_000)
        assertTrue(a.feed(142, 35_000))
        assertFalse(Repo.alarmShown(40_000))
        assertTrue(Repo.alarmShown(71_000))
        // νέο όριο πάνω από τους παλμούς: σβήνει αμέσως
        a.limit = 145
        assertFalse(a.on)
        assertFalse(Repo.alarmShown(72_000))
        // πάλι κάτω: νέο επεισόδιο, φαίνεται παρά την προηγούμενη σίγαση
        a.limit = 130
        Repo.muteAlarm(73_000)
        // οι παλμοί ήταν ήδη πάνω από το νέο όριο εδώ και ώρα: ανάβει αμέσως
        assertTrue(a.feed(142, 74_000))
        assertTrue(Repo.alarmShown(80_000))
    }

    /** W2-17 / L7: καθυστερημένη ειδοποίηση και τι λέει. */
    @Test
    fun lateAlarmAndAdvice() {
        assertTrue(lateAlarmBuzz(2_000, stillOver = false))
        assertTrue(lateAlarmBuzz(120_000, stillOver = true))
        assertFalse(lateAlarmBuzz(120_000, stillOver = false))
        assertEquals("", ageText(5_000))
        // Round 7 (R7-U3-08): σε ολόκληρες λέξεις, όχι «40″» / «2′».
        assertEquals(" (πριν 40 δευτερόλεπτα)", ageText(40_000))
        assertEquals(" (πριν 2 λεπτά)", ageText(130_000))
        assertEquals("Κόψε ρυθμό.", alarmAdvice(walk = true, recovery = false))
        // λεπτό αποκατάστασης: κάθεσαι ήδη· όχι «Κόψε ρυθμό»
        assertEquals("Ξεκουράσου.", alarmAdvice(walk = true, recovery = true))
        assertEquals("Ξεκουράσου", alarmHeadline(walk = true, recovery = true))
        // βάρη: χωρίς «κάτω από 140» (η οθόνη σβήνει κάτω από 135)
        assertEquals("Ξεκουράσου μέχρι να πέσουν οι παλμοί.", alarmAdvice(walk = false, recovery = false))
    }

    /** RT-18: μόνο παλμοί (χωρίς απόσταση και βήματα) δεν λέει «από τα βήματα». */
    @Test
    fun walkNoticeSaysWhatIsMeasured() {
        assertEquals("Μόνο παλμοί σε αυτό το περπάτημα.", walkStartNotice(gpsAsked = true, gps = false, distance = false, hr = true))
        assertEquals("Χωρίς GPS: η απόσταση από τα βήματα.", walkStartNotice(true, false, true, true))
        assertNull(walkStartNotice(true, true, true, true))
        assertEquals("Το ρολόι δεν δίνει παλμούς σε αυτή την άσκηση.", walkStartNotice(false, false, true, false))
    }

    /** W2-11: χωρίς σημείο ελέγχου από το Health Services το περπάτημα δεν γράφεται 0 λεπτά. */
    @Test
    fun walkDurationWithoutCheckpoint() {
        val t0 = 1_700_000_000_000L
        assertEquals(1500, wallActiveSec(t0, t0 + 1_600_000, listOf(longArrayOf(t0 + 100_000, t0 + 200_000))))
        assertEquals(1500, wallActiveSec(t0, t0 + 1_600_000, listOf(longArrayOf(t0 + 1_500_000, 0L))))
        Repo.running = "walk"
        Repo.startedAt = t0
        Repo.hr = HrStats(t0)
        val r = Results.build(t0 + 1_800_000)!!
        assertEquals(1800, r.second.getJSONObject("cardio").getLong("sec"))
    }

    /** W2-08: κενό από την αρχή, χωρίς όριο 60″ στο τέλος, και πόσες παραδόσεις. */
    @Test
    fun gapMeterFromStartToEnd() {
        val g = GapMeter()
        g.start(1_000)
        g.mark(241_000) // πρώτη παράδοση 4′ μετά την αρχή
        g.mark(246_000)
        g.close(2_401_000) // καμία ως το τέλος (40′)
        assertEquals(2_155, g.maxGapSec)
        assertEquals(2, g.deliveries)
        Repo.running = "walk"
        Repo.startedAt = 1_000
        Repo.hrMode = "5s"
        Repo.hrGaps = g
        Repo.diag = "5s=1 wake=0"
        Repo.lastErr = "SecurityException: x"
        val r = Results.build(10_000)!!.second
        assertEquals(2, r.getInt("hrDel"))
        assertEquals("5s=1 wake=0", r.getString("diag"))
        assertEquals("SecurityException: x", r.getString("err"))
    }

    /** W3-15: «ζωντανά» μόνο όσο κοιτάζει το κινητό· στο παλιό κινητό όπως πριν. */
    @Test
    fun liveOnlyWhilePhoneWatches() {
        // παλιό κινητό: ανά 10″
        assertTrue(liveDue(100_000, 85_000, phoneKnowsWatching = false, watchingUntil = 0))
        assertFalse(liveDue(100_000, 95_000, false, 0))
        // νέο κινητό, κλειστή εφαρμογή: μόνο το πρώτο
        assertTrue(liveDue(100_000, 0, true, 0))
        assertFalse(liveDue(100_000, 85_000, true, 0))
        // νέο κινητό που κοιτάζει
        assertTrue(liveDue(100_000, 85_000, true, 130_000))
        assertEquals(60_000, watchingTtl("""{"v":1,"ttl":60000}"""))
        assertEquals(120_000, watchingTtl("""{"ttl":9999999}"""))
        assertEquals(0, watchingTtl("όχι json"))
    }

    /** W2-06: άσκηση που παραλείφθηκε στο κινητό: το ρολόι δεν πηγαίνει εκεί. */
    @Test
    fun skippedOnPhoneIsNotVisited() {
        val s = LiveSession.parsePhone(
            """{"active":true,"id":"s1","w":"A","name":"Α","start":1,"idx":0,"items":[
              {"ex":"rdl","name":"R","rest":90,"sets":[{"label":"","reps":8,"done":true},{"label":"","reps":8}]},
              {"ex":"leg_curl","name":"L","rest":60,"skip":1,"sets":[{"label":"","reps":10}]},
              {"ex":"plank","name":"P","rest":0,"sets":[{"label":"","reps":1}]}]}""",
        )!!
        assertTrue(s.items[1].skipped)
        assertEquals(LiveSession.Next.ASK_RIR, s.tick(10_000))
        s.answer(2, 11_000)
        assertEquals(2, s.idx)
        s.idx = 0
        assertEquals(LiveSession.Next.SET, s.skip())
        assertEquals(2, s.idx)
        s.items[2].sets[0].done = true
        assertTrue(s.allDone)
        // το στιγμιότυπο κρατά το «skip»
        assertTrue(LiveSession.fromState(s.toState())!!.items[1].skipped)
    }

    /** W2-18: απάντηση ρεζέρβας όταν δεν περιμένει καμία: δεν γράφεται στην άσκηση που φαίνεται τώρα. */
    @Test
    fun rirWithoutPendingGoesNowhere() {
        val s = LiveSession.parsePhone(
            """{"active":true,"id":"s1","w":"A","name":"Α","start":1,"idx":1,"items":[
              {"ex":"a","name":"A","rest":90,"ra":2,"sets":[{"label":"","reps":8,"done":true}]},
              {"ex":"b","name":"B","rest":60,"sets":[{"label":"","reps":10}]}]}""",
        )!!
        assertFalse(s.rirPending)
        val (_, i) = s.answer(0, 5_000)
        assertEquals(-1, i)
        assertNull(s.items[1].rir)
        // ερώτηση στο ρολόι και απάντηση στο κινητό: δεν περιμένει πια
        s.rirIdx = 0
        assertFalse(s.rirPending)
        s.items[0].rir = null
        assertTrue(s.rirPending)
    }

    /** W2-20: το δαχτυλίδι του διαλείμματος μετά το τελευταίο σετ: με το διάλειμμα που ξεκίνησε, όχι της επόμενης άσκησης. */
    @Test
    fun restRingUsesStartedRest() {
        val p = Plan.parse(
            """{"v":1,"today":"A","workouts":[{"id":"A","name":"Α","minutes":30,"items":[
              {"ex":"a","name":"A","rest":120,"sets":[{"label":"","reps":8}]},
              {"ex":"b","name":"B","rest":60,"sets":[{"label":"","reps":10}]}]}]}""",
        )!!
        val s = LiveSession.fromPlan(p.workouts[0], 0)
        assertEquals(LiveSession.Next.ASK_RIR, s.tick(0))
        s.answer(2, 1_000)
        assertEquals(1, s.idx)
        // 60″ από τα 120″: μισό (πριν: 60/60 = γεμάτο)
        assertEquals(0.5f, s.restLeft(61_000), 0.01f)
        s.addRest(61_000)
        assertEquals(90_000L / 150_000f, s.restLeft(61_000), 0.01f)
        // προπόνηση του κινητού: ίδιο διάλειμμα → ίδιο σύνολο· «+30″» → +30″
        val prev = LiveSession("s", "A", "Α", 0, emptyList(), restEnd = 100_000, phone = true, restLen = 90_000)
        val same = LiveSession("s", "A", "Α", 0, emptyList(), restEnd = 100_000, phone = true)
        assertEquals(90_000, Repo.phoneRestLen(prev, same, 50_000))
        val plus = LiveSession("s", "A", "Α", 0, emptyList(), restEnd = 130_000, phone = true)
        assertEquals(120_000, Repo.phoneRestLen(prev, plus, 50_000))
    }

    /** RT-13: στο διάλειμμα, το σετ που μόλις έγινε (για διόρθωση των επαναλήψεων). */
    @Test
    fun lastDoneSetDuringRest() {
        val p = Plan.parse(
            """{"v":1,"today":"A","workouts":[{"id":"A","name":"Α","minutes":30,"items":[
              {"ex":"a","name":"A","rest":90,"sets":[{"label":"","reps":8},{"label":"","reps":8}]}]}]}""",
        )!!
        val s = LiveSession.fromPlan(p.workouts[0], 0)
        s.tick(10_000)
        assertEquals(0 to 0, s.lastDone(20_000))
        assertNull(s.lastDone(100_001)) // το διάλειμμα τελείωσε
    }

    /** W2-23: «μπες στην προπόνηση του κινητού» δεν περιμένει όσο τρέχει περπάτημα. */
    @Test
    fun joinNotKeptWhileWalking() {
        assertTrue(pendingJoin(true, null, false))
        assertFalse(pendingJoin(true, "walk", false))
        assertFalse(pendingJoin(true, null, true))
        assertFalse(pendingJoin(false, null, false))
    }

    /** W2-02: «δεν μετριούνται» από το Health Services (εκτός καρπού), και τιμή που κρατά ως 60″ όσο λέει ότι μετρά. */
    @Test
    fun availabilityDecidesNotMeasured() {
        val now = 1_000_000L
        Repo.bpm = 120
        Repo.bpmAt = now - 30_000
        Repo.hrMode = "default"
        assertFalse(Repo.hrLive(now))
        Repo.hrAvailable = true
        assertTrue(Repo.hrLive(now))
        assertFalse(Repo.hrLive(now + 40_000))
        // στο «5s» όχι (στέλνει κάθε 5″)
        Repo.hrMode = "5s"
        assertFalse(Repo.hrLive(now))
        // εκτός καρπού: όχι, και με φρέσκια τιμή
        Repo.bpmAt = now
        Repo.hrAvailable = false
        assertFalse(Repo.hrLive(now))
    }

    /** Το ίδιο JSON αποτελέσματος με πριν: μόνο νέα πεδία (το παλιό κινητό διαβάζει όσα ξέρει). */
    @Test
    fun resultOnlyAddsFields() {
        val t0 = 1_700_000_000_000L
        Repo.running = "walk"
        Repo.startedAt = t0
        Repo.hr = HrStats(t0).also { for (k in 0..20) it.add(110, t0 + k * 1000L) }
        Repo.cpActiveMs = 600_000
        Repo.cpWall = t0 + 600_000
        val o: JSONObject = Results.build(t0 + 600_000)!!.second
        for (k in listOf("v", "id", "kind", "w", "name", "start", "end", "items", "hrAvg", "hrMax", "hrT0", "hr", "cardio", "lim")) assertTrue(k, o.has(k))
        assertEquals(1, o.getInt("v"))
    }

    /** Έλεγχος του γ2, S1: το μήνυμα ασφάλειας χωρίς αριθμό που δεν μετρήθηκε, πρώτο, και στο κινητό («slow»). */
    @Test
    fun slowAlarmNoticeFirstAndWithoutNumbers() {
        assertFalse(SLOW_ALARM_TEXT, SLOW_ALARM_TEXT.any { it.isDigit() })
        assertTrue(SLOW_ALARM_TEXT.startsWith("Με σβηστή οθόνη"))
        assertEquals("$SLOW_ALARM_TEXT Χωρίς GPS: η απόσταση από τα βήματα.", withSafety(SLOW_ALARM_TEXT, "Χωρίς GPS: η απόσταση από τα βήματα."))
        assertEquals(SLOW_ALARM_TEXT, withSafety(SLOW_ALARM_TEXT, null))
        assertEquals(SLOW_ALARM_TEXT, withSafety(SLOW_ALARM_TEXT, withSafety(SLOW_ALARM_TEXT, null)))
        assertEquals(1, Link.ackJson(140, 5, slow = true).getInt("slow"))
        assertFalse(Link.ackJson(140, 5).has("slow"))
    }

    /** Έλεγχος του γ2, S2: μετά από απότομο κλείσιμο κανένα «ήρθαν όλοι μαζί» (τα κενά δεν είναι γνωστά). */
    @Test
    fun recoveredResultHasNoGapClaims() {
        val t0 = 1_700_000_000_000L
        Repo.running = "walk"
        Repo.startedAt = t0
        Repo.hrMode = "5s"
        Repo.hr = HrStats(t0).also { h -> for (k in 0 until 600) h.add(100, t0 + k * 1000L) }
        val snap = Repo.captureRun(t0 + 600_000)!!
        Repo.resetExercise()
        assertTrue(Repo.restoreRun(JSONObject(snap.toString()), t0 + 900_000, 5_000))
        // μερικό (FINALIZE)
        val p = Results.build(t0 + 900_000, partialAt = t0 + 600_000)!!.second
        assertFalse(p.has("hrDel"))
        assertFalse(p.has("hrGap"))
        assertEquals(1, p.getInt("hrRec"))
        assertEquals("5s", p.getString("hrMode"))
        // συνέχεια (ATTACH) και κανονικό «Τέλος»: επίσης άγνωστα
        val f = Results.build(t0 + 1_200_000)!!.second
        assertFalse(f.has("hrDel"))
        // κανονική άσκηση χωρίς κλείσιμο: όπως πριν
        Repo.resetExercise()
        Repo.running = "walk"
        Repo.startedAt = t0
        Repo.hrMode = "5s"
        val n = Results.build(t0 + 60_000)!!.second
        assertTrue(n.has("hrDel") && n.has("hrGap") && !n.has("hrRec"))
    }

    /** Έλεγχος του γ2, S3: «έκανες × 8» και για ✓ του κινητού (το κινητό στέλνει την ώρα του σετ). */
    @Test
    fun lastDoneWorksForPhoneTicks() {
        val now = System.currentTimeMillis()
        Repo.applyPhone(LiveSession.parsePhone(
            """{"active":true,"id":"s1","w":"A","name":"Α","start":1,"idx":0,"restEnd":${now + 80_000},
              "items":[{"ex":"a","name":"A","rest":90,"sets":[{"label":"","reps":8,"done":true,"at":${now - 10_000}},{"label":"","reps":8}]}]}""",
        ))
        assertEquals(0 to 0, Repo.phone!!.lastDone(now))
        // παλιό κινητό (χωρίς «at»): απλώς δεν φαίνεται
        Repo.applyPhone(null)
        Repo.applyPhone(LiveSession.parsePhone(
            """{"active":true,"id":"s2","w":"A","name":"Α","start":1,"idx":0,"restEnd":${now + 80_000},
              "items":[{"ex":"a","name":"A","rest":90,"sets":[{"label":"","reps":8,"done":true},{"label":"","reps":8}]}]}""",
        ))
        assertNull(Repo.phone!!.lastDone(now))
    }

    /** Έλεγχος του γ2, S4: η διόρθωση επαναλήψεων λέει ποια άσκηση και ποιο σετ (ώρα). */
    @Test
    fun repsCommandNamesTheSet() {
        val o = repsCmd(1, 2, "db_row", 9, 12_345L)
        assertEquals("reps", o.getString("op"))
        assertEquals("db_row", o.getString("ex"))
        assertEquals(12_345L, o.getLong("at"))
        assertFalse(repsCmd(0, 0, "a", 8, 0).has("at"))
    }
}
