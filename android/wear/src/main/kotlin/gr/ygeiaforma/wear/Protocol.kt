package gr.ygeiaforma.wear

import org.json.JSONArray
import org.json.JSONObject

/**
 * Τι ανταλλάσσουν κινητό και ρολόι (Wear Data Layer). Καθαρός Kotlin, χωρίς Android, για να ελέγχεται σε JVM.
 *
 * Κινητό → ρολόι (DataItem, μένει και όταν το ρολόι δεν είναι κοντά):
 *  - [PLAN]: η σημερινή προπόνηση και οι άλλες του προγράμματος, με έτοιμους στόχους ανά σετ (τους υπολογίζει το κινητό),
 *    το όριο παλμών του γιατρού και αν δόθηκε έγκριση.
 *  - [SESSION]: η προπόνηση που τρέχει στο κινητό (τρέχουσα άσκηση, σετ, διάλειμμα).
 * Ρολόι → κινητό:
 *  - [HR] (μήνυμα): παλμοί ανά λίγα δευτερόλεπτα, μόνο όσο τρέχει άσκηση.
 *  - [CMD] (μήνυμα): ✓ σετ, ρεζέρβα, διάλειμμα, όταν η προπόνηση τρέχει στο κινητό.
 *  - [LIVE] (μήνυμα): περπάτημα σε εξέλιξη (χρόνος, απόσταση, παλμοί), για την κάρτα στο κινητό.
 *  - [RESULT]+id (DataItem): προπόνηση ή περπάτημα που έγινε μόνο στο ρολόι· το κινητό το παίρνει και το σβήνει.
 */
object Paths {
    const val PLAN = "/ygeia/plan"
    const val SESSION = "/ygeia/session"
    const val RESULT = "/ygeia/result/"
    const val HR = "/ygeia/hr"
    const val CMD = "/ygeia/cmd"
    const val LIVE = "/ygeia/live"
    /**
     * Ρολόι → κινητό (DataItem, έλεγχος 9/11, V-A-06): τι έχει το ρολόι (το όριο παλμών που ισχύει εκεί, η έκδοση της
     * μορφής). Το κινητό γράφει «Στο ρολόι ✓ όριο 140» μόνο όταν το δει. Νέο path: το παλιό κινητό το αγνοεί.
     */
    const val STATE = "/ygeia/wstate"
    /**
     * Κινητό → ρολόι (DataItem, έλεγχος 9/11, E3-05): «Διαγραφή όλων των δεδομένων» στο κινητό. `{"at": ms}`. Το ρολόι
     * σβήνει τα δικά του αρχεία και ρυθμίσεις όταν το δει (όχι στη μέση άσκησης). Νέο path: το παλιό ρολόι το αγνοεί.
     */
    const val WIPE = "/ygeia/wipe"
    /**
     * Ρολόι → κινητό (DataItem, έλεγχος του fix-accuracy, M1/M4): «σβήστηκε» `{"v":1,"at": ms}` (το «at» του «σβήσε»).
     * Μόλις το δει, το κινητό σβήνει και τα δύο. Νέο path: το παλιό κινητό το αγνοεί.
     */
    const val WIPED = "/ygeia/wiped"
    /**
     * Κινητό → ρολόι (μήνυμα, έλεγχος γ2, W3-15): «κοιτάζω» `{"v":1,"ttl": ms}`: όσο είναι ανοιχτή η εφαρμογή στο κινητό
     * (ξανά ανά ~45″), το ρολόι στέλνει «ζωντανά» το περπάτημα· `ttl` 0 = έκλεισε. Νέο path: το παλιό ρολόι το αγνοεί.
     */
    const val WATCHING = "/ygeia/watching"
    const val KEY = "json"

    /** Δυνατότητα που δηλώνει η εφαρμογή του ρολογιού (res/values/wear.xml), για να τη βρίσκει το κινητό. */
    const val CAPABILITY = "ygeia_watch"
}

/**
 * Έκδοση της μορφής (πεδίο «v» σε πρόγραμμα, προπόνηση, αποτέλεσμα, εντολή). Αλλάζει ΜΟΝΟ όταν η μορφή αλλάζει με τρόπο
 * που η παλιά έκδοση δεν μπορεί να διαβάσει σωστά (νέα πεδία δεν την αλλάζουν). Ό,τι έρχεται με μεγαλύτερο «v» δεν
 * διαβάζεται: το ρολόι λέει «Ενημέρωσε την εφαρμογή στο ρολόι» (έλεγχος 9/11, V-A-08).
 */
object Proto {
    const val MAJOR = 1

    /**
     * Στις εντολές ([Paths.CMD]) η έκδοση πάει στο «pv»: το «v» εκεί είναι ήδη η τιμή (ρεζέρβα, επαναλήψεις, διάλειμμα)
     * από την πρώτη έκδοση και δεν αλλάζει.
     */
    const val CMD_VERSION = "pv"

    /** Κείμενο από νεότερη έκδοση της εφαρμογής (με «v» μεγαλύτερο από όσο ξέρουμε). Χωρίς «v» = 1. */
    fun tooNew(text: String): Boolean = try {
        JSONObject(text).optInt("v", 1) > MAJOR
    } catch (_: Exception) {
        false
    }
}

/**
 * [confirmed]: το κινητό έχει δει το ✓ (στην κατάσταση που στέλνει). Ως τότε το ✓ του ρολογιού κρατιέται (έλεγχος #2).
 *
 * [trail]: όταν αλλάζεις τις επαναλήψεις σε ΑΥΤΟ το ρολόι σε προπόνηση του κινητού (τελικός έλεγχος, Συμβούλιο 4, W-4), οι
 * τιμές που μπορεί να δείχνει ακόμα το κινητό επειδή δεν πρόλαβε τη δική σου: αυτή που είχε πριν, και όσες του έστειλες
 * πριν από την τωρινή. null = τίποτα δεν εκκρεμεί. Όσο δεν είναι null, η διόρθωση δεν έχει επιβεβαιωθεί από το κινητό:
 * μένει στην οθόνη του ρολογιού και ξαναστέλνεται ([keepWatchEdits], [tickCmd], [Repo.pendingReps]).
 */
class SetT(
    val load: Double?,
    val label: String,
    var reps: Int,
    var done: Boolean = false,
    var at: Long = 0,
    var confirmed: Boolean = false,
    var trail: Set<Int>? = null,
) {
    /** Αλλαγή επαναλήψεων από το ρολόι σε προπόνηση του κινητού (0–99): η προηγούμενη τιμή μπαίνει στο [trail]. */
    fun edit(v: Int) {
        val n = v.coerceIn(0, 99)
        if (n == reps) return
        trail = (trail ?: emptySet()) + reps
        reps = n
    }
}

/**
 * Η νέα κατάσταση ενός σετ από το κινητό ([set]) πάνω σε ό,τι είχε το ρολόι ([old]). Τελικός έλεγχος, Συμβούλιο 4 (W-4):
 * - ✓ του ρολογιού που το κινητό δεν έχει δει ακόμα: μένει, με την ώρα του (όπως πριν, έλεγχος #2).
 * - Επαναλήψεις που άλλαξες στο ρολόι ([SetT.trail]):
 *   το κινητό δείχνει τη δική σου τιμή → έφτασε, τίποτα δεν εκκρεμεί·
 *   το κινητό δείχνει ακόμα μια παλιά (του [SetT.trail]) → η εντολή δεν έφτασε: μένει η δική σου και ξαναστέλνεται·
 *   το κινητό δείχνει κάτι άλλο → τις άλλαξες στο κινητό στο μεταξύ: ισχύει του κινητού.
 * Πριν, η κατάσταση του κινητού έσβηνε πάντα τη διόρθωση του ρολογιού· αν η εντολή «reps» είχε χαθεί (Bluetooth, κλειστή
 * εφαρμογή στο κινητό), το σετ γραφόταν με τις προγραμματισμένες επαναλήψεις χωρίς να φανεί πουθενά.
 */
fun keepWatchEdits(old: SetT, set: SetT) {
    if (old.done && !set.done && !old.confirmed) {
        set.done = true
        set.at = old.at
    }
    val t = old.trail ?: return
    if (set.reps == old.reps || set.reps !in t) return
    set.reps = old.reps
    set.trail = t
}

/**
 * Η νέα κατάσταση [s] της ΙΔΙΑΣ προπόνησης του κινητού πάνω σε ό,τι ήξερε το ρολόι ([prev]): ανά σετ [keepWatchEdits], η
 * ρεζέρβα που δόθηκε στο ρολόι (όσο το κινητό δεν έχει δική του), και η ερώτηση ρεζέρβας που περιμένει ακόμα εδώ.
 * Ίδιος κανόνας όταν έρχεται νέα κατάσταση ([Repo.applyPhone]) και όταν η εφαρμογή ξανανοίγει μετά από απότομο κλείσιμο
 * (έλεγχος 13/11, round 7, R7-A8-1).
 */
fun mergeWatchEdits(prev: LiveSession, s: LiveSession) {
    for ((i, it) in s.items.withIndex()) {
        val old = prev.items.getOrNull(i) ?: continue
        if (old.ex != it.ex) continue
        for ((k, set) in it.sets.withIndex()) {
            val o = old.sets.getOrNull(k) ?: continue
            keepWatchEdits(o, set)
        }
        if (it.rir == null) it.rir = old.rir
    }
    // Η ερώτηση για ρεζέρβα μένει για την άσκηση που τελείωσε, όχι για όποια δείχνει τώρα το κινητό.
    if (prev.rirIdx >= 0 && s.items.getOrNull(prev.rirIdx)?.rir == null) s.rirIdx = prev.rirIdx
    // R8-U3-01: όσες ρωτήθηκαν δεν ξαναρωτιούνται· η ερώτηση του 1ου σετ μένει ανοιχτή μόνο όσο το κινητό τη θέλει ακόμα
    // («f» στην ίδια άσκηση). Απαντήθηκε στο κινητό (χωρίς «f»): κλείνει εδώ, χωρίς αποστολή.
    s.firstAsked.addAll(prev.firstAsked)
    val fi = prev.firstIdx
    if (fi >= 0 && s.items.getOrNull(fi)?.let { it.first && it.ex == prev.items.getOrNull(fi)?.ex } == true) s.firstIdx = fi
    // Round 9 (R9-A8-3): και οι απαντήσεις στο «Πρώτο σετ» που δόθηκαν εδώ (για την επανάληψη και για το αποτέλεσμα).
    for ((ex, v) in prev.firstAns) if (ex !in s.firstAns) s.firstAns[ex] = v
}

/**
 * Εντολή «επαναλήψεις» προς το κινητό: άσκηση [i], σετ [k], και (νέα πεδία, έλεγχος του γ2, S4) το id της άσκησης [ex]
 * και η ώρα του σετ [at] (αν έγινε), ώστε το κινητό να την αγνοήσει αν δεν ταιριάζουν πια. Το παλιό κινητό τα αγνοεί.
 */
fun repsCmd(i: Int, k: Int, ex: String, reps: Int, at: Long): JSONObject =
    JSONObject().put("op", "reps").put("i", i).put("s", k).put("v", reps).put("ex", ex).also { if (at > 0) it.put("at", at) }

/**
 * Εντολή «✓» προς το κινητό: άσκηση [i], σετ [k], η ώρα του ✓ [at]. Αν άλλαξες τις επαναλήψεις στο ρολόι ([reps] όχι
 * null), πάνε ΜΑΖΙ με το ✓ («r»): ένα ✓ που φτάνει ενώ η εντολή «reps» χάθηκε δεν γράφει πια το σετ με τις
 * προγραμματισμένες επαναλήψεις (τελικός έλεγχος, Συμβούλιο 4, W-4). [late]: ✓ που ξαναστέλνεται (το κινητό δεν ξεκινά
 * νέο διάλειμμα για σετ του παρελθόντος). Νέα πεδία: το παλιό κινητό τα αγνοεί.
 *
 * Έλεγχος 13/11 (S6-10): το id της άσκησης («ex») πάει ΠΑΝΤΑ μαζί με το ✓, όχι μόνο όταν άλλαξαν οι επαναλήψεις. Ένα ✓
 * που φτάνει αργά (ρολόι εκτός εμβέλειας), αφού στο μεταξύ η άσκηση αυτής της θέσης άλλαξε στο κινητό, δεν γράφεται πια
 * στη νέα άσκηση: το κινητό συγκρίνει το «ex». Το κινητό της #100 το αγνοεί όταν λείπει το «r» (όπως πριν).
 */
fun tickCmd(i: Int, k: Int, at: Long, ex: String, reps: Int?, late: Boolean = false): JSONObject =
    JSONObject().put("op", "tick").put("i", i).put("s", k).put("ex", ex).also {
        if (at > 0) it.put("at", at)
        if (reps != null) it.put("r", reps)
        if (late) it.put("late", true)
    }

/**
 * Εντολή «απάντηση στο Πρώτο σετ» προς το κινητό (έλεγχος 14/11, round 8, R8-U3-01, συμβόλαιο με το κινητό στο CROSS.md):
 * άσκηση [i] και [ex] όπως στο «tick», σετ 0, η ώρα του ✓ του 1ου σετ [at] (για τον ίδιο έλεγχο «ανήκει στην προπόνηση»)
 * και [v] 0–4 όπως τα κουμπιά της ρεζέρβας, ή −1 για «Δεν ξέρω» (εκεί το κινητό δεν αλλάζει τίποτα). Το sid / pv / q τα
 * βάζει ο αποστολέας, όπως σε κάθε εντολή. Κινητό παλιότερης έκδοσης: άγνωστη εντολή, δεν κάνει τίποτα.
 */
fun rir1Cmd(i: Int, ex: String, at: Long, v: Int): JSONObject =
    JSONObject().put("op", "rir1").put("i", i).put("s", 0).put("ex", ex).put("v", v.coerceIn(-1, 4)).also { if (at > 0) it.put("at", at) }

/**
 * Τα όρια χρόνου του «Τέλος» (τελικός έλεγχος, Συμβούλιο 4, W-1/W-2). Κάθε κλήση προς το Health Services και προς το
 * κινητό περιμένει το πολύ τόσο· αν δεν απαντήσει, το «Τέλος» συνεχίζει (πριν περίμενε χωρίς όριο: με ένα Health Services
 * που δεν απαντά, το αποτέλεσμα δεν γραφόταν ποτέ και η υπηρεσία έμενε ανοιχτή με τους αισθητήρες).
 */
object FinishTimes {
    /** Αναμονή για μια έναρξη άσκησης που δεν έχει απαντήσει ακόμα, και για καθεμία από flush / end / clear. */
    const val HS_CALL_MS = 4_000L
    /** Μικρή αναμονή μετά το flush, να παραδοθούν οι τελευταίες τιμές. */
    const val FLUSH_SETTLE_MS = 400L
    /** Πόσο περιμένει την τελευταία ενημέρωση («ENDED») του Health Services μετά το «Τέλος» (W2-09). */
    const val ENDED_WAIT_MS = 5_000L
    /** Το μήνυμα «end» προς το κινητό (αν δεν φύγει, το «fin» μέσα στο αποτέλεσμα κάνει την ίδια δουλειά). */
    const val SEND_MS = 3_000L
    /** Το αποτέλεσμα στο Data Layer (αν δεν μπει τώρα, μένει στην αναμονή και μπαίνει στο επόμενο άνοιγμα). */
    const val PUT_MS = 5_000L
    /** Ο χειρότερος δρόμος του «Τέλος», όταν τίποτα δεν απαντά. */
    const val WORST_MS = HS_CALL_MS + HS_CALL_MS + FLUSH_SETTLE_MS + HS_CALL_MS + ENDED_WAIT_MS + HS_CALL_MS + SEND_MS + PUT_MS
    /** Το πολύ τόσο ξύπνιος ο επεξεργαστής στο «Τέλος» (W2-09): καλύπτει τον χειρότερο δρόμο. Αφήνεται μόλις τελειώσει. */
    const val LOCK_MS = 35_000L
}

/**
 * Άσκηση ΔΙΚΗ μας που τρέχει ακόμα στο Health Services ενώ εδώ δεν τρέχει τίποτα και δεν υπάρχει στιγμιότυπο να συνεχίσει
 * (τελικός έλεγχος, Συμβούλιο 4, W-7): έμεινε «ορφανή» (π.χ. το «Τέλος» δεν πήρε απάντηση, ή η έναρξη απάντησε μετά το
 * «Τέλος») και κρατά τους αισθητήρες ανοιχτούς. Τότε τελειώνει στο άνοιγμα της εφαρμογής. [idle]: η οθόνη είναι στην αρχική
 * ή στο «Αποθηκεύτηκε» (ο χρήστης δεν έχει πατήσει έναρξη σε αυτό το άνοιγμα).
 */
fun shouldEndOrphan(owned: Boolean, hasSnapshot: Boolean, running: Boolean, local: Boolean, idle: Boolean): Boolean =
    owned && !hasSnapshot && !running && !local && idle

class ItemT(
    val ex: String,
    val name: String,
    val rest: Int,
    val lo: Int,
    val hi: Int,
    val rirTarget: Int,
    val sets: MutableList<SetT>,
    var rir: Int? = null,
    /** Παραλείφθηκε στο κινητό («skip»: 1, έλεγχος γ2, W2-06): το ρολόι δεν πηγαίνει εκεί. */
    val skipped: Boolean = false,
    /**
     * Μόνο σε προπόνηση του κινητού («f»: 1, έλεγχος 14/11, round 8, R8-U3-01): εκκρεμεί η ερώτηση «Πρώτο σετ: πόσες ακόμα;»
     * αυτής της άσκησης (πρώτη φορά, ελαφριά αρχή). Λείπει = όχι (παλιό κινητό, ή απαντήθηκε).
     */
    val first: Boolean = false,
) {
    val complete: Boolean get() = sets.all { it.done }

    /** Δεν μένει τίποτα να γίνει εδώ: όλα τα σετ ✓ ή παραλείφθηκε (για το «επόμενη άσκηση»). */
    val finished: Boolean get() = complete || skipped
    val doneCount: Int get() = sets.count { it.done }
    val nextSet: Int get() = sets.indexOfFirst { !it.done }
}

/**
 * Αερόβια. [minutes]: τα λεπτά όπως τα έστειλε το κινητό (της εβδομάδας που έγινε η αποστολή). [plan]: τα λεπτά ανά
 * εβδομάδα του προγράμματος (η 1η πρώτη) και [from]: η μέρα έναρξης, αν το κινητό τα στέλνει (έλεγχος 13/11, S6-11/S11-7)·
 * από παλιό κινητό λείπουν και ισχύει το [minutes]. Δες [planMinutes].
 */
class CardioT(
    val activity: String,
    val name: String,
    val minutes: Int,
    val note: String?,
    val plan: List<Int> = emptyList(),
    val from: java.time.LocalDate? = null,
)

/**
 * Τα λεπτά της αερόβιας τη μέρα [day] (έλεγχος 13/11, S6-11/S11-7). Ίδιος κανόνας με το κινητό (Program.weekOf και
 * Cardio.minutesInWeek): εβδομάδα = ημερολογιακές μέρες από το [from] διά 7· πριν από το [from] ισχύει η 1η τιμή, μετά το
 * τέλος του πλάνου η τελευταία. Χωρίς πλάνο ή χωρίς μέρα έναρξης (παλιό κινητό): τα λεπτά που στάλθηκαν ([sent]).
 * Πριν, το ρολόι έδειχνε πάντα τα λεπτά της εβδομάδας που έγινε η αποστολή: αν το κινητό δεν άνοιγε μέσα στη νέα
 * εβδομάδα, το κουμπί έγραφε τα λεπτά της προηγούμενης. Μέρες ημερολογίου (LocalDate): η αλλαγή ώρας δεν το πειράζει.
 */
fun planMinutes(sent: Int, plan: List<Int>, from: java.time.LocalDate?, day: java.time.LocalDate): Int {
    if (plan.isEmpty() || from == null) return sent
    val days = java.time.temporal.ChronoUnit.DAYS.between(from, day)
    val week = if (days < 0) 0L else days / 7
    return plan[minOf(week, (plan.size - 1).toLong()).toInt()]
}

/** «2026-11-16» → μέρα, ή null για ό,τι δεν διαβάζεται (τότε ισχύουν τα λεπτά που στάλθηκαν). */
internal fun dayOrNull(text: String?): java.time.LocalDate? = try {
    if (text == null || text.length < 10) null else java.time.LocalDate.parse(text.substring(0, 10))
} catch (_: Exception) {
    null
}

/** Τα λεπτά ανά εβδομάδα από το JSON: μόνο ακέραιοι 1–600 (όπως τα δέχεται το κινητό)· αλλιώς κανένα πλάνο. */
internal fun weekPlanOf(a: JSONArray?): List<Int> {
    if (a == null || a.length() == 0) return emptyList()
    val out = ArrayList<Int>(a.length())
    for (k in 0 until a.length()) {
        val v = a.optInt(k, -1)
        if (v !in 1..600) return emptyList()
        out.add(v)
    }
    return out
}

class WorkoutT(val id: String, val name: String, val minutes: Int, val items: List<ItemT>, val cardio: CardioT?) {
    val isCardio: Boolean get() = cardio != null
}

class Plan(
    val hrLimit: Int?,
    /** Το id της προπόνησης της μέρας που το έστειλε το κινητό (ή null για ξεκούραση). */
    val today: String?,
    val day: String?,
    val workouts: List<WorkoutT>,
    val at: Long,
    /** Μέρα εβδομάδας (1 = Δευτέρα … 7 = Κυριακή) → id προπόνησης. */
    val days: Map<Int, String> = emptyMap(),
    /** Ζώνη περπατήματος (κινητό από 12/11)· παλιό κινητό: null, καμία δόνηση ζώνης. */
    val zone: WalkZone? = null,
    /** Η μέρα έναρξης του προγράμματος («from», έλεγχος 13/11, S6-11)· παλιό κινητό: null. */
    val from: java.time.LocalDate? = null,
) {
    fun workout(id: String?): WorkoutT? = workouts.firstOrNull { it.id == id }

    /**
     * Τα λεπτά της αερόβιας [c] τη μέρα [day] ([planMinutes]): της εβδομάδας του προγράμματος που τρέχει ΣΗΜΕΡΑ, και αν το
     * κινητό δεν άνοιξε μέσα σε αυτήν. Η μέρα έναρξης μέσα στο «cardio», αν υπάρχει, αλλιώς του προγράμματος.
     */
    fun cardioMinutes(c: CardioT, day: java.time.LocalDate = java.time.LocalDate.now()): Int =
        planMinutes(c.minutes, c.plan, c.from ?: from, day)

    /** Η προπόνηση μιας μέρας (για να είναι σωστή και αν το κινητό δεν άνοιξε σήμερα). */
    fun forWeekday(weekday: Int): WorkoutT? = if (days.isEmpty()) workout(today) else workout(days[weekday])

    /**
     * Η προπόνηση της μέρας [day]: καμία πριν από την έναρξη του προγράμματος ([from]), όπως στο κινητό (Program.forDay·
     * έλεγχος 13/11, round 7, R7-A6-6, αίτημα του f2). Πριν, το Σάββατο πριν από την έναρξη έγραφε «Σήμερα · <προπόνηση>».
     * Παλιό κινητό (χωρίς «from»): όπως πριν.
     */
    fun forDay(day: java.time.LocalDate): WorkoutT? = if (from != null && day < from) null else forWeekday(day.dayOfWeek.value)

    val todayWorkout: WorkoutT? get() = forDay(java.time.LocalDate.now())

    /**
     * Το περπάτημα (αερόβια) του προγράμματος τη μέρα που ξεκίνησε μια άσκηση στις [startedAt] (ms), ή null (έλεγχος 13/11,
     * round 7, R7-A8-6): όχι της μέρας που γράφεται το αποτέλεσμα. Χωρίς ώρα έναρξης: της σημερινής, όπως πριν.
     */
    fun walkOn(startedAt: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): WorkoutT? {
        val w = if (startedAt > 0) forDay(dayOf(startedAt, zone)) else todayWorkout
        return w?.takeIf { it.isCardio }
    }

    /** Η μέρα (ημερολογίου) της στιγμής [at] (ms)· χωρίς ώρα ([at] ≤ 0): σήμερα. */
    fun dayOf(at: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): java.time.LocalDate =
        if (at > 0) java.time.Instant.ofEpochMilli(at).atZone(zone).toLocalDate() else java.time.LocalDate.now(zone)

    companion object {
        fun parse(text: String): Plan? = try {
            val j = JSONObject(text)
            val ws = j.optJSONArray("workouts") ?: JSONArray()
            Plan(
                hrLimit = if (j.has("hrLimit") && !j.isNull("hrLimit")) j.getInt("hrLimit") else null,
                today = j.optStringOrNull("today"),
                day = j.optStringOrNull("day"),
                workouts = (0 until ws.length()).map { workoutOf(ws.getJSONObject(it)) },
                at = j.optLong("at", 0),
                days = j.optJSONObject("days")?.let { d ->
                    d.keys().asSequence().mapNotNull { k -> k.toIntOrNull()?.let { it to d.getString(k) } }.toMap()
                } ?: emptyMap(),
                zone = WalkZone.parse(j.optJSONObject("zone")),
                from = dayOrNull(j.optStringOrNull("from")),
            )
        } catch (_: Exception) {
            null
        }
    }
}

/** Η ζώνη περπατήματος όπως τη στέλνει το κινητό: κάτω/πάνω όριο και ποιες δονήσεις είναι ανοιχτές. */
data class WalkZone(val lo: Int, val hi: Int, val up: Boolean = true, val down: Boolean = false) {
    fun toJson(): JSONObject = JSONObject().put("lo", lo).put("hi", hi).put("up", up).put("down", down)

    companion object {
        /** null για ό,τι δεν μοιάζει σωστό (τότε καμία δόνηση, όχι λάθος δόνηση). */
        fun parse(j: JSONObject?): WalkZone? {
            if (j == null || !j.has("lo") || !j.has("hi")) return null
            val lo = j.optInt("lo", -1)
            val hi = j.optInt("hi", -1)
            if (lo < 50 || hi > 220 || lo >= hi) return null
            return WalkZone(lo, hi, j.optBoolean("up", true), j.optBoolean("down", false))
        }
    }
}

/**
 * Κείμενο ή null (λείπει ή είναι JSON null). Έλεγχος 13/11 (S12-17β): ΚΑΙ για κάθε κείμενο με προεπιλογή γράφουμε
 * `optStringOrNull(k) ?: προεπιλογή` αντί για `optString(k, προεπιλογή)`: για τιμή JSON null το org.json του Android δίνει
 * το κείμενο «null» (θα γραφόταν «null» στην οθόνη), ενώ το json.org των δοκιμών δίνει την προεπιλογή.
 */
internal fun JSONObject.optStringOrNull(k: String): String? = if (has(k) && !isNull(k)) getString(k) else null

internal fun itemOf(o: JSONObject): ItemT {
    val sets = o.optJSONArray("sets") ?: JSONArray()
    return ItemT(
        ex = o.getString("ex"),
        name = o.optStringOrNull("name") ?: o.getString("ex"),
        rest = o.optInt("rest", 90),
        lo = o.optInt("lo", 8),
        hi = o.optInt("hi", 12),
        rirTarget = o.optInt("rir", 2),
        sets = (0 until sets.length()).map {
            val s = sets.getJSONObject(it)
            SetT(
                load = if (s.has("load") && !s.isNull("load")) s.getDouble("load") else null,
                label = s.optStringOrNull("label") ?: "",
                reps = s.optInt("reps", 0),
                done = s.optBoolean("done", false),
                at = s.optLong("at", 0),
            )
        }.toMutableList(),
        rir = if (o.has("ra") && !o.isNull("ra")) o.getInt("ra") else null,
        skipped = o.optInt("skip", 0) == 1,
        // R8-U3-01: «f»: 1 (ή true) από το κινητό.
        first = o.optInt("f", 0) == 1 || o.optBoolean("f", false),
    )
}

internal fun workoutOf(o: JSONObject): WorkoutT {
    val items = o.optJSONArray("items") ?: JSONArray()
    val c = o.optJSONObject("cardio")
    return WorkoutT(
        id = o.getString("id"),
        name = o.optStringOrNull("name") ?: o.getString("id"),
        minutes = o.optInt("minutes", 0),
        items = (0 until items.length()).map { itemOf(items.getJSONObject(it)) },
        cardio = c?.let {
            CardioT(
                it.optStringOrNull("activity") ?: "walk", it.optStringOrNull("name") ?: "Περπάτημα", it.optInt("minutes", 30), it.optStringOrNull("note"),
                plan = weekPlanOf(it.optJSONArray("plan")),
                from = dayOrNull(it.optStringOrNull("from")),
            )
        },
    )
}

/**
 * Προπόνηση σε εξέλιξη στο ρολόι: είτε δική του ([phone] = false, από το [Plan]) είτε καθρέφτης της προπόνησης
 * του κινητού ([phone] = true, από το [Paths.SESSION]). Ίδια οθόνη και για τις δύο.
 */
class LiveSession(
    val id: String,
    val workout: String,
    val name: String,
    val start: Long,
    val items: List<ItemT>,
    var idx: Int = 0,
    /** Τέλος διαλείμματος (ms), 0 = χωρίς διάλειμμα. */
    var restEnd: Long = 0,
    val phone: Boolean = false,
    /** Το κινητό έκλεισε την προπόνηση (μόνο για [phone]). */
    var ended: Boolean = false,
    /**
     * Η άσκηση που περιμένει απάντηση για ρεζέρβα (−1 = καμία). Κλειδώνει τη στιγμή του τελευταίου ✓,
     * γιατί στο μεταξύ το κινητό μπορεί να έχει ήδη πάει στην επόμενη άσκηση (έλεγχος 8/11).
     */
    var rirIdx: Int = -1,
    /**
     * Πόσο κρατά όλο το τρέχον διάλειμμα (ms), για το δαχτυλίδι (έλεγχος γ2, W2-20): το διάλειμμα μετά το τελευταίο σετ
     * είναι της άσκησης που τελείωσε, όχι της επόμενης (που δείχνει πια το [idx]). 0 = άγνωστο.
     */
    var restLen: Long = 0,
    /**
     * Μόνο για [phone]: πότε πατήθηκε «Συνέχεια» στην «Ξεχασμένη προπόνηση;» του κινητού (ms, «res» του [Paths.SESSION]·
     * 0 = ποτέ ή παλιό κινητό). Μετρά ως κίνηση στο [phoneLastActivity] (έλεγχος 14/11, round 8, R8-A8-3, αίτημα του f2).
     */
    val res: Long = 0,
) {
    val current: ItemT? get() = items.getOrNull(idx)

    /**
     * Περιμένει απάντηση για ρεζέρβα (το ρολόι δείχνει την ερώτηση). Σε προπόνηση του κινητού: αν απαντήθηκε στο κινητό,
     * όχι πια — η οθόνη του ρολογιού την αφήνει (έλεγχος γ2, W2-18).
     */
    val rirPending: Boolean get() = rirIdx >= 0 && items.getOrNull(rirIdx)?.rir == null

    /**
     * Έλεγχος 14/11, round 8 (R8-U3-01), μόνο σε προπόνηση του κινητού: η άσκηση (θέση) που περιμένει εδώ απάντηση στο
     * «Πρώτο σετ: πόσες ακόμα;» (−1 = καμία), και οι ασκήσεις (id) για τις οποίες ρωτήθηκε ήδη σε αυτή την προπόνηση: ποτέ
     * δεύτερη φορά (κρατιούνται και στο στιγμιότυπο, «fa»).
     */
    var firstIdx: Int = -1
    val firstAsked: MutableSet<String> = mutableSetOf()

    /**
     * Έλεγχος 14/11, round 9 (R9-A8-3), μόνο σε προπόνηση του κινητού: η απάντηση που δόθηκε ΕΔΩ στο «Πρώτο σετ» ανά άσκηση
     * (id → 0–4, ή −1 για «Δεν ξέρω»). Ξαναστέλνεται ως «rir1» όσο το κινητό τη ζητά ακόμα ([firstResends]) και πάει και στο
     * αποτέλεσμα των παλμών («fr»). Κρατιέται και στο στιγμιότυπο («fr» του «pp»).
     */
    val firstAns: MutableMap<String, Int> = mutableMapOf()

    /** Η ερώτηση του 1ου σετ είναι ανοιχτή εδώ και το κινητό τη θέλει ακόμα («f»). */
    val firstPending: Boolean get() = firstIdx >= 0 && items.getOrNull(firstIdx)?.first == true

    /**
     * Μετά το ✓ του σετ [k] της άσκησης [i] σε αυτό το ρολόι ([tick] έδωσε [next]): ανοίγει η ερώτηση του 1ου σετ, αν είναι
     * προπόνηση του κινητού, το σετ είναι το 1ο, το κινητό τη ζητά («f») και δεν ρωτήθηκε ήδη. Μόνο όταν ακολουθεί
     * διάλειμμα (μένουν σετ): το διάλειμμα τρέχει κανονικά από κάτω. true αν άνοιξε.
     */
    fun askFirst(i: Int, k: Int, next: Next): Boolean {
        val it = items.getOrNull(i) ?: return false
        if (!phone || k != 0 || !it.first || next != Next.REST || it.ex in firstAsked) return false
        firstIdx = i
        firstAsked.add(it.ex)
        return true
    }

    /** Η απάντηση κλείνει την ερώτηση του 1ου σετ. Η θέση της άσκησης για την εντολή, ή −1 αν δεν περίμενε τίποτα. */
    fun answerFirst(): Int {
        val pending = firstPending
        val i = firstIdx
        firstIdx = -1
        return if (pending) i else -1
    }

    /**
     * Έλεγχος 14/11, round 9 (R9-A12-2): ένα πάτημα στην οθόνη της ρεζέρβας ([rir] 0–4, −1 = «Δεν ξέρω»), όπως το κρίνει η
     * οθόνη ([WatchActivity.answer]). Πρώτα η ερώτηση «Πρώτο σετ», αν είναι ανοιχτή ([firstIdx] ≥ 0): την ΚΛΕΙΝΕΙ
     * ([answerFirst]) και, σε προπόνηση του κινητού που τη ζητά ακόμα, δίνει την εντολή «rir1» και κρατά την απάντηση
     * ([firstAns], R9-A8-3). Η ρεζέρβα της άσκησης δεν αλλάζει. Αλλιώς: η ρεζέρβα της άσκησης ([answer]).
     */
    fun answerAny(rir: Int, now: Long): AnswerResult {
        if (firstIdx >= 0) {
            val fi = answerFirst()
            val item = items.getOrNull(fi)
            if (!phone || item == null) return AnswerResult(true, null, null, fi)
            val v = rir.coerceIn(-1, 4)
            firstAns[item.ex] = v
            return AnswerResult(true, rir1Cmd(fi, item.ex, item.sets.getOrNull(0)?.at ?: 0L, v), null, fi)
        }
        val (next, i) = answer(rir, now)
        return AnswerResult(false, null, next, i)
    }

    /**
     * Έλεγχος 14/11, round 9 (R9-A8-3): οι απαντήσεις στο «Πρώτο σετ» που δόθηκαν εδώ ([firstAns]) και το κινητό ΔΕΝ έχει
     * πάρει ακόμα: η κατάστασή του ζητά ακόμα την ερώτηση («f») ενώ έχει ήδη το ✓ του 1ου σετ (πριν από αυτό πρώτα ξαναστέλνεται
     * το ✓, με τις επαναλήψεις του). Ως (θέση, id άσκησης, απάντηση), για να ξανασταλούν ως «rir1» ([rir1Cmd]). Το κινητό
     * κρατά μόνο την πρώτη απάντηση («η πρώτη κερδίζει»): μια δεύτερη δεν αλλάζει τίποτα. Μόλις τη δεχτεί, χωρίς «f» → τίποτα.
     */
    fun firstResends(): List<Triple<Int, String, Int>> {
        if (!phone) return emptyList()
        val out = mutableListOf<Triple<Int, String, Int>>()
        for ((i, it) in items.withIndex()) {
            val v = firstAns[it.ex] ?: continue
            val s0 = it.sets.getOrNull(0) ?: continue
            if (it.first && s0.done && s0.confirmed) out.add(Triple(i, it.ex, v))
        }
        return out
    }

    /** Όλες οι ασκήσεις τελείωσαν (ή παραλείφθηκαν στο κινητό). */
    val allDone: Boolean get() = items.all { it.finished }

    /** Διάλειμμα [sec] δευτερόλεπτα από τώρα (0 = κανένα). */
    private fun startRest(now: Long, sec: Int) {
        restEnd = if (sec > 0) now + sec * 1000L else 0
        restLen = if (sec > 0) sec * 1000L else 0
    }

    /**
     * Το σετ που μόλις έγινε σε αυτό το ρολόι ([άσκηση, σετ]), για διόρθωση των επαναλήψεων στο διάλειμμα (RT-13): το
     * πιο πρόσφατο ✓ με ώρα, μόνο όσο κρατά το διάλειμμα που ξεκίνησε με αυτό.
     */
    fun lastDone(now: Long): Pair<Int, Int>? {
        if (restEnd <= now) return null
        var best: Pair<Int, Int>? = null
        var at = 0L
        for ((i, it) in items.withIndex()) for ((k, set) in it.sets.withIndex()) {
            if (set.done && set.at > at) {
                at = set.at
                best = i to k
            }
        }
        val from = restEnd - (if (restLen > 0) restLen else 0L) - 2_000
        return if (best != null && (restLen <= 0 || at >= from)) best else null
    }

    /** «+30″» στο διάλειμμα. */
    fun addRest(now: Long, ms: Long = 30_000) {
        if (restEnd > now) {
            restEnd += ms
            restLen = maxOf(restLen, 0) + ms
        } else {
            restEnd = now + ms
            restLen = ms
        }
    }

    /** Πόσο από το διάλειμμα μένει (1 = όλο, 0 = τελείωσε), για το δαχτυλίδι. */
    fun restLeft(now: Long): Float {
        val left = (restEnd - now).coerceAtLeast(0)
        val total = if (restLen > 0) restLen else (items.getOrNull(idx)?.rest ?: 90).coerceAtLeast(1) * 1000L
        return (left.toFloat() / maxOf(total, left).coerceAtLeast(1)).coerceIn(0f, 1f)
    }
    val setsDone: Int get() = items.sumOf { it.doneCount }

    /** ✓ στο τρέχον σετ. Επιστρέφει τι ακολουθεί. */
    fun tick(now: Long): Next {
        val it = current ?: return Next.END
        val s = it.nextSet
        if (s < 0) return advance(now)
        it.sets[s].done = true
        it.sets[s].at = now
        if (!it.complete) {
            startRest(now, it.rest)
            return Next.REST
        }
        rirIdx = idx
        return Next.ASK_RIR
    }

    /**
     * Ρεζέρβα μετά το τελευταίο σετ· μετά πάει στην επόμενη άσκηση που δεν έχει τελειώσει. Επιστρέφει και ποια άσκηση πήρε
     * την απάντηση: −1 αν καμία δεν περιμένει απάντηση (π.χ. απαντήθηκε ήδη στο κινητό)· τότε δεν γράφεται πουθενά, ποτέ
     * στην άσκηση που δείχνει τώρα (έλεγχος γ2, W2-18).
     *
     * Έλεγχος 13/11, round 7 (R7-U3-04): [rir] αρνητικό = «Δεν ξέρω». Η ερώτηση κλείνει, αλλά καμία απάντηση δεν γράφεται
     * (η ρεζέρβα μένει null, όπως το «Δεν ξέρω» του κινητού): ένας αριθμός «στην τύχη» θα ανέβαζε βάρος.
     */
    fun answer(rir: Int, now: Long): Pair<Next, Int> {
        val i = rirIdx
        if (i < 0 || items.getOrNull(i) == null) {
            rirIdx = -1
            return (if (current == null || allDone) Next.END else Next.SET) to -1
        }
        val restSec = items.getOrNull(i)?.rest ?: 0
        items.getOrNull(i)?.rir = rir.takeIf { it >= 0 }
        rirIdx = -1
        return advance(now, restSec) to i
    }

    private fun advance(now: Long, restOf: Int? = null): Next {
        val restSec = restOf ?: current?.rest ?: 0
        val next = items.indexOfFirst { !it.finished }
        if (next < 0) {
            startRest(now, 0)
            return Next.END
        }
        idx = next
        startRest(now, restSec)
        return Next.REST
    }

    /** Παράλειψη της τρέχουσας άσκησης (πάει στην επόμενη, χωρίς διάλειμμα). */
    fun skip(): Next {
        val n = items.indices.firstOrNull { it > idx && !items[it].finished } ?: items.indices.firstOrNull { it != idx && !items[it].finished }
        restEnd = 0
        restLen = 0
        if (n == null) return Next.END
        idx = n
        return Next.SET
    }

    enum class Next { SET, REST, ASK_RIR, END }

    /** Η κατάσταση για το στιγμιότυπο (έλεγχος 9/11, V-A-03): ονόματα, στόχοι, ✓ με την ώρα τους, τρέχουσα άσκηση. */
    fun toState(): JSONObject {
        val arr = JSONArray()
        for (it in items) {
            val sets = JSONArray()
            for (s in it.sets) {
                val o = JSONObject().put("label", s.label).put("reps", s.reps)
                if (s.load != null) o.put("load", finite(s.load))
                if (s.done) o.put("done", true).put("at", s.at)
                sets.put(o)
            }
            val o = JSONObject().put("ex", it.ex).put("name", it.name).put("rest", it.rest).put("lo", it.lo).put("hi", it.hi)
                .put("rir", it.rirTarget).put("sets", sets)
            it.rir?.let { r -> o.put("ra", r) }
            if (it.skipped) o.put("skip", 1)
            arr.put(o)
        }
        return JSONObject().put("id", id).put("w", workout).put("name", name).put("start", start).put("idx", idx)
            .put("restEnd", restEnd).put("rirIdx", rirIdx).put("restLen", restLen).put("items", arr)
    }

    /** Για το κινητό: ίδια μορφή με το ExLog.toJson της εφαρμογής (l, r, d, t). */
    fun resultJson(end: Long, hr: HrStats, cardio: JSONObject? = null): JSONObject {
        val arr = JSONArray()
        for (it in items) {
            val log = JSONArray()
            for (s in it.sets) {
                val o = JSONObject().put("r", s.reps)
                if (s.load != null) o.put("l", s.load)
                if (s.done) o.put("d", 1).put("t", s.at)
                // Διόρθωση επαναλήψεων του ρολογιού που δεν επιβεβαιώθηκε από το κινητό (Συμβούλιο 4, W-4): μαζί και οι τιμές
                // που είχε το κινητό πριν («rb»), για να την εφαρμόσει μόνο αν δείχνει ακόμα μία από αυτές (δεν άλλαξε
                // κάτι εκεί στο μεταξύ). Νέο πεδίο: το παλιό κινητό το αγνοεί.
                s.trail?.let { t -> o.put("rb", JSONArray(t.sorted())) }
                log.put(o)
            }
            val o = JSONObject()
                .put("ex", it.ex).put("sets", it.sets.size).put("lo", it.lo).put("hi", it.hi)
                .put("rir", it.rirTarget).put("rest", it.rest).put("log", log)
            it.rir?.let { r -> o.put("ra", r) }
            // Round 9 (R9-A8-3): η απάντηση του ρολογιού στο «Πρώτο σετ» (0–4, −1 = «Δεν ξέρω»), αντίγραφο της «rir1» για την
            // περίπτωση που εκείνη δεν έφτασε ποτέ (όπως το «ra» για τη ρεζέρβα). Νέο πεδίο: το παλιό κινητό το αγνοεί.
            firstAns[it.ex]?.let { v -> o.put("fr", v) }
            arr.put(o)
        }
        return JSONObject()
            .put("v", 1).put("id", id).put("kind", if (cardio != null) "cardio" else "strength")
            .put("w", workout).put("name", name).put("start", start).put("end", end)
            .put("items", arr)
            .also { o -> hr.writeTo(o) }
            .also { o -> if (cardio != null) o.put("cardio", cardio) }
    }

    companion object {
        /** Δική του προπόνηση από το πρόγραμμα (αντίγραφο των στόχων, για να μη πειράζει το [Plan]). */
        fun fromPlan(w: WorkoutT, now: Long): LiveSession = LiveSession(
            id = "w$now",
            workout = w.id,
            name = w.name,
            start = now,
            items = w.items.map { i ->
                ItemT(i.ex, i.name, i.rest, i.lo, i.hi, i.rirTarget, i.sets.map { SetT(it.load, it.label, it.reps) }.toMutableList())
            },
        )

        /** Από το στιγμιότυπο ([toState]), ή null αν δεν διαβάζεται. */
        fun fromState(o: JSONObject): LiveSession? = try {
            val arr = o.optJSONArray("items") ?: JSONArray()
            LiveSession(
                id = o.getString("id"),
                workout = o.optStringOrNull("w") ?: "",
                name = o.optStringOrNull("name") ?: "",
                start = o.optLong("start", 0),
                items = (0 until arr.length()).map { itemOf(arr.getJSONObject(it)) },
                idx = o.optInt("idx", 0),
                restEnd = o.optLong("restEnd", 0),
                rirIdx = o.optInt("rirIdx", -1),
                restLen = o.optLong("restLen", 0),
            )
        } catch (_: Exception) {
            null
        }

        /**
         * Η προπόνηση του κινητού όπως την ξέρει ΤΟ ΡΟΛΟΪ, για το στιγμιότυπο της άσκησης (έλεγχος 13/11, round 7, R7-A8-1):
         * ό,τι γράφει το [toState] και, ανά σετ, αν το κινητό το έχει δει («c»: 1, [SetT.confirmed]) και τις τιμές που μπορεί να
         * δείχνει ακόμα το κινητό («rb», [SetT.trail]). Έτσι τα ✓, οι επαναλήψεις και η ρεζέρβα του ρολογιού που δεν έφτασαν
         * ακόμα στο κινητό ΔΕΝ χάνονται αν η εφαρμογή του ρολογιού κλείσει απότομα. Νέο πεδίο του run.json («pp»): η παλιά
         * έκδοση το αγνοεί.
         */
        fun phoneWatchState(s: LiveSession): JSONObject {
            val o = s.toState()
            val arr = o.getJSONArray("items")
            for ((i, item) in s.items.withIndex()) {
                val sets = arr.getJSONObject(i).getJSONArray("sets")
                for ((k, set) in item.sets.withIndex()) {
                    val so = sets.getJSONObject(k)
                    if (set.confirmed) so.put("c", 1)
                    set.trail?.let { t -> so.put("rb", JSONArray(t.sorted())) }
                }
            }
            // R8-A8-3: και η «Συνέχεια» του κινητού (νέο, προαιρετικό πεδίο).
            if (s.res > 0) o.put("res", s.res)
            // R8-U3-01: οι ασκήσεις που ρωτήθηκαν ήδη για το 1ο σετ (νέο, προαιρετικό πεδίο): ούτε μετά από επανεκκίνηση ξανά.
            if (s.firstAsked.isNotEmpty()) o.put("fa", JSONArray(s.firstAsked.sorted()))
            // R9-A8-3: και οι απαντήσεις που δόθηκαν εδώ (νέο, προαιρετικό πεδίο): ξαναστέλνονται και μετά από επανεκκίνηση.
            if (s.firstAns.isNotEmpty()) o.put("fr", JSONObject().also { m -> for ((ex, v) in s.firstAns) m.put(ex, v) })
            return o
        }

        /** Από το [phoneWatchState]: η προπόνηση του κινητού όπως την ήξερε το ρολόι, ή null αν δεν διαβάζεται. */
        fun phoneFromWatchState(o: JSONObject): LiveSession? {
            val s = fromState(o) ?: return null
            return try {
                val arr = o.optJSONArray("items") ?: JSONArray()
                for ((i, item) in s.items.withIndex()) {
                    val sets = arr.optJSONObject(i)?.optJSONArray("sets") ?: continue
                    for ((k, set) in item.sets.withIndex()) {
                        val so = sets.optJSONObject(k) ?: continue
                        set.confirmed = so.optInt("c", 0) == 1
                        val rb = so.optJSONArray("rb") ?: continue
                        val t = (0 until rb.length()).map { rb.optInt(it, -1) }.filter { it in 0..99 }.toSet()
                        if (t.isNotEmpty()) set.trail = t
                    }
                }
                LiveSession(
                    s.id, s.workout, s.name, s.start, s.items, s.idx, s.restEnd, phone = true, rirIdx = s.rirIdx, restLen = s.restLen,
                    res = o.optLong("res", 0),
                ).also { p ->
                    o.optJSONArray("fa")?.let { a -> for (k in 0 until a.length()) a.optString(k, "").takeIf { it.isNotEmpty() }?.let { p.firstAsked.add(it) } }
                    // R9-A8-3: στιγμιότυπο χωρίς «fr» (έκδοση ως #107): καμία απάντηση. Μόνο τιμές −1…4.
                    o.optJSONObject("fr")?.let { m ->
                        for (ex in m.keys().asSequence()) {
                            val v = m.optInt(ex, Int.MIN_VALUE)
                            if (ex.isNotEmpty() && v in -1..4) p.firstAns[ex] = v
                        }
                    }
                }
            } catch (_: Exception) {
                null
            }
        }

        /** Η προπόνηση του κινητού ([Paths.SESSION]). null αν δεν τρέχει καμία. */
        fun parsePhone(text: String): LiveSession? = try {
            val j = JSONObject(text)
            if (!j.optBoolean("active", false)) {
                null
            } else {
                val arr = j.optJSONArray("items") ?: JSONArray()
                LiveSession(
                    id = j.getString("id"),
                    workout = j.optStringOrNull("w") ?: "",
                    name = j.optStringOrNull("name") ?: "",
                    start = j.optLong("start", 0),
                    items = (0 until arr.length()).map { itemOf(arr.getJSONObject(it)) },
                    idx = j.optInt("idx", 0),
                    restEnd = j.optLong("restEnd", 0),
                    phone = true,
                    // R8-A8-3: «Συνέχεια» στην «Ξεχασμένη προπόνηση;» του κινητού (νέο, προαιρετικό· παλιό κινητό: 0).
                    res = j.optLong("res", 0),
                )
            }
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Παλμοί μιας άσκησης: μέσος, μέγιστος και οι τιμές με τον χρόνο τους. Κρατά μία τιμή ανά [step] δευτερόλεπτα
 * (1″: όσο συχνά μετρά το ρολόι· ως #87 κρατούσε μία ανά 10″ και οι παλμοί ανά σετ δεν έβγαιναν σωστοί, 9/11).
 * [start] (ms) πάει μαζί με τις τιμές («hrT0»), ώστε το κινητό να τις βάλει στη σωστή ώρα της προπόνησής του.
 *
 * Παύσεις και «Τέλος» κρίνονται με τον χρόνο ΚΑΘΕ τιμής, όχι με την ώρα που έφτασε (έλεγχος 9/11, W3-11): οι τιμές
 * έρχονται σε πακέτα (ανά 5″ ή και λεπτά), οπότε μια τιμή πριν από την παύση μπορεί να φτάσει μετά.
 */
class HrStats(val start: Long, private val step: Int = 1) {
    private var sum = 0L
    private var n = 0
    var max = 0
        private set
    var last = 0
        private set
    val samples = mutableListOf<IntArray>()
    private var lastSampleSec = -1

    /** Χειροκίνητο «δεν μετράει» (παλιός τρόπος· οι παύσεις πλέον με [pause]/[resume], ανά χρόνο τιμής). */
    var counting = true

    /** Παύσεις σε δευτερόλεπτα από την αρχή: [από, ως) — «ως» = Int.MAX_VALUE όσο κρατά. */
    private val pauses = mutableListOf<IntArray>()

    /** Το «Τέλος» (δευτερόλεπτα από την αρχή): ό,τι μετά είναι λεπτό αποκατάστασης και δεν πάει στο κινητό ως άσκηση. */
    var endSec = Int.MAX_VALUE
        private set

    private fun secOf(at: Long): Int = ((at - start) / 1000).toInt()

    fun markEnd(at: Long) {
        endSec = secOf(at)
    }

    /** Παύση από [at]: τιμές με χρόνο μέσα στην παύση δεν μετρούν στον μέσο/υψηλότερο (κρατιούνται ως τιμές). */
    fun pause(at: Long) {
        if (pauses.lastOrNull()?.get(1) == Int.MAX_VALUE) return
        pauses.add(intArrayOf(secOf(at), Int.MAX_VALUE))
    }

    fun resume(at: Long) {
        val p = pauses.lastOrNull() ?: return
        if (p[1] == Int.MAX_VALUE) p[1] = maxOf(p[0], secOf(at))
    }

    private fun paused(sec: Int): Boolean = pauses.any { sec >= it[0] && sec < it[1] }

    fun add(bpm: Int, at: Long) {
        if (bpm <= 25 || bpm >= 250) return // όχι πραγματική τιμή (π.χ. το ρολόι δεν ακουμπά)
        val sec = secOf(at)
        // Ίδιο ή παλιότερο δευτερόλεπτο από ό,τι έχουμε ήδη (π.χ. ξαναπαράδοση μετά από επανασύνδεση, V-A-03): ήδη μετρήθηκε.
        if (lastSampleSec >= 0 && sec <= lastSampleSec) return
        last = bpm
        if (counting && sec <= endSec && !paused(sec)) {
            sum += bpm
            n++
            if (bpm > max) max = bpm
        }
        if (lastSampleSec < 0 || sec - lastSampleSec >= step) {
            samples.add(intArrayOf(sec, bpm))
            lastSampleSec = sec
        }
    }

    val avg: Int get() = if (n == 0) 0 else Math.round(sum.toDouble() / n).toInt()

    fun writeTo(o: JSONObject) {
        if (n == 0) return
        o.put("hrAvg", avg).put("hrMax", max).put("hrT0", start)
        val a = JSONArray()
        for (s in fit(samples.filter { it[0] <= endSec })) a.put(JSONArray().put(s[0]).put(s[1]))
        o.put("hr", a)
    }

    /** Πτώση παλμών 1′ μετά το «Τέλος»: (παλμοί στο τέλος, παλμοί στο 1′), ή null. Δες [recovery]. */
    fun recovery(): Pair<Int, Int>? = if (endSec == Int.MAX_VALUE) null else recovery(samples, endSec)

    /** Για το στιγμιότυπο της άσκησης (έλεγχος 9/11, V-A-03): όλη η κατάσταση, για να συνεχίσει μετά από απότομο κλείσιμο. */
    fun toState(): JSONObject {
        val s = JSONArray()
        for (x in samples) s.put(JSONArray().put(x[0]).put(x[1]))
        val p = JSONArray()
        for (x in pauses) p.put(JSONArray().put(x[0]).put(x[1]))
        return JSONObject().put("start", start).put("step", step).put("sum", sum).put("n", n).put("max", max).put("last", last)
            .put("end", endSec).put("counting", counting).put("ls", lastSampleSec).put("s", s).put("pz", p)
    }

    companion object {
        fun fromState(o: JSONObject): HrStats {
            val h = HrStats(o.getLong("start"), o.optInt("step", 1))
            h.sum = o.optLong("sum", 0)
            h.n = o.optInt("n", 0)
            h.max = o.optInt("max", 0)
            h.last = o.optInt("last", 0)
            h.endSec = o.optInt("end", Int.MAX_VALUE)
            h.counting = o.optBoolean("counting", true)
            h.lastSampleSec = o.optInt("ls", -1)
            o.optJSONArray("s")?.let { a -> for (i in 0 until a.length()) a.optJSONArray(i)?.let { h.samples.add(intArrayOf(it.getInt(0), it.getInt(1))) } }
            o.optJSONArray("pz")?.let { a -> for (i in 0 until a.length()) a.optJSONArray(i)?.let { h.pauses.add(intArrayOf(it.getInt(0), it.getInt(1))) } }
            return h
        }

        /** Πόσο κρατά το λεπτό αποκατάστασης: ως το τέλος του παραθύρου γύρω από το 1′ (55″–65″). */
        const val RECOVERY_MS = 65_000L

        /**
         * Πτώση παλμών στο 1ο λεπτό μετά το «Τέλος» (Cole et al., N Engl J Med 1999· εδώ μόνο για σύγκριση με τον εαυτό σου):
         * παλμοί στο τέλος = μέσος όρος των 10″ ως το «Τέλος»· παλμοί στο 1′ = μέσος όρος από 55″ ως 65″ μετά. Και τα δύο
         * θέλουν τουλάχιστον 5 τιμές, αλλιώς null (καλύτερα τίποτα παρά λάθος αριθμός). Παράθυρα [από, έως): «10″» = 10
         * τιμές, όπως στο ⓘ (έλεγχος 9/11, 03-Χ4· πριν ήταν κλειστά και στις δύο άκρες, δηλαδή 11).
         */
        fun recovery(samples: List<IntArray>, endSec: Int): Pair<Int, Int>? {
            fun mean(from: Int, to: Int): Int? {
                var sum = 0
                var n = 0
                for (s in samples) if (s[0] >= from && s[0] < to) {
                    sum += s[1]
                    n++
                }
                return if (n < 5) null else Math.round(sum.toDouble() / n).toInt()
            }
            val end = mean(endSec - 10, endSec) ?: return null
            val oneMin = mean(endSec + 55, endSec + 65) ?: return null
            return end to oneMin
        }

        /** Ως τόσες τιμές σε ένα αποτέλεσμα (≈ 90′ ανά 1″): χωράνε άνετα στο όριο του Data Layer (100 KB). */
        const val MAX_SAMPLES = 5400

        /**
         * Πάνω από [MAX_SAMPLES] (πολύ μεγάλη άσκηση): ανά δύο διαδοχικές τιμές μία, ο μέσος τους, στον χρόνο της
         * πρώτης. Κανένα κενό και κανένα κομμάτι της άσκησης δεν χάνεται· χάνεται μόνο λεπτομέρεια.
         */
        fun fit(src: List<IntArray>): List<IntArray> {
            var cur = src
            while (cur.size > MAX_SAMPLES) {
                val out = ArrayList<IntArray>((cur.size + 1) / 2)
                var i = 0
                while (i < cur.size) {
                    val a = cur[i]
                    val b = if (i + 1 < cur.size) cur[i + 1] else null
                    out.add(if (b == null) a else intArrayOf(a[0], Math.round((a[1] + b[1]) / 2.0).toInt()))
                    i += 2
                }
                cur = out
            }
            return cur
        }
    }
}

/**
 * Χρόνος ανά km (έλεγχος 9/11, V-A-19): η απόσταση έρχεται σε πακέτα (με σβηστή οθόνη και ανά 150″). Το km γράφεται τη
 * στιγμή που ΠΕΡΑΣΤΗΚΕ, με γραμμική παρεμβολή ανάμεσα σε δύο τιμές απόστασης, με τους χρόνους των ίδιων των τιμών
 * (όχι την ώρα που έφτασε το πακέτο). [splits]: [ενεργός χρόνος (″), ώρα (ms)] κάθε ολόκληρου km.
 */
class SplitTracker(startWall: Long) {
    val splits = mutableListOf<LongArray>()
    private var pm = 0.0
    private var pt = startWall
    private var pa = 0.0

    /** Νέα συνολική απόσταση [totalM] τη στιγμή [atWall] (ms), με ενεργό χρόνο [activeSecAt] (″) εκείνη τη στιγμή. */
    fun update(totalM: Double, atWall: Long, activeSecAt: Double) {
        if (totalM.isNaN() || totalM.isInfinite() || totalM < pm) return
        val t1 = maxOf(atWall, pt)
        val a1 = maxOf(activeSecAt, pa)
        while (totalM >= (splits.size + 1) * 1000.0) {
            val target = (splits.size + 1) * 1000.0
            val f = if (totalM > pm) ((target - pm) / (totalM - pm)).coerceIn(0.0, 1.0) else 1.0
            splits.add(longArrayOf(Math.round(pa + f * (a1 - pa)), Math.round(pt + f * (t1 - pt))))
        }
        pm = totalM
        pt = t1
        pa = a1
    }

    fun toState(): JSONObject {
        val a = JSONArray()
        for (k in splits) a.put(JSONArray().put(k[0]).put(k[1]))
        return JSONObject().put("m", pm).put("t", pt).put("a", pa).put("k", a)
    }

    companion object {
        fun fromState(o: JSONObject, startWall: Long): SplitTracker {
            val s = SplitTracker(startWall)
            s.pm = o.optDouble("m", 0.0).takeIf { it.isFinite() } ?: 0.0
            s.pt = o.optLong("t", startWall)
            s.pa = o.optDouble("a", 0.0).takeIf { it.isFinite() } ?: 0.0
            o.optJSONArray("k")?.let { a -> for (i in 0 until a.length()) a.optJSONArray(i)?.let { s.splits.add(longArrayOf(it.getLong(0), it.getLong(1))) } }
            return s
        }
    }
}

/**
 * Ενεργός χρόνος (″) τη στιγμή [now] από το σημείο ελέγχου του Health Services: [cpActiveMs] ενεργός χρόνος τη στιγμή
 * [cpWall]· αν τρέχει, + ό,τι πέρασε από τότε (έλεγχος 9/11, W3-12: όχι μόνο όταν έρχεται ενημέρωση). Χωρίς σημείο
 * ελέγχου ([cpWall] = 0): [fallbackSec].
 */
fun activeSecAt(cpActiveMs: Long, cpWall: Long, running: Boolean, now: Long, fallbackSec: Long): Long {
    if (cpWall <= 0L) return fallbackSec
    val ms = cpActiveMs + if (running) maxOf(0L, now - cpWall) else 0L
    return maxOf(0L, ms / 1000)
}

/**
 * Ενεργός χρόνος (″) τη στιγμή [t] (π.χ. ο χρόνος μιας τιμής απόστασης, V-A-19), από το σημείο ελέγχου: αν τρέχει από
 * το [cpWall], + ό,τι πέρασε· αν είναι σε παύση από το [cpWall], − ό,τι ήταν πριν. Ποτέ αρνητικός.
 */
fun activeAtWall(cpActiveMs: Long, cpWall: Long, running: Boolean, t: Long, fallbackSec: Long): Double {
    if (cpWall <= 0L) return fallbackSec.toDouble()
    val ms = if (running) cpActiveMs + maxOf(0L, t - cpWall) else cpActiveMs - maxOf(0L, cpWall - t)
    return maxOf(0L, ms) / 1000.0
}

/**
 * Το «μηδέν» του χρονομέτρου της πρόσοψης (Ongoing Activity): θέλει χρόνο από την εκκίνηση της συσκευής
 * (elapsedRealtime), όχι ώρα τοίχου (έλεγχος 9/11, W3-04). [elapsedMs]: πόσος χρόνος έχει ήδη μετρηθεί.
 */
fun stopwatchZero(nowElapsed: Long, elapsedMs: Long): Long = nowElapsed - maxOf(0L, elapsedMs)

/** Πεπερασμένος αριθμός για JSON (το JSONObject δεν δέχεται NaN/άπειρο· DP-05). */
fun finite(v: Double): Double = if (v.isFinite()) v else 0.0

/**
 * Τι γίνεται με άσκηση που έμεινε μισή (η εφαρμογή έκλεισε απότομα, έλεγχος 9/11, V-A-03):
 * - [Action.ATTACH]: το Health Services την κρατά ακόμα για εμάς (ως 5′ χωρίς ακροατή): συνεχίζει από εκεί που ήταν.
 * - [Action.RESUME]: προπόνηση με βάρη στο ρολόι, πρόσφατη: συνεχίζει (με νέα μέτρηση παλμών)· τα σετ δεν χάνονται.
 * - [Action.FINALIZE]: γράφεται ως «μερική» με ό,τι είχε σωθεί και στέλνεται στο κινητό. Ένα αποτέλεσμα, με το ίδιο id.
 */
object Recovery {
    enum class Action { ATTACH, RESUME, FINALIZE }

    /** Πόσο πρόσφατη πρέπει να είναι μια προπόνηση με βάρη για να συνεχίσει (αλλιώς γράφεται ως μερική). */
    const val RESUME_MS = 15 * 60_000L

    fun decide(owned: Boolean, kind: String?, phone: Boolean, hasLocal: Boolean, savedAt: Long, now: Long): Action = when {
        owned -> Action.ATTACH
        kind == "strength" && !phone && hasLocal && now - savedAt in 0..RESUME_MS -> Action.RESUME
        else -> Action.FINALIZE
    }
}

/**
 * Ειδοποίηση ορίου παλμών, με βάση τον χρόνο κάθε τιμής (όχι πόσες τιμές ήρθαν μαζί):
 * ανάβει όταν οι παλμοί μένουν στο όριο ή πάνω τα 4 από τα τελευταία 5″ ([holdMs]), ξαναδονείται κάθε [repeatMs] (30″)
 * όσο μένουν πάνω, σβήνει κάτω από όριο − 5. Έλεγχος 8/11: πριν μετρούσε «2 μηνύματα», που με τα πακέτα των παλμών
 * μπορούσε να σημαίνει και 2–3 λεπτά καθυστέρηση.
 *
 * Έλεγχος γ2 (W2-02): κάθε τιμή ισχύει ώσπου να έρθει η επόμενη (το ρολόι μπορεί να στέλνει μόνο όταν αλλάζει), και μία
 * στιγμιαία τιμή κάτω από το όριο δεν μηδενίζει πια τη μέτρηση (πριν: 133, 133, 133, 133, 129… με όριο 130 = καμία δόνηση).
 */
class HrAlarm(limit: Int?, private val holdMs: Long = 5_000, private val repeatMs: Long = 30_000) {
    /** Αλλαγή ορίου στη μέση της άσκησης (W2-16): η κόκκινη οθόνη κρίνεται ξανά από την αρχή με το νέο όριο. */
    var limit: Int? = limit
        set(v) {
            if (v == field) return
            field = v
            on = false
            lastBuzz = 0
        }
    var on = false
        private set

    /** Αυξάνει κάθε φορά που ανάβει (νέο «επεισόδιο»): η σίγαση 60″ ισχύει μόνο για το ίδιο (W2-16). */
    var episode = 0
        private set

    /** Η τελευταία τιμή που ήρθε (για την καθυστερημένη ειδοποίηση, W2-17). */
    var lastBpm = 0
        private set
    private var lastBuzz = 0L
    private var lastAt = Long.MIN_VALUE

    /** Οι τιμές των τελευταίων [holdMs] (και μία πριν), [χρόνος, παλμοί]. */
    private val window = ArrayDeque<LongArray>()

    /**
     * true όταν πρέπει να δονηθεί (τη στιγμή που ανάβει και ανά 30″ όσο μένει πάνω). [at]: χρόνος της τιμής (ms).
     * Τιμές παλαιότερες από την τελευταία αγνοούνται: έτσι ακούει και τις δύο πηγές (Health Services και αισθητήρα)
     * χωρίς να ανακατεύονται οι χρόνοι, και αν σταματήσει η μία, συνεχίζει η άλλη (έλεγχος #2, W2-04).
     */
    fun feed(bpm: Int, at: Long): Boolean {
        if (at < lastAt) return false
        lastAt = at
        lastBpm = bpm
        window.addLast(longArrayOf(at, bpm.toLong()))
        // Κρατά μία τιμή πριν από το παράθυρο (ισχύει ως την επόμενη).
        while (window.size > 2 && window[1][0] <= at - holdMs) window.removeFirst()
        return step(bpm, at)
    }

    /**
     * Καμία νέα τιμή, αλλά η τελευταία ([bpm], ακόμα φρέσκια) ισχύει και τώρα: ο αισθητήρας στέλνει μόνο αλλαγές, οπότε
     * σταθεροί παλμοί πάνω από το όριο δεν θα έφερναν ποτέ δόνηση (έλεγχος #2, W2-02).
     */
    fun steady(bpm: Int, now: Long): Boolean = if (now < lastAt || window.isEmpty()) false else step(bpm, now)

    /** Πόση ώρα από τα τελευταία [holdMs] ως το [at] οι παλμοί ήταν στο όριο [l] ή πάνω (κάθε τιμή ισχύει ως την επόμενη). */
    private fun overMs(l: Int, at: Long): Long {
        val from = at - holdMs
        if (window.isEmpty() || window.first()[0] > from) return 0 // δεν έχουμε ακόμα 5″
        var sum = 0L
        for (k in window.indices) {
            val a = maxOf(window[k][0], from)
            val b = if (k + 1 < window.size) minOf(window[k + 1][0], at) else at
            if (b > a && window[k][1] >= l) sum += b - a
        }
        return sum
    }

    private fun step(bpm: Int, at: Long): Boolean {
        val l = limit
        if (l == null) {
            on = false
            return false
        }
        if (bpm >= l) {
            if (!on && overMs(l, at) >= holdMs * 4 / 5) {
                on = true
                episode++
                lastBuzz = at
                return true
            }
            if (on && at - lastBuzz >= repeatMs) {
                lastBuzz = at
                return true
            }
        } else if (on && bpm < l - 5) {
            on = false
        }
        return false
    }

    fun reset() {
        on = false
        lastBuzz = 0
        lastAt = Long.MIN_VALUE
        lastBpm = 0
        window.clear()
    }
}

/**
 * Ειδοποίηση ορίου που ήρθε με καθυστέρηση (πακέτο παλμών, έλεγχος γ2, W2-17): [ageMs] πόσο παλιά είναι η τιμή που την
 * άναψε, [stillOver] αν η τελευταία τιμή είναι ακόμα στο όριο ή πάνω. Αν οι παλμοί έπεσαν ήδη και η τιμή είναι πάνω από
 * 30″ παλιά, καμία δόνηση (θα έλεγε «τώρα» κάτι που πέρασε)· γράφεται μόνο στο logcat.
 */
fun lateAlarmBuzz(ageMs: Long, stillOver: Boolean): Boolean = stillOver || ageMs <= 30_000

/**
 * Τι λέει η ειδοποίηση ορίου (έλεγχος γ2, L7/W2-16): στο περπάτημα «Κόψε ρυθμό»· στο λεπτό αποκατάστασης (κάθεσαι
 * ήδη) και στα βάρη «Ξεκουράσου», όπως το κινητό («Ξεκουράσου μέχρι να πέσουν»). Χωρίς «κάτω από 140»: η κόκκινη οθόνη
 * σβήνει λίγο πιο κάτω (όριο − 5), οπότε το «κάτω από το όριο» δεν ήταν ακριβές.
 */
fun alarmAdvice(walk: Boolean, recovery: Boolean): String = when {
    recovery -> "Ξεκουράσου."
    walk -> "Κόψε ρυθμό."
    else -> "Ξεκουράσου μέχρι να πέσουν οι παλμοί."
}

/**
 * Ρολόι χωρίς παλμούς ανά 5″ και χωρίς αισθητήρα αφύπνισης, με όριο (W3-10· έλεγχος του γ2, S1): χωρίς αριθμό που
 * δεν έχει μετρηθεί.
 */
const val SLOW_ALARM_TEXT = "Με σβηστή οθόνη η δόνηση του ορίου μπορεί να αργήσει λίγα λεπτά σε αυτό το ρολόι."

/** Το μήνυμα ασφάλειας πρώτο· ένα άλλο μήνυμα (π.χ. για το GPS) ακολουθεί, δεν το κρύβει (S1). */
fun withSafety(safety: String, other: String?): String =
    if (other.isNullOrEmpty() || other.contains(safety)) safety else "$safety $other"


/** Η μεγάλη λέξη της κόκκινης οθόνης. */
fun alarmHeadline(walk: Boolean, recovery: Boolean): String = if (walk && !recovery) "Κόψε ρυθμό" else "Ξεκουράσου"

/** «» για τωρινή τιμή, αλλιώς « (πριν 40 δευτερόλεπτα)» / « (πριν 2 λεπτά)» για την ειδοποίηση (W2-17). */
fun ageText(ageMs: Long): String = if (ageMs < 20_000) "" else " (πριν ${agoText(ageMs)})"

/**
 * Πόσο παλιά είναι μια τιμή, σε ολόκληρες λέξεις (έλεγχος 13/11, round 7, R7-U3-08· όπως το κινητό, U5-06): «40
 * δευτερόλεπτα», «1 λεπτό», «3 λεπτά». Πριν «40″» / «3′».
 */
fun agoText(ageMs: Long): String {
    val ms = maxOf(0L, ageMs)
    return if (ms < 60_000) {
        val s = ms / 1000
        if (s == 1L) "1 δευτερόλεπτο" else "$s δευτερόλεπτα"
    } else {
        val m = ms / 60_000
        if (m == 1L) "1 λεπτό" else "$m λεπτά"
    }
}

/**
 * Το μήνυμα στην αρχή του περπατήματος για ό,τι ΔΕΝ μετριέται (έλεγχος γ2, RT-18): [gpsAsked] ζητήθηκε GPS, [gps]/
 * [distance]/[hr]: τι δέχτηκε τελικά το Health Services. null = όλα όπως ζητήθηκαν.
 */
fun walkStartNotice(gpsAsked: Boolean, gps: Boolean, distance: Boolean, hr: Boolean): String? = when {
    !hr -> "Το ρολόι δεν δίνει παλμούς σε αυτή την άσκηση."
    !distance -> "Μόνο παλμοί σε αυτό το περπάτημα."
    gpsAsked && !gps -> "Χωρίς GPS: η απόσταση από τα βήματα."
    else -> null
}

/**
 * Ενεργός χρόνος περπατήματος (″) όταν το Health Services δεν έδωσε κανένα σημείο ελέγχου (έλεγχος γ2, W2-11): ώρα από
 * την αρχή ως το τέλος, χωρίς τις παύσεις ([pauses]: [αρχή, τέλος] ms, τέλος 0 = κρατά ακόμα). Πριν: 0 λεπτά.
 */
fun wallActiveSec(start: Long, end: Long, pauses: List<LongArray>): Long {
    if (start <= 0 || end <= start) return 0
    var ms = end - start
    for (p in pauses) {
        val a = p[0].coerceIn(start, end)
        val b = (if (p[1] == 0L) end else p[1]).coerceIn(start, end)
        if (b > a) ms -= b - a
    }
    return maxOf(0L, ms) / 1000
}

/**
 * «Ζωντανά» του περπατήματος προς το κινητό (έλεγχος γ2, W3-15): ανά 10″ μόνο όσο το κινητό λέει ότι κοιτάζει
 * ([watchingUntil], από το μήνυμα «/ygeia/watching»). Κινητό που δεν έχει στείλει ποτέ τέτοιο μήνυμα ([phoneKnowsWatching]
 * = false: παλιά έκδοση) τα παίρνει όπως πριν, ανά 10″. Το πρώτο στέλνεται πάντα (το κινητό μαθαίνει ότι τρέχει περπάτημα).
 */
fun liveDue(now: Long, lastSent: Long, phoneKnowsWatching: Boolean, watchingUntil: Long): Boolean {
    if (lastSent > 0 && now - lastSent < 10_000) return false
    return lastSent <= 0 || !phoneKnowsWatching || now < watchingUntil
}

/**
 * «Δεν μετριούνται παλμοί» όσο ισχύει όριο γιατρού (έλεγχος 9/11, V-A-04). Μία δόνηση όταν:
 * - δεν ήρθε ΚΑΝΕΝΑΣ παλμός [firstMs] (30″) μετά την αρχή (π.χ. λείπει η άδεια, το Health Services αρνήθηκε την
 *   άσκηση, χαλαρό λουρί από την αρχή): [Silence.NEVER]·
 * - χάθηκαν για [lostMs] αφού είχαν έρθει: [Silence.LOST] (όπως πριν: 15″ στο περπάτημα, 45″ στα βάρη).
 * Ξανά μόνο αφού ξαναέρθουν παλμοί και χαθούν πάλι (όχι κάθε δευτερόλεπτο). Σε παύση δεν δονείται.
 * Καθαρή λογική, χωρίς Android, για να ελέγχεται.
 */
class HrSilence(private val firstMs: Long = FIRST_MS) {
    enum class Silence { NEVER, LOST }

    companion object {
        /** Αναμονή για τον πρώτο παλμό (ίδια με του κινητού, `hrWaitSeconds`). */
        const val FIRST_MS = 30_000L
    }

    /** Τι λείπει τώρα (μετά τον χρόνο αναμονής), ή null. */
    var state: Silence? = null
        private set
    private var buzzed = false

    /**
     * true = δόνηση τώρα. [lastAt]: πότε ήρθε ο τελευταίος παλμός (0 = κανένας), [live]: παλμοί που ισχύουν τώρα.
     */
    fun check(now: Long, startedAt: Long, lastAt: Long, live: Boolean, hasLimit: Boolean, paused: Boolean, lostMs: Long): Boolean {
        if (live) {
            state = null
            buzzed = false
            return false
        }
        state = when {
            lastAt <= 0L -> if (startedAt > 0L && now - startedAt >= firstMs) Silence.NEVER else null
            now - lastAt >= lostMs -> Silence.LOST
            else -> null
        }
        if (state == null || !hasLimit || paused || buzzed) return false
        buzzed = true
        return true
    }

    fun reset() {
        state = null
        buzzed = false
    }
}

/** Χρόνος τιμής αισθητήρα (ns από την εκκίνηση) → ώρα (ms), ποτέ στο μέλλον. */
fun sensorWallTime(eventNanos: Long, nowWallMs: Long, nowElapsedNanos: Long): Long =
    (nowWallMs - (nowElapsedNanos - eventNanos) / 1_000_000).coerceAtMost(nowWallMs)

/**
 * Πόσο συχνά φτάνουν πραγματικά οι παλμοί στην εφαρμογή (το μεγαλύτερο κενό ανάμεσα σε δύο παραδόσεις).
 * Για τον έλεγχο στη συσκευή: δείχνει αν η ειδοποίηση ορίου μπορεί να αργήσει (8/11).
 *
 * Έλεγχος γ2 (W2-08): μετρά και από την αρχή της άσκησης ως την πρώτη παράδοση ([start]) και ως το τέλος χωρίς όριο
 * 60″ (πριν: ένα λουρί χαλαρό τα τελευταία 30′ έβγαζε «60″»), και πόσες παραδόσεις έγιναν ([deliveries]): όλο το
 * περπάτημα σε ένα πακέτο δεν είναι «κάθε λίγα δευτερόλεπτα».
 */
class GapMeter {
    private var last = 0L
    var maxGapMs = 0L
        private set
    var deliveries = 0
        private set

    /** Η αρχή της άσκησης: το κενό ως την πρώτη παράδοση μετράει κι αυτό. */
    fun start(at: Long) {
        if (last == 0L && deliveries == 0) last = at
    }

    fun mark(at: Long) {
        if (last > 0 && at > last) maxGapMs = maxOf(maxGapMs, at - last)
        last = maxOf(last, at)
        deliveries++
    }

    /** Και ο χρόνος ως το τέλος (αν σταμάτησαν να έρχονται). */
    fun close(at: Long) {
        if (last > 0 && at > last) maxGapMs = maxOf(maxGapMs, at - last)
    }

    val maxGapSec: Int get() = ((maxGapMs + 500) / 1000).toInt()
}

/**
 * Ποιότητα μιας τιμής παλμών, όπως τη δηλώνει το ίδιο το ρολόι (τελικός έλεγχος, Συμβούλιο 1, Σ1). Το Health Services
 * δίνει με κάθε τιμή την κατάσταση του αισθητήρα (HeartRateAccuracy.SensorStatus): «χωρίς επαφή», «αναξιόπιστη»,
 * «χαμηλή / μέτρια / υψηλή ακρίβεια». Ως την #99 η εφαρμογή την αγνοούσε και κρατούσε κάθε τιμή 26–249.
 * - [BAD] (χωρίς επαφή ή αναξιόπιστη): η τιμή ΔΕΝ μπαίνει πουθενά (μέσος, υψηλότερος, ζώνη, όριο, ένδειξη)· αν λείψουν
 *   οι καλές τιμές, η οθόνη λέει «δεν μετριούνται», όπως όταν δεν έρχεται τίποτα.
 * - [LOW] (χαμηλή ακρίβεια): μένει όπως πριν, αλλά ΜΕΤΡΙΕΤΑΙ. Δεν πετιέται ακόμα: δεν έχει μετρηθεί στο Galaxy Watch
 *   Ultra 2 πόσο συχνά τη δηλώνει το ρολόι στα βάρη· αν πεταχτεί στα τυφλά, μπορεί να μείνει η προπόνηση χωρίς παλμούς.
 * - [OK]: μέτρια ή υψηλή ακρίβεια, ή ρολόι που δεν δηλώνει τίποτα (όπως πριν).
 */
enum class HrQuality { OK, LOW, BAD }

/** Από την κατάσταση του αισθητήρα στην απόφαση. Καθαρή συνάρτηση (χωρίς Android), για να ελέγχεται σε JVM. */
fun hrQualityOf(noContact: Boolean, unreliable: Boolean, lowAccuracy: Boolean): HrQuality = when {
    noContact || unreliable -> HrQuality.BAD
    lowAccuracy -> HrQuality.LOW
    else -> HrQuality.OK
}

/**
 * Μια τιμή παλμών από το Health Services που χρησιμοποιείται: όχι «χωρίς επαφή»/«αναξιόπιστη» ([HrQuality.BAD]) και μέσα
 * στο 26–249. Έλεγχος 13/11, round 7 (R7-A7-2): μόνο μια παράδοση με τουλάχιστον μία τέτοια τιμή μετρά ως «ήρθαν παλμοί»
 * για το μεγαλύτερο κενό ([GapMeter]). Πριν μετρούσε κάθε παράδοση, και 2 λεπτά χωρίς επαφή (σημεία ανά 5″ χωρίς τιμή)
 * έβγαιναν «οι παλμοί έφταναν κάθε λίγα δευτερόλεπτα».
 */
fun hrValueUsable(q: HrQuality, bpm: Int): Boolean = q != HrQuality.BAD && bpm in 26..249

/**
 * Πόσες τιμές παλμών ήρθαν με κάθε ποιότητα σε μια άσκηση. Πηγαίνει στο κινητό μέσα στο υπάρχον κείμενο «diag»
 * («5s=1 wake=1 q=5400/120/15»: καλές/χαμηλής ακρίβειας/άχρηστες), για να φανεί στη δοκιμή στη συσκευή τι δηλώνει
 * πραγματικά το ρολόι. Κανένα νέο πεδίο: το παλιό κινητό το διαβάζει όπως πριν.
 */
/**
 * Γ3 (13/11): η ερώτηση του ρολογιού πριν ξεκινήσει άσκηση ενώ τρέχει άσκηση άλλης εφαρμογής. Κείμενα εγκεκριμένα 12/11.
 * [ask]: ρωτά μόνο όταν το Health Services είπε καθαρά «άλλη εφαρμογή»· αν δεν απάντησε (null), ξεκινά όπως πριν, ώστε
 * μια αργή απάντηση να μη μπλοκάρει ποτέ την προπόνηση.
 */
object OtherAppAsk {
    const val TEXT = "Τρέχει άσκηση σε άλλη εφαρμογή. Αν ξεκινήσεις εδώ, εκείνη σταματά."
    const val YES = "Ξεκίνα εδώ"
    const val NO = "Άκυρο"

    fun ask(otherAppInProgress: Boolean?): Boolean = otherAppInProgress == true
}

class HrQualityCount {
    var ok = 0
        private set
    var low = 0
        private set
    var bad = 0
        private set

    val total: Int get() = ok + low + bad

    fun add(q: HrQuality) {
        when (q) {
            HrQuality.OK -> ok++
            HrQuality.LOW -> low++
            HrQuality.BAD -> bad++
        }
    }

    /** «q=5400/120/15», ή κενό αν δεν ήρθε καμία τιμή. */
    fun text(): String = if (total == 0) "" else "q=$ok/$low/$bad"

    /** Το «diag» της άσκησης μαζί με την ποιότητα (ένα κενό ανάμεσα· ό,τι είναι άδειο παραλείπεται). */
    fun withDiag(diag: String): String = listOf(diag, text()).filter { it.isNotEmpty() }.joinToString(" ")
}

/** «1:04», «24:31», «1:02:05». */
fun clock(sec: Long): String {
    val s = if (sec < 0) 0 else sec
    val h = s / 3600
    val m = (s % 3600) / 60
    val r = s % 60
    // Locale.ROOT (τελικός έλεγχος, Συμβούλιο 4, W-5): πάντα ψηφία 0–9, σε όποια γλώσσα κι αν είναι το ρολόι.
    return if (h > 0) "%d:%02d:%02d".format(java.util.Locale.ROOT, h, m, r) else "%d:%02d".format(java.util.Locale.ROOT, m, r)
}

/** «2,18» km. */
fun km(meters: Double): String = "%.2f".format(java.util.Locale.ROOT, meters / 1000.0).replace('.', ',')

/** Ρυθμός ανά km, ίδιος με το κινητό (σχέδια 9/11): «11:15 /km». Στρογγυλεύει πριν χωρίσει, άρα ποτέ «10:60». */
fun pace(meters: Double, sec: Long): String {
    if (meters < 50 || sec <= 0) return "—"
    val p = Math.round(sec / (meters / 1000.0))
    return "%d:%02d /km".format(java.util.Locale.ROOT, p / 60, p % 60)
}

/** Πόσο ισχύει ένα «κοιτάζω» του κινητού (ms), από το μήνυμα: 0–120″ (ό,τι άλλο → 0). */
fun watchingTtl(text: String?): Long = try {
    if (text == null) 0L else JSONObject(text).optLong("ttl", 0L).coerceIn(0L, 120_000L)
} catch (_: Exception) {
    0L
}

/** Πότε σβήνει το ρολόι τα δεδομένα του μετά από «Διαγραφή όλων» στο κινητό (καθαρό, με δοκιμές). */
object WipeRule {
    /**
     * [at]: πότε ζητήθηκε· [done]: η τελευταία διαγραφή που έγινε εδώ· [running]: τρέχει άσκηση, ή υπάρχει άσκηση που
     * έμεινε μισή από απότομο κλείσιμο (στιγμιότυπο run.json, έλεγχος του fix-accuracy, S1)· τότε περιμένει ώσπου να
     * τελειώσει ή να σωθεί.
     */
    fun shouldWipe(at: Long, done: Long, running: Boolean): Boolean = at > 0 && at > done && !running

    /** Η διαγραφή [at] έχει ήδη γίνει εδώ αλλά το κινητό δεν έχει πάρει την απάντηση ([acked] = η τελευταία που στάλθηκε). */
    fun shouldAck(at: Long, done: Long, acked: Long): Boolean = at > 0 && at <= done && acked < at

    /**
     * Πότε ξεκίνησε η άσκηση ενός αποτελέσματος («start», ή από το id «walk<ms>» / «w<ms>» / «hr<sid>-<ms>»), αλλιώς
     * [putAt]. Ίδιος κανόνας με το κινητό (DataRules.resultStart).
     */
    fun resultStart(json: String, putAt: Long): Long {
        Regex("\"start\"\\s*:\\s*(\\d{9,15})").find(json)?.let { return it.groupValues[1].toLong() }
        val id = Regex("\"id\"\\s*:\\s*\"([^\"]{1,80})\"").find(json)?.groupValues?.get(1)
        if (id != null) {
            Regex("^(?:walk|w)(\\d{9,15})$").find(id)?.let { return it.groupValues[1].toLong() }
            Regex("^hr.*-(\\d{9,15})$").find(id)?.let { return it.groupValues[1].toLong() }
        }
        return putAt
    }

    /**
     * Έλεγχος του fix-accuracy (N1): η διαγραφή [at] σβήνει ΜΟΝΟ ό,τι έγινε πριν από αυτήν. Ένα περπάτημα που έγινε στο ρολόι
     * μετά τη διαγραφή στο κινητό (πριν φτάσει εδώ το «σβήσε») μένει και στέλνεται.
     */
    fun keepAfterWipe(json: String, putAt: Long, at: Long): Boolean = at <= 0L || resultStart(json, putAt) >= at

    /** Πρόγραμμα/προπόνηση του κινητού γραμμένα πριν από τη διαγραφή που έγινε εδώ ([done]): δεν ξαναμπαίνουν (N3). */
    fun staleFromPhone(t: Long, done: Long): Boolean = done > 0L && t < done

    /** Η απάντηση «σβήστηκε» προς το κινητό ([Paths.WIPED]). */
    fun ackJson(at: Long): String = org.json.JSONObject().put("v", 1).put("at", at).toString()

    fun parseAt(text: String?): Long = try {
        if (text == null) 0L else org.json.JSONObject(text).optLong("at", 0L)
    } catch (_: Exception) {
        0L
    }
}

/**
 * Δόνηση ζώνης περπατήματος (σχέδια 12/11). Καθοδήγηση, όχι ασφάλεια: απαλή δόνηση, όχι ξυπνητήρι, και ποτέ όταν μιλά το
 * όριο του γιατρού ([HrAlarm], το ελέγχει η υπηρεσία).
 * - Πάνω: όταν οι παλμοί μείνουν πάνω από τη ζώνη [holdMs] (20″, όχι μια ανηφόρα). Ξανά κάθε [repeatMs] (2′) όσο μένουν
 *   πάνω· ξαναοπλίζεται όταν πέσουν [REARM] παλμούς κάτω από το πάνω όριο.
 * - Κάτω (αν είναι ανοιχτή): όταν μείνουν κάτω από τη ζώνη [lowHoldMs] (1′), ξανά κάθε [lowRepeatMs] (5′).
 * - Τίποτα τα πρώτα [warmupMs] (5′): οι παλμοί ακόμα ανεβαίνουν.
 * Χρόνοι σε ms από την εκκίνηση (elapsedRealtime), όπως στο [HrAlarm]. Κάθε τιμή ισχύει ως την επόμενη.
 */
class ZoneAlarm(
    private val warmupMs: Long = 5 * 60_000L,
    private val holdMs: Long = 20_000L,
    private val repeatMs: Long = 120_000L,
    private val lowHoldMs: Long = 60_000L,
    private val lowRepeatMs: Long = 300_000L,
) {
    enum class Buzz { NONE, UP, DOWN }

    /** Αλλαγή ζώνης στη μέση (νέο πρόγραμμα από το κινητό): η κρίση ξεκινά από την αρχή, όχι η προθέρμανση. */
    var zone: WalkZone? = null
        set(v) {
            if (v == field) return
            field = v
            clear()
        }

    /** Ανοιχτή τουλάχιστον μία δόνηση. */
    val active: Boolean get() = zone?.let { it.up || it.down } == true

    /** Πόσες δονήσεις έγιναν (για τον έλεγχο στη συσκευή). */
    var ups = 0
        private set
    var downs = 0
        private set

    private var startEl = 0L
    private var lastAt = Long.MIN_VALUE
    private var aboveSince = -1L
    private var belowSince = -1L
    private var upOn = false
    private var downOn = false
    private var lastUp = 0L
    private var lastDown = 0L

    fun start(z: WalkZone?, startEl: Long) {
        zone = z
        this.startEl = startEl
        clear()
        ups = 0
        downs = 0
    }

    fun stop() {
        zone = null
        clear()
    }

    /** Παύση ή λεπτό αποκατάστασης: οι 20″/1′ μετρούν ξανά από την αρχή μετά. */
    fun hold() {
        aboveSince = -1
        belowSince = -1
    }

    /** Νέα τιμή [bpm] τη στιγμή [at]. Παλιότερες από την τελευταία αγνοούνται (δύο πηγές: Health Services, αισθητήρας). */
    fun feed(bpm: Int, at: Long): Buzz {
        if (at < lastAt) return Buzz.NONE
        lastAt = at
        return step(bpm, at)
    }

    /** Καμία νέα τιμή, αλλά η τελευταία ισχύει ακόμα [now] (ο αισθητήρας στέλνει μόνο αλλαγές). */
    fun steady(bpm: Int, now: Long): Buzz = if (lastAt == Long.MIN_VALUE || now < lastAt) Buzz.NONE else step(bpm, now)

    private fun step(bpm: Int, at: Long): Buzz {
        val z = zone ?: return Buzz.NONE
        if (bpm <= 0) return Buzz.NONE
        if (bpm > z.hi) {
            if (aboveSince < 0) aboveSince = at
        } else {
            aboveSince = -1
            if (bpm <= z.hi - REARM) upOn = false
        }
        if (bpm < z.lo) {
            if (belowSince < 0) belowSince = at
        } else {
            belowSince = -1
            if (bpm >= z.lo + REARM) downOn = false
        }
        if (at - startEl < warmupMs) return Buzz.NONE
        // Τελικός έλεγχος (Συμβούλιο 1, μ1): και η ΕΠΑΝΑΛΗΨΗ θέλει [holdMs] συνεχώς έξω από τη ζώνη. Πριν: αν οι παλμοί
        // γύριζαν στη ζώνη χωρίς να «ξαναοπλίσουν» (π.χ. 128–130 με πάνω όριο 130) και 2′ μετά ερχόταν ΜΙΑ τιμή 131,
        // δονούσε αμέσως, ενώ η οθόνη υπόσχεται «όταν μείνεις πάνω 20″».
        if (z.up && aboveSince >= 0 && at - aboveSince >= holdMs) {
            if (!upOn) {
                upOn = true
                lastUp = at
                ups++
                return Buzz.UP
            }
            if (at - lastUp >= repeatMs) {
                lastUp = at
                ups++
                return Buzz.UP
            }
        }
        if (z.down && belowSince >= 0 && at - belowSince >= lowHoldMs) {
            if (!downOn) {
                downOn = true
                lastDown = at
                downs++
                return Buzz.DOWN
            }
            if (at - lastDown >= lowRepeatMs) {
                lastDown = at
                downs++
                return Buzz.DOWN
            }
        }
        return Buzz.NONE
    }

    private fun clear() {
        lastAt = Long.MIN_VALUE
        aboveSince = -1
        belowSince = -1
        upOn = false
        downOn = false
        lastUp = 0
        lastDown = 0
    }

    companion object {
        const val REARM = 3
    }
}

// ------------------------------------------------------------------ έλεγχος 13/11 (round 1): αποφάσεις της υπηρεσίας
// Καθαρές συναρτήσεις (χωρίς Android), για να ελέγχονται σε JVM (S12-11). Η συμπεριφορά δεν άλλαξε· μεταφέρθηκε εδώ.

/** Δόνηση ζώνης μόνο για τιμή το πολύ τόσο παλιά (12/11): αλλιώς οι παλμοί έχουν ήδη αλλάξει. */
const val ZONE_LATE_MS = 30_000L

/**
 * Η ζώνη «κρατιέται» ([ZoneAlarm.hold]: οι 20″ / το 1′ μετρούν ξανά από την αρχή μετά): όχι περπάτημα, παύση, λεπτό
 * αποκατάστασης, ή μετά το «Τέλος».
 */
fun zoneOnHold(walk: Boolean, paused: Boolean, recovery: Boolean, stopping: Boolean): Boolean = !walk || paused || recovery || stopping

/**
 * Κρίνεται αυτή η τιμή για τη ζώνη (και μπορεί να φέρει δόνηση); Ποτέ όταν η ζώνη κρατιέται ([zoneOnHold])· ποτέ με όριο
 * γιατρού ([hasDoctorLimit]: τότε μιλά μόνο εκείνο, και η οθόνη δεν δείχνει ζώνη)· ποτέ για τιμή παλιότερη από
 * [ZONE_LATE_MS] ([ageMs], πακέτο παλμών με καθυστέρηση): ούτε δόνηση ούτε κρίση.
 */
fun zoneMaySpeak(walk: Boolean, paused: Boolean, recovery: Boolean, stopping: Boolean, hasDoctorLimit: Boolean, ageMs: Long): Boolean =
    !zoneOnHold(walk, paused, recovery, stopping) && !hasDoctorLimit && ageMs <= ZONE_LATE_MS

/**
 * Η ηλικία (ms) της τιμής που κρίνεται για τη ζώνη (S5, N2). Νέα τιμή: τώρα − ο χρόνος της. «Σταθεροί παλμοί» χωρίς νέα
 * τιμή ([steady]): μετρά η τελευταία πραγματική τιμή ([bpmEl]), εκτός αν ο αισθητήρας έχει επαφή και ίδια τιμή ως το
 * [steadyUntilEl] (τότε είναι τωρινή: 0).
 */
fun zoneValueAgeMs(steady: Boolean, steadyUntilEl: Long, bpmEl: Long, atEl: Long, nowEl: Long): Long =
    if (steady) (if (steadyUntilEl > nowEl) 0L else nowEl - bpmEl) else nowEl - atEl

/**
 * Μετά από πόση ώρα χωρίς τιμή λέμε «χάθηκαν παλμοί»: 15″ στο περπάτημα, 45″ στα βάρη (ο καρπός που λυγίζει κόβει συχνά
 * για λίγο· έλεγχος #2).
 */
fun lostAfterMs(walk: Boolean): Long = if (walk) 15_000L else 45_000L

/**
 * Πότε (elapsedRealtime) πρέπει να ξυπνήσει ο επεξεργαστής για τον έλεγχο «χάθηκαν παλμοί», αν δεν έρθει άλλη τιμή μετά
 * την [lastHrEl] (έλεγχος 13/11, S8-07): ένα δευτερόλεπτο μετά το όριο [lostMs]. Πριν, ο έλεγχος γινόταν μόνο στον βρόχο
 * του δευτερολέπτου, που με σβηστή οθόνη σταματά ακριβώς όταν δεν έρχονται παλμοί.
 */
fun silenceWakeAt(lastHrEl: Long, lostMs: Long): Long = lastHrEl + lostMs + 1_000L

/**
 * Δόνηση στο τέλος του λεπτού αποκατάστασης (έλεγχος 13/11, S8-01): το κινητό λέει «μένεις έτσι ώσπου να δονηθεί το
 * ρολόι». Όταν το λεπτό τελειώνει μόνο του ([now] ≥ [recoveryUntil])· όχι όταν το έκοψε ο χρήστης με «Παράλειψη»
 * ([skipped]), ούτε όταν δεν τρέχει λεπτό αποκατάστασης ([recoveryUntil] = 0).
 */
fun recoveryEndBuzz(recoveryUntil: Long, now: Long, skipped: Boolean): Boolean = recoveryUntil > 0L && now >= recoveryUntil && !skipped

/**
 * Δόνηση «τέλος διαλείμματος» τώρα; (έλεγχος 13/11, S8-04) Μία φορά ανά διάλειμμα ([buzzedFor] = το διάλειμμα που έχει
 * ήδη δονηθεί), και ποτέ μέσα σε περπάτημα ([walking]): το περπάτημα επιτρέπεται με ανοιχτή προπόνηση του κινητού, και το
 * διάλειμμα εκείνης δεν το αφορά.
 */
fun restBuzzDue(restEnd: Long, now: Long, buzzedFor: Long, walking: Boolean): Boolean =
    !walking && restEnd > 0L && now >= restEnd && buzzedFor != restEnd

/**
 * Στην αρχή της μέτρησης (S8-04): διάλειμμα που είχε ΗΔΗ λήξει πριν ξεκινήσει (η προπόνηση του κινητού κρατά το παλιό
 * «restEnd») μετρά ως «δονήθηκε ήδη». Πριν, το πρώτο δευτερόλεπτο έφερνε μια ψεύτικη δόνηση «τέλος διαλείμματος».
 * Επιστρέφει την τιμή για το «έχει δονηθεί για»· 0 = κανένα.
 */
fun restAlreadyOver(restEnd: Long?, now: Long): Long = if (restEnd != null && restEnd in 1..now) restEnd else 0L

/**
 * Το Android κόβει τη δόνηση ειδοποίησης (USAGE_NOTIFICATION, η δόνηση ζώνης) όταν το ρολόι είναι σε Εξοικονόμηση
 * ενέργειας ([powerSave]) ή σε Σίγαση ([ringerSilent]) (έλεγχος 13/11, S8-02· AOSP VibrationSettings: σε εξοικονόμηση
 * περνούν μόνο κλήση/ξυπνητήρι, σε σίγαση δεν περνά η δόνηση ειδοποίησης). true = η δόνηση ζώνης φτάνει στον καρπό.
 * Η δόνηση του ορίου γιατρού (USAGE_ALARM) δεν κόβεται από κανένα από τα δύο.
 */
fun zoneBuzzFelt(powerSave: Boolean, ringerSilent: Boolean, dnd: Boolean = false): Boolean = !powerSave && !ringerSilent && !dnd

/**
 * Η οθόνη του περπατήματος γράφει «χωρίς δόνηση» (S8-02): υπάρχει ζώνη με ανοιχτή δόνηση ([zoneActive]), δεν υπάρχει όριο
 * γιατρού (αλλιώς η ζώνη δεν μιλά έτσι κι αλλιώς), και το ρολόι θα έκοβε τη δόνηση ([zoneBuzzFelt]).
 *
 * Έλεγχος 13/11, round 7 (R7-A7-1): και σε «Μην ενοχλείτε» (ή Λειτουργία ύπνου, που το ανοίγει) — [dnd]. Στο AOSP
 * (ZenModeHelper.applyRestrictions) κάθε τρόπος «Μην ενοχλείτε» βάζει AppOps OP_VIBRATE = IGNORED για τη δόνηση
 * ειδοποίησης, και στο συνηθισμένο «προτεραιότητα» ο ήχος κουδουνιού ΔΕΝ γίνεται «Σίγαση»: πριν, η δόνηση κοβόταν
 * σιωπηλά και η οθόνη δεν το έλεγε. Η δόνηση ζώνης μένει δόνηση ειδοποίησης (απόφαση του χρήστη: απαλή, όχι ξυπνητήρι).
 */
fun zoneMutedNow(zoneActive: Boolean, hasDoctorLimit: Boolean, powerSave: Boolean, ringerSilent: Boolean, dnd: Boolean = false): Boolean =
    zoneActive && !hasDoctorLimit && !zoneBuzzFelt(powerSave, ringerSilent, dnd)

/** Η ετικέτα δίπλα στους παλμούς όσο η δόνηση ζώνης δεν φτάνει (S8-02). Κείμενο προς έγκριση από τον χρήστη. */
const val ZONE_MUTED_TAG = "χωρίς δόνηση"

/**
 * Το σύντομο μήνυμα με την αιτία, μία φορά όταν εμφανιστεί (S8-02)· null = η δόνηση φτάνει. Κείμενα προς έγκριση. Πρώτο το
 * «Μην ενοχλείτε» (R7-A7-1): στη «Μόνο ξυπνητήρια» / «Απόλυτη σιωπή» το Android βάζει ΚΑΙ τον ήχο σε σίγαση, άρα η αιτία
 * που μετρά είναι εκείνο.
 */
fun zoneMutedNotice(powerSave: Boolean, ringerSilent: Boolean, dnd: Boolean = false): String? = when {
    dnd -> "Μην ενοχλείτε: χωρίς δόνηση ζώνης"
    ringerSilent -> "Σίγαση: χωρίς δόνηση ζώνης"
    powerSave -> "Εξοικονόμηση: χωρίς δόνηση ζώνης"
    else -> null
}

/**
 * Από πότε (elapsedRealtime, ms) μετρά η «προθέρμανση» των 5′ της ζώνης μετά από απότομο κλείσιμο (έλεγχος 13/11,
 * round 7, R7-A7-3): από την αρχή του περπατήματος ([startedAtWall], ώρα), όχι από τη συνέχεια. Πριν ξαναμετρούσε 5′
 * χωρίς δόνηση στη μέση του περπατήματος. Αν η ώρα του ρολογιού πήγε πίσω (αρχή «στο μέλλον»), από τη συνέχεια.
 */
fun zoneWarmupStartEl(nowEl: Long, nowWall: Long, startedAtWall: Long): Long =
    nowEl - (nowWall - startedAtWall).coerceAtLeast(0L)

/**
 * Το «Τέλος» μπορεί να πει «Αποθηκεύτηκε» (έλεγχος 13/11, round 7, R7-A8-5): μόνο αν το αποτέλεσμα γράφτηκε στην αναμονή
 * του ρολογιού ([saved]) ή μπήκε στο Data Layer ([put]). Με γεμάτο χώρο και τα δύο αποτυγχάνουν: τότε όχι.
 */
fun endScreenSaved(saved: Boolean, put: Boolean): Boolean = saved || put

/**
 * «Περιμένω παλμούς» αντί για «δεν μετριούνται» (έλεγχος 13/11, round 7, R7-U3-05): στα πρώτα [HrSilence.FIRST_MS] (30″)
 * μιας άσκησης ([startedAt], ώρα), όσο δεν έχει έρθει κανένας παλμός σε αυτήν ([bpmAt] πριν από την αρχή, 0 = κανένας) και
 * πριν κριθεί «δεν έρχονται» ([silent]). Ίδια φράση με το κινητό («Περιμένω παλμούς από το ρολόι…»).
 */
fun hrWaiting(silent: Boolean, bpmAt: Long, startedAt: Long, now: Long): Boolean =
    !silent && startedAt > 0 && bpmAt < startedAt && now - startedAt in 0L until HrSilence.FIRST_MS

/**
 * Άσκηση που ξεχάστηκε ανοιχτή στο ρολόι (έλεγχος 13/11, S8-06). Το κινητό ρωτά «Ξεχασμένη προπόνηση;» μετά από 3 ώρες
 * χωρίς κίνηση (TrainingStore.staleAfter)· το ρολόι δεν είχε τίποτα: ένα μόνο «Τέλος», ή μια «Παύση» κατά λάθος, άφηναν
 * GPS και παλμούς ανοιχτούς για ώρες και έγραφαν περπάτημα 5 ωρών. ΜΟΝΟ υπενθύμιση (δόνηση + ειδοποίηση)· ποτέ αυτόματο
 * τέλος. Όλοι οι χρόνοι σε ms από την εκκίνηση (elapsedRealtime).
 */
object Forgotten {
    /** Ίδιο όριο με το κινητό: 3 ώρες. */
    const val LONG_MS = 3 * 60 * 60_000L

    /** Παύση περπατήματος που κρατά πάνω από τόσο. */
    const val PAUSE_MS = 10 * 60_000L

    /** Ξανά ανά τόσο, όσο ισχύει ακόμα. */
    const val REPEAT_MS = 30 * 60_000L

    enum class Why { WALK_LONG, WALK_PAUSED, STRENGTH_IDLE }

    /**
     * Γιατί μοιάζει ξεχασμένη, ή null. [kind]: «walk» ή «strength». Περπάτημα: σε παύση ([pausedSinceEl] ≥ 0) πάνω από
     * [PAUSE_MS], ή τρέχει πάνω από 3 ώρες και πάνω από το διπλάσιο των λεπτών του προγράμματος ([plannedMin], 0 = άγνωστα).
     * Βάρη: πάνω από 3 ώρες από το τελευταίο ✓ ([lastActionEl]) ή από την αρχή.
     */
    fun why(kind: String?, startedEl: Long, lastActionEl: Long, pausedSinceEl: Long, plannedMin: Int, nowEl: Long): Why? {
        if (kind == null || nowEl < startedEl) return null
        if (kind == "walk") {
            if (pausedSinceEl >= 0L && nowEl - pausedSinceEl > PAUSE_MS) return Why.WALK_PAUSED
            val limit = maxOf(LONG_MS, 2L * maxOf(plannedMin, 0) * 60_000L)
            return if (nowEl - startedEl > limit) Why.WALK_LONG else null
        }
        return if (nowEl - maxOf(startedEl, lastActionEl) > LONG_MS) Why.STRENGTH_IDLE else null
    }

    /** Υπενθύμιση τώρα: την πρώτη φορά ([lastRemindEl] ≤ 0) και μετά ανά [REPEAT_MS]. */
    fun remindNow(why: Why?, lastRemindEl: Long, nowEl: Long): Boolean = why != null && (lastRemindEl <= 0L || nowEl - lastRemindEl >= REPEAT_MS)

    /** Η ερώτηση (ειδοποίηση και οθόνη). Κείμενα προς έγκριση από τον χρήστη. */
    fun title(why: Why): String = when (why) {
        Why.WALK_LONG -> "Τρέχει ακόμα το περπάτημα;"
        Why.WALK_PAUSED -> "Το περπάτημα είναι σε παύση"
        Why.STRENGTH_IDLE -> "Τρέχει ακόμα η προπόνηση;"
    }

    /**
     * Τι να κάνεις (δεύτερη γραμμή της ειδοποίησης). Round 8 (R8-U3-03): πάνω από την ερώτηση ρεζέρβας ([onRir], [rirEnds])
     * το ίδιο με το [screenText]: εκεί δεν υπάρχει «Τέλος».
     */
    fun text(why: Why, onRir: Boolean = false, rirEnds: Boolean = false): String = when (why) {
        Why.WALK_PAUSED -> "Πάτα «Συνέχεια» ή «Τέλος» στο ρολόι."
        Why.WALK_LONG, Why.STRENGTH_IDLE -> when {
            !onRir -> "Αν τελείωσες, πάτα «Τέλος» στο ρολόι."
            rirEnds -> "Αν τελείωσες, απάντησε στην ερώτηση στο ρολόι."
            else -> "Αν τελείωσες, απάντησε στην ερώτηση και πάτα «Τέλος» στο ρολόι."
        }
    }

    /**
     * Το ίδιο στην ΟΘΟΝΗ της εφαρμογής, ολόκληρο σε όλη την οθόνη (έλεγχος 13/11, round 7, R7-U3-07): η ερώτηση στη δική
     * της γραμμή, χωρίς «στο ρολόι» (το διαβάζεις ήδη εκεί), και πρώτα «κλείσε αυτό»: ένα πάτημα στο μήνυμα το κλείνει (από
     * κάτω γράφει «πάτα για να κλείσει»), δεν τελειώνει την άσκηση. Κείμενο προς έγκριση από τον χρήστη.
     *
     * Έλεγχος 14/11, round 8 (R8-U3-03): όταν από κάτω είναι η ερώτηση ρεζέρβας ([onRir]), εκεί ΔΕΝ υπάρχει «Τέλος»· η
     * προπόνηση προχωρά μόνο με απάντηση. [rirEnds]: η απάντηση την τελειώνει κιόλας (προπόνηση του ρολογιού, όλες οι
     * ασκήσεις έγιναν: [WatchActivity.answer]) — αλλιώς μετά την απάντηση φαίνεται το «Τέλος».
     */
    fun screenText(why: Why, onRir: Boolean = false, rirEnds: Boolean = false): String = when (why) {
        Why.WALK_PAUSED -> "${title(why)}\nΚλείσε αυτό και πάτα «Συνέχεια» ή «Τέλος»."
        Why.WALK_LONG, Why.STRENGTH_IDLE -> when {
            !onRir -> "${title(why)}\nΑν τελείωσες: κλείσε αυτό και πάτα «Τέλος»."
            rirEnds -> "${title(why)}\nΑν τελείωσες: κλείσε αυτό και απάντησε στην ερώτηση."
            else -> "${title(why)}\nΑν τελείωσες: κλείσε αυτό, απάντησε στην ερώτηση και πάτα «Τέλος»."
        }
    }
}

/**
 * Η τελευταία κίνηση σε μια προπόνηση του κινητού: το πιο πρόσφατο ✓ (με ώρα), αλλιώς η αρχή της. Ίδιος κανόνας με το
 * κινητό (Session.lastActivity), για το [phoneStale]. Έλεγχος 14/11, round 8 (R8-A8-3, αίτημα του f2): και η «Συνέχεια»
 * στην «Ξεχασμένη προπόνηση;» του κινητού ([LiveSession.res]), αν είναι πιο πρόσφατη: πριν, μετά τη «Συνέχεια» το ρολόι
 * έγραφε «κλείσε την εκεί» και δεν πρότεινε «Παλμοί εδώ» ως το πρώτο ✓ στο κινητό. Όπως το κινητό: max(αρχή, ✓, «res»).
 */
fun phoneLastActivity(s: LiveSession): Long {
    var last = s.start
    for (item in s.items) for (x in item.sets) if (x.done && x.at > last) last = x.at
    return maxOf(last, s.res)
}

/**
 * Προπόνηση του κινητού που μοιάζει ξεχασμένη ανοιχτή (έλεγχος 13/11, round 7, R7-A8-3, αίτημα του f2): η τελευταία κίνηση
 * πριν από 3 ώρες και πάνω, ίδιο όριο με το κινητό (TrainingStore.staleAfter, [Forgotten.LONG_MS]). Το κινητό πλέον αγνοεί
 * ✓ και παλμούς του ρολογιού σε τέτοια προπόνηση· γι' αυτό η αρχική του ρολογιού δεν την προτείνει («Παλμοί εδώ») και δεν
 * κρύβει πια τη σημερινή: πριν, μια προπόνηση που ξεχάστηκε τη Δευτέρα έπαιρνε τα σετ και τους παλμούς της Τρίτης.
 */
fun phoneStale(s: LiveSession, now: Long): Boolean = now - phoneLastActivity(s) >= Forgotten.LONG_MS

private val WEEKDAY_NAMES = listOf("Δευτέρα", "Τρίτη", "Τετάρτη", "Πέμπτη", "Παρασκευή", "Σάββατο", "Κυριακή")

/**
 * «από τις 14:05» (ίδια μέρα), «από χθες», «από Δευτέρα» (μέσα στην εβδομάδα) ή «από 9/11»: από πότε είναι ανοιχτή μια
 * ξεχασμένη προπόνηση του κινητού ([phoneStale]). Κείμενο προς έγκριση από τον χρήστη.
 */
fun staleSinceText(start: Long, now: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String {
    val d = java.time.Instant.ofEpochMilli(start).atZone(zone)
    val today = java.time.Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
    val days = java.time.temporal.ChronoUnit.DAYS.between(d.toLocalDate(), today)
    return when {
        days <= 0L -> "από τις %02d:%02d".format(java.util.Locale.ROOT, d.hour, d.minute)
        days == 1L -> "από χθες"
        days < 7L -> "από ${WEEKDAY_NAMES[d.dayOfWeek.value - 1]}"
        else -> "από ${d.dayOfMonth}/${d.monthValue}"
    }
}

/** Η σημείωση της αρχικής για ξεχασμένη προπόνηση του κινητού (R7-A8-3), σε δύο γραμμές. Κείμενο προς έγκριση. */
const val STALE_PHONE_LINE1 = "Ανοιχτή προπόνηση στο κινητό"

fun stalePhoneLine2(start: Long, now: Long): String = "${staleSinceText(start, now)}· κλείσε την εκεί"

/**
 * Το «μπες στην προπόνηση του κινητού» (άνοιγμα από το κινητό, [flag]) γίνεται ΤΩΡΑ; Έλεγχος 14/11, round 8 (R8-A8-6): μόνο
 * αφού διαβαστεί η τωρινή κατάσταση του κινητού σε αυτό το άνοιγμα ([loaded], Link.load), και μόνο σε προπόνηση που δεν
 * έκλεισε και δεν μοιάζει ξεχασμένη ([phoneStale]). Πριν, το αίτημα κρινόταν με ό,τι είχε μείνει στη μνήμη από παλιότερα
 * (μια προπόνηση που είχε κλείσει στο κινητό χωρίς να το μάθει το ρολόι) και σβηνόταν: η νέα προπόνηση έμενε χωρίς παλμούς
 * από το ρολόι. Όσο δεν ισχύουν αυτά, το αίτημα ΜΕΝΕΙ (ώσπου να φτάσει η νέα προπόνηση· σβήνει μόνο αν ξεκινήσει κάτι εδώ,
 * [pendingJoin]).
 */
fun joinNow(flag: Boolean, loaded: Boolean, phone: LiveSession?, now: Long): Boolean =
    flag && loaded && phone != null && !phone.ended && !phoneStale(phone, now)

/**
 * Έναρξη ([kind], [fromPhone]) ενώ τρέχει ήδη άσκηση ([running]): δεκτή ΜΟΝΟ η περίπτωση για την οποία υπάρχει, δηλαδή η
 * προπόνηση του κινητού βρίσκει το ρολόι σε προπόνηση με βάρη («strength» + κινητό), και ποτέ όσο η άσκηση κλείνει
 * ([stopping]) ή σε περπάτημα (DP-10). Έλεγχος 14/11, round 8 (R8-A8-1): πριν, κάθε έναρξη (και «Περπάτημα» ή μια προπόνηση
 * του ρολογιού από την αρχική, όσο έκλεινε η μέτρηση μιας προπόνησης του κινητού) έγραφε «όχι του κινητού» και το
 * αποτέλεσμα των παλμών της δεν γραφόταν ποτέ.
 */
fun joinAllowedWhileRunning(running: String?, kind: String, fromPhone: Boolean, stopping: Boolean): Boolean =
    running != null && running != "walk" && kind == "strength" && fromPhone && !stopping

/**
 * Η «άλλη προπόνηση» που διάλεξες στην αρχική (τρίτο κουμπί, [chosen]) ισχύει μόνο τη μέρα που τη διάλεξες ([chosenDay]).
 * Έλεγχος 14/11, round 8 (R8-U3-06): πριν έμενε όσο ζούσε η εφαρμογή, και τις επόμενες μέρες το πρώτο κουμπί ήταν η χθεσινή
 * επιλογή (σε μέρα περπατήματος χανόταν και η αρχική του περπατήματος).
 */
fun chosenToday(chosen: String?, chosenDay: java.time.LocalDate?, today: java.time.LocalDate): String? =
    if (chosen != null && chosenDay == today) chosen else null

/** Μοιάζει ξεχασμένη η άσκηση; ([Forgotten.why]) */
fun forgottenDue(kind: String?, startedEl: Long, lastUserActionEl: Long, pausedSinceEl: Long, plannedMin: Int, nowEl: Long): Boolean =
    Forgotten.why(kind, startedEl, lastUserActionEl, pausedSinceEl, plannedMin, nowEl) != null

// ------------------------------------------------------------------ έλεγχος 13/11 (round 1): αποφάσεις της οθόνης

/** Πόσο αγνοούνται τα πατήματα αφού η οθόνη άλλαξε ΜΟΝΗ της (S8-05). */
const val TAP_GUARD_MS = 600L

/**
 * Δεκτό το πάτημα; (έλεγχος 13/11, S8-05) Όταν η οθόνη αλλάζει μόνη της (π.χ. το διάλειμμα λήγει και γίνεται «σετ», ή
 * ανάβει η κόκκινη οθόνη του ορίου) ενώ το δάχτυλο πηγαίνει ήδη σε κουμπί της προηγούμενης, το πάτημα έπεφτε σε ό,τι
 * βρέθηκε από κάτω: το μισό «+30″»/«Πάμε» γινόταν ✓ του επόμενου σετ. Για [TAP_GUARD_MS] μετά την αλλαγή
 * ([autoChangedEl], ms από την εκκίνηση· αρνητικό = ποτέ) το πάτημα αγνοείται.
 */
fun tapAllowed(nowEl: Long, autoChangedEl: Long): Boolean = autoChangedEl < 0L || nowEl - autoChangedEl >= TAP_GUARD_MS

/**
 * Η οθόνη άλλαξε μόνη της μπροστά στα μάτια του χρήστη; (S8-05) [hadScreen]: είχε ήδη ζωγραφιστεί άλλη οθόνη· [byTap]: η
 * αλλαγή ήρθε από πάτημα εδώ· [sinceLastDrawMs]: πόσο πριν ζωγραφίστηκε η προηγούμενη (πάνω από 1,5″ = η οθόνη ήταν
 * σβηστή ή αχνή, κανείς δεν σημάδευε κουμπί: καμία αναμονή όταν σηκώνεις τον καρπό).
 */
fun screenAutoChanged(hadScreen: Boolean, byTap: Boolean, sinceLastDrawMs: Long): Boolean = hadScreen && !byTap && sinceLastDrawMs in 0L..1_500L

/** Πόσο μένει ένα μήνυμα της υπηρεσίας μέσα στην οθόνη, από τη στιγμή που φάνηκε (U7-06/U7-07). */
const val NOTICE_INLINE_MS = 8_000L

/**
 * Φαίνεται ακόμα το μήνυμα μέσα στην οθόνη; (έλεγχος 13/11, U7-06/U7-07) Πριν, ένα μόνιμο μήνυμα (π.χ. «Χωρίς GPS: …»)
 * έσβηνε για όλο το περπάτημα τη λεζάντα της ζώνης («πάνω · κόψε λίγο») και στο σετ έκρυβε το «Τέλος» για όλη την
 * προπόνηση. Τώρα μένει [NOTICE_INLINE_MS] από τη στιγμή που φάνηκε ([ageMs]) και μετά δίνει πίσω τη θέση του.
 */
fun noticeInline(ageMs: Long): Boolean = ageMs < NOTICE_INLINE_MS

// ------------------------------------------------------------------ έλεγχος 14/11 (round 9)

/**
 * Τι έκανε ένα πάτημα στην οθόνη της ρεζέρβας ([LiveSession.answerAny], R9-A12-2). [first]: απαντήθηκε η ερώτηση «Πρώτο
 * σετ» (όχι η ρεζέρβα της άσκησης)· [rir1]: η εντολή «rir1» προς το κινητό, ή null (προπόνηση του ρολογιού, ή το κινητό
 * δεν τη ζητά πια)· [next]: μετά τη ρεζέρβα της άσκησης, τι ακολουθεί (null για το «Πρώτο σετ»)· [i]: η άσκηση που πήρε
 * την απάντηση, ή −1.
 */
class AnswerResult(val first: Boolean, val rir1: JSONObject?, val next: LiveSession.Next?, val i: Int)

/**
 * Η 2η γραμμή της ειδοποίησης «Η άσκηση σταμάτησε …» (άλλη εφαρμογή, χάθηκε άδεια· έλεγχος 14/11, round 9, R9-U3-09). Μιλά
 * για το όριο ΜΟΝΟ όταν υπάρχει όριο γιατρού ([hasLimit]), όπως κάθε άλλο κείμενο του ορίου στο ρολόι· σε περπάτημα με
 * ανοιχτή δόνηση ζώνης ([zoneBuzz], χωρίς όριο) λέει ότι σταμάτησε η δόνηση της ζώνης. Πριν έλεγε «Το όριο παλμών δεν σε
 * προσέχει πια» και σε χρήστη χωρίς όριο. Κείμενα προς έγκριση από τον χρήστη.
 */
fun endedElsewhereText(hasLimit: Boolean, zoneBuzz: Boolean): String = when {
    hasLimit -> "Ό,τι μετρήθηκε σώθηκε. Το όριο παλμών δεν σε προσέχει πια."
    zoneBuzz -> "Ό,τι μετρήθηκε σώθηκε. Η δόνηση της ζώνης σταμάτησε."
    else -> "Ό,τι μετρήθηκε σώθηκε."
}

/**
 * Η ζώνη ενός περπατήματος που ΣΥΝΕΧΙΖΕΙ μετά από απότομο κλείσιμο της εφαρμογής (έλεγχος 14/11, round 9, R9-A7-2): με
 * πρόγραμμα στο ρολόι ([plan]), η ζώνη του (ίδιος κανόνας με ένα νέο πρόγραμμα στη μέση του περπατήματος, [Repo.applyPlan])·
 * χωρίς πρόγραμμα (δεν διαβάστηκε ακόμα), η ζώνη που ίσχυε, από το στιγμιότυπο ([kept]), αντί για καμία ζώνη.
 */
fun resumeZone(plan: Plan?, kept: WalkZone?): WalkZone? = if (plan != null) plan.zone else kept
