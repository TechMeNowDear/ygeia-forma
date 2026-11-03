package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.LocalDate

/** Απλό JVM (χωρίς συσκευή): οι κανόνες δεδομένων του ελέγχου 4/11 (κομμάτι A). */
class DataRulesTest {
    @Test
    fun watchOnlyTypesAndScaleApp() {
        // A2: ύπνος, παλμοί, οξυγόνο, θερμοκρασία μόνο από ρολόι· όχι βήματα (σύνολο της Samsung) ούτε ζυγίσεις.
        assertEquals(setOf("sleep", "heart_rate", "blood_oxygen", "skin_temperature"), DataRules.WATCH_ONLY)
        assertTrue(DataRules.isScaleApp("com.inbody2014.inbody"))
        assertTrue(DataRules.isScaleApp("kr.co.InBody.x"))
        assertFalse(DataRules.isScaleApp("com.sec.android.app.shealth"))
        assertFalse(DataRules.isScaleApp("com.samsung.android.wear.shealth"))
        assertFalse(DataRules.isScaleApp(""))
        assertFalse(DataRules.isScaleApp(null))
    }

    @Test
    fun sleepPolicyReadErrorIsAnErrorNotNoSleep() {
        val key: (String) -> String = { t -> Regex("\"sleepUntil\":\"([^\"]*)\"").find(t)?.groupValues?.get(1) ?: "" }
        // Χωρίς αρχείο: χωρίς όριο, χωρίς σφάλμα.
        assertEquals(DataRules.SleepLimit(null, false), DataRules.sleepLimit(false, { error("δεν καλείται") }, key))
        // Κανονικό αρχείο.
        assertEquals(
            DataRules.SleepLimit(LocalDate.of(2026, 11, 19), false),
            DataRules.sleepLimit(true, { "{\"sleepUntil\":\"2026-11-19\"}" }, key),
        )
        // Αρχείο χωρίς όριο (τελευταία εποχή ρολόι).
        assertEquals(DataRules.SleepLimit(null, false), DataRules.sleepLimit(true, { "{}" }, key))
        // A15: αρχείο που δεν διαβάζεται ή έχει λάθος ημερομηνία → σφάλμα (όχι «καθόλου ύπνος»).
        assertTrue(DataRules.sleepLimit(true, { throw java.io.IOException("x") }, key).error)
        assertTrue(DataRules.sleepLimit(true, { "{\"sleepUntil\":\"2026-13-45\"}" }, key).error)
        assertTrue(DataRules.sleepLimit(true, { "{\"sleepUntil\":\"χθες\"}" }, key).error)
    }

    @Test
    fun corruptDatabaseIsKeptNeverDeleted() {
        val root = Files.createTempDirectory("ygeia").toFile()
        val db = File(root, "ygeia.db").apply { writeText("ΒΑΣΗ") }
        File(root, "ygeia.db-wal").writeText("WAL")
        val dir = File(root, "corrupt")
        val kept = DataRules.keepCorrupt(db, dir, 1730000000000L)
        assertEquals(File(dir, "ygeia.db.corrupt-1730000000000"), kept)
        assertEquals("ΒΑΣΗ", kept!!.readText())
        assertEquals("WAL", File(dir, "ygeia.db-wal.corrupt-1730000000000").readText())
        assertFalse("η θέση της βάσης αδειάζει για καινούργια", db.exists())
        assertNull(DataRules.keepCorrupt(File(root, "δεν-υπάρχει.db"), dir, 1L))
        root.deleteRecursively()
    }

    @Test
    fun browserHostsIncludeNewOuraAuthorizePage() {
        // A13: η σελίδα σύνδεσης για νέες εφαρμογές της Oura πρέπει να ανοίγει (αλλιώς «Δεν άνοιξε ο browser»).
        assertTrue(DataRules.ALLOWED_HOSTS.contains("developer.ouraring.com"))
        assertTrue(DataRules.ALLOWED_HOSTS.contains("cloud.ouraring.com"))
        assertTrue(DataRules.ALLOWED_HOSTS.contains("api.ouraring.com"))
        assertFalse(DataRules.ALLOWED_HOSTS.contains("ouraring.com.evil.com"))
        assertEquals(3, DataRules.ALLOWED_HOSTS.size)
    }
}
