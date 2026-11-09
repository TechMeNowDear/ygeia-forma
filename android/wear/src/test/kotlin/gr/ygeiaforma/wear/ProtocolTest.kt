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
    fun formats() {
        assertEquals("1:04", clock(64))
        assertEquals("1:02:05", clock(3725))
        assertEquals("2,18", km(2180.0))
        assertEquals("11′15″", pace(2000.0, 1350))
        assertEquals("—", pace(10.0, 100))
        assertTrue(JSONObject().put("x", 1).has("x"))
    }
}
