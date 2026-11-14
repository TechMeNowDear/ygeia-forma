package gr.ygeiaforma.wear

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

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

    /**
     * Η τελευταία κατάσταση της προπόνησης του κινητού, και αφού εκείνη κλείσει (έλεγχος 9/11, V-A-12): τα ✓ του ρολογιού
     * που δεν έφτασαν πάνε στο κινητό μέσα στο αποτέλεσμα («items»), ακόμα κι αν το κινητό έκλεισε πρώτο την προπόνηση.
     */
    var lastPhone: LiveSession? = null
        set(v) {
            field = v
            // «Ξέχνα την τελευταία» ξεχνά και την προηγούμενή της ([endedPhone], R7-A8-2)· η εφαρμογή γράφει εδώ μόνο προπονήσεις.
            if (v == null) endedPhone = null
        }

    /**
     * Το τελευταίο όριο παλμών που ήρθε από το κινητό (μένει και μετά από επανεκκίνηση, έλεγχος 9/11, V-A-06): ισχύει και
     * σε περπάτημα όταν δεν υπάρχει (ακόμα) πρόγραμμα στο ρολόι. null = χωρίς όριο.
     */
    var knownLimit: Int? = null

    /** Το όριο που ισχύει τώρα: του προγράμματος, αλλιώς το τελευταίο που ήρθε. */
    fun limitNow(): Int? {
        val p = plan
        return if (p != null) p.hrLimit else knownLimit
    }

    /** Ήρθε πρόγραμμα ή προπόνηση από νεότερη έκδοση της εφαρμογής του κινητού (V-A-08): «Ενημέρωσε την εφαρμογή στο ρολόι». */
    var updateNeeded = false

    /** Προπόνηση που ξεκίνησε στο ρολόι. */
    var local: LiveSession? = null

    /** Η προπόνηση που δείχνει η οθόνη: η δική του αν υπάρχει, αλλιώς του κινητού. */
    val session: LiveSession? get() = local ?: phone

    var screen = Screen.HOME

    /** Τι μετράει τώρα η υπηρεσία άσκησης: «strength», «walk» ή null. */
    var running: String? = null
    var runningPhone = false
    var startedAt = 0L

    /** Η αρχή σε χρόνο από την εκκίνηση της συσκευής (elapsedRealtime): για τους χρόνους της ειδοποίησης (W3-14). */
    var startedEl = 0L

    /** Το id της προπόνησης του κινητού που μετράει τώρα («Παλμοί εδώ»). */
    var runningSid: String? = null

    var bpm = 0
    var bpmAt = 0L

    /** Ο χρόνος της τελευταίας τιμής σε elapsedRealtime (ms): δεν «πηδά» όταν αλλάζει η ώρα του ρολογιού (W3-14). */
    var bpmEl = 0L
    var hr: HrStats? = null

    /** Πώς έρχονται οι παλμοί: «5s» (ανά 5″ και με σβηστή οθόνη), «sensor» (εφεδρεία αισθητήρα), «default». */
    var hrMode = ""
    /** Κενά στην παράδοση παλμών (ό,τι φτάνει στην εφαρμογή, όχι ό,τι μετρά το ρολόι). */
    var hrGaps = GapMeter()

    /**
     * Πόσες τιμές παλμών ήρθαν από το Health Services με κάθε ποιότητα σε αυτή την άσκηση (τελικός έλεγχος, Συμβούλιο 1,
     * Σ1). Οι άχρηστες (χωρίς επαφή, αναξιόπιστες) δεν μπαίνουν πουθενά· οι υπόλοιπες μετριούνται για τη διάγνωση.
     */
    var hrQuality = HrQualityCount()
    val alarm = HrAlarm(null)

    /** Ζώνη περπατήματος (12/11), από το πρόγραμμα του κινητού· μόνο στο περπάτημα. */
    val zoneAlarm = ZoneAlarm()

    fun zoneNow(): WalkZone? = plan?.zone

    /**
     * Η δόνηση ζώνης δεν φτάνει τώρα στον καρπό: το ρολόι είναι σε Σίγαση ή σε Εξοικονόμηση ενέργειας (έλεγχος 13/11,
     * S8-02, [zoneMutedNow]). Η οθόνη του περπατήματος γράφει «χωρίς δόνηση»· το κρίνει η υπηρεσία ανά λίγα δευτερόλεπτα.
     */
    var zoneMuted = false

    /**
     * Χρειάζονται παλμοί χωρίς καθυστέρηση (εφεδρεία αισθητήρα όταν το ρολόι δεν στέλνει ανά 5″): όριο γιατρού, ή
     * δόνηση ζώνης σε περπάτημα. Αλλιώς τίποτα παραπάνω (μπαταρία).
     */
    fun fastHr(): Boolean = alarm.limit != null || (running == "walk" && zoneAlarm.active)
    /** Μέχρι πότε έχει σιγήσει η κόκκινη οθόνη (ο χρήστης την πάτησε). */
    var alarmMutedUntil = 0L

    /**
     * Αισθητήρας που στέλνει μόνο αλλαγές, με επαφή και ίδια τιμή: οι παλμοί είναι σταθεροί, όχι χαμένοι, ως αυτή
     * την ώρα (ms). Μόνο για την ένδειξη και την ειδοποίηση· ποτέ ως τιμή προς το κινητό (έλεγχος #2).
     */
    var steadyUntil = 0L
    var steadyUntilEl = 0L

    /** Δεν μετριούνται παλμοί, μετά την αναμονή του [HrSilence] (30″ στην αρχή, 15″/45″ αν χάθηκαν), ή null. */
    var hrSilent: HrSilence.Silence? = null

    /**
     * Τι λέει το Health Services για τους παλμούς (έλεγχος γ2, W2-02): true = μετρά, false = το ρολόι δεν είναι στον καρπό,
     * null = δεν είπε τίποτα ακόμα.
     */
    var hrAvailable: Boolean? = null

    /**
     * Παλμοί που ισχύουν τώρα: φρέσκια τιμή, σταθεροί από τον αισθητήρα, ή (όχι σε «5s») η τελευταία τιμή ως 60″ όσο το
     * Health Services λέει ότι μετρά: κάποια ρολόγια στέλνουν τιμή μόνο όταν αλλάζει (W2-02). Ποτέ όταν λέει ότι το
     * ρολόι βγήκε από τον καρπό.
     */
    fun hrLive(now: Long): Boolean {
        if (hrAvailable == false) return false
        if (bpmFresh(now) || (bpm > 0 && now < steadyUntil)) return true
        return hrAvailable == true && hrMode != "5s" && bpm > 0 && now - bpmAt in 0 until 60_000
    }

    /** Το σφάλμα που σταμάτησε τη μέτρηση (είδος: μήνυμα), για τη σύνοψη στο κινητό (έλεγχος γ2, W2-14), ή null. */
    var lastErr: String? = null

    /** Η άσκηση ξαναστήθηκε από στιγμιότυπο (απότομο κλείσιμο): τα κενά των παλμών δεν είναι γνωστά (S2). */
    var restored = false

    /** Τι μπορεί το ρολόι (για τον έλεγχο στη συσκευή, W2-14/W3-10): π.χ. «5s=1 wake=1». */
    var diag = ""

    /**
     * Ως πότε (ώρα του ρολογιού, ms) το κινητό κοιτάζει το περπάτημα («/ygeia/watching», έλεγχος γ2, W3-15), και αν το
     * κινητό ξέρει να το λέει (νεότερη έκδοση). Παλιό κινητό: «ζωντανά» ανά 10″ όπως πριν.
     */
    var watchingUntil = 0L
    var phoneKnowsWatching = false

    /** Το «επεισόδιο» του ορίου που σίγησε ο χρήστης (W2-16): η σίγαση δεν κόβει ένα νέο. */
    var alarmMutedEpisode = -1

    var meters = 0.0
    var steps = 0L
    var activeSec = 0L
    var gps = false

    /** Το μήκος βήματος (m) της άσκησης που τρέχει, από το πρόγραμμα στην αρχή (14/11)· null: καμία εκτίμηση. */
    var stride: Double? = null

    /** Η απόσταση της οθόνης και αν είναι εκτίμηση από τα βήματα ([shownDistance], 14/11). */
    fun shown(): Pair<Double, Boolean> = shownDistance(meters, gps, steps, stride)

    /** Το τελευταίο χιλιόμετρο που ειπώθηκε (14/11): κάθε χιλιόμετρο μία φορά. */
    var kmDone = 0

    /** Πράσινη οθόνη «Πρώτο χιλιόμετρο» ως πότε (ms) και για ποιο (14/11). */
    var kmFlashUntil = 0L
    var kmFlashN = 0

    /**
     * Σημείο ελέγχου του Health Services για τον ενεργό χρόνο (W3-12): ο χρόνος στην οθόνη προχωρά κάθε δευτερόλεπτο,
     * όχι μόνο όταν έρχεται ενημέρωση. [cpWall] = 0: δεν ήρθε ακόμα.
     */
    var cpActiveMs = 0L
    var cpWall = 0L
    var cpRunning = false

    /** Ενεργός χρόνος (″) τώρα. */
    fun activeSecNow(now: Long): Long = activeSecAt(cpActiveMs, cpWall, cpRunning, now, activeSec)

    /** Περπάτημα σε παύση (9/11): χρόνος, απόσταση και μέσος παλμών σταματούν· η ειδοποίηση ορίου μένει. */
    var paused = false
    /** Παύσεις: [αρχή, τέλος] σε ms (το τέλος 0 όσο κρατά). */
    val pauses = mutableListOf<LongArray>()

    /** Κάθε ολόκληρο χιλιόμετρο, τη στιγμή που περάστηκε (V-A-19). Μόνο με GPS δείχνεται ανά km στο κινητό. */
    var split = SplitTracker(0)
    val splits: List<LongArray> get() = split.splits

    /**
     * Λεπτό αποκατάστασης μετά το «Τέλος» του περπατήματος (9/11): ως πότε (ms), 0 αν δεν τρέχει. Χρόνος, απόσταση
     * και βήματα έχουν «παγώσει» στο [endAt].
     */
    var recoveryUntil = 0L
    var endAt = 0L

    /** Μήνυμα για τον χρήστη (π.χ. λείπει άδεια), ή null. */
    var notice: String? = null

    /**
     * Αποτελέσματα που στο «Τέλος» δεν γράφτηκαν ΟΥΤΕ στην αναμονή ΟΥΤΕ στο Data Layer (γεμάτος χώρος· έλεγχος 13/11, round 7,
     * R7-A8-5): id → JSON. Μόνο στη μνήμη· ξαναδοκιμάζονται σε κάθε άνοιγμα της εφαρμογής (WatchActivity), πριν από την
     * ανάκτηση του στιγμιότυπου (που κρατήθηκε ως εφεδρεία, S8-08).
     */
    val unsaved = LinkedHashMap<String, JSONObject>()

    /** Το τελευταίο «Τέλος» (ή ένα παλιότερο) δεν γράφτηκε πουθενά: η οθόνη του τέλους λέει «Δεν αποθηκεύτηκε». */
    var endUnsaved = false

    /** Το μήνυμα να ανοίξει ολόκληρο σε όλη την οθόνη (μήνυμα ασφάλειας, S1)· η οθόνη το σβήνει μόλις το δείξει. */
    var openNotice = false

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
        // Νέο όριο στη μέση της άσκησης: η κόκκινη οθόνη κρίνεται ξανά με αυτό (HrAlarm.limit, W2-16).
        alarm.limit = p.hrLimit
        // Νέα ζώνη στη μέση του περπατήματος: ισχύει από τώρα (η προθέρμανση δεν ξαναρχίζει).
        if (running == "walk") zoneAlarm.zone = p.zone
        syncedAt = System.currentTimeMillis()
    }

    /** Η κόκκινη οθόνη του ορίου φαίνεται τώρα (αναμμένο και όχι σε σίγαση για αυτό το επεισόδιο). */
    fun alarmShown(now: Long): Boolean =
        alarm.on && running != null && !(now < alarmMutedUntil && alarmMutedEpisode == alarm.episode)

    /** «Πάτα για να κλείσει»: σίγαση 60″ για το ίδιο επεισόδιο (οι δονήσεις ανά 30″ συνεχίζουν, W2-16). */
    fun muteAlarm(now: Long) {
        alarmMutedUntil = now + 60_000
        alarmMutedEpisode = alarm.episode
    }

    /**
     * ✓ του ρολογιού που το κινητό δεν έχει δει ακόμα (άσκηση, σετ): ξαναστέλνονται (έλεγχος #2, W2-05). Κάθε φορά από την
     * ίδια την κατάσταση (έλεγχος 9/11, W3-03): και όταν το κινητό δεν έστειλε τίποτα νέο από τότε.
     */
    val pendingTicks: List<Pair<Int, Int>>
        get() {
            val p = phone ?: return emptyList()
            val out = mutableListOf<Pair<Int, Int>>()
            for ((i, it) in p.items.withIndex()) for ((k, set) in it.sets.withIndex()) if (set.done && !set.confirmed) out.add(i to k)
            return out
        }

    /**
     * Επαναλήψεις που άλλαξες στο ρολόι και το κινητό δεν δείχνει ακόμα (άσκηση, σετ): ξαναστέλνονται ως «reps» μαζί με
     * τα ✓ που εκκρεμούν (τελικός έλεγχος, Συμβούλιο 4, W-4). Όχι για ✓ του ρολογιού που το κινητό δεν έχει δει: εκεί οι
     * επαναλήψεις πάνε μέσα στο ίδιο το ✓ ([tickCmd], [pendingTicks]).
     */
    val pendingReps: List<Pair<Int, Int>>
        get() {
            val p = phone ?: return emptyList()
            val out = mutableListOf<Pair<Int, Int>>()
            for ((i, it) in p.items.withIndex()) for ((k, set) in it.sets.withIndex()) {
                if (set.trail != null && (set.confirmed || !set.done)) out.add(i to k)
            }
            return out
        }

    /**
     * Απαντήσεις στο «Πρώτο σετ» που δόθηκαν στο ρολόι και το κινητό ακόμα ζητά (έλεγχος 14/11, round 9, R9-A8-3): (θέση,
     * άσκηση, απάντηση), για να ξανασταλούν ως «rir1» μαζί με τα ✓ που εκκρεμούν ([LiveSession.firstResends]). Πριν, η «rir1»
     * έφευγε μία φορά: αν το κινητό δεν άκουγε εκείνη τη στιγμή, η βαθμονόμηση των επόμενων σετ χανόταν.
     */
    val pendingFirst: List<Triple<Int, String, Int>>
        get() = phone?.firstResends() ?: emptyList()

    /**
     * Αύξων αριθμός («q») για τις εντολές προς το κινητό (έλεγχος γ2, W2-19): ένας για όλη την εφαρμογή (οθόνη και
     * υπηρεσία), πάντα μεγαλύτερος από τον προηγούμενο, και ποτέ μικρότερος από την ώρα (ώστε να συνεχίζει σωστά και μετά
     * από νέα εκκίνηση της εφαρμογής). Πριν ήταν μέσα στην οθόνη· τώρα τον χρειάζεται και η υπηρεσία (W-4).
     */
    private var cmdSeq = 0L
    fun nextCmdSeq(now: Long = System.currentTimeMillis()): Long {
        cmdSeq = maxOf(cmdSeq + 1, now)
        return cmdSeq
    }

    /**
     * Νέα κατάσταση από το κινητό. Κρατά κάθε ✓ που έγινε στο ρολόι και δεν έχει φτάσει ακόμα εκεί (όσο κι αν αργήσει,
     * π.χ. κλειστή εφαρμογή στο κινητό)· ένα ✓ που το κινητό είχε δει και μετά το έβγαλε, βγαίνει κι εδώ. Το ίδιο για τις
     * επαναλήψεις που άλλαξες στο ρολόι και δεν έφτασαν ακόμα ([keepWatchEdits], W-4).
     */
    fun applyPhone(s: LiveSession?) {
        val prev = phone
        s?.items?.forEach { it.sets.forEach { set -> if (set.done) set.confirmed = true } }
        // Ό,τι ήξερε το ρολόι για την ΙΔΙΑ προπόνηση: η προηγούμενη κατάσταση, ή (μετά από απότομο κλείσιμο, πριν φτάσει
        // ξανά η κατάσταση του κινητού) αυτή που ξαναστήθηκε από το στιγμιότυπο ([restorePhone], R7-A8-1).
        val base = if (s == null) null else prev?.takeIf { it.id == s.id } ?: listOfNotNull(lastPhone, endedPhone).firstOrNull { it.id == s.id }
        if (s != null && base != null) mergeWatchEdits(base, s)
        if (s != null) s.restLen = phoneRestLen(prev?.takeIf { it.id == s.id }, s, System.currentTimeMillis())
        phone = s
        if (s != null) {
            // Έλεγχος 13/11, round 7 (R7-A8-2): η προηγούμενη προπόνηση του κινητού (με τα ✓ του ρολογιού που δεν έφτασαν)
            // δεν χάνεται όταν φτάνει μαζί η επόμενη: την κρατά το [endedPhone] για το αποτέλεσμα των παλμών της.
            keepEnded(lastPhone, s.id)
            lastPhoneId = s.id
            lastPhone = s
        }
        if (s == null && prev != null) prev.ended = true
        syncedAt = System.currentTimeMillis()
    }

    /**
     * Η προπόνηση του κινητού που μόλις αντικαταστάθηκε από ΑΛΛΗ (έλεγχος 13/11, round 7, R7-A8-2). Πριν, το [lastPhone]
     * γραφόταν από πάνω από την επόμενη: αν το ρολόι μάθαινε ότι η Α τελείωσε μαζί με την έναρξη της Β (Bluetooth, ύπνος
     * του επεξεργαστή), το αποτέλεσμα των παλμών της Α έφευγε χωρίς σετ, και τα ✓ / η ρεζέρβα του ρολογιού χάνονταν.
     */
    var endedPhone: LiveSession? = null

    /** [old] φεύγει από το [lastPhone] για την [newId]: κρατιέται, εκτός αν πάνω του ήταν ήδη αυτή που μετράει τώρα. */
    private fun keepEnded(old: LiveSession?, newId: String) {
        if (old == null || old.id == newId) return
        val kept = endedPhone
        if (kept != null && kept.id == runningSid && old.id != runningSid) return
        endedPhone = old
    }

    /** Η προπόνηση του κινητού [id] όπως την ξέρει το ρολόι: η τωρινή, η τελευταία ή αυτή που μόλις αντικαταστάθηκε. */
    fun phoneById(id: String?): LiveSession? =
        if (id.isNullOrEmpty()) null else listOfNotNull(phone, lastPhone, endedPhone).firstOrNull { it.id == id }

    /**
     * Έναρξη ([kind], [fromPhone]) ενώ τρέχει ήδη άσκηση ([ExerciseService], έλεγχος 14/11, round 8, R8-A8-1): η προπόνηση
     * του κινητού βρήκε το ρολόι σε προπόνηση με βάρη → μετρά πλέον και γι' αυτήν. Οτιδήποτε άλλο ([joinAllowedWhileRunning]:
     * περπάτημα, προπόνηση του ρολογιού, ή η άσκηση κλείνει ήδη, [stopping]) αγνοείται: ΠΟΤΕ «όχι του κινητού» πάνω σε
     * προπόνηση του κινητού, ώστε το αποτέλεσμα των παλμών της να γραφτεί. true αν δέχτηκε.
     */
    fun joinWhileRunning(kind: String, fromPhone: Boolean, stopping: Boolean): Boolean {
        if (!joinAllowedWhileRunning(running, kind, fromPhone, stopping)) return false
        runningPhone = true
        if (runningSid == null) runningSid = phone?.id
        return true
    }

    /**
     * Η προπόνηση του κινητού όπως την ήξερε το ρολόι πριν κλείσει απότομα ([LiveSession.phoneWatchState], R7-A8-1). Αν το
     * κινητό έχει ήδη στείλει την ίδια, μπαίνουν πάνω της ό,τι δεν είχε φτάσει εκεί ([mergeWatchEdits]): τα ✓ ξαναστέλνονται
     * και πάνε και στο αποτέλεσμα. Αλλιώς (τελείωσε, ή ξεκίνησε άλλη στο μεταξύ) κρατιέται ως η τελευταία ή η προηγούμενη.
     */
    fun restorePhone(w: LiveSession) {
        val known = listOfNotNull(phone, lastPhone).firstOrNull { it.id == w.id }
        if (known != null) {
            mergeWatchEdits(w, known)
            return
        }
        val lp = lastPhone
        if (lp == null) {
            lastPhone = w
            lastPhoneId = w.id
        } else {
            endedPhone = w
        }
    }

    /**
     * Πόσο κρατά όλο το διάλειμμα της προπόνησης του κινητού (για το δαχτυλίδι, W2-20): ίδιο διάλειμμα → ίδιο· «+30″» →
     * + όσο μεγάλωσε· νέο → από τώρα ως το τέλος του.
     */
    fun phoneRestLen(prev: LiveSession?, s: LiveSession, now: Long): Long = when {
        s.restEnd <= now -> 0
        prev != null && prev.restEnd == s.restEnd -> prev.restLen
        prev != null && prev.restEnd > now && prev.restLen > 0 && s.restEnd > prev.restEnd -> prev.restLen + (s.restEnd - prev.restEnd)
        prev != null && prev.restEnd > now && prev.restLen > 0 && s.restEnd > now && prev.restEnd - s.restEnd < 3_000 -> prev.restLen
        else -> {
            // Νέο διάλειμμα: από την ώρα του ✓ που το ξεκίνησε, αν το κινητό τη στέλνει (S3)· αλλιώς από τώρα.
            val at = s.items.maxOfOrNull { it.sets.maxOfOrNull { x -> if (x.done) x.at else 0L } ?: 0L } ?: 0L
            if (at in 1..now && s.restEnd - at in 1..15 * 60_000L) s.restEnd - at else s.restEnd - now
        }
    }

    fun resetExercise() {
        running = null
        runningPhone = false
        runningSid = null
        startedAt = 0
        startedEl = 0
        bpm = 0
        bpmAt = 0
        bpmEl = 0
        hr = null
        hrMode = ""
        hrGaps = GapMeter()
        hrQuality = HrQualityCount()
        meters = 0.0
        steps = 0
        stride = null
        kmDone = 0
        kmFlashUntil = 0
        kmFlashN = 0
        activeSec = 0
        cpActiveMs = 0
        cpWall = 0
        cpRunning = false
        gps = false
        paused = false
        pauses.clear()
        split = SplitTracker(0)
        recoveryUntil = 0
        endAt = 0
        alarmMutedUntil = 0
        steadyUntil = 0
        steadyUntilEl = 0
        hrSilent = null
        hrAvailable = null
        lastErr = null
        diag = ""
        restored = false
        alarmMutedEpisode = -1
        zoneAlarm.stop()
        zoneMuted = false
    }

    // ------------------------------------------------------------------ αντίγραφα ασφαλείας
    // 1) Άσκηση σε εξέλιξη: στιγμιότυπο ανά ~60″ και σε παύση/τέλος (αρχείο «run.json», ατομική εγγραφή). Αν η εφαρμογή
    //    κλείσει απότομα, στο επόμενο άνοιγμα συνεχίζει ή γράφεται ως μερική (έλεγχος 9/11, V-A-03).
    // 2) Αποτέλεσμα που δεν έφτασε ακόμα στο Data Layer: ένα ανά id («p:<id>»), στέλνεται στο επόμενο άνοιγμα (W3-17, V-A-13).
    private const val PREFS = "ygeia_watch"
    private const val PENDING = "pending"
    private const val PENDING_PREFIX = "p:"
    private const val RUN_FILE = "run.json"
    private const val LIMIT = "limit"

    /** Κλειδιά της παύσης μετά από «Σταμάτησα» (ως #84): σβήνονται μία φορά (απλοποίηση 9/11). */
    fun dropOldKeys(ctx: Context) {
        val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (sp.contains("symHoldAt") || sp.contains("pendingSym")) sp.edit().remove("symHoldAt").remove("pendingSym").apply()
    }

    /** Αποτέλεσμα που πρέπει να φτάσει στο κινητό· μένει ώσπου να μπει στο Data Layer ([removePending]). */
    fun savePending(ctx: Context, id: String, json: JSONObject): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(PENDING_PREFIX + id, json.toString()).commit()

    /**
     * Το στιγμιότυπο της άσκησης σβήνεται ΜΟΝΟ αν το αποτέλεσμα γράφτηκε στην αναμονή (έλεγχος 13/11, S8-08). [save]: η
     * εγγραφή ([savePending], false π.χ. με γεμάτο χώρο)· [clear]: το σβήσιμο ([clearRun]). Πριν, το στιγμιότυπο σβηνόταν
     * ό,τι κι αν απαντούσε η εγγραφή: με γεμάτο χώρο το αποτέλεσμα έμενε μόνο στη μνήμη. Επιστρέφει αν γράφτηκε.
     */
    fun storeResultThenClear(save: () -> Boolean, clear: () -> Unit): Boolean {
        val saved = save()
        if (saved) clear()
        return saved
    }

    fun removePending(ctx: Context, id: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(PENDING_PREFIX + id).commit()
    }

    /** Όλα τα αποτελέσματα σε αναμονή (id → JSON). Και το παλιό ένα «pending» (ως #90), με id ακόμα και για «hr» (V-A-13). */
    fun pendingAll(ctx: Context): List<Pair<String, JSONObject>> {
        val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        sp.getString(PENDING, null)?.let { legacy ->
            val o = try { JSONObject(legacy) } catch (_: Exception) { null }
            val id = o?.let { pendingId(it) }
            val e = sp.edit().remove(PENDING)
            if (o != null && id != null) e.putString(PENDING_PREFIX + id, legacy)
            e.commit()
        }
        val out = mutableListOf<Pair<String, JSONObject>>()
        for ((k, v) in sp.all) {
            if (!k.startsWith(PENDING_PREFIX) || v !is String) continue
            val o = try { JSONObject(v) } catch (_: Exception) { null } ?: continue
            out.add(k.removePrefix(PENDING_PREFIX) to o)
        }
        return out
    }

    /** Το id (όνομα του DataItem) ενός αποτελέσματος: «id», ή για τους παλμούς προπόνησης του κινητού «hr<sid>». */
    fun pendingId(o: JSONObject): String? {
        val id = o.optString("id", "")
        if (id.isNotEmpty()) return id
        val sid = o.optString("sid", "")
        return if (o.optString("kind") == "hr" && sid.isNotEmpty()) "hr$sid" else null
    }

    /** Το τελευταίο όριο από το κινητό, για επόμενες εκκινήσεις. */
    fun rememberLimit(ctx: Context, limit: Int?) {
        knownLimit = limit
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putInt(LIMIT, limit ?: 0).apply()
    }

    fun loadLimit(ctx: Context) {
        if (plan != null) return
        val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (sp.contains(LIMIT)) knownLimit = sp.getInt(LIMIT, 0).takeIf { it > 0 }
    }

    // ------------------------------------------------------------------ στιγμιότυπο άσκησης (V-A-03)
    /** Όλη η κατάσταση της άσκησης που τρέχει, για το στιγμιότυπο· null αν δεν τρέχει καμία. */
    fun captureRun(now: Long): JSONObject? {
        val kind = running ?: return null
        val pz = JSONArray()
        for (p in pauses) pz.put(JSONArray().put(p[0]).put(p[1]))
        val o = JSONObject().put("v", 1).put("kind", kind).put("phone", runningPhone).put("start", startedAt).put("saved", now)
            .put("sec", activeSecNow(now)).put("cpA", cpActiveMs).put("cpW", cpWall).put("cpR", cpRunning)
            .put("m", finite(meters)).put("steps", steps).put("gps", gps).put("paused", paused).put("pz", pz)
            .put("split", split.toState()).put("endAt", endAt).put("recUntil", recoveryUntil).put("hrMode", hrMode)
            // 14/11: ποιο χιλιόμετρο ειπώθηκε (να μην ξαναειπωθεί μετά από συνέχεια) και το μήκος βήματος της άσκησης.
            .put("kmD", kmDone)
        stride?.let { o.put("stride", it) }
        alarm.limit?.let { o.put("lim", it) }
        // Έλεγχος 14/11, round 9 (R9-A7-2): και η ζώνη του περπατήματος (νέο, προαιρετικό πεδίο του run.json), όπως το όριο:
        // ένα μερικό αποτέλεσμα γράφεται με τη ζώνη που ίσχυε, όχι με όποια έχει το κινητό τη μέρα της εισαγωγής.
        zoneAlarm.zone?.let { o.put("zone", it.toJson()) }
        hr?.let { o.put("hr", it.toState()) }
        local?.let { o.put("local", it.toState()) }
        runningSid?.let { o.put("sid", it) }
        // R7-A8-1: σε προπόνηση του κινητού και ό,τι ξέρει το ρολόι γι' αυτήν (✓, επαναλήψεις, ρεζέρβα που δεν έφτασαν ακόμα).
        if (runningPhone) phoneById(runningSid)?.let { o.put("pp", LiveSession.phoneWatchState(it)) }
        return o
    }

    /** Η άσκηση από το στιγμιότυπο, στη μνήμη (μετά από απότομο κλείσιμο). false αν δεν διαβάζεται. */
    fun restoreRun(o: JSONObject, nowWall: Long, nowEl: Long): Boolean = try {
        val start = o.getLong("start")
        resetExercise()
        running = o.getString("kind")
        runningPhone = o.optBoolean("phone", false)
        runningSid = o.optStringOrNull("sid")
        startedAt = start
        // Η αναμονή των 30″ για τον «πρώτο» παλμό ξεκινά από τη συνέχεια, όχι από την αρχική έναρξη: αλλιώς μόλις συνεχίσει
        // θα δονούσε «κανένας παλμός» πριν προλάβει να έρθει ο πρώτος (έλεγχος του #91, S2).
        startedEl = nowEl
        hr = o.optJSONObject("hr")?.let { HrStats.fromState(it) } ?: HrStats(start)
        activeSec = o.optLong("sec", 0)
        cpActiveMs = o.optLong("cpA", 0)
        cpWall = o.optLong("cpW", 0)
        cpRunning = o.optBoolean("cpR", false)
        meters = o.optDouble("m", 0.0).takeIf { it.isFinite() } ?: 0.0
        steps = o.optLong("steps", 0)
        gps = o.optBoolean("gps", false)
        kmDone = o.optInt("kmD", 0)
        stride = strideOrNull(o.optDouble("stride", Double.NaN))
        paused = o.optBoolean("paused", false)
        o.optJSONArray("pz")?.let { a -> for (i in 0 until a.length()) a.optJSONArray(i)?.let { pauses.add(longArrayOf(it.getLong(0), it.getLong(1))) } }
        split = o.optJSONObject("split")?.let { SplitTracker.fromState(it, start) } ?: SplitTracker(start)
        endAt = o.optLong("endAt", 0)
        recoveryUntil = o.optLong("recUntil", 0)
        hrMode = o.optString("hrMode", "")
        alarm.limit = if (o.has("lim")) o.getInt("lim") else null
        alarm.reset()
        // R9-A7-2: η ζώνη που ίσχυε στο περπάτημα ([captureRun]). Στιγμιότυπο χωρίς «zone» (έκδοση ως #107): καμία, όπως πριν.
        if (running == "walk") zoneAlarm.zone = WalkZone.parse(o.optJSONObject("zone"))
        o.optJSONObject("local")?.let { local = LiveSession.fromState(it) }
        // R7-A8-1: τα ✓ / οι επαναλήψεις / η ρεζέρβα του ρολογιού στην προπόνηση του κινητού που δεν είχαν φτάσει εκεί.
        if (runningPhone) o.optJSONObject("pp")?.let { LiveSession.phoneFromWatchState(it) }?.takeIf { it.id == runningSid }?.let { restorePhone(it) }
        restored = true
        true
    } catch (_: Exception) {
        resetExercise()
        false
    }

    private fun runFile(ctx: Context) = File(ctx.filesDir, RUN_FILE)

    /**
     * «Γενιά» του στιγμιότυπου (έλεγχος του #91, S3): αλλάζει σε κάθε [clearRun]. Μια εγγραφή που ετοιμάστηκε πριν από το
     * τέλος της άσκησης και φτάνει μετά ([writeRun] σε άλλο νήμα) δεν γράφει τίποτα: μια τελειωμένη άσκηση δεν «ξαναζεί».
     */
    @Volatile
    var runGen = 0L
        private set

    /** Ατομική εγγραφή (προσωρινό αρχείο + μετονομασία): ποτέ μισό αρχείο. Σε νήμα εκτός οθόνης. Μόνο αν [gen] ισχύει ακόμα. */
    fun writeRun(ctx: Context, text: String, gen: Long = runGen): Boolean = synchronized(this) {
        if (gen != runGen) return@synchronized false
        try {
            val f = runFile(ctx)
            val tmp = File(f.parentFile, "$RUN_FILE.tmp")
            FileOutputStream(tmp).use { out ->
                out.write(text.toByteArray(Charsets.UTF_8))
                out.flush()
                out.fd.sync()
            }
            tmp.renameTo(f)
        } catch (_: Exception) {
            false
        }
    }

    fun readRun(ctx: Context): JSONObject? = synchronized(this) {
        try {
            val f = runFile(ctx)
            if (!f.exists()) null else JSONObject(f.readText())
        } catch (_: Exception) {
            null
        }
    }

    fun clearRun(ctx: Context) {
        synchronized(this) {
            runGen++
            try {
                runFile(ctx).delete()
            } catch (_: Exception) {
            }
        }
    }

    /** Στιγμιότυπο που δεν διαβάζεται/δεν γίνεται αποτέλεσμα: μετονομάζεται σε «run.bad.json» (κρατιέται, δεν σβήνεται, S4). */
    fun quarantineRun(ctx: Context) {
        synchronized(this) {
            runGen++
            try {
                val f = runFile(ctx)
                var bad = File(ctx.filesDir, "run.bad.json")
                if (bad.exists()) bad = File(ctx.filesDir, "run.${System.currentTimeMillis()}.bad.json")
                if (f.exists() && !f.renameTo(bad)) f.delete()
            } catch (_: Exception) {
            }
        }
    }

    /** Το id (όνομα DataItem) που θα έχει το αποτέλεσμα της άσκησης του στιγμιότυπου [o], ή null. */
    fun runId(o: JSONObject): String? {
        val start = o.optLong("start", 0)
        return when {
            o.optString("kind") == "walk" && start > 0 -> "walk$start"
            o.optBoolean("phone", false) -> o.optStringOrNull("sid")?.let { "hr$it-$start" }
            else -> o.optJSONObject("local")?.optStringOrNull("id")
        }
    }

    /** Υπάρχει ήδη στην αναμονή το ΚΑΝΟΝΙΚΟ (όχι μερικό) αποτέλεσμα [id]: η άσκηση έχει τελειώσει (S3). */
    fun hasFinalPending(ctx: Context, id: String): Boolean {
        val v = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(PENDING_PREFIX + id, null) ?: return false
        return try {
            JSONObject(v).optInt("partial", 0) != 1
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Το στιγμιότυπο [o] ως μερικό αποτέλεσμα (ίδιο id με το κανονικό, «partial»), στην αναμονή. Ποτέ: πάνω σε κανονικό που
     * περιμένει ακόμα (S3)· ποτέ εξαίρεση (S4): ό,τι δεν διαβάζεται κρατιέται στο «run.bad.json» με μήνυμα. Η άσκηση που
     * ετοιμάζεται τώρα (π.χ. η νέα προπόνηση του ρολογιού) δεν πειράζεται. Επιστρέφει το αποτέλεσμα για αποστολή, ή null.
     */
    fun finalizeRun(ctx: Context, o: JSONObject, now: Long, nowEl: Long): Pair<String, JSONObject>? {
        val keepLocal = local
        local = null
        try {
            val id = runId(o)
            if (id != null && hasFinalPending(ctx, id)) {
                clearRun(ctx)
                return null
            }
            if (!restoreRun(o, now, nowEl)) {
                quarantineRun(ctx)
                notice = BAD_RUN_NOTICE
                return null
            }
            val r = Results.build(now, partialAt = o.optLong("saved", now))
            if (r != null && hasFinalPending(ctx, r.first)) {
                clearRun(ctx)
                return null
            }
            // S8-08: αν το μερικό αποτέλεσμα δεν γράφτηκε στην αναμονή, το στιγμιότυπο μένει (ξαναδοκιμάζεται στο επόμενο
            // άνοιγμα, με το ίδιο id). Το αποτέλεσμα επιστρέφεται έτσι κι αλλιώς, για να σταλεί τώρα αν γίνεται.
            if (r != null) storeResultThenClear({ savePending(ctx, r.first, r.second) }, { clearRun(ctx) })
            else clearRun(ctx)
            return r
        } catch (e: Exception) {
            android.util.Log.e("YgeiaWatch", "finalizeRun", e)
            quarantineRun(ctx)
            notice = BAD_RUN_NOTICE
            return null
        } finally {
            resetExercise()
            local = keepLocal
        }
    }

    /** Μήνυμα όταν ένα στιγμιότυπο δεν έγινε αποτέλεσμα (κρατιέται στο ρολόι, για να μη χαθεί). */
    const val BAD_RUN_NOTICE = "Μια άσκηση που είχε μείνει μισή δεν διαβάστηκε· κρατήθηκε στο ρολόι."
}
