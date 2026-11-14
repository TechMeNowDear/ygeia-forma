package gr.ygeiaforma.ygeia_forma

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Round 8, f4: ανάγνωση του αρχείου της χαλασμένης βάσης σε κομμάτια (R8-A9-1 = R8-A12-1), σημάδια «έγινε» /
 * «η κάρτα έκλεισε» (R8-A9-2) και διαγραφές μετά από βλάβη (R8-A9-3). Απλό JVM· δεδομένα επινοημένα.
 */
class R8F4Test {
    /**
     * Ψεύτικος πίνακας με τη συμπεριφορά της SQLite στο Android: οι γραμμές είναι σε σελίδες (συνεχόμενα rowid ανά
     * σελίδα)· ένα ερώτημα «rowid ≥ from … LIMIT n» κατεβαίνει στη σελίδα του from (ή στην τελευταία, αν το from είναι
     * μετά από όλες) και διαβάζει γραμμή-γραμμή ως το LIMIT. Αν αγγίξει χαλασμένη σελίδα, ΟΛΟ το ερώτημα πετά (ο δρομέας
     * του Android μετρά όλες τις γραμμές του πριν δώσει την πρώτη).
     */
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

    private fun ids(a: JSONArray): List<String> = (0 until a.length()).map { a.getJSONObject(it).getString("id") }

    @Test
    fun aDamagedPageLosesOnlyItsOwnRows() {
        // 2.000 καταχωρίσεις, 5 ανά σελίδα· χαλασμένη η σελίδα 199 (rowid 996–1000).
        val t = FakeTable((1L..2000L).toList(), 5, setOf(199))
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out)
        val want = (1..2000).filter { it !in 996..1000 }.map { "E$it" }
        assertEquals(want, ids(out))
        assertEquals(1995, out.length())
        assertFalse("δεν διαβάστηκαν όλα", r.complete)
        assertTrue(r.lost > 0)
        assertEquals(0, r.skipped)
        assertTrue("λίγα ερωτήματα: ${t.queries}", t.queries < 200)
    }

    @Test
    fun aHealthyTableIsReadWholeAndComplete() {
        val t = FakeTable((1L..2000L).toList(), 5, emptySet())
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out)
        assertEquals(2000, out.length())
        assertEquals(DbSalvage.Read(skipped = 0, lost = 0, complete = true), r)
        // 2.000 / 64 = 31,25 → 32 ερωτήματα.
        assertEquals(32, t.queries)
    }

    @Test
    fun firstLastAndTwoNeighbouringPagesDamaged() {
        val t = FakeTable((1L..2000L).toList(), 5, setOf(0, 100, 101, 399))
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out)
        val gone = (1..5) + (501..510) + (1996..2000)
        assertEquals((1..2000).filter { it !in gone }.map { "E$it" }, ids(out))
        assertFalse(r.complete)
    }

    @Test
    fun sparseRowidsAfterEditsAndDeletes() {
        // «INSERT OR REPLACE» δίνει νέο rowid σε κάθε αλλαγή: κενά στη σειρά. rowid 3, 6, 9, … 6000.
        val rowids = (1L..2000L).map { it * 3 }
        val t = FakeTable(rowids, 5, setOf(50))
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out)
        // Σελίδα 50 = θέσεις 250–254 = rowid 753, 756, 759, 762, 765.
        val gone = setOf(753L, 756L, 759L, 762L, 765L)
        assertEquals(rowids.filter { it !in gone }.map { "E$it" }, ids(out))
        assertFalse(r.complete)
    }

    @Test
    fun chunkEndingExactlyAtADamagedPage() {
        // Σελίδες των 64 (όσο ένα κομμάτι): χαλασμένη η δεύτερη (rowid 65–128).
        val t = FakeTable((1L..640L).toList(), 64, setOf(1))
        val out = JSONArray()
        DbSalvage.read(t.source, emptySet(), out)
        assertEquals((1..640).filter { it !in 65..128 }.map { "E$it" }, ids(out))
    }

    @Test
    fun nothingReadableEndsQuicklyAndIncomplete() {
        val t = FakeTable((1L..2000L).toList(), 5, (0 until 400).toSet())
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out)
        assertEquals(0, out.length())
        assertFalse(r.complete)
        // Round 10 (R10-B6-1, g4): χαλασμένο ως το τέλος → και τα BACKFILL rowid ένα-ένα (μια καλή σελίδα ανάμεσα δεν
        // φαίνεται αλλιώς)· πριν < 200. Τελειώνει πάντα: 2 + GAP + 64 βήματα + BACKFILL = 8.322 το πολύ.
        assertTrue("ερωτήματα: ${t.queries}", t.queries <= 2 + DbSalvage.GAP + 64 + DbSalvage.BACKFILL)
    }

    @Test
    fun theQueryLimitStopsAndSaysIncomplete() {
        val t = FakeTable((1L..2000L).toList(), 5, emptySet())
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out, maxQueries = 5)
        assertEquals(5, t.queries)
        assertEquals(5 * 64, out.length())
        assertFalse(r.complete)
    }

    @Test
    fun removedDuplicateAndBrokenRows() {
        val rows = listOf(
            DbSalvage.Row(1, "E1", "{\"id\":\"E1\"}"),
            DbSalvage.Row(2, "E2", "{\"id\":\"E2\"}"), // σβήστηκε μετά από τη βλάβη
            DbSalvage.Row(3, "E1", "{\"id\":\"E1\",\"grams\":999}"), // ίδιο id: μετρά η νεότερη (R9-A9-2)
            DbSalvage.Row(4, null, "{\"id\":\"E4\"}"), // χωρίς id
            DbSalvage.Row(5, "E5", "όχι JSON"),
            DbSalvage.Row(6, "E6", "{\"id\":\"E6\"}"),
        )
        val source = DbSalvage.RowSource { from, limit -> rows.filter { it.rowid >= from }.take(limit) }
        val out = JSONArray()
        val r = DbSalvage.read(source, setOf("E2"), out)
        assertEquals(listOf("E1", "E6"), ids(out))
        // Round 9 (R9-A9-2): η γραμμή με το μεγαλύτερο rowid (η διόρθωση του χρήστη), όχι η πρώτη.
        assertEquals(999, out.getJSONObject(0).getInt("grams"))
        assertEquals(DbSalvage.Read(skipped = 2, lost = 0, complete = true), r)
    }

    @Test
    fun doneMarkerKeepsTheRulesAndWhetherAllWasRead() {
        val at = 1_731_500_000_000L
        // Round 9 (f4): κανόνας 3 (R9-A9-1/2/4). Round 10 (R10-B6-1, g4): κανόνας 4.
        assertEquals(4, DbSalvage.RULES)
        assertEquals("$at 120 3 4 1", DbSalvage.doneText(at, 120, 3, complete = true))
        assertEquals("$at 120 3 4 0", DbSalvage.doneText(at, 120, 3, complete = false))
        // Με τον τωρινό κανόνα: έγινε (και όταν δεν διαβάστηκαν όλα· δεν ξαναδιαβάζεται κάθε φορά).
        assertEquals(120 to 3, DbSalvage.parseDone("$at 120 3 4 1", at))
        assertEquals(120 to 3, DbSalvage.parseDone("$at 120 3 4 0", at))
        // Παλιότερος κανόνας: ξαναδιαβάζεται μόνο αν τότε δεν διαβάστηκαν όλα.
        assertNull(DbSalvage.parseDone("$at 120 3 1 0", at))
        assertNull(DbSalvage.parseDone("$at 120 3 2 0", at))
        assertEquals(120 to 3, DbSalvage.parseDone("$at 120 3 1 1", at))
        // Το σημάδι του #105 («ώρα καταχωρίσεις προϊόντα»): ξαναδιαβάζεται μία φορά.
        assertNull(DbSalvage.parseDone("$at 0 0", at))
        assertNull(DbSalvage.parseDone("$at 120 3 2 2", at))
        assertNull(DbSalvage.parseDone("$at 120 3 2 1", at + 1))
        // «Τελείωσε για πάντα» μόνο όταν διαβάστηκαν όλα.
        assertTrue(DbSalvage.finished("$at 120 3 2 1\n", at))
        assertFalse(DbSalvage.finished("$at 120 3 2 0", at))
        assertFalse(DbSalvage.finished("$at 0 0", at))
        assertFalse(DbSalvage.finished("$at 120 3 2 1", at + 1))
        assertFalse(DbSalvage.finished(null, at))
    }

    @Test
    fun theCardClosedMarkerIsPerCorruption() {
        val at = 1_731_500_000_000L
        assertTrue(DbSalvage.isSeen("$at\n", at))
        assertFalse(DbSalvage.isSeen("${at + 1}", at))
        assertFalse(DbSalvage.isSeen(null, at))
        assertFalse(DbSalvage.isSeen("χαλασμένο", at))
    }

    @Test
    fun removedAfterTheCorruptionAreKeptPerCorruptionAndOnlyWholeLines() {
        val at = 1_731_500_000_000L
        assertEquals("$at e E1\n", DbSalvage.removedLine(at, 'e', "E1"))
        assertNull(DbSalvage.removedLine(at, 'e', ""))
        assertNull(DbSalvage.removedLine(at, 'e', "E1\nE2"))
        assertNull(DbSalvage.removedLine(at, 'x', "E1"))
        val text = DbSalvage.removedLine(at, 'e', "E1")!! +
            DbSalvage.removedLine(at, 'f', "M πίτουρο 2")!! +
            DbSalvage.removedLine(at + 1, 'e', "E9")!! + // άλλη βλάβη
            "$at e E7" // μισή γραμμή (η εγγραφή κόπηκε): δεν μετρά
        val (entries, foods) = DbSalvage.parseRemoved(text, at)
        assertEquals(setOf("E1"), entries)
        assertEquals(setOf("M πίτουρο 2"), foods)
        assertEquals(emptySet<String>() to emptySet<String>(), DbSalvage.parseRemoved(null, at))
    }
}
