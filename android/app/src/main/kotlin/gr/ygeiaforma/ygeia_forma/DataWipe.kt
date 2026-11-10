package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import android.app.ActivityManager
import androidx.work.WorkManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * «Διαγραφή όλων των δεδομένων» (Ρυθμίσεις › Απόρρητο· έλεγχος 9/11, E3-05 / V-A-23, ΓΚΠΔ άρθρο 17).
 *
 * Η Flutter έχει ήδη κάνει ό,τι θέλει δίκτυο (ανάκληση της Oura) και έχει πάρει δύο επιβεβαιώσεις. Εδώ:
 * 1. τα widgets ξαναζωγραφίζονται χωρίς τιμές ([HomeWidgets.wipe]),
 * 2. σταματά η ανανέωση στο παρασκήνιο,
 * 3. [ActivityManager.clearApplicationUserData]: το ίδιο με «Ρυθμίσεις Android › Εφαρμογές › Αποθηκευτικός χώρος ›
 *    Διαγραφή δεδομένων». Σβήνει ΟΛΑ τα αρχεία της εφαρμογής (files, και όσα προστεθούν, π.χ. hr/), βάσεις, ρυθμίσεις,
 *    κλειδιά του Keystore (tokens Oura), cache και no_backup, και κλείνει την εφαρμογή.
 * Ό,τι δεν είναι στο κινητό (Samsung Health, Oura, Λήψεις, αντίγραφο Google, ρολόι) δεν σβήνεται: το λέει η οθόνη.
 */
class DataWipe(private val activity: Activity) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "wipe" -> {
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
            else -> result.notImplemented()
        }
    }
}
