package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Round 9 · f5: widgets και πλατφόρμα. R9-A12-3 (σμίκρυνση και μονάδες του WidgetRenderer σε καθαρές συναρτήσεις),
 * R9-U1-5 («+0,2°» κολλητά), R9-U1-4 (σύντομο όνομα κουτιού), R9-A4-4 (τιμές float της Samsung ως ο δεκαδικός της
 * ζυγαριάς), R9-A10-1 (το πάτημα widget δεν ξαναπαίζει σε επαναδημιουργία), R9-A10-2 (CLEAR_TOP). Καθαρό JVM.
 * Οι αναμενόμενες τιμές από τον κανόνα (python: /home/claude/scratch/f5r9/floatjson.py), όχι από τον κώδικα.
 */
class R9F5Test {
    // ------------------------------------------------------------------------------------------- A12-3: fitSize

    @Test
    fun fitSizeStopsAtTheFloorWhenTheTextNeverFits() {
        // Πλάτος = 10 × μέγεθος, και τίποτα δεν χωρά στο 1: το τελευταίο βήμα είναι ακριβώς το όριο.
        assertEquals(21f * 0.85f, WidgetText.fitSize(21f, WidgetText.MIN_SCALE_SMALL, 1f) { it * 10f }, 1e-4f)
        assertEquals(21f * 0.75f, WidgetText.fitSize(21f, 0.75f, 1f) { it * 10f }, 1e-4f)
        assertEquals(34f * 0.6f, WidgetText.fitSize(34f, 0.6f, 1f) { it * 10f }, 1e-4f)
        // Ποτέ ένα βήμα κάτω από το όριο (ο παλιός βρόχος του R8-U1-7 έδινε 80% αντί για 85%).
        assertNotEquals(21f * 0.80f, WidgetText.fitSize(21f, WidgetText.MIN_SCALE_SMALL, 1f) { it * 10f }, 1e-3f)
    }

    @Test
    fun fitSizeKeepsTheFirstSizeThatFits() {
        // Χωρά από την αρχή: το αρχικό μέγεθος, με μία μόνο μέτρηση.
        var calls = 0
        assertEquals(21f, WidgetText.fitSize(21f, 0.75f, 210f) { calls++; it * 10f }, 0f)
        assertEquals(1, calls)
        // 210 > 200, 199,5 ≤ 200: το πρώτο βήμα (95%), όχι μικρότερο.
        assertEquals(21f * 0.95f, WidgetText.fitSize(21f, 0.75f, 200f) { it * 10f }, 1e-4f)
        // Η κεντρική τιμή μετρά αριθμό + μονάδα: 30 × 3 + 12 = 102 > 100· στο 95%: 28,5 × 3 + 12 = 97,5 ≤ 100.
        assertEquals(30f * 0.95f, WidgetText.fitSize(30f, 0.6f, 100f) { it * 3f + 12f }, 1e-4f)
    }

    // ------------------------------------------------------------------------------------------- A12-3 / U1-5: μονάδες

    @Test
    fun valueAndUnitAsTheRendererDrawsThem() {
        assertEquals("96" to "%", WidgetText.valueParts("96", "%"))
        assertEquals("25,4" to "%", WidgetText.valueParts("25,4", "%"))
        // Το στιγμιότυπο γράφει τις μονάδες με κενό μπροστά (« kg», widget_snapshot.dart): ένα κενό, όχι δύο.
        assertEquals("82,2" to " kg", WidgetText.valueParts("82,2", " kg"))
        assertEquals("82,2" to " kg", WidgetText.valueParts("82,2", "kg"))
        assertEquals("7:16" to " ώρες", WidgetText.valueParts("7:16", " ώρες"))
        assertEquals("71" to "", WidgetText.valueParts("71", ""))
        // R9-U1-5: «+0,2°» κολλητά, όπως η γραμμή «συνήθως +0,1°» από κάτω· με «°C» κενό (SI).
        assertEquals("°", WidgetText.unitText("°"))
        assertEquals("+0,2" to "°", WidgetText.valueParts("+0,2", "°"))
        assertEquals("+0,2°", "+0,2" + WidgetText.unitText("°"))
        assertEquals(" °C", WidgetText.unitText("°C"))
    }

    // ------------------------------------------------------------------------------------------- U1-4: σύντομο όνομα

    @Test
    fun chipLabelFallsBackToTheShortName() {
        assertEquals("Energy Score", WidgetText.chipLabel("Energy Score", "Energy") { true })
        assertEquals("Energy", WidgetText.chipLabel("Energy Score", "Energy") { it.length <= 6 })
        // Χωρίς σύντομο όνομα (ή κενό, όταν λείπει το «ls»): το κανονικό, και ας κοπεί.
        assertEquals("Ετοιμότητα", WidgetText.chipLabel("Ετοιμότητα", null) { false })
        assertEquals("Ετοιμότητα", WidgetText.chipLabel("Ετοιμότητα", "") { false })
    }

    // ------------------------------------------------------------------------------------------- A4-4: float της Samsung

    @Test
    fun samsungFloatsBecomeTheScaleDecimals() {
        // Ο δείκτης 26,9 της InBody: float 26.899999618530273 → 26,9 (πριν φαινόταν «26,8», κομμένος στο 0,1).
        assertEquals(26.9, DataRules.floatJson(26.9f)!!, 0.0)
        assertNotEquals(26.9, 26.9f.toDouble(), 0.0)
        assertEquals(89.1, DataRules.floatJson(89.1f)!!, 0.0)
        assertEquals(82.2, DataRules.floatJson(82.2f)!!, 0.0)
        assertEquals(25.0, DataRules.floatJson(25f)!!, 0.0)
        // Κάθε τιμή με 1 δεκαδικό ως 300,0 και με 2 δεκαδικά ως 300,00: ακριβώς ο δεκαδικός.
        for (i in 0..3000) assertEquals("$i/10", i / 10.0, DataRules.floatJson((i / 10.0).toFloat())!!, 0.0)
        for (i in 0..30000) assertEquals("$i/100", i / 100.0, DataRules.floatJson((i / 100.0).toFloat())!!, 0.0)
        // Ό,τι δεν δέχεται το JSONObject: τίποτα (πριν: εξαίρεση για άπειρο).
        assertNull(DataRules.floatJson(null))
        assertNull(DataRules.floatJson(Float.NaN))
        assertNull(DataRules.floatJson(Float.POSITIVE_INFINITY))
    }

    @Test
    fun bmiFromTheScaleDecimalsIsNotCutTooLow() {
        // Ο κανόνας του reference.dart `bmiShown` (κομμένος στο 0,1 με ανοχή 1e-9), με τις τιμές που στέλνει πια η Kotlin.
        fun shown(b: Double) = Math.floor(b * 10 + 1e-9) / 10
        assertEquals(26.9, shown(DataRules.floatJson(26.9f)!!), 1e-9)
        assertEquals(27.5, shown(DataRules.floatJson(89.1f)!! / Math.pow(1.8, 2.0)), 1e-9)
        assertEquals(28.8, shown(DataRules.floatJson(88.2f)!! / Math.pow(1.75, 2.0)), 1e-9)
        // Πριν (η δυαδική τιμή του float): 26,8 / 27,4 / 28,7.
        assertEquals(26.8, shown(26.9f.toDouble()), 1e-9)
        assertEquals(27.4, shown(89.1f.toDouble() / Math.pow(1.8, 2.0)), 1e-9)
    }

    // ------------------------------------------------------------------------------------------- A10-1 / A10-2

    @Test
    fun widgetTapRunsOnlyOnAFreshStart() {
        assertEquals("w:food:scan:", DataRules.launchOpenTarget("w:food:scan:", restored = false, fromHistory = false))
        // Επαναδημιουργία (αποθηκευμένη κατάσταση) ή άνοιγμα από τα Πρόσφατα με το αρχικό Intent: όχι ξανά ο σαρωτής.
        assertNull(DataRules.launchOpenTarget("w:food:scan:", restored = true, fromHistory = false))
        assertNull(DataRules.launchOpenTarget("w:sleep:metric:hrv", restored = false, fromHistory = true))
        // Ό,τι δεν έχει τη μορφή των widgets: τίποτα, όπως πριν (E3-24).
        assertNull(DataRules.launchOpenTarget("x", restored = false, fromHistory = false))
        assertNull(DataRules.launchOpenTarget(null, restored = false, fromHistory = false))
    }

    @Test
    fun widgetTapBringsTheExistingScreenForward() {
        // CLEAR_TOP + SINGLE_TOP: ό,τι είναι πάνω από την υπάρχουσα MainActivity κλείνει και το πάτημα πάει σε αυτήν
        // (onNewIntent)· ποτέ δεύτερη MainActivity με δεύτερη μηχανή Flutter.
        // Οι τιμές των σταθερών του Android (Intent.FLAG_ACTIVITY_*), γραμμένες εδώ ώστε ο έλεγχος να μη χρειάζεται Android.
        val clearTop = 0x04000000
        val singleTop = 0x20000000
        val newTask = 0x10000000
        assertTrue((HomeWidgets.OPEN_FLAGS and clearTop) != 0)
        assertTrue((HomeWidgets.OPEN_FLAGS and singleTop) != 0)
        assertTrue((HomeWidgets.OPEN_FLAGS and newTask) != 0)
        assertEquals(clearTop or singleTop or newTask, HomeWidgets.OPEN_FLAGS)
    }
}
