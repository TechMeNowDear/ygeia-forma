package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Αποφάσεις 20/11: η υπενθύμιση ξαναμπαίνει μετά από επανεκκίνηση μόνο αν η ώρα της δεν πέρασε. */
class FoodReminderBootTest {
    private val now = 1_800_000_000_000L
    private val hour = 60 * 60 * 1000L

    @Test
    fun onlyFutureTimes() {
        assertTrue(FoodReminderRules.restoreAt(now + hour, now))
        assertFalse("πέρασε όσο το κινητό ήταν κλειστό: όχι αργή ειδοποίηση", FoodReminderRules.restoreAt(now - 1, now))
        assertFalse(FoodReminderRules.restoreAt(now, now))
        assertFalse("χωρίς αποθηκευμένη ώρα", FoodReminderRules.restoreAt(0L, now))
        assertFalse("πάνω από 2 μέρες μπροστά: παλιό ή χαλασμένο", FoodReminderRules.restoreAt(now + 49 * hour, now))
        assertTrue(FoodReminderRules.restoreAt(now + 48 * hour, now))
    }
}
