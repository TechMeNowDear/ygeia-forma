package gr.ygeiaforma.ygeia_forma

import android.content.Intent
import android.net.Uri
import android.os.Bundle
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

    // Σύνδεση Oura: η επιστροφή ygeiaforma://oura-callback φτάνει εδώ (singleTask: στην ίδια οθόνη).
    private var oura: OuraBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        takeOuraCallback(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeOuraCallback(intent)
    }

    private fun takeOuraCallback(i: Intent?) {
        if (!OuraBridge.isCallback(i)) return
        val uri = i?.dataString ?: return
        // Μία φορά: να μην ξαναδιαβαστεί αν η οθόνη ξαναφτιαχτεί (π.χ. περιστροφή).
        i.data = null
        val b = oura
        if (b != null) b.deliver(uri) else OuraBridge.pendingCallback = uri
    }

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
        oura = OuraBridge(this, scope, ouraChannel).also { ouraChannel.setMethodCallHandler(it) }
        // Ανανέωση κάθε 3 ώρες στο παρασκήνιο (δες RefreshWorker). Δεν αποτρέπει το άνοιγμα αν αποτύχει.
        try {
            RefreshWorker.schedule(this)
        } catch (e: Throwable) {
            ErrorQueue.report(e, "background")
        }
    }

    override fun onDestroy() {
        oura = null
        scope.cancel()
        super.onDestroy()
    }
}
