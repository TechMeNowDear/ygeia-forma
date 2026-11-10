package gr.ygeiaforma.ygeia_forma

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Όριο μνήμης για τις εικόνες των widgets (Android 17, targetSdk 37).
 *
 * Το Android μετρά ΟΛΑ τα bitmaps μιας ενημέρωσης widget (όλα τα μεγέθη, ημέρας και νύχτας· το ίδιο bitmap μία φορά)
 * και, αν ξεπεράσουν τα 6 · πλάτος · ύψος της οθόνης σε byte (1,5 × μια εικόνα ARGB όλης της οθόνης), η
 * updateAppWidget πετά IllegalArgumentException και το widget μένει παλιό ή κενό. Ως το targetSdk 36 ήταν μόνο
 * προειδοποίηση στο log. Πηγή: developer.android.com/about/versions/17/behavior-changes-17 (RemoteViews bitmap).
 *
 * Καθαρές συναρτήσεις (χωρίς Android), για να ελέγχονται σε απλό JVM (WidgetBudgetTest).
 */
object WidgetBudget {
    /** Το παλιό όριο ανά εικόνα (~3 MB, ως την #96): μένει ως ανώτατο, για λίγη μνήμη. */
    const val MAX_IMAGE_BYTES = 3_000_000L

    /** Αν δεν ξέρουμε την οθόνη: το ίδιο με το παράδειγμα της Google (15 MB). */
    const val FALLBACK_BUDGET_BYTES = 15_000_000L

    /** Κάτω από αυτό τα γράμματα δεν διαβάζονται· μια τέτοια εικόνα είναι ήδη πολύ μικρότερη από κάθε όριο. */
    private const val MIN_IMAGE_BYTES = 40_000L

    /**
     * Τι μέρος του ορίου παίρνουμε σε κάθε προσπάθεια. Πρώτα 3/4 (περιθώριο: η αρχική οθόνη μπορεί να είναι σε
     * άλλη οθόνη από αυτή που ξέρει η εφαρμογή, π.χ. Fold που μόλις κλείνει). Αν το Android πει ακόμα «όχι», ξανά
     * με μικρότερες εικόνες: θολότερο widget αντί για κενό.
     */
    val SHARES = doubleArrayOf(0.75, 0.3, 0.1)

    /** Το όριο του Android για όλες τις εικόνες μιας ενημέρωσης, από το μέγεθος της οθόνης σε px. */
    fun systemBudget(screenWPx: Int, screenHPx: Int): Long =
        if (screenWPx <= 0 || screenHPx <= 0) FALLBACK_BUDGET_BYTES else 6L * screenWPx * screenHPx

    /** Μέγιστα byte ανά εικόνα, όταν μια ενημέρωση έχει [images] εικόνες και παίρνουμε το [share] του ορίου. */
    fun imageCap(budget: Long, images: Int, share: Double): Long {
        val per = (budget * share / max(1, images)).toLong()
        return per.coerceIn(MIN_IMAGE_BYTES, MAX_IMAGE_BYTES)
    }

    /** Πυκνότητα (px ανά dp) ώστε η εικόνα [wDp]×[hDp] σε ARGB_8888 (4 byte/px) να χωρά στα [capBytes]. */
    fun density(wDp: Float, hDp: Float, density: Float, capBytes: Long): Float {
        val w = max(1f, wDp)
        val h = max(1f, hDp)
        val d = if (density > 0f) density else 1f
        val bytes = w * d * h * d * 4f
        return if (bytes > capBytes) d * sqrt(capBytes / bytes) else d
    }

    /** Πλάτος και ύψος σε px (προς τα κάτω, ώστε να μη ξεπερνούν ποτέ το όριο· τουλάχιστον 1). */
    fun pixels(wDp: Float, hDp: Float, density: Float): Pair<Int, Int> =
        max(1, floor(max(1f, wDp) * density).toInt()) to max(1, floor(max(1f, hDp) * density).toInt())

    /** Byte μιας εικόνας ARGB_8888. */
    fun bytes(wPx: Int, hPx: Int): Long = 4L * wPx * hPx

    /** Το μήνυμα του Android όταν ξεπερνιέται το όριο («…exceeds maximum bitmap memory usage…»). */
    fun isBitmapLimit(e: Throwable): Boolean = e is IllegalArgumentException && e.message?.contains("bitmap memory", ignoreCase = true) == true
}
