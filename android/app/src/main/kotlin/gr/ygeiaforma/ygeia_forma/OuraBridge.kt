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
            "vaultLoad" -> io(result) { Vault.load(activity, call.argument<String>("name") ?: "") }
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
            "readNights" -> io(result) { readText(NIGHTS_FILE) }
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
        if (uri.scheme != "https" || !(uri.host ?: "").endsWith("ouraring.com")) return false
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
            channel.invokeMethod("callback", uri)
            pendingCallback = null
        } catch (_: Throwable) {
            // Η Flutter δεν είναι έτοιμη ακόμα: θα το πάρει με takeCallback.
        }
    }

    private fun readText(name: String): String? =
        File(activity.filesDir, name).let { if (it.exists()) it.readText() else null }

    private fun writeText(name: String, text: String): Boolean = atomicWrite(File(activity.filesDir, name), text.toByteArray(Charsets.UTF_8))

    companion object {
        const val NIGHTS_FILE = "oura_nights.json"
        const val SCHEME = "ygeiaforma"
        const val HOST = "oura-callback"

        @Volatile
        var pendingCallback: String? = null

        fun isCallback(intent: Intent?): Boolean {
            val d = intent?.data ?: return false
            return intent.action == Intent.ACTION_VIEW && d.scheme == SCHEME && d.host == HOST
        }

        fun atomicWrite(f: File, bytes: ByteArray): Boolean = try {
            f.parentFile?.mkdirs()
            val tmp = File(f.parentFile, "${f.name}.tmp")
            FileOutputStream(tmp).use { out ->
                out.write(bytes)
                out.flush()
                out.fd.sync()
            }
            tmp.renameTo(f)
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
    private val allowed = setOf("oura_tokens", "oura_pending")

    private fun file(context: Context, name: String): File {
        require(name in allowed) { "Άγνωστο όνομα" }
        return File(File(context.noBackupFilesDir, "oura"), "$name.bin")
    }

    @Synchronized
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
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

    @Synchronized
    fun load(context: Context, name: String): String? {
        val f = file(context, name)
        if (!f.exists()) return null
        return try {
            val b = f.readBytes()
            if (b.size < 1 + 12 + 16 || b[0] != VERSION) throw IllegalStateException("Άγνωστη μορφή")
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, b, 1, 12))
            String(c.doFinal(b, 13, b.size - 13), Charsets.UTF_8)
        } catch (e: Throwable) {
            // Δεν αποκρυπτογραφείται (άλλο κλειδί): χωρίς αξία πια. Σβήνεται, ώστε να ζητηθεί νέα σύνδεση.
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
    fun until(context: Context): java.time.LocalDate? = try {
        val f = File(context.filesDir, SamsungHealthBridge.PREFS_FILE)
        if (!f.exists()) {
            null
        } else {
            val v = org.json.JSONObject(f.readText()).optString("sleepUntil", "")
            if (v.length == 10) java.time.LocalDate.parse(v) else null
        }
    } catch (e: Throwable) {
        null
    }
}
