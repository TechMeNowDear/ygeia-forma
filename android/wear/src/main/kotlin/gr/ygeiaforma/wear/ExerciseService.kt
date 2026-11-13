package gr.ygeiaforma.wear

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.LocationManager
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.media.AudioAttributes
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.concurrent.futures.await
import androidx.core.content.ContextCompat
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.BatchingMode
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DataTypeAvailability
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseEndReason
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseState
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.health.services.client.data.HeartRateAccuracy
import androidx.health.services.client.data.SampleDataPoint
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import android.annotation.SuppressLint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.time.Instant

/**
 * Υπηρεσία άσκησης: τρέχει ΜΟΝΟ από το «Ξεκίνα» ως το «Τέλος» (foreground, με ένδειξη στην πρόσοψη).
 * Health Services μετρά παλμούς (και απόσταση/βήματα με GPS στο περπάτημα)· εδώ: όριο γιατρού με δόνηση,
 * τέλος διαλείμματος με δόνηση, παλμοί προς το κινητό ανά 5″, αποτέλεσμα στο κινητό στο τέλος.
 */
class ExerciseService : Service() {

    companion object {
        const val TAG = "YgeiaWatch"
        const val ACTION_START = "gr.ygeiaforma.wear.START"
        const val ACTION_STOP = "gr.ygeiaforma.wear.STOP"
        const val ACTION_PAUSE = "gr.ygeiaforma.wear.PAUSE"
        const val ACTION_RESUME = "gr.ygeiaforma.wear.RESUME"
        /** Μετά από απότομο κλείσιμο: συνέχεια ή μερικό αποτέλεσμα (έλεγχος 9/11, V-A-03). */
        const val ACTION_RECOVER = "gr.ygeiaforma.wear.RECOVER"
        const val EXTRA_KIND = "kind"
        const val EXTRA_PHONE = "phone"
        const val EXTRA_MODE = "mode"
        /** Στιγμιότυπο της άσκησης το πολύ ανά τόσο (και σε παύση, τέλος, ✓). */
        const val RUN_SAVE_MS = 60_000L
        private const val NOTIF_ID = 41
        private const val ALARM_ID = 42
        private const val OTHER_ID = 43
        /** Υπενθύμιση για άσκηση που μοιάζει ξεχασμένη (έλεγχος 13/11, S8-06). */
        private const val FORGOT_ID = 44
        private const val CH_WORKOUT = "workout"
        // Νέο κανάλι (έλεγχος #2): χωρίς δική του δόνηση, για να μη «κόβει» τη δόνηση ξυπνητηριού της εφαρμογής.
        // Οι ρυθμίσεις ενός καναλιού δεν αλλάζουν μετά τη δημιουργία του, γι' αυτό νέο όνομα· το παλιό σβήνεται.
        private const val CH_ALARM = "hr_alarm2"
        private const val CH_ALARM_OLD = "hr_alarm"
        /** Το πολύ τόσο ξύπνιος ο επεξεργαστής στην αρχή, για τον έλεγχο «κανένας παλμός» (30″) και τη δόνησή του. */
        private const val FIRST_HR_LOCK_MS = HrSilence.FIRST_MS + 10_000L
        /** Το πολύ τόσο ξύπνιος ο επεξεργαστής σε ένα διάλειμμα, για τη δόνηση του τέλους του (W2-03). */
        private const val REST_LOCK_MAX_MS = 5 * 60_000L
        /** Το πολύ τόσο ξύπνιος ο επεξεργαστής στο λεπτό αποκατάστασης, για τη δόνηση του τέλους του (S8-01). */
        private const val RECOVERY_LOCK_MS = HrStats.RECOVERY_MS + 5_000L
        /** Κάθε πόσο κοιτά αν το ρολόι θα έκοβε τη δόνηση ζώνης (Σίγαση, Εξοικονόμηση ενέργειας· S8-02). */
        private const val MUTE_CHECK_MS = 5_000L

        fun start(ctx: Context, kind: String, phone: Boolean) {
            val i = Intent(ctx, ExerciseService::class.java).setAction(ACTION_START)
                .putExtra(EXTRA_KIND, kind).putExtra(EXTRA_PHONE, phone)
            ContextCompat.startForegroundService(ctx, i)
        }

        fun stop(ctx: Context) {
            if (Repo.running == null) return
            ctx.startService(Intent(ctx, ExerciseService::class.java).setAction(ACTION_STOP))
        }

        /** Άσκηση που έμεινε από απότομο κλείσιμο ([Recovery]). Από την οθόνη (σε πρώτο πλάνο). */
        fun recover(ctx: Context, action: Recovery.Action) {
            val i = Intent(ctx, ExerciseService::class.java).setAction(ACTION_RECOVER).putExtra(EXTRA_MODE, action.name)
            if (action == Recovery.Action.FINALIZE) ctx.startService(i) else ContextCompat.startForegroundService(ctx, i)
        }

        /** «Ώρα:λεπτά» για τα μηνύματα (π.χ. «σώθηκε ως τις 18:42»). */
        fun hm(ms: Long): String = java.text.SimpleDateFormat("HH:mm", java.util.Locale.ROOT).format(java.util.Date(ms))

        /** Παύση / συνέχεια του περπατήματος (9/11). */
        fun pause(ctx: Context, on: Boolean) {
            if (Repo.running != "walk") return
            ctx.startService(Intent(ctx, ExerciseService::class.java).setAction(if (on) ACTION_PAUSE else ACTION_RESUME))
        }

        /**
         * Χωρίς παλμούς ανά 5″ και χωρίς αισθητήρα αφύπνισης, με όριο (W3-10). Χωρίς αριθμό: δεν έχει μετρηθεί στο ρολόι
         * (έλεγχος του γ2, S1). Κείμενο προς έγκριση από τον χρήστη.
         */
        const val SLOW_ALARM_NOTICE = SLOW_ALARM_TEXT

        fun has(ctx: Context, p: String) = ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED

        /** Η άδεια παλμών: «health.READ_HEART_RATE» από το Wear OS 6 (API 36), «BODY_SENSORS» πριν. */
        val heartPermission: String
            get() = if (Build.VERSION.SDK_INT >= 36) "android.permission.health.READ_HEART_RATE" else Manifest.permission.BODY_SENSORS
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val client by lazy { HealthServices.getClient(this).exerciseClient }
    private var ticker: Job? = null
    /** Η έναρξη της άσκησης στο Health Services, όσο δεν έχει απαντήσει (τελικός έλεγχος, Συμβούλιο 4, W-1). */
    private var startJob: Job? = null
    private var restBuzzedFor = 0L
    private var lastHrSent = 0L
    private var lastLiveSent = 0L
    /** «Δεν μετριούνται παλμοί» με όριο: μία δόνηση (V-A-04). */
    private val silence = HrSilence()

    /**
     * Ο επεξεργαστής ξύπνιος ώσπου να έρθει ο πρώτος παλμός (έλεγχος του #90, Σ-1): με σβηστή οθόνη ο βρόχος του
     * δευτερολέπτου σταματά, και ακριβώς όταν δεν έρχονται παλμοί δεν υπάρχει τίποτα άλλο να τον ξυπνήσει. Μόνο με όριο,
     * το πολύ [FIRST_HR_LOCK_MS] (40″) μία φορά ανά άσκηση· αφήνεται στον πρώτο παλμό ή μόλις γίνει ο έλεγχος των 30″.
     * Μπαταρία: το πολύ 40″ ξύπνιος επεξεργαστής ανά έναρξη (η άσκηση ήδη κρατά τους αισθητήρες ανοιχτούς).
     */
    private var firstHrLock: PowerManager.WakeLock? = null
    private var lastPendingSent = 0L
    /** Εφεδρεία αισθητήρα για την ειδοποίηση (μόνο χωρίς παράδοση ανά 5″ και με όριο). */
    private var sensor: HrSensor? = null
    private var exerciseStarted = false
    private var stopping = false
    /** Το Health Services δέχτηκε παλμούς σε αυτή την άσκηση (για να ξεκινήσει η εφεδρεία αν το όριο έρθει αργότερα, W2-04). */
    private var hrInExercise = false
    /** Ο επεξεργαστής ξύπνιος ως το τέλος του διαλείμματος ([restLockFor]), για τη δόνηση (έλεγχος γ2, W2-03). */
    private var restLock: PowerManager.WakeLock? = null
    private var restLockFor = 0L
    /** Ήρθε η τελευταία ενημέρωση («ENDED») μετά το «Τέλος» (W2-09). */
    private var ended: CompletableDeferred<Unit>? = null
    /** Ο διάλειμμα/κατάσταση αλλάζει και από την οθόνη ή το κινητό: ο επεξεργαστής κρατιέται ξύπνιος αμέσως (W2-03). */
    private val onRepo: () -> Unit = { holdForRest() }
    /** Πότε γράφτηκε το τελευταίο στιγμιότυπο (elapsedRealtime). */
    private var lastRunSave = 0L
    /** Η ένδειξη στην πρόσοψη (για να αλλάζει στην παύση). */
    private var ongoingActivity: OngoingActivity? = null
    private var ongoingTitle = ""

    /** Ο επεξεργαστής ξύπνιος στο λεπτό αποκατάστασης (ως 70″), για να έρθει στην ώρα της η δόνηση του τέλους (S8-01). */
    private var recoveryLock: PowerManager.WakeLock? = null

    /** Σίγαση / Εξοικονόμηση ενέργειας (S8-02): πότε κοιτάχτηκε τελευταία, και ποιο μήνυμα έχει ήδη ειπωθεί. */
    private var lastMuteCheckEl = 0L
    private var zoneMuteTold: String? = null

    /**
     * Το τελευταίο «ελαφρύ» μήνυμα που έβαλε η υπηρεσία στην οθόνη (χωρίς δόνηση ζώνης, ξεχασμένη άσκηση): σβήνεται στο
     * τέλος της άσκησης, για να μη μείνει κάτω από το «Αποθηκεύτηκε» μια ερώτηση που δεν ισχύει πια.
     */
    private var softNotice: String? = null

    /**
     * Ξεχασμένη άσκηση (S8-06): το «αποτύπωμα» των ✓ (αλλάζει σε κάθε ✓, εδώ ή στο κινητό), πότε άλλαξε τελευταία, από
     * πότε κρατά η παύση (−1 = όχι σε παύση) και πότε έγινε η τελευταία υπενθύμιση. Χρόνοι από την εκκίνηση (elapsedRealtime).
     */
    private var actSig = -1
    private var lastActionEl = 0L
    private var pausedSinceEl = -1L
    private var forgotBuzzEl = 0L

    /**
     * Η αρχή της άσκησης σε elapsedRealtime (ms), για την προθέρμανση της ζώνης και την υπενθύμιση «3 ώρες» (έλεγχος 13/11,
     * round 7, R7-A7-3). Μετά από απότομο κλείσιμο ΔΕΝ είναι η στιγμή της συνέχειας ([Repo.startedEl], που μένει για την
     * αναμονή 30″ του πρώτου παλμού) αλλά η πραγματική αρχή ([zoneWarmupStartEl]).
     */
    private var originEl = 0L

    /**
     * Ξυπνητήρι για τον έλεγχο «χάθηκαν παλμοί» με σβηστή οθόνη (S8-07): ξαναοπλίζεται σε κάθε παράδοση παλμών, μόνο με
     * όριο γιατρού. Ίδια μορφή με το διάλειμμα του κινητού (TrainingBridge.arm): καλεί κατευθείαν εδώ, χωρίς άδεια
     * «Ξυπνητήρια και υπενθυμίσεις». [silenceAlarmAt]: για πότε είναι οπλισμένο (0 = όχι).
     */
    private val silenceHandler = Handler(Looper.getMainLooper())
    private val silenceAlarm = AlarmManager.OnAlarmListener { onSilenceAlarm() }
    private var silenceAlarmAt = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Link.attach(this)
        channels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> begin(intent.getStringExtra(EXTRA_KIND) ?: "strength", intent.getBooleanExtra(EXTRA_PHONE, false))
            ACTION_RECOVER -> recover(intent.getStringExtra(EXTRA_MODE))
            ACTION_STOP -> scope.launch { stopRequested() }
            ACTION_PAUSE -> scope.launch { setPaused(true) }
            ACTION_RESUME -> scope.launch { setPaused(false) }
            else -> if (Repo.running == null) stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Repo.unlisten(onRepo)
        releaseRestLock()
        releaseFirstHrLock()
        releaseRecoveryLock()
        cancelSilenceAlarm()
        sensor?.stop()
        sensor = null
        ticker?.cancel()
        scope.cancel()
        Link.detach(this)
        super.onDestroy()
    }

    // ------------------------------------------------------------------ έναρξη
    private fun begin(kind: String, phone: Boolean) {
        if (Repo.running != null) {
            // Ήδη τρέχει: απλώς ενημερώνει τον τρόπο (π.χ. η προπόνηση του κινητού βρήκε το ρολόι). Όχι όμως σε
            // περπάτημα: αλλιώς το περπάτημα θα τελείωνε μαζί με την προπόνηση του κινητού (DP-10).
            if (Repo.running != "walk") {
                Repo.runningPhone = phone
                if (phone && Repo.runningSid == null) Repo.runningSid = Repo.phone?.id
            }
            return
        }
        // Άσκηση που έμεινε από απότομο κλείσιμο και δεν ελέγχθηκε ακόμα: πρώτα γράφεται ως μερική (ένα αποτέλεσμα).
        Repo.readRun(this)?.let { o -> finalizeLeftover(o)?.let { r -> scope.launch { put(r) } } }
        val now = System.currentTimeMillis()
        Repo.resetExercise()
        Repo.running = kind
        Repo.runningPhone = phone
        Repo.runningSid = if (phone) Repo.phone?.id else null
        Repo.startedAt = now
        Repo.startedEl = SystemClock.elapsedRealtime()
        Repo.hr = HrStats(now)
        Repo.split = SplitTracker(now)
        // Το όριο του προγράμματος, αλλιώς το τελευταίο που ήρθε από το κινητό (V-A-06: και χωρίς πρόγραμμα στο ρολόι).
        Repo.alarm.limit = Repo.limitNow()
        Repo.alarm.reset()
        silence.reset()
        // S8-04: διάλειμμα της προπόνησης του κινητού που είχε ήδη λήξει πριν ξεκινήσει η μέτρηση δεν δονείται.
        restBuzzedFor = restAlreadyOver(Repo.session?.restEnd, now)
        // S8-06: η «τελευταία κίνηση» μετρά από την αρχή.
        actSig = activitySignature()
        lastActionEl = Repo.startedEl
        pausedSinceEl = -1L
        forgotBuzzEl = 0L
        originEl = Repo.startedEl

        val walk = kind == "walk"
        // Ζώνη περπατήματος (12/11): μόνο στο περπάτημα, από το πρόγραμμα του κινητού.
        Repo.zoneAlarm.start(if (walk) Repo.zoneNow() else null, originEl)
        // GPS μόνο με άδεια ΚΑΙ με την τοποθεσία του ρολογιού ανοιχτή (αλλιώς το Health Services αρνείται την άσκηση).
        val location = walk && has(this, Manifest.permission.ACCESS_FINE_LOCATION) && locationOn()
        Repo.gps = location
        var type = 0
        if (Build.VERSION.SDK_INT >= 34) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        if (location) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        val n = ongoing(if (walk) "Περπάτημα" else (Repo.session?.name ?: "Προπόνηση"))
        val gpsOk = startForegroundOrWithoutGps(n, type, location)
        if (gpsOk == null) {
            Repo.notice = "Δεν ξεκίνησε η μέτρηση: λείπει άδεια."
            Repo.resetExercise()
            Repo.changed()
            stopSelf()
            return
        }
        Repo.gps = gpsOk
        Repo.hrGaps.start(now)
        Repo.listen(onRepo)
        Repo.changed()
        holdUntilFirstHr()
        saveRun(force = true)
        startJob = scope.launch { startExercise(walk, gpsOk) }
        ticker = scope.launch { tick() }
    }

    /**
     * Υπηρεσία προσκηνίου. Αν το σύστημα αρνηθεί τον τύπο «τοποθεσία» (π.χ. κλειστή τοποθεσία, έλεγχος γ2, W2-21), ξανά
     * μόνο με «υγεία»: το περπάτημα γράφεται χωρίς GPS αντί να μη γραφτεί καθόλου. Επιστρέφει αν έχει GPS, ή null αν απέτυχε.
     */
    private fun startForegroundOrWithoutGps(n: Notification, type: Int, location: Boolean): Boolean? {
        try {
            ServiceCompat.startForeground(this, NOTIF_ID, n, type)
            return location
        } catch (e: Exception) {
            Log.e(TAG, "startForeground", e)
            Repo.lastErr = why(e)
            if (!location) return null
        }
        return try {
            ServiceCompat.startForeground(this, NOTIF_ID, n, type and ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION.inv())
            false
        } catch (e: Exception) {
            Log.e(TAG, "startForeground (χωρίς GPS)", e)
            Repo.lastErr = why(e)
            null
        }
    }

    // ------------------------------------------------------------------ μετά από απότομο κλείσιμο (V-A-03)
    /**
     * [mode]: [Recovery.Action]. ATTACH: ξανά ακροατής στην άσκηση που το Health Services κρατά ακόμα για εμάς (οι τιμές
     * του ενδιάμεσου έρχονται από την κρυφή του μνήμη). RESUME: προπόνηση με βάρη του ρολογιού, συνεχίζει με νέα μέτρηση.
     * FINALIZE: μερικό αποτέλεσμα με ό,τι είχε σωθεί.
     */
    private fun recover(mode: String?) {
        if (Repo.running != null) return
        val o = Repo.readRun(this)
        val action = try { Recovery.Action.valueOf(mode ?: "") } catch (_: Exception) { Recovery.Action.FINALIZE }
        if (o == null) {
            if (action != Recovery.Action.FINALIZE) quitForeground()
            stopSelf()
            return
        }
        if (action == Recovery.Action.FINALIZE) {
            val saved = o.optLong("saved", System.currentTimeMillis())
            val r = finalizeLeftover(o)
            if (r != null) {
                Repo.screen = if (o.optBoolean("phone", false)) Repo.Screen.HOME else Repo.Screen.END
                Repo.notice = "Σώθηκε ως τις ${hm(saved)}: η εφαρμογή έκλεισε πριν το «Τέλος»."
            }
            Repo.changed()
            // Πρώτα στο Data Layer, μετά τέλος της υπηρεσίας (αλλιώς η αποστολή θα ακυρωνόταν).
            scope.launch {
                if (r != null) put(r)
                if (Repo.running == null) stopSelf()
            }
            return
        }
        val now = System.currentTimeMillis()
        // Το κανονικό αποτέλεσμα αυτής της άσκησης περιμένει ήδη: έχει τελειώσει, δεν «ξαναζεί» (S3).
        val runId = Repo.runId(o)
        if (runId != null && Repo.hasFinalPending(this, runId)) {
            Repo.clearRun(this)
            quitForeground()
            stopSelf()
            return
        }
        if (!Repo.restoreRun(o, now, SystemClock.elapsedRealtime())) {
            // Δεν διαβάζεται: κρατιέται στην άκρη, όχι σβήσιμο (S4).
            Repo.quarantineRun(this)
            Repo.notice = Repo.BAD_RUN_NOTICE
            Repo.changed()
            quitForeground()
            stopSelf()
            return
        }
        silence.reset()
        // S8-04 / S8-06: όπως στην έναρξη (η παύση που βρέθηκε μετρά από τη συνέχεια).
        restBuzzedFor = restAlreadyOver(Repo.session?.restEnd, now)
        actSig = activitySignature()
        lastActionEl = Repo.startedEl
        pausedSinceEl = if (Repo.paused) Repo.startedEl else -1L
        forgotBuzzEl = 0L
        // R7-A7-3: η προθέρμανση των 5′ και οι «3 ώρες» από την ΑΡΧΗ της άσκησης, όχι από τη συνέχεια.
        originEl = zoneWarmupStartEl(Repo.startedEl, now, Repo.startedAt)
        val walk = Repo.running == "walk"
        Repo.zoneAlarm.start(if (walk) Repo.zoneNow() else null, originEl)
        val location = walk && Repo.gps && has(this, Manifest.permission.ACCESS_FINE_LOCATION) && locationOn()
        var type = 0
        if (Build.VERSION.SDK_INT >= 34) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        if (location) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        val gpsOk = startForegroundOrWithoutGps(ongoing(if (walk) "Περπάτημα" else (Repo.session?.name ?: "Προπόνηση")), type, location)
        if (gpsOk == null) {
            // Δεν μπορεί να συνεχίσει: ό,τι σώθηκε γράφεται ως μερικό (τίποτα δεν χάνεται).
            val saved = o.optLong("saved", now)
            Repo.resetExercise()
            Repo.local = null
            val r = finalizeLeftover(o)
            if (r != null) Repo.notice = "Σώθηκε ως τις ${hm(saved)}: η εφαρμογή έκλεισε πριν το «Τέλος»."
            Repo.changed()
            scope.launch {
                if (r != null) put(r)
                if (Repo.running == null) stopSelf()
            }
            return
        }
        if (location && !gpsOk) Repo.gps = false
        Repo.hrGaps.start(System.currentTimeMillis())
        Repo.listen(onRepo)
        Repo.notice = "Συνεχίζει: η εφαρμογή είχε κλείσει απότομα."
        Repo.screen = when {
            walk -> if (Repo.recoveryUntil > 0) Repo.Screen.RECOVER else Repo.Screen.WALK
            else -> Repo.Screen.SET
        }
        Repo.changed()
        // Νέα αναμονή 30″ για τον πρώτο παλμό από εδώ (S2), με τον επεξεργαστή ξύπνιο ως τότε.
        holdUntilFirstHr()
        if (action == Recovery.Action.ATTACH) {
            scope.launch { attach() }
        } else {
            startJob = scope.launch { startExercise(walk, walk && Repo.gps) }
        }
        saveRun(force = true)
        ticker = scope.launch { tick() }
    }

    /** Ξανά ακροατής στην άσκηση που τρέχει ακόμα (δική μας). Οι ενημερώσεις του ενδιάμεσου έρχονται αμέσως. */
    private fun attach() {
        try {
            client.setUpdateCallback(callback)
            exerciseStarted = true
            // Εφεδρεία αισθητήρα όπως πριν (μόνο αν τη χρησιμοποιούσε και υπάρχει όριο).
            hrInExercise = has(this, heartPermission)
            if (Repo.hrMode == "sensor" && Repo.fastHr() && hrInExercise) startSensor()
            // Συνέχεια σε ρολόι που στέλνει αργά: το μήνυμα ασφάλειας ξανά, πρώτο (S1).
            if (Repo.hrMode == "default" && Repo.alarm.limit != null && hrInExercise) {
                Repo.notice = withSafety(SLOW_ALARM_NOTICE, Repo.notice)
                Repo.openNotice = true
            }
        } catch (e: Exception) {
            Log.e(TAG, "attach", e)
            Repo.lastErr = why(e)
            Repo.notice = "Δεν συνεχίστηκε η μέτρηση: ${why(e)}"
            Repo.changed()
        }
    }

    /**
     * Το στιγμιότυπο [o] ως μερικό αποτέλεσμα (ίδιο id με το κανονικό, «partial»), στην αναμονή και στο κινητό. Η άσκηση
     * που ετοιμάζεται τώρα (π.χ. η νέα προπόνηση του ρολογιού) δεν πειράζεται. Επιστρέφει το αποτέλεσμα (ήδη στην
     * αναμονή), για [put].
     */
    private fun finalizeLeftover(o: JSONObject): Pair<String, JSONObject>? =
        Repo.finalizeRun(this, o, System.currentTimeMillis(), SystemClock.elapsedRealtime())

    /**
     * Ξεκίνησε με startForegroundService αλλά δεν υπάρχει τίποτα να συνεχίσει: το σύστημα θέλει πάντα startForeground
     * (αλλιώς κλείνει την εφαρμογή με σφάλμα)· αμέσως μετά φεύγει.
     */
    private fun quitForeground() {
        try {
            val type = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH else 0
            ServiceCompat.startForeground(this, NOTIF_ID, NotificationCompat.Builder(this, CH_WORKOUT).setSmallIcon(R.drawable.ic_heart).build(), type)
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
    }

    /** Στο Data Layer· από την αναμονή σβήνεται μόνο αν μπήκε. */
    private suspend fun put(r: Pair<String, JSONObject>) {
        if (Link.putResult(this, r.first, r.second)) Repo.removePending(this, r.first)
    }

    /** Στιγμιότυπο της άσκησης (V-A-03): το πολύ ανά [RUN_SAVE_MS], ή αμέσως ([force]: παύση, τέλος, έναρξη). */
    private fun saveRun(force: Boolean = false) {
        if (stopping) return
        val nowEl = SystemClock.elapsedRealtime()
        if (!force && nowEl - lastRunSave < RUN_SAVE_MS) return
        lastRunSave = nowEl
        // Η κατάσταση αντιγράφεται εδώ· το κείμενο φτιάχνεται εκτός οθόνης. Με τη «γενιά» της στιγμής: αν η άσκηση
        // τελειώσει πριν γραφτεί, δεν γράφεται (S3).
        val o = Repo.captureRun(System.currentTimeMillis()) ?: return
        val gen = Repo.runGen
        scope.launch(Dispatchers.IO) { Repo.writeRun(this@ExerciseService, o.toString(), gen) }
    }

    private fun holdUntilFirstHr() {
        if (Repo.alarm.limit == null) return
        try {
            val pm = getSystemService(PowerManager::class.java) ?: return
            firstHrLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ygeia:firstHr").apply {
                setReferenceCounted(false)
                acquire(FIRST_HR_LOCK_MS)
            }
        } catch (e: Exception) {
            Log.w(TAG, "wakelock", e)
        }
    }

    private fun releaseFirstHrLock() {
        val l = firstHrLock ?: return
        firstHrLock = null
        try {
            if (l.isHeld) l.release()
        } catch (_: Exception) {
        }
    }

    private suspend fun startExercise(walk: Boolean, location: Boolean) {
        if (!has(this, heartPermission)) {
            Repo.notice = "Χωρίς άδεια παλμών: η προπόνηση γράφεται, οι παλμοί όχι."
            Repo.changed()
            if (!walk) return
        }
        try {
            val caps = client.getCapabilitiesAsync().await()
            val wanted = if (walk) listOf(ExerciseType.WALKING) else listOf(ExerciseType.STRENGTH_TRAINING, ExerciseType.WEIGHTLIFTING, ExerciseType.WORKOUT)
            val type = wanted.firstOrNull { it in caps.supportedExerciseTypes } ?: run {
                Repo.notice = "Το ρολόι δεν υποστηρίζει μέτρηση για αυτή την άσκηση."
                Repo.changed()
                return
            }
            val supported = caps.getExerciseTypeCapabilities(type).supportedDataTypes
            val types = mutableSetOf<DataType<*, *>>()
            if (has(this, heartPermission)) types.add(DataType.HEART_RATE_BPM)
            if (walk) {
                types.add(DataType.DISTANCE_TOTAL)
                types.add(DataType.STEPS_TOTAL)
                if (location) types.add(DataType.LOCATION)
            }
            types.retainAll(supported)
            client.setUpdateCallback(callback)
            // Παλμοί κάθε ~5″ και με σβηστή οθόνη (χωρίς αυτό το ρολόι τους στέλνει σε πακέτα ανά λίγα λεπτά).
            val batching = if (DataType.HEART_RATE_BPM in types && BatchingMode.HEART_RATE_5_SECONDS in caps.supportedBatchingModeOverrides) {
                setOf(BatchingMode.HEART_RATE_5_SECONDS)
            } else {
                emptySet()
            }
            // Σε κάποια ρολόγια (Galaxy, One UI 9) το Health Services αρνείται όλη την άσκηση για την τοποθεσία, παρότι
            // η άδεια έχει δοθεί (logcat 9/11: WHS_PermissionPolicy, ACCESS_FINE_LOCATION). Τότε ξανά χωρίς GPS, και
            // στο τέλος μόνο με παλμούς: οι παλμοί και η ειδοποίηση ορίου μετράνε περισσότερο από την απόσταση.
            val tries = buildList {
                add(types.toSet())
                if (DataType.LOCATION in types) add(types - DataType.LOCATION)
                if (DataType.HEART_RATE_BPM in types && types.size > 1) add(setOf<DataType<*, *>>(DataType.HEART_RATE_BPM))
            }.distinct()
            var last: Exception? = null
            var used: Set<DataType<*, *>>? = null
            for (t in tries) {
                try {
                    client.startExerciseAsync(
                        ExerciseConfig(
                            exerciseType = type,
                            dataTypes = t,
                            isAutoPauseAndResumeEnabled = false,
                            isGpsEnabled = DataType.LOCATION in t,
                            batchingModeOverrides = if (DataType.HEART_RATE_BPM in t) batching else emptySet(),
                        ),
                    ).await()
                    used = t
                    break
                } catch (e: Exception) {
                    Log.w(TAG, "startExercise ${t.map { it.name }}", e)
                    last = e
                }
            }
            if (used == null) throw last ?: IllegalStateException("startExercise")
            if (location && DataType.LOCATION !in used) Repo.gps = false
            // Ό,τι δεν μετριέται, ειπωμένο σωστά (έλεγχος γ2, RT-18: χωρίς απόσταση και βήματα όχι «από τα βήματα»).
            val hrOk = DataType.HEART_RATE_BPM in used
            val distOk = !walk || DataType.DISTANCE_TOTAL in used || DataType.STEPS_TOTAL in used
            walkStartNotice(walk && location, DataType.LOCATION in used, distOk, hrOk)?.let {
                Repo.notice = it
                Repo.changed()
            }
            exerciseStarted = true
            hrInExercise = hrOk
            Repo.hrMode = if (hrOk && batching.isNotEmpty()) "5s" else "default"
            // Για τον έλεγχο στη συσκευή (W2-14/W3-10): τι μπορεί το ρολόι. Στη σύνοψη του κινητού και στο logcat.
            Repo.diag = "5s=${if (BatchingMode.HEART_RATE_5_SECONDS in caps.supportedBatchingModeOverrides) 1 else 0} wake=${if (HrSensor.hasWakeUp(this)) 1 else 0}"
            Log.i(TAG, "hrMode=${Repo.hrMode} ${Repo.diag} types=${used.map { it.name }}")
            // Χωρίς παράδοση ανά 5″: με σβηστή οθόνη οι παλμοί μπορεί να έρθουν σε πακέτα με καθυστέρηση λεπτών.
            // Για την ειδοποίηση ορίου, τότε και μόνο, ο αισθητήρας απευθείας (μόνο όσο τρέχει η άσκηση).
            // 12/11: και για τη δόνηση ζώνης στο περπάτημα (Repo.fastHr).
            if (Repo.hrMode == "default" && hrOk && Repo.fastHr()) startSensor()
            // Ούτε ανά 5″ ούτε αισθητήρας αφύπνισης: το λέμε, όχι σιωπηλά (έλεγχος γ2, W3-10).
            // Πρώτο, πριν από κάθε άλλο μήνυμα (π.χ. «Χωρίς GPS…»), ώστε να μην κρύβεται (S1).
            val slow = Repo.hrMode == "default" && hrOk && Repo.alarm.limit != null
            if (slow) {
                Repo.notice = withSafety(SLOW_ALARM_NOTICE, Repo.notice)
                // Ολόκληρο, σε όλη την οθόνη ώσπου να το πατήσεις (σε μία γραμμή θα κοβόταν).
                Repo.openNotice = true
                Repo.changed()
            }
            // Και στο κινητό (κάρτα ορίου, πριν από την επόμενη άσκηση): «/ygeia/wstate» με «slow».
            if (hrOk) Link.setSlow(this, Repo.hrMode == "default")
        } catch (e: Exception) {
            // Η αιτία στην οθόνη και στο logcat (ετικέτα «YgeiaWatch»): χωρίς αυτήν δεν διορθώνεται (9/11).
            Log.e(TAG, "startExercise", e)
            Repo.lastErr = why(e)
            Repo.notice = "Δεν ξεκίνησε η μέτρηση: ${why(e)}"
            Repo.changed()
        }
    }

    /**
     * Εφεδρεία αισθητήρα (μόνο αισθητήρας αφύπνισης, W2-04). Οι τιμές του περνούν αμέσως, μέσα στην παράδοση (όχι
     * αργότερα σε άλλη εργασία: ο επεξεργαστής μένει ξύπνιος μόνο όσο κρατά η παράδοση).
     */
    private fun startSensor() {
        if (sensor != null) return
        val s = HrSensor(this) { bpm, at, atEl -> onSensorBpm(bpm, at, atEl) }
        if (s.start()) {
            sensor = s
            Repo.hrMode = "sensor"
        }
    }

    private fun stopSensor() {
        val s = sensor ?: return
        s.stop()
        sensor = null
        if (Repo.hrMode == "sensor") Repo.hrMode = "default"
    }

    private fun locationOn(): Boolean = try {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        lm.isLocationEnabled && lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
    } catch (_: Exception) {
        false
    }

    /** Σύντομη αιτία για την οθόνη: το είδος του σφάλματος και η αρχή του μηνύματος. */
    private fun why(e: Throwable): String {
        val c = (e.cause ?: e)
        return "${c.javaClass.simpleName}: ${c.message.orEmpty()}".take(90)
    }

    private val callback = object : ExerciseUpdateCallback {
        override fun onRegistered() {}

        override fun onRegistrationFailed(throwable: Throwable) {
            Log.e(TAG, "registration", throwable)
            Repo.lastErr = why(throwable)
            Repo.notice = "Δεν ξεκίνησε η μέτρηση: ${why(throwable)}"
            Repo.changed()
        }

        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            val now = System.currentTimeMillis()
            val nowEl = SystemClock.elapsedRealtime()
            val m = update.latestMetrics
            // Κάθε τιμή με τον δικό της χρόνο (σε ένα πακέτο μπορεί να έρθουν πολλές).
            val boot = Instant.ofEpochMilli(now - nowEl)
            var buzz = -1
            var buzzEl = 0L
            val hrElBefore = Repo.bpmEl
            val points = m.getData(DataType.HEART_RATE_BPM)
            // Μετά το «Τέλος» (αναμονή της ENDED) καμία δόνηση ορίου (έλεγχος του γ2, NIT 3).
            val alarmOk = !stopping
            // Πόσες τιμές αυτής της παράδοσης χρησιμοποιήθηκαν (για το μεγαλύτερο κενό, R7-A7-2).
            var usable = 0
            for (p in points) {
                // Τελικός έλεγχος (Συμβούλιο 1, Σ1): πρώτα τι λέει το ίδιο το ρολόι για την τιμή. «Χωρίς επαφή» ή
                // «αναξιόπιστη» δεν μπαίνει πουθενά (ούτε μέσος/υψηλότερος, ούτε ζώνη, ούτε όριο, ούτε ένδειξη): αν
                // λείψουν οι καλές τιμές, η οθόνη λέει «δεν μετριούνται» και με όριο δονείται, όπως όταν δεν έρχεται
                // τίποτα. Οι «χαμηλής ακρίβειας» μένουν όπως πριν και μόνο μετριούνται (HrQuality).
                val quality = heartQuality(p)
                Repo.hrQuality.add(quality)
                val bpm = Math.round(p.value).toInt()
                if (!hrValueUsable(quality, bpm)) continue
                usable++
                val at = p.getTimeInstant(boot).toEpochMilli().coerceAtMost(now)
                // Για την ειδοποίηση: χρόνος από την εκκίνηση (μονότονος), όχι ώρα τοίχου (έλεγχος 9/11, W3-14).
                val atEl = p.timeDurationFromBoot.toMillis().coerceAtMost(nowEl)
                Repo.hr?.add(bpm, at)
                if (at >= Repo.bpmAt) {
                    Repo.bpm = bpm
                    Repo.bpmAt = at
                }
                if (atEl > Repo.bpmEl) Repo.bpmEl = atEl
                // Και οι δύο πηγές πάνε στην ειδοποίηση· οι παλιότερες τιμές αγνοούνται (HrAlarm.feed), οπότε αν ο
                // αισθητήρας σωπάσει, συνεχίζει το Health Services (έλεγχος #2, W2-04).
                if (Repo.alarm.feed(bpm, atEl)) {
                    buzz = bpm
                    buzzEl = atEl
                }
                zoneCheck(bpm, atEl, nowEl)
            }
            // Το κενό στους παλμούς είναι όσο δεν έφτανε καμία τιμή που χρησιμοποιείται (W2-08· έλεγχος 13/11, round 7,
            // R7-A7-2): μια παράδοση μόνο με τιμές «χωρίς επαφή» δεν μετρά ως «ήρθαν παλμοί».
            if (usable > 0) Repo.hrGaps.mark(now)
            // Σταθεροί παλμοί χωρίς νέα τιμή (όχι στο «5s», που στέλνει κάθε 5″): κρίνονται και σε κάθε ενημέρωση, όχι μόνο
            // στον βρόχο του δευτερολέπτου, που σταματά με σβηστή οθόνη (W2-02, W3-10).
            if (buzz < 0 && Repo.hrMode != "5s" && Repo.hrLive(now) && Repo.alarm.steady(Repo.bpm, nowEl)) {
                buzz = Repo.bpm
                // Με την ηλικία της τελευταίας τιμής, όχι «τώρα» (NIT 4).
                buzzEl = if (Repo.bpmEl > 0) Repo.bpmEl else nowEl
            }
            // Από πακέτο με καθυστέρηση (W2-17): με την ηλικία της τιμής· καμία δόνηση αν έπεσαν ήδη και πέρασαν >30″.
            if (buzz > 0 && alarmOk) {
                val age = nowEl - buzzEl
                val lim = Repo.alarm.limit
                if (lateAlarmBuzz(age, lim != null && Repo.alarm.lastBpm >= lim)) onAlarm(buzz, age)
                // Χωρίς την τιμή των παλμών (έλεγχος 13/11, S10-5): το logcat μπαίνει και στις αναφορές σφάλματος του συστήματος.
                else Log.i(TAG, "όριο: παλιά τιμή πριν ${age / 1000}″, οι παλμοί έπεσαν ήδη (χωρίς δόνηση)")
            }
            // S8-07: ήρθε νεότερη τιμή: το ξυπνητήρι του «χάθηκαν παλμοί» πάει πιο πέρα.
            if (Repo.bpmEl > hrElBefore) armSilenceAlarm(Repo.bpmEl)
            if (points.isNotEmpty()) sendHrToPhone(now)
            // Μετά το «Τέλος» (λεπτό αποκατάστασης) χρόνος, απόσταση και βήματα μένουν όπως ήταν· μόνο οι παλμοί.
            if (Repo.recoveryUntil == 0L) {
                update.activeDurationCheckpoint?.let { c ->
                    // Σημείο ελέγχου: ο χρόνος στην οθόνη προχωρά κάθε δευτερόλεπτο από εδώ (W3-12). Σε παύση δεν τρέχει.
                    Repo.cpActiveMs = c.activeDuration.toMillis()
                    Repo.cpWall = c.time.toEpochMilli()
                    Repo.cpRunning = update.exerciseStateInfo.state == ExerciseState.ACTIVE
                    Repo.activeSec = Repo.activeSecNow(now)
                }
                m.getData(DataType.DISTANCE_TOTAL)?.let { d ->
                    Repo.meters = d.total
                    // Κάθε ολόκληρο χιλιόμετρο τη στιγμή που περάστηκε (με τον χρόνο της τιμής, V-A-19).
                    if (Repo.running == "walk") {
                        val at = d.end.toEpochMilli().coerceAtMost(now)
                        Repo.split.update(d.total, at, activeAtWall(Repo.cpActiveMs, Repo.cpWall, Repo.cpRunning, at, Repo.activeSec))
                    }
                }
                m.getData(DataType.STEPS_TOTAL)?.let { Repo.steps = it.total }
            }
            if (update.exerciseStateInfo.state.isEnded) ended?.complete(Unit)
            if (update.exerciseStateInfo.state.isEnded && !stopping) {
                val reason = update.exerciseStateInfo.endReason
                // Τελείωσε από αλλού (άλλη εφαρμογή, χάθηκε άδεια): κρατάμε ό,τι γράφτηκε, και το λέμε με δόνηση (V-A-16):
                // από εδώ και πέρα ούτε παλμοί μετράνε ούτε η ειδοποίηση ορίου.
                if (reason != ExerciseEndReason.USER_END) {
                    endedElsewhere(reason)
                    scope.launch { finish(endReason = reason) }
                } else {
                    scope.launch { finish() }
                }
            } else {
                // S8-06: και από εδώ, όχι μόνο από τον βρόχο του δευτερολέπτου (που σταματά με σβηστή οθόνη).
                checkForgotten(nowEl)
                saveRun()
            }
            Repo.changed()
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) {}

        /**
         * Αν μετρά (AVAILABLE) ή αν το ρολόι βγήκε από τον καρπό (OFF_BODY): για το «δεν μετριούνται» (έλεγχος γ2, W2-02).
         * Στο logcat για τη δοκιμή στη συσκευή.
         */
        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {
            if (dataType != DataType.HEART_RATE_BPM) return
            Log.i(TAG, "παλμοί: $availability")
            Repo.hrAvailable = when (availability) {
                DataTypeAvailability.AVAILABLE -> true
                DataTypeAvailability.UNAVAILABLE_DEVICE_OFF_BODY -> false
                else -> null
            }
            Repo.changed()
        }
    }

    /**
     * Η ποιότητα μιας τιμής παλμών όπως τη δηλώνει το Health Services (HeartRateAccuracy.SensorStatus). Ρολόι που δεν
     * δηλώνει τίποτα (accuracy null ή άλλου είδους): [HrQuality.OK], δηλαδή όπως πριν. Ο ίδιος κανόνας με την εφεδρεία
     * αισθητήρα ([HrSensor]: SENSOR_STATUS_NO_CONTACT / UNRELIABLE δεν γίνονται τιμή).
     */
    private fun heartQuality(p: SampleDataPoint<Double>): HrQuality {
        val status = (p.accuracy as? HeartRateAccuracy)?.sensorStatus ?: return HrQuality.OK
        return hrQualityOf(
            noContact = status == HeartRateAccuracy.SensorStatus.NO_CONTACT,
            unreliable = status == HeartRateAccuracy.SensorStatus.UNRELIABLE,
            lowAccuracy = status == HeartRateAccuracy.SensorStatus.ACCURACY_LOW,
        )
    }

    /** Τιμή από την εφεδρεία αισθητήρα: ένδειξη και ειδοποίηση (όχι στατιστικά: αυτά από το Health Services). */
    private fun onSensorBpm(bpm: Int, at: Long, atEl: Long) {
        if (stopping) return
        Repo.hrGaps.mark(System.currentTimeMillis())
        if (at >= Repo.bpmAt) {
            Repo.bpm = bpm
            Repo.bpmAt = at
        }
        if (atEl > Repo.bpmEl) {
            Repo.bpmEl = atEl
            armSilenceAlarm(atEl)
        }
        if (Repo.alarm.feed(bpm, atEl)) onAlarm(bpm, SystemClock.elapsedRealtime() - atEl)
        zoneCheck(bpm, atEl, SystemClock.elapsedRealtime())
        sendHrToPhone(System.currentTimeMillis())
        Repo.changed()
    }

    /**
     * Η άσκηση τελείωσε από άλλη εφαρμογή ή το σύστημα (έλεγχος 9/11, V-A-16): δόνηση, μήνυμα στην οθόνη και ειδοποίηση
     * (ανάβει η οθόνη). Ό,τι μετρήθηκε ως εκεί σώζεται ([finish]).
     */
    private fun endedElsewhere(reason: Int) {
        val text = when (reason) {
            ExerciseEndReason.AUTO_END_PERMISSION_LOST -> "Η άσκηση σταμάτησε: χάθηκε μια άδεια."
            ExerciseEndReason.AUTO_END_SUPERSEDED -> "Η άσκηση σταμάτησε από άλλη εφαρμογή."
            else -> "Η άσκηση σταμάτησε από το ρολόι."
        }
        // Σύντομο, να χωρά ολόκληρο στην οθόνη «Αποθηκεύτηκε»· η ειδοποίηση λέει και για το όριο.
        Repo.notice = "$text Ό,τι μετρήθηκε σώθηκε."
        vibrate(longArrayOf(0, 300, 120, 300, 120, 300))
        try {
            val pi = PendingIntent.getActivity(this, 2, Intent(this, WatchActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
            val n = NotificationCompat.Builder(this, CH_ALARM)
                .setSmallIcon(R.drawable.ic_heart)
                .setContentTitle(text)
                .setContentText("Ό,τι μετρήθηκε σώθηκε. Το όριο παλμών δεν σε προσέχει πια.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()
            getSystemService(NotificationManager::class.java).notify(OTHER_ID, n)
        } catch (_: Exception) {
        }
    }

    /**
     * Παλμοί προς το κινητό (ανά 5″), όταν η προπόνηση τρέχει εκεί. Από την ίδια την παράδοση παλμών, όχι από τον βρόχο
     * του δευτερολέπτου, που σταματά όταν κοιμάται ο επεξεργαστής (έλεγχος #2, W2-03).
     */
    private fun sendHrToPhone(now: Long) {
        if (!Repo.runningPhone || !Repo.bpmFresh(now) || now - lastHrSent < 5000) return
        lastHrSent = now
        val o = JSONObject().put("v", Proto.MAJOR).put("bpm", Repo.bpm).put("t", Repo.bpmAt).put("sid", Repo.runningSid ?: Repo.phone?.id ?: "")
        scope.launch { Link.sendJson(this@ExerciseService, Paths.HR, o) }
    }

    // ------------------------------------------------------------------ κάθε δευτερόλεπτο
    private suspend fun tick() {
        while (scope.isActive) {
            val now = System.currentTimeMillis()
            // Για τους χρόνους της ειδοποίησης: μονότονος χρόνος (αν η ώρα του ρολογιού πάει πίσω, δεν «τυφλώνεται», W3-14).
            val nowEl = SystemClock.elapsedRealtime()
            val s = Repo.session
            val walk = Repo.running == "walk"
            // Τέλος διαλείμματος: δόνηση μία φορά (και με σβηστή οθόνη). Ποτέ μέσα σε περπάτημα (S8-04, [restBuzzDue]).
            if (s != null && restBuzzDue(s.restEnd, now, restBuzzedFor, walk)) {
                restBuzzedFor = s.restEnd
                vibrate(longArrayOf(0, 180, 120, 180))
                if (Repo.screen == Repo.Screen.REST) Repo.screen = Repo.Screen.SET
                releaseRestLock()
                Repo.changed()
            }
            holdForRest()
            // Παλμοί προς το κινητό (και αν δεν ήρθε νέα τιμή, π.χ. σταθεροί παλμοί από τον αισθητήρα).
            sendHrToPhone(now)
            // Περπάτημα: ζωντανά στο κινητό (αν είναι ανοιχτή η εφαρμογή εκεί). Χωρίς αναμονή μέσα στον βρόχο.
            // Μόνο όσο το κινητό λέει ότι κοιτάζει (W3-15)· στο παλιό κινητό όπως πριν.
            if (walk && liveDue(now, lastLiveSent, Repo.phoneKnowsWatching, Repo.watchingUntil)) {
                lastLiveSent = now
                val o = JSONObject().put("v", Proto.MAJOR).put("kind", "walk").put("start", Repo.startedAt).put("sec", Repo.activeSecNow(now))
                    .put("m", finite(Repo.meters)).put("steps", Repo.steps).put("bpm", if (Repo.bpmFresh(now)) Repo.bpm else 0)
                    .put("paused", Repo.paused).put("rec", Repo.recoveryUntil > 0)
                scope.launch { Link.sendJson(this@ExerciseService, Paths.LIVE, o) }
            }
            // ✓ του ρολογιού που δεν έφτασαν στο κινητό: ξανά, ανά 10″ (το κινητό αγνοεί όσα έχει ήδη· έλεγχος #2).
            // Τελικός έλεγχος, Συμβούλιο 4 (W-4): μαζί και οι επαναλήψεις που άλλαξες στο ρολόι — μέσα στο ✓ όταν το κινητό
            // δεν έχει δει ακόμα το ✓ σου, αλλιώς ως «reps». Ώσπου το κινητό να δείξει τη δική σου τιμή.
            val pend = Repo.pendingTicks
            val pendReps = Repo.pendingReps
            val ph = Repo.phone
            if (Repo.runningPhone && ph != null && (pend.isNotEmpty() || pendReps.isNotEmpty()) && nowEl - lastPendingSent >= 10_000) {
                lastPendingSent = nowEl
                for ((i, k) in pend) {
                    val item = ph.items.getOrNull(i) ?: continue
                    val set = item.sets.getOrNull(k) ?: continue
                    val o = tickCmd(i, k, set.at, item.ex, set.reps.takeIf { set.trail != null }, late = true)
                        .put(Proto.CMD_VERSION, Proto.MAJOR).put("sid", ph.id)
                    scope.launch { Link.sendJson(this@ExerciseService, Paths.CMD, o) }
                }
                for ((i, k) in pendReps) {
                    val item = ph.items.getOrNull(i) ?: continue
                    val set = item.sets.getOrNull(k) ?: continue
                    val o = repsCmd(i, k, item.ex, set.reps, set.at)
                        .put(Proto.CMD_VERSION, Proto.MAJOR).put("sid", ph.id).put("q", Repo.nextCmdSeq())
                    scope.launch { Link.sendJson(this@ExerciseService, Paths.CMD, o) }
                }
            }
            // Εφεδρεία αισθητήρα με επαφή και ίδια τιμή: οι παλμοί είναι απλώς σταθεροί, όχι χαμένοι (ως 2′).
            // Μόνο για ένδειξη/ειδοποίηση· δεν γίνεται «τιμή» προς το κινητό (έλεγχος #2).
            val sn = sensor
            val steady = sn != null && sn.contact && sn.last > 0 && Repo.bpm == sn.last
            Repo.steadyUntil = if (steady) sn!!.lastAt + 120_000L else 0L
            Repo.steadyUntilEl = if (steady) sn!!.lastEl + 120_000L else 0L
            val fresh = Repo.hrLive(now)
            // Εφεδρεία αισθητήρα (ή ρολόι που στέλνει μόνο αλλαγές): σταθεροί παλμοί πάνω από το όριο μετρούν κι αυτοί (W2-02).
            if ((sensor != null || Repo.hrMode == "default") && fresh && Repo.alarm.steady(Repo.bpm, nowEl)) onAlarm(Repo.bpm, 0)
            // Το όριο ήρθε ή έφυγε στη μέση της άσκησης: η εφεδρεία αισθητήρα ξεκινά ή σταματά μαζί του (W2-04).
            if (exerciseStarted && hrInExercise && Repo.fastHr() && Repo.hrMode == "default" && sensor == null && has(this, heartPermission)) startSensor()
            if (sensor != null && !Repo.fastHr()) stopSensor()
            // Ζώνη: σταθεροί παλμοί χωρίς νέα τιμή μετρούν κι αυτοί (όπως το όριο, W2-02).
            if (fresh) zoneCheck(Repo.bpm, nowEl, nowEl, steady = true)
            checkSilence(nowEl, fresh)
            // S8-02: θα έκοβε τώρα το ρολόι τη δόνηση ζώνης (Σίγαση, Εξοικονόμηση ενέργειας); Η οθόνη το γράφει.
            if (walk && exerciseStarted && nowEl - lastMuteCheckEl >= MUTE_CHECK_MS) {
                lastMuteCheckEl = nowEl
                checkZoneMute()
            }
            // S8-06: άσκηση που μοιάζει ξεχασμένη (μόνο υπενθύμιση).
            checkForgotten(nowEl)
            // Ήρθε ο πρώτος παλμός ή έγινε ο έλεγχος των 30″: ο επεξεργαστής ξανά ελεύθερος να κοιμηθεί.
            if (firstHrLock != null && (fresh || Repo.bpmAt > 0 || silence.state != null || nowEl - Repo.startedEl >= FIRST_HR_LOCK_MS)) {
                releaseFirstHrLock()
            }
            // Τέλος του λεπτού αποκατάστασης: μία δόνηση (ξυπνητηριού, να μην κόβεται), όπως υπόσχεται το κινητό («ώσπου να
            // δονηθεί το ρολόι», έλεγχος 13/11, S8-01). Η «Παράλειψη» δεν περνά από εδώ ([stopRequested]): χωρίς δόνηση.
            if (recoveryEndBuzz(Repo.recoveryUntil, now, skipped = false)) {
                vibrate(longArrayOf(0, 250, 150, 250))
                scope.launch { finish() }
                return
            }
            // Η προπόνηση του κινητού έκλεισε εκεί (ή το κινητό ξεκίνησε άλλη, DP-09): τέλος και εδώ.
            val ph2 = Repo.phone
            if (Repo.runningPhone && Repo.local == null && (ph2 == null || (Repo.runningSid != null && ph2.id != Repo.runningSid))) {
                scope.launch { finish() } // όχι μέσα σε αυτόν τον βρόχο: το finish τον σταματά
                return
            }
            saveRun()
            Repo.changed()
            delay(1000)
        }
    }

    // ------------------------------------------------------------------ «χάθηκαν παλμοί» (V-A-04, S8-07)
    /**
     * Με όριο: αν χαθούν οι παλμοί (π.χ. χαλαρό λουρί), μία δόνηση να το ξέρεις, και στα βάρη (έλεγχος #2): στο περπάτημα
     * μετά από 15″, στα βάρη μετά από 45″ ([lostAfterMs]). Τρεις σύντομες, για να μη μοιάζει με το τέλος του διαλείμματος
     * (δύο μεγαλύτερες). Έλεγχος 9/11 (V-A-04): και όταν δεν ήρθε ΚΑΝΕΝΑΣ παλμός 30″ μετά την αρχή, με άλλο μοτίβο (μία
     * μακριά και δύο σύντομες). Μία φορά· ξανά μόνο αν ξαναέρθουν παλμοί και χαθούν.
     * Τρέχει από τον βρόχο του δευτερολέπτου ΚΑΙ από το ξυπνητήρι ([onSilenceAlarm], έλεγχος 13/11, S8-07).
     */
    private fun checkSilence(nowEl: Long, fresh: Boolean) {
        val lostAfter = lostAfterMs(Repo.running == "walk")
        val lastEl = if (Repo.bpmEl > 0) maxOf(Repo.bpmEl, Repo.steadyUntilEl) else 0L
        if (silence.check(nowEl, Repo.startedEl, lastEl, fresh, Repo.alarm.limit != null, Repo.paused, lostAfter)) {
            vibrate(if (silence.state == HrSilence.Silence.NEVER) longArrayOf(0, 400, 150, 70, 90, 70) else longArrayOf(0, 70, 90, 70, 90, 70))
        }
        Repo.hrSilent = silence.state
    }

    /**
     * Ξαναοπλίζει το ξυπνητήρι του ελέγχου «χάθηκαν παλμοί» για [silenceWakeAt] μετά την τιμή της στιγμής [fromEl] (S8-07).
     * Μόνο με όριο γιατρού (χωρίς όριο δεν δονείται τίποτα). Όχι σε κάθε τιμή: μόνο όταν η ώρα πάει τουλάχιστον 3″ πιο
     * πέρα (μία κλήση ανά παράδοση των 5″). Αν το σύστημα το αρνηθεί, μένει ο έλεγχος του βρόχου, όπως πριν.
     */
    private fun armSilenceAlarm(fromEl: Long) {
        if (stopping || Repo.running == null || Repo.alarm.limit == null) return
        val at = silenceWakeAt(fromEl, lostAfterMs(Repo.running == "walk"))
        if (silenceAlarmAt != 0L && at - silenceAlarmAt < 3_000L) return
        try {
            val am = getSystemService(AlarmManager::class.java) ?: return
            am.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, "ygeia:silence", silenceAlarm, silenceHandler)
            silenceAlarmAt = at
        } catch (e: Exception) {
            Log.w(TAG, "ξυπνητήρι σιωπής", e)
        }
    }

    private fun cancelSilenceAlarm() {
        silenceAlarmAt = 0L
        try {
            getSystemService(AlarmManager::class.java)?.cancel(silenceAlarm)
        } catch (_: Exception) {
        }
    }

    /**
     * Το ξυπνητήρι χτύπησε: δεν ήρθε νεότερη τιμή παλμών από τότε που οπλίστηκε. Ο ίδιος έλεγχος με τον βρόχο. Αν οι παλμοί
     * μετρούν ακόμα ως «ζωντανοί» (σταθεροί από τον αισθητήρα, ή το ρολόι λέει ότι μετρά), ξανά σε λίγο, ώσπου να κριθεί·
     * σταματά μόλις κριθεί «χάθηκαν» ή έρθει νέα τιμή (το πολύ λίγες φορές: το «ζωντανοί» κρατά ως 2′).
     */
    private fun onSilenceAlarm() {
        silenceAlarmAt = 0L
        if (stopping || Repo.running == null || Repo.alarm.limit == null) return
        val nowEl = SystemClock.elapsedRealtime()
        checkSilence(nowEl, Repo.hrLive(System.currentTimeMillis()))
        if (silence.state == null && Repo.bpmEl > 0) armSilenceAlarm(nowEl)
        Repo.changed()
    }

    // ------------------------------------------------------------------ Σίγαση / Εξοικονόμηση ενέργειας (S8-02)
    /**
     * Η δόνηση ζώνης είναι δόνηση ειδοποίησης (απόφαση του χρήστη: απαλή, όχι ξυπνητήρι)· το Android την κόβει σε Σίγαση
     * και σε Εξοικονόμηση ενέργειας, χωρίς να το λέει (έλεγχος 13/11, S8-02). Εδώ μόνο ανίχνευση: η οθόνη του περπατήματος
     * γράφει «χωρίς δόνηση» δίπλα στους παλμούς, και μία φορά ένα σύντομο μήνυμα με την αιτία (όχι πάνω σε μήνυμα «πάτα
     * ξανά»). Τρεις φθηνές ερωτήσεις στο σύστημα ανά [MUTE_CHECK_MS] (και «Μην ενοχλείτε», R7-A7-1), μόνο σε περπάτημα· ό,τι
     * σφάλμα = «δεν ξέρω» = όχι.
     */
    private fun checkZoneMute() {
        val powerSave = try {
            getSystemService(PowerManager::class.java)?.isPowerSaveMode == true
        } catch (_: Exception) {
            false
        }
        val silent = try {
            getSystemService(AudioManager::class.java)?.ringerMode == AudioManager.RINGER_MODE_SILENT
        } catch (_: Exception) {
            false
        }
        // Έλεγχος 13/11, round 7 (R7-A7-1): «Μην ενοχλείτε» (και Λειτουργία ύπνου, που το ανοίγει) κόβει κι αυτό τη δόνηση
        // ειδοποίησης (AOSP ZenModeHelper: OP_VIBRATE = IGNORED σε κάθε τρόπο του). Δημόσια ερώτηση, χωρίς άδεια.
        val dnd = try {
            when (getSystemService(NotificationManager::class.java)?.currentInterruptionFilter) {
                NotificationManager.INTERRUPTION_FILTER_PRIORITY, NotificationManager.INTERRUPTION_FILTER_ALARMS,
                NotificationManager.INTERRUPTION_FILTER_NONE -> true
                else -> false
            }
        } catch (_: Exception) {
            false
        }
        val muted = zoneMutedNow(Repo.zoneAlarm.active, Repo.alarm.limit != null, powerSave, silent, dnd)
        Repo.zoneMuted = muted
        val told = if (muted) zoneMutedNotice(powerSave, silent, dnd) else null
        if (told == null) {
            // Η δόνηση φτάνει ξανά: το μήνυμα, αν φαίνεται ακόμα, φεύγει.
            val was = zoneMuteTold
            if (was != null && Repo.notice == was) Repo.notice = null
            zoneMuteTold = null
        } else if (told != zoneMuteTold && !isBriefNotice(Repo.notice)) {
            zoneMuteTold = told
            softNotice = told
            Repo.notice = told
        }
    }

    // ------------------------------------------------------------------ ξεχασμένη άσκηση (S8-06)
    /** Αλλάζει σε κάθε ✓ (εδώ ή στο κινητό) και σε κάθε αλλαγή άσκησης: «κάτι έγινε» στην προπόνηση. */
    private fun activitySignature(): Int = Repo.session?.let { it.setsDone * 100 + it.idx } ?: 0

    /** Τα λεπτά του περπατήματος του προγράμματος τη μέρα που ξεκίνησε (0 = δεν υπάρχει· R7-A8-6, όχι «σήμερα»). */
    private fun plannedWalkMinutes(): Int {
        val p = Repo.plan ?: return 0
        val c = p.walkOn(Repo.startedAt)?.cardio ?: return 0
        return p.cardioMinutes(c, p.dayOf(Repo.startedAt))
    }

    /**
     * Υπενθύμιση όταν η άσκηση μοιάζει ξεχασμένη ([Forgotten]): δόνηση (ξυπνητηριού), ειδοποίηση και το ίδιο μήνυμα στην
     * οθόνη. Ξανά ανά 30′ όσο ισχύει. ΠΟΤΕ αυτόματο τέλος: αποφασίζει ο χρήστης. Όχι στο λεπτό αποκατάστασης.
     */
    private fun checkForgotten(nowEl: Long) {
        val kind = Repo.running ?: return
        if (stopping || Repo.recoveryUntil > 0) return
        val sig = activitySignature()
        if (sig != actSig) {
            actSig = sig
            lastActionEl = nowEl
        }
        val why = Forgotten.why(kind, originEl, lastActionEl, pausedSinceEl, if (kind == "walk") plannedWalkMinutes() else 0, nowEl)
        if (why == null) {
            forgotBuzzEl = 0L
            return
        }
        if (!Forgotten.remindNow(why, forgotBuzzEl, nowEl)) return
        forgotBuzzEl = nowEl
        val title = Forgotten.title(why)
        val text = Forgotten.text(why)
        // Τέσσερις μέτριες: δεν μοιάζει ούτε με το όριο (τρεις μακριές) ούτε με το τέλος διαλείμματος (δύο).
        vibrate(longArrayOf(0, 150, 100, 150, 100, 150, 100, 150))
        // Στο περπάτημα σε μία γραμμή (χωρά)· στα βάρη ολόκληρο, σε όλη την οθόνη (η οθόνη το ανοίγει μόνη της), με το
        // κείμενο της οθόνης (R7-U3-07: χωρίς «στο ρολόι», πρώτα «κλείσε αυτό»).
        if (!isBriefNotice(Repo.notice)) {
            val shown = if (kind == "walk") title else Forgotten.screenText(why)
            softNotice = shown
            Repo.notice = shown
        }
        try {
            val pi = PendingIntent.getActivity(this, 3, Intent(this, WatchActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
            val n = NotificationCompat.Builder(this, CH_ALARM)
                .setSmallIcon(R.drawable.ic_heart)
                .setContentTitle(title)
                .setContentText(text)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setTimeoutAfter(10 * 60_000L)
                .build()
            getSystemService(NotificationManager::class.java).notify(FORGOT_ID, n)
        } catch (_: Exception) {
        }
    }

    // ------------------------------------------------------------------ ζώνη περπατήματος (12/11)
    /**
     * Δόνηση ζώνης: καθοδήγηση, όχι ασφάλεια. Απαλή (όχι «ξυπνητήρι»), ποτέ όταν μιλά το όριο του γιατρού, σε παύση ή στο
     * λεπτό αποκατάστασης, και ποτέ για τιμή που ήρθε με καθυστέρηση (πακέτο παλμών): τότε ήδη άλλαξαν.
     * Πάνω: δύο σύντομες. Κάτω: μία μακρύτερη.
     */
    private fun zoneCheck(bpm: Int, atEl: Long, nowEl: Long, steady: Boolean = false) {
        val za = Repo.zoneAlarm
        if (za.zone == null) return
        // Οι αποφάσεις είναι καθαρές συναρτήσεις του Protocol.kt, με δοκιμές (έλεγχος 13/11, S12-11)· ίδια συμπεριφορά.
        val walk = Repo.running == "walk"
        val recovery = Repo.recoveryUntil > 0
        if (zoneOnHold(walk, Repo.paused, recovery, stopping)) {
            za.hold()
            return
        }
        // Με όριο γιατρού μιλά μόνο εκείνο (και η οθόνη δεν δείχνει ζώνη· ανασκόπηση 11/11, S7).
        // Ηλικία της τιμής ΠΡΙΝ αλλάξει η κατάσταση (S5, N2): στο «σταθεροί παλμοί» μετρά η τελευταία πραγματική τιμή,
        // εκτός αν ο αισθητήρας έχει επαφή και ίδια τιμή (τότε είναι τωρινή). Παλιά τιμή: ούτε δόνηση ούτε κρίση.
        val age = zoneValueAgeMs(steady, Repo.steadyUntilEl, Repo.bpmEl, atEl, nowEl)
        if (!zoneMaySpeak(walk, Repo.paused, recovery, stopping, Repo.alarm.limit != null, age)) return
        val b = if (steady) za.steady(bpm, atEl) else za.feed(bpm, atEl)
        if (b == ZoneAlarm.Buzz.NONE) return
        // Χωρίς την τιμή των παλμών (S10-5).
        Log.i(TAG, "ζώνη: $b")
        // Δόνηση ειδοποίησης (απόφαση του χρήστη): σε Σίγαση / Εξοικονόμηση ενέργειας το ρολόι την κόβει· τότε η οθόνη
        // γράφει «χωρίς δόνηση» ([checkZoneMute], S8-02). Η κλήση γίνεται έτσι κι αλλιώς.
        vibrate(if (b == ZoneAlarm.Buzz.UP) longArrayOf(0, 110, 120, 110) else longArrayOf(0, 260), alarm = false)
    }

    // ------------------------------------------------------------------ όριο παλμών
    /**
     * Δόνηση ορίου. [ageMs]: πόσο παλιά είναι η τιμή (πακέτο με καθυστέρηση, W2-17): η ειδοποίηση το λέει. Η σίγαση
     * «πάτα για να κλείσει» κρατά 60″ για το ίδιο επεισόδιο, με δόνηση ανά 30″ (W2-16· πριν έσβηνε στη 2η δόνηση).
     */
    private fun onAlarm(bpm: Int, ageMs: Long) {
        vibrate(longArrayOf(0, 500, 200, 500, 200, 500))
        // Αν η οθόνη δεν είναι ανοιχτή: ειδοποίηση υψηλής προτεραιότητας (ανάβει και δονείται).
        val nm = getSystemService(NotificationManager::class.java)
        val pi = PendingIntent.getActivity(this, 1, Intent(this, WatchActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(this, CH_ALARM)
            .setSmallIcon(R.drawable.ic_heart)
            .setContentTitle("Πάνω από το όριο: $bpm${ageText(ageMs)}")
            .setContentText(alarmAdvice(Repo.running == "walk", Repo.recoveryUntil > 0) + " Όριο γιατρού ${Repo.alarm.limit}.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setTimeoutAfter(60_000)
            .build()
        try {
            nm.notify(ALARM_ID, n)
        } catch (_: SecurityException) {
        }
    }

    // ------------------------------------------------------------------ ξύπνιος ως το τέλος του διαλείμματος (W2-03)
    /**
     * Με σβηστή οθόνη ο επεξεργαστής κοιμάται και ο βρόχος του δευτερολέπτου σταματά: η δόνηση «τέλος διαλείμματος» θα
     * ερχόταν λεπτά αργότερα. Όσο κρατά ένα διάλειμμα, ξύπνιος ως το τέλος του + 3″ (το πολύ 5′)· αφήνεται στη δόνηση.
     */
    private fun holdForRest() {
        val s = Repo.session
        val now = System.currentTimeMillis()
        // Όχι σε περπάτημα (S8-04): το διάλειμμα μιας ανοιχτής προπόνησης του κινητού δεν το αφορά.
        val end = if (Repo.running != null && Repo.running != "walk" && s != null && s.restEnd > now) s.restEnd else 0L
        // Ίδιο διάλειμμα και ο επεξεργαστής ακόμα ξύπνιος: τίποτα. Αν έληξε (διάλειμμα > 5′ με «+30″»), ξανά (NIT 2).
        if (end == restLockFor && (end == 0L || restLock?.isHeld == true)) return
        releaseRestLock()
        if (end == 0L) return
        restLockFor = end
        try {
            val pm = getSystemService(PowerManager::class.java) ?: return
            restLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ygeia:rest").apply {
                setReferenceCounted(false)
                acquire((end - now + 3_000).coerceIn(1_000, REST_LOCK_MAX_MS))
            }
        } catch (e: Exception) {
            Log.w(TAG, "wakelock rest", e)
        }
    }

    private fun releaseRestLock() {
        restLockFor = 0
        val l = restLock ?: return
        restLock = null
        try {
            if (l.isHeld) l.release()
        } catch (_: Exception) {
        }
    }

    /**
     * Ξύπνιος στο λεπτό αποκατάστασης (έλεγχος 13/11, S8-01): το κινητό λέει «μένεις έτσι ώσπου να δονηθεί το ρολόι», άρα ο
     * χρήστης ΔΕΝ κοιτά την οθόνη· αν σβήσει, ο βρόχος του δευτερολέπτου σταματά και η δόνηση (και το αποτέλεσμα) θα
     * αργούσαν. Το πολύ [RECOVERY_LOCK_MS] (70″), μία φορά ανά περπάτημα· αφήνεται στο τέλος ([finish]) και στο [onDestroy].
     */
    private fun holdForRecovery() {
        releaseRecoveryLock()
        try {
            val pm = getSystemService(PowerManager::class.java) ?: return
            recoveryLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ygeia:recovery").apply {
                setReferenceCounted(false)
                acquire(RECOVERY_LOCK_MS)
            }
        } catch (e: Exception) {
            Log.w(TAG, "wakelock recovery", e)
        }
    }

    private fun releaseRecoveryLock() {
        val l = recoveryLock ?: return
        recoveryLock = null
        try {
            if (l.isHeld) l.release()
        } catch (_: Exception) {
        }
    }

    /**
     * Δόνηση ως «ξυπνητήρι» (USAGE_ALARM): αλλιώς η Εξοικονόμηση μπαταρίας και η Σίγαση την κόβουν, και οι σύντομες
     * μπορεί να θεωρηθούν δόνηση αφής (έλεγχος #2, W2-01). Μόνο όσο τρέχει άσκηση.
     */
    /** [alarm]: δόνηση «ξυπνητήρι» (όριο γιατρού, χαμένοι παλμοί)· αλλιώς ειδοποίησης (ζώνη, 12/11), πιο διακριτική. */
    private fun vibrate(pattern: LongArray, alarm: Boolean = true) {
        val v: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
        val effect = VibrationEffect.createWaveform(pattern, -1)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                v?.vibrate(effect, VibrationAttributes.createForUsage(if (alarm) VibrationAttributes.USAGE_ALARM else VibrationAttributes.USAGE_NOTIFICATION))
            } else {
                @Suppress("DEPRECATION")
                v?.vibrate(effect, AudioAttributes.Builder().setUsage(if (alarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION).build())
            }
        } catch (_: Exception) {
        }
    }

    // ------------------------------------------------------------------ παύση, αποκατάσταση
    private suspend fun setPaused(on: Boolean) {
        if (Repo.running != "walk" || Repo.recoveryUntil > 0 || Repo.paused == on || !exerciseStarted) return
        try {
            if (on) client.pauseExerciseAsync().await() else client.resumeExerciseAsync().await()
        } catch (e: Exception) {
            Log.w(TAG, "pause $on", e)
            Repo.notice = if (on) "Δεν έγινε παύση." else "Δεν συνεχίστηκε."
            Repo.changed()
            return
        }
        val now = System.currentTimeMillis()
        // Ο χρόνος σταματά/συνεχίζει αμέσως στην οθόνη (το Health Services στέλνει το ακριβές σημείο ελέγχου μετά).
        if (Repo.cpWall > 0) {
            Repo.cpActiveMs = Repo.activeSecNow(now) * 1000
            Repo.cpWall = now
            Repo.cpRunning = !on
        }
        Repo.paused = on
        // S8-06: από πότε κρατά η παύση (για την υπενθύμιση μετά από 10 λεπτά)· η συνέχεια μετρά ως «κίνηση».
        pausedSinceEl = if (on) SystemClock.elapsedRealtime() else -1L
        forgotBuzzEl = 0L
        // Ποιες τιμές μπαίνουν στον μέσο κρίνεται με τον χρόνο κάθε τιμής (W3-11).
        Repo.hr?.let { if (on) it.pause(now) else it.resume(now) }
        if (on) Repo.pauses.add(longArrayOf(now, 0L)) else Repo.pauses.lastOrNull()?.let { if (it[1] == 0L) it[1] = now }
        Repo.notice = null
        updateOngoing()
        saveRun(force = true)
        Repo.changed()
    }

    /**
     * «Τέλος»: στο περπάτημα, με παλμούς και χωρίς παύση, πρώτα το λεπτό αποκατάστασης (πτώση παλμών στο 1′, 9/11)·
     * δεύτερο «Τέλος» (Παράλειψη) ή κάθε άλλη περίπτωση: τέλος αμέσως.
     */
    private suspend fun stopRequested() {
        val now = System.currentTimeMillis()
        val hr = Repo.hr
        if (Repo.running == "walk" && Repo.recoveryUntil == 0L && !Repo.paused && exerciseStarted && hr != null && Repo.bpmFresh(now)) {
            Repo.endAt = now
            hr.markEnd(now)
            // Χρόνος «παγωμένος» στο «Τέλος».
            Repo.activeSec = Repo.activeSecNow(now)
            if (Repo.cpWall > 0) {
                Repo.cpActiveMs = Repo.activeSec * 1000
                Repo.cpWall = now
                Repo.cpRunning = false
            }
            Repo.recoveryUntil = now + HrStats.RECOVERY_MS
            Repo.screen = Repo.Screen.RECOVER
            holdForRecovery()
            vibrate(longArrayOf(0, 120))
            saveRun(force = true)
            Repo.changed()
            return
        }
        finish(userEnd = true)
    }

    // ------------------------------------------------------------------ τέλος
    /**
     * Μία κλήση προς το Health Services στο «Τέλος», με όριο χρόνου ([FinishTimes.HS_CALL_MS]· τελικός έλεγχος, Συμβούλιο 4,
     * W-1). false ΜΟΝΟ αν δεν απάντησε εγκαίρως· μια απάντηση με σφάλμα είναι απάντηση (όπως πριν: συνεχίζουμε). Το ότι
     * δεν απάντησε γράφεται στο logcat και πάει στο κινητό με το αποτέλεσμα («err»), αν δεν υπάρχει ήδη άλλο σφάλμα.
     */
    private suspend fun hsCall(what: String, block: suspend () -> Unit): Boolean = try {
        val ok = withTimeoutOrNull(FinishTimes.HS_CALL_MS) {
            block()
            true
        } == true
        if (!ok) {
            Log.w(TAG, "Health Services ($what): καμία απάντηση σε ${FinishTimes.HS_CALL_MS / 1000}″")
            if (Repo.lastErr == null) Repo.lastErr = "TimeoutException: Health Services ($what)"
        }
        ok
    } catch (_: Exception) {
        true
    }

    /**
     * Τέλος της άσκησης και αποτέλεσμα στο κινητό. [userEnd]: πάτησε «Τέλος» εδώ (σε προπόνηση του κινητού: τέλος και εκεί,
     * V-A-09). [endReason]: τελείωσε από αλλού (V-A-16). Το αποτέλεσμα μπαίνει πρώτα στην αναμονή (σβήνεται μόνο όταν μπει
     * στο Data Layer) και μετά σβήνεται το στιγμιότυπο της άσκησης: σε κάθε στιγμή υπάρχει ένα από τα δύο.
     */
    private suspend fun finish(userEnd: Boolean = false, endReason: Int? = null) {
        if (stopping) return
        stopping = true
        releaseFirstHrLock()
        releaseRestLock()
        releaseRecoveryLock()
        cancelSilenceAlarm()
        Repo.unlisten(onRepo)
        // Ξύπνιος ώσπου να γραφτεί και να σταλεί το αποτέλεσμα (το πολύ [FinishTimes.LOCK_MS]), όχι μισό στον ύπνο.
        val finishLock = try {
            getSystemService(PowerManager::class.java)?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ygeia:finish")?.apply {
                setReferenceCounted(false)
                acquire(FinishTimes.LOCK_MS)
            }
        } catch (_: Exception) {
            null
        }
        val now = System.currentTimeMillis()
        ticker?.cancel()
        // Τελικός έλεγχος, Συμβούλιο 4 (W-1): μια έναρξη που δεν έχει απαντήσει ακόμα (το «Τέλος» ήρθε στα πρώτα
        // δευτερόλεπτα) την περιμένουμε λίγο, ώστε ό,τι ξεκίνησε να τελειώσει κανονικά εδώ. Αν δεν απαντήσει, ακυρώνεται·
        // το «τέλος» παρακάτω κλείνει την άσκηση ακόμα κι αν το Health Services την ξεκινήσει αργότερα (οι κλήσεις
        // εκτελούνται με τη σειρά). Πριν, μια τέτοια άσκηση έμενε ανοιχτή χωρίς κανέναν να την τελειώσει.
        val starting = startJob?.takeIf { it.isActive }
        if (starting != null) {
            try {
                withTimeoutOrNull(FinishTimes.HS_CALL_MS) { starting.join() }
            } catch (_: Exception) {
            }
            if (starting.isActive) starting.cancel()
        }
        val lateStart = starting != null && starting.isCancelled && !exerciseStarted
        sensor?.stop()
        sensor = null
        if (exerciseStarted) {
            // Ό,τι έχει μετρηθεί και δεν έχει παραδοθεί ακόμα (πακέτα ανά 5″) έρχεται τώρα, πριν από τον λογαριασμό.
            hsCall("flush") { client.flushAsync().await() }
            try {
                delay(FinishTimes.FLUSH_SETTLE_MS)
            } catch (_: Exception) {
            }
            // Οι τελευταίες τιμές (ως 150″ σε πακέτα) και ο τελικός χρόνος/απόσταση έρχονται με την ενημέρωση «ENDED»,
            // που μπορεί να φτάσει μετά την απάντηση του «τέλος» (W2-09): την περιμένουμε ως 5″ πριν κλείσει ο ακροατής.
            // Όχι όμως αν το ίδιο το «τέλος» δεν απάντησε: τότε δεν θα έρθει.
            val wait = if (endReason == null) CompletableDeferred<Unit>().also { ended = it } else null
            val answered = hsCall("end") { client.endExerciseAsync().await() }
            if (wait != null && answered) {
                val got = try {
                    withTimeoutOrNull(FinishTimes.ENDED_WAIT_MS) { wait.await() } != null
                } catch (_: Exception) {
                    false
                }
                if (!got) Log.w(TAG, "χωρίς ENDED σε ${FinishTimes.ENDED_WAIT_MS / 1000}″")
            }
            ended = null
            hsCall("clear") { client.clearUpdateCallbackAsync(callback).await() }
        } else if (lateStart) {
            hsCall("end") { client.endExerciseAsync().await() }
            hsCall("clear") { client.clearUpdateCallbackAsync(callback).await() }
        }
        // Το κενό ως το τέλος, χωρίς όριο (W2-08): ένα λουρί χαλαρό στο τέλος φαίνεται ολόκληρο.
        Repo.hrGaps.close(now)
        val kind = Repo.running
        val wasPhone = Repo.runningPhone
        var failed = false
        val result = try {
            Results.build(now, userEnd = userEnd, endReason = endReason)
        } catch (e: Exception) {
            // Ποτέ χαμένο αποτέλεσμα από ένα σφάλμα εδώ: το στιγμιότυπο μένει και στέλνεται ως μερικό στο επόμενο άνοιγμα.
            Log.e(TAG, "result", e)
            failed = true
            null
        }
        // Τελικός έλεγχος, Συμβούλιο 4 (W-2): ΠΡΩΤΑ το αποτέλεσμα στην αναμονή (στον δίσκο του ρολογιού) και μετά
        // οτιδήποτε περιμένει το κινητό. Πριν, το μήνυμα «end» έφευγε πρώτο· όσο περίμενε απάντηση, το αποτέλεσμα υπήρχε
        // μόνο στη μνήμη.
        // Έλεγχος 13/11 (S8-08): το στιγμιότυπο σβήνεται ΜΟΝΟ αν το αποτέλεσμα γράφτηκε πράγματι στην αναμονή. Με γεμάτο
        // χώρο η εγγραφή αποτυγχάνει· πριν το στιγμιότυπο σβηνόταν έτσι κι αλλιώς και το αποτέλεσμα έμενε μόνο στη μνήμη.
        var saved = true
        if (result != null) {
            saved = Repo.storeResultThenClear({ Repo.savePending(this, result.first, result.second) }, { Repo.clearRun(this) })
            if (!saved) {
                Log.w(TAG, "αναμονή: το αποτέλεσμα δεν γράφτηκε στον δίσκο· το στιγμιότυπο μένει")
                // Και στη σύνοψη του κινητού, αν το αποτέλεσμα φτάσει τώρα από το Data Layer («err», υπάρχον πεδίο).
                if (!result.second.has("err")) result.second.put("err", "pending: δεν γράφτηκε")
            }
        } else if (!failed) {
            // Τίποτα να σταλεί (π.χ. προπόνηση χωρίς σετ): το στιγμιότυπο δεν χρειάζεται πια.
            Repo.clearRun(this)
        }
        // «Τέλος» στο ρολόι σε προπόνηση του κινητού: τέλος και εκεί (V-A-09). Μήνυμα τώρα (αν το κινητό ακούει)· και το
        // «fin» μέσα στο αποτέλεσμα, που μένει ώσπου να το πάρει το κινητό. Και τα δύο με όριο χρόνου (W-1): ό,τι δεν
        // προλάβει μένει στην αναμονή και φεύγει στο επόμενο άνοιγμα της εφαρμογής.
        val sid = result?.second?.optString("sid", "").orEmpty()
        if (userEnd && wasPhone && sid.isNotEmpty()) {
            val end = JSONObject().put(Proto.CMD_VERSION, Proto.MAJOR).put("op", "end").put("sid", sid).put("at", now)
            try {
                withTimeoutOrNull(FinishTimes.SEND_MS) { Link.sendJson(this@ExerciseService, Paths.CMD, end) }
            } catch (_: Exception) {
            }
        }
        var unsaved = false
        if (result != null) {
            val put = try {
                withTimeoutOrNull(FinishTimes.PUT_MS) { Link.putResult(this@ExerciseService, result.first, result.second) } == true
            } catch (_: Exception) {
                false
            }
            if (put) {
                Repo.removePending(this, result.first)
                // S8-08: το αποτέλεσμα είναι πια στο Data Layer· το στιγμιότυπο που κρατήθηκε δεν χρειάζεται άλλο.
                if (!saved) Repo.clearRun(this)
            }
            // Έλεγχος 13/11, round 7 (R7-A8-5): ούτε στην αναμονή ούτε στο Data Layer (γεμάτος χώρος). Το αποτέλεσμα μένει στη
            // μνήμη ([Repo.unsaved]) και ξαναδοκιμάζεται σε κάθε άνοιγμα της εφαρμογής· η οθόνη ΔΕΝ λέει «Αποθηκεύτηκε».
            if (!endScreenSaved(saved, put)) {
                unsaved = true
                Repo.unsaved[result.first] = result.second
                Log.w(TAG, "αποτέλεσμα: ούτε στην αναμονή ούτε στο Data Layer· μένει στη μνήμη")
            }
        }
        Repo.endUnsaved = unsaved
        Repo.local = null
        Repo.resetExercise()
        // Ένα «ελαφρύ» μήνυμα της άσκησης που τελείωσε (χωρίς δόνηση ζώνης, «τρέχει ακόμα;») δεν μένει στο «Αποθηκεύτηκε».
        val soft = softNotice
        if (soft != null && Repo.notice == soft) Repo.notice = null
        // Προπόνηση του κινητού: γράφεται εκεί, εδώ πίσω στην αρχή. Δική του: «Αποθηκεύτηκε». Αν δεν γράφτηκε πουθενά: η
        // οθόνη του τέλους με «Δεν αποθηκεύτηκε ακόμα» (και για την προπόνηση του κινητού: οι παλμοί της).
        Repo.screen = when {
            unsaved -> Repo.Screen.END
            result != null && kind != null && !wasPhone -> Repo.Screen.END
            else -> Repo.Screen.HOME
        }
        Repo.changed()
        getSystemService(NotificationManager::class.java).cancel(ALARM_ID)
        getSystemService(NotificationManager::class.java).cancel(FORGOT_ID)
        ongoingActivity = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        try {
            finishLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        stopSelf()
    }

    // ------------------------------------------------------------------ ειδοποιήσεις
    private fun channels() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_WORKOUT, "Άσκηση σε εξέλιξη", NotificationManager.IMPORTANCE_LOW))
        nm.deleteNotificationChannel(CH_ALARM_OLD)
        nm.createNotificationChannel(
            NotificationChannel(CH_ALARM, "Όριο παλμών", NotificationManager.IMPORTANCE_HIGH).apply {
                // Η δόνηση είναι της εφαρμογής (ως ξυπνητήρι)· το κανάλι μόνο ανάβει την οθόνη με το μήνυμα.
                enableVibration(false)
                setSound(null, null)
            },
        )
    }

    /**
     * Ένδειξη στην πρόσοψη με χρονόμετρο. Το χρονόμετρο θέλει χρόνο από την εκκίνηση της συσκευής, όχι ώρα τοίχου
     * (έλεγχος 9/11, W3-04)· στο περπάτημα δείχνει τον ενεργό χρόνο και σταματά στην παύση.
     */
    private fun ongoing(title: String): Notification {
        ongoingTitle = title
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, WatchActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val b = NotificationCompat.Builder(this, CH_WORKOUT)
            .setSmallIcon(R.drawable.ic_heart)
            .setContentTitle(title)
            .setContentText("Υγεία & Φόρμα")
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pi)
        ongoingActivity = OngoingActivity.Builder(applicationContext, NOTIF_ID, b)
            .setStaticIcon(R.drawable.ic_heart)
            .setTouchIntent(pi)
            .setStatus(status())
            .build()
            .apply { apply(applicationContext) }
        return b.build()
    }

    private fun status(): Status {
        val now = System.currentTimeMillis()
        val nowEl = SystemClock.elapsedRealtime()
        val walk = Repo.running == "walk"
        val ms = if (walk) Repo.activeSecNow(now) * 1000 else now - Repo.startedAt
        val zero = stopwatchZero(nowEl, ms)
        val part = if (walk && Repo.paused) Status.StopwatchPart(zero, nowEl) else Status.StopwatchPart(zero)
        return Status.Builder()
            .addTemplate("#name# · #time#")
            .addPart("name", Status.TextPart(ongoingTitle))
            .addPart("time", part)
            .build()
    }

    /** Η ένδειξη στην πρόσοψη μετά από παύση/συνέχεια. */
    @SuppressLint("MissingPermission")
    private fun updateOngoing() {
        try {
            ongoingActivity?.update(applicationContext, status())
        } catch (_: Exception) {
        }
    }
}
