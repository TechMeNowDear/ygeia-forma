package gr.ygeiaforma.ygeia_forma

import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
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

    // Widgets (7/11): κανάλι για το στιγμιότυπο και για τα πατήματα σε widget.
    private var widgets: MethodChannel? = null

    private var wear: WearBridge? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Μόνο η μορφή των widgets (E3-24): ό,τι άλλο στείλει άλλη εφαρμογή αγνοείται.
        val target = DataRules.widgetOpenTarget(intent.getStringExtra(HomeWidgets.EXTRA_OPEN)) ?: return
        val ch = widgets
        if (ch != null) ch.invokeMethod("open", target) else HomeWidgets.pendingOpen = target
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DataRules.widgetOpenTarget(intent?.getStringExtra(HomeWidgets.EXTRA_OPEN))?.let { HomeWidgets.pendingOpen = it }
        widgets = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/widgets").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "count" -> result.success(try { HomeWidgets.count(this) } catch (_: Throwable) { 0 })
                    "update" -> {
                        val text = call.arguments as? String
                        try {
                            if (text != null) HomeWidgets.saveSnapshot(this, text)
                            result.success(true)
                        } catch (e: Throwable) {
                            ErrorQueue.report(e, "widget")
                            result.success(false)
                        }
                    }
                    "takeOpen" -> {
                        val o = HomeWidgets.pendingOpen
                        HomeWidgets.pendingOpen = null
                        result.success(o)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Σφάλματα για το Sentry: μόνο γράφει σε αρχείο όταν κάτι χαλάσει· τα στέλνει η Flutter.
        ErrorQueue.install(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/errors")
            .setMethodCallHandler(ErrorQueue)
        // «Διαγραφή όλων των δεδομένων» (Ρυθμίσεις › Απόρρητο).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/privacy")
            .setMethodCallHandler(DataWipe(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/samsung")
            .setMethodCallHandler(SamsungHealthBridge(this, scope))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/food")
            .setMethodCallHandler(FoodBridge(this, scope))
        // Προπόνηση (8/11): αρχείο προπονήσεων, οθόνη αναμμένη, διάλειμμα με ειδοποίηση.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/training")
            .setMethodCallHandler(TrainingBridge(this, scope))
        // Ρολόι (8/11): πρόγραμμα και προπόνηση προς το ρολόι, παλμοί και ✓ από εκεί, όσο ζει η εφαρμογή.
        wear = WearBridge(this, scope).also { w ->
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/wear").setMethodCallHandler(w)
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/wear/events").setStreamHandler(w)
        }
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
        widgets = null
        wear?.dispose()
        wear = null
        if (OuraBridge.live === oura) OuraBridge.live = null
        oura = null
        scope.cancel()
        super.onDestroy()
    }
}
