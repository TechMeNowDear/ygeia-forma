package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

/** Round 7 · f8: η στιγμή μιας ανάγνωσης της Samsung (R7-A10-4). Απλό JVM, χωρίς Android. */
class R7F8Test {
    private val athens = ZoneId.of("Europe/Athens")

    @Test
    fun readStartedJustBeforeMidnightBelongsToThatDay() {
        // 12/11/2026 23:59:55 Αθήνα (+02:00) = 21:59:55Z. Η ανάγνωση τελειώνει μετά τα μεσάνυχτα, αλλά τα «σημερινά»
        // σύνολα (δραστηριότητα, βήματα) και το «readAt» είναι της 12/11.
        val ms = 1794520795000L
        val m = DataRules.readMoment(ms, athens)
        assertEquals(ms, m.ms)
        assertEquals(LocalDateTime.of(2026, 11, 12, 23, 59, 55), m.now)
        assertEquals(LocalDate.of(2026, 11, 12), m.today)
    }

    @Test
    fun repeatedHourAtTheEndOfSummerTimeKeepsTheRealInstant() {
        // 31/10/2027: 04:00 θερινή → 03:00 χειμερινή. 01:30Z = η ΔΕΥΤΕΡΗ 03:30 της νύχτας (+02:00).
        val ms = 1824946200000L
        val m = DataRules.readMoment(ms, athens)
        assertEquals(ms, m.ms)
        assertEquals(LocalDateTime.of(2027, 10, 31, 3, 30), m.now)
        assertEquals(LocalDate.of(2027, 10, 31), m.today)
        // Από την τοπική ώρα πίσω σε ms βγαίνει η ΠΡΩΤΗ 03:30 (+03:00), μία ώρα νωρίτερα: γι' αυτό το «readAt» είναι τα ms.
        assertEquals(ms - 3_600_000L, m.now.atZone(athens).toInstant().toEpochMilli())
    }
}
