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
            "logRange" -> respond(result) {
                val from = call.argument<String>("from") ?: ""
                val to = call.argument<String>("to") ?: ""
                val rows = withContext(Dispatchers.IO) { store.logRange(from, to) }
                JSONObject().put("ok", true).put("entries", rows)
            }
            "logPut" -> respond(result) {
                val json = JSONObject(call.argument<String>("json") ?: "{}")
                val id = json.optString("id")
                val day = json.optString("day")
                require(id.isNotEmpty() && day.isNotEmpty()) { "Λείπει id ή day" }
                withContext(Dispatchers.IO) { store.logPut(id, day, json.toString()) }
                JSONObject().put("ok", true)
            }
            "logDelete" -> respond(result) {
                val id = call.argument<String>("id") ?: ""
                withContext(Dispatchers.IO) { store.logDelete(id) }
                JSONObject().put("ok", true)
            }
            "myFoods" -> respond(result) {
                val rows = withContext(Dispatchers.IO) { store.myFoods() }
                JSONObject().put("ok", true).put("foods", rows)
            }
            "myFoodPut" -> respond(result) {
                val json = JSONObject(call.argument<String>("json") ?: "{}")
                val id = json.optString("id")
                require(id.isNotEmpty()) { "Λείπει id" }
                withContext(Dispatchers.IO) { store.myFoodPut(id, json.toString()) }
                JSONObject().put("ok", true)
            }
            "myFoodDelete" -> respond(result) {
                withContext(Dispatchers.IO) { store.myFoodDelete(call.argument<String>("id") ?: "") }
                JSONObject().put("ok", true)
            }
            "scanBarcode" -> respond(result) { scan() }
            "offLookup" -> respond(result) {
                withContext(Dispatchers.IO) { offLookup(call.argument<String>("code") ?: "") }
            }
            else -> result.notImplemented()
        }
    }

    private fun respond(result: MethodChannel.Result, block: suspend () -> JSONObject) {
        scope.launch {
            val json = try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                JSONObject().put("ok", false).put("kind", "other").put("message", e.message ?: e.javaClass.simpleName)
                    .put("detail", e.stackTraceToString().lines().take(12).joinToString("\n"))
            }
            result.success(json.toString())
        }
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
            conn.setRequestProperty("User-Agent", "YgeiaForma/0.1 (Android; personal use)")
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
