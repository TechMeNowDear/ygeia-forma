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
        // Round 7 (R7-A9 ΒΕΛΤΙΩΣΗ, f4): μετά από «Διαγραφή όλων» τίποτα δεν διαβάζεται ώσπου ο χρήστης να ξεκινήσει ξανά, ακόμα
        // κι αν η ακύρωση των εργασιών (DataWipe, cancelAllWork) δεν πρόλαβε να γραφτεί πριν κλείσει η εφαρμογή.
        if (DataWipe.unfinished(applicationContext) || DataWipe.awaitsStart(applicationContext)) return Result.success()
        ErrorQueue.install(applicationContext) // χωρίς ανοιχτή εφαρμογή δεν έχει γίνει ακόμα
        // Πρόσφατη ανάγνωση (π.χ. η εφαρμογή ήταν ανοιχτή): δεν χρειάζεται άλλη.
        val cache = java.io.File(applicationContext.filesDir, SamsungHealthBridge.DASHBOARD_FILE)
        if (cache.exists() && System.currentTimeMillis() - cache.lastModified() < FRESH_MS) return Result.success()
        // Η Samsung αρνήθηκε 3 φορές στη σειρά: παύση για μία μέρα (μπαταρία), όχι για πάντα (έλεγχος 8/11, DATA-07).
        // Το άνοιγμα της εφαρμογής μηδενίζει τον μετρητή (schedule).
        if (failures() >= MAX_FAILURES && System.currentTimeMillis() - failFile().lastModified() < PAUSE_MS) return Result.success()
        val started = System.currentTimeMillis()
        return try {
            val store = HealthDataService.getStore(applicationContext)
            val granted = store.getGrantedPermissions(SamsungHealthBridge.permissions)
            if (granted.isEmpty()) return Result.success()
            val names = granted.map { it.dataType.name }.toSet()
            // Μόνο ό,τι χρειάζεται η πρώτη οθόνη (A12, μπαταρία): παλμοί 7 ημερών. Το ιστορικό γράφεται μόνο από την πλήρη
            // ανάγνωση της εφαρμογής, ποτέ από αυτό το αρχείο.
            // Round 1 (S1-10 / S3-5): ΟΛΕΣ οι ζυγίσεις, όπως η εφαρμογή (πριν: 30 μέρες). Είναι λίγες εγγραφές (μία-δύο
            // σελίδες), ενώ με 30 μέρες ο έλεγχος θερμίδων (παράθυρο ως 42 μέρες + 1 εβδομάδα) και η οθόνη «Σώμα»
            // έβγαιναν, ώσπου να έρθει η πλήρης ανάγνωση, από μέρος των ζυγίσεων. Το «background» το λέει στη Flutter.
            // Round 7 (R7-A10-4): το «readAt» είναι του DashboardReader (η αρχή της ανάγνωσης): μια εκτέλεση που αρχίζει
            // 23:59 και τελειώνει μετά τα μεσάνυχτα δεν δείχνει τα χθεσινά σύνολα ως σημερινά.
            val o = SleepPolicy.reader(applicationContext, store, heartDays = 7).read(names)
                .put("ok", true)
                .put("granted", granted.size)
                .put("total", SamsungHealthBridge.permissions.size)
                .put("background", true)
            // Αν η Samsung αρνήθηκε κάποιο είδος (π.χ. δεν επιτρέπει ανάγνωση στο παρασκήνιο), δεν γράφουμε
            // μισά δεδομένα πάνω στα καλά· το λέμε στο Sentry, μία φορά ανά έκδοση.
            val failed = o.keys().asSequence().filter { k -> (o.opt(k) as? org.json.JSONObject)?.has("error") == true }.toList()
            if (failed.isNotEmpty()) {
                fail(IllegalStateException("Ανάγνωση στο παρασκήνιο: σφάλμα σε ${failed.joinToString()}"))
                return Result.success()
            }
            val text = withContext(Dispatchers.Default) { o.toString() }
            withContext(Dispatchers.IO) {
                // Η εφαρμογή έγραψε στο μεταξύ νεότερα δεδομένα: δεν τα πατάμε.
                if (!(cache.exists() && cache.lastModified() > started)) {
                    writeAtomically(SamsungHealthBridge.DASHBOARD_FILE, text)
                    // Widgets (7/11): η Κίνηση της μέρας από τη νέα ανάγνωση· αν αποτύχει, δεν πειράζει τίποτα άλλο.
                    try {
                        HomeWidgets.refreshMoveFromDashboard(applicationContext, o)
                    } catch (e: Throwable) {
                        ErrorQueue.report(e, "widget")
                    }
                }
                failFile().delete()
            }
            Result.success()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Στο Sentry μία φορά ανά έκδοση, για να ξέρουμε αν η Samsung επιτρέπει την ανάγνωση στο παρασκήνιο.
            fail(e)
            Result.success()
        }
    }

    private fun version(): String = try {
        applicationContext.packageManager.getPackageInfo(applicationContext.packageName, 0).versionName ?: "dev"
    } catch (_: Throwable) {
        "dev"
    }

    // «έκδοση:αποτυχίες στη σειρά». Νέα έκδοση = ξανά από το μηδέν.
    private fun failFile() = java.io.File(applicationContext.filesDir, "bg-failures")

    private fun failures(): Int = try {
        val parts = failFile().readText().split(':')
        if (parts.size == 2 && parts[0] == version()) parts[1].toInt() else 0
    } catch (_: Throwable) {
        0
    }

    /** Μετρά την αποτυχία· στο Sentry μόνο η πρώτη της έκδοσης. */
    private fun fail(e: Throwable) {
        val n = failures() + 1
        try {
            failFile().writeText("${version()}:$n")
        } catch (_: Throwable) {
        }
        if (n == 1) ErrorQueue.report(e, "background")
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
        private const val MAX_FAILURES = 3
        private const val PAUSE_MS = 24 * 60 * 60 * 1000L

        /**
         * Καλείται όταν ανοίγει η εφαρμογή. UPDATE: κρατά το πρόγραμμα, αλλά παίρνει τις νέες ρυθμίσεις
         * αν αλλάξουν σε νεότερη έκδοση. Η πρώτη εκτέλεση μία ώρα μετά (όχι πάνω στο άνοιγμα).
         */
        fun schedule(context: Context) {
            // Η εφαρμογή άνοιξε: ό,τι απέτυχε στο παρασκήνιο ξαναδοκιμάζεται από την αρχή.
            try {
                java.io.File(context.filesDir, "bg-failures").delete()
            } catch (_: Throwable) {
            }
            val request = PeriodicWorkRequestBuilder<RefreshWorker>(3, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
                .setInitialDelay(1, TimeUnit.HOURS)
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
