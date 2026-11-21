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

    @Test
    fun afterBootMovesAMissedReminderToTheNextEvening() {
        // Έλεγχος 21/11 (K6-R-06): κινητό κλειστό 21:00–08:00. Πριν: η υπενθύμιση σβηνόταν ώσπου να ανοίξει η εφαρμογή.
        val athens = java.time.ZoneId.of("Europe/Athens")
        fun at(y: Int, m: Int, d: Int, h: Int, min: Int) =
            java.time.ZonedDateTime.of(y, m, d, h, min, 0, 0, athens).toInstant().toEpochMilli()
        val mon = at(2026, 11, 23, 21, 30)
        val tueMorning = at(2026, 11, 24, 8, 0)
        assertEquals(at(2026, 11, 24, 21, 30) to true, FoodReminderRules.afterBoot(mon, tueMorning, true, athens))
        // Η ώρα δεν πέρασε: η ίδια υπενθύμιση, με το δικό της κείμενο.
        assertEquals(mon to false, FoodReminderRules.afterBoot(mon, at(2026, 11, 23, 19, 0), true, athens))
        assertEquals(mon to false, FoodReminderRules.afterBoot(mon, at(2026, 11, 23, 19, 0), false, athens))
        // Πέρασε και δεν υπάρχει κείμενο επόμενης μέρας (αρχείο παλιάς έκδοσης): καμία, όπως πριν.
        assertEquals(null, FoodReminderRules.afterBoot(mon, tueMorning, false, athens))
        // Χωρίς ώρα, ή ώρα πάνω από 2 μέρες μπροστά (χαλασμένο αρχείο): καμία.
        assertEquals(null, FoodReminderRules.afterBoot(0L, tueMorning, true, athens))
        assertEquals(null, FoodReminderRules.afterBoot(mon + 49 * hour, mon, true, athens))
        // Κλειστό 10 μέρες: η επόμενη 21:30 μετά το «τώρα», όχι δέκα ειδοποιήσεις.
        assertEquals(at(2026, 12, 3, 21, 30) to true, FoodReminderRules.afterBoot(mon, at(2026, 12, 3, 9, 0), true, athens))
        // Ακριβώς την ώρα της: θεωρείται περασμένη (το ξυπνητήρι χάθηκε στην επανεκκίνηση) → αύριο.
        assertEquals(at(2026, 11, 24, 21, 30) to true, FoodReminderRules.afterBoot(mon, mon, true, athens))
    }

    @Test
    fun noRearmAfterDeleteAll() {
        // Έλεγχος 21/11 (K6-R-05): μετά από «Διαγραφή όλων» το αρχείο της υπενθύμισης δεν υπάρχει (ώρα 0): το ξυπνητήρι
        // που τυχόν χτυπήσει δεν ξαναβάζει επόμενο. Πριν χτυπούσε κάθε βράδυ ώσπου να ανοίξει η εφαρμογή.
        assertFalse(FoodReminderRules.rearm(0L, now, "Δεν έχεις γράψει φαγητό σήμερα."))
        assertTrue(FoodReminderRules.rearm(now, now, "Δεν έχεις γράψει φαγητό σήμερα."))
        assertFalse("άλλη υπενθύμιση στο αρχείο από αυτήν που χτύπησε", FoodReminderRules.rearm(now + hour, now, "κείμενο"))
        assertFalse("ξυπνητήρι παλιάς έκδοσης: χωρίς κείμενο επόμενης μέρας", FoodReminderRules.rearm(now, now, null))
        assertFalse("ξυπνητήρι παλιάς έκδοσης: χωρίς ώρα", FoodReminderRules.rearm(0L, 0L, "κείμενο"))
    }
}
