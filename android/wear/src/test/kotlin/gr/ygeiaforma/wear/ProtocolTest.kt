package gr.ygeiaforma.wear

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolTest {
    private val planJson = """
        {"v":1,"hrLimit":140,"today":"A","day":"2026-11-13","at":5,
         "workouts":[
          {"id":"A","name":"Προπόνηση Α","minutes":50,"items":[
            {"ex":"db_press","name":"Πιεστικό με αλτήρες","rest":120,"lo":8,"hi":12,"rir":2,
             "sets":[{"load":10.3,"label":"10,3 kg","reps":8},{"load":10.3,"label":"10,3 kg","reps":8}]},
            {"ex":"reverse_crunch","name":"Ανάποδο crunch","rest":0,"lo":10,"hi":15,"rir":2,
             "sets":[{"label":"","reps":12}]}]},
          {"id":"walk","name":"Περπάτημα","minutes":30,"cardio":{"activity":"walk","name":"Περπάτημα","minutes":30,"note":"χαλαρά"}}]}
    """.trimIndent()

    @Test
    fun parsesPlan() {
        val p = Plan.parse(planJson)!!
        assertEquals(140, p.hrLimit)
        assertEquals("Προπόνηση Α", p.todayWorkout!!.name)
        assertEquals(2, p.todayWorkout!!.items.size)
        assertEquals(10.3, p.todayWorkout!!.items[0].sets[0].load!!, 1e-9)
        assertNull(p.todayWorkout!!.items[1].sets[0].load)
        assertTrue(p.workout("walk")!!.isCardio)
        assertNull(Plan.parse("{χαλασμένο"))
    }

    @Test
    fun weekdayFromDays() {
        val p = Plan.parse(planJson.replace("\"at\":5,", "\"at\":5,\"days\":{\"5\":\"A\",\"2\":\"walk\"},"))!!
        assertEquals("A", p.forWeekday(5)!!.id)
        assertTrue(p.forWeekday(2)!!.isCardio)
        assertNull(p.forWeekday(1))
    }

    @Test
    fun sessionFlow() {
        val p = Plan.parse(planJson)!!
        val s = LiveSession.fromPlan(p.todayWorkout!!, 1_000)
        // σετ 1 → διάλειμμα 120″
        assertEquals(LiveSession.Next.REST, s.tick(1_000))
        assertEquals(121_000, s.restEnd)
        // σετ 2 (τελευταίο της άσκησης) → ρεζέρβα
        assertEquals(LiveSession.Next.ASK_RIR, s.tick(200_000))
        // ρεζέρβα → επόμενη άσκηση με το διάλειμμα της προηγούμενης
        assertEquals(LiveSession.Next.REST, s.answer(2, 201_000).first)
        assertEquals(1, s.idx)
        assertEquals(2, s.items[0].rir)
        // τελευταία άσκηση χωρίς διάλειμμα
        assertEquals(LiveSession.Next.ASK_RIR, s.tick(400_000))
        assertEquals(LiveSession.Next.END, s.answer(3, 401_000).first)
        assertTrue(s.allDone)
        // το πλάνο μένει ανέγγιχτο
        assertFalse(p.todayWorkout!!.items[0].sets[0].done)
    }

    @Test
    fun resultHasAppFormat() {
        val p = Plan.parse(planJson)!!
        val s = LiveSession.fromPlan(p.todayWorkout!!, 1_000)
        s.tick(2_000)
        val hr = HrStats(1_000)
        hr.add(100, 2_000)
        hr.add(120, 15_000)
        hr.add(10, 16_000) // όχι πραγματική τιμή
        val o = s.resultJson(30_000, hr)
        assertEquals("strength", o.getString("kind"))
        assertEquals("A", o.getString("w"))
        val item = o.getJSONArray("items").getJSONObject(0)
        assertEquals("db_press", item.getString("ex"))
        val set0 = item.getJSONArray("log").getJSONObject(0)
        assertEquals(1, set0.getInt("d"))
        assertEquals(10.3, set0.getDouble("l"), 1e-9)
        assertFalse(item.getJSONArray("log").getJSONObject(1).has("d"))
        assertEquals(110, o.getInt("hrAvg"))
        assertEquals(120, o.getInt("hrMax"))
        assertEquals(2, o.getJSONArray("hr").length())
        // Η αρχή της μέτρησης πάει μαζί: το κινητό βάζει τους παλμούς στη σωστή ώρα της προπόνησής του (9/11).
        assertEquals(1_000L, o.getLong("hrT0"))
    }

    @Test
    fun recoveryAfterEnd() {
        val hr = HrStats(0)
        // 120″ περπάτημα στους 120, μετά «Τέλος» και πτώση: 100 στο 1′.
        for (t in 0..120) hr.add(120, t * 1000L)
        hr.markEnd(120_000)
        for (t in 121..190) hr.add(if (t < 170) 110 else 100, t * 1000L)
        val r = hr.recovery()!!
        assertEquals(120, r.first)
        // 55″–65″ μετά το τέλος = 175″–185″: όλα 100.
        assertEquals(100, r.second)
        // Ο μέσος και το υψηλότερο: μόνο ως το «Τέλος».
        assertEquals(120, hr.avg)
        assertEquals(120, hr.max)
        // Στο κινητό πάνε μόνο οι τιμές ως το «Τέλος».
        val o = JSONObject()
        hr.writeTo(o)
        val a = o.getJSONArray("hr")
        assertEquals(120, a.getJSONArray(a.length() - 1).getInt(0))
        // Λίγες τιμές στο 1′ (π.χ. έφυγε το ρολόι από τον καρπό): καμία τιμή.
        val few = HrStats(0)
        for (t in 0..60) few.add(120, t * 1000L)
        few.markEnd(60_000)
        few.add(100, 116_000)
        assertNull(few.recovery())
    }

    @Test
    fun pauseNotInAverage() {
        val hr = HrStats(0)
        hr.add(120, 1000)
        hr.counting = false
        hr.add(80, 2000)
        hr.counting = true
        hr.add(120, 3000)
        assertEquals(120, hr.avg)
        assertEquals(3, hr.samples.size)
    }

    @Test
    fun hrEverySecondAndCap() {
        val hr = HrStats(0)
        for (s in 0 until 120) hr.add(100 + (s % 2), s * 1000L)
        // Μία τιμή το δευτερόλεπτο (ως #87: μία ανά 10″).
        assertEquals(120, hr.samples.size)
        // Πολύ μεγάλη άσκηση: μισές τιμές, μέσος κάθε ζευγαριού, ίδια διάρκεια.
        val big = List(HrStats.MAX_SAMPLES + 2) { intArrayOf(it, if (it % 2 == 0) 100 else 102) }
        val fit = HrStats.fit(big)
        assertTrue(fit.size <= HrStats.MAX_SAMPLES)
        assertEquals(101, fit[0][1])
        assertEquals(0, fit[0][0])
        assertEquals(big.last()[0] - 1, fit.last()[0])
    }

    @Test
    fun phoneSession() {
        assertNull(LiveSession.parsePhone("""{"active":false}"""))
        val s = LiveSession.parsePhone(
            """{"active":true,"id":"s1","w":"A","name":"Προπόνηση Α","start":1,"idx":0,"restEnd":99,
               "items":[{"ex":"db_press","name":"Π","rest":90,"sets":[{"label":"10,3 kg","reps":8,"done":true},{"label":"10,3 kg","reps":8}]}]}""",
        )
        assertNotNull(s)
        assertTrue(s!!.phone)
        assertEquals(1, s.current!!.nextSet)
        assertEquals(99, s.restEnd)
    }

    /** «Ελεύθερη άσκηση» του κινητού χωρίς ασκήσεις (9/11): κανένα σφάλμα, τίποτα δεν στέλνεται ως ✓. */
    @Test
    fun emptyFreePhoneSession() {
        val s = LiveSession.parsePhone("""{"active":true,"id":"s2","w":"_free","name":"Ελεύθερη άσκηση","start":1,"idx":0,"items":[]}""")!!
        assertNull(s.current)
        assertEquals(LiveSession.Next.END, s.tick(5))
        assertEquals(LiveSession.Next.END, s.skip())
        assertEquals(0, s.setsDone)
        Repo.applyPhone(s)
        Repo.applyPhone(null)
    }

    @Test
    fun alarm() {
        val a = HrAlarm(140)
        assertFalse(a.feed(139, 0))
        assertFalse(a.feed(141, 1_000)) // πάνω, αλλά όχι ακόμα 5″
        assertFalse(a.feed(142, 4_000))
        assertTrue(a.feed(142, 6_000)) // 5″ πάνω: ανάβει
        assertFalse(a.feed(143, 11_000)) // ήδη αναμμένο
        assertTrue(a.on)
        assertTrue(a.feed(143, 36_000)) // ακόμα πάνω μετά από 30″: ξανά δόνηση
        a.feed(137, 40_000)
        assertTrue(a.on) // όχι αρκετά κάτω
        a.feed(134, 45_000)
        assertFalse(a.on)
        // μία στιγμιαία τιμή δεν ανάβει
        assertFalse(a.feed(150, 50_000))
        assertFalse(a.feed(130, 51_000))
        assertFalse(a.feed(150, 52_000))
        assertFalse(a.on)
        val none = HrAlarm(null)
        assertFalse(none.feed(200, 0))
        assertFalse(none.feed(200, 60_000))
    }

    @Test
    fun planZone() {
        // Παλιό κινητό: χωρίς «zone», καμία δόνηση ζώνης.
        assertNull(Plan.parse(planJson)!!.zone)
        val withZone = planJson.replace("\"at\":5,", "\"at\":5,\"zone\":{\"lo\":108,\"hi\":131,\"up\":true,\"down\":false},")
        assertEquals(WalkZone(108, 131, up = true, down = false), Plan.parse(withZone)!!.zone)
        // Άκυρη ζώνη: αγνοείται, το πρόγραμμα διαβάζεται κανονικά.
        val bad = planJson.replace("\"at\":5,", "\"at\":5,\"zone\":{\"lo\":140,\"hi\":120},")
        assertNull(Plan.parse(bad)!!.zone)
        assertEquals(140, Plan.parse(bad)!!.hrLimit)
        assertEquals(WalkZone(100, 120, up = false, down = true), WalkZone.parse(WalkZone(100, 120, up = false, down = true).toJson()))
    }

    @Test
    fun zoneAlarmUp() {
        val z = ZoneAlarm(holdMs = 20_000L)
        z.start(WalkZone(108, 131), 0)
        // Τα πρώτα 5′ τίποτα, όσο ψηλά κι αν είναι.
        for (t in 0..290 step 10) assertEquals(ZoneAlarm.Buzz.NONE, z.feed(150, t * 1000L))
        // Μετά: 20″ συνεχώς πάνω από το 131.
        val t0 = 400_000L
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(120, t0))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(135, t0 + 1_000))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(136, t0 + 15_000))
        assertEquals(ZoneAlarm.Buzz.UP, z.feed(136, t0 + 21_000))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(137, t0 + 60_000))
        // Ακόμα πάνω μετά από 2′: ξανά.
        assertEquals(ZoneAlarm.Buzz.UP, z.feed(137, t0 + 141_000))
        // Κάτω από 131 − 3: ξαναοπλίζεται· νέο ανέβασμα θέλει πάλι 20″.
        z.feed(127, t0 + 150_000)
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(134, t0 + 160_000))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(134, t0 + 170_000))
        assertEquals(ZoneAlarm.Buzz.UP, z.feed(134, t0 + 180_000))
        assertEquals(3, z.ups)
    }

    @Test
    fun zoneAlarmShortHillAndOrder() {
        val z = ZoneAlarm(holdMs = 20_000L)
        z.start(WalkZone(108, 131), 0)
        val t0 = 600_000L
        // Ανηφόρα 15″: καμία δόνηση.
        z.feed(140, t0)
        z.feed(140, t0 + 15_000)
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(125, t0 + 16_000))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(140, t0 + 30_000))
        // Παλιότερη τιμή από άλλη πηγή: αγνοείται.
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(140, t0 + 10_000))
        // Σταθεροί παλμοί χωρίς νέα τιμή (αισθητήρας που στέλνει αλλαγές): μετρούν.
        assertEquals(ZoneAlarm.Buzz.UP, z.steady(140, t0 + 51_000))
        // Παύση: οι 20″ ξαναρχίζουν.
        val y = ZoneAlarm(holdMs = 20_000L)
        y.start(WalkZone(108, 131), 0)
        y.feed(140, t0)
        y.hold()
        assertEquals(ZoneAlarm.Buzz.NONE, y.feed(140, t0 + 25_000))
        assertEquals(ZoneAlarm.Buzz.UP, y.feed(140, t0 + 45_000))
    }

    @Test
    fun zoneAlarmDownOnlyWhenOn() {
        val off = ZoneAlarm(holdMs = 20_000L)
        off.start(WalkZone(108, 131), 0)
        for (t in 0..20) assertEquals(ZoneAlarm.Buzz.NONE, off.feed(95, 400_000L + t * 10_000L))
        val on = ZoneAlarm(holdMs = 20_000L)
        on.start(WalkZone(108, 131, up = true, down = true), 0)
        val t0 = 400_000L
        assertEquals(ZoneAlarm.Buzz.NONE, on.feed(100, t0))
        assertEquals(ZoneAlarm.Buzz.NONE, on.feed(100, t0 + 50_000))
        assertEquals(ZoneAlarm.Buzz.DOWN, on.feed(100, t0 + 61_000))
        assertEquals(ZoneAlarm.Buzz.NONE, on.feed(100, t0 + 200_000))
        assertEquals(ZoneAlarm.Buzz.DOWN, on.feed(100, t0 + 361_000))
        // Χωρίς ζώνη: τίποτα.
        val none = ZoneAlarm(holdMs = 20_000L)
        none.start(null, 0)
        assertFalse(none.active)
        assertEquals(ZoneAlarm.Buzz.NONE, none.feed(200, 900_000))
        // Ζώνη με κλειστές και τις δύο δονήσεις: δεν χρειάζεται αισθητήρας.
        val quiet = ZoneAlarm(holdMs = 20_000L)
        quiet.start(WalkZone(108, 131, up = false, down = false), 0)
        assertFalse(quiet.active)
    }

    @Test
    fun alarmFromOneBatch() {
        // Πακέτο με 5 τιμές ανά 1″: ο χρόνος κάθε τιμής μετράει, όχι το πλήθος των πακέτων.
        val a = HrAlarm(140)
        var fired = false
        for (i in 0..5) fired = fired or a.feed(145, 100_000L + i * 1000)
        assertTrue(fired)
    }

    @Test
    fun rirStaysWithFinishedExercise() {
        val p = Plan.parse(planJson)!!
        val s = LiveSession.fromPlan(p.todayWorkout!!, 1_000)
        s.tick(1_000)
        assertEquals(LiveSession.Next.ASK_RIR, s.tick(200_000))
        // στο μεταξύ το κινητό πήγε ήδη στην επόμενη άσκηση
        s.idx = 1
        val (_, i) = s.answer(1, 201_000)
        assertEquals(0, i)
        assertEquals(1, s.items[0].rir)
        assertNull(s.items[1].rir)
        assertEquals(-1, s.rirIdx)
    }

    @Test
    fun sensorTimeAndGaps() {
        // τιμή 3″ πριν (σε ns από την εκκίνηση) → 3″ πριν σε ώρα· ποτέ στο μέλλον
        assertEquals(97_000L, sensorWallTime(7_000_000_000L, 100_000L, 10_000_000_000L))
        assertEquals(100_000L, sensorWallTime(11_000_000_000L, 100_000L, 10_000_000_000L))
        val g = GapMeter()
        assertEquals(0, g.maxGapSec)
        g.mark(1_000)
        g.mark(6_000)
        g.mark(11_200)
        assertEquals(5, g.maxGapSec)
        g.mark(90_000)
        assertEquals(79, g.maxGapSec)
        g.close(200_000)
        assertEquals(110, g.maxGapSec)
    }

    @Test
    fun alarmTwoSourcesAndSteady() {
        val a = HrAlarm(140)
        // αισθητήρας (νεότερες τιμές) και Health Services (πακέτο με παλιότερες): οι παλιές αγνοούνται
        assertFalse(a.feed(150, 10_000))
        assertFalse(a.feed(100, 8_000))
        // σταθεροί παλμοί χωρίς νέα τιμή: μετά από 5″ ανάβει
        assertFalse(a.steady(150, 12_000))
        assertTrue(a.steady(150, 15_000))
        assertTrue(a.on)
        // ο αισθητήρας σώπασε: οι νεότερες του Health Services περνούν
        assertTrue(a.feed(152, 46_000))
    }

    @Test
    fun noHeartRateEverWithLimitBuzzesOnce() {
        // V-A-04: άσκηση με όριο, κανένας παλμός ποτέ (π.χ. το Health Services αρνήθηκε): πριν, καμία δόνηση.
        val s = HrSilence()
        val t0 = 1_000_000L
        assertFalse(s.check(t0 + 10_000, t0, 0, live = false, hasLimit = true, paused = false, lostMs = 15_000))
        assertNull(s.state)
        assertTrue(s.check(t0 + 30_000, t0, 0, live = false, hasLimit = true, paused = false, lostMs = 15_000))
        assertEquals(HrSilence.Silence.NEVER, s.state)
        // μία φορά, όχι κάθε δευτερόλεπτο
        for (k in 31..200) assertFalse(s.check(t0 + k * 1_000L, t0, 0, false, true, false, 15_000))
        assertEquals(HrSilence.Silence.NEVER, s.state)
    }

    @Test
    fun noHeartRateWithoutLimitOrPausedDoesNotBuzz() {
        val t0 = 1_000_000L
        val a = HrSilence()
        assertFalse(a.check(t0 + 60_000, t0, 0, live = false, hasLimit = false, paused = false, lostMs = 15_000))
        // η οθόνη ξέρει ότι δεν μετριούνται, ακόμα και χωρίς όριο
        assertEquals(HrSilence.Silence.NEVER, a.state)
        val b = HrSilence()
        assertFalse(b.check(t0 + 60_000, t0, 0, live = false, hasLimit = true, paused = true, lostMs = 15_000))
        // μετά την παύση: δονείται
        assertTrue(b.check(t0 + 61_000, t0, 0, live = false, hasLimit = true, paused = false, lostMs = 15_000))
    }

    @Test
    fun lostHeartRateBuzzesAgainOnlyAfterRecovery() {
        val s = HrSilence()
        val t0 = 1_000_000L
        // ήρθαν παλμοί: τίποτα
        assertFalse(s.check(t0 + 5_000, t0, t0 + 5_000, live = true, hasLimit = true, paused = false, lostMs = 15_000))
        // χάθηκαν: μετά από 15″ μία δόνηση (LOST, όχι NEVER)
        assertFalse(s.check(t0 + 19_000, t0, t0 + 5_000, false, true, false, 15_000))
        assertTrue(s.check(t0 + 20_000, t0, t0 + 5_000, false, true, false, 15_000))
        assertEquals(HrSilence.Silence.LOST, s.state)
        assertFalse(s.check(t0 + 60_000, t0, t0 + 5_000, false, true, false, 15_000))
        // ξαναήρθαν και ξαναχάθηκαν: ξανά μία
        assertFalse(s.check(t0 + 70_000, t0, t0 + 70_000, live = true, hasLimit = true, paused = false, lostMs = 15_000))
        assertNull(s.state)
        assertTrue(s.check(t0 + 86_000, t0, t0 + 70_000, false, true, false, 15_000))
        assertFalse(s.check(t0 + 87_000, t0, t0 + 70_000, false, true, false, 15_000))
        s.reset()
        assertNull(s.state)
    }

    /** Έλεγχος 9/11 (W3-11): παύση και «Τέλος» κρίνονται με τον χρόνο της τιμής, όχι με την ώρα που έφτασε. */
    @Test
    fun pauseAndEndBySampleTime() {
        val hr = HrStats(0)
        // πριν την παύση (στα 10″) φτάνουν μόνο οι τιμές ως τα 7″
        for (t in 0..7) hr.add(120, t * 1000L)
        hr.pause(10_000)
        // το πακέτο με τα 8″–9″ φτάνει μετά την παύση: μετρά (είναι πριν από αυτήν)
        hr.add(150, 8_000)
        hr.add(150, 9_000)
        // τιμές μέσα στην παύση: όχι
        hr.add(80, 12_000)
        hr.resume(20_000)
        hr.add(120, 21_000)
        assertEquals(150, hr.max)
        // «Τέλος» στα 30″, τιμή των 29″ που φτάνει μετά: μετρά· των 31″ όχι
        hr.markEnd(30_000)
        hr.add(160, 29_000)
        hr.add(170, 31_000)
        assertEquals(160, hr.max)
        // 8 × 120 + 2 × 150 + 120 + 160 = 1540 / 12
        assertEquals(Math.round(1540.0 / 12).toInt(), hr.avg)
    }

    /** Έλεγχος 9/11 (V-A-03): η κατάσταση των παλμών ξαναστήνεται ακριβώς· ξαναπαράδοση παλιών τιμών δεν μετρά διπλά. */
    @Test
    fun hrStateRoundTripAndNoDoubleCount() {
        val hr = HrStats(1_000)
        for (t in 0..59) hr.add(100 + t % 5, 1_000 + t * 1000L)
        hr.pause(70_000)
        val back = HrStats.fromState(JSONObject(hr.toState().toString()))
        assertEquals(hr.avg, back.avg)
        assertEquals(hr.max, back.max)
        assertEquals(hr.samples.size, back.samples.size)
        assertEquals(1_000L, back.start)
        // οι ίδιες τιμές ξανά (κρυφή μνήμη του Health Services): δεν αλλάζουν τίποτα
        for (t in 0..59) back.add(200, 1_000 + t * 1000L)
        assertEquals(hr.avg, back.avg)
        assertEquals(hr.samples.size, back.samples.size)
        // η παύση έμεινε: τιμή μέσα της δεν μετρά
        back.add(200, 75_000)
        assertEquals(hr.max, back.max)
    }

    /**
     * Έλεγχος 9/11 (V-A-19): σταθερά 5 km/h (12′00″ ανά km), απόσταση σε πακέτα ανά 150″ (σβηστή οθόνη). Πριν: 12′30″ και
     * 10′00″. Τώρα κάθε km 12′00″, με παρεμβολή στους χρόνους των τιμών.
     */
    @Test
    fun kmSplitsInterpolatedWithBatchedDistance() {
        val t0 = 1_700_000_000_000L
        val sp = SplitTracker(t0)
        val speed = 5000.0 / 3600.0 // m/s
        var t = 0
        while (t <= 3750) {
            sp.update(speed * t, t0 + t * 1000L, t.toDouble())
            t += 150
        }
        assertEquals(5, sp.splits.size)
        for ((k, s) in sp.splits.withIndex()) {
            assertEquals("ενεργός χρόνος km ${k + 1}", 720L * (k + 1), s[0])
            assertEquals("ώρα km ${k + 1}", t0 + 720_000L * (k + 1), s[1])
        }
        // Πακέτο που περνά δύο km μαζί: και τα δύο στη σωστή ώρα.
        val two = SplitTracker(0)
        two.update(500.0, 360_000, 360.0)
        two.update(2500.0, 1_800_000, 1800.0)
        assertEquals(2, two.splits.size)
        assertEquals(720L, two.splits[0][0])
        assertEquals(1440L, two.splits[1][0])
        // Μικρότερη ή χαλασμένη τιμή: τίποτα.
        two.update(Double.NaN, 1_900_000, 1900.0)
        two.update(100.0, 1_900_000, 1900.0)
        assertEquals(2, two.splits.size)
        // Κατάσταση μπρος-πίσω.
        val back = SplitTracker.fromState(JSONObject(two.toState().toString()), 0)
        back.update(3000.0, 2_160_000, 2160.0)
        assertEquals(3, back.splits.size)
        assertEquals(2160L, back.splits[2][0])
    }

    /** W3-12: ο χρόνος στην οθόνη από το σημείο ελέγχου (κάθε δευτερόλεπτο)· σε παύση σταθερός. W3-04: μηδέν σε elapsedRealtime. */
    @Test
    fun activeTimeFromCheckpointAndStopwatchZero() {
        assertEquals(125L, activeSecAt(120_000, 1_000_000, true, 1_005_000, 0))
        assertEquals(120L, activeSecAt(120_000, 1_000_000, false, 1_005_000, 0))
        assertEquals(42L, activeSecAt(0, 0, true, 5_000_000, 42))
        // τρέχει από το σημείο ελέγχου (πριν ήταν σε παύση): πριν από αυτό ο ενεργός χρόνος ήταν ίδιος
        assertEquals(120.0, activeAtWall(120_000, 1_000_000, true, 990_000, 0), 1e-9)
        assertEquals(130.0, activeAtWall(120_000, 1_000_000, true, 1_010_000, 0), 1e-9)
        assertEquals(110.0, activeAtWall(120_000, 1_000_000, false, 990_000, 0), 1e-9)
        // 3 μέρες αναμμένο ρολόι, 10′ άσκηση: το μηδέν είναι 10′ πριν από το «τώρα» της εκκίνησης, όχι ώρα 1970.
        val el = 3L * 24 * 3600 * 1000
        assertEquals(el - 600_000, stopwatchZero(el, 600_000))
    }

    /** V-A-03: συνέχεια αν το Health Services κρατά την άσκηση· βάρη ρολογιού πρόσφατα: συνέχεια· αλλιώς μερικό. */
    @Test
    fun recoveryDecision() {
        val now = 10_000_000L
        assertEquals(Recovery.Action.ATTACH, Recovery.decide(true, "walk", false, false, now - 60_000, now))
        assertEquals(Recovery.Action.FINALIZE, Recovery.decide(false, "walk", false, false, now - 60_000, now))
        assertEquals(Recovery.Action.RESUME, Recovery.decide(false, "strength", false, true, now - 60_000, now))
        assertEquals(Recovery.Action.FINALIZE, Recovery.decide(false, "strength", false, true, now - 20 * 60_000, now))
        assertEquals(Recovery.Action.FINALIZE, Recovery.decide(false, "strength", true, false, now - 60_000, now))
        assertEquals(Recovery.Action.ATTACH, Recovery.decide(true, "strength", true, false, now - 60_000, now))
    }

    /** V-A-08: νεότερη μορφή = δεν διαβάζεται· χωρίς «v» = 1. V-A-13: id και για τους παλμούς χωρίς «id». */
    @Test
    fun versionAndPendingIds() {
        assertFalse(Proto.tooNew("""{"v":1}"""))
        assertFalse(Proto.tooNew("""{"active":false}"""))
        assertTrue(Proto.tooNew("""{"v":2,"hrLimit":120}"""))
        assertFalse(Proto.tooNew("χαλασμένο"))
        assertEquals("hrs1", Repo.pendingId(JSONObject().put("kind", "hr").put("sid", "s1")))
        assertEquals("walk5", Repo.pendingId(JSONObject().put("kind", "cardio").put("id", "walk5")))
        assertNull(Repo.pendingId(JSONObject().put("kind", "hr")))
        val ack = Link.ackJson(140, 77)
        assertEquals(140, ack.getInt("lim"))
        assertEquals(1, ack.getInt("v"))
        assertEquals(0, Link.ackJson(null, 0).getInt("lim"))
    }

    /**
     * W3-14: η ώρα του ρολογιού πάει 20″ πίσω στη μέση. Με ώρα τοίχου η ειδοποίηση «τυφλωνόταν» 20″· με τον μονότονο
     * χρόνο (που δίνει πλέον η υπηρεσία) δονείται κανονικά μετά από 5″.
     */
    @Test
    fun alarmNotBlindedByClockGoingBack() {
        val wall = HrAlarm(140)
        assertFalse(wall.feed(150, 100_000))
        // ώρα τοίχου 20″ πίσω: οι επόμενες 15″ τιμές αγνοούνται
        var buzzWall = false
        for (k in 1..15) buzzWall = buzzWall || wall.feed(150, 80_000L + k * 1000)
        assertFalse(buzzWall)
        val mono = HrAlarm(140)
        assertFalse(mono.feed(150, 5_000))
        var buzz = false
        for (k in 1..15) buzz = buzz || mono.feed(150, 5_000L + k * 1000)
        assertTrue(buzz)
    }

    @Test
    fun ambientStates() {
        assertTrue(isAmbientState(android.view.Display.STATE_DOZE))
        assertTrue(isAmbientState(android.view.Display.STATE_DOZE_SUSPEND))
        assertTrue(isAmbientState(android.view.Display.STATE_OFF))
        assertFalse(isAmbientState(android.view.Display.STATE_ON))
    }

    @Test
    fun formats() {
        assertEquals("1:04", clock(64))
        assertEquals("1:02:05", clock(3725))
        assertEquals("2,18", km(2180.0))
        assertEquals("11:15 /km", pace(2000.0, 1350))
        // 659,5″ ανά km στρογγυλεύεται σε 11:00, ποτέ «10:60».
        assertEquals("11:00 /km", pace(2000.0, 1319))
        assertEquals("—", pace(10.0, 100))
        assertTrue(JSONObject().put("x", 1).has("x"))
    }

    // ------------------------------------------------------------------ τελικός έλεγχος, Συμβούλιο 1

    /** Σ1: τι γίνεται με μια τιμή παλμών ανάλογα με το τι δηλώνει το ρολόι για αυτήν. */
    @Test
    fun hrQualityFromSensorStatus() {
        assertEquals(HrQuality.BAD, hrQualityOf(noContact = true, unreliable = false, lowAccuracy = false))
        assertEquals(HrQuality.BAD, hrQualityOf(noContact = false, unreliable = true, lowAccuracy = false))
        // «Αναξιόπιστη» νικά το «χαμηλή ακρίβεια» (δεν γίνεται ποτέ «απλώς χαμηλή»).
        assertEquals(HrQuality.BAD, hrQualityOf(noContact = false, unreliable = true, lowAccuracy = true))
        assertEquals(HrQuality.LOW, hrQualityOf(noContact = false, unreliable = false, lowAccuracy = true))
        // Μέτρια/υψηλή ακρίβεια, ή ρολόι που δεν δηλώνει τίποτα: όπως πριν.
        assertEquals(HrQuality.OK, hrQualityOf(noContact = false, unreliable = false, lowAccuracy = false))
    }

    /** Σ1: η καταμέτρηση πηγαίνει στο κινητό μέσα στο «diag», χωρίς νέο πεδίο και χωρίς να αλλάζει το παλιό κείμενο. */
    @Test
    fun hrQualityCountInDiag() {
        val none = HrQualityCount()
        assertEquals("", none.text())
        // Καμία τιμή: το «diag» ακριβώς όπως πριν (το παλιό κινητό και οι παλιές δοκιμές δεν βλέπουν διαφορά).
        assertEquals("5s=1 wake=0", none.withDiag("5s=1 wake=0"))
        assertEquals("", none.withDiag(""))

        val q = HrQualityCount()
        repeat(5400) { q.add(HrQuality.OK) }
        repeat(120) { q.add(HrQuality.LOW) }
        repeat(15) { q.add(HrQuality.BAD) }
        assertEquals(5535, q.total)
        assertEquals("q=5400/120/15", q.text())
        assertEquals("5s=1 wake=1 q=5400/120/15", q.withDiag("5s=1 wake=1"))
        assertEquals("q=5400/120/15", q.withDiag(""))
        // Το κινητό κρατά ως 40 χαρακτήρες του «diag» (training_store.dart): και η χειρότερη περίπτωση χωρά.
        val big = HrQualityCount()
        repeat(99_999) { big.add(HrQuality.OK) }
        repeat(9_999) { big.add(HrQuality.LOW) }
        repeat(9_999) { big.add(HrQuality.BAD) }
        assertTrue(big.withDiag("5s=1 wake=1").length <= 40)
    }

    /** μ1: και η επανάληψη της δόνησης ζώνης θέλει 20″ συνεχώς πάνω (1′ κάτω), όπως υπόσχεται η οθόνη. */
    @Test
    fun zoneAlarmRepeatNeedsHold() {
        val z = ZoneAlarm(holdMs = 20_000L)
        z.start(WalkZone(109, 130), 0)
        val t0 = 400_000L
        // 25″ πάνω από το 130: μία δόνηση στα 20″.
        var ups = 0
        for (s in 0..24) if (z.feed(133, t0 + s * 1000L) == ZoneAlarm.Buzz.UP) ups++
        assertEquals(1, ups)
        // Πίσω στη ζώνη, αλλά όχι 3 παλμούς κάτω από το πάνω όριο (128–130): δεν «ξαναοπλίζει».
        for (s in 25..144) assertEquals(ZoneAlarm.Buzz.NONE, z.feed(128 + s % 3, t0 + s * 1000L))
        // 2′05″ μετά τη δόνηση, ΜΙΑ τιμή πάνω από το όριο: όχι δόνηση (πριν από τη διόρθωση: δόνηση αμέσως).
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(131, t0 + 145_000L))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(129, t0 + 146_000L))
        // Αν όμως μείνει πάνω 20″ συνεχώς, δονείται ξανά (έχουν περάσει τα 2′).
        for (s in 150..169) assertEquals(ZoneAlarm.Buzz.NONE, z.feed(134, t0 + s * 1000L))
        assertEquals(ZoneAlarm.Buzz.UP, z.feed(134, t0 + 170_000L))
        assertEquals(2, z.ups)

        // Το ίδιο προς τα κάτω: 1′ συνεχώς κάτω και για την επανάληψη (5′ μετά).
        val d = ZoneAlarm(holdMs = 20_000L)
        d.start(WalkZone(109, 130, up = true, down = true), 0)
        assertEquals(ZoneAlarm.Buzz.NONE, d.feed(100, t0))
        assertEquals(ZoneAlarm.Buzz.DOWN, d.feed(100, t0 + 60_000L))
        // Γυρίζει στη ζώνη χωρίς να ξαναοπλίσει (109–111 < 109 + 3) και 5′ μετά μία τιμή κάτω: όχι δόνηση.
        assertEquals(ZoneAlarm.Buzz.NONE, d.feed(110, t0 + 70_000L))
        assertEquals(ZoneAlarm.Buzz.NONE, d.feed(105, t0 + 365_000L))
        // Μένει κάτω 1′: δονείται.
        assertEquals(ZoneAlarm.Buzz.NONE, d.feed(105, t0 + 400_000L))
        assertEquals(ZoneAlarm.Buzz.DOWN, d.feed(105, t0 + 425_000L))
        assertEquals(2, d.downs)
    }
}
