package gr.ygeiaforma.wear

import android.Manifest
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
import android.os.Build
import android.os.IBinder
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
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseEndReason
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseState
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import kotlinx.coroutines.CoroutineScope
import android.annotation.SuppressLint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
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
        private const val CH_WORKOUT = "workout"
        // Νέο κανάλι (έλεγχος #2): χωρίς δική του δόνηση, για να μη «κόβει» τη δόνηση ξυπνητηριού της εφαρμογής.
        // Οι ρυθμίσεις ενός καναλιού δεν αλλάζουν μετά τη δημιουργία του, γι' αυτό νέο όνομα· το παλιό σβήνεται.
        private const val CH_ALARM = "hr_alarm2"
        private const val CH_ALARM_OLD = "hr_alarm"
        /** Το πολύ τόσο ξύπνιος ο επεξεργαστής στην αρχή, για τον έλεγχο «κανένας παλμός» (30″) και τη δόνησή του. */
        private const val FIRST_HR_LOCK_MS = HrSilence.FIRST_MS + 10_000L

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

        fun has(ctx: Context, p: String) = ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED

        /** Η άδεια παλμών: «health.READ_HEART_RATE» από το Wear OS 6 (API 36), «BODY_SENSORS» πριν. */
        val heartPermission: String
            get() = if (Build.VERSION.SDK_INT >= 36) "android.permission.health.READ_HEART_RATE" else Manifest.permission.BODY_SENSORS
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val client by lazy { HealthServices.getClient(this).exerciseClient }
    private var ticker: Job? = null
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
    /** Πότε γράφτηκε το τελευταίο στιγμιότυπο (elapsedRealtime). */
    private var lastRunSave = 0L
    /** Η ένδειξη στην πρόσοψη (για να αλλάζει στην παύση). */
    private var ongoingActivity: OngoingActivity? = null
    private var ongoingTitle = ""

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
        releaseFirstHrLock()
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

        val walk = kind == "walk"
        // GPS μόνο με άδεια ΚΑΙ με την τοποθεσία του ρολογιού ανοιχτή (αλλιώς το Health Services αρνείται την άσκηση).
        val location = walk && has(this, Manifest.permission.ACCESS_FINE_LOCATION) && locationOn()
        Repo.gps = location
        var type = 0
        if (Build.VERSION.SDK_INT >= 34) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        if (location) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        val n = ongoing(if (walk) "Περπάτημα" else (Repo.session?.name ?: "Προπόνηση"))
        try {
            ServiceCompat.startForeground(this, NOTIF_ID, n, type)
        } catch (e: Exception) {
            Log.e(TAG, "startForeground", e)
            Repo.notice = "Δεν ξεκίνησε η μέτρηση: λείπει άδεια."
            Repo.resetExercise()
            Repo.changed()
            stopSelf()
            return
        }
        Repo.changed()
        holdUntilFirstHr()
        saveRun(force = true)
        scope.launch { startExercise(walk, location) }
        ticker = scope.launch { tick() }
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
        val walk = Repo.running == "walk"
        val location = walk && Repo.gps && has(this, Manifest.permission.ACCESS_FINE_LOCATION) && locationOn()
        var type = 0
        if (Build.VERSION.SDK_INT >= 34) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        if (location) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        try {
            ServiceCompat.startForeground(this, NOTIF_ID, ongoing(if (walk) "Περπάτημα" else (Repo.session?.name ?: "Προπόνηση")), type)
        } catch (e: Exception) {
            Log.e(TAG, "startForeground (recover)", e)
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
            scope.launch { startExercise(false, false) }
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
            if (Repo.hrMode == "sensor" && Repo.alarm.limit != null && has(this, heartPermission)) {
                val s = HrSensor(this) { bpm, at, atEl -> scope.launch { onSensorBpm(bpm, at, atEl) } }
                if (s.start()) sensor = s
            }
        } catch (e: Exception) {
            Log.e(TAG, "attach", e)
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
            if (location && DataType.LOCATION !in used) {
                Repo.gps = false
                Repo.notice = "Χωρίς GPS: η απόσταση από τα βήματα."
                Repo.changed()
            }
            if (DataType.HEART_RATE_BPM !in used) {
                Repo.notice = "Το ρολόι δεν δίνει παλμούς σε αυτή την άσκηση."
                Repo.changed()
            }
            exerciseStarted = true
            Repo.hrMode = if (batching.isNotEmpty()) "5s" else "default"
            // Χωρίς παράδοση ανά 5″: με σβηστή οθόνη οι παλμοί μπορεί να έρθουν σε πακέτα με καθυστέρηση λεπτών.
            // Για την ειδοποίηση ορίου, τότε και μόνο, ο αισθητήρας απευθείας (μόνο όσο τρέχει η άσκηση).
            if (batching.isEmpty() && DataType.HEART_RATE_BPM in types && Repo.alarm.limit != null) {
                val s = HrSensor(this) { bpm, at, atEl -> scope.launch { onSensorBpm(bpm, at, atEl) } }
                if (s.start()) {
                    sensor = s
                    Repo.hrMode = "sensor"
                }
            }
        } catch (e: Exception) {
            // Η αιτία στην οθόνη και στο logcat (ετικέτα «YgeiaWatch»): χωρίς αυτήν δεν διορθώνεται (9/11).
            Log.e(TAG, "startExercise", e)
            Repo.notice = "Δεν ξεκίνησε η μέτρηση: ${why(e)}"
            Repo.changed()
        }
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
            val points = m.getData(DataType.HEART_RATE_BPM)
            if (points.isNotEmpty() && sensor == null) Repo.hrGaps.mark(now)
            for (p in points) {
                val bpm = Math.round(p.value).toInt()
                if (bpm !in 26..249) continue
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
                if (Repo.alarm.feed(bpm, atEl)) buzz = bpm
            }
            if (buzz > 0) onAlarm(buzz)
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
                saveRun()
            }
            Repo.changed()
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) {}

        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {}
    }

    /** Τιμή από την εφεδρεία αισθητήρα: ένδειξη και ειδοποίηση (όχι στατιστικά: αυτά από το Health Services). */
    private fun onSensorBpm(bpm: Int, at: Long, atEl: Long) {
        if (stopping) return
        Repo.hrGaps.mark(System.currentTimeMillis())
        if (at >= Repo.bpmAt) {
            Repo.bpm = bpm
            Repo.bpmAt = at
        }
        if (atEl > Repo.bpmEl) Repo.bpmEl = atEl
        if (Repo.alarm.feed(bpm, atEl)) onAlarm(bpm)
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
            // Τέλος διαλείμματος: δόνηση μία φορά (και με σβηστή οθόνη).
            if (s != null && s.restEnd > 0 && now >= s.restEnd && restBuzzedFor != s.restEnd) {
                restBuzzedFor = s.restEnd
                vibrate(longArrayOf(0, 180, 120, 180))
                if (Repo.screen == Repo.Screen.REST) Repo.screen = Repo.Screen.SET
                Repo.changed()
            }
            // Παλμοί προς το κινητό (και αν δεν ήρθε νέα τιμή, π.χ. σταθεροί παλμοί από τον αισθητήρα).
            sendHrToPhone(now)
            // Περπάτημα: ζωντανά στο κινητό (αν είναι ανοιχτή η εφαρμογή εκεί). Χωρίς αναμονή μέσα στον βρόχο.
            if (Repo.running == "walk" && now - lastLiveSent >= 10_000) {
                lastLiveSent = now
                val o = JSONObject().put("v", Proto.MAJOR).put("kind", "walk").put("start", Repo.startedAt).put("sec", Repo.activeSecNow(now))
                    .put("m", finite(Repo.meters)).put("steps", Repo.steps).put("bpm", if (Repo.bpmFresh(now)) Repo.bpm else 0)
                    .put("paused", Repo.paused).put("rec", Repo.recoveryUntil > 0)
                scope.launch { Link.sendJson(this@ExerciseService, Paths.LIVE, o) }
            }
            // ✓ του ρολογιού που δεν έφτασαν στο κινητό: ξανά, ανά 10″ (το κινητό αγνοεί όσα έχει ήδη· έλεγχος #2).
            val pend = Repo.pendingTicks
            val ph = Repo.phone
            if (Repo.runningPhone && ph != null && pend.isNotEmpty() && nowEl - lastPendingSent >= 10_000) {
                lastPendingSent = nowEl
                for ((i, k) in pend) {
                    val o = JSONObject().put(Proto.CMD_VERSION, Proto.MAJOR).put("op", "tick").put("i", i).put("s", k).put("sid", ph.id).put("late", true)
                    ph.items.getOrNull(i)?.sets?.getOrNull(k)?.at?.takeIf { it > 0 }?.let { o.put("at", it) }
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
            // Εφεδρεία αισθητήρα: στέλνει μόνο αλλαγές· σταθεροί παλμοί πάνω από το όριο μετρούν κι αυτοί (W2-02).
            if (sensor != null && fresh && Repo.alarm.steady(Repo.bpm, nowEl)) onAlarm(Repo.bpm)
            // Με όριο: αν χαθούν οι παλμοί (π.χ. χαλαρό λουρί), μία δόνηση να το ξέρεις, και στα βάρη (έλεγχος #2):
            // στο περπάτημα μετά από 15″, στα βάρη μετά από 45″ (ο καρπός που λυγίζει κόβει συχνά για λίγο). Τρεις
            // σύντομες, για να μη μοιάζει με το τέλος του διαλείμματος (δύο μεγαλύτερες).
            // Έλεγχος 9/11 (V-A-04): και όταν δεν ήρθε ΚΑΝΕΝΑΣ παλμός 30″ μετά την αρχή (πριν: καμία δόνηση), με άλλο
            // μοτίβο (μία μακριά και δύο σύντομες). Μία φορά· ξανά μόνο αν ξαναέρθουν παλμοί και χαθούν.
            val lostAfter = if (Repo.running == "walk") 15_000L else 45_000L
            val lastEl = if (Repo.bpmEl > 0) maxOf(Repo.bpmEl, Repo.steadyUntilEl) else 0L
            if (silence.check(nowEl, Repo.startedEl, lastEl, fresh, Repo.alarm.limit != null, Repo.paused, lostAfter)) {
                vibrate(if (silence.state == HrSilence.Silence.NEVER) longArrayOf(0, 400, 150, 70, 90, 70) else longArrayOf(0, 70, 90, 70, 90, 70))
            }
            Repo.hrSilent = silence.state
            // Ήρθε ο πρώτος παλμός ή έγινε ο έλεγχος των 30″: ο επεξεργαστής ξανά ελεύθερος να κοιμηθεί.
            if (firstHrLock != null && (fresh || Repo.bpmAt > 0 || silence.state != null || nowEl - Repo.startedEl >= FIRST_HR_LOCK_MS)) {
                releaseFirstHrLock()
            }
            // Τέλος του λεπτού αποκατάστασης.
            if (Repo.recoveryUntil > 0 && now >= Repo.recoveryUntil) {
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

    // ------------------------------------------------------------------ όριο παλμών
    private fun onAlarm(bpm: Int) {
        vibrate(longArrayOf(0, 500, 200, 500, 200, 500))
        Repo.alarmMutedUntil = 0
        // Αν η οθόνη δεν είναι ανοιχτή: ειδοποίηση υψηλής προτεραιότητας (ανάβει και δονείται).
        val nm = getSystemService(NotificationManager::class.java)
        val pi = PendingIntent.getActivity(this, 1, Intent(this, WatchActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(this, CH_ALARM)
            .setSmallIcon(R.drawable.ic_heart)
            .setContentTitle("Πάνω από το όριο: $bpm")
            .setContentText(alarmAdvice() + " Όριο γιατρού ${Repo.alarm.limit}.")
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

    private fun alarmAdvice(): String = if (Repo.running == "walk") "Κόψε ρυθμό." else "Ξεκουράσου μέχρι να πέσουν κάτω από ${Repo.alarm.limit}."

    /**
     * Δόνηση ως «ξυπνητήρι» (USAGE_ALARM): αλλιώς η Εξοικονόμηση μπαταρίας και η Σίγαση την κόβουν, και οι σύντομες
     * μπορεί να θεωρηθούν δόνηση αφής (έλεγχος #2, W2-01). Μόνο όσο τρέχει άσκηση.
     */
    private fun vibrate(pattern: LongArray) {
        val v: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
        val effect = VibrationEffect.createWaveform(pattern, -1)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                v?.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
            } else {
                @Suppress("DEPRECATION")
                v?.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
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
            vibrate(longArrayOf(0, 120))
            saveRun(force = true)
            Repo.changed()
            return
        }
        finish(userEnd = true)
    }

    // ------------------------------------------------------------------ τέλος
    /**
     * Τέλος της άσκησης και αποτέλεσμα στο κινητό. [userEnd]: πάτησε «Τέλος» εδώ (σε προπόνηση του κινητού: τέλος και εκεί,
     * V-A-09). [endReason]: τελείωσε από αλλού (V-A-16). Το αποτέλεσμα μπαίνει πρώτα στην αναμονή (σβήνεται μόνο όταν μπει
     * στο Data Layer) και μετά σβήνεται το στιγμιότυπο της άσκησης: σε κάθε στιγμή υπάρχει ένα από τα δύο.
     */
    private suspend fun finish(userEnd: Boolean = false, endReason: Int? = null) {
        if (stopping) return
        stopping = true
        releaseFirstHrLock()
        val now = System.currentTimeMillis()
        ticker?.cancel()
        sensor?.stop()
        sensor = null
        Repo.hrGaps.close(if (Repo.bpmAt > 0) minOf(now, Repo.bpmAt + 60_000) else now)
        if (exerciseStarted) {
            // Ό,τι έχει μετρηθεί και δεν έχει παραδοθεί ακόμα (πακέτα ανά 5″) έρχεται τώρα, πριν από τον λογαριασμό.
            try {
                client.flushAsync().await()
                delay(400)
            } catch (_: Exception) {
            }
            try {
                client.endExerciseAsync().await()
            } catch (_: Exception) {
            }
            try {
                client.clearUpdateCallbackAsync(callback).await()
            } catch (_: Exception) {
            }
        }
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
        // «Τέλος» στο ρολόι σε προπόνηση του κινητού: τέλος και εκεί (V-A-09). Μήνυμα τώρα (αν το κινητό ακούει)· και το
        // «fin» μέσα στο αποτέλεσμα, που μένει ώσπου να το πάρει το κινητό.
        val sid = result?.second?.optString("sid", "").orEmpty()
        if (userEnd && wasPhone && sid.isNotEmpty()) {
            Link.sendJson(this, Paths.CMD, JSONObject().put(Proto.CMD_VERSION, Proto.MAJOR).put("op", "end").put("sid", sid).put("at", now))
        }
        if (result != null) {
            Repo.savePending(this, result.first, result.second)
            Repo.clearRun(this)
            if (Link.putResult(this, result.first, result.second)) Repo.removePending(this, result.first)
        } else if (!failed) {
            // Τίποτα να σταλεί (π.χ. προπόνηση χωρίς σετ): το στιγμιότυπο δεν χρειάζεται πια.
            Repo.clearRun(this)
        }
        Repo.local = null
        Repo.resetExercise()
        // Προπόνηση του κινητού: γράφεται εκεί, εδώ πίσω στην αρχή. Δική του: «Αποθηκεύτηκε».
        Repo.screen = when {
            result != null && kind != null && !wasPhone -> Repo.Screen.END
            else -> Repo.Screen.HOME
        }
        Repo.changed()
        getSystemService(NotificationManager::class.java).cancel(ALARM_ID)
        ongoingActivity = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
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
