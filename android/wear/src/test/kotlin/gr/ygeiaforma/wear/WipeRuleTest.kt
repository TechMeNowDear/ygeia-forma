package gr.ygeiaforma.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** «Διαγραφή όλων» από το κινητό (έλεγχος 9/11, E3-05): πότε σβήνει το ρολόι. */
class WipeRuleTest {
    @Test
    fun wipesOnceNeverDuringExercise() {
        assertTrue(WipeRule.shouldWipe(at = 2000, done = 0, running = false))
        // Η ίδια διαγραφή δεύτερη φορά (το DataItem μένει): όχι ξανά.
        assertFalse(WipeRule.shouldWipe(at = 2000, done = 2000, running = false))
        // Νέα διαγραφή αργότερα: ναι.
        assertTrue(WipeRule.shouldWipe(at = 3000, done = 2000, running = false))
        // Στη μέση άσκησης: περιμένει (γίνεται στο επόμενο άνοιγμα).
        assertFalse(WipeRule.shouldWipe(at = 3000, done = 2000, running = true))
        // Χαλασμένο/κενό μήνυμα: ποτέ.
        assertFalse(WipeRule.shouldWipe(at = 0, done = 0, running = false))
        assertEquals(0L, WipeRule.parseAt("όχι json"))
        assertEquals(0L, WipeRule.parseAt(null))
        assertEquals(1234L, WipeRule.parseAt("""{"v":1,"at":1234}"""))
        assertEquals("/ygeia/wipe", Paths.WIPE)
    }

    @Test
    fun acksOnceAfterWipeAndDefersWhileRecoverable() {
        // Η διαγραφή έγινε, η απάντηση δεν έφτασε (acked < at): ξανά μόνο η απάντηση, όχι νέα διαγραφή.
        assertTrue(WipeRule.shouldAck(at = 2000, done = 2000, acked = 0))
        assertFalse(WipeRule.shouldWipe(at = 2000, done = 2000, running = false))
        // Απαντήθηκε: τίποτα.
        assertFalse(WipeRule.shouldAck(at = 2000, done = 2000, acked = 2000))
        // Δεν έγινε ακόμα (π.χ. άσκηση): ούτε απάντηση.
        assertFalse(WipeRule.shouldAck(at = 3000, done = 2000, acked = 2000))
        assertEquals(3000L, org.json.JSONObject(WipeRule.ackJson(3000)).getLong("at"))
        assertEquals("/ygeia/wiped", Paths.WIPED)
        // S1: άσκηση που έμεινε μισή (στιγμιότυπο) μετρά ως «τρέχει»: το Link.tryWipe το ελέγχει.
        val link = java.io.File("src/main/kotlin/gr/ygeiaforma/wear/Link.kt").readText()
        assertTrue(link.contains("Repo.readRun(ctx) != null"))
        // M1: σβήνονται και τα DataItems που έγραψε το ρολόι (του τοπικού κόμβου).
        assertTrue(link.contains(".authority(me.id).path(\"/ygeia/\")"))
    }

    @Test
    fun recoveryWindowsAreHalfOpen() {
        // 03-Χ4: «10″ ως το Τέλος» = 10 τιμές [τέλος−10, τέλος). Η τιμή ακριβώς στο «Τέλος» δεν μπαίνει.
        val samples = ArrayList<IntArray>()
        for (t in 50..59) samples.add(intArrayOf(t, 120))
        samples.add(intArrayOf(60, 60)) // η στιγμή του «Τέλος»
        for (t in 115..124) samples.add(intArrayOf(t, 100))
        samples.add(intArrayOf(125, 40)) // ακριβώς στο 65″: εκτός
        val r = HrStats.recovery(samples, 60)!!
        assertEquals(120, r.first)
        assertEquals(100, r.second)
    }
}
