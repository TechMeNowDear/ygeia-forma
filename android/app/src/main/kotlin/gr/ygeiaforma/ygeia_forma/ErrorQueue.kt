package gr.ygeiaforma.ygeia_forma

import android.content.Context
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Σφάλματα της πλευράς Android (Kotlin) για το Sentry.
 *
 * Δεν στέλνει τίποτα η ίδια: γράφει ένα αρχείο στην ουρά (files/errq) και την αποστολή
 * την κάνει η Flutter (lib/error_report.dart) — στο επόμενο άνοιγμα ή όταν επιστρέψω στην εφαρμογή.
 * Μόνο το σφάλμα, η στοίβα και η οθόνη· ποτέ δεδομένα υγείας ή φαγητού.
 *
 * Διακόπτης «Αναφορές σφαλμάτων» (έλεγχος 9/11, E3-05): η επιλογή γράφεται εδώ (SharedPreferences «errors»), ώστε να
 * ισχύει και για κρασάρισμα πριν ανοίξει η Flutter. Κλειστός: τίποτα δεν γράφεται στην ουρά, και ό,τι περίμενε σβήνεται.
 * Ανοιχτός από την αρχή, όπως λέει η πολιτική απορρήτου.
 */
object ErrorQueue : MethodChannel.MethodCallHandler {
    private const val MAX_QUEUE = 20
    private const val DEDUPE_MS = 60_000L

    private var dir: File? = null
    private const val PREFS = "errors"
    private const val KEY_SEND = "send"

    /** Ο διακόπτης· διαβάζεται στο [install]. */
    @Volatile
    var enabled: Boolean = true
        private set
    private var version = "dev"
    private var installed = false
    private val recent = HashMap<String, Long>()

    /** Η οθόνη που βλέπω τώρα· την ενημερώνει η Flutter. */
    @Volatile
    var screen: String = "Σήμερα"

    fun install(context: Context) {
        val app = context.applicationContext
        dir = File(app.filesDir, "errq")
        enabled = try {
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_SEND, true)
        } catch (_: Throwable) {
            true
        }
        version = try {
            app.packageManager.getPackageInfo(app.packageName, 0).versionName ?: "dev"
        } catch (_: Throwable) {
            "dev"
        }
        prefsWriter = { on -> app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_SEND, on).commit() }
        if (installed) return
        installed = true
        // Κρασάρισμα: γράφω το σφάλμα και αφήνω το Android να κλείσει την εφαρμογή όπως πάντα.
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            write(e, handled = false, where = "crash")
            previous?.uncaughtException(thread, e)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> result.success(
                mapOf(
                    "dir" to (dir?.absolutePath ?: ""),
                    "version" to version,
                    "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                    "enabled" to enabled,
                ),
            )
            "setEnabled" -> {
                val on = call.arguments as? Boolean
                if (on == null) {
                    result.success(false)
                    return
                }
                result.success(setEnabled(on))
            }
            "screen" -> {
                (call.arguments as? String)?.let { screen = it }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Σφάλμα που πιάστηκε σε μια γέφυρα (η εφαρμογή συνεχίζει). Δεν πετάει ποτέ η ίδια. */
    fun report(e: Throwable, where: String) {
        // Χωρίς ίντερνετ / αργή σύνδεση: φυσιολογικό, δεν αναφέρεται.
        if (e is java.io.IOException) return
        write(e, handled = true, where = where)
    }

    /** Γράφει την επιλογή (commit: πριν απαντήσει)· κλείσιμο = σβήνεται η ουρά. `false` αν δεν γράφτηκε. */
    @Synchronized
    private fun setEnabled(on: Boolean): Boolean {
        val queue = dir ?: return false
        val ok = try {
            prefsWriter?.invoke(on) ?: false
        } catch (_: Throwable) {
            false
        }
        if (!ok) return false
        enabled = on
        if (!on) queue.listFiles()?.forEach { it.delete() }
        return true
    }

    /** Ορίζεται στο [install] (χρειάζεται Context). */
    private var prefsWriter: ((Boolean) -> Boolean)? = null

    @Synchronized
    private fun write(e: Throwable, handled: Boolean, where: String) {
        try {
            if (!enabled) return
            val d = dir ?: return
            val sig = "${e.javaClass.name}:${firstLine(e.message)}"
            val now = System.currentTimeMillis()
            if (handled && now - (recent[sig] ?: 0L) < DEDUPE_MS) return
            recent[sig] = now
            d.mkdirs()
            val id = UUID.randomUUID().toString().replace("-", "")
            File(d, "${now.toString().padStart(14, '0')}_$id.json").writeText(event(e, handled, where, id, now).toString())
            val files = d.listFiles { f -> f.name.endsWith(".json") }?.sortedBy { it.name } ?: return
            files.take(maxOf(0, files.size - MAX_QUEUE)).forEach { it.delete() }
        } catch (_: Throwable) {
            // Η αναφορά σφαλμάτων δεν πρέπει ποτέ να χαλάσει την εφαρμογή.
        }
    }

    private fun event(e: Throwable, handled: Boolean, where: String, id: String, now: Long): JSONObject {
        // Αλυσίδα αιτιών: το Sentry θέλει την αρχική αιτία πρώτη και το εξωτερικό σφάλμα τελευταίο.
        val chain = ArrayList<Throwable>()
        var t: Throwable? = e
        while (t != null && chain.size < 5 && t !in chain) {
            chain.add(t)
            t = t.cause
        }
        val values = JSONArray()
        for (x in chain.reversed()) {
            val frames = JSONArray()
            for (f in x.stackTrace.take(60).reversed()) {
                frames.put(
                    JSONObject()
                        .put("function", f.methodName)
                        .put("module", f.className)
                        .put("filename", f.fileName ?: "?")
                        .put("lineno", f.lineNumber)
                        .put("in_app", f.className.startsWith("gr.ygeiaforma")),
                )
            }
            values.put(
                JSONObject()
                    .put("type", x.javaClass.simpleName)
                    .put("module", x.javaClass.`package`?.name ?: "")
                    .put("value", DataRules.reportableMessage(x.javaClass, firstLine(x.message)).take(300))
                    .put("stacktrace", JSONObject().put("frames", frames))
                    .put("mechanism", JSONObject().put("type", if (handled) "handled" else "uncaught").put("handled", handled)),
            )
        }
        return JSONObject()
            .put("event_id", id)
            .put("timestamp", now / 1000.0)
            .put("platform", "java")
            .put("level", if (handled) "error" else "fatal")
            .put("release", "ygeia-forma@$version")
            .put("environment", "android")
            .put("sdk", JSONObject().put("name", "ygeia-forma.report").put("version", "1"))
            .put("tags", JSONObject().put("screen", screen).put("handled", handled.toString()).put("source", "android").put("where", where))
            .put(
                "contexts",
                JSONObject()
                    .put("os", JSONObject().put("name", "Android").put("version", "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"))
                    .put("device", JSONObject().put("model", "${Build.MANUFACTURER} ${Build.MODEL}")),
            )
            .put("exception", JSONObject().put("values", values))
    }

    private fun firstLine(s: String?): String = (s ?: "").lineSequence().firstOrNull()?.trim() ?: ""
}
