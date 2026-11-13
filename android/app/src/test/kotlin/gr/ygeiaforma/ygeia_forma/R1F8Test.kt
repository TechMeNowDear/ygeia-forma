package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Round 1 · f8: extras της Flutter από άλλες εφαρμογές (S10-1) και «Διαγραφή όλων» (U4-6). Απλό JVM, χωρίς Android. */
class R1F8Test {
    @Test
    fun everyLaunchExtraTheFlutterEmbeddingReadsIsDropped() {
        // S10-1: τα ονόματα των extras της Flutter (FlutterActivityLaunchConfigs). Αν λείψει ένα, μια άλλη εφαρμογή
        // μπορεί πάλι να ανοίξει την εφαρμογή σε άλλη διαδρομή ή να τη ρίξει στο άνοιγμα.
        val names = FlutterLaunchExtras.NAMES
        val expected = listOf(
            "route",
            "cached_engine_id",
            "cached_engine_group_id",
            "dart_entrypoint",
            "dart_entrypoint_args",
            "background_mode",
            "destroy_engine_with_activity",
            "enable_state_restoration",
        )
        for (n in expected) assertTrue(n, names.contains(n))
        assertEquals(expected.size, names.toSet().size)
    }

    @Test
    fun ourOwnExtrasAreNeverDropped() {
        // Τα δικά μας (widgets, οθόνη ρύθμισης widget) περνούν από τους δικούς τους ελέγχους (DataRules) και μένουν.
        val names = FlutterLaunchExtras.NAMES
        for (own in listOf("ygeia_open", "ygeia_kind", "ygeia_w", "ygeia_h", "appWidgetId")) {
            assertFalse(own, names.contains(own))
        }
    }

    @Test
    fun nothingIsReadAfterDeleteAllUntilTheUserLeavesTheDeletedScreen() {
        // U4-6: [at] = πότε έγινε η «Διαγραφή όλων» (0 = ποτέ)· [seen] = ο χρήστης έφυγε από το «Όλα διαγράφηκαν».
        assertFalse(WipeRules.awaitsStart(0L, false))
        assertFalse(WipeRules.awaitsStart(0L, true))
        assertTrue(WipeRules.awaitsStart(1_794_000_000_000L, false))
        assertFalse(WipeRules.awaitsStart(1_794_000_000_000L, true))
        assertFalse(WipeRules.awaitsStart(-5L, false))
    }
}
