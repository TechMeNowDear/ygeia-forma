package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.UnrecoverableKeyException
import android.security.keystore.KeyPermanentlyInvalidatedException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Γέφυρα για τη σύνδεση με το Oura (κανάλι «ygeia/oura»), χωρίς βιβλιοθήκες.
 *
 * - Ανοίγει τη σελίδα σύνδεσης της Oura στον browser του κινητού (Intent.ACTION_VIEW, όχι WebView).
 * - Πιάνει την επιστροφή ygeiaforma://oura-callback (η MainActivity τη δίνει εδώ) και τη στέλνει στη Flutter.
 * - Κρατά τα tokens κρυπτογραφημένα (AES-GCM, κλειδί στο Android Keystore που δεν βγαίνει ποτέ από τη συσκευή),
 *   στον φάκελο noBackupFilesDir: το Android δεν τον βάζει ποτέ στο αντίγραφο ασφαλείας (Auto Backup), οπότε
 *   δεν υπάρχει επαναφορά σε άλλο κινητό με αρχεία που δεν αποκρυπτογραφούνται (το κλειδί δεν μεταφέρεται).
 * - Οι νύχτες του Oura (λεπτομέρειες για τις οθόνες) σε απλό αρχείο της εφαρμογής, όπως τα άλλα δεδομένα.
 * Ποτέ δεν γράφει tokens ή τιμές σε σφάλματα.
 */
class OuraBridge(
    private val activity: Activity,
    private val scope: CoroutineScope,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // {"v": κείμενο ή null} ή {"error": "transient"} (προσωρινό σφάλμα: τα αρχεία μένουν).
            "vaultLoad" -> scope.launch {
                val out = try {
                    val v = withContext(Dispatchers.IO) { Vault.load(activity, call.argument<String>("name") ?: "") }
                    org.json.JSONObject().put("v", v ?: org.json.JSONObject.NULL)
                } catch (e: Throwable) {
                    org.json.JSONObject().put("error", "transient")
                }
                result.success(out.toString())
            }
            "vaultSave" -> io(result) {
                Vault.save(activity, call.argument<String>("name") ?: "", call.argument<String>("value") ?: "")
            }
            "vaultDelete" -> io(result) {
                Vault.delete(activity, call.argument<String>("name") ?: "")
                true
            }
            "open" -> {
                val url = call.argument<String>("url") ?: ""
                result.success(openBrowser(url))
            }
            "takeCallback" -> {
                val uri = pendingCallback
                pendingCallback = null
                result.success(uri)
            }
            // Έλεγχος 3, E4: {"state": missing|ok|error, "json"} (όπως το readPlan). Πριν, ένα σφάλμα ανάγνωσης γύριζε
            // null, ίδιο με «δεν υπάρχει», και η επόμενη ανάγνωση της Oura έγραφε 3 νύχτες πάνω στις 45.
            "readNights" -> scope.launch {
                val out = withContext(Dispatchers.IO) {
                    val f = File(activity.filesDir, NIGHTS_FILE)
                    DataRules.nightsState(f.exists()) { f.readText() }
                }
                result.success(out)
            }
            // Στην εκκίνηση: προσωρινά αρχεία που έμειναν από εγγραφή που διακόπηκε (μόνο τα δικά μας).
            "cleanTmp" -> io(result) { cleanTmp(activity) }
            // Το σχέδιο πηγών (δικό του αρχείο, ανεξάρτητο από τις ρυθμίσεις): {"state": missing|ok|error, "json"}.
            "readPlan" -> scope.launch {
                val out = withContext(Dispatchers.IO) {
                    val f = File(activity.filesDir, planName(call.argument<String>("name")))
                    try {
                        if (!f.exists()) org.json.JSONObject().put("state", "missing")
                        else org.json.JSONObject().put("state", "ok").put("json", f.readText())
                    } catch (e: Throwable) {
                        org.json.JSONObject().put("state", "error")
                    }
                }
                result.success(out.toString())
            }
            "writePlan" -> io(result) { writeText(planName(call.argument<String>("name")), call.argument<String>("json") ?: "") }
            "writeNights" -> io(result) { writeText(NIGHTS_FILE, call.argument<String>("json") ?: "") }
            else -> result.notImplemented()
        }
    }

    private fun io(result: MethodChannel.Result, block: () -> Any?) {
        scope.launch {
            val v = try {
                withContext(Dispatchers.IO) { block() }
            } catch (e: Throwable) {
                ErrorQueue.report(e, "oura")
                null
            }
            result.success(v)
        }
    }

    /** Μόνο https στην Oura: τίποτα άλλο δεν ανοίγει από εδώ. */
    private fun openBrowser(url: String): Boolean {
        val uri = Uri.parse(url)
        if (uri.scheme != "https" || uri.host !in ALLOWED_HOSTS) return false
        return try {
            val i = Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
            activity.startActivity(i)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** Η επιστροφή από την Oura: στη Flutter αμέσως, ή κρατιέται ώσπου να τη ζητήσει (takeCallback). */
    fun deliver(uri: String) {
        pendingCallback = uri
        try {
            // Έλεγχος 2, C14 (R12): σβήνεται ΜΟΝΟ αν η Flutter το δέχτηκε. Χωρίς χειριστή ακόμα (η εφαρμογή ξεκινά),
            // μένει για το takeCallback· πριν χανόταν, γιατί το invokeMethod χωρίς απάντηση δεν πετά ποτέ σφάλμα.
            channel.invokeMethod("callback", uri, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (DataRules.callbackDelivered("success") && pendingCallback == uri) pendingCallback = null
                }

                override fun error(code: String, message: String?, details: Any?) {}

                override fun notImplemented() {}
            })
        } catch (_: Throwable) {
            // Η Flutter δεν είναι έτοιμη ακόμα: θα το πάρει με takeCallback.
        }
    }

    private fun readText(name: String): String? =
        File(activity.filesDir, name).let { if (it.exists()) it.readText() else null }

    private fun writeText(name: String, text: String): Boolean = atomicWrite(File(activity.filesDir, name), text.toByteArray(Charsets.UTF_8))

    companion object {
        const val NIGHTS_FILE = OuraRules.NIGHTS_FILE
        const val PLAN_FILE = OuraRules.PLAN_FILE

        /** Ημερολόγιο αλλαγών πηγής (για επαναφορά αν χαλάσει το sources.json). */
        const val PLAN_LOG_FILE = OuraRules.PLAN_LOG_FILE

        /** Μόνο τα δύο αρχεία του σχεδίου πηγών. */
        fun planName(n: String?): String = if (n == PLAN_LOG_FILE) PLAN_LOG_FILE else PLAN_FILE
        const val SCHEME = OuraRules.SCHEME
        const val HOST = OuraRules.HOST

        /** Μόνο οι σελίδες σύνδεσης της Oura ανοίγουν από εδώ (ακριβές όνομα, όχι «τελειώνει σε»). */
        /** Μόνο οι σελίδες της Oura (DataRules.ALLOWED_HOSTS): νέα σελίδα σύνδεσης, κλασική, v2. */
        val ALLOWED_HOSTS = DataRules.ALLOWED_HOSTS

        @Volatile
        var pendingCallback: String? = null

        /** Η γέφυρα της οθόνης που ζει τώρα (αν η εφαρμογή είναι ανοιχτή). */
        @Volatile
        var live: OuraBridge? = null

        /** Από την OuraCallbackActivity: κρατιέται και δίνεται στη Flutter αν είναι ανοιχτή. */
        fun receive(uri: String) {
            pendingCallback = uri
            live?.deliver(uri)
        }

        /** App Link (https) της επιστροφής: μόνο αυτός ο ακριβής host και η διαδρομή. */
        const val HTTPS_HOST = OuraRules.HTTPS_HOST
        const val HTTPS_PATH = OuraRules.HTTPS_PATH

        /** Μόνο οι δύο ακριβείς μορφές: https://ygeia-forma.netlify.app/oura/callback ή ygeiaforma://oura-callback. */
        fun isCallback(intent: Intent?): Boolean {
            val d = intent?.data ?: return false
            if (intent.action != Intent.ACTION_VIEW) return false
            return OuraRules.isCallback(d.scheme, d.host, d.port, d.path, d.userInfo)
        }

        /**
         * Σβήνει μόνο προσωρινά αρχεία των δικών μας εγγραφών (filesDir και noBackupFilesDir/oura), παλιότερα από
         * ένα λεπτό. Ίδιο κλείδωμα με την [atomicWrite]: ποτέ το προσωρινό μιας εγγραφής που τρέχει.
         */
        @Synchronized
        fun cleanTmp(context: Context): Int {
            val cutoff = System.currentTimeMillis() - 60_000
            var n = 0
            for (dir in listOf(context.filesDir, File(context.noBackupFilesDir, "oura"))) {
                val files = dir.listFiles() ?: continue
                for (f in files) {
                    val name = f.name
                    if (!f.isFile || !OuraRules.isOwnTmp(name) || f.lastModified() > cutoff) continue
                    if (f.delete()) n++
                }
            }
            return n
        }

        /** Μία εγγραφή τη φορά (κλείδωμα) και μοναδικό προσωρινό αρχείο: δύο εγγραφές δεν μπλέκονται ποτέ. */
        @Synchronized
        fun atomicWrite(f: File, bytes: ByteArray): Boolean = try {
            f.parentFile?.mkdirs()
            val tmp = File(f.parentFile, "${f.name}.${System.nanoTime()}.tmp")
            FileOutputStream(tmp).use { out ->
                out.write(bytes)
                out.flush()
                out.fd.sync()
            }
            val ok = tmp.renameTo(f)
            if (!ok) tmp.delete()
            ok
        } catch (e: Throwable) {
            false
        }
    }
}

/**
 * Κρυπτογραφημένη αποθήκευση μικρών κειμένων (tokens). Μορφή αρχείου: [1 byte έκδοση][12 bytes IV][κρυπτογράφημα+tag].
 * Αν το κλειδί λείπει ή άλλαξε (π.χ. επαναφορά κινητού), το αρχείο σβήνεται και επιστρέφεται null: η εφαρμογή
 * τότε ζητά νέα σύνδεση, χωρίς να χαθεί κανένα άλλο δεδομένο.
 */
object Vault {
    private const val ALIAS = "ygeia_oura_v1"
    private const val VERSION: Byte = 1
    private val allowed = OuraRules.VAULT_NAMES

    private fun file(context: Context, name: String): File {
        require(name in allowed) { "Άγνωστο όνομα" }
        return File(File(context.noBackupFilesDir, "oura"), "$name.bin")
    }

    @Synchronized
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        try {
            (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        } catch (e: Throwable) {
            // Έλεγχος 2, C14 (R14): κλειδί που δεν ανακτάται πια (π.χ. μετά από αλλαγή κλειδώματος): νέο κλειδί, αλλιώς
            // κάθε νέα σύνδεση θα αποτύγχανε για πάντα. Τα παλιά tokens δεν διαβάζονται ούτως ή άλλως (νέα σύνδεση).
            if (!DataRules.regenerateKeyOn(e)) throw e
            try {
                ks.deleteEntry(ALIAS)
            } catch (_: Throwable) {
            }
        }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    @Synchronized
    fun save(context: Context, name: String, value: String): Boolean {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        val iv = c.iv
        val ct = c.doFinal(value.toByteArray(Charsets.UTF_8))
        val out = ByteArray(1 + iv.size + ct.size)
        out[0] = VERSION
        System.arraycopy(iv, 0, out, 1, iv.size)
        System.arraycopy(ct, 0, out, 1 + iv.size, ct.size)
        return OuraBridge.atomicWrite(file(context, name), out)
    }

    /**
     * null = δεν υπάρχει, ή δεν αποκρυπτογραφείται ΠΟΤΕ πια (άλλο ή χαμένο κλειδί, χαλασμένη μορφή): τότε
     * σβήνεται, ώστε να ζητηθεί νέα σύνδεση. Κάθε άλλο (προσωρινό) σφάλμα πετιέται και το αρχείο ΜΕΝΕΙ.
     */
    @Synchronized
    fun load(context: Context, name: String): String? {
        val f = file(context, name)
        if (!f.exists()) return null
        val b = f.readBytes()
        if (b.size < 1 + 12 + 16 || b[0] != VERSION) {
            f.delete()
            return null
        }
        return try {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, b, 1, 12))
            String(c.doFinal(b, 13, b.size - 13), Charsets.UTF_8)
        } catch (e: AEADBadTagException) {
            f.delete()
            null
        } catch (e: KeyPermanentlyInvalidatedException) {
            f.delete()
            null
        } catch (e: UnrecoverableKeyException) {
            f.delete()
            null
        }
    }

    @Synchronized
    fun delete(context: Context, name: String) {
        val f = file(context, name)
        if (f.exists()) f.delete()
    }
}

/**
 * Ως ποια νύχτα διαβάζεται ο ύπνος του ρολογιού από τη Samsung. Το γράφει η Flutter στις ρυθμίσεις
 * («sleepUntil», από το σχέδιο πηγών στο sources.dart) και το διαβάζουν η ανάγνωση και ο RefreshWorker.
 * Χωρίς ρύθμιση: χωρίς όριο (όπως πριν από το Oura).
 */
object SleepPolicy {
    /**
     * Από το αρχείο του σχεδίου πηγών («sources.json», το γράφει η Flutter πριν από κάθε ανάγνωση):
     * - δεν υπάρχει → χωρίς όριο (όπως πριν από το Oura),
     * - υπάρχει αλλά δεν διαβάζεται → καθόλου ύπνος ρολογιού (ποτέ σιωπηλά ύπνος ρολογιού για νύχτες του Oura), και
     *   ο ύπνος γυρίζει ως σφάλμα, όχι ως «καθόλου ύπνος» (A15).
     */
    fun limit(context: Context): DataRules.SleepLimit {
        val f = File(context.filesDir, OuraBridge.PLAN_FILE)
        return DataRules.sleepLimit(f.exists(), { f.readText() }) { org.json.JSONObject(it).optString("sleepUntil", "") }
    }

    /** Η ανάγνωση της Samsung με το όριο ύπνου του σχεδίου πηγών (και «σφάλμα» αν το αρχείο δεν διαβάζεται). */
    fun reader(
        context: Context,
        store: com.samsung.android.sdk.health.data.HealthDataStore,
        heartDays: Int = DashboardReader.DAYS,
        bodyDays: Long = 3653,
    ): DashboardReader {
        val l = limit(context)
        return DashboardReader(store, l.until, spo2Series(context), l.error, heartDays, bodyDays)
    }

    /** Αναλυτικές μετρήσεις οξυγόνου (λεπτά κάτω από 90%) μόνο μετά από σύνδεση Oura. */
    fun spo2Series(context: Context): Boolean = try {
        val f = File(context.filesDir, OuraBridge.PLAN_FILE)
        f.exists() && org.json.JSONObject(f.readText()).optBoolean("spo2Series", false)
    } catch (e: Throwable) {
        false
    }
}
