package gr.ygeiaforma.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Τα features της #100 στο ρολόι (13/11). Καθαρή JVM, χωρίς Robolectric. */
class Features100Test {
    /** Γ3: ρωτά μόνο όταν το Health Services είπε καθαρά «τρέχει άσκηση άλλης εφαρμογής». */
    @Test
    fun asksOnlyWhenAnotherAppIsMeasuring() {
        assertTrue(OtherAppAsk.ask(true))
        assertFalse(OtherAppAsk.ask(false))
        // Καμία απάντηση (όριο χρόνου ή σφάλμα): ξεκινά όπως πριν· η ερώτηση δεν μπλοκάρει ποτέ την προπόνηση.
        assertFalse(OtherAppAsk.ask(null))
    }

    /** Τα κείμενα όπως εγκρίθηκαν 12/11 (egkriseis-keimenon, 21–22). */
    @Test
    fun approvedTexts() {
        assertEquals("Τρέχει άσκηση σε άλλη εφαρμογή. Αν ξεκινήσεις εδώ, εκείνη σταματά.", OtherAppAsk.TEXT)
        assertEquals("Ξεκίνα εδώ", OtherAppAsk.YES)
        assertEquals("Άκυρο", OtherAppAsk.NO)
    }

    /** Η καταμέτρηση ποιότητας παλμών φτάνει στο κινητό μέσα στο «diag», σε μορφή που το κινητό διαβάζει (hr_quality.dart). */
    @Test
    fun hrQualityTextIsWhatThePhoneReads() {
        val q = HrQualityCount()
        assertEquals("5s=1 wake=1", q.withDiag("5s=1 wake=1"))
        val re = Regex("(?:^| )q=(\\d{1,9})/(\\d{1,9})/(\\d{1,9})(?: |$)")
        repeat(3) { q.add(HrQuality.OK) }
        q.add(HrQuality.LOW)
        val m = re.find(q.withDiag("5s=1 wake=1"))!!
        assertEquals(listOf("3", "1", "0"), m.groupValues.drop(1))
    }
}
