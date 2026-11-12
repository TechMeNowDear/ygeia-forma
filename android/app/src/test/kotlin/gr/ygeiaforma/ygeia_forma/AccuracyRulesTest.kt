package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        // 13/11: τα δύο νέα widgets («Προπόνηση σήμερα», «Γρήγορο φαγητό»).
        assertEquals("w:workout:section:", DataRules.widgetOpenTarget("w:workout:section:"))
        assertEquals("w:food:scan:", DataRules.widgetOpenTarget("w:food:scan:"))
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

    @Test
    fun watchResultsFromBeforeWipeAreDropped() {
        // M1: η ώρα αρχής κάθε είδους αποτελέσματος του ρολογιού.
        assertEquals(1762700000000L, DataRules.resultStart("""{"v":1,"id":"walk1762700000000","kind":"cardio","start":1762700000000,"end":1762701800000}""", 5L))
        assertEquals(1762700000000L, DataRules.resultStart("""{"v":1,"kind":"hr","sid":"s9","id":"hrs9-1762700000000","hr":[]}""", 5L))
        assertEquals(1762700000000L, DataRules.resultStart("""{"v":1,"id":"w1762700000000","items":[]}""", 5L))
        assertEquals(42L, DataRules.resultStart("""{"v":1}""", 42L))
        assertEquals(42L, DataRules.resultStart("όχι json", 42L))
        // Πριν από τη διαγραφή: δεν μπαίνει· μετά: μπαίνει· καμία διαγραφή: πάντα.
        assertTrue(DataRules.droppedByWipe(1762700000000L, 1762800000000L))
        assertFalse(DataRules.droppedByWipe(1762900000000L, 1762800000000L))
        assertFalse(DataRules.droppedByWipe(1762700000000L, 0L))
        // N3: ό,τι γράφτηκε στο Data Layer πριν από τη διαγραφή σβήνεται όσο περιμένουμε το ρολόι.
        assertTrue(DataRules.writtenBeforeWipe(1762700000000L, 1762800000000L))
        assertFalse(DataRules.writtenBeforeWipe(1762900000000L, 1762800000000L))
        assertFalse(DataRules.writtenBeforeWipe(1762700000000L, 0L))
    }
}
