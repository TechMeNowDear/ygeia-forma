package gr.ygeiaforma.wear

import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Αποφάσεις 20/11: «Πόσες περίπου;» και στο ρολόι. Μετά το «4+» του «Πρώτο σετ», 4 / 5–7 / 8–12 / 13+ στέλνονται ως 4, 6,
 * 10, 15 (όπως το κινητό, Κ5-H1)· τίποτα πάνω από 15. Δοκιμαστικά νούμερα.
 */
class FirstMoreTest {
    private val t0 = 1_700_000_000_000L

    private fun set(reps: Int) = JSONObject().put("label", "10,3 kg").put("load", 10.3).put("reps", reps)

    private fun phone(id: String): LiveSession =
        LiveSession.parsePhone(
            JSONObject().put("v", 1).put("active", true).put("id", id).put("w", "A").put("name", "Α").put("start", t0)
                .put("idx", 0).put("restEnd", 0).put(
                    "items",
                    JSONArray(
                        listOf(
                            JSONObject().put("ex", "db_press").put("name", "db_press").put("rest", 90).put("lo", 8).put("hi", 12)
                                .put("rir", 2).put("sets", JSONArray(listOf(set(10), set(10), set(10)))).put("f", 1),
                        ),
                    ),
                ).toString(),
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
    fun before() = clean()

    @After
    fun after() = clean()

    private fun answer(v: Int): Int {
        clean()
        Repo.applyPhone(phone("s$v"))
        Repo.running = "strength"
        Repo.runningPhone = true
        Repo.runningSid = "s$v"
        Repo.startedAt = t0
        Repo.hr = HrStats(t0).also { for (k in 0..30) it.add(110, t0 + k * 1000L) }
        val p = Repo.phone!!
        p.tick(t0 + 60_000)
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        val a = p.answerAny(v, t0 + 65_000)
        assertTrue(a.first)
        return a.rir1!!.getInt("v")
    }

    @Test
    fun valuesLikeThePhone() {
        assertEquals(listOf(4, 6, 10, 15), FIRST_MORE.map { it.second })
        assertEquals(listOf("4", "5–7", "8–12", "13+"), FIRST_MORE.map { it.first })
        for (v in listOf(4, 6, 10, 15)) assertEquals(v, answer(v))
        assertEquals(FIRST_MAX, answer(40))
        assertEquals(-1, answer(-1))
    }
}
