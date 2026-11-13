package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Round 2 · h1: widgets της αρχικής οθόνης (WidgetText): σύντομη πηγή (R2-U3-04), ράβδοι βάρους με ελάχιστο εύρος
 * (R2-U3-05), διάρκεια ύπνου από το μηδέν (R2-U3-06). Καθαρό JVM. Οι αναμενόμενες τιμές βγήκαν σε python από τον
 * γραμμένο κανόνα. Φανταστικές τιμές (δημόσιο repo).
 */
class R2H1Test {
    private fun close(expected: List<Float?>, actual: List<Float?>) {
        assertEquals(expected.size, actual.size)
        for (i in expected.indices) {
            val e = expected[i]
            val a = actual[i]
            if (e == null) assertNull("θέση $i", a) else assertEquals("θέση $i", e, a!!, 0.002f)
        }
    }

    /** R2-U3-04: η σύντομη πηγή μόνο όταν η κανονική δεν χωρά· ποτέ «καμία πρόσφατη…». */
    @Test
    fun shortSourceOnlyWhenTheFullOneDoesNotFit() {
        val narrow: (String) -> Boolean = { it.length <= 12 }
        val wide: (String) -> Boolean = { it.length <= 40 }
        assertEquals("καμία νύχτα", WidgetText.sourceText("καμία πρόσφατη νύχτα", "καμία νύχτα", narrow))
        assertEquals("καμία πρόσφατη νύχτα", WidgetText.sourceText("καμία πρόσφατη νύχτα", "καμία νύχτα", wide))
        assertEquals("καμία ζύγιση", WidgetText.sourceText("καμία ζύγιση ακόμα", "καμία ζύγιση", narrow))
        // Χωρίς σύντομη (όλες οι άλλες πηγές): όπως πριν, η κανονική (το `fit` τη μικραίνει όσο επιτρέπεται).
        assertEquals("Oura · Σάβ 7/11", WidgetText.sourceText("Oura · Σάβ 7/11", null, narrow))
        assertEquals("Oura · Σάβ 7/11", WidgetText.sourceText("Oura · Σάβ 7/11", "", narrow))
    }

    /** Ποιες τιμές μετριούνται από το μηδέν και ποιο ελάχιστο εύρος έχουν οι άλλες. */
    @Test
    fun zeroBasedAndMinimumSpans() {
        assertTrue(WidgetText.zeroBased("sleep", "sleepMin"))
        assertTrue(WidgetText.zeroBased("move", "steps"))
        assertTrue(WidgetText.zeroBased("food", "kcal"))
        assertFalse(WidgetText.zeroBased("sleep", "hrv"))
        assertFalse(WidgetText.zeroBased("sleep", "sleepHr"))
        assertFalse(WidgetText.zeroBased("body", "weight"))
        assertEquals(3f, WidgetText.minSpanFor("weight"), 0f)
        assertEquals(3f, WidgetText.minSpanFor("fatPct"), 0f)
        assertEquals(3f, WidgetText.minSpanFor("smm"), 0f)
        assertEquals(3f, WidgetText.minSpanFor("ffm"), 0f)
        assertEquals(8f, WidgetText.minSpanFor("sleepHr"), 0f)
        assertEquals(20f, WidgetText.minSpanFor("energy"), 0f)
        assertEquals(0f, WidgetText.minSpanFor("hrv"), 0f)
        assertEquals(0f, WidgetText.minSpanFor("bmi"), 0f)
    }

    /**
     * R2-U3-05: ζυγίσεις μιας εβδομάδας με ±0,2 kg νερό. Πριν: 84 / 53 / 100 / 69 / 38 / 69 / 53% (μοιάζουν άλματα). Με
     * ελάχιστο εύρος 3 kg γύρω από τη μέση (82,9): άξονας 81,4–84,4, βάση 81,4 − 1,8 = 79,6 → (v − 79,6) / 4,8.
     */
    @Test
    fun weightNoiseLooksFlat() {
        val w = listOf(83.0f, 82.8f, 83.1f, 82.9f, 82.7f, 82.9f, 82.8f)
        close(
            listOf(0.70833f, 0.66667f, 0.72917f, 0.6875f, 0.64583f, 0.6875f, 0.66667f),
            WidgetText.barFractions(w, false, 3f),
        )
        // Χωρίς ελάχιστο εύρος: ακριβώς ο παλιός κανόνας (βάση = χαμηλότερο − 0,6 × εύρος).
        close(
            listOf(0.84375f, 0.53125f, 1f, 0.6875f, 0.375f, 0.6875f, 0.53125f),
            WidgetText.barFractions(w, false, 0f),
        )
        // Πραγματική πτώση 4 kg (μεγαλύτερη από το ελάχιστο): όπως πριν, η μικρότερη ράβδος 37,5% της μεγαλύτερης.
        close(listOf(1f, 0.375f), WidgetText.barFractions(listOf(86f, 82f), false, 3f))
        // Ίδια τιμή όλη την εβδομάδα: στη μέση, όχι γεμάτες ράβδοι (82: (82 − 78,7) / 4,8 = 0,6875).
        close(listOf(0.6875f, 0.6875f), WidgetText.barFractions(listOf(82f, 82f), false, 3f))
    }

    /** R2-U3-06: νύχτες 6,9 … 7,6 ώρες από το μηδέν: η νύχτα των 6,5 ωρών 86% της μεγαλύτερης (πριν 38%). */
    @Test
    fun sleepDurationFromZero() {
        val nights = listOf(414f, 444f, 390f, 426f, 408f, 456f, 438f)
        close(
            listOf(0.90789f, 0.97368f, 0.85526f, 0.93421f, 0.89474f, 1f, 0.96053f),
            WidgetText.barFractions(nights, WidgetText.zeroBased("sleep", "sleepMin"), WidgetText.minSpanFor("sleepMin")),
        )
    }

    /** Κενές μέρες μένουν κενές· όλες κενές → τίποτα· ίδιες τιμές χωρίς ελάχιστο → γεμάτες (όπως πριν). */
    @Test
    fun gapsAndEdgeCasesAsBefore() {
        close(listOf(null, 1f, null, 0.375f), WidgetText.barFractions(listOf(null, 86f, null, 82f), false, 0f))
        close(listOf(null, null), WidgetText.barFractions(listOf(null, null), false, 3f))
        close(listOf(1f, 1f), WidgetText.barFractions(listOf(5f, 5f), false, 0f))
        close(listOf(1f, 1f), WidgetText.barFractions(listOf(0f, 0f), true, 0f))
        // Βήματα από το μηδέν, με τον ελάχιστο 8% για να φαίνεται η ράβδος.
        close(listOf(0.08f, 0.5f, 1f), WidgetText.barFractions(listOf(100f, 5000f, 10000f), true, 0f))
    }
}
