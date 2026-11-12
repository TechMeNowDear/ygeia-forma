package gr.ygeiaforma.ygeia_forma

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

/** Το widget «Προπόνηση σήμερα» (13/11): τι γράφει κάθε μέρα, από το στιγμιότυπο της εφαρμογής. */
class QuickWidgetRulesTest {
    // Δευτέρα 16/11/2026.
    private val mon = LocalDate.of(2026, 11, 16)

    private fun week(vararg days: Int) = JSONObject().put("has", true).put(
        "week",
        JSONObject().also { w ->
            for (d in days) w.put("$d", JSONObject().put("t", if (d == 3) "Περπάτημα" else "Προπόνηση Α").put("s", if (d == 3) "40 λεπτά" else "6 ασκήσεις · περίπου 50′"))
        },
    )

    @Test
    fun todayWorkoutOrRestWithTheNextOne() {
        assertEquals("Προπόνηση Α" to "6 ασκήσεις · περίπου 50′", QuickWidgetRules.workoutLines(week(1, 3, 5), mon))
        // Τρίτη: ξεκούραση, η επόμενη είναι αύριο.
        assertEquals("Ξεκούραση σήμερα" to "Αύριο: Περπάτημα", QuickWidgetRules.workoutLines(week(1, 3, 5), mon.plusDays(1)))
        // Σάββατο: η επόμενη είναι τη Δευτέρα (περνά την Κυριακή και την αλλαγή εβδομάδας).
        assertEquals("Ξεκούραση σήμερα" to "Δευτέρα: Προπόνηση Α", QuickWidgetRules.workoutLines(week(1, 3, 5), mon.plusDays(5)))
        // Πρόγραμμα χωρίς καμία μέρα.
        assertEquals("Ξεκούραση σήμερα" to "", QuickWidgetRules.workoutLines(week(), mon))
    }

    @Test
    fun doneOnlyCountsForItsOwnDay() {
        val w = week(1, 3, 5).put("done", "2026-11-16").put("doneText", "Προπόνηση Α · 52′")
        assertEquals("Έγινε σήμερα" to "Προπόνηση Α · 52′", QuickWidgetRules.workoutLines(w, mon))
        // Την επόμενη μέρα το χθεσινό «έγινε» δεν φαίνεται πια (το widget αλλάζει στα μεσάνυχτα χωρίς την εφαρμογή).
        assertEquals("Ξεκούραση σήμερα" to "Αύριο: Περπάτημα", QuickWidgetRules.workoutLines(w, mon.plusDays(1)))
    }

    @Test
    fun withoutProgramOrSnapshot() {
        assertEquals("Προπόνηση" to "Άνοιξε την εφαρμογή", QuickWidgetRules.workoutLines(null, mon))
        assertEquals("Χωρίς πρόγραμμα" to "Φτιάξε ένα στην Άσκηση", QuickWidgetRules.workoutLines(JSONObject().put("has", false), mon))
        // Προπόνηση χωρίς πρόγραμμα («ελεύθερη») που έγινε σήμερα: φαίνεται.
        assertEquals(
            "Έγινε σήμερα" to "Ελεύθερη προπόνηση · 30′",
            QuickWidgetRules.workoutLines(JSONObject().put("has", false).put("done", "2026-11-16").put("doneText", "Ελεύθερη προπόνηση · 30′"), mon),
        )
        // Χαλασμένο στιγμιότυπο: ποτέ σφάλμα, ποτέ κενός τίτλος.
        assertEquals("Ξεκούραση σήμερα" to "", QuickWidgetRules.workoutLines(JSONObject().put("has", true).put("week", "x"), mon))
        assertEquals("Ξεκούραση σήμερα" to "", QuickWidgetRules.workoutLines(JSONObject().put("has", true).put("week", JSONObject().put("1", JSONObject().put("t", ""))), mon))
    }
}
