package gr.ygeiaforma.ygeia_forma

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Round 10, g4: ανάγνωση του αρχείου της χαλασμένης βάσης όταν η χαλασμένη περιοχή φτάνει ως το τέλος του πίνακα
 * (R10-B6-1: κομμένο αρχείο, όπου το δεξιότερο φύλλο δεν διαβάζεται) και ο κανόνας 4 στο σημάδι «έγινε». Απλό JVM·
 * δεδομένα επινοημένα. Αναμενόμενα: κάθε γραμμή σε σελίδα που δεν είναι χαλασμένη (ο ίδιος κανόνας ελέγχθηκε και σε
 * πραγματική SQLite 3.53 με κομμένα αρχεία).
 */
class R10G4Test {
    /**
     * Ψεύτικος πίνακας όπως στο R8F4Test/R9F4Test, με δικές του γραμμές: σελίδες των [perPage] με σειρά rowid· ένα ερώτημα
     * «rowid ≥ from … LIMIT n» κατεβαίνει στη σελίδα του from (ή στην ΤΕΛΕΥΤΑΙΑ, αν το from είναι μετά από όλες) και
     * πετά αν αγγίξει χαλασμένη σελίδα.
     */
    private class Paged(val rows: List<DbSalvage.Row>, perPage: Int, val bad: Set<Int>) {
        private val pages: List<List<DbSalvage.Row>> = rows.chunked(perPage)
        private val pageOf: Map<Long, Int> = HashMap<Long, Int>().also { m ->
            pages.forEachIndexed { i, p -> for (r in p) m[r.rowid] = i }
        }
        var queries = 0
        val source = DbSalvage.RowSource { from, limit ->
            queries++
            val seek = pages.indexOfFirst { it.last().rowid >= from }.let { if (it < 0) pages.size - 1 else it }
            if (seek in bad) throw IllegalStateException("database disk image is malformed")
            val out = ArrayList<DbSalvage.Row>()
            for (r in rows) {
                if (r.rowid < from) continue
                if (pageOf.getValue(r.rowid) in bad) throw IllegalStateException("database disk image is malformed")
                out.add(r)
                if (out.size == limit) break
            }
            out
        }
    }

    /** Καταχωρίσεις με rowid [range] και id «[prefix]rowid», 100 g η καθεμία. */
    private fun entries(range: LongRange, prefix: String = "E"): List<DbSalvage.Row> =
        range.map { DbSalvage.Row(it, "$prefix$it", "{\"id\":\"$prefix$it\",\"grams\":100}") }

    private fun ids(a: JSONArray): List<String> = (0 until a.length()).map { a.getJSONObject(it).getString("id") }

    private fun read(t: Paged, maxQueries: Int = DbSalvage.MAX_QUERIES): Pair<List<String>, DbSalvage.Read> {
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out, maxQueries = maxQueries)
        return ids(out) to r
    }

    @Test
    fun aGoodPageInsideADamagedAreaThatReachesTheEndIsRead() {
        // Το παράδειγμα της αναφοράς: 2.000 καταχωρίσεις, 5 ανά σελίδα· χαλασμένες οι σελίδες 100–399 (ως το τέλος του
        // πίνακα) εκτός από την 130 (E651–E655). Πριν (#108): μόνο E1–E500.
        val t = Paged(entries(1L..2000L), 5, (100..399).toSet() - 130)
        val (got, r) = read(t)
        assertEquals((1..500).map { "E$it" } + (651..655).map { "E$it" }, got)
        assertFalse(r.complete)
        assertTrue("ερωτήματα: ${t.queries}", t.queries < DbSalvage.MAX_QUERIES)
    }

    @Test
    fun aTruncatedTableKeepsEveryScatteredGoodPage() {
        // Κομμένο αρχείο: ό,τι μετά από τη σελίδα 99 χάθηκε, εκτός από τρεις σελίδες σε άλλα σημεία του αρχείου.
        val t = Paged(entries(1L..2000L), 5, (100..399).toSet() - setOf(130, 250, 390))
        val (got, r) = read(t)
        val want = (1..500) + (651..655) + (1251..1255) + (1951..1955)
        assertEquals(want.map { "E$it" }, got)
        assertFalse(r.complete)
        assertTrue("ερωτήματα: ${t.queries}", t.queries < DbSalvage.MAX_QUERIES)
    }

    @Test
    fun theUsersCorrectionInTheDamagedTailWinsOverTheOldVersion() {
        // 400 καταχωρίσεις των 100 g· μετά ο χρήστης διόρθωσε την E50 σε 150 g και την E7 σε 60 g («INSERT OR REPLACE»:
        // νέα rowid 401, 402) και έγραψε 48 νέες (N403–N450). Το αρχείο κόπηκε: χαλασμένες οι σελίδες 60–89 (ως το τέλος)
        // εκτός από την 80 (rowid 401–405, σε σελίδα που ελευθερώθηκε νωρίτερα στο αρχείο). Πριν (#108): E50 με 100 g.
        val rows = entries(1L..400L) +
            DbSalvage.Row(401, "E50", "{\"id\":\"E50\",\"grams\":150}") +
            DbSalvage.Row(402, "E7", "{\"id\":\"E7\",\"grams\":60}") +
            entries(403L..450L, "N")
        val t = Paged(rows, 5, (60..89).toSet() - 80)
        val out = JSONArray()
        val r = DbSalvage.read(t.source, emptySet(), out)
        assertEquals((1..300).map { "E$it" } + listOf("N403", "N404", "N405"), ids(out))
        val grams = HashMap<String, Int>()
        for (i in 0 until out.length()) grams[out.getJSONObject(i).getString("id")] = out.getJSONObject(i).getInt("grams")
        assertEquals(150, grams["E50"])
        assertEquals(60, grams["E7"])
        assertEquals(100, grams["E8"])
        assertFalse(r.complete)
    }

    @Test
    fun aTableDamagedOnlyAtItsEndIsReadUpToTheDamageAndTheReadEnds() {
        val t = Paged(entries(1L..2000L), 5, (390..399).toSet())
        val (got, r) = read(t)
        assertEquals((1..1950).map { "E$it" }, got)
        assertFalse(r.complete)
        assertEquals(1, r.lost)
        // 62 ερωτήματα ως τη βλάβη· μετά GAP ένα-ένα, ≤ 64 διπλάσια βήματα ως το Long.MAX_VALUE, BACKFILL ένα-ένα· τέλος.
        assertTrue("ερωτήματα: ${t.queries}", t.queries <= 62 + DbSalvage.GAP + 64 + DbSalvage.BACKFILL)
    }

    @Test
    fun theQueryLimitAlsoStopsTheSearchAfterADamagedEnd() {
        // 200 ερωτήματα: τελειώνει μέσα στην αναζήτηση ένα-ένα, πριν από την καλή σελίδα 130.
        val a = Paged(entries(1L..2000L), 5, (100..399).toSet() - 130)
        val (gotA, rA) = read(a, maxQueries = 200)
        assertEquals(200, a.queries)
        assertEquals((1..500).map { "E$it" }, gotA)
        assertFalse(rA.complete)
        // 300 ερωτήματα: προλαβαίνει τη σελίδα 130 και σταματά στο όριο.
        val b = Paged(entries(1L..2000L), 5, (100..399).toSet() - 130)
        val (gotB, rB) = read(b, maxQueries = 300)
        assertEquals(300, b.queries)
        assertEquals((1..500).map { "E$it" } + (651..655).map { "E$it" }, gotB)
        assertFalse(rB.complete)
    }

    @Test
    fun rowidsUpToLongMaxValueDoNotOverflowTheSearch() {
        // Οι πίνακες της εφαρμογής δεν φτάνουν ποτέ εκεί· ελέγχεται ότι η αναζήτηση ένα-ένα σταματά στο Long.MAX_VALUE.
        val rows = entries((Long.MAX_VALUE - 1999)..Long.MAX_VALUE)
        val bad = (100..399).toSet() - 130
        val t = Paged(rows, 5, bad)
        val (got, r) = read(t)
        val want = rows.filterIndexed { i, _ -> i / 5 !in bad }.map { it.id }
        assertEquals(505, want.size)
        assertEquals(want, got)
        assertFalse(r.complete)
    }

    @Test
    fun aReadWithRule3ThatDidNotReadEverythingIsDoneOnceMore() {
        val at = 1_731_500_000_000L
        assertEquals(4, DbSalvage.RULES)
        assertEquals("$at 120 3 4 0", DbSalvage.doneText(at, 120, 3, complete = false))
        // Κανόνας 3 χωρίς όλα (π.χ. ένα κομμένο αρχείο που διάβασε το #108): ξαναδιαβάζεται μία φορά με τον κανόνα 4, και
        // ως τότε κρατιούνται οι διαγραφές (δεν «τελείωσε») και η κάρτα «δεν διαβάστηκαν όλα».
        assertNull(DbSalvage.parseDone("$at 120 3 3 0", at))
        assertFalse(DbSalvage.finished("$at 120 3 3 0", at))
        assertTrue(DbSalvage.partial("$at 120 3 3 0", at))
        // Κανόνας 3 με όλα, ή κανόνας 4: έγινε.
        assertEquals(120 to 3, DbSalvage.parseDone("$at 120 3 3 1", at))
        assertEquals(120 to 3, DbSalvage.parseDone(DbSalvage.doneText(at, 120, 3, complete = false), at))
        assertTrue(DbSalvage.finished(DbSalvage.doneText(at, 120, 3, complete = true), at))
    }
}
