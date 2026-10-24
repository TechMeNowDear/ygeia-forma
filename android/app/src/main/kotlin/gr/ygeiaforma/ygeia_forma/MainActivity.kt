package gr.ygeiaforma.ygeia_forma

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class MainActivity : FlutterActivity() {
    // Ζει όσο ζει η οθόνη· τίποτα δεν τρέχει στο παρασκήνιο.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/samsung")
            .setMethodCallHandler(SamsungHealthBridge(this, scope))
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
