package gr.ygeiaforma.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Έλεγχος 13/11, round 7 (f9, κείμενα του TalkBack στο ρολόι, R7-U4-2): ενικός με το 1. Οι τιμές βγαίνουν από τον κανόνα
 * της γλώσσας («1 επανάληψη», «Μένει 1 δευτερόλεπτο»), όχι από τον κώδικα.
 */
class R7F9Test {
    private fun source(name: String): String = File("src/main/kotlin/gr/ygeiaforma/wear/$name").readText()

    @Test
    fun secondsLeftUsesTheSingularForOne() {
        assertEquals("Μένει 1 δευτερόλεπτο", secondsLeftText(1))
        assertEquals("Μένουν 2 δευτερόλεπτα", secondsLeftText(2))
        assertEquals("Μένουν 0 δευτερόλεπτα", secondsLeftText(0))
        assertEquals("Μένουν 60 δευτερόλεπτα", secondsLeftText(60))
    }

    @Test
    fun repetitionsUseTheSingularForOne() {
        assertEquals("1 επανάληψη", countText(1, "επανάληψη", "επαναλήψεις"))
        assertEquals("2 επαναλήψεις", countText(2, "επανάληψη", "επαναλήψεις"))
        assertEquals("0 επαναλήψεις", countText(0, "επανάληψη", "επαναλήψεις"))
    }

    /** Κανένα κείμενο του TalkBack με μεταβλητή ακολουθούμενη από πληθυντικό χωρίς κανόνα για το 1. */
    @Test
    fun watchTalkBackTextsHaveNoUnguardedPlural() {
        val s = source("WatchView.kt")
        assertFalse(s.contains("Έκανες \$reps επαναλήψεις"))
        assertFalse(s.contains("Μένουν \$left δευτερόλεπτα"))
        assertFalse(s.contains("\${x.reps} επαναλήψεις"))
        assertTrue(s.contains("secondsLeftText(left)"))
        val bad = Regex("""sayAdd\([^\n]*\$\{?[\w.]+\}? (επαναλήψεις|δευτερόλεπτα|λεπτά|ασκήσεις)""")
        assertEquals(emptyList<String>(), bad.findAll(s).map { it.value }.toList())
    }
}
