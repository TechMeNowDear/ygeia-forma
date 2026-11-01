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
            val text = withContext(Dispatchers.Default) { o.toString() }
            withContext(Dispatchers.IO) { writeAtomically(SamsungHealthBridge.DASHBOARD_FILE, text) }
            Result.success()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Μία φορά ανά εκτέλεση στο Sentry, για να ξέρουμε αν η Samsung επιτρέπει την ανάγνωση στο παρασκήνιο.
            ErrorQueue.report(e, "background")
            Result.success()
        }
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

        /** Καλείται όταν ανοίγει η εφαρμογή. KEEP: δεν ξαναπρογραμματίζεται αν υπάρχει ήδη. */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<RefreshWorker>(3, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
