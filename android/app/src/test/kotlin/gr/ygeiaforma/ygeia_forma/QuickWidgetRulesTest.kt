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

    /** Έλεγχος 21/11: τα widgets ξαναζωγραφίζονται στα μεσάνυχτα ΚΑΙ στις 04:00 (αλλιώς το «Προπόνηση σήμερα» έμενε στη χθεσινή). */
    @Test
    fun redrawAtMidnightAndAtFour() {
        val d = LocalDate.of(2026, 11, 21)
        assertEquals(d.atTime(4, 1), QuickWidgetRules.nextRedraw(d.atTime(0, 1, 5)))
        assertEquals(d.atTime(4, 1), QuickWidgetRules.nextRedraw(d.atTime(3, 59)))
        assertEquals(d.plusDays(1).atTime(0, 1), QuickWidgetRules.nextRedraw(d.atTime(4, 1, 10)))
        assertEquals(d.plusDays(1).atTime(0, 1), QuickWidgetRules.nextRedraw(d.atTime(23, 59)))
    }

    /** Α13 (απόφαση χρήστη 21/11): η μέρα της προπόνησης αλλάζει στις 04:00, όπως στην εφαρμογή. */
    @Test
    fun trainingDayChangesAtFour() {
        val sat = java.time.LocalDate.of(2026, 11, 21)
        assertEquals(sat.minusDays(1), QuickWidgetRules.trainingDate(sat.atTime(0, 30)))
        assertEquals(sat.minusDays(1), QuickWidgetRules.trainingDate(sat.atTime(3, 59)))
        assertEquals(sat, QuickWidgetRules.trainingDate(sat.atTime(4, 0)))
        assertEquals(sat, QuickWidgetRules.trainingDate(sat.atTime(23, 59)))
        // Ακριβώς μεσάνυχτα: ημερομηνία, μένει ίδια (όπως το trainingDay του κινητού).
        assertEquals(sat, QuickWidgetRules.trainingDate(sat.atStartOfDay()))
        // Στις 00:30 της Τρίτης το widget δείχνει ακόμα το «έγινε» της Δευτέρας.
        val w = week(1, 3, 5).put("done", "2026-11-16").put("doneText", "Προπόνηση Α · 52′")
        val tue0030 = QuickWidgetRules.trainingDate(java.time.LocalDate.of(2026, 11, 17).atTime(0, 30))
        assertEquals("Έγινε σήμερα" to "Προπόνηση Α · 52′", QuickWidgetRules.workoutLines(w, tue0030))
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
