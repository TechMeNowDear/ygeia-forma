package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Round 2 · g5: η κρίση του εύρους στα widgets της αρχικής οθόνης (WidgetText.usualLines). Καθαρό JVM. Φανταστικές
 * τιμές (δημόσιο repo).
 */
class R2G5Test {
    /** Πλάτος ανά χαρακτήρα σταθερό (1 μονάδα), για να είναι προβλέψιμο. */
    private fun fitsIn(w: Int): (String) -> Boolean = { it.length <= w }

    /**
     * R2-D-1: η κρίση του μέσου όρου των νυχτών δεν γράφεται ποτέ χωρίς το «N νύχτες». Πριν, σε στενή στήλη έμενε σκέτο
     * «κάτω από το εύρος» κάτω από τη χθεσινή νύχτα (π.χ. 7:16 ώρες, πάνω από τις 7), σαν κρίση για εκείνη.
     */
    @Test
    fun verdictNeverLosesItsNights() {
        val usuals = listOf(null, "▲ συνήθως 6:58", "▼ συνήθως 7:05", "συνήθως 14,0")
        val ranges = listOf(
            "7 νύχτες κάτω από το εύρος",
            "7 νύχτες μέσα στο εύρος",
            "5 νύχτες πάνω από το εύρος",
            "4 νύχτες κοντά στο κάτω όριο",
            "6 νύχτες κοντά στο πάνω όριο",
            "1 νύχτα κάτω από το εύρος",
        )
        for (us in usuals) {
            for (r in ranges) {
                for (w in 1..70) {
                    val lines = WidgetText.usualLines(us, r, fitsIn(w))
                    for (line in lines) {
                        assertTrue("«$line» (πλάτος $w) χωρίς τη λέξη νύχτα/νύχτες", !(line.contains("εύρος") || line.contains("όριο")) || line.contains("νύχτ"))
                        assertTrue(line.length <= w)
                        assertFalse(line.endsWith("…"))
                    }
                    // Η κρίση είτε ολόκληρη είτε καθόλου.
                    assertTrue(lines.none { it.contains("εύρος") || it.contains("όριο") } || lines.any { it.contains(r) })
                }
            }
        }
    }

    /** R2-D-1: το σενάριο του ελέγχου: στενή στήλη που χωρά το «κάτω από το εύρος» αλλά όχι ολόκληρη την κρίση. */
    @Test
    fun narrowColumnShowsUsualOnly() {
        val us = "▲ συνήθως 6:58"
        val r = "7 νύχτες κάτω από το εύρος"
        // «κάτω από το εύρος» = 17 χαρακτήρες· η κρίση ολόκληρη = 26.
        assertEquals(listOf(us), WidgetText.usualLines(us, r, fitsIn(20)))
        assertEquals(emptyList<String>(), WidgetText.usualLines(null, r, fitsIn(20)))
        assertEquals(listOf(us, r), WidgetText.usualLines(us, r, fitsIn(26)))
        assertEquals(listOf("$us · $r"), WidgetText.usualLines(us, r, fitsIn(43)))
        // Κρίσεις χωρίς νύχτες («χθες …», σώμα) μένουν όπως ήταν: ολόκληρες όταν χωρούν.
        assertEquals(listOf("χθες μέσα στο εύρος"), WidgetText.usualLines(null, "χθες μέσα στο εύρος", fitsIn(19)))
        assertEquals(emptyList<String>(), WidgetText.usualLines(null, "χθες μέσα στο εύρος", fitsIn(18)))
    }
}
