package gr.ygeiaforma.ygeia_forma

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.samsung.android.sdk.health.data.HealthDataService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalTime
import java.util.concurrent.TimeUnit

/**
 * Ανανέωση στο παρασκήνιο (απόφαση χρήστη 2/11): κάθε 3 ώρες διαβάζει τη Samsung Health και γράφει το
 * βοηθητικό αρχείο που δείχνει η εφαρμογή μόλις ανοίξει, ώστε τα δεδομένα να είναι ήδη φρέσκα.
 *
 * - Το πρόγραμμα το αποφασίζει το Android (WorkManager): μαζεύει τις εργασίες, δεν ξυπνά το κινητό
 *   για αυτή μόνο, και δεν τρέχει με χαμηλή μπαταρία. Τη νύχτα (00:00–06:00) δεν διαβάζει τίποτα.
 * - Γράφει **μόνο** το βοηθητικό αρχείο: το ιστορικό, οι ρυθμίσεις και το ημερολόγιο φαγητού αλλάζουν
 *   μόνο με την εφαρμογή ανοιχτή. Αν κάτι αποτύχει, απλώς δεν αλλάζει τίποτα.
 */
class RefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val hour = LocalTime.now().hour
        if (hour < 6) return Result.success()
        ErrorQueue.install(applicationContext) // χωρίς ανοιχτή εφαρμογή δεν έχει γίνει ακόμα
        // Πρόσφατη ανάγνωση (π.χ. η εφαρμογή ήταν ανοιχτή): δεν χρειάζεται άλλη.
        val cache = java.io.File(applicationContext.filesDir, SamsungHealthBridge.DASHBOARD_FILE)
        if (cache.exists() && System.currentTimeMillis() - cache.lastModified() < FRESH_MS) return Result.success()
        val started = System.currentTimeMillis()
        return try {
            val store = HealthDataService.getStore(applicationContext)
            val granted = store.getGrantedPermissions(SamsungHealthBridge.permissions)
            if (granted.isEmpty()) return Result.success()
            val names = granted.map { it.dataType.name }.toSet()
            val o = DashboardReader(store).read(names)
                .put("ok", true)
                .put("readAt", System.currentTimeMillis())
                .put("granted", granted.size)
                .put("total", SamsungHealthBridge.permissions.size)
                .put("background", true)
            // Αν η Samsung αρνήθηκε κάποιο είδος (π.χ. δεν επιτρέπει ανάγνωση στο παρασκήνιο), δεν γράφουμε
            // μισά δεδομένα πάνω στα καλά· το λέμε στο Sentry, μία φορά ανά έκδοση.
            val failed = o.keys().asSequence().filter { k -> (o.opt(k) as? org.json.JSONObject)?.has("error") == true }.toList()
            if (failed.isNotEmpty()) {
                reportOnce(IllegalStateException("Ανάγνωση στο παρασκήνιο: σφάλμα σε ${failed.joinToString()}"))
                return Result.success()
            }
            val text = withContext(Dispatchers.Default) { o.toString() }
            withContext(Dispatchers.IO) {
                // Η εφαρμογή έγραψε στο μεταξύ νεότερα δεδομένα: δεν τα πατάμε.
                if (!(cache.exists() && cache.lastModified() > started)) writeAtomically(SamsungHealthBridge.DASHBOARD_FILE, text)
            }
            Result.success()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Στο Sentry μία φορά ανά έκδοση, για να ξέρουμε αν η Samsung επιτρέπει την ανάγνωση στο παρασκήνιο.
            reportOnce(e)
            Result.success()
        }
    }

    private fun reportOnce(e: Throwable) {
        val version = try {
            applicationContext.packageManager.getPackageInfo(applicationContext.packageName, 0).versionName ?: "dev"
        } catch (_: Throwable) {
            "dev"
        }
        val mark = java.io.File(applicationContext.filesDir, "bg-reported")
        if (mark.exists() && mark.readText() == version) return
        mark.writeText(version)
        ErrorQueue.report(e, "background")
    }

    // Δικό του προσωρινό αρχείο, ώστε να μη συγκρούεται με την εφαρμογή· η μετονομασία είναι ατομική.
    private fun writeAtomically(name: String, text: String) {
        val dir = applicationContext.filesDir
        val tmp = java.io.File(dir, "$name.bg.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(java.io.File(dir, name))) tmp.delete()
    }

    companion object {
        private const val NAME = "ygeia-refresh"
        private const val FRESH_MS = 150 * 60 * 1000L // 2,5 ώρες

        /**
         * Καλείται όταν ανοίγει η εφαρμογή. UPDATE: κρατά το πρόγραμμα, αλλά παίρνει τις νέες ρυθμίσεις
         * αν αλλάξουν σε νεότερη έκδοση. Η πρώτη εκτέλεση μία ώρα μετά (όχι πάνω στο άνοιγμα).
         */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<RefreshWorker>(3, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
                .setInitialDelay(1, TimeUnit.HOURS)
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
