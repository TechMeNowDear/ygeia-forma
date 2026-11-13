package gr.ygeiaforma.ygeia_forma

import android.content.Intent
import android.os.Build
import android.os.Bundle
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

/**
 * Έλεγχος 13/11 (S10-1): τα extras που διαβάζει η Flutter από το Intent με το οποίο ανοίγει μια οθόνη της (διαδρομή,
 * έτοιμη μηχανή, σημείο εισόδου Dart, φόντο…· FlutterActivityLaunchConfigs). Η MainActivity και η WidgetConfigActivity
 * είναι «exported», άρα μια άλλη εφαρμογή του κινητού μπορούσε να ανοίξει την εφαρμογή στη ρύθμιση widget
 * («route» = «/widget»: καμία ανάγνωση, καμία σελίδα) ή να τη ρίξει στο άνοιγμα («cached_engine_id» που δεν υπάρχει).
 * Η εφαρμογή δεν χρησιμοποιεί κανένα από αυτά: σβήνονται από το Intent πριν τα δει η Flutter.
 */
object FlutterLaunchExtras {
    val NAMES = listOf(
        "route",
        "cached_engine_id",
        "cached_engine_group_id",
        "dart_entrypoint",
        "dart_entrypoint_args",
        "background_mode",
        "destroy_engine_with_activity",
        "enable_state_restoration",
    )
}

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

    override fun onCreate(savedInstanceState: Bundle?) {
        // «Διαγραφή όλων» που ξεκίνησε: τελειώνει εδώ, πριν ξεκινήσει η Flutter (έλεγχος του fix-accuracy, M4).
        DataWipe.finishIfNeeded(this)
        // S10-1: ό,τι extra της Flutter έβαλε άλλη εφαρμογή στο Intent φεύγει πριν το διαβάσει η Flutter.
        try {
            for (k in FlutterLaunchExtras.NAMES) intent?.removeExtra(k)
        } catch (_: Throwable) {
        }
        super.onCreate(savedInstanceState)
        // Τα δεδομένα υγείας δεν φαίνονται στη μικρογραφία των «πρόσφατων εφαρμογών» (Συμβούλιο 5, Δ5, έγκριση 13/11).
        // Μόνο εκεί: τα στιγμιότυπα οθόνης που παίρνει ο χρήστης συνεχίζουν να δουλεύουν (όχι FLAG_SECURE).
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
    }

    // S10-1: η κανονική εφαρμογή ανοίγει πάντα στην αρχική διαδρομή· η ρύθμιση widget («/widget») μόνο από τη δική της
    // οθόνη (WidgetConfigActivity), ποτέ από extra «route» άλλης εφαρμογής.
    override fun getInitialRoute(): String = "/"

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
        // «Διαγραφή όλων των δεδομένων» (Ρυθμίσεις › Τα δεδομένα μου), αντιγραφή ευαίσθητου, πολιτική απορρήτου.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/privacy")
            .setMethodCallHandler(DataWipe(this, scope))
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
            // N2: με διαγραφή που δεν τελείωσε, καμία ανανέωση στο παρασκήνιο (θα έγραφε αρχεία πριν το σβήσιμο).
            // Έλεγχος 13/11 (U4-6): ούτε όσο φαίνεται το «Όλα διαγράφηκαν»· ξεκινά όταν ο χρήστης φύγει από εκεί
            // (DataWipe, «wipeSeen»). Αλλιώς μία ώρα μετά τη διαγραφή το κινητό είχε ξανά δεδομένα του Samsung Health.
            if (!DataWipe.unfinished(this) && !DataWipe.awaitsStart(this)) RefreshWorker.schedule(this)
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
