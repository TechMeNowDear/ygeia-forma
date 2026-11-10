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
