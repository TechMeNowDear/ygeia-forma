package gr.ygeiaforma.ygeia_forma

import org.json.JSONObject
import java.time.LocalDate

/**
 * Τι γράφει το widget «Προπόνηση σήμερα» (13/11). Καθαρή συνάρτηση (χωρίς Android), για να ελέγχεται σε απλό JVM.
 *
 * Η εφαρμογή γράφει στο στιγμιότυπο των widgets (widget_snapshot.dart, κλειδί «workout») ΟΛΗ την εβδομάδα του
 * προγράμματος, με έτοιμα κείμενα. Έτσι το widget αλλάζει μόνο του στα μεσάνυχτα (το ξυπνητήρι που υπάρχει ήδη), χωρίς
 * να ξυπνήσει η εφαρμογή και χωρίς καμία δουλειά στο παρασκήνιο.
 *
 * Μορφή: {has: true|false, week: {"1": {t, s}, … "7": {t, s}}, done: "2026-11-16", doneText: "Προπόνηση Α · 52 λεπτά"}
 *   week: 1 = Δευτέρα … 7 = Κυριακή (μόνο οι μέρες με προπόνηση)· done: η μέρα που τελείωσε η τελευταία προπόνηση.
 */
object QuickWidgetRules {
    private val DAYS = listOf("Δευτέρα", "Τρίτη", "Τετάρτη", "Πέμπτη", "Παρασκευή", "Σάββατο", "Κυριακή")

    /**
     * Round 1 (U7-17 α): χωρά η επικεφαλίδα πάνω από τις δύο γραμμές; Τρεις γραμμές (11 + 17 + 13 sp) με 8 dp πάνω-κάτω
     * θέλουν ≈ 72 dp στο κανονικό μέγεθος γραμμάτων· με περιθώριο, 76 dp × [fontScale]. Ύψος άγνωστο (0): ναι.
     */
    fun workoutHeadFits(maxHeightDp: Int, fontScale: Float): Boolean = maxHeightDp <= 0 || maxHeightDp >= 76f * fontScale

    /** (τίτλος, δεύτερη γραμμή). */
    fun workoutLines(w: JSONObject?, today: LocalDate): Pair<String, String> {
        if (w == null) return "Προπόνηση" to "Άνοιξε την εφαρμογή"
        if (w.optString("done", "") == today.toString()) {
            return "Έγινε σήμερα" to w.optString("doneText", "")
        }
        if (!w.optBoolean("has", false)) return "Χωρίς πρόγραμμα" to "Φτιάξε ένα στην Άσκηση"
        val week = w.optJSONObject("week") ?: JSONObject()
        fun day(d: LocalDate): JSONObject? = week.optJSONObject(d.dayOfWeek.value.toString())?.takeIf { it.optString("t", "").isNotEmpty() }
        day(today)?.let { return it.optString("t") to it.optString("s", "") }
        for (i in 1..6) {
            val d = today.plusDays(i.toLong())
            val e = day(d) ?: continue
            val whenText = if (i == 1) "Αύριο" else DAYS[d.dayOfWeek.value - 1]
            return "Ξεκούραση σήμερα" to "$whenText: ${e.optString("t")}"
        }
        return "Ξεκούραση σήμερα" to ""
    }
}
