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
    // Ζει όσο ζει η οθόνη. Στο παρασκήνιο τρέχει μόνο η ανανέωση ανά 3 ώρες (RefreshWorker).
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // Επιλογέας αρχείου του συστήματος (για την επαναφορά αντιγράφου). Δηλώνεται πριν ανοίξει η οθόνη.
    private var pickCallback: ((Uri?) -> Unit)? = null
    private val documentPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val cb = pickCallback
        pickCallback = null
        cb?.invoke(uri)
    }

    // Σύνδεση Oura: η επιστροφή ygeiaforma://oura-callback την πιάνει η OuraCallbackActivity (όχι αυτή η οθόνη,
    // ώστε η MainActivity να μείνει όπως ήταν: launchMode, επιλογέας αρχείων, άδειες Samsung).
    private var oura: OuraBridge? = null

    fun pickDocument(callback: (Uri?) -> Unit) {
        pickCallback?.invoke(null) // προηγούμενη επιλογή που δεν ολοκληρώθηκε
        pickCallback = callback
        documentPicker.launch(arrayOf("application/json", "application/gzip", "application/x-gzip", "text/plain", "application/octet-stream"))
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
        val ouraChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/oura")
        oura = OuraBridge(this, scope, ouraChannel).also {
            ouraChannel.setMethodCallHandler(it)
            OuraBridge.live = it
        }
        // Ανανέωση κάθε 3 ώρες στο παρασκήνιο (δες RefreshWorker). Δεν αποτρέπει το άνοιγμα αν αποτύχει.
        try {
            RefreshWorker.schedule(this)
        } catch (e: Throwable) {
            ErrorQueue.report(e, "background")
        }
    }

    override fun onDestroy() {
        if (OuraBridge.live === oura) OuraBridge.live = null
        oura = null
        scope.cancel()
        super.onDestroy()
    }
}
