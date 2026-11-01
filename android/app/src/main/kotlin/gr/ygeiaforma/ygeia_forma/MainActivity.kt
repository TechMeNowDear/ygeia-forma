package gr.ygeiaforma.ygeia_forma

import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

// FragmentActivity: το χρειάζονται υπηρεσίες της Google (π.χ. σαρωτής barcode) για να ανοίγουν τις δικές τους οθόνες.
class MainActivity : FlutterFragmentActivity() {
    // Ζει όσο ζει η οθόνη· τίποτα δεν τρέχει στο παρασκήνιο.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // Επιλογέας αρχείου του συστήματος (για την επαναφορά αντιγράφου). Δηλώνεται πριν ανοίξει η οθόνη.
    private var pickCallback: ((Uri?) -> Unit)? = null
    private val documentPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val cb = pickCallback
        pickCallback = null
        cb?.invoke(uri)
    }

    fun pickDocument(callback: (Uri?) -> Unit) {
        pickCallback?.invoke(null) // προηγούμενη επιλογή που δεν ολοκληρώθηκε
        pickCallback = callback
        documentPicker.launch(arrayOf("application/json", "text/plain", "application/octet-stream"))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Σφάλματα για το Sentry: μόνο γράφει σε αρχείο όταν κάτι χαλάσει· τα στέλνει η Flutter.
        ErrorQueue.install(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/errors")
            .setMethodCallHandler(ErrorQueue)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/samsung")
            .setMethodCallHandler(SamsungHealthBridge(this, scope))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/food")
            .setMethodCallHandler(FoodBridge(this, scope))
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
