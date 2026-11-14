package gr.ygeiaforma.wear

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.SystemClock
import android.text.TextPaint
import android.text.TextUtils
import android.view.HapticFeedbackConstants
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import kotlin.math.abs

/**
 * Όλες οι οθόνες του ρολογιού σε ένα View (στρογγυλή οθόνη, ζωγραφισμένη με Canvas: καμία βιβλιοθήκη UI).
 * Μεγέθη σε «u» = πλάτος/200, ώστε να ταιριάζει σε κάθε ρολόι.
 * Σχέδια Α–Ε (8/11): έναρξη, σετ, διάλειμμα, όριο παλμών, περπάτημα.
 */
class WatchView(context: Context, private val actions: Actions) : View(context) {

    interface Actions {
        fun startWorkout(id: String)
        fun startWalk()
        fun joinPhone()
        fun tick()
        fun answer(rir: Int)
        fun reps(delta: Int)
        fun nextExercise()
        fun restPlus()
        fun restStop()
        /** «Τέλος» της άσκησης (όχι Activity.finish(): το «Πίσω» δεν τελειώνει την άσκηση, V-A-17). */
        fun finishWorkout()
        fun pauseWalk(on: Boolean)
        fun muteAlarm()
        fun doneOk()
        /** Διόρθωση των επαναλήψεων του σετ που μόλις έγινε (στο διάλειμμα, RT-13). */
        fun lastReps(delta: Int)
        /** Η απάντηση στο «Τρέχει άσκηση σε άλλη εφαρμογή» ([otherAppAsk]· 13/11, Γ3): «Ξεκίνα εδώ» / «Άκυρο». */
        fun startHere() {}
        fun cancelStart() {}
    }

    /**
     * Γ3 (13/11): το ρολόι μετρά ΜΙΑ άσκηση τη φορά, για όλες τις εφαρμογές (Health Services). Αν τρέχει άσκηση άλλης
     * εφαρμογής (π.χ. Samsung Health) και ξεκινήσουμε εδώ, εκείνη σταματά χωρίς να ρωτηθεί ο χρήστης. Γι' αυτό πρώτα
     * ερώτηση, όπως ζητά η οδηγία του Android («ask the user for confirmation before overriding a previous exercise»).
     */
    var otherAppAsk = false

    private val orange = Color.parseColor("#EA580C")

    /**
     * Το πορτοκαλί ως ΦΟΝΤΟ κουμπιού με λευκά γράμματα (έλεγχος 13/11, U7-19): λευκό σε #EA580C = 3,56:1, κάτω από το
     * 4,5:1 που θέλουν γράμματα αυτού του μεγέθους (WCAG 2.1, 1.4.3)· σε #C2410C = 5,18:1. Το [orange] μένει για γράμματα
     * και δαχτυλίδι πάνω σε μαύρο (5,90:1).
     */
    private val orangeFill = Color.parseColor("#C2410C")
    private val green = Color.parseColor("#16A34A")
    private val red = Color.parseColor("#EF4444")
    private val alarmBg = Color.parseColor("#991B1B")

    /** Μικρά γράμματα πάνω στην κόκκινη οθόνη (U7-19): #FECACA σε #991B1B = 5,74:1 (πριν #FCA5A5 = 4,38:1). */
    private val alarmSoft = Color.parseColor("#FECACA")
    private val gray = Color.parseColor("#9CA3AF")
    private val dim = Color.parseColor("#374151")
    private val card = Color.parseColor("#1F2937")

    // Σχέδια 9/11 (7α–7γ): κουμπιά αρχικής, ανοιχτό «Τέλος», κεχριμπάρι «προσοχή», απαλό κόκκινο-σομόν για την καρδιά.
    private val button2 = Color.parseColor("#2B303B")
    private val button3 = Color.parseColor("#1C2028")
    private val light = Color.parseColor("#E8ECF4")
    private val ink = Color.parseColor("#0F172A")
    private val amber = Color.parseColor("#F2B13C")
    private val amberSoft = Color.parseColor("#F7D9A0")
    private val amberInk = Color.parseColor("#2A1A04")
    private val salmon = Color.parseColor("#F28B6C")
    private val zoneGreen = Color.parseColor("#9BE1A8")
    private val soft = Color.parseColor("#C7CDD8")

    /**
     * Μέγεθος γραμμάτων του ρολογιού (σχέδια 9/11): τα κείμενα της αρχικής, του περπατήματος και της οθόνης «δεν
     * έρχονται παλμοί» ακολουθούν τη ρύθμιση του ρολογιού, ως 1,3×.
     */
    private val fs: Float get() = resources.configuration.fontScale.coerceIn(1f, 1.3f)

    /**
     * Ελάχιστο μέγεθος για ό,τι χρειάζεται για ασφάλεια ή ενέργεια (έλεγχος γ2, W3-09): 10u ≈ 12 sp στο Ultra 2, και
     * μεγαλύτερο με το μέγεθος γραμμάτων του ρολογιού.
     */
    private fun ess(size: Float): Float = maxOf(size, 10f) * fs

    /**
     * «Δεν έρχονται παλμοί» με όριο γιατρού (σχέδια 9/11, 7γ): όλη η οθόνη, μία φορά για κάθε σιωπή. Μετά το
     * «Εντάξει» μένει «♥ —» σε κεχριμπάρι ώσπου να ξαναέρθουν παλμοί. Μόνο εμφάνιση· η δόνηση είναι όπως πριν.
     */
    var noHrSeen: Boolean
        get() = noHrSeenNow
        set(v) {
            noHrSeenNow = v
        }

    companion object {
        /** Κρατιέται και αν ξαναφτιαχτεί η οθόνη (π.χ. αλλαγή μεγέθους γραμμάτων), για να μη ξαναβγεί (N3). */
        @JvmStatic
        internal var noHrSeenNow = false

        // Γεωμετρία των μηνυμάτων, σε u (έλεγχος 13/11, U7-02…U7-08). Οι υπολογισμοί: fix/round1/f7.md.
        /** Μικρότερο μέγεθος γραμμάτων ενός μηνύματος πριν κοπεί με «…» (≈ 10 sp στο Ultra 2). */
        private const val NOTE_MIN = 8.5f
        /** Βάση του κάτω μηνύματος (αρχική, ρεζέρβα): μία γραμμή. */
        private const val NOTE_Y = 186f
        /** Βάση του κάτω μηνύματος στο σετ όταν χωρά σε μία γραμμή (κάτω από το ✓, που τελειώνει στα 168u). */
        private const val NOTE_SET_Y = 182f
        /** Βάση της πρώτης από τις δύο γραμμές μηνύματος στο σετ (το ✓ τελειώνει τότε στα 162u, U7-03). */
        private const val NOTE_SET_TWO_Y = 171f
        /** Περπάτημα: η λεζάντα της ζώνης / το μήνυμα, 1,5u πιο κάτω από πριν (U7-02), και το πλάτος της γραμμής. */
        private const val WALK_NOTE_Y = 136.5f
        private const val WALK_NOTE_W = 160f
        /** Διάλειμμα: πλάτος γραμμής στο ύψος του «επόμενο» (το δαχτυλίδι αφήνει 161u· 5u περιθώριο κάθε πλευρά). */
        private const val REST_LINE_W = 150f
        /** Πλάτος των κουμπιών της αρχικής (u). */
        private const val HOME_BUTTON_W = 144f
        /**
         * Η 2η γραμμή του κουμπιού της μέρας περπατήματος γράφεται ολόκληρη μόνο αν χωρά με αυτό το μέγεθος (R7-U3-03): έτσι,
         * και με γράμματα 1,3× (που μικραίνουν ανά 0,5u), δεν πέφτει ποτέ κάτω από 9u.
         */
        private const val HOME_SUB_MIN = 9.5f
    }

    private val text = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }

    /**
     * Κάτι που πατιέται ([run]) ή μόνο διαβάζεται από το TalkBack ([run] = null), με την περιγραφή του ([label]).
     * Έλεγχος γ2 (W3-09): πριν, το TalkBack δεν έβρισκε τίποτα στην οθόνη (ζωγραφισμένη σε ένα View).
     */
    private class Hit(val r: RectF, val label: String, val run: (() -> Unit)?)
    private val hits = mutableListOf<Hit>()

    /** Για το TalkBack: οι περιοχές της τελευταίας εικόνας (η πρώτη = τι δείχνει η οθόνη, μετά τα κουμπιά). */
    internal val a11yItems: List<Pair<String, Boolean>> get() = a11y.map { it.label to (it.run != null) }
    private var a11y: List<Hit> = emptyList()

    /** Τι δείχνει η οθόνη, σε μία φράση για το TalkBack (η πρώτη περιοχή). */
    private var say = ""

    /** Ένα κουμπί για το TalkBack ([index] στη σειρά του [a11yItems]): «πάτημα». */
    internal fun a11yClick(index: Int): Boolean {
        val h = a11y.getOrNull(index)?.run ?: return false
        byTap = true
        h()
        invalidate()
        return true
    }

    /**
     * Η προπόνηση που δείχνει η αρχική (μπορεί να αλλάξει με πάτημα στο όνομα). Ισχύει μόνο τη μέρα που διαλέχτηκε
     * ([chosenDay], [chosenToday]· έλεγχος 14/11, round 8, R8-U3-06).
     */
    var chosen: String? = null
        set(v) {
            field = v
            chosenDay = if (v == null) null else java.time.LocalDate.now()
        }

    /** Η μέρα που διαλέχτηκε το [chosen] (αλλάζει μόνο με αυτό· εδώ και στις δοκιμές). */
    internal var chosenDay: java.time.LocalDate? = null

    /** Χρόνος από την εκκίνηση της συσκευής (ms)· αλλάζει μόνο στις δοκιμές. */
    internal var clockEl: () -> Long = { SystemClock.elapsedRealtime() }

    /**
     * Φύλακας πατήματος (έλεγχος 13/11, S8-05): ποια οθόνη ζωγραφίστηκε τελευταία και πότε, αν η αλλαγή της ήρθε από
     * πάτημα εδώ, και πότε άλλαξε τελευταία ΜΟΝΗ της ([screenAutoChanged], [tapAllowed]). Η αχνή οθόνη (ambient) δεν μετρά.
     */
    private var lastKey = ""
    private var lastDrawEl = -1L
    private var autoChangedEl = -1L
    private var byTap = false

    /**
     * Το μήνυμα μέσα στην οθόνη (U7-06/U7-07): ποιο είδαμε τελευταία και από πότε φαίνεται ([noticeInline])· [shownNote]
     * είναι αυτό που ζωγραφίζεται τώρα μέσα στην οθόνη (null = κανένα) και [noteTwo] αν πιάνει δύο γραμμές (οθόνη σετ).
     */
    private var noteSeen: String? = null
    private var noteSeenEl = 0L
    private var shownNote: String? = null
    private var noteTwo = false

    /** Κείμενα που κόπηκαν με «…» στην τελευταία εικόνα (για τις δοκιμές: κανένα σταθερό κείμενο δεν κόβεται, U7-04). */
    internal val clipped = mutableListOf<String>()

    /**
     * Μόνο για τις δοκιμές (round 2, R2-U3-01/03): κάθε γραμμή που έγραψε το [t] στην τελευταία εικόνα → το μέγεθος (u) με το
     * οποίο ζωγραφίστηκε. Στο ρολόι μένει null: καμία δουλειά και καμία δέσμευση μνήμης ανά εικόνα.
     */
    internal var drawnSizes: MutableMap<String, Float>? = null

    /**
     * Ambient (αχνή οθόνη «πάντα ανοιχτή», έλεγχος 9/11, W3-08): μαύρο φόντο, μόνο λευκά/γκρι γράμματα χωρίς εξομάλυνση
     * (οθόνες με λίγα bit), καθόλου γεμάτα σχήματα ή κουμπιά, χρόνος σε λεπτά (ανανέωση μία φορά το λεπτό).
     */
    var ambient = false
        set(v) {
            if (field == v) return
            field = v
            text.isAntiAlias = !v
            invalidate()
        }

    private var u = 1f
    private var cx = 0f
    private var cy = 0f

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        // Η οθόνη παίρνει πια την εστίαση για τη στεφάνη (WatchActivity.onWindowFocusChanged, τελικός έλεγχος, Συμβούλιο 4,
        // W-6): χωρίς το «φωτισμένο» πλαίσιο εστίασης που ζωγραφίζει το Android πάνω σε προβολή με εστίαση.
        defaultFocusHighlightEnabled = false
    }

    override fun onDraw(c: Canvas) {
        hits.clear()
        clipped.clear()
        drawnSizes?.clear()
        say = ""
        markScreen(drawScreen(c))
        // Η πρώτη περιοχή για το TalkBack: τι δείχνει η οθόνη· μετά τα κουμπιά με τη σειρά που ζωγραφίστηκαν.
        val next = buildList {
            if (say.isNotEmpty()) add(Hit(RectF(0f, 0f, width.toFloat(), height * 0.3f), say, null))
            addAll(hits.filter { it.label.isNotEmpty() })
        }
        val changed = next.map { it.label } != a11y.map { it.label }
        a11y = next
        if (changed) {
            try {
                sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
            } catch (_: Exception) {
            }
        }
    }

    /**
     * S8-05: σημειώνει ποια οθόνη ζωγραφίστηκε ([key], κενό = αχνή οθόνη, δεν μετρά). Αν άλλαξε χωρίς πάτημα εδώ ενώ η
     * προηγούμενη φαινόταν ως πριν από λίγο, τα πατήματα αγνοούνται για [TAP_GUARD_MS].
     */
    private fun markScreen(key: String) {
        if (key.isEmpty()) return
        val nowEl = clockEl()
        if (key != lastKey) {
            if (screenAutoChanged(lastKey.isNotEmpty(), byTap, nowEl - lastDrawEl)) autoChangedEl = nowEl
            lastKey = key
        }
        lastDrawEl = nowEl
        byTap = false
    }

    /** Ζωγραφίζει την οθόνη και επιστρέφει ποια ήταν (για το [markScreen])· κενό για την αχνή οθόνη. */
    private fun drawScreen(c: Canvas): String {
        u = width / 200f
        cx = width / 2f
        cy = height / 2f
        shownNote = null
        noteTwo = false
        val now = System.currentTimeMillis()
        if (ambient) {
            c.drawColor(Color.BLACK)
            drawAmbient(c, now)
            return ""
        }
        val alarm = Repo.alarmShown(now)
        c.drawColor(if (alarm) alarmBg else Color.BLACK)
        if (alarm) {
            drawAlarm(c)
            return "alarm"
        }
        if (otherAppAsk) {
            drawOtherApp(c)
            return "ask"
        }
        val note = Repo.notice
        if (Repo.openNotice && note != null) {
            Repo.openNotice = false
            noticeOpen = true
        }
        val nowEl = clockEl()
        if (note != noteSeen) {
            noteSeen = note
            noteSeenEl = nowEl
            // Έλεγχος 13/11 (U7-04/U7-07): μήνυμα της υπηρεσίας που δεν χωρά ολόκληρο στη θέση του (ή, στο σετ, θα έκρυβε
            // το «Τέλος») ανοίγει ολόκληρο μία φορά, σε όλη την οθόνη, αντί να κοπεί με «…».
            if (note != null && !isBriefNotice(note) && !fitsInline(note)) noticeOpen = true
        }
        if (noticeOpen && note != null) {
            drawNotice(c, note)
            return "notice"
        }
        noticeOpen = false
        if (Repo.hrSilent == null) noHrSeen = false
        if (!noHrSeen && Repo.running != null && Repo.alarm.limit != null && Repo.hrSilent != null &&
            Repo.screen != Repo.Screen.HOME && Repo.screen != Repo.Screen.END && Repo.screen != Repo.Screen.RECOVER
        ) {
            drawNoHr(c)
            return "nohr"
        }
        // Το μήνυμα μέσα στην οθόνη: ως [NOTICE_INLINE_MS] από τη στιγμή που φάνηκε (U7-06/U7-07)· μετά δίνει πίσω τη θέση του
        // (λεζάντα ζώνης στο περπάτημα, «Τέλος» στο σετ). Στο «Αποθηκεύτηκε» γράφεται ολόκληρο από το [drawEnd]· στο λεπτό
        // αποκατάστασης δεν γράφεται (κάτω είναι η «Παράλειψη»).
        val slot = Repo.screen != Repo.Screen.END && Repo.screen != Repo.Screen.RECOVER
        val inNote = note?.takeIf { slot && noticeInline(nowEl - noteSeenEl) }
        // Φάνηκε όσο έπρεπε: φεύγει οριστικά (δεν ξαναβγαίνει αργότερα κάτω από το «Αποθηκεύτηκε»). Αν το ίδιο κείμενο
        // ξαναμπεί αργότερα, μετρά ως νέο.
        if (note != null && slot && inNote == null && Repo.notice == note) {
            Repo.notice = null
            noteSeen = null
        }
        shownNote = inNote
        noteTwo = inNote != null && Repo.screen == Repo.Screen.SET && !fitsSetLine(inNote)
        // Πάτημα στο μήνυμα: ολόκληρο (π.χ. η αιτία όταν δεν ξεκινά η μέτρηση· 9/11). Πρώτο στη λίστα, ώστε τα κουμπιά της
        // οθόνης να κερδίζουν όπου ακουμπούν· οι περιοχές του δεν τέμνουν κουμπιά (U7-08γ). Στο σετ, το «Πάτα ξανά…» χωρά
        // πάντα ολόκληρο και στη θέση του είναι το (αόρατο) «Τέλος»: εκεί μόνο για ανάγνωση (TalkBack), όχι δεύτερη
        // περιοχή πατήματος πάνω στην ίδια θέση.
        if (inNote != null) {
            if (Repo.screen == Repo.Screen.SET && isBriefNotice(inNote)) hits.add(Hit(noteHit(), inNote, null))
            else hits.add(Hit(noteHit(), inNote) { noticeOpen = true; invalidate() })
        }
        when (Repo.screen) {
            Repo.Screen.HOME -> drawHome(c)
            Repo.Screen.SET -> drawSet(c, now)
            Repo.Screen.RIR -> drawRir(c)
            Repo.Screen.REST -> drawRest(c, now)
            Repo.Screen.WALK -> drawWalk(c, now)
            Repo.Screen.RECOVER -> drawRecover(c, now)
            Repo.Screen.END -> drawEnd(c)
        }
        // Στο περπάτημα το μήνυμα γράφεται στη θέση της λεζάντας (κάτω είναι τα κουμπιά, έλεγχος γ2, Μ3/RT-18): μικραίνει
        // ώσπου να χωρέσει (U7-04). Στο διάλειμμα το γράφει το [drawRest], στη θέση του «επόμενο».
        if (inNote != null) {
            when (Repo.screen) {
                Repo.Screen.WALK -> small(c, inNote, WALK_NOTE_Y + (fs - 1f) * 8f, amber, ess(10f), WALK_NOTE_W, NOTE_MIN)
                Repo.Screen.REST -> {}
                else -> noteLines(c, inNote)
            }
        }
        return Repo.screen.name
    }

    /**
     * Η περιοχή πατήματος του μηνύματος ανά οθόνη, σε θέση που δεν τέμνει κανένα κουμπί (U7-08γ). Περπάτημα: η ζώνη από
     * τους παλμούς ως πάνω από τα κουμπιά (104–137u· τα κουμπιά πιάνουν από 137u). Διάλειμμα: ανάμεσα στα − / + (ως 135u)
     * και στα κάτω κουμπιά (από 147u). Σετ: κάτω από το ✓. Αλλού: η κάτω λωρίδα.
     */
    private fun noteHit(): RectF = when (Repo.screen) {
        Repo.Screen.WALK -> RectF(cx - 80 * u, 104 * u, cx + 80 * u, 137 * u)
        Repo.Screen.REST -> RectF(cx - 80 * u, 135 * u, cx + 80 * u, 147 * u)
        Repo.Screen.SET -> RectF(cx - 60 * u, (if (noteTwo) 163 else 169) * u, cx + 60 * u, 198 * u)
        else -> RectF(cx - 60 * u, 177 * u, cx + 60 * u, 198 * u)
    }

    /** Χωρά το [note] σε μία γραμμή στη θέση του κάτω μηνύματος του σετ, με γράμματα τουλάχιστον 10u; */
    private fun fitsSetLine(note: String): Boolean {
        text.typeface = Typeface.DEFAULT
        text.textSize = 10f * u
        return text.measureText(note) <= chordAt(NOTE_SET_Y, 10f) * u
    }

    /**
     * Χωρά το μήνυμα ολόκληρο μέσα στην οθόνη που φαίνεται τώρα (με το μικρότερο επιτρεπτό μέγεθος, [NOTE_MIN]); Στο σετ
     * ένα μήνυμα της υπηρεσίας δεν γράφεται ποτέ μέσα (θα έκρυβε το «Τέλος», U7-07): πάντα ολόκληρο, σε όλη την οθόνη.
     * Στο «Αποθηκεύτηκε» και στο λεπτό αποκατάστασης δεν ανοίγει τίποτα μόνο του.
     */
    private fun fitsInline(note: String): Boolean {
        val maxW = when (Repo.screen) {
            Repo.Screen.END, Repo.Screen.RECOVER -> return true
            Repo.Screen.SET -> return false
            Repo.Screen.WALK -> WALK_NOTE_W
            Repo.Screen.REST -> REST_LINE_W
            else -> chordAt(NOTE_Y, NOTE_MIN)
        }
        text.typeface = Typeface.DEFAULT
        text.textSize = NOTE_MIN * u
        return text.measureText(note) <= maxW * u
    }

    private var noticeOpen = false

    /**
     * Μήνυμα κάτω στη στρογγυλή οθόνη: μία γραμμή, ή στο σετ ως δύο (η κάτω πιο στενή): ολόκληρο το «Πάτα ξανά: τέλος και
     * στο κινητό» κ.λπ., όχι κομμένο στις άκρες (W3-09). Πάτημα: ολόκληρο, σε όλη την οθόνη.
     *
     * Έλεγχος 13/11 (U7-03): τα πλάτη βγαίνουν από τη χορδή του κύκλου στο ύψος κάθε γραμμής ([chordAt], 3u από την άκρη),
     * όχι από σταθερούς αριθμούς (η 2η γραμμή έφτανε ως την άκρη της οθόνης)· οι δύο γραμμές είναι 5u πιο ψηλά (171u και
     * 182u, με το ✓ να τελειώνει τότε στα 162u) και πάντα με γράμματα ως 10u (με 13u η 2η δεν χωρά σε καμία θέση). Αν μια
     * γραμμή δεν χωρά, μικραίνουν και οι δύο ως [NOTE_MIN]· μόνο μετά κόβεται με «…».
     */
    private fun noteLines(c: Canvas, note: String) {
        text.typeface = Typeface.DEFAULT
        val set = Repo.screen == Repo.Screen.SET
        val y = if (set) NOTE_SET_Y else NOTE_Y
        // 1) Μία γραμμή, στο μεγαλύτερο μέγεθος (από το μέγεθος του ρολογιού ως 10u) που χωρά.
        var sz = ess(10f)
        while (true) {
            text.textSize = sz * u
            if (text.measureText(note) <= chordAt(y, sz) * u) {
                small(c, note, y, soft, sz, chordAt(y, sz), sz)
                return
            }
            if (sz <= 10f) break
            sz = maxOf(10f, sz - 0.5f)
        }
        if (!set) {
            // Εκτός σετ δεν υπάρχει χώρος για δεύτερη γραμμή: μικραίνει ως το ελάχιστο και, αν χρειαστεί, κόβεται.
            small(c, note, y, soft, 10f, chordAt(y, 10f), NOTE_MIN)
            return
        }
        // 2) Δύο γραμμές (μόνο στο σετ· εκεί κάτω είναι μόνο το «Τέλος», που κρύβεται όσο φαίνεται το μήνυμα). Πού σπάει:
        // [twoLineSplit] (round 2, R2-U3-03: μετά το «:» όταν χωρά, όχι μία λέξη μόνη της στη 2η γραμμή).
        val words = note.split(' ')
        sz = 10f
        while (true) {
            text.textSize = sz * u
            val y2 = NOTE_SET_TWO_Y + sz * 1.1f
            val w1 = minOf(124f, chordAt(NOTE_SET_TWO_Y, sz))
            val w2 = chordAt(y2, sz)
            val (best, fits) = twoLineSplit(words, { s -> text.measureText(s) / u }, w1, w2)
            if (fits || sz <= NOTE_MIN) {
                small(c, words.take(best).joinToString(" "), NOTE_SET_TWO_Y, soft, sz, w1, sz)
                small(c, words.drop(best).joinToString(" "), y2, soft, sz, w2, sz)
                return
            }
            sz = maxOf(NOTE_MIN, sz - 0.5f)
        }
    }

    /** Ambient: τα βασικά μόνο, λευκό/γκρι σε μαύρο, χωρίς δευτερόλεπτα. Δεν πατιέται τίποτα. */
    private fun drawAmbient(c: Canvas, now: Long) {
        val light = Color.WHITE
        val dimText = Color.parseColor("#8A8A8A")
        when {
            Repo.running == "walk" -> {
                small(c, if (Repo.paused) "ΠΑΥΣΗ" else "ΠΕΡΠΑΤΗΜΑ", 56f, dimText, 9f, 120f)
                val sec = Repo.activeSecNow(now).let { if (it > 0) it else (now - Repo.startedAt) / 1000 }
                // Έλεγχος 13/11, round 7 (R7-U3-08): ο αριθμός μεγάλος και η λέξη από κάτω («24» / «λεπτά»), όπως το
                // κινητό (U5-06), όχι «24′».
                val min = (sec / 60).toInt()
                t(c, "$min", 98f, light, 30f, true)
                small(c, if (min == 1) "λεπτό" else "λεπτά", 111f, dimText, 11f, 120f)
                if (Repo.meters > 0) small(c, "${km(Repo.meters)} km", 128f, light, 11f, 150f)
                Repo.alarm.limit?.let { small(c, "όριο παλμών $it", 147f, dimText, 9f, 130f) }
            }
            Repo.session != null && Repo.running != null -> {
                val s = Repo.session!!
                val it = s.current
                small(c, s.name, 64f, dimText, 9f, 140f)
                if (it != null) {
                    t(c, it.name, 96f, light, 12f, true)
                    val si = it.nextSet.let { n -> if (n < 0) it.sets.size - 1 else n }
                    small(c, "ΣΕΤ ${si + 1}/${it.sets.size}", 118f, dimText, 9f, 120f)
                }
                // Σε ολόκληρες λέξεις («23 λεπτά», R7-U3-08).
                if (Repo.startedAt > 0) small(c, countText(((now - Repo.startedAt) / 60_000).toInt(), "λεπτό", "λεπτά"), 142f, light, 11f, 120f)
            }
            else -> {
                t(c, "Υγεία & Φόρμα", 100f, dimText, 11f, true)
            }
        }
    }

    /**
     * Ολόκληρο το μήνυμα, σε πολλές γραμμές· πάτημα οπουδήποτε κλείνει.
     *
     * Έλεγχος 13/11, round 2 (R2-U3-02): κάτω γράφει πια «πάτα για να κλείσει», ίδια φράση, θέση και μέγεθος με την κόκκινη
     * οθόνη του ορίου ([closeHint]). Πριν δεν έλεγε πώς κλείνει, και στο σετ ανοίγει έτσι ΚΑΘΕ μήνυμα της υπηρεσίας (π.χ.
     * «Τρέχει ακόμα η προπόνηση; … πάτα «Τέλος»», με το «Τέλος» κρυμμένο από πίσω): ο χρήστης έψαχνε κουμπί ή έσερνε προς
     * τα δεξιά (= «Πίσω» του ρολογιού, έξω από την εφαρμογή). Το κείμενο μένει στη μέση· μόνο αν είναι τόσο μακρύ που θα
     * έφτανε στη φράση, ανεβαίνει όσο χρειάζεται (3u κενό πάνω από τους τόνους της).
     */
    private fun drawNotice(c: Canvas, note: String) {
        text.color = Color.WHITE
        text.textSize = ess(10f) * u
        text.typeface = Typeface.DEFAULT
        val w = (150f * u).toInt()
        val tp = android.text.TextPaint(text).apply { textAlign = Paint.Align.LEFT }
        val layout = android.text.StaticLayout.Builder.obtain(note, 0, note.length, tp, w)
            .setAlignment(android.text.Layout.Alignment.ALIGN_CENTER)
            .setMaxLines(9)
            .build()
        val bottom = (closeY() - 0.86f * ess(10f) - 3f) * u
        c.save()
        c.translate(cx - w / 2f, minOf(cy - layout.height / 2f, bottom - layout.height))
        layout.draw(c)
        c.restore()
        closeHint(c, gray)
        say = note
        // Κλείσιμο = διαβάστηκε: το μήνυμα δεν μένει μετά μέσα στην οθόνη (εκεί θα έκρυβε τη λεζάντα ζώνης ή το «Τέλος»,
        // U7-06/U7-07). Ό,τι πρέπει να φαίνεται μόνιμα έχει δική του ένδειξη («χωρίς GPS», «♥ δεν μετριούνται»).
        hits.add(Hit(RectF(0f, 0f, width.toFloat(), height.toFloat()), "Κλείσιμο") {
            noticeOpen = false
            if (Repo.notice == note) {
                Repo.notice = null
                noteSeen = null
            }
            invalidate()
        })
    }

    /** Γ3: ερώτηση πριν σταματήσει η άσκηση άλλης εφαρμογής. Κείμενα εγκεκριμένα 12/11 ([OtherAppAsk]). */
    private fun drawOtherApp(c: Canvas) {
        text.color = Color.WHITE
        text.textSize = ess(10f) * u
        text.typeface = Typeface.DEFAULT
        val w = (150f * u).toInt()
        val tp = android.text.TextPaint(text).apply { textAlign = Paint.Align.LEFT }
        val layout = android.text.StaticLayout.Builder.obtain(OtherAppAsk.TEXT, 0, OtherAppAsk.TEXT.length, tp, w)
            .setAlignment(android.text.Layout.Alignment.ALIGN_CENTER)
            .setMaxLines(4)
            .build()
        c.save()
        c.translate(cx - w / 2f, 74f * u - layout.height / 2f)
        layout.draw(c)
        c.restore()
        say = OtherAppAsk.TEXT
        // Περιοχές πατήματος ≥ 40u (≈ 48 dp) που δεν ακουμπούν: «Ξεκίνα εδώ» 110–154u, «Άκυρο» 157–198u.
        pill(c, OtherAppAsk.YES, 132f, 116f, 32f, orangeFill, Color.WHITE, 13f * fs, padTop = 6f, padBottom = 6f) { actions.startHere() }
        pill(c, OtherAppAsk.NO, 176f, 68f, 28f, button3, soft, ess(10f), padTop = 5f, padBottom = 8f) { actions.cancelStart() }
    }

    // ------------------------------------------------------------------ βοηθητικά
    /**
     * Μία κεντραρισμένη γραμμή που χωρά πάντα στο [maxW] (u). Έλεγχος 13/11 (U7-04): πριν κοβόταν με TextUtils.ellipsize,
     * που στις δοκιμές (Robolectric) ΔΕΝ μετρά το πραγματικό πλάτος: τα στιγμιότυπα έδειχναν ολόκληρο ό,τι στο ρολόι
     * κοβόταν με «…». Τώρα μετριέται με την ίδια γραμματοσειρά που ζωγραφίζει (στιγμιότυπο = ρολόι): πρώτα μικραίνει ως
     * το [minSize] (αν δεν δοθεί: ως το 70% του μεγέθους, όχι κάτω από 8,5u) και μόνο αν ούτε τότε χωρά κόβεται με «…».
     */
    private fun t(c: Canvas, s: String, y: Float, color: Int, size: Float, bold: Boolean = false, maxW: Float = 150f, minSize: Float = 0f) {
        text.color = color
        text.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        val floor = minOf(size, if (minSize > 0f) minSize else maxOf(NOTE_MIN, size * 0.7f))
        var sz = size
        text.textSize = sz * u
        while (sz > floor && text.measureText(s) > maxW * u) {
            sz = maxOf(floor, sz - 0.5f)
            text.textSize = sz * u
        }
        drawnSizes?.put(s, sz)
        c.drawText(clip(s, maxW * u), cx, y * u, text)
    }

    /**
     * Το [s] όπως χωρά σε [maxPx] με τη γραμματοσειρά που έχει τώρα το [text]: ολόκληρο, αλλιώς κομμένο με «…» (μετρημένο
     * με measureText/breakText, U7-04). Ό,τι κόπηκε σημειώνεται στο [clipped], για τις δοκιμές.
     */
    private fun clip(s: String, maxPx: Float): String {
        if (text.measureText(s) <= maxPx) return s
        clipped.add(s)
        val dots = "…"
        val room = maxPx - text.measureText(dots)
        if (room <= 0f) return dots
        val n = text.breakText(s, true, room, null)
        return s.substring(0, n.coerceIn(0, s.length)).trimEnd() + dots
    }

    /** Κείμενο που μικραίνει ώσπου να χωρέσει (π.χ. «πράσινο + μπλε (50 lb)» στη θέση των κιλών). */
    private fun fit(c: Canvas, s: String, y: Float, color: Int, size: Float, maxW: Float) {
        text.typeface = Typeface.DEFAULT_BOLD
        text.color = color
        var sz = size
        text.textSize = sz * u
        while (text.measureText(s) > maxW * u && sz > 9f) {
            sz -= 1f
            text.textSize = sz * u
        }
        c.drawText(clip(s, maxW * u), cx, y * u, text)
    }

    private fun small(c: Canvas, s: String, y: Float, color: Int, size: Float, maxW: Float, minSize: Float = 0f) =
        t(c, s, y, color, size, false, maxW, minSize)

    private fun pill(
        c: Canvas, label: String, y: Float, w: Float, h: Float, bg: Int, fg: Int, size: Float = 12f,
        desc: String = label, padTop: Float = 6f, padBottom: Float = 6f, padSide: Float = 6f, run: () -> Unit,
    ) {
        val r = RectF(cx - w * u / 2, (y - h / 2) * u, cx + w * u / 2, (y + h / 2) * u)
        fill.color = bg
        c.drawRoundRect(r, h * u / 2, h * u / 2, fill)
        text.color = fg
        text.textSize = size * u
        text.typeface = Typeface.DEFAULT_BOLD
        c.drawText(label, cx, r.centerY() - (text.descent() + text.ascent()) / 2, text)
        // Λίγο μεγαλύτερη περιοχή πατήματος από το σχήμα (δάχτυλο σε μικρή οθόνη).
        hits.add(Hit(RectF(r.left - padSide * u, r.top - padTop * u, r.right + padSide * u, r.bottom + padBottom * u), desc, run))
    }

    /**
     * Κουμπί-χάπι σε θέση [x]. Η περιοχή πατήματος είναι λίγο μεγαλύτερη από το σχήμα: 3u δεξιά-αριστερά (έλεγχος 13/11,
     * U7-08: με 4u οι περιοχές διπλανών κουμπιών έπεφταν η μία πάνω στην άλλη και το κενό ανάμεσα «χαριζόταν» στο
     * τελευταίο) και [padTop]/[padBottom] πάνω-κάτω.
     */
    private fun pillAt(
        c: Canvas, label: String, x: Float, y: Float, w: Float, h: Float, bg: Int, fg: Int, size: Float, desc: String = label,
        padTop: Float = 6f, padBottom: Float = 6f, run: () -> Unit,
    ) {
        val r = RectF((x - w / 2) * u, (y - h / 2) * u, (x + w / 2) * u, (y + h / 2) * u)
        fill.color = bg
        c.drawRoundRect(r, h * u / 2, h * u / 2, fill)
        text.color = fg
        text.textSize = size * u
        text.typeface = Typeface.DEFAULT_BOLD
        c.drawText(label, r.centerX(), r.centerY() - (text.descent() + text.ascent()) / 2, text)
        hits.add(Hit(RectF(r.left - 3 * u, r.top - padTop * u, r.right + 3 * u, r.bottom + padBottom * u), desc, run))
    }

    /**
     * Κουμπί − / + (έλεγχος γ2, W3-09): κύκλος [d] u και περιοχή πατήματος [hw]×[hh] u (≥ 40u ≈ 48 dp), ως την άκρη της
     * οθόνης προς τα έξω, ώστε να μην ακουμπά το ✓.
     */
    private fun roundKey(c: Canvas, label: String, x: Float, y: Float, d: Float, hw: Float, hh: Float, desc: String, run: () -> Unit) {
        fill.color = card
        c.drawCircle(x * u, y * u, d * u / 2, fill)
        text.color = Color.WHITE
        text.textSize = d * 0.62f * u
        text.typeface = Typeface.DEFAULT_BOLD
        c.drawText(label, x * u, y * u - (text.descent() + text.ascent()) / 2, text)
        val left = if (x < 100f) 0f else (x - hw / 2) * u
        val right = if (x < 100f) (x + hw / 2) * u else width.toFloat()
        hits.add(Hit(RectF(left, (y - hh / 2) * u, right, (y + hh / 2) * u), desc, run))
    }

    private fun heart(c: Canvas, y: Float, now: Long, size: Float = 12f) {
        val fresh = Repo.hrLive(now)
        val over = fresh && Repo.alarm.limit != null && Repo.bpm >= Repo.alarm.limit!!
        if (!fresh && Repo.running != null) {
            // Έλεγχος 13/11, round 7 (R7-U3-05): στα πρώτα 30″, πριν έρθει ο πρώτος παλμός, «περιμένω παλμούς» σε γκρι (ίδια
            // φράση με το κινητό), όχι «δεν μετριούνται» που μοιάζει με βλάβη σε κάθε έναρξη.
            if (hrWaiting(Repo.hrSilent != null, Repo.bpmAt, Repo.startedAt, now)) {
                t(c, HR_WAIT_TEXT, y, gray, ess(size * 0.75f), true)
                sayAdd("Περιμένω παλμούς")
                return
            }
            // Δεν φτάνουν τιμές: να φαίνεται, όχι μια παύλα που μοιάζει με «όλα καλά».
            t(c, "♥ δεν μετριούνται", y, if (Repo.alarm.limit != null) amber else gray, ess(size * 0.75f), true)
            // Με όριο γιατρού (έλεγχος 9/11, V-A-04): ξεκάθαρα ότι το όριο δεν σε προσέχει τώρα. Μόνο μετά την αναμονή (ίδια
            // στιγμή με τη δόνηση και με το κινητό), όχι στα πρώτα δευτερόλεπτα κάθε έναρξης.
            val off = Repo.alarm.limit != null && Repo.hrSilent != null
            if (off) t(c, "το όριο δεν σε προσέχει", y + ess(10f) * 1.05f, amber, ess(10f), false, 150f)
            sayAdd(if (off) "Δεν μετριούνται παλμοί. Το όριο δεν σε προσέχει." else "Δεν μετριούνται παλμοί.")
            return
        }
        val s = if (fresh) "♥ ${Repo.bpm}" else "♥ —"
        t(c, s, y, if (over) red else if (fresh) Color.WHITE else gray, size * fs, true)
        if (fresh) sayAdd("Παλμοί ${Repo.bpm}" + (Repo.alarm.limit?.let { ", όριο $it" } ?: ""))
        if (fresh) {
            // Μικρή γραμμή με το όριο του γιατρού κάτω από τους παλμούς.
            val lim = Repo.alarm.limit ?: return
            val w = 60f
            val x0 = cx - w * u / 2
            val yy = (y + 4) * u
            fill.color = dim
            c.drawRoundRect(RectF(x0, yy, x0 + w * u, yy + 2.4f * u), u, u, fill)
            val lo = 60f
            val hi = lim + 20f
            val p = ((Repo.bpm - lo) / (hi - lo)).coerceIn(0f, 1f)
            fill.color = if (over) red else orange
            c.drawRoundRect(RectF(x0, yy, x0 + w * u * p, yy + 2.4f * u), u, u, fill)
            val lp = ((lim - lo) / (hi - lo)).coerceIn(0f, 1f)
            fill.color = Color.WHITE
            c.drawRect(RectF(x0 + w * u * lp - 0.6f * u, yy - 1.5f * u, x0 + w * u * lp + 0.6f * u, yy + 3.9f * u), fill)
        }
    }

    /** Προσθήκη στη φράση του TalkBack για αυτή την οθόνη. */
    private fun sayAdd(x: String) {
        say = if (say.isEmpty()) x else "$say. $x"
    }

    // ------------------------------------------------------------------ Α. έναρξη
    private fun drawHome(c: Canvas) {
        // Έλεγχος 14/11, round 8 (R8-A8-1): μια προπόνηση με βάρη κλείνει ακόμα (το κινητό την τελείωσε, το ρολόι γράφει
        // τους παλμούς της): όχι η αρχική με κουμπιά έναρξης ως τότε (λίγα δευτερόλεπτα).
        if (Repo.running != null && Repo.running != "walk" && Repo.session == null) return drawClosing(c)
        val plan = Repo.plan
        val phone = Repo.phone
        // Πρόγραμμα από νεότερη έκδοση του κινητού (V-A-08): δεν διαβάστηκε. Έλεγχος 13/11 (S8-03/U7-01): το μήνυμα γράφεται
        // πια σε θέση που δεν την καλύπτει κανένα κουμπί ([updateNote])· πριν ζωγραφιζόταν κάτω από το τρίτο κουμπί.
        val upd = Repo.updateNeeded
        if (upd) sayAdd("Ενημέρωσε την εφαρμογή στο ρολόι")
        val nowHome = System.currentTimeMillis()
        // Έλεγχος 13/11, round 7 (R7-A8-3, αίτημα του f2): μια προπόνηση του κινητού που μοιάζει ξεχασμένη ([phoneStale], 3 ώρες
        // χωρίς κίνηση) δεν κρύβει την κανονική αρχική και δεν προτείνει «Παλμοί εδώ»· μια σημείωση λέει να κλείσει στο κινητό.
        val staleLine2 = phone?.takeIf { !it.ended && phoneStale(it, nowHome) }?.let { stalePhoneLine2(it.start, nowHome) }
        if (staleLine2 != null) sayAdd("$STALE_PHONE_LINE1 $staleLine2")
        if (phone != null && !phone.ended && staleLine2 == null) {
            // Με «ενημέρωσε»: οι δύο γραμμές του στη θέση της ετικέτας «ΣΤΟ ΚΙΝΗΤΟ» (τα κουμπιά πιάνουν όλο το κάτω μέρος).
            if (upd) updateNote(c, 36f) else small(c, "ΣΤΟ ΚΙΝΗΤΟ", 50f, gray, ess(10f), 120f)
            t(c, phone.name, 72f, Color.WHITE, 15f * fs, true)
            small(c, "${phone.setsDone} σετ ως τώρα", 90f, gray, ess(10f), 130f)
            sayAdd("Στο κινητό: ${phone.name}, ${phone.setsDone} σετ ως τώρα")
            // Περιοχές πατήματος 40u (≈ 48 dp) η καθεμία, με 3u κενό ανάμεσα (U7-08δ): 95–135u και 138–178u.
            pill(c, "Παλμοί εδώ", 118f, 110f, 34f, orangeFill, Color.WHITE, 13f * fs, padBottom = 0f) { actions.joinPhone() }
            // Και περπάτημα από εδώ, ακόμα κι αν η προπόνηση του κινητού έμεινε ανοιχτή (έλεγχος 9/11, V-A-09). Κουμπί
            // (έλεγχος γ2, W3-09), όχι σκέτο κείμενο.
            pill(c, "Περπάτημα", 157f, 96f, 30f, button2, Color.WHITE, 11.5f * fs, padTop = 4f) { actions.startWalk() }
            return
        }
        val strength = plan?.workouts?.filter { !it.isCardio && it.items.isNotEmpty() }.orEmpty()
        val today = plan?.todayWorkout
        // R8-U3-06: η επιλογή του τρίτου κουμπιού μόνο τη μέρα που έγινε.
        val pick = chosenToday(chosen, chosenDay, java.time.LocalDate.now())
        val shown = plan?.workout(pick) ?: today?.takeIf { !it.isCardio } ?: strength.firstOrNull()
        if (plan != null || Repo.knownLimit != null) {
            // Το όριο που ισχύει, πριν ξεκινήσεις (έλεγχος 8/11)· και χωρίς πρόγραμμα, το τελευταίο που ήρθε (V-A-06).
            val lim = Repo.limitNow()
            // «Σήμερα» μόνο όταν το πρώτο κουμπί είναι η σημερινή (ή δεν φαίνεται καμία προπόνηση)· αλλιώς «Άλλη» (N5). Round 7
            // (R7-A6-6): και σε μέρα χωρίς προπόνηση (π.χ. πριν από την έναρξη του προγράμματος), όπου πρώτη μπαίνει μια άλλη.
            val notToday = shown != null && (if (pick == null) today == null else pick != today?.id)
            if (!upd) twoTone(c, if (!notToday) "Σήμερα · " else "Άλλη προπόνηση · ", if (lim != null) "όριο $lim" else "χωρίς όριο", 33f, if (lim != null) salmon else gray, 10.5f * fs)
        }
        when {
            plan == null -> {
                small(c, "ΥΓΕΙΑ & ΦΟΡΜΑ", 56f, gray, ess(10f), 120f)
                if (staleLine2 != null) {
                    // R8-A8-4: η ξεχασμένη προπόνηση του κινητού φαίνεται και εδώ (το TalkBack τη λέει ήδη), στη θέση του
                    // «Άνοιξε την εφαρμογή στο κινητό»: λέει ήδη τι να κάνεις στο κινητό. Κάτω από το κουμπί δεν χωρά ολόκληρη.
                    staleNote(c, staleLine2, 80f)
                } else {
                    t(c, "Άνοιξε την εφαρμογή", 80f, Color.WHITE, 12f * fs, true, 170f)
                    t(c, "στο κινητό", 80f + 16f * fs, Color.WHITE, 12f * fs, true)
                    sayAdd("Άνοιξε την εφαρμογή στο κινητό")
                }
                pill(c, "Περπάτημα", 136f, 104f, 34f, card, Color.WHITE, 12f * fs) { actions.startWalk() }
                // Κάτω από το κουμπί (τελειώνει στα 153u)· όχι όσο φαίνεται άλλο μήνυμα στην ίδια λωρίδα.
                if (upd && shownNote == null) updateNote(c, 170f)
            }
            today?.isCardio == true && pick == null -> {
                // Μέρα περπατήματος: πρώτο το περπάτημα, δεύτερη η προπόνηση με βάρη.
                val w = strength.firstOrNull()
                // Τα λεπτά της εβδομάδας του προγράμματος που τρέχει ΣΗΜΕΡΑ (S6-11/S11-7), με ολόκληρη τη λέξη (S8-10/U7-09).
                val mins = today.cardio?.let { walk -> plan?.cardioMinutes(walk) } ?: 30
                val walkName = today.cardio?.name ?: "Περπάτημα"
                val minText = countText(mins, "λεπτό", "λεπτά")
                val full = "$minText${today.cardio?.note?.let { " · $it" } ?: ""}"
                // Έλεγχος 13/11, round 7 (R7-U3-03): αν η σημείωση του προγράμματος δεν χωρά στη 2η γραμμή του κουμπιού με
                // γράμματα τουλάχιστον [HOME_SUB_MIN], μόνο τα λεπτά (η σημείωση φαίνεται στο κινητό)· όχι «…» και γράμματα
                // 8u στο κύριο κουμπί της μέρας. Το TalkBack λέει ολόκληρο.
                text.typeface = Typeface.DEFAULT
                text.textSize = HOME_SUB_MIN * u
                val sub = if (text.measureText(full) <= (HOME_BUTTON_W - 16f) * u) full else minText
                homeButton(c, walkName, sub, 44f, orangeFill, Color.WHITE, desc = "$walkName, $full") { actions.startWalk() }
                if (w != null) homeButton(c, w.name, null, 92f, button2, Color.WHITE) { actions.startWorkout(w.id) }
                if (upd) updateNote(c, 150f) else if (staleLine2 != null) staleNote(c, staleLine2)
            }
            shown != null -> {
                // Σχέδια 9/11 (7α): δύο ίσα κουμπιά ~48 dp και η άλλη προπόνηση τρίτη, χωρίς κρυφή χειρονομία.
                // Διάρκεια με ολόκληρη τη λέξη («50 λεπτά», όχι «50 λ»· έλεγχος 13/11, S8-10/U7-09).
                homeButton(c, shown.name, "${countText(shown.items.size, "άσκηση", "ασκήσεις")} · ${countText(shown.minutes, "λεπτό", "λεπτά")}", 44f, orangeFill, Color.WHITE) {
                    actions.startWorkout(shown.id)
                }
                homeButton(c, "Περπάτημα", null, 92f, button2, Color.WHITE) { actions.startWalk() }
                val otherId = nextStrength(strength.map { it.id }, shown.id)
                val other = strength.firstOrNull { it.id == otherId }
                if (upd) {
                    // Στη θέση του τρίτου κουμπιού (S8-03/U7-01): το μήνυμα φαίνεται ολόκληρο· η άλλη προπόνηση ξαναβγαίνει
                    // μόλις ενημερωθεί η εφαρμογή.
                    updateNote(c, 150f)
                } else if (staleLine2 != null) {
                    // Το ίδιο για την ξεχασμένη προπόνηση του κινητού (R7-A8-3): ξαναβγαίνει μόλις κλείσει εκεί.
                    staleNote(c, staleLine2)
                } else if (other != null) {
                    // Πάτημα: έρχεται πρώτη (δεν ξεκινά αμέσως· μία απόφαση ανά οθόνη). Η επόμενη στη σειρά του
                    // προγράμματος, κυκλικά: με 3+ προπονήσεις φτάνεις σε όλες (έλεγχος premium, M4).
                    homeButton(c, other.name, null, 138f, button3, soft, h = 36f, w = 116f, size = 11f) { chosen = other.id; invalidate() }
                }
            }
            else -> {
                small(c, "ΣΗΜΕΡΑ", 56f, gray, ess(10f), 120f)
                t(c, "Ξεκούραση", 80f, Color.WHITE, 15f * fs, true)
                sayAdd("Σήμερα ξεκούραση")
                pill(c, "Περπάτημα", 124f, 104f, 34f, card, Color.WHITE, 12f * fs) { actions.startWalk() }
                // R8-A8-4: και η ξεχασμένη προπόνηση του κινητού, στην ίδια θέση με το «ενημέρωσε» (όχι μαζί με άλλο μήνυμα).
                if (shownNote == null) {
                    if (upd) updateNote(c, 164f) else if (staleLine2 != null) staleNote(c, staleLine2, 164f)
                }
            }
        }
    }

    /**
     * Έλεγχος 14/11, round 8 (R8-A8-1): η προπόνηση κλείνει ακόμα (αποτέλεσμα, Health Services· συνήθως 1–2″, το πολύ
     * ≈ 17″). Χωρίς κουμπιά: μια έναρξη εδώ θα έσβηνε το αποτέλεσμα των παλμών της. Κείμενα προς έγκριση από τον χρήστη.
     */
    private fun drawClosing(c: Canvas) {
        t(c, CLOSING_TITLE, 92f, Color.WHITE, 14f * fs, true)
        small(c, CLOSING_SUB, 92f + 17f * fs, gray, ess(10f), 150f)
        sayAdd("$CLOSING_TITLE. $CLOSING_SUB")
    }

    /**
     * «Ενημέρωσε την εφαρμογή / στο ρολόι» σε δύο γραμμές, η πρώτη με βάση [y] (S8-03/U7-01). Το πλάτος κάθε γραμμής από
     * τη χορδή του κύκλου στο ύψος της ([chordAt])· αν δεν χωρά (γράμματα 1,3×), μικραίνει.
     *
     * Έλεγχος 13/11, round 2 (R2-U3-01): ΕΝΑ μέγεθος για τις δύο γραμμές της ίδιας φράσης, όπως στο [noteLines]. Πριν, κάθε
     * γραμμή μίκραινε χωριστά στο [t]: με γράμματα 1,3× η πρώτη έπεφτε στα ≈ 11,5u (στη θέση 36u ≈ 10,5u) και η δεύτερη
     * έμενε 13u. Τώρα μικραίνουν μαζί ως το μεγαλύτερο μέγεθος (βήμα 0,5u, ως [NOTE_MIN]) που χωρούν ΚΑΙ οι δύο.
     */
    private fun updateNote(
        c: Canvas, y: Float, l1: String = "Ενημέρωσε την εφαρμογή", l2: String = "στο ρολόι", w1: Float = 130f, w2: Float = 90f,
    ) {
        text.typeface = Typeface.DEFAULT
        fun fits(s: Float): Boolean {
            text.textSize = s * u
            return text.measureText(l1) <= minOf(w1, chordAt(y, s)) * u &&
                text.measureText(l2) <= minOf(w2, chordAt(y + s * 1.1f, s)) * u
        }
        var sz = ess(10f)
        while (sz > NOTE_MIN && !fits(sz)) sz = maxOf(NOTE_MIN, sz - 0.5f)
        val y2 = y + sz * 1.1f
        small(c, l1, y, orange, sz, minOf(w1, chordAt(y, sz)), sz)
        small(c, l2, y2, orange, sz, minOf(w2, chordAt(y2, sz)), sz)
    }

    /**
     * «Ανοιχτή προπόνηση στο κινητό / από Δευτέρα· κλείσε την εκεί» (R7-A8-3) στη θέση του τρίτου κουμπιού της αρχικής,
     * όπως το «ενημέρωσε» ([updateNote]): δύο γραμμές με ένα μέγεθος, ως 140u η καθεμία.
     */
    private fun staleNote(c: Canvas, line2: String, y: Float = 150f) {
        updateNote(c, y, STALE_PHONE_LINE1, line2, 140f, 140f)
    }

    // ------------------------------------------------------------------ Β. σετ
    /**
     * Έλεγχος γ2 (W3-09): − / + με περιοχή ≥ 40u (≈ 48 dp) ως την άκρη, που δεν ακουμπά το ✓· το ✓ πατιέται μόνο από το
     * σχήμα του και κάτω· «Τέλος» κουμπί-χάπι· γράμματα ≥ 10u και με το μέγεθος του ρολογιού.
     */
    private fun drawSet(c: Canvas, now: Long) {
        val s = Repo.session ?: return drawHome(c)
        // «Ελεύθερη άσκηση» του κινητού χωρίς ασκήσεις ακόμα (9/11): οι παλμοί μετράνε, η άσκηση διαλέγεται στο κινητό.
        if (s.phone && s.items.isEmpty()) return drawPickOnPhone(c, now)
        // Όλες οι ασκήσεις έγιναν (W3-13): όχι ένα ✓ που δεν κάνει τίποτα.
        if (s.phone && s.allDone) return if (s.workout == "_free") drawPickOnPhone(c, now, next = true) else drawAllDone(c, now)
        val it = s.current ?: return drawEnd(c)
        heart(c, 34f, now, 11f)
        val si = it.nextSet.let { n -> if (n < 0) it.sets.size - 1 else n }
        val set = it.sets.getOrNull(si)
        // Όνομα άσκησης: πάτημα = επόμενη άσκηση (δύο πατήματα). Μεγάλο όνομα μικραίνει ως 9u πριν κοπεί (U7-04).
        small(c, it.name, 52f, Color.WHITE, 10.5f * fs, 140f, 9f)
        // Έλεγχος 13/11, round 7 (R7-U3 Β-Α1): και ο στόχος έντασης «άφησε N», όπως στη γραμμή του στόχου στο κινητό. Πριν
        // στην προπόνηση μόνο με ρολόι δεν φαινόταν πουθενά.
        small(c, "ΣΕΤ ${si + 1}/${it.sets.size} · άφησε ${it.rirTarget}" + if (s.items.size > 1) "  ›" else "", 52f + 12.5f * fs, gray, ess(10f), 140f)
        sayAdd("${it.name}, σετ ${si + 1} από ${it.sets.size}, άφησε ${it.rirTarget}" + (set?.let { x -> (if (x.label.isNotEmpty()) ", ${x.label}" else "") + ", ${countText(x.reps, "επανάληψη", "επαναλήψεις")}" } ?: ""))
        // Περιοχή πατήματος 44u ψηλή (U7-08δ· πριν 28u): από τη γραμμή των παλμών ως κάτω από το «ΣΕΤ». Τα − / + αρχίζουν
        // πιο κάτω (από 80u), άρα δεν τέμνονται.
        if (s.items.size > 1) hits.add(Hit(RectF(cx - 75 * u, 26 * u, cx + 75 * u, 70 * u), "Επόμενη άσκηση") { actions.nextExercise() })
        if (set != null) {
            val noLabel = set.label.isEmpty()
            if (!noLabel) fit(c, set.label, 92f, Color.WHITE, 24f, 150f)
            // Επαναλήψεις με − / + (και με την περιστροφή).
            text.typeface = Typeface.DEFAULT_BOLD
            val ry = if (noLabel) 100f else 114f
            t(c, "× ${set.reps}", ry + (if (noLabel) 9f else 5.5f) * fs, Color.WHITE, (if (noLabel) 26f else 16f) * fs, true)
            roundKey(c, "−", 42f, ry, 26f, 44f, 40f, "Μία επανάληψη λιγότερη") { actions.reps(-1) }
            roundKey(c, "+", 158f, ry, 26f, 44f, 40f, "Μία επανάληψη παραπάνω") { actions.reps(1) }
        }
        // Το ✓ πατιέται από το σχήμα του και κάτω (όχι πάνω από αυτό, όπου είναι τα − / +).
        // (κενό 2u από την περιοχή των − / +, ώστε κανένα σημείο να μην είναι και των δύο).
        // Έλεγχος 13/11 (U7-03): όσο φαίνεται μήνυμα δύο γραμμών, το ✓ τελειώνει 7u πιο πάνω (136–161u αντί 136–168u), ώστε
        // η πρώτη γραμμή να μην το ακουμπά και η δεύτερη να μη φτάνει στην άκρη του κύκλου. Η πάνω άκρη του δεν αλλάζει.
        if (noteTwo) pill(c, "✓", 148.5f, 84f, 25f, green, Color.WHITE, 18f, desc = "Έγινε το σετ", padTop = 0f, padBottom = 0f) { actions.tick() }
        else pill(c, "✓", 152f, 84f, 32f, green, Color.WHITE, 18f, desc = "Έγινε το σετ", padTop = 0f, padBottom = 0f) { actions.tick() }
        // 13/11 (Συμβούλιο 5, Δ2): το ✓ πατιέται και 8u πάνω από το σχήμα του, μόνο στη μέση (x 66–134u): εκεί το ύψος
        // γίνεται 40u ≈ 48 dp. Τα − / + φτάνουν ως x 64u και από 136u, άρα μένει κενό 2u και κανένα σημείο δεν είναι και
        // των δύο. Χωρίς όνομα: για το TalkBack υπάρχει ήδη το «Έγινε το σετ».
        hits.add(Hit(RectF(66 * u, 128 * u, 134 * u, 136 * u), "") { actions.tick() })
        // Έλεγχος 13/11, round 7 (R7-U3-10): το «Τέλος» δεν χωρά πιο ψηλό χωρίς να μικρύνει το ✓· η περιοχή πατήματος
        // μεγαλώνει ΟΡΙΖΟΝΤΙΑ: 100u (≈ 120 dp) × 169–200u, αντί για 68u. Κανένα άλλο πατήσιμο εκεί (τα − / + ως τα 134u).
        endButton(c, 182f, 56f, 22f, 2f, padSide = 22f)
    }

    /**
     * Το «Τέλος» κάτω στην οθόνη του σετ. Κρύβεται μόνο όσο φαίνεται μήνυμα στη θέση του· τότε μένει πατήσιμο (χωρίς σχήμα)
     * ΜΟΝΟ αν το μήνυμα είναι το δικό του «Πάτα ξανά…» ([isBriefNotice]). Έλεγχος 13/11 (U7-07): πριν, κάθε μήνυμα (και
     * τα μόνιμα της υπηρεσίας) το έκρυβε για όλη την προπόνηση, και το πάτημα πάνω στο μήνυμα έκανε «Τέλος» αντί να το ανοίξει.
     */
    private fun endButton(c: Canvas, y: Float, w: Float, h: Float, padTop: Float, padSide: Float = 6f) {
        val n = shownNote
        if (n == null) pill(c, "Τέλος", y, w, h, button3, soft, ess(10f), padTop = padTop, padBottom = 8f, padSide = padSide) { actions.finishWorkout() }
        else if (isBriefNotice(n)) {
            // Το ίδιο πλάτος με το ορατό «Τέλος» (R7-U3-10), από τα 169u ως την άκρη.
            val half = w / 2 + padSide
            hits.add(Hit(RectF(cx - half * u, 169 * u, cx + half * u, 200 * u), "Τέλος") { actions.finishWorkout() })
        }
    }

    private fun drawPickOnPhone(c: Canvas, now: Long, next: Boolean = false) {
        heart(c, 50f, now)
        if (next) {
            small(c, "Διάλεξε επόμενη", 82f, Color.WHITE, 13f * fs, 150f)
            small(c, "άσκηση στο κινητό", 82f + 16f * fs, Color.WHITE, 13f * fs, 150f)
            small(c, "${s0()} σετ ως τώρα", 82f + 32f * fs, gray, ess(10f), 140f)
            sayAdd("Διάλεξε επόμενη άσκηση στο κινητό. ${s0()} σετ ως τώρα")
        } else {
            t(c, "Διάλεξε άσκηση", 90f, Color.WHITE, 14f * fs, true)
            t(c, "στο κινητό", 90f + 19f * fs, Color.WHITE, 14f * fs, true)
            sayAdd("Διάλεξε άσκηση στο κινητό")
        }
        // Όσο πάνω γράφει ήδη «♥ περιμένω παλμούς» (R7-U3-05), όχι δεύτερη φορά από κάτω.
        if (!hrWaiting(Repo.hrSilent != null, Repo.bpmAt, Repo.startedAt, now)) {
            small(c, if (Repo.bpmFresh(now)) "οι παλμοί ήδη μετράνε" else "περιμένω παλμούς", 140f, gray, ess(10f), 150f)
        }
        // Περιοχή πατήματος 40u (≈ 48 dp): 153–193u (U7-08δ· πριν 38u).
        endButton(c, 172f, 64f, 26f, 6f)
    }

    private fun s0(): Int = Repo.session?.setsDone ?: 0

    /** Προπόνηση του κινητού με όλα τα σετ ✓: τέλος εδώ ή στο κινητό. */
    private fun drawAllDone(c: Canvas, now: Long) {
        heart(c, 50f, now)
        t(c, "✓", 86f, green, 22f, true)
        t(c, "Όλα τα σετ έγιναν", 106f, Color.WHITE, 12f * fs, true)
        small(c, "Τέλος εδώ ή στο κινητό", 106f + 15f * fs, gray, ess(10f), 150f)
        sayAdd("Όλα τα σετ έγιναν. Τέλος εδώ ή στο κινητό")
        // Όσο φαίνεται μήνυμα από κάτω («Πάτα ξανά: τέλος και στο κινητό», ως δύο γραμμές από τα 162u), το κουμπί είναι
        // λίγο πιο πάνω και πιο κοντό (133–161u), για να μην το ακουμπά· ένα δεύτερο πάτημα στο ίδιο σημείο το βρίσκει.
        if (shownNote != null) pill(c, "Τέλος", 147f, 88f, 28f, card, Color.WHITE, 12f * fs, padBottom = 2f) { actions.finishWorkout() }
        else pill(c, "Τέλος", 158f, 88f, 34f, card, Color.WHITE, 12f * fs) { actions.finishWorkout() }
    }

    // ------------------------------------------------------------------ ρεζέρβα
    private fun drawRir(c: Canvas) {
        // Έλεγχος 13/11, round 7 (R7-U3-04): «Δεν ξέρω» όπως στο κινητό (καμία απάντηση: δεν ανεβαίνει τίποτα), κάτω-κάτω.
        // Για να χωρέσουν τρεις σειρές πατημάτων ≥ 40u: η ερώτηση 11u πιο ψηλά, το «με καλή τεχνική» κάτω από αυτήν (πριν
        // στη θέση του «Δεν ξέρω») και τα κουμπιά 28u ψηλά (πριν 30u).
        val y1 = 43f
        val y2 = y1 + 15f * fs
        // Round 8 (R8-U3-01): μετά το 1ο σετ άσκησης «πρώτης φοράς» της προπόνησης του κινητού, ίδια κουμπιά με τίτλο
        // «Πρώτο σετ: / πόσες ακόμα;» (η 1η γραμμή στενότερη από το «Πόσες ακόμα», η 2η στη φαρδύτερη θέση).
        val first = Repo.session?.firstPending == true
        t(c, if (first) FIRST_SET_LINE1 else "Πόσες ακόμα", y1, Color.WHITE, 12f * fs, true)
        t(c, if (first) FIRST_SET_LINE2 else "θα έβγαζες;", y2, Color.WHITE, 12f * fs, true)
        small(c, "με καλή τεχνική", y2 + 12.5f * fs, gray, ess(10f), 120f)
        sayAdd(if (first) FIRST_SET_SAY else "Πόσες επαναλήψεις ακόμα θα έβγαζες με καλή τεχνική;")
        val labels = listOf("0", "1", "2", "3", "4+")
        val descs = listOf("Καμία", "Μία", "Δύο", "Τρεις", "Τέσσερις ή περισσότερες")
        // Δύο σειρές: 0 1 2 / 3 4+ (μεγάλα κουμπιά για τον καρπό· περιοχή 40u ≈ 48 dp).
        val row1 = listOf(60f, 100f, 140f)
        for (i in 0..2) pillAt(c, labels[i], row1[i], 100f, 34f, 28f, card, Color.WHITE, 14f * fs, descs[i]) { actions.answer(i) }
        // Έλεγχος 13/11 (U7-08β): οι περιοχές πατήματος των σειρών δεν πέφτουν η μία πάνω στην άλλη: 80–120u, 120–160u και
        // 160–200u («Δεν ξέρω»), και δεξιά-αριστερά ακριβώς διπλανές (40–80, 80–120, 120–160u).
        pillAt(c, labels[3], 80f, 140f, 34f, 28f, card, Color.WHITE, 14f * fs, descs[3]) { actions.answer(3) }
        pillAt(c, labels[4], 120f, 140f, 34f, 28f, card, Color.WHITE, 14f * fs, descs[4]) { actions.answer(4) }
        pill(c, RIR_UNKNOWN, 174f, 84f, 24f, button3, soft, ess(10f), padTop = 2f, padBottom = 14f) { actions.answer(-1) }
    }

    // ------------------------------------------------------------------ Γ. διάλειμμα
    private fun drawRest(c: Canvas, now: Long) {
        val s = Repo.session ?: return drawHome(c)
        val left = ((s.restEnd - now) / 1000L).coerceAtLeast(0)
        // Το δαχτυλίδι με όλο το διάλειμμα που ξεκίνησε (έλεγχος γ2, W2-20), όχι με της άσκησης που ακολουθεί.
        val p = s.restLeft(now)
        val pad = 6 * u
        ring.strokeWidth = 5 * u
        ring.color = dim
        val box = RectF(pad, pad, width - pad, height - pad)
        c.drawArc(box, -90f, 360f, false, ring)
        ring.color = orange
        c.drawArc(box, -90f, 360f * p, false, ring)
        small(c, "ΔΙΑΛΕΙΜΜΑ", 44f, gray, ess(10f), 120f)
        t(c, clock(left), 78f, Color.WHITE, 30f * fs, true)
        sayAdd("Διάλειμμα, μένουν ${clock(left)}")
        heart(c, 96f, now, 11f)
        // Το σετ που μόλις έγινε, με διόρθωση (έλεγχος γ2, RT-13): το ✓ γράφει τον στόχο· αν έκανες άλλες, άλλαξέ το εδώ.
        val done = s.lastDone(now)
        if (done != null) {
            val reps = s.items[done.first].sets[done.second].reps
            // Μικραίνει αντί να ακουμπά τα − / + (γράμματα 1,3×).
            text.typeface = Typeface.DEFAULT
            fitPlain(c, "έκανες × $reps", 119f, Color.WHITE, 12f * fs, 72f)
            // R7-U4-2: ενικός στο 1 («Έκανες 1 επανάληψη»).
            sayAdd("Έκανες ${countText(reps, "επανάληψη", "επαναλήψεις")}")
            // Περιοχή πατήματος 40u ψηλή (95–135u, ≈ 48 dp· U7-08δ, πριν 34u): δεν ακουμπά τίποτα πατήσιμο.
            roundKey(c, "−", 46f, 115f, 22f, 44f, 40f, "Έκανες μία λιγότερη") { actions.lastReps(-1) }
            roundKey(c, "+", 154f, 115f, 22f, 44f, 40f, "Έκανες μία παραπάνω") { actions.lastReps(1) }
        }
        val it = s.current
        val si = it?.nextSet ?: -1
        val note = shownNote
        if (note != null) {
            // Το μήνυμα στη θέση του «επόμενο» (κάτω είναι τα κουμπιά και το δαχτυλίδι): μικραίνει ώσπου να χωρέσει.
            small(c, note, 141f, soft, ess(10f), REST_LINE_W, NOTE_MIN)
        } else if (it != null && si >= 0) {
            val set = it.sets[si]
            val load = "${set.label}${if (set.label.isEmpty()) "" else " "}× ${set.reps}"
            if (si == 0) {
                // Έλεγχος 13/11 (U7-05): πριν από ΝΕΑ άσκηση, το όνομα και τα κιλά × επαναλήψεις σε δύο γραμμές. Σε μία γραμμή
                // («επόμενο: Κωπηλασία με αλτήρα · 14,3 kg × 11», ≈ 190u) δεν χωρούσαν και κόβονταν ακριβώς τα νούμερα που
                // χρειάζεσαι για να ετοιμάσεις τα βάρη. Οι γραμμές χωράνε ανάμεσα στα − / + (ως 126u) και στα κουμπιά (από
                // 155u): 137u και 149u, με γράμματα ως 11,5u και 11u (και με το μέγεθος 1,3× του ρολογιού).
                // Έλεγχος 13/11, round 7 (R7-U3-02): αν «επόμενο: <όνομα>» δεν χωρά ούτε στο ελάχιστο μέγεθος, μόνο το όνομα
                // (ολόκληρο, όχι κομμένο με «…»)· το «επόμενο» φαίνεται από τη θέση και το λέει το TalkBack.
                val nextName = "επόμενο: ${it.name}"
                text.typeface = Typeface.DEFAULT
                text.textSize = NOTE_MIN * u
                val nextLine = if (text.measureText(nextName) <= REST_LINE_W * u) nextName else it.name
                small(c, nextLine, 137f, gray, minOf(ess(10f), 11.5f), REST_LINE_W, NOTE_MIN)
                t(c, load, 149f, Color.WHITE, 11f, true, 140f, NOTE_MIN)
                sayAdd("επόμενο: ${it.name}, $load")
            } else {
                val nextText = "επόμενο: σετ ${si + 1} · $load"
                small(c, nextText, 141f, gray, ess(10f), REST_LINE_W)
                sayAdd(nextText)
            }
        }
        // Έλεγχος 13/11 (U7-08α): τα δύο κουμπιά 6u πιο μακριά το ένα από το άλλο (κενό 10u) και περιοχές πατήματος που δεν
        // τέμνονται (48–98u και 102–152u· πριν 50–102 και 98–150, με το κενό να ανήκει όλο στο «Πάμε»), 40u ψηλές
        // (147–187u ≈ 48 dp). Η δεξιά γωνία μένει μέσα από το δαχτυλίδι (89,9u < 91,5u).
        pillAt(c, "+30″", 73f, 168f, 44f, 26f, card, Color.WHITE, 11f * fs, "Τριάντα δευτερόλεπτα ακόμα", padTop = 8f) { actions.restPlus() }
        pillAt(c, "Πάμε", 127f, 168f, 44f, 26f, Color.WHITE, Color.BLACK, 11f * fs, "Τέλος διαλείμματος", padTop = 8f) { actions.restStop() }
    }

    // ------------------------------------------------------------------ Δ. όριο παλμών
    private fun drawAlarm(c: Canvas) {
        val now = System.currentTimeMillis()
        val walk = Repo.running == "walk"
        val rec = Repo.recoveryUntil > 0
        small(c, "ΠΑΝΩ ΑΠΟ ΤΟ ΟΡΙΟ", 56f, Color.WHITE, ess(10f), 140f)
        t(c, "♥ ${Repo.bpm}", 94f, Color.WHITE, 30f, true)
        // Παλιός αριθμός (δεν έρχονται παλμοί): με την ηλικία του, όχι σαν τωρινός (W2-16).
        val stale = !Repo.bpmFresh(now) && Repo.bpmAt > 0
        // Σε ολόκληρες λέξεις («πριν 40 δευτερόλεπτα», R7-U3-08)· αν δεν χωρά, μικραίνει.
        if (stale) small(c, "παλμοί πριν ${agoText(now - Repo.bpmAt)}", 108f, alarmSoft, ess(10f), 140f)
        t(c, alarmHeadline(walk, rec), 126f, Color.WHITE, 14f * fs, true)
        // Όχι «μέχρι κάτω από 140»: η κόκκινη οθόνη σβήνει λίγο πιο κάτω (W2-16).
        small(c, "όριο γιατρού ${Repo.alarm.limit ?: ""}", 126f + 15f * fs, Color.WHITE, ess(10.5f), 140f)
        closeHint(c, alarmSoft)
        sayAdd("Πάνω από το όριο. Παλμοί ${Repo.bpm}. ${alarmHeadline(walk, rec)}. Όριο γιατρού ${Repo.alarm.limit ?: ""}")
        hits.add(Hit(RectF(0f, 0f, width.toFloat(), height.toFloat()), "Κλείσιμο για ένα λεπτό") { actions.muteAlarm() })
    }

    /** Βάση (u) του «πάτα για να κλείσει»: 166u, με γράμματα 1,3× 178u. */
    private fun closeY(): Float = 166f + 4f * (fs - 1f) * 10f

    /**
     * «πάτα για να κλείσει» κάτω στην οθόνη: ίδια φράση, θέση και μέγεθος στην κόκκινη οθόνη του ορίου ([color] #FECACA) και
     * στο μήνυμα σε όλη την οθόνη ([drawNotice], γκρι σε μαύρο· R2-U3-02). Το πλάτος από τη χορδή του κύκλου σε αυτό το
     * ύψος: με γράμματα 1,3× (βάση 178u) χωράνε 106u, όχι 120u· αν δεν χωρά, μικραίνει ως [NOTE_MIN].
     */
    private fun closeHint(c: Canvas, color: Int) {
        val y = closeY()
        small(c, "πάτα για να κλείσει", y, color, ess(10f), minOf(120f, chordAt(y, ess(10f))), NOTE_MIN)
    }

    // ------------------------------------------------------------------ Ε. περπάτημα
    private fun drawWalk(c: Canvas, now: Long) {
        // Σχέδια 9/11 (7β): μεγάλος χρόνος, «2,18 km · 11:15 /km», παλμοί με όριο, «Παύση» σκούρο και «Τέλος» ανοιχτό.
        text.letterSpacing = 0.08f
        small(c, if (Repo.paused) "ΠΑΥΣΗ" else "ΠΕΡΠΑΤΗΜΑ", 33f, if (Repo.paused) orange else soft, 9.5f * fs, 120f)
        text.letterSpacing = 0f
        // Ο χρόνος προχωρά κάθε δευτερόλεπτο από το σημείο ελέγχου του Health Services (W3-12).
        val sec = Repo.activeSecNow(now).let { if (it > 0 || Repo.cpWall > 0) it else (now - Repo.startedAt) / 1000 }
        fit(c, clock(sec), 78f, if (Repo.paused) gray else Color.WHITE, 40f * fs, 150f)
        val dist = if (Repo.meters > 0) "${km(Repo.meters)} km · ${pace(Repo.meters, sec)}" else if (Repo.steps > 0) "${Repo.steps} βήματα" else "—"
        text.typeface = Typeface.DEFAULT_BOLD
        fitPlain(c, dist, 96f, Color.WHITE, 10.5f * fs, 150f)
        walkHeart(c, 117f, now)
        sayAdd("${if (Repo.paused) "Παύση" else "Περπάτημα"}, ${clock(sec)}, $dist")
        // Χωρίς όριο ή χωρίς GPS: να φαίνεται (W3-18), όχι σιωπηλά. Αν υπάρχει μήνυμα, γράφεται εδώ στη θέση τους.
        // 12/11: με ζώνη περπατήματος (και χωρίς όριο γιατρού), πρώτα πού είσαι ως προς τη ζώνη.
        val zone = if (Repo.alarm.limit == null) Repo.zoneAlarm.zone else null
        val where = if (zone != null && Repo.hrLive(now) && !Repo.paused) zoneWord(Repo.bpm, zone) else null
        val tags = listOfNotNull(
            where?.first,
            if (!Repo.gps) "χωρίς GPS" else null,
            if (Repo.alarm.limit == null && zone == null) "χωρίς όριο παλμών" else null,
        )
        // Έλεγχος 13/11 (U7-06): η λεζάντα («πάνω · κόψε λίγο») κρύβεται μόνο όσο φαίνεται μήνυμα στη θέση της (ως 8″), όχι
        // για όλο το περπάτημα. U7-02: 1,5u πιο κάτω (και η γραμμή της ζώνης 1,5u πιο πάνω), για να μην πέφτει η κουκκίδα
        // πάνω στους τόνους· με μεγάλα γράμματα λίγο πιο κάτω ακόμα. Αν δεν χωρά (1,3×), μικραίνει.
        if (tags.isNotEmpty() && shownNote == null) {
            small(c, tags.joinToString(" · "), WALK_NOTE_Y + (fs - 1f) * 8f, where?.second ?: gray, ess(10f), WALK_NOTE_W, NOTE_MIN)
            sayAdd(tags.joinToString(", "))
        }
        // Παύση/Συνέχεια αριστερά, Τέλος δεξιά (δύο πατήματα, όπως πριν). Έλεγχος 13/11 (U7-02/U7-08γ): 2u πιο κάτω και 2u
        // πιο κοντά (143–177u), ώστε οι ουρές της λεζάντας να μη φτάνουν στα κουμπιά, και 2u πιο μακριά το ένα από το άλλο.
        // Περιοχές πατήματος 34–100u και 102–168u (δεν τέμνονται· πριν το κενό ανήκε όλο στο «Τέλος»), 137–183u (46u ≈ 55 dp).
        pillAt(c, if (Repo.paused) "Συνέχεια" else "Παύση", 67f, 160f, 60f, 34f, if (Repo.paused) orangeFill else button2, Color.WHITE, 11.5f * fs) {
            actions.pauseWalk(!Repo.paused)
        }
        pillAt(c, "Τέλος", 135f, 160f, 60f, 34f, light, ink, 11.5f * fs, "Τέλος περπατήματος") { actions.finishWorkout() }
    }

    /** «♥ 104  όριο 140» και γραμμή ως το όριο· χωρίς παλμούς «♥ —» (κεχριμπάρι με όριο). */
    private fun walkHeart(c: Canvas, y: Float, now: Long) {
        val fresh = Repo.hrLive(now)
        val lim = Repo.alarm.limit
        val over = fresh && lim != null && Repo.bpm >= lim
        if (!fresh && Repo.running != null && lim == null) {
            // R7-U3-05: στα πρώτα 30″ πριν από τον πρώτο παλμό «περιμένω παλμούς», όπως στο σετ και στο κινητό.
            val waiting = hrWaiting(Repo.hrSilent != null, Repo.bpmAt, Repo.startedAt, now)
            t(c, if (waiting) HR_WAIT_TEXT else "♥ δεν μετριούνται", y, gray, ess(10f), true)
            sayAdd(if (waiting) "Περιμένω παλμούς" else "Δεν μετριούνται παλμοί")
            return
        }
        sayAdd(if (fresh) "Παλμοί ${Repo.bpm}" + (lim?.let { ", όριο $it" } ?: "") else "Δεν μετριούνται παλμοί, το όριο δεν σε προσέχει")
        // Έλεγχος 13/11 (S8-02): το ρολόι είναι σε Σίγαση ή Εξοικονόμηση ενέργειας και θα έκοβε τη δόνηση ζώνης: γράφεται
        // δίπλα στους παλμούς, στη θέση που με όριο γιατρού γράφεται το «όριο 140» (με όριο η ζώνη δεν μιλά έτσι κι αλλιώς).
        // Round 7 (R7-A7-1): και σε «Μην ενοχλείτε» / Λειτουργία ύπνου.
        val muted = lim == null && fresh && Repo.zoneMuted
        if (muted) sayAdd(ZONE_MUTED_SAY)
        val heartC = if (!fresh) amber else if (over) red else salmon
        val num = if (fresh) "${Repo.bpm}" else "—"
        val tail = if (lim != null) "   όριο $lim" else if (muted) "   $ZONE_MUTED_TAG" else ""
        text.textSize = 15f * fs * u
        text.typeface = Typeface.DEFAULT_BOLD
        val wHeart = text.measureText("♥ ")
        val wNum = text.measureText(num)
        // Η ουρά μικραίνει αν όλη η γραμμή δεν χωρά σε 172u (μετρημένο· με γράμματα 1,3× χωρά άνετα και τώρα).
        var tailSize = 9.5f * fs
        text.textSize = tailSize * u
        text.typeface = Typeface.DEFAULT
        var wTail = text.measureText(tail)
        while (wHeart + wNum + wTail > 172f * u && tailSize > 8f) {
            tailSize -= 0.5f
            text.textSize = tailSize * u
            wTail = text.measureText(tail)
        }
        var x = cx - (wHeart + wNum + wTail) / 2
        val old = text.textAlign
        text.textAlign = Paint.Align.LEFT
        text.textSize = 15f * fs * u
        text.typeface = Typeface.DEFAULT_BOLD
        text.color = heartC
        c.drawText("♥ ", x, y * u, text)
        x += wHeart
        text.color = if (over) red else if (fresh) Color.WHITE else amber
        c.drawText(num, x, y * u, text)
        x += wNum
        text.textSize = tailSize * u
        text.typeface = Typeface.DEFAULT
        text.color = if (muted) amber else gray
        c.drawText(tail, x, y * u, text)
        text.textAlign = old
        if (!fresh) return
        if (lim == null) {
            Repo.zoneAlarm.zone?.let { zoneBar(c, y, it) }
            return
        }
        val w = 100f
        val x0 = cx - w * u / 2
        // 1,5u πιο πάνω από πριν, όπως η γραμμή της ζώνης (U7-02): το λευκό σημάδι του ορίου τελειώνει στα 127u, πάνω από
        // τους τόνους της λεζάντας (από ≈ 128u).
        val yy = (y + 4.5f) * u
        fill.color = dim
        c.drawRoundRect(RectF(x0, yy, x0 + w * u, yy + 3.5f * u), 2 * u, 2 * u, fill)
        val lo = 60f
        val hi = lim + 20f
        val p = ((Repo.bpm - lo) / (hi - lo)).coerceIn(0f, 1f)
        fill.color = if (over) red else salmon
        c.drawRoundRect(RectF(x0, yy, x0 + w * u * p, yy + 3.5f * u), 2 * u, 2 * u, fill)
        val lp = ((lim - lo) / (hi - lo)).coerceIn(0f, 1f)
        fill.color = Color.WHITE
        c.drawRect(RectF(x0 + w * u * lp - 0.7f * u, yy - 2f * u, x0 + w * u * lp + 0.7f * u, yy + 5.5f * u), fill)
    }

    /** Πού είσαι ως προς τη ζώνη (σχέδια 12/11, 4γ/4δ): κείμενο και χρώμα. */
    private fun zoneWord(bpm: Int, z: WalkZone): Pair<String, Int> = when {
        bpm > z.hi -> "πάνω · κόψε λίγο" to amber
        bpm < z.lo -> "κάτω από τη ζώνη" to gray
        else -> "στη ζώνη ${z.lo}–${z.hi}" to zoneGreen
    }

    /** Γραμμή με τη ζώνη (πράσινο κομμάτι) και τους παλμούς τώρα (λευκή κουκκίδα), κάτω από τον αριθμό. */
    private fun zoneBar(c: Canvas, y: Float, z: WalkZone) {
        val w = 100f
        val x0 = cx - w * u / 2
        // Έλεγχος 13/11 (U7-02): η γραμμή 1,5u πιο πάνω και η κουκκίδα λίγο μικρότερη (ακτίνα 2,8u αντί 3,2u). Πριν, η
        // κουκκίδα (ως 127,95u) έπεφτε πάνω στους τόνους της λεζάντας (από ≈ 126,4u). Τώρα: κουκκίδα 120,45–126,05u,
        // λεζάντα από ≈ 127,9u (βάση 136,5u, γράμματα 10u)· με γράμματα 1,3× από ≈ 127,7u.
        val yy = (y + 4.5f) * u
        val lo = z.lo - 25f
        val hi = z.hi + 25f
        fun px(v: Float) = x0 + w * u * ((v - lo) / (hi - lo)).coerceIn(0f, 1f)
        fill.color = dim
        c.drawRoundRect(RectF(x0, yy, x0 + w * u, yy + 3.5f * u), 2 * u, 2 * u, fill)
        fill.color = zoneGreen
        c.drawRoundRect(RectF(px(z.lo.toFloat()), yy, px(z.hi.toFloat()), yy + 3.5f * u), 2 * u, 2 * u, fill)
        fill.color = if (Repo.bpm > z.hi) amber else Color.WHITE
        c.drawCircle(px(Repo.bpm.toFloat()), yy + 1.75f * u, 2.8f * u, fill)
    }

    /** Σχέδια 9/11 (7γ): «Δεν έρχονται παλμοί» με όριο γιατρού, σε όλη την οθόνη, με «Εντάξει». */
    private fun drawNoHr(c: Canvas) {
        fill.shader = RadialGradient(cx, cy * 0.85f, width * 0.62f, Color.parseColor("#5A3A0A"), Color.parseColor("#1E1404"), Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fill)
        fill.shader = null
        // Τρίγωνο προσοχής.
        val tri = Path().apply {
            moveTo(cx, 24f * u)
            lineTo(cx + 11f * u, 43f * u)
            lineTo(cx - 11f * u, 43f * u)
            close()
        }
        ring.color = amber
        ring.strokeWidth = 2.4f * u
        ring.strokeJoin = Paint.Join.ROUND
        c.drawPath(tri, ring)
        fill.color = amber
        c.drawRect(cx - 1.1f * u, 30f * u, cx + 1.1f * u, 37f * u, fill)
        c.drawCircle(cx, 40f * u, 1.3f * u, fill)
        val lim = Repo.alarm.limit
        t(c, "Δεν έρχονται", 62f, Color.WHITE, 15f * fs, true, 160f)
        t(c, "παλμοί", 80f, Color.WHITE, 15f * fs, true, 160f)
        // Ίδια ελεγμένη φράση με το κινητό και την ειδοποίηση (V-A-04/05): «δεν σε προσέχει».
        // Έλεγχος 13/11, round 7 (R7-U3 Β-Α3): το «σε» μένει με το ρήμα του («δεν σε προσέχει» σε μία γραμμή).
        t(c, "Το όριο $lim", 99f, amberSoft, 11.5f * fs, true, 170f)
        t(c, "δεν σε προσέχει τώρα", 115f, amberSoft, 11.5f * fs, true, 170f)
        t(c, "Σφίξε λίγο το λουράκι", 131f, soft, 10f * fs, false, 160f)
        sayAdd("Δεν έρχονται παλμοί. Το όριο $lim δεν σε προσέχει τώρα. Σφίξε λίγο το λουράκι")
        pill(c, "Εντάξει", 160f, 100f, 38f, amber, amberInk, 13f * fs) { noHrSeen = true; invalidate() }
    }

    /** Κουμπί της αρχικής: τίτλος (και μικρή γραμμή) μέσα σε στρογγυλεμένο ορθογώνιο, από το [top] σε u. */
    private fun homeButton(
        c: Canvas, title: String, sub: String?, top: Float, bg: Int, fg: Int,
        h: Float = 40f, w: Float = HOME_BUTTON_W, size: Float = 13f, desc: String? = null, run: () -> Unit,
    ) {
        val r = RectF(cx - w * u / 2, top * u, cx + w * u / 2, (top + h) * u)
        fill.color = bg
        c.drawRoundRect(r, h * u / 2, h * u / 2, fill)
        if (sub == null) {
            text.typeface = Typeface.DEFAULT_BOLD
            fitPlain(c, title, (top + h / 2) / 1f + 0.36f * size * fs, fg, size * fs, w - 16f)
        } else {
            text.typeface = Typeface.DEFAULT_BOLD
            fitPlain(c, title, top + h * 0.46f, fg, 12.5f * fs, w - 16f)
            text.typeface = Typeface.DEFAULT
            fitPlain(c, sub, top + h * 0.82f, fg, 9.5f * fs, w - 16f)
        }
        hits.add(Hit(RectF(r.left - 2 * u, r.top - 3 * u, r.right + 2 * u, r.bottom + 3 * u), desc ?: if (sub == null) title else "$title, $sub", run))
    }

    /** Σαν το [fit] αλλά με όποια γραμματοσειρά έχει ήδη το [text]. */
    private fun fitPlain(c: Canvas, s: String, y: Float, color: Int, size: Float, maxW: Float) {
        text.color = color
        var sz = size
        text.textSize = sz * u
        while (text.measureText(s) > maxW * u && sz > 8f) {
            sz -= 0.5f
            text.textSize = sz * u
        }
        c.drawText(clip(s, maxW * u), cx, y * u, text)
    }

    /** Δύο χρώματα σε μία κεντραρισμένη γραμμή («Σήμερα · » γκρι + «όριο 140» χρώμα). */
    private fun twoTone(c: Canvas, a: String, b: String, y: Float, colorB: Int, size0: Float) {
        // Μικραίνει ώσπου να χωρά στον κύκλο (π.χ. «Άλλη προπόνηση · όριο 140» με γράμματα 1,3×).
        var size = size0
        var wa: Float
        var wb: Float
        while (true) {
            text.textSize = size * u
            text.typeface = Typeface.DEFAULT
            wa = text.measureText(a)
            text.typeface = Typeface.DEFAULT_BOLD
            wb = text.measureText(b)
            if (wa + wb <= 136f * u || size <= 8f) break
            size -= 0.5f
        }
        val old = text.textAlign
        text.textAlign = Paint.Align.LEFT
        val x = cx - (wa + wb) / 2
        text.typeface = Typeface.DEFAULT
        text.color = soft
        c.drawText(a, x, y * u, text)
        text.typeface = Typeface.DEFAULT_BOLD
        text.color = colorB
        c.drawText(b, x + wa, y * u, text)
        text.textAlign = old
    }

    /**
     * Λεπτό αποκατάστασης μετά το «Τέλος» (9/11): κάθισε, χέρι ακίνητο, χωρίς ομιλία· στο τέλος του μετράμε πόσο έπεσαν
     * οι παλμοί. «Παράλειψη»: τέλος αμέσως, χωρίς μέτρηση.
     */
    private fun drawRecover(c: Canvas, now: Long) {
        small(c, "ΑΠΟΚΑΤΑΣΤΑΣΗ", 42f, green, ess(10f), 120f)
        t(c, "Κάθισε", 64f, Color.WHITE, 15f * fs, true)
        small(c, "χέρι ακίνητο, μη μιλάς", 64f + 16f * fs, Color.WHITE, ess(10.5f), 150f)
        val left = ((Repo.recoveryUntil - now + 999) / 1000).coerceAtLeast(0)
        // Round 8 (R8-U3 Β2): ίδια μορφή με την αντίστροφη μέτρηση του διαλείμματος («0:47», [clock]), όχι «47″».
        t(c, clock(left), 114f, Color.WHITE, 26f, true)
        sayAdd("Αποκατάσταση. Κάθισε, χέρι ακίνητο, μη μιλάς. ${secondsLeftText(left)}")
        heart(c, 134f, now, 11f)
        pill(c, "Παράλειψη", 168f, 92f, 30f, card, Color.WHITE, 11f * fs, desc = "Παράλειψη της αποκατάστασης") { actions.finishWorkout() }
    }

    // ------------------------------------------------------------------ τέλος
    private fun drawEnd(c: Canvas) {
        // Έλεγχος 13/11, round 7 (R7-A8-5): το αποτέλεσμα δεν γράφτηκε ούτε στην αναμονή ούτε στο Data Layer (γεμάτος χώρος):
        // όχι «✓ Αποθηκεύτηκε». Μένει στη μνήμη και ξαναδοκιμάζεται σε κάθε άνοιγμα (και με το «ΟΚ»).
        if (Repo.endUnsaved) return drawUnsaved(c)
        val note = Repo.notice
        // Με μήνυμα: όλα λίγο πιο ψηλά, ώστε οι 3 γραμμές να μη φτάνουν στο «ΟΚ» (γράμματα 1,3×).
        val up = if (note != null) 12f else 0f
        t(c, "✓", 76f - up, green, 32f, true)
        t(c, "Αποθηκεύτηκε", 100f - up, Color.WHITE, 13f * fs, true)
        if (note != null) {
            // Π.χ. «Σώθηκε ως τις 18:42: η εφαρμογή έκλεισε πριν το «Τέλος».» (V-A-03): ολόκληρο, σε ως 3 γραμμές.
            text.color = orange
            text.textSize = ess(10f) * u
            text.typeface = Typeface.DEFAULT
            val w = (140f * u).toInt()
            val tp = android.text.TextPaint(text).apply { textAlign = Paint.Align.LEFT }
            val layout = android.text.StaticLayout.Builder.obtain(note, 0, note.length, tp, w)
                .setAlignment(android.text.Layout.Alignment.ALIGN_CENTER)
                .setMaxLines(3)
                .setEllipsize(TextUtils.TruncateAt.END)
                .build()
            c.save()
            c.translate(cx - w / 2f, (106f - up) * u)
            layout.draw(c)
            c.restore()
            sayAdd("Αποθηκεύτηκε. $note")
        } else {
            small(c, "Περνάει στο κινητό", 118f, gray, ess(10f), 150f)
            small(c, "όταν είναι κοντά.", 118f + 12f * fs, gray, ess(10f), 150f)
            sayAdd("Αποθηκεύτηκε. Περνάει στο κινητό όταν είναι κοντά")
        }
        pill(c, "ΟΚ", if (note != null) 172f else 166f, 72f, if (note != null) 28f else 32f, card, Color.WHITE, 12f * fs, desc = "Εντάξει") { actions.doneOk() }
    }

    /** «Δεν αποθηκεύτηκε» (R7-A8-5): τίτλος σε κεχριμπάρι και τι να κάνεις, ολόκληρο (ως 6 γραμμές με γράμματα 1,3×). */
    private fun drawUnsaved(c: Canvas) {
        t(c, UNSAVED_TITLE, 64f, amber, 12f * fs, true)
        text.color = Color.WHITE
        text.textSize = ess(10f) * u
        text.typeface = Typeface.DEFAULT
        val w = (140f * u).toInt()
        val tp = android.text.TextPaint(text).apply { textAlign = Paint.Align.LEFT }
        val layout = android.text.StaticLayout.Builder.obtain(UNSAVED_TEXT, 0, UNSAVED_TEXT.length, tp, w)
            .setAlignment(android.text.Layout.Alignment.ALIGN_CENTER)
            .setMaxLines(6)
            .build()
        c.save()
        c.translate(cx - w / 2f, 72f * u)
        layout.draw(c)
        c.restore()
        sayAdd("$UNSAVED_TITLE. $UNSAVED_TEXT")
        pill(c, "ΟΚ", 172f, 72f, 28f, card, Color.WHITE, 12f * fs, desc = "Εντάξει") { actions.doneOk() }
    }

    // ------------------------------------------------------------------ αφή και περιστροφή
    private var downX = 0f
    private var downY = 0f

    // ------------------------------------------------------------------ TalkBack (έλεγχος γ2, W3-09)
    /**
     * Κάθε περιοχή της οθόνης ως «εικονικό» στοιχείο για το TalkBack, χωρίς βιβλιοθήκη: πρώτη η φράση με ό,τι δείχνει η
     * οθόνη, μετά τα κουμπιά με την περιγραφή τους· διπλό πάτημα = πάτημα του κουμπιού.
     */
    private val provider = object : AccessibilityNodeProvider() {
        override fun createAccessibilityNodeInfo(virtualViewId: Int): AccessibilityNodeInfo? {
            if (virtualViewId == View.NO_ID) {
                val info = AccessibilityNodeInfo.obtain(this@WatchView)
                onInitializeAccessibilityNodeInfo(info)
                for (i in a11y.indices) info.addChild(this@WatchView, i)
                return info
            }
            val h = a11y.getOrNull(virtualViewId) ?: return null
            val info = AccessibilityNodeInfo.obtain(this@WatchView, virtualViewId)
            info.packageName = context.packageName
            info.className = if (h.run != null) "android.widget.Button" else "android.widget.TextView"
            info.setParent(this@WatchView)
            info.contentDescription = h.label
            val r = android.graphics.Rect()
            h.r.roundOut(r)
            r.intersect(0, 0, width, height)
            @Suppress("DEPRECATION")
            info.setBoundsInParent(r)
            val loc = IntArray(2)
            getLocationOnScreen(loc)
            r.offset(loc[0], loc[1])
            info.setBoundsInScreen(r)
            info.isVisibleToUser = true
            info.isEnabled = true
            info.isFocusable = true
            if (h.run != null) {
                info.isClickable = true
                info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
            }
            return info
        }

        override fun performAction(virtualViewId: Int, action: Int, arguments: android.os.Bundle?): Boolean {
            if (virtualViewId == View.NO_ID) return performAccessibilityAction(action, arguments)
            return when (action) {
                AccessibilityNodeInfo.ACTION_CLICK -> a11yClick(virtualViewId)
                AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS, AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS -> true
                else -> false
            }
        }
    }

    override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = provider

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.x
                downY = e.y
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (abs(e.x - downX) > 20 * u || abs(e.y - downY) > 20 * u) return true
                // Έλεγχος 13/11 (S8-05): η οθόνη μόλις άλλαξε μόνη της (π.χ. έληξε το διάλειμμα, άναψε το όριο): το πάτημα
                // ξεκίνησε για κουμπί της προηγούμενης και δεν εκτελείται σε ό,τι βρέθηκε από κάτω ([tapAllowed]).
                if (!tapAllowed(clockEl(), autoChangedEl)) return true
                // Το τελευταίο που ζωγραφίστηκε είναι από πάνω.
                for (h in hits.asReversed()) {
                    val run = h.run ?: continue
                    if (h.r.contains(e.x, e.y)) {
                        performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        byTap = true
                        run()
                        invalidate()
                        return true
                    }
                }
                return true
            }
        }
        return super.onTouchEvent(e)
    }

    private var rotary = 0f

    override fun onGenericMotionEvent(e: MotionEvent): Boolean {
        if (e.action == MotionEvent.ACTION_SCROLL && e.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)) {
            // Σετ: οι επαναλήψεις του επόμενου σετ· διάλειμμα: του σετ που μόλις έγινε (RT-13).
            val rest = Repo.screen == Repo.Screen.REST
            if (Repo.screen != Repo.Screen.SET && !rest) return true
            rotary += -e.getAxisValue(MotionEvent.AXIS_SCROLL)
            // Ένα «κλικ» της περιστροφής = μία επανάληψη.
            val step = 1f
            while (abs(rotary) >= step) {
                val d = if (rotary > 0) 1 else -1
                rotary -= d * step
                if (rest) actions.lastReps(d) else actions.reps(d)
            }
            invalidate()
            return true
        }
        return super.onGenericMotionEvent(e)
    }
}

/**
 * Η επόμενη προπόνηση βαρών μετά την [shownId], κυκλικά στη σειρά του προγράμματος (null αν υπάρχει μόνο μία).
 * Το τρίτο κουμπί της αρχικής: πατώντας το ξανά και ξανά φτάνεις σε όλες.
 */
internal fun nextStrength(ids: List<String>, shownId: String): String? {
    if (ids.size < 2) return null
    val i = ids.indexOf(shownId)
    return ids[(i + 1).mod(ids.size)].takeIf { it != shownId }
}

/** «1 άσκηση» / «4 ασκήσεις». */
internal fun countText(n: Int, one: String, many: String): String = if (n == 1) "1 $one" else "$n $many"

/** Για το TalkBack (R7-U4-2): «Μένει 1 δευτερόλεπτο» / «Μένουν 45 δευτερόλεπτα» (πριν «Μένουν 1 δευτερόλεπτα»). */
internal fun secondsLeftText(n: Long): String = if (n == 1L) "Μένει 1 δευτερόλεπτο" else "Μένουν $n δευτερόλεπτα"

/** «Δεν ξέρω» στη ρεζέρβα (έλεγχος 13/11, round 7, R7-U3-04): καμία απάντηση, όπως στο κινητό. */
internal const val RIR_UNKNOWN = "Δεν ξέρω"

/** Στα πρώτα 30″ μιας άσκησης, πριν από τον πρώτο παλμό ([hrWaiting], R7-U3-05). */
internal const val HR_WAIT_TEXT = "♥ περιμένω παλμούς"

/** Για το TalkBack, όσο η δόνηση ζώνης δεν φτάνει στον καρπό (S8-02· round 7, R7-A7-1: και «Μην ενοχλείτε»). */
internal const val ZONE_MUTED_SAY = "Σίγαση, Μην ενοχλείτε ή εξοικονόμηση ενέργειας: χωρίς δόνηση ζώνης"

/** Η οθόνη του τέλους όταν το αποτέλεσμα δεν γράφτηκε πουθενά ([Repo.endUnsaved], R7-A8-5). Κείμενα προς έγκριση. */
internal const val UNSAVED_TITLE = "Δεν αποθηκεύτηκε"
internal const val UNSAVED_TEXT = "Μάλλον γέμισε ο χώρος του ρολογιού. Άδειασε λίγο χώρο και άνοιξε ξανά την εφαρμογή."

/** «Πρώτο σετ: πόσες ακόμα;» στην οθόνη της ρεζέρβας (R8-U3-01), σε δύο γραμμές, και για το TalkBack. Κείμενα προς έγκριση. */
internal const val FIRST_SET_LINE1 = "Πρώτο σετ:"
internal const val FIRST_SET_LINE2 = "πόσες ακόμα;"
internal const val FIRST_SET_SAY = "Πρώτο σετ: πόσες επαναλήψεις ακόμα θα έβγαζες με καλή τεχνική;"

/** Η προπόνηση κλείνει ακόμα, αντί για την αρχική (R8-A8-1). Κείμενα προς έγκριση. */
internal const val CLOSING_TITLE = "Αποθηκεύεται"
internal const val CLOSING_SUB = "μία στιγμή"

/**
 * Πόσο πλάτος (σε u· η οθόνη είναι κύκλος με διάμετρο 200u) έχει μια γραμμή κειμένου με βάση [y] και μέγεθος γραμμάτων
 * [size], αν μείνει [edge] u μέσα από την άκρη (έλεγχος 13/11, U7-03). Το κείμενο πιάνει από 0,86 × μέγεθος πάνω από τη
 * βάση (τόνοι και ψηλά γράμματα, μετρημένο στα στιγμιότυπα) ως 0,24 × μέγεθος κάτω (ουρές)· μετρά όποια από τις δύο
 * άκρες είναι πιο μακριά από το κέντρο. 0 αν δεν χωρά καθόλου. Καθαρή συνάρτηση, με δοκιμή.
 */
internal fun chordAt(y: Float, size: Float, edge: Float = 3f): Float {
    val top = y - 0.86f * size
    val bottom = y + 0.24f * size
    val d = maxOf(abs(top - 100f), abs(bottom - 100f))
    val r = 100f - edge
    return if (d >= r) 0f else 2f * kotlin.math.sqrt(r * r - d * d)
}

/**
 * Πού σπάει ένα μήνυμα σε δύο γραμμές (έλεγχος 13/11, round 2, R2-U3-03). [words]: οι λέξεις· [widthOf]: το πλάτος ενός
 * κειμένου, στις ίδιες μονάδες με τα [w1] / [w2] (πλάτος της πάνω / της κάτω γραμμής). Επιστρέφει πόσες λέξεις πάνε στην
 * πάνω γραμμή (≥ 1) και αν χωράνε και οι δύο γραμμές.
 * - Από τα σπασίματα που χωράνε, πρώτα αυτό που η πάνω γραμμή τελειώνει σε «:» («Πάτα ξανά:» / «επόμενη άσκηση»)· αλλιώς
 *   το πιο ισορροπημένο (κάθε γραμμή γεμίζει περίπου το ίδιο ποσοστό του πλάτους της). Πριν, προτιμούσε αυτό που άφηνε την
 *   πιο μικρή 2η γραμμή: «Πάτα ξανά: επόμενη» / «άσκηση» (μία λέξη μόνη της).
 * - Αν δεν χωρά κανένα: αυτό που ξεπερνά λιγότερο (όπως πριν), για να μικρύνουν τα γράμματα και να ξαναδοκιμαστεί.
 * Καθαρή συνάρτηση, με δοκιμή.
 */
internal fun twoLineSplit(words: List<String>, widthOf: (String) -> Float, w1: Float, w2: Float): Pair<Int, Boolean> {
    var nearest = 1
    var nearestOver = Float.MAX_VALUE
    var pick = -1
    var pickColon = false
    var pickBalance = Float.MAX_VALUE
    for (k in 1 until words.size) {
        val a = widthOf(words.subList(0, k).joinToString(" "))
        val b = widthOf(words.subList(k, words.size).joinToString(" "))
        val over = maxOf(a - w1, b - w2)
        if (over < nearestOver) {
            nearestOver = over
            nearest = k
        }
        if (over > 0f) continue
        val colon = words[k - 1].endsWith(':')
        val balance = abs(a / maxOf(w1, 1f) - b / maxOf(w2, 1f))
        if (pick < 0 || (colon && !pickColon) || (colon == pickColon && balance < pickBalance)) {
            pick = k
            pickColon = colon
            pickBalance = balance
        }
    }
    return if (pick > 0) pick to true else nearest to false
}
