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
        {"v":1,"approved":true,"hrLimit":140,"today":"A","day":"2026-11-13","at":5,
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
        assertTrue(p.approved)
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
        assertEquals(LiveSession.Next.REST, s.answer(2, 201_000))
        assertEquals(1, s.idx)
        assertEquals(2, s.items[0].rir)
        // τελευταία άσκηση χωρίς διάλειμμα
        assertEquals(LiveSession.Next.ASK_RIR, s.tick(400_000))
        assertEquals(LiveSession.Next.END, s.answer(3, 401_000))
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

    @Test
    fun alarm() {
        val a = HrAlarm(140)
        assertFalse(a.feed(139))
        assertFalse(a.feed(141)) // μία τιμή δεν αρκεί
        assertTrue(a.feed(142)) // δεύτερη: ανάβει
        assertFalse(a.feed(143)) // ήδη αναμμένο
        assertTrue(a.on)
        a.feed(137)
        assertTrue(a.on) // όχι αρκετά κάτω
        a.feed(134)
        assertFalse(a.on)
        val none = HrAlarm(null)
        assertFalse(none.feed(200))
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
