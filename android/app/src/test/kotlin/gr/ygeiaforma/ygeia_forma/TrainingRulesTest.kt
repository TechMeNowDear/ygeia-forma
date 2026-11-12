package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Τελικός έλεγχος, Συμβούλιο 5 (U-2): πότε χτυπά το τέλος του διαλείμματος στο κινητό. */
class TrainingRulesTest {
    @Test
    fun restEndsExactlyWhenTheRemainingTimeIsOver() {
        // 90″ διάλειμμα, το κινητό είναι ανοιχτό 5 ώρες
        val now = 5 * 60 * 60 * 1000L
        assertEquals(now + 90_000, TrainingRules.restTrigger(now, 90_000))
        assertEquals(now + 1, TrainingRules.restTrigger(now, 1))
        // το μεγαλύτερο διάλειμμα του προγράμματος (10′) και με «+30″» από πάνω
        assertEquals(now + 600_000, TrainingRules.restTrigger(now, 600_000))
        assertEquals(now + 630_000, TrainingRules.restTrigger(now, 630_000))
    }

    @Test
    fun brokenTimesNeverGiveAnAlarmInThePastOrDaysAway() {
        val now = 1_000_000L
        // αρνητικό υπόλοιπο (η ώρα πήγε πίσω): τώρα, όχι στο παρελθόν
        assertEquals(now, TrainingRules.restTrigger(now, -5_000))
        assertEquals(now, TrainingRules.restTrigger(now, Long.MIN_VALUE))
        // παράλογα μεγάλο υπόλοιπο (η ώρα πήγε μπροστά): το πολύ μία ώρα
        assertEquals(now + TrainingRules.MAX_REST_MS, TrainingRules.restTrigger(now, Long.MAX_VALUE))
        assertEquals(60 * 60 * 1000L, TrainingRules.MAX_REST_MS)
        // ποτέ πριν από το «τώρα», για κάθε υπόλοιπο
        for (left in listOf(-1L, 0L, 1L, 999L, 90_000L, 3_600_000L, 3_600_001L)) {
            val t = TrainingRules.restTrigger(now, left)
            assertTrue("$left", t >= now && t <= now + TrainingRules.MAX_REST_MS)
        }
    }
}
