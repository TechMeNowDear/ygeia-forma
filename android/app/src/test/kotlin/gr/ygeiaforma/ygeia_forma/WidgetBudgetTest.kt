package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Android 17 (targetSdk 37): όλες οι εικόνες μιας ενημέρωσης widget μαζί ≤ 6 · πλάτος · ύψος οθόνης, αλλιώς
 * IllegalArgumentException και το widget δεν ενημερώνεται (developer.android.com/about/versions/17/behavior-changes-17).
 */
class WidgetBudgetTest {
    /** Ό,τι κάνει η HomeWidgets.update: [sizes] μεγέθη (dp) × 2 εικόνες (ημέρας, νύχτας), όλες με το ίδιο όριο. */
    private fun total(sizes: List<Pair<Float, Float>>, density: Float, cap: Long): Long =
        sizes.sumOf { (w, h) ->
            val d = WidgetBudget.density(w, h, density, cap)
            val (wPx, hPx) = WidgetBudget.pixels(w, h, d)
            2 * WidgetBudget.bytes(wPx, hPx)
        }

    @Test
    fun smallScreenBigWidgetFitsTheAndroid17Limit() {
        // Κινητό 720×1280 (2,0 px/dp), widget 4×4 σε κάθετη και οριζόντια θέση.
        val budget = WidgetBudget.systemBudget(720, 1280)
        assertEquals(5_529_600L, budget)
        val sizes = listOf(360f to 360f, 340f to 380f)
        // Ο παλιός κανόνας (3 MB ανά εικόνα, χωρίς άθροισμα) ξεπερνά το όριο → updateAppWidget θα πετούσε.
        assertTrue(total(sizes, 2f, WidgetBudget.MAX_IMAGE_BYTES) > budget)
        // Ο νέος χωρά, σε κάθε προσπάθεια.
        for (share in WidgetBudget.SHARES) {
            val cap = WidgetBudget.imageCap(budget, images = 4, share = share)
            assertTrue("share $share", total(sizes, 2f, cap) <= (budget * share).toLong())
        }
    }

    @Test
    fun foldCoverTypicalWidgetKeepsFullSharpness() {
        // Fold κλειστό (εξωτερική οθόνη ~1080×2520, 2,625 px/dp), widget 4×2: καμία αλλαγή στην ευκρίνεια.
        val budget = WidgetBudget.systemBudget(1080, 2520)
        val cap = WidgetBudget.imageCap(budget, images = 4, share = WidgetBudget.SHARES[0])
        assertEquals(WidgetBudget.MAX_IMAGE_BYTES, cap)
        assertEquals(2.625f, WidgetBudget.density(350f, 190f, 2.625f, cap), 0f)
        assertTrue(total(listOf(350f to 190f, 380f to 170f), 2.625f, cap) <= budget)
    }

    @Test
    fun neverAboveCapForAnySize() {
        for (w in listOf(1f, 40f, 92f, 180f, 370f, 600f, 900f, 2000f)) {
            for (h in listOf(1f, 40f, 190f, 300f, 400f, 900f, 2000f)) {
                for (dens in listOf(1f, 2f, 2.625f, 3.5f)) {
                    for (cap in listOf(40_000L, 500_000L, 1_000_000L, WidgetBudget.MAX_IMAGE_BYTES)) {
                        val d = WidgetBudget.density(w, h, dens, cap)
                        val (wPx, hPx) = WidgetBudget.pixels(w, h, d)
                        assertTrue("$w×$h@$dens cap $cap", WidgetBudget.bytes(wPx, hPx) <= cap || (wPx == 1 || hPx == 1))
                        assertTrue(wPx >= 1 && hPx >= 1)
                    }
                }
            }
        }
    }

    @Test
    fun unknownScreenAndBadInput() {
        assertEquals(WidgetBudget.FALLBACK_BUDGET_BYTES, WidgetBudget.systemBudget(0, 1280))
        assertEquals(WidgetBudget.FALLBACK_BUDGET_BYTES, WidgetBudget.systemBudget(720, -1))
        // Πυκνότητα 0 ή αρνητικό μέγεθος δεν σπάνε τίποτα.
        val (wPx, hPx) = WidgetBudget.pixels(-5f, 0f, WidgetBudget.density(-5f, 0f, 0f, 40_000L))
        assertEquals(1, wPx)
        assertEquals(1, hPx)
        // Ποτέ πάνω από το παλιό όριο ανά εικόνα, ποτέ 0.
        assertEquals(WidgetBudget.MAX_IMAGE_BYTES, WidgetBudget.imageCap(100_000_000L, 1, 0.75))
        assertTrue(WidgetBudget.imageCap(1L, 4, 0.1) > 0)
    }

    @Test
    fun recognisesOnlyTheBitmapLimitError() {
        assertTrue(
            WidgetBudget.isBitmapLimit(
                IllegalArgumentException("RemoteViews for widget update exceeds maximum bitmap memory usage (used: 9, max: 5)"),
            ),
        )
        assertFalse(WidgetBudget.isBitmapLimit(IllegalArgumentException("άλλο")))
        assertFalse(WidgetBudget.isBitmapLimit(IllegalStateException("bitmap memory")))
    }
}
