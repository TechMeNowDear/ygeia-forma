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
    enum class Screen { HOME, SET, RIR, REST, WALK, RECOVER, END }

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

    /**
     * Αισθητήρας που στέλνει μόνο αλλαγές, με επαφή και ίδια τιμή: οι παλμοί είναι σταθεροί, όχι χαμένοι, ως αυτή
     * την ώρα (ms). Μόνο για την ένδειξη και την ειδοποίηση· ποτέ ως τιμή προς το κινητό (έλεγχος #2).
     */
    var steadyUntil = 0L

    /** Δεν μετριούνται παλμοί, μετά την αναμονή του [HrSilence] (30″ στην αρχή, 15″/45″ αν χάθηκαν), ή null. */
    var hrSilent: HrSilence.Silence? = null

    /** Παλμοί που ισχύουν τώρα (φρέσκια τιμή ή σταθεροί από τον αισθητήρα). */
    fun hrLive(now: Long): Boolean = bpmFresh(now) || (bpm > 0 && now < steadyUntil)

    var meters = 0.0
    var steps = 0L
    var activeSec = 0L
    var gps = false

    /** Περπάτημα σε παύση (9/11): χρόνος, απόσταση και μέσος παλμών σταματούν· η ειδοποίηση ορίου μένει. */
    var paused = false
    /** Παύσεις: [αρχή, τέλος] σε ms (το τέλος 0 όσο κρατά). */
    val pauses = mutableListOf<LongArray>()

    /** Κάθε ολόκληρο χιλιόμετρο: [ενεργός χρόνος (″), ώρα (ms)]. Μόνο με GPS δείχνεται ανά km στο κινητό. */
    val splits = mutableListOf<LongArray>()

    /**
     * Λεπτό αποκατάστασης μετά το «Τέλος» του περπατήματος (9/11): ως πότε (ms), 0 αν δεν τρέχει. Χρόνος, απόσταση
     * και βήματα έχουν «παγώσει» στο [endAt].
     */
    var recoveryUntil = 0L
    var endAt = 0L

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

    /** ✓ του ρολογιού που το κινητό δεν έχει δει ακόμα (άσκηση, σετ): ξαναστέλνονται (έλεγχος #2, W2-05). */
    var pendingTicks: List<Pair<Int, Int>> = emptyList()

    /**
     * Νέα κατάσταση από το κινητό. Κρατά κάθε ✓ που έγινε στο ρολόι και δεν έχει φτάσει ακόμα εκεί (όσο κι αν αργήσει,
     * π.χ. κλειστή εφαρμογή στο κινητό)· ένα ✓ που το κινητό είχε δει και μετά το έβγαλε, βγαίνει κι εδώ.
     */
    fun applyPhone(s: LiveSession?) {
        val prev = phone
        val pending = mutableListOf<Pair<Int, Int>>()
        s?.items?.forEach { it.sets.forEach { set -> if (set.done) set.confirmed = true } }
        if (s != null && prev != null && prev.id == s.id) {
            for ((i, it) in s.items.withIndex()) {
                val old = prev.items.getOrNull(i) ?: continue
                if (old.ex != it.ex) continue
                for ((k, set) in it.sets.withIndex()) {
                    val o = old.sets.getOrNull(k) ?: continue
                    if (o.done && !set.done && !o.confirmed) {
                        set.done = true
                        set.at = o.at
                        pending.add(i to k)
                    }
                }
                if (it.rir == null) it.rir = old.rir
            }
            // Η ερώτηση για ρεζέρβα μένει για την άσκηση που τελείωσε, όχι για όποια δείχνει τώρα το κινητό.
            if (prev.rirIdx >= 0 && s.items.getOrNull(prev.rirIdx)?.rir == null) s.rirIdx = prev.rirIdx
        }
        phone = s
        pendingTicks = pending
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
        paused = false
        pauses.clear()
        splits.clear()
        recoveryUntil = 0
        endAt = 0
        alarmMutedUntil = 0
        steadyUntil = 0
        hrSilent = null
    }

    // ------------------------------------------------------------------ αντίγραφο ασφαλείας
    // Αν η εφαρμογή κλείσει απότομα στη μέση, το τελευταίο στιγμιότυπο στέλνεται στο κινητό στο επόμενο άνοιγμα.
    private const val PREFS = "ygeia_watch"
    private const val PENDING = "pending"

    /** Κλειδιά της παύσης μετά από «Σταμάτησα» (ως #84): σβήνονται μία φορά (απλοποίηση 9/11). */
    fun dropOldKeys(ctx: Context) {
        val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (sp.contains("symHoldAt") || sp.contains("pendingSym")) sp.edit().remove("symHoldAt").remove("pendingSym").apply()
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
