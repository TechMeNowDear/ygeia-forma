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
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.Duration
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
        const val EXTRA_KIND = "kind"
        const val EXTRA_PHONE = "phone"
        private const val NOTIF_ID = 41
        private const val ALARM_ID = 42
        private const val CH_WORKOUT = "workout"
        // Νέο κανάλι (έλεγχος #2): χωρίς δική του δόνηση, για να μη «κόβει» τη δόνηση ξυπνητηριού της εφαρμογής.
        // Οι ρυθμίσεις ενός καναλιού δεν αλλάζουν μετά τη δημιουργία του, γι' αυτό νέο όνομα· το παλιό σβήνεται.
        private const val CH_ALARM = "hr_alarm2"
        private const val CH_ALARM_OLD = "hr_alarm"

        fun start(ctx: Context, kind: String, phone: Boolean) {
            val i = Intent(ctx, ExerciseService::class.java).setAction(ACTION_START)
                .putExtra(EXTRA_KIND, kind).putExtra(EXTRA_PHONE, phone)
            ContextCompat.startForegroundService(ctx, i)
        }

        fun stop(ctx: Context) {
            if (Repo.running == null) return
            ctx.startService(Intent(ctx, ExerciseService::class.java).setAction(ACTION_STOP))
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
    private var lostBuzzed = false
    private var lastPendingSent = 0L
    /** Εφεδρεία αισθητήρα για την ειδοποίηση (μόνο χωρίς παράδοση ανά 5″ και με όριο). */
    private var sensor: HrSensor? = null
    private var exerciseStarted = false
    private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Link.attach(this)
        channels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> begin(intent.getStringExtra(EXTRA_KIND) ?: "strength", intent.getBooleanExtra(EXTRA_PHONE, false))
            ACTION_STOP -> scope.launch { finish() }
            else -> if (Repo.running == null) stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        sensor?.stop()
        sensor = null
        ticker?.cancel()
        scope.cancel()
        Link.detach(this)
        super.onDestroy()
    }

    // ------------------------------------------------------------------ έναρξη
    private fun begin(kind: String, phone: Boolean) {
        val now = System.currentTimeMillis()
        if (Repo.running != null) {
            // Ήδη τρέχει: απλώς ενημερώνει τον τρόπο (π.χ. η προπόνηση του κινητού βρήκε το ρολόι).
            Repo.runningPhone = phone
            return
        }
        Repo.resetExercise()
        Repo.running = kind
        Repo.runningPhone = phone
        Repo.startedAt = now
        Repo.hr = HrStats(now)
        Repo.alarm.limit = Repo.plan?.hrLimit
        Repo.alarm.reset()

        val walk = kind == "walk"
        // GPS μόνο με άδεια ΚΑΙ με την τοποθεσία του ρολογιού ανοιχτή (αλλιώς το Health Services αρνείται την άσκηση).
        val location = walk && has(this, Manifest.permission.ACCESS_FINE_LOCATION) && locationOn()
        Repo.gps = location
        var type = 0
        if (Build.VERSION.SDK_INT >= 34) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        if (location) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        val n = ongoing(if (walk) "Περπάτημα" else (Repo.session?.name ?: "Προπόνηση"), now)
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
        scope.launch { startExercise(walk, location) }
        ticker = scope.launch { tick() }
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
                val s = HrSensor(this) { bpm, at -> scope.launch { onSensorBpm(bpm, at) } }
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
            val m = update.latestMetrics
            // Κάθε τιμή με τον δικό της χρόνο (σε ένα πακέτο μπορεί να έρθουν πολλές).
            val boot = Instant.ofEpochMilli(now - SystemClock.elapsedRealtime())
            var buzz = -1
            val points = m.getData(DataType.HEART_RATE_BPM)
            if (points.isNotEmpty() && sensor == null) Repo.hrGaps.mark(now)
            for (p in points) {
                val bpm = Math.round(p.value).toInt()
                if (bpm !in 26..249) continue
                val at = p.getTimeInstant(boot).toEpochMilli().coerceAtMost(now)
                Repo.hr?.add(bpm, at)
                if (at >= Repo.bpmAt) {
                    Repo.bpm = bpm
                    Repo.bpmAt = at
                }
                // Και οι δύο πηγές πάνε στην ειδοποίηση· οι παλιότερες τιμές αγνοούνται (HrAlarm.feed), οπότε αν ο
                // αισθητήρας σωπάσει, συνεχίζει το Health Services (έλεγχος #2, W2-04).
                if (Repo.alarm.feed(bpm, at)) buzz = bpm
            }
            if (buzz > 0) onAlarm(buzz)
            if (points.isNotEmpty()) sendHrToPhone(now)
            m.getData(DataType.DISTANCE_TOTAL)?.let { Repo.meters = it.total }
            m.getData(DataType.STEPS_TOTAL)?.let { Repo.steps = it.total }
            update.activeDurationCheckpoint?.let { c ->
                Repo.activeSec = (c.activeDuration + Duration.between(c.time, Instant.now())).seconds
            }
            if (update.exerciseStateInfo.state.isEnded && !stopping) {
                // Τελείωσε από αλλού (άλλη εφαρμογή, χάθηκε άδεια): κρατάμε ό,τι γράφτηκε.
                scope.launch { finish() }
            }
            Repo.changed()
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) {}

        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {}
    }

    /** Τιμή από την εφεδρεία αισθητήρα: ένδειξη και ειδοποίηση (όχι στατιστικά: αυτά από το Health Services). */
    private fun onSensorBpm(bpm: Int, at: Long) {
        if (stopping) return
        Repo.hrGaps.mark(System.currentTimeMillis())
        if (at >= Repo.bpmAt) {
            Repo.bpm = bpm
            Repo.bpmAt = at
        }
        if (Repo.alarm.feed(bpm, at)) onAlarm(bpm)
        sendHrToPhone(System.currentTimeMillis())
        Repo.changed()
    }

    /**
     * Παλμοί προς το κινητό (ανά 5″), όταν η προπόνηση τρέχει εκεί. Από την ίδια την παράδοση παλμών, όχι από τον βρόχο
     * του δευτερολέπτου, που σταματά όταν κοιμάται ο επεξεργαστής (έλεγχος #2, W2-03).
     */
    private fun sendHrToPhone(now: Long) {
        if (!Repo.runningPhone || !Repo.bpmFresh(now) || now - lastHrSent < 5000) return
        lastHrSent = now
        val o = JSONObject().put("bpm", Repo.bpm).put("t", Repo.bpmAt).put("sid", Repo.phone?.id ?: "")
        scope.launch { Link.sendJson(this@ExerciseService, Paths.HR, o) }
    }

    // ------------------------------------------------------------------ κάθε δευτερόλεπτο
    private suspend fun tick() {
        while (scope.isActive) {
            val now = System.currentTimeMillis()
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
                val o = JSONObject().put("kind", "walk").put("start", Repo.startedAt).put("sec", Repo.activeSec)
                    .put("m", Repo.meters).put("steps", Repo.steps).put("bpm", if (Repo.bpmFresh(now)) Repo.bpm else 0)
                scope.launch { Link.sendJson(this@ExerciseService, Paths.LIVE, o) }
            }
            // ✓ του ρολογιού που δεν έφτασαν στο κινητό: ξανά, ανά 10″ (το κινητό αγνοεί όσα έχει ήδη· έλεγχος #2).
            val pend = Repo.pendingTicks
            val ph = Repo.phone
            if (Repo.runningPhone && ph != null && pend.isNotEmpty() && now - lastPendingSent >= 10_000) {
                lastPendingSent = now
                for ((i, k) in pend) {
                    val o = JSONObject().put("op", "tick").put("i", i).put("s", k).put("sid", ph.id).put("late", true)
                    ph.items.getOrNull(i)?.sets?.getOrNull(k)?.at?.takeIf { it > 0 }?.let { o.put("at", it) }
                    scope.launch { Link.sendJson(this@ExerciseService, Paths.CMD, o) }
                }
            }
            // Εφεδρεία αισθητήρα με επαφή και ίδια τιμή: οι παλμοί είναι απλώς σταθεροί, όχι χαμένοι (ως 2′).
            // Μόνο για ένδειξη/ειδοποίηση· δεν γίνεται «τιμή» προς το κινητό (έλεγχος #2).
            val sn = sensor
            Repo.steadyUntil = if (sn != null && sn.contact && sn.last > 0 && Repo.bpm == sn.last) sn.lastAt + 120_000L else 0L
            val fresh = Repo.hrLive(now)
            // Εφεδρεία αισθητήρα: στέλνει μόνο αλλαγές· σταθεροί παλμοί πάνω από το όριο μετρούν κι αυτοί (W2-02).
            if (sensor != null && fresh && Repo.alarm.steady(Repo.bpm, now)) onAlarm(Repo.bpm)
            // Με όριο: αν χαθούν οι παλμοί (π.χ. χαλαρό λουρί), μία δόνηση να το ξέρεις, και στα βάρη (έλεγχος #2):
            // στο περπάτημα μετά από 15″, στα βάρη μετά από 45″ (ο καρπός που λυγίζει κόβει συχνά για λίγο). Τρεις
            // σύντομες, για να μη μοιάζει με το τέλος του διαλείμματος (δύο μεγαλύτερες).
            val lostAfter = if (Repo.running == "walk") 15_000L else 45_000L
            if (fresh) {
                lostBuzzed = false
            } else if (Repo.alarm.limit != null && Repo.bpmAt > 0 && now - maxOf(Repo.bpmAt, Repo.steadyUntil) >= lostAfter && !lostBuzzed) {
                lostBuzzed = true
                vibrate(longArrayOf(0, 70, 90, 70, 90, 70))
            }
            // Η προπόνηση του κινητού έκλεισε εκεί: τέλος και εδώ.
            if (Repo.runningPhone && Repo.phone == null && Repo.local == null) {
                scope.launch { finish() } // όχι μέσα σε αυτόν τον βρόχο: το finish τον σταματά
                return
            }
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

    // ------------------------------------------------------------------ τέλος
    private suspend fun finish() {
        if (stopping) return
        stopping = true
        val now = System.currentTimeMillis()
        ticker?.cancel()
        sensor?.stop()
        sensor = null
        Repo.hrGaps.close(if (Repo.bpmAt > 0) minOf(now, Repo.bpmAt + 60_000) else now)
        if (exerciseStarted) {
            try {
                client.endExerciseAsync().await()
            } catch (_: Exception) {
            }
            try {
                client.clearUpdateCallbackAsync(callback).await()
            } catch (_: Exception) {
            }
        }
        val hr = Repo.hr ?: HrStats(now)
        val kind = Repo.running
        val wasPhone = Repo.runningPhone
        val local = Repo.local
        val result: Pair<String, JSONObject>? = when {
            kind == "walk" -> {
                val id = "walk${Repo.startedAt}"
                val cardio = JSONObject().put("activity", "walk").put("sec", Repo.activeSec).put("m", Repo.meters).put("steps", Repo.steps)
                val w = Repo.plan?.todayWorkout?.takeIf { it.isCardio }
                id to LiveSession(id, w?.id ?: "walk", w?.name ?: "Περπάτημα", Repo.startedAt, emptyList()).resultJson(now, hr, cardio)
            }
            local != null && local.setsDone > 0 -> local.id to local.resultJson(now, hr)
            Repo.runningPhone -> {
                // Η προπόνηση γράφτηκε στο κινητό· εδώ μόνο οι παλμοί, για την περίπτωση που χάθηκαν μηνύματα.
                val sid = Repo.phone?.id ?: lastPhoneId
                // Και τα σετ όπως τα ξέρει το ρολόι: αν το κινητό έχασε κάποιο ✓, το συμπληρώνει (έλεγχος 8/11).
                val items = Repo.phone?.takeIf { it.id == sid }?.resultJson(now, hr)?.optJSONArray("items")
                if (sid.isNullOrEmpty()) null else ("hr$sid" to JSONObject().put("v", 1).put("kind", "hr").put("sid", sid).also {
                    hr.writeTo(it)
                    if (items != null) it.put("items", items)
                })
            }
            else -> null
        }
        // Για τον έλεγχο στη συσκευή: πώς ήρθαν οι παλμοί και το μεγαλύτερο κενό (φαίνεται στη σύνοψη του κινητού).
        if (result != null && Repo.hrMode.isNotEmpty()) result.second.put("hrMode", Repo.hrMode).put("hrGap", Repo.hrGaps.maxGapSec)
        if (result != null) {
            Repo.snapshot(this, result.second)
            if (Link.putResult(this, result.first, result.second)) Repo.snapshot(this, null)
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
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Το id της προπόνησης του κινητού, για τους παλμούς μετά που εκείνη έκλεισε. */
    private val lastPhoneId: String? get() = Repo.lastPhoneId

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

    private fun ongoing(title: String, start: Long): Notification {
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
        val status = Status.Builder()
            .addTemplate("#name# · #time#")
            .addPart("name", Status.TextPart(title))
            .addPart("time", Status.StopwatchPart(start))
            .build()
        OngoingActivity.Builder(applicationContext, NOTIF_ID, b)
            .setStaticIcon(R.drawable.ic_heart)
            .setTouchIntent(pi)
            .setStatus(status)
            .build()
            .apply(applicationContext)
        return b.build()
    }
}
