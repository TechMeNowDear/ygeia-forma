package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume

/**
 * Διατροφή: ημερολόγιο φαγητού και δικά μου τρόφιμα (τοπικά, SQLite),
 * σκανάρισμα barcode (Google code scanner: δεν χρειάζεται άδεια κάμερας)
 * και αναζήτηση προϊόντος στο Open Food Facts (ανοιχτή βάση, άδεια ODbL).
 * Κανάλι «ygeia/food». Τίποτα στο παρασκήνιο.
 */
class FoodBridge(
    private val activity: Activity,
    private val scope: CoroutineScope,
) : MethodChannel.MethodCallHandler {

    private val store by lazy { DayStore.get(activity.applicationContext) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "logRange" -> respondDb(result) {
                val from = call.argument<String>("from") ?: ""
                val to = call.argument<String>("to") ?: ""
                val rows = withContext(DbQueue.dispatcher) { store.logRange(from, to) }
                JSONObject().put("ok", true).put("entries", rows)
            }
            "logPut" -> respondDb(result) {
                val json = JSONObject(call.argument<String>("json") ?: "{}")
                val id = json.optString("id")
                val day = json.optString("day")
                require(id.isNotEmpty() && day.isNotEmpty()) { "Λείπει id ή day" }
                withContext(DbQueue.dispatcher) { store.logPut(id, day, json.toString()) }
                JSONObject().put("ok", true)
            }
            "logDelete" -> respondDb(result) {
                val id = call.argument<String>("id") ?: ""
                withContext(DbQueue.dispatcher) { store.logDelete(id) }
                JSONObject().put("ok", true)
            }
            "myFoods" -> respondDb(result) {
                val rows = withContext(DbQueue.dispatcher) { store.myFoods() }
                JSONObject().put("ok", true).put("foods", rows)
            }
            "myFoodPut" -> respondDb(result) {
                val json = JSONObject(call.argument<String>("json") ?: "{}")
                val id = json.optString("id")
                require(id.isNotEmpty()) { "Λείπει id" }
                withContext(DbQueue.dispatcher) { store.myFoodPut(id, json.toString()) }
                JSONObject().put("ok", true)
            }
            "myFoodDelete" -> respondDb(result) {
                withContext(DbQueue.dispatcher) { store.myFoodDelete(call.argument<String>("id") ?: "") }
                JSONObject().put("ok", true)
            }
            "saveBackup" -> respond(result) {
                val json = call.argument<String>("json") ?: ""
                val name = call.argument<String>("name") ?: "ygeia-antigrafo.json"
                require(json.isNotEmpty()) { "Κενό αντίγραφο" }
                val uri = withContext(Dispatchers.IO) { BackupFiles.save(activity, json, name) }
                val shown = withContext(Dispatchers.IO) { BackupFiles.displayName(activity, uri) } ?: name
                JSONObject().put("ok", true).put("uri", uri.toString()).put("name", shown)
            }
            "shareBackup" -> respondMain(result) {
                BackupFiles.share(activity, android.net.Uri.parse(call.argument<String>("uri") ?: ""))
                JSONObject().put("ok", true)
            }
            "pickBackup" -> respondMain(result) {
                val main = activity as? MainActivity ?: throw IllegalStateException("Δεν ανοίγει επιλογέας")
                val uri = suspendCancellableCoroutine<android.net.Uri?> { cont ->
                    main.pickDocument { u -> if (cont.isActive) cont.resume(u) }
                }
                if (uri == null) {
                    JSONObject().put("ok", false).put("kind", "cancelled").put("message", "Ακυρώθηκε")
                } else {
                    val text = withContext(Dispatchers.IO) { BackupFiles.read(activity, uri) }
                    JSONObject().put("ok", true).put("json", text)
                }
            }
            "scanBarcode" -> respondMain(result) { scan() }
            "offLookup" -> respond(result) {
                withContext(Dispatchers.IO) { offLookup(call.argument<String>("code") ?: "") }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Η δουλειά και η σειριοποίηση (π.χ. όλο το ημερολόγιο για το αντίγραφο) εκτός main thread (A9)· μόνο η απάντηση
     * στη Flutter στο main thread. Οι εργασίες στη βάση μία-μία ([DbQueue], A8).
     */
    private fun respond(result: MethodChannel.Result, block: suspend () -> JSONObject) {
        scope.launch {
            val text = withContext(Dispatchers.Default) { guarded(block).toString() }
            result.success(text)
        }
    }

    /** Έλεγχος 3, E6: εργασία της βάσης ΚΑΤΕΥΘΕΙΑΝ στη σειρά της ([DbQueue.run]), αυστηρά με τη σειρά των κλήσεων. */
    private fun respondDb(result: MethodChannel.Result, block: suspend () -> JSONObject) {
        DbQueue.run(scope, { result.success(it) }) { guarded(block).toString() }
    }

    /** Για ό,τι ανοίγει οθόνη (επιλογέας αρχείων, κοινοποίηση, σαρωτής): στο main thread. */
    private fun respondMain(result: MethodChannel.Result, block: suspend () -> JSONObject) {
        scope.launch { result.success(guarded(block).toString()) }
    }

    private suspend fun guarded(block: suspend () -> JSONObject): JSONObject =
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            ErrorQueue.report(e, "food")
            JSONObject().put("ok", false).put("kind", "other").put("message", e.message ?: e.javaClass.simpleName)
                .put("detail", e.stackTraceToString().lines().take(12).joinToString("\n"))
        }

    // ---------- Barcode ----------

    private suspend fun scan(): JSONObject = suspendCancellableCoroutine { cont ->
        // Το ML Kit αρχικοποιείται συνήθως μόνο του· το κάνουμε ρητά για σιγουριά.
        try {
            com.google.mlkit.common.sdkinternal.MlKitContext.initializeIfNeeded(activity.applicationContext)
        } catch (e: Throwable) {
            // αν έχει ήδη γίνει, απλώς συνεχίζουμε
        }
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(
                Barcode.FORMAT_EAN_13, Barcode.FORMAT_EAN_8, Barcode.FORMAT_UPC_A, Barcode.FORMAT_UPC_E,
            )
            .enableAutoZoom()
            .build()
        val scanner = try {
            GmsBarcodeScanning.getClient(activity, options)
        } catch (e: Throwable) {
            cont.resume(
                JSONObject().put("ok", false).put("kind", "other").put("message", e.message ?: e.javaClass.simpleName)
                    .put("detail", e.stackTraceToString().lines().take(12).joinToString("\n"))
            )
            return@suspendCancellableCoroutine
        }
        scanner.startScan()
            .addOnSuccessListener { b ->
                if (cont.isActive) cont.resume(JSONObject().put("ok", true).put("code", b.rawValue ?: ""))
            }
            .addOnCanceledListener {
                if (cont.isActive) cont.resume(JSONObject().put("ok", false).put("kind", "cancelled"))
            }
            .addOnFailureListener { e ->
                val kind = if (e is MlKitException && e.errorCode == MlKitException.UNAVAILABLE) "unavailable" else "other"
                if (kind == "other") ErrorQueue.report(e, "barcode")
                if (cont.isActive) cont.resume(
                    JSONObject().put("ok", false).put("kind", kind).put("message", e.message ?: "")
                        .put("detail", e.stackTraceToString().lines().take(12).joinToString("\n"))
                )
            }
    }

    // ---------- Open Food Facts ----------

    private fun offLookup(code: String): JSONObject {
        require(code.matches(Regex("^[0-9]{8,14}$"))) { "Μη έγκυρο barcode" }
        val fields = "code,product_name,product_name_el,generic_name_el,brands,quantity,serving_size," +
            "serving_quantity,nutriments,nutrition_data_per,lang"
        val url = URL("https://world.openfoodfacts.org/api/v2/product/$code.json?fields=$fields")
        val conn = url.openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 8000
            conn.readTimeout = 10000
            // Η τεκμηρίωση του Open Food Facts ζητά «AppName/Version (επικοινωνία)». Επικοινωνία = η σελίδα του έργου
            // (όχι προσωπικό email· έλεγχος 9/11, Μ5). Μένει το API v2: είναι «deprecated» αλλά υποστηρίζεται, ενώ το v3.5
            // άλλαξε τη μορφή των θρεπτικών και είναι ακόμα υπό ανάπτυξη (changelog του API).
            conn.setRequestProperty("User-Agent", "YgeiaForma/0.1 (+https://github.com/TechMeNowDear/ygeia-forma)")
            val status = conn.responseCode
            if (status == 404) return JSONObject().put("ok", true).put("found", false)
            if (status !in 200..299) {
                return JSONObject().put("ok", false).put("kind", "connection").put("message", "HTTP $status")
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val j = JSONObject(body)
            if (j.optInt("status", 0) != 1 || !j.has("product")) {
                return JSONObject().put("ok", true).put("found", false)
            }
            return JSONObject().put("ok", true).put("found", true).put("product", j.getJSONObject("product"))
        } catch (e: java.io.IOException) {
            return JSONObject().put("ok", false).put("kind", "connection").put("message", e.message ?: "")
        } finally {
            conn.disconnect()
        }
    }
}
