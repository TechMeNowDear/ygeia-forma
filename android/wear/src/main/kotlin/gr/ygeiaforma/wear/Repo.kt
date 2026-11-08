package gr.ygeiaforma.wear

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject

/**
 * Η κατάσταση της εφαρμογής του ρολογιού, στη μνήμη (μία διεργασία: οθόνη + υπηρεσία άσκησης).
 * Όλες οι αλλαγές γίνονται στο κύριο νήμα· η οθόνη ακούει με [listen].
 */
object Repo {
    enum class Screen { HOME, SET, RIR, REST, WALK, END, SYM }

    var plan: Plan? = null
    /** Προπόνηση που τρέχει στο κινητό (καθρέφτης). */
    var phone: LiveSession? = null
    /** Το id της τελευταίας προπόνησης του κινητού (για τους παλμούς της, αφού κλείσει). */
    var lastPhoneId: String? = null

    /** Προπόνηση που ξεκίνησε στο ρολόι. */
    var local: LiveSession? = null

    /** Η προπόνηση που δείχνει η οθόνη: η δική του αν υπάρχει, αλλιώς του κινητού. */
    val session: LiveSession? get() = local ?: phone

    var screen = Screen.HOME

    /** Τι μετράει τώρα η υπηρεσία άσκησης: «strength», «walk» ή null. */
    var running: String? = null
    var runningPhone = false
    var startedAt = 0L

    var bpm = 0
    var bpmAt = 0L
    var hr: HrStats? = null

    /** Πώς έρχονται οι παλμοί: «5s» (ανά 5″ και με σβηστή οθόνη), «sensor» (εφεδρεία αισθητήρα), «default». */
    var hrMode = ""
    /** Κενά στην παράδοση παλμών (ό,τι φτάνει στην εφαρμογή, όχι ό,τι μετρά το ρολόι). */
    var hrGaps = GapMeter()
    val alarm = HrAlarm(null)
    /** Μέχρι πότε έχει σιγήσει η κόκκινη οθόνη (ο χρήστης την πάτησε). */
    var alarmMutedUntil = 0L

    /** «Νιώθω κάτι»: η οθόνη πριν (για «Πίσω») και αν στάλθηκε ήδη. */
    var symBack = Screen.HOME
    var symSent = false

    /** Πότε πατήθηκε «Σταμάτησα» (ms, 0 = ποτέ). Μένει και μετά από επανεκκίνηση, ώσπου να το δει το κινητό. */
    var symHoldAt = 0L

    /** Τι δεν ξεκινά τώρα: δες [holdOf]. */
    fun hold(): String? = holdOf(plan, symHoldAt, java.time.LocalDate.now().toString())

    var meters = 0.0
    var steps = 0L
    var activeSec = 0L
    var gps = false

    /** Μήνυμα για τον χρήστη (π.χ. λείπει άδεια), ή null. */
    var notice: String? = null

    /** Τελευταία φορά που ήρθαν δεδομένα από το κινητό (ms), για το «άνοιξε την εφαρμογή στο κινητό». */
    var syncedAt = 0L

    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableListOf<() -> Unit>()

    fun listen(l: () -> Unit) {
        listeners.add(l)
    }

    fun unlisten(l: () -> Unit) {
        listeners.remove(l)
    }

    fun changed() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            for (l in listeners.toList()) l()
        } else {
            main.post { changed() }
        }
    }

    fun bpmFresh(now: Long): Boolean = bpm > 0 && now - bpmAt < 15_000

    fun applyPlan(p: Plan?) {
        if (p == null) return
        plan = p
        alarm.limit = p.hrLimit
        syncedAt = System.currentTimeMillis()
    }

    /** Νέα κατάσταση από το κινητό. Κρατά ό,τι ✓ έγινε στο ρολόι και δεν έχει φτάσει ακόμα εκεί. */
    fun applyPhone(s: LiveSession?) {
        val prev = phone
        if (s != null && prev != null && prev.id == s.id) {
            for ((i, it) in s.items.withIndex()) {
                val old = prev.items.getOrNull(i) ?: continue
                if (old.ex != it.ex) continue
                for ((k, set) in it.sets.withIndex()) {
                    val o = old.sets.getOrNull(k) ?: continue
                    if (o.done && !set.done && System.currentTimeMillis() - o.at < 10_000) set.done = true
                }
                if (it.rir == null) it.rir = old.rir
            }
            // Η ερώτηση για ρεζέρβα μένει για την άσκηση που τελείωσε, όχι για όποια δείχνει τώρα το κινητό.
            if (prev.rirIdx >= 0 && s.items.getOrNull(prev.rirIdx)?.rir == null) s.rirIdx = prev.rirIdx
        }
        phone = s
        if (s != null) lastPhoneId = s.id
        if (s == null && prev != null) prev.ended = true
        syncedAt = System.currentTimeMillis()
    }

    fun resetExercise() {
        running = null
        runningPhone = false
        startedAt = 0
        bpm = 0
        bpmAt = 0
        hr = null
        hrMode = ""
        hrGaps = GapMeter()
        meters = 0.0
        steps = 0
        activeSec = 0
        gps = false
        alarmMutedUntil = 0
    }

    // ------------------------------------------------------------------ αντίγραφο ασφαλείας
    // Αν η εφαρμογή κλείσει απότομα στη μέση, το τελευταίο στιγμιότυπο στέλνεται στο κινητό στο επόμενο άνοιγμα.
    private const val PREFS = "ygeia_watch"
    private const val PENDING = "pending"

    private const val HOLD = "symHoldAt"

    fun loadHold(ctx: Context) {
        symHoldAt = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(HOLD, 0L)
    }

    fun setHold(ctx: Context, at: Long) {
        symHoldAt = at
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(HOLD, at).apply()
    }

    fun snapshot(ctx: Context, json: JSONObject?) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        if (json == null) p.remove(PENDING) else p.putString(PENDING, json.toString())
        p.apply()
    }

    fun takeSnapshot(ctx: Context): String? {
        val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val s = sp.getString(PENDING, null) ?: return null
        sp.edit().remove(PENDING).apply()
        return s
    }
}
