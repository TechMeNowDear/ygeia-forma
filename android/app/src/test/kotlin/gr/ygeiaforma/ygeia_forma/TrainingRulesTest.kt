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

    // ------------------------------------------------------------------ 13/11: πόσο άργησε το τέλος του διαλείμματος
    @Test
    fun restLatenessIsCountedAndSurvivesSaving() {
        var r = TrainingRules.RestLate()
        assertEquals(0, r.count)
        assertEquals(0L, r.avgMs)
        r = r.add(120, true).add(2500, false).add(-40, true)
        assertEquals(3, r.count)
        assertEquals(2620L, r.sumMs)
        assertEquals(873L, r.avgMs)
        assertEquals(2500L, r.maxMs)
        // χτύπησε λίγο νωρίτερα: μετρά 0, όχι αρνητικό
        assertEquals(0L, r.lastMs)
        assertEquals(1, r.over2s)
        assertEquals(2, r.alarms)
        val back = TrainingRules.RestLate.decode(r.encode())
        assertEquals(r.encode(), back.encode())
        assertEquals("3;2620;2500;0;1;2", r.encode())
        // παράλογα μεγάλη καθυστέρηση κόβεται στη μία ώρα
        assertEquals(TrainingRules.MAX_REST_MS, TrainingRules.RestLate().add(Long.MAX_VALUE, false).maxMs)
    }

    @Test
    fun brokenLatenessRecordStartsFromZero() {
        for (s in listOf(null, "", "x", "1;2;3", "1;2;3;4;5;6;7", "a;b;c;d;e;f", "-1;0;0;0;0;0", "1;10;5;9;0;0", "1;10;10;10;2;0",
            "1;10;10;10;0;2", "99999999999;0;0;0;0;0", "1;99999999;99999999;0;0;0")) {
            val r = TrainingRules.RestLate.decode(s)
            assertEquals("$s", 0, r.count)
            assertEquals("$s", "0;0;0;0;0;0", r.encode())
        }
    }
}
