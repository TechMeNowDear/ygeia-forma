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
import android.os.Build
import android.os.IBinder
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
        const val ACTION_START = "gr.ygeiaforma.wear.START"
        const val ACTION_STOP = "gr.ygeiaforma.wear.STOP"
        const val EXTRA_KIND = "kind"
        const val EXTRA_PHONE = "phone"
        private const val NOTIF_ID = 41
        private const val ALARM_ID = 42
        private const val CH_WORKOUT = "workout"
        private const val CH_ALARM = "hr_alarm"

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

        val walk = kind == "walk"
        val location = walk && has(this, Manifest.permission.ACCESS_FINE_LOCATION)
        Repo.gps = location
        var type = 0
        if (Build.VERSION.SDK_INT >= 34) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        if (location) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        val n = ongoing(if (walk) "Περπάτημα" else (Repo.session?.name ?: "Προπόνηση"), now)
        try {
            ServiceCompat.startForeground(this, NOTIF_ID, n, type)
        } catch (e: Exception) {
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
            val config = ExerciseConfig(
                exerciseType = type,
                dataTypes = types,
                isAutoPauseAndResumeEnabled = false,
                isGpsEnabled = location && DataType.LOCATION in types,
            )
            client.startExerciseAsync(config).await()
            exerciseStarted = true
        } catch (e: Exception) {
            Repo.notice = "Δεν ξεκίνησε η μέτρηση παλμών στο ρολόι."
            Repo.changed()
        }
    }

    private val callback = object : ExerciseUpdateCallback {
        override fun onRegistered() {}

        override fun onRegistrationFailed(throwable: Throwable) {
            Repo.notice = "Δεν ξεκίνησε η μέτρηση παλμών στο ρολόι."
            Repo.changed()
        }

        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            val now = System.currentTimeMillis()
            val m = update.latestMetrics
            val hrPoints = m.getData(DataType.HEART_RATE_BPM)
            val last = hrPoints.lastOrNull()
            if (last != null) {
                val bpm = Math.round(last.value).toInt()
                if (bpm in 26..249) {
                    Repo.bpm = bpm
                    Repo.bpmAt = now
                    for (p in hrPoints) Repo.hr?.add(Math.round(p.value).toInt(), now)
                    if (Repo.alarm.feed(bpm)) onAlarm(bpm)
                }
            }
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
            // Παλμοί προς το κινητό, όταν η προπόνηση τρέχει εκεί.
            if (Repo.runningPhone && Repo.bpmFresh(now) && now - lastHrSent >= 5000) {
                lastHrSent = now
                val ph = Repo.phone
                Link.sendJson(this, Paths.HR, JSONObject().put("bpm", Repo.bpm).put("t", Repo.bpmAt).put("sid", ph?.id ?: ""))
            }
            // Περπάτημα: ζωντανά στο κινητό (αν είναι ανοιχτή η εφαρμογή εκεί).
            if (Repo.running == "walk" && now - lastLiveSent >= 10_000) {
                lastLiveSent = now
                Link.sendJson(
                    this, Paths.LIVE,
                    JSONObject().put("kind", "walk").put("start", Repo.startedAt).put("sec", Repo.activeSec)
                        .put("m", Repo.meters).put("steps", Repo.steps).put("bpm", if (Repo.bpmFresh(now)) Repo.bpm else 0),
                )
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
            .setContentText("Σταμάτα, ανάσα. Όριο γιατρού ${Repo.alarm.limit}.")
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

    private fun vibrate(pattern: LongArray) {
        val v: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
        try {
            v?.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } catch (_: Exception) {
        }
    }

    // ------------------------------------------------------------------ τέλος
    private suspend fun finish() {
        if (stopping) return
        stopping = true
        val now = System.currentTimeMillis()
        ticker?.cancel()
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
                if (sid.isNullOrEmpty()) null else ("hr$sid" to JSONObject().put("v", 1).put("kind", "hr").put("sid", sid).also { hr.writeTo(it) })
            }
            else -> null
        }
        if (result != null) {
            Repo.snapshot(this, result.second)
            if (Link.putResult(this, result.first, result.second)) Repo.snapshot(this, null)
        }
        Repo.local = null
        Repo.resetExercise()
        Repo.screen = if (result != null && kind != null) Repo.Screen.END else Repo.Screen.HOME
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
        nm.createNotificationChannel(
            NotificationChannel(CH_ALARM, "Όριο παλμών", NotificationManager.IMPORTANCE_HIGH).apply {
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
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
