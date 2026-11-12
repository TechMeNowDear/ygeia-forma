package gr.ygeiaforma.wear

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.Locale

/**
 * Τελικός έλεγχος, Συμβούλιο 4 (αρχιτεκτονική Android 17 / Wear OS), η πλευρά του ρολογιού. Καθαρός Kotlin, χωρίς
 * συσκευή. Όλα τα νούμερα είναι δοκιμαστικά.
 * - W-4: επαναλήψεις που αλλάζεις στο ρολόι δεν χάνονται όταν χαθεί ένα μήνυμα προς το κινητό.
 * - W-1/W-2: τα όρια χρόνου του «Τέλος». W-5: ώρες με ψηφία 0–9 σε κάθε γλώσσα. W-7: ορφανή άσκηση.
 */
class AuditFinalS4Test {
    private fun item(ex: String, vararg sets: JSONObject) = JSONObject()
        .put("ex", ex).put("name", ex).put("rest", 90).put("lo", 8).put("hi", 12).put("rir", 2).put("sets", JSONArray(sets.toList()))

    private fun set(reps: Int, done: Boolean = false, at: Long = 0) =
        JSONObject().put("label", "20 kg").put("load", 20.0).put("reps", reps).also { if (done) it.put("done", true).put("at", at) }

    /** Η προπόνηση όπως τη στέλνει το κινητό ([Paths.SESSION]). */
    private fun phone(vararg items: JSONObject, id: String = "s1"): LiveSession = LiveSession.parsePhone(
        JSONObject().put("v", 1).put("active", true).put("id", id).put("w", "A").put("name", "Α").put("start", 1_000L)
            .put("idx", 0).put("restEnd", 0).put("items", JSONArray(items.toList())).toString(),
    )!!

    private fun fresh() {
        Repo.phone = null
        Repo.lastPhone = null
        Repo.local = null
        Repo.resetExercise()
    }

    // ------------------------------------------------------------------ W-4: το ίδιο το σετ
    @Test
    fun editRemembersWhatThePhoneHad() {
        val s = SetT(20.0, "20 kg", 10)
        assertNull(s.trail)
        s.edit(9)
        assertEquals(9, s.reps)
        assertEquals(setOf(10), s.trail)
        // δεύτερη αλλαγή: και η τιμή που στάλθηκε πριν μπορεί να είναι ακόμα στο κινητό
        s.edit(8)
        assertEquals(8, s.reps)
        assertEquals(setOf(10, 9), s.trail)
        // ίδια τιμή: τίποτα
        s.edit(8)
        assertEquals(setOf(10, 9), s.trail)
        // όρια 0–99, όπως πριν
        s.edit(150)
        assertEquals(99, s.reps)
        s.edit(-3)
        assertEquals(0, s.reps)
    }

    @Test
    fun phoneStateDoesNotEraseAnEditItHasNotSeen() {
        // το κινητό δείχνει ακόμα την παλιά τιμή: η δική σου μένει και περιμένει
        val old = SetT(20.0, "", 10).also { it.edit(8) }
        val still = SetT(20.0, "", 10)
        keepWatchEdits(old, still)
        assertEquals(8, still.reps)
        assertEquals(setOf(10), still.trail)

        // το κινητό δείχνει ενδιάμεση τιμή που του είχες στείλει πριν (10 → 9 → 8, έφτασε μόνο το 9): πάλι περιμένει το 8
        val twice = SetT(20.0, "", 10).also { it.edit(9); it.edit(8) }
        val mid = SetT(20.0, "", 9)
        keepWatchEdits(twice, mid)
        assertEquals(8, mid.reps)
        assertEquals(setOf(10, 9), mid.trail)
    }

    @Test
    fun editIsSettledWhenThePhoneShowsIt() {
        val old = SetT(20.0, "", 10).also { it.edit(8) }
        val got = SetT(20.0, "", 8)
        keepWatchEdits(old, got)
        assertEquals(8, got.reps)
        assertNull(got.trail)
    }

    @Test
    fun phoneWinsWhenItChangedTheSetItself() {
        // στο ρολόι 10 → 8, στο κινητό το έκανες 12 στο μεταξύ: ισχύει του κινητού, τίποτα δεν εκκρεμεί
        val old = SetT(20.0, "", 10).also { it.edit(8) }
        val other = SetT(20.0, "", 12)
        keepWatchEdits(old, other)
        assertEquals(12, other.reps)
        assertNull(other.trail)
    }

    @Test
    fun withoutAnEditThePhoneStateIsTakenAsIs() {
        val old = SetT(20.0, "", 10)
        val now = SetT(20.0, "", 11)
        keepWatchEdits(old, now)
        assertEquals(11, now.reps)
        assertNull(now.trail)
    }

    @Test
    fun unseenTickIsKeptWithItsTimeAndReps() {
        // ✓ στο ρολόι με 8 (αντί για 10) που το κινητό δεν έχει δει: μένουν ✓, ώρα ΚΑΙ επαναλήψεις
        val old = SetT(20.0, "", 10).also { it.edit(8); it.done = true; it.at = 5_000 }
        val phoneSays = SetT(20.0, "", 10)
        keepWatchEdits(old, phoneSays)
        assertTrue(phoneSays.done)
        assertEquals(5_000L, phoneSays.at)
        assertEquals(8, phoneSays.reps)
        assertEquals(setOf(10), phoneSays.trail)
        // ✓ που το κινητό είχε δει και μετά το έβγαλε: βγαίνει κι εδώ (όπως πριν)
        val seen = SetT(20.0, "", 10, done = true, at = 5_000, confirmed = true)
        val unticked = SetT(20.0, "", 10)
        keepWatchEdits(seen, unticked)
        assertFalse(unticked.done)
    }

    // ------------------------------------------------------------------ W-4: οι εντολές
    @Test
    fun tickCarriesRepsOnlyWhenEditedOnTheWatch() {
        // χωρίς αλλαγή στο ρολόι: ακριβώς τα πεδία που έστελνε πριν (το παλιό κινητό δεν βλέπει καμία διαφορά)
        val plain = tickCmd(2, 1, 7_000, "bench", null)
        assertEquals(setOf("op", "i", "s", "at"), plain.keySet())
        assertEquals("tick", plain.getString("op"))
        assertEquals(2, plain.getInt("i"))
        assertEquals(1, plain.getInt("s"))
        assertEquals(7_000L, plain.getLong("at"))
        // με αλλαγή: και οι επαναλήψεις, με την άσκηση που αφορούν
        val edited = tickCmd(2, 1, 7_000, "bench", 8)
        assertEquals(8, edited.getInt("r"))
        assertEquals("bench", edited.getString("ex"))
        assertFalse(edited.has("late"))
        // ξανασταλμένο ✓: «late», και χωρίς ώρα αν δεν υπάρχει
        val late = tickCmd(0, 0, 0, "row", 6, late = true)
        assertTrue(late.getBoolean("late"))
        assertFalse(late.has("at"))
        // η εντολή «reps» δεν άλλαξε μορφή (μεταφέρθηκε μόνο αρχείο)
        val reps = repsCmd(0, 1, "row", 9, 3_000)
        assertEquals(setOf("op", "i", "s", "v", "ex", "at"), reps.keySet())
    }

    @Test
    fun commandNumbersOnlyGoUp() {
        val a = Repo.nextCmdSeq(1_000_000)
        val b = Repo.nextCmdSeq(1_000_000)
        // η ώρα του ρολογιού πήγε πίσω: ο αριθμός συνεχίζει να ανεβαίνει
        val c = Repo.nextCmdSeq(500)
        // η ώρα πήγε μπροστά: τουλάχιστον η ώρα
        val d = Repo.nextCmdSeq(9_000_000_000_000)
        assertTrue(b > a)
        assertTrue(c > b)
        assertEquals(9_000_000_000_000, d)
    }

    // ------------------------------------------------------------------ W-4: όλη η διαδρομή μέσα από το Repo
    @Test
    fun repsEditedBeforeTickSurviveALostMessage() {
        fresh()
        Repo.applyPhone(phone(item("bench", set(10), set(10))))
        val s = Repo.phone!!
        // στο ρολόι: 10 → 8 και ✓ (όπως το WatchActivity.reps / tick)· κανένα μήνυμα δεν φτάνει στο κινητό
        s.items[0].sets[0].edit(8)
        s.tick(6_000)
        // το κινητό στέλνει ξανά την κατάστασή του για άλλο λόγο (χωρίς το ✓, με 10 επαναλήψεις)
        Repo.applyPhone(phone(item("bench", set(10), set(10))))
        val kept = Repo.phone!!.items[0].sets[0]
        assertTrue(kept.done)
        assertEquals(8, kept.reps)
        assertEquals(listOf(0 to 0), Repo.pendingTicks)
        assertTrue(Repo.pendingReps.isEmpty())
        // το ✓ που ξαναστέλνεται κουβαλά τις 8 επαναλήψεις
        val again = tickCmd(0, 0, kept.at, Repo.phone!!.items[0].ex, kept.reps.takeIf { kept.trail != null }, late = true)
        assertEquals(8, again.getInt("r"))
        // το κινητό το πήρε (✓ με 8): τίποτα δεν εκκρεμεί πια
        Repo.applyPhone(phone(item("bench", set(8, done = true, at = 6_000), set(10))))
        val done = Repo.phone!!.items[0].sets[0]
        assertEquals(8, done.reps)
        assertNull(done.trail)
        assertTrue(Repo.pendingTicks.isEmpty())
        assertTrue(Repo.pendingReps.isEmpty())
    }

    @Test
    fun oldPhoneThatIgnoresRepsInTickGetsThemAsRepsCommand() {
        fresh()
        Repo.applyPhone(phone(item("bench", set(10), set(10))))
        val s = Repo.phone!!
        s.items[0].sets[0].edit(8)
        s.tick(6_000)
        // κινητό παλιότερης έκδοσης: γράφει το ✓ αλλά αγνοεί το «r» → δείχνει ✓ με 10
        Repo.applyPhone(phone(item("bench", set(10, done = true, at = 6_000), set(10))))
        val set = Repo.phone!!.items[0].sets[0]
        assertEquals(8, set.reps)
        assertTrue(Repo.pendingTicks.isEmpty())
        assertEquals(listOf(0 to 0), Repo.pendingReps)
        // η «reps» που ξαναστέλνεται έχει την άσκηση και την ώρα του σετ όπως τις ξέρει το κινητό (τα ελέγχει πριν γράψει)
        val cmd = repsCmd(0, 0, Repo.phone!!.items[0].ex, set.reps, set.at)
        assertEquals(8, cmd.getInt("v"))
        assertEquals(6_000L, cmd.getLong("at"))
        Repo.applyPhone(phone(item("bench", set(8, done = true, at = 6_000), set(10))))
        assertTrue(Repo.pendingReps.isEmpty())
    }

    @Test
    fun correctionAfterTickIsResentUntilThePhoneShowsIt() {
        fresh()
        // το σετ είναι ήδη ✓ και στο κινητό· στο διάλειμμα το διορθώνεις στο ρολόι 10 → 9 (WatchActivity.lastReps)
        Repo.applyPhone(phone(item("bench", set(10, done = true, at = 6_000), set(10))))
        Repo.phone!!.items[0].sets[0].edit(9)
        assertEquals(listOf(0 to 0), Repo.pendingReps)
        // το κινητό ξαναστέλνει την παλιά τιμή (η εντολή χάθηκε): η διόρθωση μένει στο ρολόι και εκκρεμεί
        Repo.applyPhone(phone(item("bench", set(10, done = true, at = 6_000), set(10))))
        assertEquals(9, Repo.phone!!.items[0].sets[0].reps)
        assertEquals(listOf(0 to 0), Repo.pendingReps)
        // έφτασε
        Repo.applyPhone(phone(item("bench", set(9, done = true, at = 6_000), set(10))))
        assertTrue(Repo.pendingReps.isEmpty())
    }

    @Test
    fun editBeforeTickIsResentWhileThePhoneShowsTheOldValue() {
        fresh()
        Repo.applyPhone(phone(item("bench", set(10), set(10))))
        // αλλαγή σε σετ που δεν έχει γίνει ακόμα· η εντολή χάθηκε
        Repo.phone!!.items[0].sets[1].edit(12)
        assertEquals(listOf(0 to 1), Repo.pendingReps)
        // η «reps» που ξαναστέλνεται δεν έχει ώρα σετ (το σετ δεν έγινε): το κινητό τη γράφει με μόνο έλεγχο την άσκηση
        assertFalse(repsCmd(0, 1, "bench", 12, Repo.phone!!.items[0].sets[1].at).has("at"))
        Repo.applyPhone(phone(item("bench", set(10), set(10))))
        assertEquals(12, Repo.phone!!.items[0].sets[1].reps)
        assertEquals(listOf(0 to 1), Repo.pendingReps)
        Repo.applyPhone(phone(item("bench", set(10), set(12))))
        assertTrue(Repo.pendingReps.isEmpty())
    }

    @Test
    fun editIsDroppedWhenTheExerciseChangedOnThePhone() {
        fresh()
        Repo.applyPhone(phone(item("bench", set(10), set(10))))
        Repo.phone!!.items[0].sets[0].edit(8)
        // στο κινητό η άσκηση άλλαξε σε εναλλακτική: η διόρθωση δεν πάει σε άλλη άσκηση
        Repo.applyPhone(phone(item("db_press", set(10), set(10))))
        val set = Repo.phone!!.items[0].sets[0]
        assertEquals(10, set.reps)
        assertNull(set.trail)
    }

    @Test
    fun resultCarriesWhatThePhoneHadOnlyForUnsettledEdits() {
        fresh()
        Repo.applyPhone(phone(item("bench", set(10, done = true, at = 6_000), set(10, done = true, at = 7_000))))
        val s = Repo.phone!!
        s.items[0].sets[0].edit(9)
        s.items[0].sets[0].edit(8)
        val log = s.resultJson(9_000, HrStats(1_000)).getJSONArray("items").getJSONObject(0).getJSONArray("log")
        assertEquals(8, log.getJSONObject(0).getInt("r"))
        assertEquals("[9,10]", log.getJSONObject(0).getJSONArray("rb").toString())
        // σετ χωρίς διόρθωση: ακριβώς όπως πριν (κανένα νέο πεδίο)
        assertFalse(log.getJSONObject(1).has("rb"))
        assertEquals(setOf("r", "l", "d", "t"), log.getJSONObject(1).keySet())
    }

    // ------------------------------------------------------------------ W-1/W-2: «Τέλος»
    @Test
    fun finishWakeLockCoversTheWorstCase() {
        // Κάθε βήμα έχει όριο, και ο επεξεργαστής μένει ξύπνιος για όλα μαζί, ακόμα κι αν τίποτα δεν απαντήσει.
        val steps = listOf(FinishTimes.HS_CALL_MS, FinishTimes.FLUSH_SETTLE_MS, FinishTimes.ENDED_WAIT_MS, FinishTimes.SEND_MS, FinishTimes.PUT_MS)
        assertTrue(steps.all { it > 0 })
        assertEquals(29_400L, FinishTimes.WORST_MS)
        assertTrue(FinishTimes.LOCK_MS >= FinishTimes.WORST_MS)
        // και δεν κρατά τον επεξεργαστή ξύπνιο αδικαιολόγητα πολύ
        assertTrue(FinishTimes.LOCK_MS <= 60_000)
    }

    // ------------------------------------------------------------------ W-7: ορφανή άσκηση
    @Test
    fun orphanExerciseIsEndedOnlyWhenNothingElseCouldOwnIt() {
        assertTrue(shouldEndOrphan(owned = true, hasSnapshot = false, running = false, local = false, idle = true))
        // δεν είναι δική μας, ή δεν τρέχει τίποτα στο Health Services
        assertFalse(shouldEndOrphan(owned = false, hasSnapshot = false, running = false, local = false, idle = true))
        // υπάρχει στιγμιότυπο: τη συνεχίζει η ανάκτηση, δεν τελειώνει εδώ
        assertFalse(shouldEndOrphan(owned = true, hasSnapshot = true, running = false, local = false, idle = true))
        // τρέχει άσκηση ή προπόνηση εδώ: είναι αυτή
        assertFalse(shouldEndOrphan(owned = true, hasSnapshot = false, running = true, local = false, idle = true))
        assertFalse(shouldEndOrphan(owned = true, hasSnapshot = false, running = false, local = true, idle = true))
        // ο χρήστης πάτησε ήδη έναρξη σε αυτό το άνοιγμα: όχι
        assertFalse(shouldEndOrphan(owned = true, hasSnapshot = false, running = false, local = false, idle = false))
    }

    // ------------------------------------------------------------------ W-5: ψηφία 0–9 σε κάθε γλώσσα
    @Test
    fun clockUsesPlainDigitsInEveryLanguage() {
        val before = Locale.getDefault()
        try {
            for (tag in listOf("el-GR", "ar-EG", "fa-IR", "hi-IN-u-nu-deva")) {
                Locale.setDefault(Locale.forLanguageTag(tag))
                assertEquals(tag, "1:04", clock(64))
                assertEquals(tag, "1:02:05", clock(3725))
                assertEquals(tag, "0:00", clock(-5))
            }
        } finally {
            Locale.setDefault(before)
        }
    }

    @Test
    fun withoutLocaleRootTheDigitsFollowTheLanguage() {
        // Το πρόβλημα που διορθώθηκε, όπου το JVM της δοκιμής έχει τα δεδομένα της γλώσσας (αλλιώς η δοκιμή παραλείπεται).
        val before = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("ar-EG"))
            val old = "%d:%02d".format(1, 4)
            assumeTrue("το JVM δεν έχει αραβικά ψηφία για ar-EG", old != "1:04")
            assertFalse(old.any { it in '0'..'9' })
            assertEquals("1:04", "%d:%02d".format(Locale.ROOT, 1, 4))
        } finally {
            Locale.setDefault(before)
        }
    }
}
