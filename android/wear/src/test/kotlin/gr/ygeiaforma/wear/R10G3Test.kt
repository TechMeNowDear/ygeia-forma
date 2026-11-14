package gr.ygeiaforma.wear

import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Γύρος 10, g3 (ρολόι), R10-B5-1: η απάντηση στο «Πρώτο σετ» που δόθηκε στο ρολόι ξαναστέλνεται («rir1») μόνο με τον ίδιο
 * κανόνα που έχει το κινητό (`firstPending`: κανένα σετ μετά το 1ο δεν έχει γίνει), όπως τον ξέρει το ρολόι, και όχι όσο
 * οι επαναλήψεις του 1ου σετ που άλλαξες εδώ δεν έχουν φτάσει. Καλεί τον ίδιο τον κώδικα (Repo, LiveSession), όχι έλεγχο
 * κειμένου. Οι τιμές που περιμένουμε βγαίνουν από τον κανόνα. Όλα τα νούμερα είναι δοκιμαστικά.
 */
class R10G3Test {
    private val t0 = 1_700_000_000_000L

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

    /**
     * Το κινητό είδε το ✓ του 1ου σετ αλλά όχι την απάντηση («f» ακόμα)· εδώ γίνεται ✓ στο 2ο σετ, που το κινητό δεν έχει
     * δει. Ξαναστέλνεται μόνο το ✓, ΟΧΙ η «rir1»: αλλιώς, αν η «rir1» έφτανε πρώτη, το κινητό θα άλλαζε το βάρος του 2ου σετ
     * (βαθμονόμηση) και το ✓ που ακολουθεί θα το έγραφε με βάρος που δεν σηκώθηκε. Η απάντηση μένει για το αποτέλεσμα («fr»).
     */
    @Test
    fun noFirstAnswerResendOnceALaterSetIsDoneHere() {
        Repo.applyPhone(phone("sA", item("db_press", true, set(10), set(10), set(10))))
        runningPhone("sA")
        val p = Repo.phone!!
        assertEquals(LiveSession.Next.REST, p.tick(t0 + 60_000))
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        p.answerAny(4, t0 + 65_000)
        // Το κινητό είδε το ✓, όχι την απάντηση: ξαναστέλνεται, όπως πριν (R9-A8-3).
        Repo.applyPhone(phone("sA", item("db_press", true, set(10, done = true, at = t0 + 60_000), set(10), set(10))))
        assertEquals(listOf(Triple(0, "db_press", 4)), Repo.pendingFirst)
        // ✓ του 2ου σετ εδώ (το κινητό δεν το είδε): εκκρεμεί το ✓, όχι η απάντηση.
        assertEquals(LiveSession.Next.REST, Repo.phone!!.tick(t0 + 160_000))
        assertEquals(listOf(0 to 1), Repo.pendingTicks)
        assertTrue(Repo.pendingFirst.isEmpty())
        assertEquals(4, Repo.phone!!.firstAns["db_press"])
        // Το κινητό είδε και το 2ο σετ (εκεί η ερώτηση δεν εκκρεμεί πια, χωρίς «f»): τίποτα δεν ξαναστέλνεται.
        Repo.applyPhone(
            phone("sA", item("db_press", false, set(10, done = true, at = t0 + 60_000), set(10, done = true, at = t0 + 160_000), set(10))),
        )
        assertTrue(Repo.pendingTicks.isEmpty())
        assertTrue(Repo.pendingFirst.isEmpty())
        assertEquals(4, Repo.phone!!.firstAns["db_press"])
    }

    /**
     * Επαναλήψεις του 1ου σετ που διόρθωσες εδώ (10 → 12) και το κινητό δεν έχει ακόμα: η βαθμονόμηση τις χρειάζεται, άρα
     * η «rir1» περιμένει. Μόλις το κινητό δείξει τις 12, ξαναστέλνεται.
     */
    @Test
    fun noFirstAnswerResendWhileTheFirstSetRepsHaveNotArrived() {
        Repo.applyPhone(phone("sB", item("db_press", true, set(10), set(10), set(10))))
        runningPhone("sB")
        val p = Repo.phone!!
        p.tick(t0 + 60_000)
        assertTrue(p.askFirst(0, 0, LiveSession.Next.REST))
        p.answerAny(4, t0 + 65_000)
        Repo.applyPhone(phone("sB", item("db_press", true, set(10, done = true, at = t0 + 60_000), set(10), set(10))))
        assertEquals(listOf(Triple(0, "db_press", 4)), Repo.pendingFirst)
        Repo.phone!!.items[0].sets[0].edit(12)
        assertEquals(listOf(0 to 0), Repo.pendingReps)
        assertTrue(Repo.pendingFirst.isEmpty())
        Repo.applyPhone(phone("sB", item("db_press", true, set(12, done = true, at = t0 + 60_000), set(10), set(10))))
        assertTrue(Repo.pendingReps.isEmpty())
        assertEquals(listOf(Triple(0, "db_press", 4)), Repo.pendingFirst)
    }
}
