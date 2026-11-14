package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/** Round 7, f4: ανάγνωση του αρχείου της χαλασμένης βάσης (R7-A9-1) και σφάλματα αντιγράφου (R7-A9-5). Απλό JVM. */
class R7F4Test {
    private fun tmp(): File = Files.createTempDirectory("r7f4").toFile().also { it.deleteOnExit() }

    @Test
    fun keptCopyIsCopiedWithItsWalUnderTheNormalNamesAndNeverChanged() {
        val dir = tmp()
        val at = 1_731_500_000_000L
        File(dir, DataRules.corruptName("ygeia.db", at)).writeBytes(byteArrayOf(1, 2, 3))
        File(dir, DataRules.corruptName("ygeia.db-wal", at)).writeBytes(byteArrayOf(4, 5))
        File(dir, DataRules.corruptName("ygeia.db-shm", at)).writeBytes(byteArrayOf(6))
        File(dir, DataRules.corruptName("ygeia.db", at + 1)).writeBytes(byteArrayOf(9)) // άλλη βλάβη
        val work = File(tmp(), "salvage")
        val copy = DbSalvage.copyKept(dir, work, at)
        assertEquals(File(work, "ygeia.db"), copy)
        assertArrayEquals(byteArrayOf(1, 2, 3), copy!!.readBytes())
        assertArrayEquals(byteArrayOf(4, 5), File(work, "ygeia.db-wal").readBytes())
        // Το -shm δεν αντιγράφεται (ξαναφτιάχνεται)· ούτε το αρχείο άλλης βλάβης.
        assertEquals(setOf("ygeia.db", "ygeia.db-wal"), work.list()!!.toSet())
        // Το κρατημένο μένει όπως ήταν.
        assertArrayEquals(byteArrayOf(1, 2, 3), File(dir, DataRules.corruptName("ygeia.db", at)).readBytes())
        assertEquals(4, dir.list()!!.size)
        // Καμία κρατημένη βάση για αυτή την ώρα: τίποτα.
        assertNull(DbSalvage.copyKept(dir, File(tmp(), "w2"), at + 2))
    }

    @Test
    fun doneMarkerIsPerCorruption() {
        val at = 1_731_500_000_000L
        // Round 8 (R8-A9-1): το σημάδι γράφει και τον κανόνα ανάγνωσης και αν διαβάστηκαν όλα.
        assertEquals("$at 120 3 ${DbSalvage.RULES} 1", DbSalvage.doneText(at, 120, 3, complete = true))
        assertEquals(120 to 3, DbSalvage.parseDone(DbSalvage.doneText(at, 120, 3, complete = true), at))
        assertEquals(0 to 0, DbSalvage.parseDone("$at 0 0 ${DbSalvage.RULES} 1\n", at))
        // Το σημάδι του #105 («ώρα 0 0») δεν μετρά πια: εκείνη η ανάγνωση μπορεί να μη διάβασε τίποτα (R8-A9-1).
        assertNull(DbSalvage.parseDone("$at 0 0\n", at))
        assertNull(DbSalvage.parseDone(DbSalvage.doneText(at, 1, 1, complete = true), at + 1))
        assertNull(DbSalvage.parseDone(null, at))
        assertNull(DbSalvage.parseDone("", at))
        assertNull(DbSalvage.parseDone("$at x 1 ${DbSalvage.RULES} 1", at))
        assertNull(DbSalvage.parseDone("$at 1", at))
    }

    @Test
    fun backupErrorsGetAKindNotTheJavaText() {
        assertEquals("damaged", BackupRules.failKind(java.io.EOFException("Unexpected end of ZLIB input stream")))
        assertEquals("damaged", BackupRules.failKind(java.util.zip.ZipException("Corrupt GZIP trailer")))
        assertEquals("full", BackupRules.failKind(java.io.IOException("write failed: ENOSPC (No space left on device)")))
        assertEquals("full", BackupRules.failKind(RuntimeException("x", java.io.IOException("No space left on device"))))
        assertEquals("too_big", BackupRules.failKind(BackupRules.TooBig()))
        assertEquals("other", BackupRules.failKind(IllegalStateException("Δεν δημιουργήθηκε αρχείο στις Λήψεις")))
        assertEquals("other", BackupRules.failKind(java.io.IOException("Permission denied")))
        assertTrue(BackupRules.TooBig() is java.io.IOException)
    }

    @Test
    fun aTruncatedGzipBackupIsDamaged() {
        val json = "{\"app\":\"ygeia-forma\",\"version\":1,\"foodLog\":[" + (1..400).joinToString(",") { "{\"id\":\"E$it\"}" } + "]}"
        val full = ByteArrayOutputStream().also { o -> GZIPOutputStream(o).use { it.write(json.toByteArray()) } }.toByteArray()
        // Ολόκληρο: διαβάζεται.
        assertEquals(json, String(GZIPInputStream(ByteArrayInputStream(full)).readBytes()))
        // Μισό κατέβασμα από το Drive: σφάλμα «damaged», όχι κείμενο της Java στην οθόνη.
        val cut = full.copyOf(full.size / 2)
        val e = try {
            GZIPInputStream(ByteArrayInputStream(cut)).readBytes()
            null
        } catch (t: Throwable) {
            t
        }
        assertFalse(e == null)
        assertEquals("damaged", BackupRules.failKind(e!!))
        // Χαλασμένη ουρά (CRC): επίσης «damaged».
        val badTrailer = full.copyOf().also { it[it.size - 6] = (it[it.size - 6] + 1).toByte() }
        val e2 = try {
            GZIPInputStream(ByteArrayInputStream(badTrailer)).readBytes()
            null
        } catch (t: Throwable) {
            t
        }
        assertFalse(e2 == null)
        assertEquals("damaged", BackupRules.failKind(e2!!))
    }
}
