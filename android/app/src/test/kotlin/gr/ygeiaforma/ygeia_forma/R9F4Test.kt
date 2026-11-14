package gr.ygeiaforma.ygeia_forma

import org.json.JSONArray
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * Round 9, f4: ανάγνωση του αρχείου της χαλασμένης βάσης — κομμένο αρχείο (R9-A9-1), ίδιο id δύο φορές (R9-A9-2), σημάδι
 * του #105 (R9-A9-3), καλές σελίδες ανάμεσα σε δύο χαλασμένες περιοχές (R9-A9-4), «δεν διαβάστηκαν όλα» για την κάρτα
 * (R9-A9-B1) και η απάντηση «dbStatus» της γέφυρας με τιμές (R9-A12-2). Απλό JVM· δεδομένα επινοημένα.
 */
class R9F4Test {
    private fun tmp(): File = Files.createTempDirectory("r9f4").toFile().also { it.deleteOnExit() }

    private fun ids(a: JSONArray): List<String> = (0 until a.length()).map { a.getJSONObject(it).getString("id") }

    /** Ο ίδιος ψεύτικος πίνακας με το R8F4Test (σελίδες, «rowid ≥ from … LIMIT n», όλο το ερώτημα πετά σε χαλασμένη σελίδα). */
    private class FakeTable(val rowids: List<Long>, perPage: Int, val bad: Set<Int>) {
        private val pages: List<List<Long>> = rowids.chunked(perPage)
        private val pageOf: Map<Long, Int> = HashMap<Long, Int>().also { m ->
            pages.forEachIndexed { i, p -> for (r in p) m[r] = i }
        }
        var queries = 0
        val source = DbSalvage.RowSource { from, limit ->
            queries++
            val seek = pages.indexOfFirst { it.last() >= from }.let { if (it < 0) pages.size - 1 else it }
            if (seek in bad) throw IllegalStateException("database disk image is malformed")
            val out = ArrayList<DbSalvage.Row>()
            for (r in rowids) {
                if (r < from) continue
                if (pageOf.getValue(r) in bad) throw IllegalStateException("database disk image is malformed")
                out.add(DbSalvage.Row(r, "E$r", "{\"id\":\"E$r\"}"))
                if (out.size == limit) break
            }
            out
        }
    }

    // ---------------------------------------------------------------------------------------------------------------
    // R9-A9-1: κεφαλίδα που λέει περισσότερες σελίδες από όσες έχει το αρχείο.

    /** Κεφαλίδα SQLite: μέγεθος σελίδας [pageSize] (65.536 γράφεται 1), [pages] σελίδες, μετρητής [counter] και στο 92–95 [valid]. */
    private fun sqliteFile(length: Int, pageSize: Int, pages: Long, counter: Long, valid: Long): ByteArray {
        val b = ByteArray(length) { (it % 251).toByte() }
        val magic = "SQLite format 3\u0000".toByteArray(Charsets.US_ASCII)
        System.arraycopy(magic, 0, b, 0, 16)
        val ps = if (pageSize == 65_536) 1 else pageSize
        b[16] = (ps shr 8).toByte()
        b[17] = ps.toByte()
        fun put(at: Int, v: Long) {
            b[at] = (v ushr 24).toByte()
            b[at + 1] = (v ushr 16).toByte()
            b[at + 2] = (v ushr 8).toByte()
            b[at + 3] = v.toByte()
        }
        put(24, counter)
        put(28, pages)
        put(92, valid)
        return b
    }

    private fun u32(b: ByteArray, at: Int): Long =
        ((b[at].toLong() and 0xff) shl 24) or ((b[at + 1].toLong() and 0xff) shl 16) or
            ((b[at + 2].toLong() and 0xff) shl 8) or (b[at + 3].toLong() and 0xff)

    @Test
    fun aTruncatedFileGetsItsPageCountIgnoredOnTheCopyOnly() {
        val dir = tmp()
        val at = 1_731_500_000_000L
        // Η κεφαλίδα λέει 10 σελίδες των 512· το αρχείο κόπηκε στις 8.
        val kept = sqliteFile(8 * 512, 512, pages = 10, counter = 7, valid = 7)
        File(dir, DataRules.corruptName("ygeia.db", at)).writeBytes(kept)
        val copy = DbSalvage.copyKept(dir, File(tmp(), "salvage"), at)!!
        val b = copy.readBytes()
        // Στο αντίγραφο το 92–95 ≠ 24–27: η SQLite μετρά τις σελίδες από το μέγεθος του αρχείου.
        assertEquals(7L, u32(b, 24))
        assertEquals(8L, u32(b, 92))
        // Τίποτα άλλο δεν άλλαξε στο αντίγραφο, και το κρατημένο αρχείο μένει όπως ήταν.
        for (i in b.indices) if (i !in 92..95) assertEquals("byte $i", kept[i], b[i])
        assertArrayEquals(kept, File(dir, DataRules.corruptName("ygeia.db", at)).readBytes())
    }

    @Test
    fun oneBitInThePageCountAndTheLargestPageSize() {
        val f = File(tmp(), "a.db")
        // 4 σελίδες των 4.096, αλλά ένα bit στο byte 29 → 65.540 σελίδες.
        f.writeBytes(sqliteFile(4 * 4096, 4096, pages = 4L + (1L shl 16), counter = 0xffffffffL, valid = 0xffffffffL))
        assertTrue(DbSalvage.fixPageCount(f))
        // Ο μετρητής στο μέγιστο: η νέα τιμή γυρίζει στο 0 (διαφορετική από τον μετρητή).
        assertEquals(0L, u32(f.readBytes(), 92))
        // Σελίδα 65.536 (γράφεται «1»): 2 σελίδες στην κεφαλίδα, μία στο αρχείο.
        val g = File(tmp(), "b.db")
        g.writeBytes(sqliteFile(65_536, 65_536, pages = 2, counter = 3, valid = 3))
        assertTrue(DbSalvage.fixPageCount(g))
        assertEquals(4L, u32(g.readBytes(), 92))
    }

    @Test
    fun aHealthyOrAlreadyIgnoredHeaderOrNotSqliteIsLeftAlone() {
        val d = tmp()
        fun same(name: String, bytes: ByteArray) {
            val f = File(d, name)
            f.writeBytes(bytes)
            assertFalse(name, DbSalvage.fixPageCount(f))
            assertArrayEquals(name, bytes, f.readBytes())
        }
        // Ίδιες σελίδες με το αρχείο.
        same("ok.db", sqliteFile(8 * 512, 512, pages = 8, counter = 7, valid = 7))
        // Μισή τελευταία σελίδα: η SQLite τη μετρά (στρογγυλοποίηση προς τα πάνω), όπως κι εδώ.
        same("half.db", sqliteFile(7 * 512 + 100, 512, pages = 8, counter = 7, valid = 7))
        // Ο αριθμός σελίδων ήδη άκυρος (24–27 ≠ 92–95).
        same("ignored.db", sqliteFile(8 * 512, 512, pages = 10, counter = 7, valid = 6))
        // Όχι SQLite, πολύ μικρό, άκυρο μέγεθος σελίδας.
        same("text.db", ByteArray(4096) { 'x'.code.toByte() })
        same("tiny.db", byteArrayOf(1, 2, 3))
        same("size.db", sqliteFile(8 * 512, 700, pages = 10, counter = 7, valid = 7))
        // Κανένα αρχείο: τίποτα (χωρίς σφάλμα).
        assertFalse(DbSalvage.fixPageCount(File(d, "κανένα/x.db")))
    }

    // ---------------------------------------------------------------------------------------------------------------
    // R9-A9-2: ίδιο id σε δύο γραμμές → η νεότερη (μεγαλύτερο rowid).

    @Test
    fun theUsersCorrectionWinsOverAStalePageWithTheOldVersion() {
        // Διόρθωση 300 g → 150 g με «INSERT OR REPLACE» (νέο rowid 301)· η σελίδα της παλιάς γραμμής (rowid 51) έμεινε ως ήταν.
        val rows = listOf(
            DbSalvage.Row(51, "E50", "{\"id\":\"E50\",\"grams\":300}"),
            DbSalvage.Row(120, "E7", "{\"id\":\"E7\",\"grams\":80}"),
            DbSalvage.Row(301, "E50", "{\"id\":\"E50\",\"grams\":150}"),
        )
        val source = DbSalvage.RowSource { from, limit -> rows.filter { it.rowid >= from }.take(limit) }
        val out = JSONArray()
        val r = DbSalvage.read(source, emptySet(), out)
        assertEquals(listOf("E50", "E7"), ids(out))
        assertEquals(150, out.getJSONObject(0).getInt("grams"))
        assertEquals(DbSalvage.Read(skipped = 0, lost = 0, complete = true), r)
    }

    @Test
    fun aNewestRowThatDoesNotParseIsNotReplacedByTheOldVersion() {
        val rows = listOf(
            DbSalvage.Row(1, "E9", "{\"id\":\"E9\",\"grams\":300}"),
            DbSalvage.Row(2, "E9", "{\"id\":\"E9\",\"gra"), // η νεότερη, χαλασμένη
            DbSalvage.Row(3, "E3", "{\"id\":\"E3\",\"grams\":2}"),
            DbSalvage.Row(4, "E3", "{\"id\":\"E3\",\"grams\":1}"),
        )
        val source = DbSalvage.RowSource { from, limit -> rows.filter { it.rowid >= from }.take(limit) }
        val out = JSONArray()
        val r = DbSalvage.read(source, emptySet(), out)
        assertEquals(listOf("E3"), ids(out))
        assertEquals(1, out.getJSONObject(0).getInt("grams"))
        assertEquals(1, r.skipped)
    }

    // ---------------------------------------------------------------------------------------------------------------
    // R9-A9-4: καλές σελίδες ανάμεσα σε δύο χαλασμένες περιοχές.

    private fun expectAllBut(t: FakeTable, bad: Set<Int>, perPage: Int) {
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out)
        val gone = bad.flatMap { p -> (p * perPage + 1)..(p * perPage + perPage) }.toSet()
        assertEquals((1..2000).filter { it !in gone }.map { "E$it" }, ids(out))
        assertFalse(r.complete)
        assertTrue("λίγα ερωτήματα: ${t.queries}", t.queries < 400)
    }

    @Test
    fun aGoodPageBetweenTwoNearbyDamagedAreasIsRead() {
        // Το παράδειγμα της αναφοράς: χαλασμένες 100–106 και 108–114, καλή η 107 (E536–E540). Πριν: χανόταν.
        val bad = (100..106).toSet() + (108..114).toSet()
        expectAllBut(FakeTable((1L..2000L).toList(), 5, bad), bad, 5)
    }

    @Test
    fun aGoodPageBetweenTwoLargeDamagedAreasIsRead() {
        // 100 rowid χαλασμένα, 5 καλά (E601–E605), 100 χαλασμένα: τα διπλάσια βήματα πηδούν πάνω από την καλή σελίδα.
        val bad = (100..119).toSet() + (121..140).toSet()
        expectAllBut(FakeTable((1L..2000L).toList(), 5, bad), bad, 5)
    }

    // ---------------------------------------------------------------------------------------------------------------
    // R9-A9-3: σημάδι του #105 («ώρα καταχωρίσεις προϊόντα»).

    @Test
    fun anOldMarkerKeepsTheTablesThatCameBackThen() {
        val at = 1_731_500_000_000L
        // Ξαναμπήκαν και καταχωρίσεις και προϊόντα: έγινε (όσα σβήστηκαν μετά δεν ξαναμπαίνουν).
        assertEquals(412 to 6, DbSalvage.parseDone("$at 412 6", at))
        assertEquals(true to true, DbSalvage.oldDone("$at 412 6\n", at))
        assertTrue(DbSalvage.finished("$at 412 6", at))
        // Καμία καταχώριση τότε (π.χ. η ανάγνωση απέτυχε): ξαναδιαβάζεται ΜΟΝΟ το ημερολόγιο.
        assertNull(DbSalvage.parseDone("$at 0 6", at))
        assertEquals(false to true, DbSalvage.oldDone("$at 0 6", at))
        assertFalse(DbSalvage.finished("$at 0 6", at))
        assertEquals(true to false, DbSalvage.oldDone("$at 412 0", at))
        assertNull(DbSalvage.parseDone("$at 0 0", at))
        assertEquals(false to false, DbSalvage.oldDone("$at 0 0", at))
        // Άλλη βλάβη, σημάδι του #106+, χαλασμένο, κανένα: τίποτα από το παλιό σημάδι.
        assertEquals(false to false, DbSalvage.oldDone("${at + 1} 412 6", at))
        assertNull(DbSalvage.parseDone("${at + 1} 412 6", at))
        assertEquals(false to false, DbSalvage.oldDone("$at 412 6 3 1", at))
        assertEquals(false to false, DbSalvage.oldDone("$at x y", at))
        assertEquals(false to false, DbSalvage.oldDone(null, at))
    }

    // ---------------------------------------------------------------------------------------------------------------
    // R9-A9-B1 + R9-A12-2: η απάντηση «dbStatus» από τα σημάδια, με τιμές.

    @Test
    fun theStatusSaysTheCorruptionWhetherItsCardClosedAndWhetherAllWasRead() {
        val dir = tmp()
        val none = DbSalvage.status(dir)
        assertTrue(none.getBoolean("ok"))
        assertTrue(none.isNull("corrupt"))
        assertFalse(none.getBoolean("seen"))
        assertFalse(none.getBoolean("partial"))

        File(dir, DbSalvage.CORRUPT).writeText("5678")
        assertEquals(5678L, DbSalvage.status(dir).getLong("corrupt"))
        assertFalse(DbSalvage.status(dir).getBoolean("seen"))
        // «Εντάξει» στην κάρτα: η ίδια βλάβη → «seen»· το σημάδι της βλάβης μένει.
        DbSalvage.markSeen(dir, 5678)
        val seen = DbSalvage.status(dir)
        assertEquals(5678L, seen.getLong("corrupt"))
        assertTrue(seen.getBoolean("seen"))
        assertEquals(5678L, DbSalvage.corruptAt(dir))
        // Νέα βλάβη: η κάρτα ξαναβγαίνει.
        File(dir, DbSalvage.CORRUPT).writeText("5679")
        assertFalse(DbSalvage.status(dir).getBoolean("seen"))

        // Η επαναφορά δεν διάβασε όλα → «partial»· διάβασε όλα, ή σημάδι άλλης βλάβης → όχι.
        File(dir, DbSalvage.SALVAGED).writeText(DbSalvage.doneText(5679, 3, 1, complete = false))
        assertTrue(DbSalvage.status(dir).getBoolean("partial"))
        File(dir, DbSalvage.SALVAGED).writeText(DbSalvage.doneText(5679, 3, 1, complete = true))
        assertFalse(DbSalvage.status(dir).getBoolean("partial"))
        File(dir, DbSalvage.SALVAGED).writeText(DbSalvage.doneText(5678, 3, 1, complete = false))
        assertFalse(DbSalvage.status(dir).getBoolean("partial"))

        // Χαλασμένο σημάδι βλάβης: καμία βλάβη.
        File(dir, DbSalvage.CORRUPT).writeText("όχι αριθμός")
        assertTrue(DbSalvage.status(dir).isNull("corrupt"))
        assertNull(DbSalvage.corruptAt(dir))
    }

    @Test
    fun partialOnlyForThisCorruptionsDoneMarkerWithZero() {
        val at = 1_731_500_000_000L
        assertTrue(DbSalvage.partial("$at 120 3 3 0\n", at))
        assertTrue(DbSalvage.partial("$at 0 0 2 0", at))
        assertFalse(DbSalvage.partial("$at 120 3 3 1", at))
        assertFalse(DbSalvage.partial("$at 120 3", at))
        assertFalse(DbSalvage.partial("${at + 1} 120 3 3 0", at))
        assertFalse(DbSalvage.partial(null, at))
    }
}
