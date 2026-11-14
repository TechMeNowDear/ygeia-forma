package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Αίτημα χρήστη 14/11: «τα μικρά γράμματα και οι αριθμοί [των widgets] είναι πολύ μικροί… ακόμα και αν έχει λιγότερη
 * πληροφόρηση». Μεγαλύτερα μικρά γράμματα, λιγότερα κουτάκια, και ο αριθμός ενός κουτιού ποτέ κομμένος για τη μονάδα.
 */
class WidgetSizesTest {
    @Test
    fun smallTextIsNoticeablyBigger() {
        // Τουλάχιστον 12 sp κάθε μικρή γραμμή, και η τιμή του κουτιού ≥ 18 sp (πριν 9,5–10,5 και 13).
        for (s in listOf(WidgetText.TITLE_SP, WidgetText.SOURCE_SP, WidgetText.CAPTION_SP, WidgetText.CHIP_LABEL_SP, WidgetText.CHIP_UNIT_SP)) {
            assertTrue("$s", s >= 12f)
        }
        assertTrue(WidgetText.CHIP_VALUE_SP >= 18f)
        // Μικραίνει (όταν δεν χωρά) το πολύ ως 85%: ποτέ κάτω από ≈ 10,2 sp.
        assertTrue(WidgetText.CHIP_LABEL_SP * WidgetText.MIN_SCALE_SMALL >= 10f)
        // Όλες οι μικρές γραμμές μετρούν ως «μικρές» (όριο 85%, όχι 75%)· η τιμή του κουτιού όχι.
        assertTrue(WidgetText.CAPTION_SP < WidgetText.SMALL_LINE_SP)
        assertTrue(WidgetText.CHIP_VALUE_SP > WidgetText.SMALL_LINE_SP)
    }

    @Test
    fun fewerBoxes() {
        assertEquals(3, WidgetRenderer.maxValues(WidgetRenderer.Shape.COLUMN1))
        assertEquals(6, WidgetRenderer.maxValues(WidgetRenderer.Shape.COLUMN2))
        assertEquals(2, WidgetRenderer.maxValues(WidgetRenderer.Shape.SMALL))
        assertEquals(4, WidgetRenderer.maxValues(WidgetRenderer.Shape.WIDE))
    }

    @Test
    fun shortNamesInsteadOfCutWords() {
        assertEquals("Υδατ/κες", WidgetText.shortLabel("carbs"))
        assertEquals("BMR", WidgetText.shortLabel("bmr"))
        assertEquals(null, WidgetText.shortLabel("protein"))
    }

    @Test
    fun numberFirstThenUnit() {
        // «1.930 kcal» χωρά: και τα δύο.
        assertTrue(WidgetText.chipWithUnit(50f, 30f, 90f))
        // Δεν χωρά: μόνο ο αριθμός, ολόκληρος (όχι «1.9…»).
        assertFalse(WidgetText.chipWithUnit(50f, 30f, 70f))
        // Χωρίς μονάδα: τίποτα να προστεθεί.
        assertFalse(WidgetText.chipWithUnit(50f, 0f, 90f))
        val src = File("src/main/kotlin/gr/ygeiaforma/ygeia_forma/WidgetRenderer.kt").takeIf { it.exists() }
            ?: File("android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/WidgetRenderer.kt")
        assertTrue(src.path, src.exists())
        val s = src.readText()
        assertTrue(s.contains("val vt = if (withTail) v else fit(v, vp, avail)"))
        assertFalse(s.contains("sp(9.5f)"))
        assertFalse(s.contains("sp(10.5f)"))
    }
}
