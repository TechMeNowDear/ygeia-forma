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

    @Test
    fun sleepWithTwoSessionsBecomesTwoRecords() {
        // Έλεγχος 2, C2: η νύχτα 2→3/11 ως ΜΙΑ εγγραφή της Samsung με δύο συνεδρίες (23:43–02:40, 03:50–07:08).
        val m = 60_000L
        val t0 = 1_762_119_780_000L // 23:43
        val a = DataRules.SessionIn(t0, t0 + 177 * m, 177, listOf(DataRules.StageIn("LIGHT", t0, t0 + 177 * m)))
        val b = DataRules.SessionIn(t0 + 247 * m, t0 + 445 * m, 198, emptyList())
        val out = DataRules.splitSleep(t0, t0 + 445 * m, 445, 40, listOf(b, a))
        assertEquals(2, out.size)
        assertEquals(t0, out[0].start)
        assertEquals(t0 + 177 * m, out[0].end)
        assertEquals(177L, out[0].minutes)
        assertEquals(1, out[0].stages.size)
        assertEquals(t0 + 247 * m, out[1].start)
        assertEquals(t0 + 445 * m, out[1].end)
        assertTrue("συνεδρία χωρίς φάσεις μένει χωριστή", out[1].stages.isEmpty())
        assertNull("η βαθμολογία είναι όλης της εγγραφής, όχι μιας συνεδρίας", out[0].score)
        assertNull(out[1].score)
        // Το κενό 02:40–03:50 δεν ανήκει σε καμία εγγραφή.
        assertTrue(out.none { it.start < t0 + 247 * m && it.end > t0 + 177 * m })
    }

    @Test
    fun sleepWithOneSessionStaysAsBefore() {
        val s = DataRules.SessionIn(5L, 100L, null, listOf(DataRules.StageIn("DEEP", 5L, 100L)))
        assertEquals(listOf(DataRules.SleepOut(0L, 120L, 2L, 77, s.stages)), DataRules.splitSleep(0L, 120L, 2L, 77, listOf(s)))
        assertEquals(listOf(DataRules.SleepOut(0L, 120L, 2L, 77, emptyList())), DataRules.splitSleep(0L, 120L, 2L, 77, emptyList()))
        // Συνεδρίες χωρίς χρόνους: παίρνουν τα όρια από τις φάσεις τους, ή (καμία) όλη η εγγραφή.
        val x = DataRules.SessionIn(null, null, null, listOf(DataRules.StageIn("LIGHT", 10L, 70_010L)))
        val y = DataRules.SessionIn(null, null, null, emptyList())
        assertEquals(listOf(DataRules.SleepOut(10L, 70_010L, 1L, null, x.stages)), DataRules.splitSleep(0L, 200_000L, 3L, 9, listOf(x, y)))
    }

    @Test
    fun watchFilterEmptyIsAnError() {
        // Έλεγχος 2, C6: 0 με φίλτρο ρολογιού ενώ υπάρχουν χωρίς φίλτρο = σφάλμα (κρατάμε το ιστορικό).
        assertTrue(DataRules.watchFilterEmpty(0, 1))
        assertFalse(DataRules.watchFilterEmpty(0, 0))
        assertFalse(DataRules.watchFilterEmpty(3, 5))
        assertEquals("watch_filter_empty", DataRules.WATCH_FILTER_EMPTY)
    }

    @Test
    fun corruptHandlerClosesOnlyAnOpenDatabase() {
        // Έλεγχος 2, C8: στο πρώτο άνοιγμα η βάση δεν είναι ανοιχτή ακόμα· close() θα έκανε το άνοιγμα να αποτύχει.
        var closed = 0
        DataRules.closeIfOpen(false) { closed++ }
        assertEquals(0, closed)
        DataRules.closeIfOpen(true) { closed++ }
        assertEquals(1, closed)
        DataRules.closeIfOpen(true) { throw IllegalStateException("ήδη κλειστή") }
    }

    @Test
    fun corruptMoveKeepsMainDbWhenWalCannotMove() {
        // C14 (R11): αν δεν μετακινηθεί το -wal, η κύρια βάση ΔΕΝ φεύγει (αλλιώς η νέα βάση θα έπαιζε το παλιό -wal).
        val root = Files.createTempDirectory("ygeia").toFile()
        val db = File(root, "ygeia.db").apply { writeText("ΒΑΣΗ") }
        File(root, "ygeia.db-wal").writeText("WAL")
        val dir = File(root, "corrupt")
        // Ο προορισμός του -wal είναι φάκελος με περιεχόμενο: ούτε μετονομασία ούτε αντιγραφή γίνεται.
        File(dir, "ygeia.db-wal.corrupt-7").apply { mkdirs() }.resolve("x").writeText("x")
        try {
            DataRules.keepCorrupt(db, dir, 7L)
        } catch (_: Throwable) {
        }
        assertTrue("η κύρια βάση μένει στη θέση της", db.exists())
        assertEquals("ΒΑΣΗ", db.readText())
        root.deleteRecursively()
    }

    @Test
    fun reportsNoDataSnippetsKeystoreRegeneratesCallbackKeptUntilAccepted() {
        // C14 (R13): μηνύματα org.json / require() έχουν κομμάτια δεδομένων· στο Sentry μόνο ο τύπος.
        assertEquals("", DataRules.reportableMessage("org.json.JSONException", "Value {\"kcal\":12} of type x"))
        assertEquals("", DataRules.reportableMessage("java.lang.IllegalArgumentException", "Failed requirement: 82.4"))
        assertEquals("Η βάση χάλασε", DataRules.reportableMessage("java.lang.IllegalStateException", "Η βάση χάλασε"))
        // C14 (R14): κλειδί που δεν ανακτάται → νέο κλειδί· άλλο σφάλμα → όχι.
        assertTrue(DataRules.regenerateKeyOn(java.security.UnrecoverableKeyException("x")))
        assertFalse(DataRules.regenerateKeyOn(java.io.IOException("x")))
        // C14 (R12): η επιστροφή της Oura μένει ώσπου η Flutter να απαντήσει «success».
        assertTrue(DataRules.callbackDelivered("success"))
        assertFalse(DataRules.callbackDelivered("notImplemented"))
        assertFalse(DataRules.callbackDelivered("error"))
    }
}
