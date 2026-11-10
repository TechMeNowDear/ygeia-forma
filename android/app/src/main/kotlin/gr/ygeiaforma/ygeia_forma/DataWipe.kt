package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.os.Build
import android.os.PersistableBundle
import android.content.Intent
import android.net.Uri
import androidx.work.WorkManager
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

/**
 * «Διαγραφή όλων των δεδομένων» (Ρυθμίσεις › Τα δεδομένα μου· έλεγχος 9/11, E3-05 / V-A-23, ΓΚΠΔ άρθρο 17).
 *
 * Η Flutter έχει ήδη κάνει ό,τι θέλει δίκτυο (ανάκληση της Oura) και έχει πάρει δύο επιβεβαιώσεις. Εδώ:
 * 1. Ρολόι: σβήνονται ΟΛΑ τα DataItems «/ygeia/…» (πρόγραμμα, όριο, αποτελέσματα σε αναμονή, κατάσταση) και μπαίνει
 *    το «/ygeia/wipe» {"at"}· η εφαρμογή του ρολογιού σβήνει τα δικά της αρχεία όταν το δει (Link.wipe).
 * 2. Τα widgets ξαναζωγραφίζονται χωρίς τιμές ([HomeWidgets.wipe]), σταματά η ανανέωση στο παρασκήνιο.
 * 3. [ActivityManager.clearApplicationUserData]: το ίδιο με «Ρυθμίσεις Android › Εφαρμογές › Αποθηκευτικός χώρος ›
 *    Διαγραφή δεδομένων». Σβήνει ΟΛΑ τα αρχεία της εφαρμογής (training.json, hr/, βάσεις, ρυθμίσεις, κλειδιά του
 *    Keystore με τα tokens της Oura, cache, no_backup) και κλείνει την εφαρμογή.
 * Ό,τι δεν είναι εδώ (Samsung Health, Oura, Λήψεις, αντίγραφο Google) δεν σβήνεται: το λέει η οθόνη.
 */
class DataWipe(private val activity: Activity, private val scope: CoroutineScope) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "wipe" -> scope.launch {
                withTimeoutOrNull(8_000) { watch() }
                try {
                    HomeWidgets.wipe(activity)
                } catch (_: Throwable) {}
                try {
                    WorkManager.getInstance(activity).cancelAllWork()
                } catch (_: Throwable) {}
                val ok = try {
                    activity.getSystemService(ActivityManager::class.java)?.clearApplicationUserData() ?: false
                } catch (_: Throwable) {
                    false
                }
                // Με επιτυχία η εφαρμογή κλείνει από το σύστημα· η απάντηση ίσως δεν φτάσει ποτέ.
                result.success(ok)
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

    private suspend fun watch() {
        try {
            val dc = Wearable.getDataClient(activity)
            dc.deleteDataItems(Uri.Builder().scheme("wear").path("/ygeia/").build(), DataClient.FILTER_PREFIX).await()
            val req = PutDataMapRequest.create("/ygeia/wipe").apply {
                dataMap.putString(WearBridge.KEY, JSONObject().put("v", 1).put("at", System.currentTimeMillis()).toString())
                dataMap.putLong("t", System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
            dc.putDataItem(req).await()
        } catch (_: Throwable) {
            // Χωρίς ρολόι ή Google Play services: τίποτα να σβηστεί εκεί.
        }
    }

    companion object {
        const val POLICY = "https://ygeia-forma.netlify.app/privacy/"
    }
}
