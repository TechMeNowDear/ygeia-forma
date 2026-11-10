package gr.ygeiaforma.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** «Διαγραφή όλων» από το κινητό (έλεγχος 9/11, E3-05): πότε σβήνει το ρολόι. */
class WipeRuleTest {
    @Test
    fun wipesOnceNeverDuringExercise() {
        assertTrue(WipeRule.shouldWipe(at = 2000, done = 0, running = false))
        // Η ίδια διαγραφή δεύτερη φορά (το DataItem μένει): όχι ξανά.
        assertFalse(WipeRule.shouldWipe(at = 2000, done = 2000, running = false))
        // Νέα διαγραφή αργότερα: ναι.
        assertTrue(WipeRule.shouldWipe(at = 3000, done = 2000, running = false))
        // Στη μέση άσκησης: περιμένει (γίνεται στο επόμενο άνοιγμα).
        assertFalse(WipeRule.shouldWipe(at = 3000, done = 2000, running = true))
        // Χαλασμένο/κενό μήνυμα: ποτέ.
        assertFalse(WipeRule.shouldWipe(at = 0, done = 0, running = false))
        assertEquals(0L, WipeRule.parseAt("όχι json"))
        assertEquals(0L, WipeRule.parseAt(null))
        assertEquals(1234L, WipeRule.parseAt("""{"v":1,"at":1234}"""))
        assertEquals("/ygeia/wipe", Paths.WIPE)
    }

    @Test
    fun acksOnceAfterWipeAndDefersWhileRecoverable() {
        // Η διαγραφή έγινε, η απάντηση δεν έφτασε (acked < at): ξανά μόνο η απάντηση, όχι νέα διαγραφή.
        assertTrue(WipeRule.shouldAck(at = 2000, done = 2000, acked = 0))
        assertFalse(WipeRule.shouldWipe(at = 2000, done = 2000, running = false))
        // Απαντήθηκε: τίποτα.
        assertFalse(WipeRule.shouldAck(at = 2000, done = 2000, acked = 2000))
        // Δεν έγινε ακόμα (π.χ. άσκηση): ούτε απάντηση.
        assertFalse(WipeRule.shouldAck(at = 3000, done = 2000, acked = 2000))
        assertEquals(3000L, org.json.JSONObject(WipeRule.ackJson(3000)).getLong("at"))
        assertEquals("/ygeia/wiped", Paths.WIPED)
        // S1: άσκηση που έμεινε μισή (στιγμιότυπο) μετρά ως «τρέχει»: το Link.tryWipe το ελέγχει.
        val link = java.io.File("src/main/kotlin/gr/ygeiaforma/wear/Link.kt").readText()
        assertTrue(link.contains("Repo.readRun(ctx) != null"))
        // M1: σβήνονται και τα DataItems που έγραψε το ρολόι (του τοπικού κόμβου).
        assertTrue(link.contains("u.host != me.id"))
    }

    @Test
    fun wipeKeepsWhatHappenedAfterIt() {
        // N1: «Διαγραφή όλων» στο κινητό στις `at`· περπάτημα στο ρολόι 1 ώρα μετά, πριν φτάσει το «σβήσε».
        val at = 1_762_800_000_000L
        val after = at + 3_600_000L
        val before = at - 3_600_000L
        val newWalk = Results0.walk(after)
        val oldWalk = Results0.walk(before)
        assertTrue(WipeRule.keepAfterWipe(newWalk, 0L, at))
        assertFalse(WipeRule.keepAfterWipe(oldWalk, 0L, at))
        // Παλμοί προπόνησης του κινητού: η αρχή από το id «hr<sid>-<ms>».
        assertTrue(WipeRule.keepAfterWipe("""{"v":1,"kind":"hr","sid":"s1","id":"hrs1-$after"}""", 0L, at))
        assertFalse(WipeRule.keepAfterWipe("""{"v":1,"kind":"hr","sid":"s1","id":"hrs1-$before"}""", 0L, at))
        // Χωρίς χρόνο μέσα: η ώρα του DataItem.
        assertTrue(WipeRule.keepAfterWipe("{}", after, at))
        assertFalse(WipeRule.keepAfterWipe("{}", before, at))
        // Καμία διαγραφή: όλα μένουν.
        assertTrue(WipeRule.keepAfterWipe(oldWalk, 0L, 0L))
        // Το ρολόι κρατά τα νέα στη διαγραφή και τα στέλνει όσο περιμένει το «σβήσε».
        val link = java.io.File("src/main/kotlin/gr/ygeiaforma/wear/Link.kt").readText()
        assertTrue(link.contains("Repo.pendingAll(ctx).filter { (_, o) -> WipeRule.keepAfterWipe(o.toString(), 0L, at) }"))
        assertTrue(link.contains("for ((id, o) in keep) Repo.savePending(ctx, id, o)"))
        val act = java.io.File("src/main/kotlin/gr/ygeiaforma/wear/WatchActivity.kt").readText()
        assertFalse(act.contains("wipeWanted"))
        assertTrue(act.contains("if (!Link.sendable(this, o)) continue"))
    }

    @Test
    fun oldPhonePlanIsIgnoredAfterWipe() {
        // N3: το παλιό πρόγραμμα/όριο του κινητού (γραμμένο πριν από τη διαγραφή που έγινε εδώ) δεν ξαναμπαίνει.
        assertTrue(WipeRule.staleFromPhone(t = 1000, done = 2000))
        assertFalse(WipeRule.staleFromPhone(t = 3000, done = 2000))
        assertFalse(WipeRule.staleFromPhone(t = 1000, done = 0))
        val link = java.io.File("src/main/kotlin/gr/ygeiaforma/wear/Link.kt").readText()
        assertTrue(link.contains("WipeRule.staleFromPhone(t,"))
    }

    /** Ένα αποτέλεσμα περπατήματος όπως το γράφει το [Results] (id «walk<αρχή>», «start»). */
    private object Results0 {
        fun walk(start: Long): String = org.json.JSONObject()
            .put("v", 1).put("id", "walk$start").put("kind", "cardio").put("start", start).put("end", start + 1_800_000L)
            .toString()
    }

    @Test
    fun recoveryWindowsAreHalfOpen() {
        // 03-Χ4: «10″ ως το Τέλος» = 10 τιμές [τέλος−10, τέλος). Η τιμή ακριβώς στο «Τέλος» δεν μπαίνει.
        val samples = ArrayList<IntArray>()
        for (t in 50..59) samples.add(intArrayOf(t, 120))
        samples.add(intArrayOf(60, 60)) // η στιγμή του «Τέλος»
        for (t in 115..124) samples.add(intArrayOf(t, 100))
        samples.add(intArrayOf(125, 40)) // ακριβώς στο 65″: εκτός
        val r = HrStats.recovery(samples, 60)!!
        assertEquals(120, r.first)
        assertEquals(100, r.second)
    }
}
