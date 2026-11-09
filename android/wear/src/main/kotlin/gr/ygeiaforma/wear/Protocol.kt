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
    const val KEY = "json"

    /** Δυνατότητα που δηλώνει η εφαρμογή του ρολογιού (res/values/wear.xml), για να τη βρίσκει το κινητό. */
    const val CAPABILITY = "ygeia_watch"
}

/** [confirmed]: το κινητό έχει δει το ✓ (στην κατάσταση που στέλνει). Ως τότε το ✓ του ρολογιού κρατιέται (έλεγχος #2). */
class SetT(val load: Double?, val label: String, var reps: Int, var done: Boolean = false, var at: Long = 0, var confirmed: Boolean = false)

class ItemT(
    val ex: String,
    val name: String,
    val rest: Int,
    val lo: Int,
    val hi: Int,
    val rirTarget: Int,
    val sets: MutableList<SetT>,
    var rir: Int? = null,
) {
    val complete: Boolean get() = sets.all { it.done }
    val doneCount: Int get() = sets.count { it.done }
    val nextSet: Int get() = sets.indexOfFirst { !it.done }
}

class CardioT(val activity: String, val name: String, val minutes: Int, val note: String?)

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
) {
    fun workout(id: String?): WorkoutT? = workouts.firstOrNull { it.id == id }

    /** Η προπόνηση μιας μέρας (για να είναι σωστή και αν το κινητό δεν άνοιξε σήμερα). */
    fun forWeekday(weekday: Int): WorkoutT? = if (days.isEmpty()) workout(today) else workout(days[weekday])

    val todayWorkout: WorkoutT? get() = forWeekday(java.time.LocalDate.now().dayOfWeek.value)

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
            )
        } catch (_: Exception) {
            null
        }
    }
}

internal fun JSONObject.optStringOrNull(k: String): String? = if (has(k) && !isNull(k)) getString(k) else null

internal fun itemOf(o: JSONObject): ItemT {
    val sets = o.optJSONArray("sets") ?: JSONArray()
    return ItemT(
        ex = o.getString("ex"),
        name = o.optString("name", o.getString("ex")),
        rest = o.optInt("rest", 90),
        lo = o.optInt("lo", 8),
        hi = o.optInt("hi", 12),
        rirTarget = o.optInt("rir", 2),
        sets = (0 until sets.length()).map {
            val s = sets.getJSONObject(it)
            SetT(
                load = if (s.has("load") && !s.isNull("load")) s.getDouble("load") else null,
                label = s.optString("label", ""),
                reps = s.optInt("reps", 0),
                done = s.optBoolean("done", false),
            )
        }.toMutableList(),
        rir = if (o.has("ra") && !o.isNull("ra")) o.getInt("ra") else null,
    )
}

internal fun workoutOf(o: JSONObject): WorkoutT {
    val items = o.optJSONArray("items") ?: JSONArray()
    val c = o.optJSONObject("cardio")
    return WorkoutT(
        id = o.getString("id"),
        name = o.optString("name", o.getString("id")),
        minutes = o.optInt("minutes", 0),
        items = (0 until items.length()).map { itemOf(items.getJSONObject(it)) },
        cardio = c?.let { CardioT(it.optString("activity", "walk"), it.optString("name", "Περπάτημα"), it.optInt("minutes", 30), it.optStringOrNull("note")) },
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
) {
    val current: ItemT? get() = items.getOrNull(idx)
    val allDone: Boolean get() = items.all { it.complete }
    val setsDone: Int get() = items.sumOf { it.doneCount }

    /** ✓ στο τρέχον σετ. Επιστρέφει τι ακολουθεί. */
    fun tick(now: Long): Next {
        val it = current ?: return Next.END
        val s = it.nextSet
        if (s < 0) return advance(now)
        it.sets[s].done = true
        it.sets[s].at = now
        if (!it.complete) {
            restEnd = if (it.rest > 0) now + it.rest * 1000L else 0
            return Next.REST
        }
        rirIdx = idx
        return Next.ASK_RIR
    }

    /** Ρεζέρβα μετά το τελευταίο σετ· μετά πάει στην επόμενη άσκηση που δεν έχει τελειώσει. Επιστρέφει και ποια άσκηση πήρε την απάντηση. */
    fun answer(rir: Int, now: Long): Pair<Next, Int> {
        val i = if (rirIdx >= 0) rirIdx else idx
        val restSec = items.getOrNull(i)?.rest ?: 0
        items.getOrNull(i)?.rir = rir
        rirIdx = -1
        return advance(now, restSec) to i
    }

    private fun advance(now: Long, restOf: Int? = null): Next {
        val restSec = restOf ?: current?.rest ?: 0
        val next = items.indexOfFirst { !it.complete }
        if (next < 0) {
            restEnd = 0
            return Next.END
        }
        idx = next
        restEnd = if (restSec > 0) now + restSec * 1000L else 0
        return Next.REST
    }

    /** Παράλειψη της τρέχουσας άσκησης (πάει στην επόμενη, χωρίς διάλειμμα). */
    fun skip(): Next {
        val n = items.indices.firstOrNull { it > idx && !items[it].complete } ?: items.indices.firstOrNull { it != idx && !items[it].complete }
        restEnd = 0
        if (n == null) return Next.END
        idx = n
        return Next.SET
    }

    enum class Next { SET, REST, ASK_RIR, END }

    /** Για το κινητό: ίδια μορφή με το ExLog.toJson της εφαρμογής (l, r, d, t). */
    fun resultJson(end: Long, hr: HrStats, cardio: JSONObject? = null): JSONObject {
        val arr = JSONArray()
        for (it in items) {
            val log = JSONArray()
            for (s in it.sets) {
                val o = JSONObject().put("r", s.reps)
                if (s.load != null) o.put("l", s.load)
                if (s.done) o.put("d", 1).put("t", s.at)
                log.put(o)
            }
            val o = JSONObject()
                .put("ex", it.ex).put("sets", it.sets.size).put("lo", it.lo).put("hi", it.hi)
                .put("rir", it.rirTarget).put("rest", it.rest).put("log", log)
            it.rir?.let { r -> o.put("ra", r) }
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

        /** Η προπόνηση του κινητού ([Paths.SESSION]). null αν δεν τρέχει καμία. */
        fun parsePhone(text: String): LiveSession? = try {
            val j = JSONObject(text)
            if (!j.optBoolean("active", false)) {
                null
            } else {
                val arr = j.optJSONArray("items") ?: JSONArray()
                LiveSession(
                    id = j.getString("id"),
                    workout = j.optString("w", ""),
                    name = j.optString("name", ""),
                    start = j.optLong("start", 0),
                    items = (0 until arr.length()).map { itemOf(arr.getJSONObject(it)) },
                    idx = j.optInt("idx", 0),
                    restEnd = j.optLong("restEnd", 0),
                    phone = true,
                )
            }
        } catch (_: Exception) {
            null
        }
    }
}

/** Παλμοί μιας άσκησης: μέσος, υψηλότερος και δείγματα ανά [step] δευτερόλεπτα (για το γράφημα στο κινητό). */
class HrStats(private val start: Long, private val step: Int = 10) {
    private var sum = 0L
    private var n = 0
    var max = 0
        private set
    var last = 0
        private set
    val samples = mutableListOf<IntArray>()
    private var lastSampleSec = -1

    fun add(bpm: Int, at: Long) {
        if (bpm <= 25 || bpm >= 250) return // όχι πραγματική τιμή (π.χ. το ρολόι δεν ακουμπά)
        sum += bpm
        n++
        last = bpm
        if (bpm > max) max = bpm
        val sec = ((at - start) / 1000).toInt()
        if (lastSampleSec < 0 || sec - lastSampleSec >= step) {
            samples.add(intArrayOf(sec, bpm))
            lastSampleSec = sec
        }
    }

    val avg: Int get() = if (n == 0) 0 else Math.round(sum.toDouble() / n).toInt()

    fun writeTo(o: JSONObject) {
        if (n == 0) return
        o.put("hrAvg", avg).put("hrMax", max)
        val a = JSONArray()
        for (s in samples) a.put(JSONArray().put(s[0]).put(s[1]))
        o.put("hr", a)
    }
}

/**
 * Ειδοποίηση ορίου παλμών, με βάση τον χρόνο κάθε τιμής (όχι πόσες τιμές ήρθαν μαζί):
 * ανάβει όταν οι παλμοί μένουν στο όριο ή πάνω για [holdMs] (5″), ξαναδονείται κάθε [repeatMs] (30″)
 * όσο μένουν πάνω, σβήνει κάτω από όριο − 5. Έλεγχος 8/11: πριν μετρούσε «2 μηνύματα», που
 * με τα πακέτα των παλμών μπορούσε να σημαίνει και 2–3 λεπτά καθυστέρηση.
 */
class HrAlarm(var limit: Int?, private val holdMs: Long = 5_000, private val repeatMs: Long = 30_000) {
    var on = false
        private set
    private var overSince = -1L
    private var lastBuzz = 0L
    private var lastAt = Long.MIN_VALUE

    /**
     * true όταν πρέπει να δονηθεί (τη στιγμή που ανάβει και ανά 30″ όσο μένει πάνω). [at]: χρόνος της τιμής (ms).
     * Τιμές παλαιότερες από την τελευταία αγνοούνται: έτσι ακούει και τις δύο πηγές (Health Services και αισθητήρα)
     * χωρίς να ανακατεύονται οι χρόνοι, και αν σταματήσει η μία, συνεχίζει η άλλη (έλεγχος #2, W2-04).
     */
    fun feed(bpm: Int, at: Long): Boolean {
        if (at < lastAt) return false
        lastAt = at
        return step(bpm, at)
    }

    /**
     * Καμία νέα τιμή, αλλά η τελευταία ([bpm], ακόμα φρέσκια) ισχύει και τώρα: ο αισθητήρας στέλνει μόνο αλλαγές, οπότε
     * σταθεροί παλμοί πάνω από το όριο δεν θα έφερναν ποτέ δόνηση (έλεγχος #2, W2-02).
     */
    fun steady(bpm: Int, now: Long): Boolean = step(bpm, now)

    private fun step(bpm: Int, at: Long): Boolean {
        val l = limit
        if (l == null) {
            on = false
            overSince = -1
            return false
        }
        if (bpm >= l) {
            if (overSince < 0) overSince = at
            if (!on && at - overSince >= holdMs) {
                on = true
                lastBuzz = at
                return true
            }
            if (on && at - lastBuzz >= repeatMs) {
                lastBuzz = at
                return true
            }
        } else {
            overSince = -1
            if (on && bpm < l - 5) on = false
        }
        return false
    }

    fun reset() {
        on = false
        overSince = -1
        lastBuzz = 0
        lastAt = Long.MIN_VALUE
    }
}

/** Χρόνος τιμής αισθητήρα (ns από την εκκίνηση) → ώρα (ms), ποτέ στο μέλλον. */
fun sensorWallTime(eventNanos: Long, nowWallMs: Long, nowElapsedNanos: Long): Long =
    (nowWallMs - (nowElapsedNanos - eventNanos) / 1_000_000).coerceAtMost(nowWallMs)

/**
 * Πόσο συχνά φτάνουν πραγματικά οι παλμοί στην εφαρμογή (το μεγαλύτερο κενό ανάμεσα σε δύο παραδόσεις).
 * Για τον έλεγχο στη συσκευή: δείχνει αν η ειδοποίηση ορίου μπορεί να αργήσει (8/11).
 */
class GapMeter {
    private var last = 0L
    var maxGapMs = 0L
        private set

    fun mark(at: Long) {
        if (last > 0 && at > last) maxGapMs = maxOf(maxGapMs, at - last)
        last = at
    }

    /** Και ο χρόνος ως το τέλος (αν σταμάτησαν να έρχονται). */
    fun close(at: Long) {
        if (last > 0 && at > last) maxGapMs = maxOf(maxGapMs, at - last)
    }

    val maxGapSec: Int get() = ((maxGapMs + 500) / 1000).toInt()
}

/** «1:04», «24:31», «1:02:05». */
fun clock(sec: Long): String {
    val s = if (sec < 0) 0 else sec
    val h = s / 3600
    val m = (s % 3600) / 60
    val r = s % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, r) else "%d:%02d".format(m, r)
}

/** «2,18» km. */
fun km(meters: Double): String = "%.2f".format(java.util.Locale.ROOT, meters / 1000.0).replace('.', ',')

/** Ρυθμός ανά km: «11′15″». */
fun pace(meters: Double, sec: Long): String {
    if (meters < 50 || sec <= 0) return "—"
    val p = (sec / (meters / 1000.0)).toLong()
    return "%d′%02d″".format(p / 60, p % 60)
}
