package gr.ygeiaforma.ygeia_forma

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
