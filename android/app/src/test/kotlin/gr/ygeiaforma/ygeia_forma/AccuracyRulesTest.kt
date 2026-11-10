package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Έλεγχος 9/11 (fix-accuracy): μηνύματα για το Sentry και extras από άλλες εφαρμογές (απλό JVM). */
class AccuracyRulesTest {
    @Test
    fun subclassesOfDataCarryingErrorsSendNoMessage() {
        // E3-19: το NumberFormatException είναι IllegalArgumentException· το μήνυμά του έχει το κείμενο που διάβαζε.
        assertEquals("", DataRules.reportableMessage(NumberFormatException::class.java, "For input string: \"82,4\""))
        assertEquals("", DataRules.reportableMessage(IllegalArgumentException::class.java, "Failed requirement: 82.4"))
        assertEquals("Η βάση χάλασε", DataRules.reportableMessage(IllegalStateException::class.java, "Η βάση χάλασε"))
    }

    @Test
    fun onlyWidgetShapedOpenTargetsPass() {
        // E3-24: ό,τι φτιάχνουν τα widgets περνά· οτιδήποτε άλλο από άλλη εφαρμογή όχι.
        assertEquals("w:sleep:section:", DataRules.widgetOpenTarget("w:sleep:section:"))
        assertEquals("w:food:add:", DataRules.widgetOpenTarget("w:food:add:"))
        assertEquals("w:body:metric:weight", DataRules.widgetOpenTarget("w:body:metric:weight"))
        assertNull(DataRules.widgetOpenTarget(null))
        assertNull(DataRules.widgetOpenTarget("w:sleep:section:x\n"))
        assertNull(DataRules.widgetOpenTarget("w:evil:section:"))
        assertNull(DataRules.widgetOpenTarget("w:sleep:delete:"))
        assertNull(DataRules.widgetOpenTarget("w:sleep:metric:" + "a".repeat(40)))
        assertNull(DataRules.widgetOpenTarget("https://example.com"))
        // Μέγεθος προεπισκόπησης: μόνο λογικές τιμές.
        assertEquals(180.0, DataRules.previewDp(180)!!, 0.0)
        assertNull(DataRules.previewDp(0))
        assertNull(DataRules.previewDp(100000))
    }
}
