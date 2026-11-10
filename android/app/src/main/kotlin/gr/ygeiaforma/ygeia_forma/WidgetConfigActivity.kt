package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * Η οθόνη ρύθμισης widget (7/11): ανοίγει όταν βάζεις widget στην αρχική οθόνη και με παρατεταμένο πάτημα › Ρυθμίσεις.
 * Τρέχει τη Flutter στη διαδρομή «/widget» (lib/pages/widget_config_page.dart), χωρίς να φορτώσει δεδομένα.
 *
 * Για τον έλεγχο στο emulator (check.yml): με «ygeia_kind» και χωρίς widget ανοίγει μόνο ως προεπισκόπηση.
 */
class WidgetConfigActivity : FlutterFragmentActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        widgetId = intent?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Αν κλείσει χωρίς «Προσθήκη», η αρχική οθόνη δεν βάζει το widget.
        setResult(Activity.RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        super.onCreate(savedInstanceState)
    }

    override fun getInitialRoute(): String = "/widget"

    private fun kind(): String =
        (if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) HomeWidgets.kindOf(this, widgetId) else null)
            ?: intent?.getStringExtra("ygeia_kind")?.takeIf { it in setOf("sleep", "move", "food", "body") }
            ?: "sleep"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ErrorQueue.install(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/errors").setMethodCallHandler(ErrorQueue)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ygeia/widgets").setMethodCallHandler { call, result ->
            when (call.method) {
                "target" -> {
                    val valid = widgetId != AppWidgetManager.INVALID_APPWIDGET_ID
                    val k = kind()
                    val size = if (valid) HomeWidgets.sizeOf(this, widgetId) else null
                    // Extras μόνο με λογικές τιμές (E3-24): όχι bitmap χιλιάδων dp από πλαστό intent.
                    val w = size?.width?.toDouble() ?: DataRules.previewDp(intent?.getIntExtra("ygeia_w", 0) ?: 0)
                    val h = size?.height?.toDouble() ?: DataRules.previewDp(intent?.getIntExtra("ygeia_h", 0) ?: 0)
                    result.success(
                        mapOf(
                            "id" to (if (valid) widgetId else 0),
                            "kind" to k,
                            "w" to w,
                            "h" to h,
                            "style" to (if (valid) HomeWidgets.styleJson(this, widgetId) else null),
                            "hasData" to HomeWidgets.hasData(this, k),
                        )
                    )
                }
                "render" -> {
                    val args = call.arguments as? Map<*, *>
                    val style = try {
                        JSONObject(args?.get("style") as? String ?: "{}")
                    } catch (_: Throwable) {
                        JSONObject()
                    }
                    val w = (args?.get("w") as? Number)?.toFloat() ?: 180f
                    val h = (args?.get("h") as? Number)?.toFloat() ?: 190f
                    val dark = args?.get("dark") == true
                    val k = style.optString("kind", kind())
                    scope.launch {
                        val png = try {
                            withContext(Dispatchers.Default) {
                                val data = if (HomeWidgets.hasData(this@WidgetConfigActivity, k)) {
                                    HomeWidgets.kindData(this@WidgetConfigActivity, k)
                                } else {
                                    WidgetRenderer.sample(k)
                                }
                                val bmp = WidgetRenderer.render(this@WidgetConfigActivity, k, style, data, w, h, dark)
                                val out = ByteArrayOutputStream()
                                bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                                bmp.recycle()
                                out.toByteArray()
                            }
                        } catch (e: Throwable) {
                            ErrorQueue.report(e, "widget-render")
                            null
                        }
                        result.success(png)
                    }
                }
                "save" -> {
                    val args = call.arguments as? Map<*, *>
                    val id = (args?.get("id") as? Number)?.toInt() ?: widgetId
                    val json = args?.get("style") as? String
                    if (json == null || id == AppWidgetManager.INVALID_APPWIDGET_ID || id == 0) {
                        result.success(false)
                    } else {
                        try {
                            HomeWidgets.saveStyle(this, id, json)
                            if (args["all"] == true) HomeWidgets.applyLookToAll(this, JSONObject(json))
                            HomeWidgets.updateAll(this)
                            setResult(Activity.RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
                            result.success(true)
                            finish()
                        } catch (e: Throwable) {
                            ErrorQueue.report(e, "widget-save")
                            result.success(false)
                        }
                    }
                }
                "cancel" -> {
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
