package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PersistableBundle
import androidx.work.WorkManager
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

/**
 * «Διαγραφή όλων των δεδομένων» (Ρυθμίσεις › Τα δεδομένα μου· έλεγχος 9/11, E3-05 / V-A-23, ΓΚΠΔ άρθρο 17).
 * Ξανασχεδιασμένη στον έλεγχο του fix-accuracy (M1, M4): η εφαρμογή σβήνει μόνη της τα αρχεία της, ΟΧΙ με το
 * «Διαγραφή δεδομένων» του συστήματος, γιατί αυτό θα έσβηνε και το σημάδι που κρατά το «σβήσε» για το ρολόι ώσπου να
 * το επιβεβαιώσει (και ίσως τα DataItems μας).
 *
 * Η Flutter έχει ήδη κάνει ό,τι θέλει δίκτυο (ανάκληση της Oura) και έχει πάρει δύο επιβεβαιώσεις. Εδώ, με τη σειρά:
 * 1. Σημάδι ([MARKER]: ώρα, «deleting», τι έγινε με την Oura) με commit. Αν δεν γραφτεί, τίποτα άλλο δεν γίνεται.
 * 2. Ρολόι: σβήνονται τα DataItems «/ygeia/…» που ξέρει το κινητό και μπαίνει το «/ygeia/wipe» {"at"}. Το ρολόι
 *    σβήνει τα δικά του (αρχεία, αποτελέσματα σε αναμονή, DataItems) όταν το δει και απαντά «/ygeia/wiped».
 * 3. Widgets χωρίς τιμές, καμία δουλειά στο παρασκήνιο.
 * 4. Σβήσιμο όλων των αρχείων της εφαρμογής ([wipeLocal]) και νέα εκκίνηση. Στη νέα εκκίνηση, ΠΡΙΝ ξεκινήσει η
 *    Flutter ([finishIfNeeded]), σβήνονται ξανά (ό,τι πρόλαβε να γράψει η Flutter στο μεταξύ) και το σημάδι γίνεται
 *    «done». Η Flutter δείχνει «Όλα διαγράφηκαν».
 *
 * Μένουν: το σημάδι (ώρα, χωρίς δεδομένα υγείας: χρειάζεται για να μη ξαναμπεί ποτέ παλιό αποτέλεσμα του ρολογιού,
 * [DataRules.droppedByWipe]), η επιλογή για τις αναφορές σφαλμάτων («errors», ένας διακόπτης) και τα αρχεία του
 * WorkManager (χωρίς δεδομένα· ακυρώθηκαν όλα). Ό,τι δεν είναι στη συσκευή (Samsung Health, Oura, Λήψεις, αντίγραφο
 * Google) δεν σβήνεται: το λέει η οθόνη.
 */
class DataWipe(private val activity: Activity, private val scope: CoroutineScope) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "wipe" -> scope.launch {
                val oura = call.argument<String>("oura") ?: "none"
                val at = System.currentTimeMillis()
                if (!begin(activity, at, oura)) {
                    result.success(mapOf("ok" to false))
                    return@launch
                }
                withTimeoutOrNull(8_000) { sendWipe(activity, at, deleteOld = true) }
                try {
                    HomeWidgets.wipe(activity)
                } catch (_: Throwable) {}
                try {
                    WorkManager.getInstance(activity).cancelAllWork()
                } catch (_: Throwable) {}
                withContext(Dispatchers.IO) { wipeLocal(activity) }
                // Ό,τι δεν σβήστηκε τώρα σβήνεται στην εκκίνηση (finishIfNeeded). Η απάντηση δεν φτάνει ποτέ.
                restart(activity)
            }
            "wipeStatus" -> result.success(status(activity))
            "wipeWatch" -> scope.launch { result.success(syncWatch(activity)) }
            "wipeSeen" -> result.success(prefs(activity).edit().putBoolean(SEEN, true).commit())
            "wipeRetry" -> scope.launch {
                val failed = withContext(Dispatchers.IO) { wipeLocal(activity) }
                if (failed == 0) {
                    prefs(activity).edit().putString(STAGE, DONE).commit()
                    restart(activity)
                } else {
                    result.success(mapOf("failed" to failed))
                }
            }
            // E3-20: αντιγραφή με σήμανση ευαίσθητου (υγεία/φαγητό).
            "copy" -> result.success(
                try {
                    val text = call.arguments as? String ?: ""
                    val clip = ClipData.newPlainText("Υγεία & Φόρμα", text)
                    clip.description.extras = PersistableBundle().apply {
                        putBoolean(if (Build.VERSION.SDK_INT >= 33) ClipDescription.EXTRA_IS_SENSITIVE else "android.content.extra.IS_SENSITIVE", true)
                    }
                    activity.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(clip) != null
                } catch (_: Throwable) {
                    false
                },
            )
            "openPolicy" -> result.success(
                try {
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(POLICY)).addCategory(Intent.CATEGORY_BROWSABLE))
                    true
                } catch (_: Throwable) {
                    false
                },
            )
            else -> result.notImplemented()
        }
    }

    companion object {
        const val POLICY = "https://ygeia-forma.netlify.app/privacy/"

        /** Κινητό → ρολόι: «σβήσε» {"v":1,"at"}. Ρολόι → κινητό: «σβήστηκε» {"v":1,"at"} (νέα paths, πρόσθετα). */
        const val WIPE = "/ygeia/wipe"
        const val WIPED = "/ygeia/wiped"

        /** Το σημάδι: ένα μικρό αρχείο ρυθμίσεων που ΔΕΝ σβήνεται με τα υπόλοιπα. */
        const val MARKER = "ygeia_wipe"
        private const val AT = "at"
        private const val STAGE = "stage"
        private const val DELETING = "deleting"
        private const val DONE = "done"
        private const val SEEN = "seen"
        private const val PENDING = "pending"
        private const val OURA = "oura"

        /** Αρχεία ρυθμίσεων που μένουν: το σημάδι και ο διακόπτης των αναφορών σφαλμάτων (ErrorQueue). */
        private val KEEP_PREFS = setOf("$MARKER.xml", "errors.xml")

        private fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences(MARKER, Context.MODE_PRIVATE)

        /** Πότε έγινε η τελευταία «Διαγραφή όλων» (0 = ποτέ). Αποτελέσματα του ρολογιού από πριν δεν μπαίνουν. */
        fun wipedAt(ctx: Context): Long = try {
            prefs(ctx).getLong(AT, 0L)
        } catch (_: Throwable) {
            0L
        }

        /** Διαγραφή που δεν τελείωσε: τίποτα στο παρασκήνιο ώσπου να τελειώσει (N2). */
        fun unfinished(ctx: Context): Boolean = try {
            prefs(ctx).getString(STAGE, null) == DELETING
        } catch (_: Throwable) {
            false
        }

        private fun begin(ctx: Context, at: Long, oura: String): Boolean = try {
            prefs(ctx).edit()
                .putLong(AT, at)
                .putString(STAGE, DELETING)
                .putBoolean(SEEN, false)
                .putBoolean(PENDING, true)
                .putString(OURA, oura)
                .commit()
        } catch (_: Throwable) {
            false
        }

        private fun status(ctx: Context): Map<String, Any>? {
            val p = prefs(ctx)
            val at = p.getLong(AT, 0L)
            if (at <= 0L) return null
            return mapOf(
                "at" to at,
                "stage" to (p.getString(STAGE, DONE) ?: DONE),
                "seen" to p.getBoolean(SEEN, true),
                "pending" to p.getBoolean(PENDING, false),
                "oura" to (p.getString(OURA, "none") ?: "none"),
            )
        }

        /**
         * Στην εκκίνηση (MainActivity.onCreate, πριν ξεκινήσει η Flutter): μια διαγραφή που ξεκίνησε τελειώνει εδώ. Αν
         * σβηστούν όλα, «done»· αλλιώς μένει «deleting» και η Flutter λέει «Η διαγραφή δεν τελείωσε».
         */
        fun finishIfNeeded(ctx: Context) {
            try {
                val p = prefs(ctx)
                if (p.getString(STAGE, null) != DELETING) return
                if (wipeLocal(ctx) == 0) p.edit().putString(STAGE, DONE).commit()
            } catch (_: Throwable) {
            }
        }

        /**
         * Σβήνει ό,τι έχει η εφαρμογή στη συσκευή: όλους τους φακέλους της (app_flutter με το φαγητό και τις
         * ρυθμίσεις, files με training.json/hr/run.json/καραντίνα/errq/widgets, βάσεις, ρυθμίσεις, cache, no_backup),
         * τους εξωτερικούς φακέλους της και τα κλειδιά της στο Keystore (tokens της Oura). Εκτός: [KEEP_PREFS], τα
         * αρχεία του WorkManager, «lib» και «code_cache» (κώδικας, όχι δεδομένα). Επιστρέφει πόσα δεν σβήστηκαν.
         */
        fun wipeLocal(ctx: Context): Int {
            var failed = 0
            fun del(f: File) {
                if (f.exists() && !f.deleteRecursively()) failed++
            }
            val root = File(ctx.applicationInfo.dataDir)
            for (top in root.listFiles() ?: emptyArray()) {
                when (top.name) {
                    "lib", "code_cache" -> {}
                    "shared_prefs" -> for (f in top.listFiles() ?: emptyArray()) {
                        if (f.name !in KEEP_PREFS && !f.name.startsWith("androidx.work")) del(f)
                    }
                    "databases", "no_backup" -> for (f in top.listFiles() ?: emptyArray()) {
                        if (!f.name.startsWith("androidx.work")) del(f)
                    }
                    else -> del(top)
                }
            }
            try {
                for (d in ctx.getExternalFilesDirs(null)) d?.listFiles()?.forEach { del(it) }
                ctx.externalCacheDir?.listFiles()?.forEach { del(it) }
            } catch (_: Throwable) {
            }
            try {
                val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                for (alias in ks.aliases().toList()) {
                    try {
                        ks.deleteEntry(alias)
                    } catch (_: Throwable) {
                        failed++
                    }
                }
            } catch (_: Throwable) {
            }
            return failed
        }

        /** Νέα εκκίνηση της εφαρμογής: τίποτα από τη μνήμη της Flutter δεν γράφεται ξανά. */
        private fun restart(activity: Activity) {
            try {
                activity.startActivity(
                    Intent(activity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
                )
            } catch (_: Throwable) {
            }
            Runtime.getRuntime().exit(0)
        }

        /** «/ygeia/wipe» προς το ρολόι. [deleteOld]: πρώτα σβήνονται όσα DataItems «/ygeia/…» ξέρει το κινητό. */
        private suspend fun sendWipe(ctx: Context, at: Long, deleteOld: Boolean) {
            try {
                val dc = Wearable.getDataClient(ctx)
                if (deleteOld) dc.deleteDataItems(Uri.Builder().scheme("wear").path("/ygeia/").build(), DataClient.FILTER_PREFIX).await()
                val req = PutDataMapRequest.create(WIPE).apply {
                    dataMap.putString(WearBridge.KEY, JSONObject().put("v", 1).put("at", at).toString())
                    dataMap.putLong("t", System.currentTimeMillis())
                }.asPutDataRequest().setUrgent()
                dc.putDataItem(req).await()
            } catch (_: Throwable) {
                // Χωρίς ρολόι ή Google Play services: ξαναδοκιμάζει στην επόμενη εκκίνηση (syncWatch).
            }
        }

        /**
         * Επιβεβαίωσε το ρολόι; Αν ναι: σβήνονται το «σβήσε» και η απάντηση (καμία επανάληψη μετά από επανεγκατάσταση
         * στο ρολόι) και το σημάδι γίνεται «όχι σε αναμονή». Αν όχι: το «σβήσε» ξαναμπαίνει, μόνο αν λείπει.
         * «acked» / «waiting».
         */
        suspend fun syncWatch(ctx: Context): String {
            val p = prefs(ctx)
            val at = p.getLong(AT, 0L)
            if (at <= 0L || !p.getBoolean(PENDING, false)) return "acked"
            return try {
                val dc = Wearable.getDataClient(ctx)
                var acked = false
                var present = false
                // N3: ό,τι «/ygeia/…» γράφτηκε πριν από τη διαγραφή (π.χ. το παλιό πρόγραμμα και όριο, αν το κινητό
                // έκλεισε πριν τα σβήσει) σβήνεται εδώ, όσο περιμένουμε το ρολόι.
                val stale = mutableListOf<Uri>()
                val buf = dc.dataItems.await()
                try {
                    for (item in buf) {
                        val path = item.uri.path ?: continue
                        if (path.startsWith("/ygeia/") && path != WIPE && path != WIPED) {
                            val t = try {
                                DataMapItem.fromDataItem(item).dataMap.getLong("t", 0L)
                            } catch (_: Throwable) {
                                0L
                            }
                            if (DataRules.writtenBeforeWipe(t, at)) stale.add(item.uri)
                        }
                        when (path) {
                            WIPE -> present = true
                            WIPED -> {
                                val text = try {
                                    DataMapItem.fromDataItem(item).dataMap.getString(WearBridge.KEY)
                                } catch (_: Throwable) {
                                    null
                                }
                                val got = try {
                                    if (text == null) 0L else JSONObject(text).optLong("at", 0L)
                                } catch (_: Throwable) {
                                    0L
                                }
                                if (got >= at) acked = true
                            }
                        }
                    }
                } finally {
                    buf.release()
                }
                for (u in stale) {
                    try {
                        dc.deleteDataItems(u).await()
                    } catch (_: Throwable) {
                    }
                }
                if (acked) {
                    dc.deleteDataItems(Uri.Builder().scheme("wear").path(WIPE).build()).await()
                    dc.deleteDataItems(Uri.Builder().scheme("wear").path(WIPED).build()).await()
                    p.edit().putBoolean(PENDING, false).commit()
                    "acked"
                } else {
                    if (!present) sendWipe(ctx, at, deleteOld = false)
                    "waiting"
                }
            } catch (_: Throwable) {
                "waiting"
            }
        }
    }
}
