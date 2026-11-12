package gr.ygeiaforma.ygeia_forma

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Προπόνηση (8/11). Κανάλι «ygeia/training».
 * - Το training.json (προγράμματα, προπονήσεις): ατομική εγγραφή, μπαίνει στο κρυπτογραφημένο αντίγραφο.
 * - Οθόνη αναμμένη μόνο όσο είναι ανοιχτή η προπόνηση.
 * - Διάλειμμα: ειδοποίηση με αντίστροφη μέτρηση (φαίνεται και στο ρολόι) και δόνηση στο τέλος.
 *   Χωρίς υπηρεσία παρασκηνίου και χωρίς καμία νέα άδεια. Το τέλος έρχεται με ξυπνητήρι που καλεί κατευθείαν εδώ
 *   (OnAlarmListener): ξυπνά το κινητό στην ώρα του και με σβηστή οθόνη, όσο ζει η εφαρμογή (τελικός έλεγχος,
 *   Συμβούλιο 5, U-2). Πριν ήταν ένας χρονοδιακόπτης στη μνήμη, που με κλειδωμένο κινητό αργούσε.
 */
class TrainingBridge(
    private val activity: Activity,
    private val scope: CoroutineScope,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Το κείμενο ως έχει (όχι μέσα σε άλλο JSON: μία κωδικοποίηση λιγότερη, DP-02).
            "read" -> scope.launch {
                val out: Map<String, String> = withContext(Dispatchers.IO) {
                    val f = File(activity.filesDir, FILE)
                    try {
                        if (!f.exists()) mapOf("state" to "missing")
                        else mapOf("state" to "ok", "json" to f.readText())
                    } catch (e: Throwable) {
                        mapOf("state" to "error")
                    }
                }
                result.success(out)
            }
            "write" -> scope.launch {
                val text = call.argument<String>("json") ?: ""
                val ok = withContext(Dispatchers.IO) {
                    OuraBridge.atomicWrite(File(activity.filesDir, FILE), text.toByteArray(Charsets.UTF_8))
                }
                result.success(ok)
            }
            // Οι παλμοί κάθε προπόνησης σε δικό της αρχείο (V-A-02).
            "hrRead" -> scope.launch {
                val id = call.argument<String>("id") ?: ""
                val (state, json) = withContext(Dispatchers.IO) { HrFiles.readState(hrDir(), id) }
                result.success(if (json == null) mapOf("state" to state) else mapOf("state" to state, "json" to json))
            }
            "hrWrite" -> scope.launch {
                val id = call.argument<String>("id") ?: ""
                val text = call.argument<String>("json") ?: ""
                result.success(withContext(Dispatchers.IO) { HrFiles.write(hrDir(), id, text) })
            }
            "hrDelete" -> scope.launch {
                val id = call.argument<String>("id") ?: ""
                result.success(withContext(Dispatchers.IO) { HrFiles.delete(hrDir(), id) })
            }
            "hrBad" -> scope.launch {
                val id = call.argument<String>("id") ?: ""
                result.success(withContext(Dispatchers.IO) { HrFiles.setAside(hrDir(), id) })
            }
            "hrList" -> scope.launch {
                result.success(withContext(Dispatchers.IO) { HrFiles.list(hrDir()) })
            }
            "keepOn" -> {
                val on = call.argument<Boolean>("on") == true
                if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                result.success(true)
            }
            "askNotify" -> result.success(askNotify())
            "rest" -> {
                val end = (call.argument<Number>("endAt") ?: 0).toLong()
                rest(
                    activity.applicationContext, end,
                    call.argument<String>("title") ?: "Διάλειμμα",
                    call.argument<String>("text") ?: "",
                    call.argument<String>("doneTitle") ?: "Τέλος διαλείμματος",
                    call.argument<String>("doneText") ?: "",
                )
                result.success(true)
            }
            "restCancel" -> {
                cancel(activity.applicationContext)
                result.success(true)
            }
            "buzz" -> {
                vibrate(activity.applicationContext, longArrayOf(0, 300, 150, 300))
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun hrDir() = File(activity.filesDir, HrFiles.DIR)

    /** Ζητά άδεια ειδοποιήσεων (Android 13+), μία φορά, όταν ξεκινά η πρώτη προπόνηση. */
    private fun askNotify(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        val granted = ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7301)
        return granted
    }

    companion object {
        const val FILE = "training.json"
        private const val CH_COUNT = "rest_count"
        private const val CH_DONE = "rest_done"
        private const val ID_COUNT = 7310
        private const val ID_DONE = 7311

        private val handler = Handler(Looper.getMainLooper())
        private var pending: Runnable? = null

        /** Το ξυπνητήρι του διαλείμματος που εκκρεμεί, για να ακυρώνεται (Συμβούλιο 5, U-2). */
        private var alarm: AlarmManager.OnAlarmListener? = null

        private fun channels(ctx: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CH_COUNT) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CH_COUNT, "Διάλειμμα (αντίστροφη μέτρηση)", NotificationManager.IMPORTANCE_LOW).apply {
                        description = "Πόσος χρόνος μένει ως το επόμενο σετ"
                        setShowBadge(false)
                    },
                )
            }
            if (nm.getNotificationChannel(CH_DONE) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CH_DONE, "Τέλος διαλείμματος", NotificationManager.IMPORTANCE_HIGH).apply {
                        description = "Δόνηση όταν τελειώνει το διάλειμμα"
                        enableVibration(true)
                        vibrationPattern = longArrayOf(0, 400, 200, 400)
                        setShowBadge(false)
                    },
                )
            }
        }

        private fun openApp(ctx: Context): PendingIntent {
            val i = Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(ctx, 7300, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        private fun canNotify(ctx: Context): Boolean =
            Build.VERSION.SDK_INT < 33 ||
                ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

        fun rest(ctx: Context, endAt: Long, title: String, text: String, doneTitle: String, doneText: String) {
            cancel(ctx)
            val left = endAt - System.currentTimeMillis()
            if (left <= 0) return
            try {
                channels(ctx)
                val nm = ctx.getSystemService(NotificationManager::class.java)
                if (nm != null && canNotify(ctx)) {
                    val n = NotificationCompat.Builder(ctx, CH_COUNT)
                        .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                        .setContentTitle(title)
                        .setContentText(text)
                        .setWhen(endAt)
                        .setShowWhen(true)
                        .setUsesChronometer(true)
                        .setChronometerCountDown(true)
                        .setOngoing(true)
                        .setOnlyAlertOnce(true)
                        .setSilent(true)
                        .setTimeoutAfter(left + 1000)
                        .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
                        .setContentIntent(openApp(ctx))
                        .build()
                    nm.notify(ID_COUNT, n)
                }
            } catch (e: Throwable) {
                ErrorQueue.report(e, "training")
            }
            val r = object : Runnable {
                override fun run() {
                    // Ένα διάλειμμα που ακυρώθηκε ή αντικαταστάθηκε στο μεταξύ («Συνέχεια», «+30″») δεν χτυπά.
                    if (pending !== this) return
                    pending = null
                    alarm = null
                    try {
                        val nm = ctx.getSystemService(NotificationManager::class.java)
                        nm?.cancel(ID_COUNT)
                        if (nm != null && canNotify(ctx)) {
                            val n = NotificationCompat.Builder(ctx, CH_DONE)
                                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                                .setContentTitle(doneTitle)
                                .setContentText(doneText)
                                .setPriority(NotificationCompat.PRIORITY_HIGH)
                                .setCategory(NotificationCompat.CATEGORY_ALARM)
                                .setAutoCancel(true)
                                .setTimeoutAfter(60_000)
                                .setContentIntent(openApp(ctx))
                                .build()
                            nm.notify(ID_DONE, n)
                        }
                    } catch (e: Throwable) {
                        ErrorQueue.report(e, "training")
                    }
                    vibrate(ctx, longArrayOf(0, 400, 200, 400, 200, 600))
                }
            }
            pending = r
            arm(ctx, r, left)
        }

        /**
         * Το «τέλος διαλείμματος» στην ώρα του και με σβηστή οθόνη (τελικός έλεγχος, Συμβούλιο 5, U-2).
         * Πριν: μόνο Handler.postDelayed. Ο χρόνος του δεν μετρά όσο ο επεξεργαστής κοιμάται, άρα με κλειδωμένο κινητό η
         * ειδοποίηση και η δόνηση έρχονταν όταν ξυπνούσε το κινητό (το ίδιο σφάλμα είχε βρεθεί στο ρολόι, W2-03).
         * Τώρα: ξυπνητήρι ακριβείας που ξυπνά το κινητό και καλεί εδώ (OnAlarmListener), με τον χρόνο από την εκκίνηση
         * του κινητού (δεν το πειράζει μια αλλαγή ώρας στη μέση). Αυτή η μορφή ΔΕΝ θέλει την άδεια «Ξυπνητήρια και
         * υπενθυμίσεις» (τεκμηρίωση Android 14, «Schedule exact alarms are denied by default»): δουλεύει όσο ζει η
         * διεργασία της εφαρμογής. Αν το σύστημα το αρνηθεί, μένει ο παλιός χρονοδιακόπτης.
         */
        private fun arm(ctx: Context, r: Runnable, left: Long) {
            try {
                val am = ctx.getSystemService(AlarmManager::class.java)
                if (am != null) {
                    val l = AlarmManager.OnAlarmListener { r.run() }
                    am.setExact(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        TrainingRules.restTrigger(SystemClock.elapsedRealtime(), left),
                        "ygeia:rest", l, handler,
                    )
                    alarm = l
                    return
                }
            } catch (e: Throwable) {
                ErrorQueue.report(e, "training")
            }
            handler.postDelayed(r, left)
        }

        fun cancel(ctx: Context) {
            pending?.let { handler.removeCallbacks(it) }
            pending = null
            alarm?.let { l ->
                try {
                    ctx.getSystemService(AlarmManager::class.java)?.cancel(l)
                } catch (_: Throwable) {
                }
            }
            alarm = null
            try {
                val nm = ctx.getSystemService(NotificationManager::class.java)
                nm?.cancel(ID_COUNT)
                nm?.cancel(ID_DONE)
            } catch (_: Throwable) {
            }
        }

        /**
         * Δόνηση ως «ξυπνητήρι» (USAGE_ALARM), όπως στο ρολόι (W2-01). Χωρίς αυτό η δόνηση δεν έχει «είδος» και το Android
         * την αγνοεί όταν η εφαρμογή δεν είναι μπροστά ή η οθόνη είναι σβηστή, και η Εξοικονόμηση μπαταρίας την κόβει:
         * έμενε μόνο η δόνηση της ειδοποίησης (τελικός έλεγχος, Συμβούλιο 5, U-2).
         */
        fun vibrate(ctx: Context, pattern: LongArray) {
            try {
                val v: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
                    ctx.getSystemService(VibratorManager::class.java)?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                }
                if (v == null || !v.hasVibrator()) return
                val effect = VibrationEffect.createWaveform(pattern, -1)
                if (Build.VERSION.SDK_INT >= 33) {
                    v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
                }
            } catch (e: Throwable) {
                ErrorQueue.report(e, "training")
            }
        }
    }
}
