package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
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

    @Test
    fun nextDaySameWallClockTime() {
        // Έλεγχος 20/11 (K6C-02): η υπενθύμιση ξαναμπαίνει μόνη της για την επόμενη μέρα, ίδια ώρα τοίχου.
        val athens = java.time.ZoneId.of("Europe/Athens")
        fun at(y: Int, m: Int, d: Int, h: Int, min: Int) =
            java.time.ZonedDateTime.of(y, m, d, h, min, 0, 0, athens).toInstant().toEpochMilli()
        val mon = at(2026, 11, 23, 21, 30)
        assertEquals(at(2026, 11, 24, 21, 30), FoodReminderRules.nextDay(mon, mon + 60_000, athens))
        // Αλλαγή ώρας 28/3/2027 (μέρα 23 ωρών) και 31/10/2027 (25 ωρών): πάλι 21:30, όχι 22:30 ή 20:30.
        val sat = at(2027, 3, 27, 21, 30)
        assertEquals(at(2027, 3, 28, 21, 30), FoodReminderRules.nextDay(sat, sat + 1, athens))
        assertEquals(23 * hour, FoodReminderRules.nextDay(sat, sat + 1, athens) - sat)
        val oct = at(2027, 10, 30, 21, 30)
        assertEquals(25 * hour, FoodReminderRules.nextDay(oct, oct + 1, athens) - oct)
        // Το ξυπνητήρι χτύπησε πολύ αργά (π.χ. το κινητό ήταν κλειστό 3 μέρες): η επόμενη είναι ΜΕΤΑ το «τώρα».
        assertEquals(at(2026, 11, 27, 21, 30), FoodReminderRules.nextDay(mon, at(2026, 11, 26, 22, 0), athens))
        assertEquals("χωρίς ώρα (ξυπνητήρι παλιάς έκδοσης): τίποτα", 0L, FoodReminderRules.nextDay(0L, mon, athens))
    }
}
