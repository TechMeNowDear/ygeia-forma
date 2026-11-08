package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Σύνδεση με την εφαρμογή του ρολογιού (8/11). Κανάλια «ygeia/wear» και «ygeia/wear/events».
 * Ακούει το ρολόι ΜΟΝΟ όσο ζει η εφαρμογή (χωρίς υπηρεσία παρασκηνίου)· ό,τι γίνει στο ρολόι όταν είναι κλειστή
 * μένει εκεί (DataItem) και έρχεται στο επόμενο άνοιγμα. Διαδρομές: όπως στο android/wear/…/Protocol.kt.
 */
class WearBridge(
    private val activity: Activity,
    private val scope: CoroutineScope,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val PLAN = "/ygeia/plan"
        const val SESSION = "/ygeia/session"
        const val RESULT = "/ygeia/result/"
        const val HR = "/ygeia/hr"
        const val CMD = "/ygeia/cmd"
        const val LIVE = "/ygeia/live"
        const val KEY = "json"
        const val CAPABILITY = "ygeia_watch"
    }

    private val ctx get() = activity.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    private val messages = MessageClient.OnMessageReceivedListener { e: MessageEvent ->
        if (e.path == HR || e.path == CMD || e.path == LIVE) {
            val text = String(e.data, Charsets.UTF_8)
            emit(mapOf("path" to e.path, "json" to text))
        }
    }

    private val data = DataClient.OnDataChangedListener { events: DataEventBuffer ->
        var result = false
        for (ev in events) {
            if (ev.type == DataEvent.TYPE_CHANGED && ev.dataItem.uri.path?.startsWith(RESULT) == true) result = true
        }
        if (result) emit(mapOf("path" to RESULT, "json" to ""))
    }

    private fun emit(m: Map<String, String>) {
        main.post { sink?.success(m) }
    }

    // ------------------------------------------------------------------ γεγονότα (όσο ακούει η Flutter)
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        try {
            Wearable.getMessageClient(ctx).addListener(messages)
            Wearable.getDataClient(ctx).addListener(data)
        } catch (e: Throwable) {
            // Χωρίς Wear OS στο κινητό: τίποτα.
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        try {
            Wearable.getMessageClient(ctx).removeListener(messages)
            Wearable.getDataClient(ctx).removeListener(data)
        } catch (_: Throwable) {
        }
    }

    fun dispose() = onCancel(null)

    // ------------------------------------------------------------------ κλήσεις
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> scope.launch { result.success(status()) }
            "putPlan" -> scope.launch { result.success(put(PLAN, call.argument<String>("json") ?: "{}", urgent = false)) }
            "putSession" -> scope.launch { result.success(put(SESSION, call.argument<String>("json") ?: "{}", urgent = true)) }
            "takeResults" -> scope.launch { result.success(results()) }
            "ackResult" -> scope.launch { result.success(ack(call.argument<String>("path") ?: "")) }
            "openWatch" -> scope.launch { result.success(openWatch()) }
            else -> result.notImplemented()
        }
    }

    /** Πόσα ρολόγια είναι συνδεδεμένα και σε πόσα υπάρχει η εφαρμογή μας. */
    private suspend fun status(): Map<String, Int> = try {
        val nodes = Wearable.getNodeClient(ctx).connectedNodes.await()
        val cap = Wearable.getCapabilityClient(ctx).getCapability(CAPABILITY, CapabilityClient.FILTER_REACHABLE).await()
        mapOf("nodes" to nodes.size, "app" to cap.nodes.size)
    } catch (_: Throwable) {
        mapOf("nodes" to 0, "app" to 0)
    }

    private suspend fun put(path: String, json: String, urgent: Boolean): Boolean = try {
        val req = PutDataMapRequest.create(path).apply {
            dataMap.putString(KEY, json)
            // Χρόνος μέσα, ώστε η ίδια κατάσταση δύο φορές να φτάνει κι αυτή (το ρολόι ξανασυγχρονίζεται).
            dataMap.putLong("t", System.currentTimeMillis())
        }.asPutDataRequest()
        if (urgent) req.setUrgent()
        Wearable.getDataClient(ctx).putDataItem(req).await()
        true
    } catch (_: Throwable) {
        false
    }

    /** Ό,τι έγινε μόνο στο ρολόι και δεν έχει περάσει ακόμα. */
    private suspend fun results(): List<Map<String, String>> = try {
        val buf = Wearable.getDataClient(ctx).dataItems.await()
        val out = mutableListOf<Map<String, String>>()
        try {
            for (item in buf) {
                val path = item.uri.path ?: continue
                if (!path.startsWith(RESULT)) continue
                val json = try {
                    DataMapItem.fromDataItem(item).dataMap.getString(KEY)
                } catch (_: Throwable) {
                    null
                } ?: continue
                out.add(mapOf("path" to path, "json" to json))
            }
        } finally {
            buf.release()
        }
        out
    } catch (_: Throwable) {
        emptyList()
    }

    /** Σβήνει ένα αποτέλεσμα αφού αποθηκευτεί στο κινητό (και από το ρολόι). */
    private suspend fun ack(path: String): Boolean = try {
        if (!path.startsWith(RESULT)) {
            false
        } else {
            val uri = Uri.Builder().scheme("wear").path(path).build()
            Wearable.getDataClient(ctx).deleteDataItems(uri).await()
            true
        }
    } catch (_: Throwable) {
        false
    }

    /** Ανοίγει την εφαρμογή στο ρολόι, στην προπόνηση που μόλις ξεκίνησε στο κινητό. */
    private suspend fun openWatch(): Boolean = try {
        val cap = Wearable.getCapabilityClient(ctx).getCapability(CAPABILITY, CapabilityClient.FILTER_REACHABLE).await()
        val helper = RemoteActivityHelper(ctx)
        val intent = Intent(Intent.ACTION_VIEW)
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .setData(Uri.parse("ygeiaforma-wear://session"))
        var ok = false
        for (n in cap.nodes) {
            try {
                helper.startRemoteActivity(intent, n.id)
                ok = true
            } catch (_: Throwable) {
            }
        }
        ok
    } catch (_: Throwable) {
        false
    }
}
