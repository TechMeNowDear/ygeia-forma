package gr.ygeiaforma.wear

import android.content.Context
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

/**
 * Σύνδεση με το κινητό (Wear Data Layer). Ακούει αλλαγές μόνο όσο είναι ανοιχτή η οθόνη ή τρέχει άσκηση
 * ([attach]/[detach] με μετρητή)· αλλιώς δεν κάνει τίποτα στο παρασκήνιο.
 */
object Link {
    private var users = 0
    private var app: Context? = null

    private val listener = DataClient.OnDataChangedListener { events: DataEventBuffer ->
        var any = false
        for (e in events) {
            if (e.type != DataEvent.TYPE_CHANGED) continue
            any = apply(e.dataItem) || any
        }
        if (any) Repo.changed()
    }

    fun attach(ctx: Context) {
        app = ctx.applicationContext
        Repo.loadLimit(ctx.applicationContext)
        if (users++ == 0) Wearable.getDataClient(ctx.applicationContext).addListener(listener)
    }

    fun detach(ctx: Context) {
        if (users > 0 && --users == 0) Wearable.getDataClient(ctx.applicationContext).removeListener(listener)
    }

    private fun textOf(item: DataItem): String? = try {
        DataMapItem.fromDataItem(item).dataMap.getString(Paths.KEY)
    } catch (_: Exception) {
        null
    }

    /** true αν άλλαξε κάτι που βλέπει η οθόνη. */
    private fun apply(item: DataItem): Boolean {
        val text = textOf(item) ?: return false
        val path = item.uri.path
        if (path != Paths.PLAN && path != Paths.SESSION) return false
        // Από νεότερη έκδοση της εφαρμογής του κινητού (V-A-08): δεν διαβάζεται· το ρολόι ζητά ενημέρωση και κρατά ό,τι είχε
        // (ούτε «η προπόνηση του κινητού τελείωσε»).
        if (Proto.tooNew(text)) {
            Repo.updateNeeded = true
            return true
        }
        return when (path) {
            Paths.PLAN -> {
                val p = Plan.parse(text) ?: return false
                Repo.updateNeeded = false
                Repo.applyPlan(p)
                app?.let { ctx ->
                    Repo.rememberLimit(ctx, p.hrLimit)
                    ack(ctx, p)
                }
                true
            }
            else -> {
                Repo.applyPhone(LiveSession.parsePhone(text))
                true
            }
        }
    }

    private const val ACKED = "acked"

    /**
     * Το ρολόι λέει στο κινητό ποιο όριο έχει (DataItem [Paths.STATE], έλεγχος 9/11, V-A-06): το κινητό γράφει
     * «Στο ρολόι ✓ όριο 140» μόνο τότε. DataItem: φτάνει και αν το κινητό είναι μακριά τώρα (μόλις συνδεθούν), χωρίς
     * καμία επανάληψη από εδώ. Γράφεται μόνο όταν αλλάζει (όχι σε κάθε άνοιγμα).
     */
    fun ack(ctx: Context, p: Plan) {
        val text = ackJson(p.hrLimit, p.at).toString()
        val key = "${p.hrLimit ?: 0}/${p.at}"
        val sp = ctx.getSharedPreferences("ygeia_watch", Context.MODE_PRIVATE)
        if (sp.getString(ACKED, null) == key) return
        try {
            val req = PutDataMapRequest.create(Paths.STATE).apply {
                dataMap.putString(Paths.KEY, text)
                dataMap.putLong("t", System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
            Wearable.getDataClient(ctx).putDataItem(req)
                .addOnSuccessListener { sp.edit().putString(ACKED, key).apply() }
        } catch (_: Exception) {
        }
    }

    /** Τι λέει το ρολόι για τον εαυτό του: το όριο που ισχύει (0 = χωρίς), από ποιο πρόγραμμα, ποια μορφή ξέρει. */
    fun ackJson(limit: Int?, planAt: Long): JSONObject =
        JSONObject().put("v", Proto.MAJOR).put("lim", limit ?: 0).put("planAt", planAt)

    /** Διαβάζει ό,τι έχει ήδη στείλει το κινητό (στο άνοιγμα). */
    suspend fun load(ctx: Context) {
        try {
            val buf = Wearable.getDataClient(ctx.applicationContext).dataItems.await()
            try {
                for (item in buf) apply(item)
            } finally {
                buf.release()
            }
            Repo.changed()
        } catch (_: Exception) {
            // Χωρίς κινητό κοντά: μένει ό,τι υπάρχει.
        }
    }

    /** Μήνυμα σε όσα συνδεδεμένα κινητά υπάρχουν. false αν δεν βρέθηκε κανένα. */
    suspend fun send(ctx: Context, path: String, data: ByteArray): Boolean = try {
        val nodes = Wearable.getNodeClient(ctx.applicationContext).connectedNodes.await()
        val mc = Wearable.getMessageClient(ctx.applicationContext)
        var ok = false
        for (n in nodes) {
            try {
                mc.sendMessage(n.id, path, data).await()
                ok = true
            } catch (_: Exception) {
            }
        }
        ok
    } catch (_: Exception) {
        false
    }

    suspend fun sendJson(ctx: Context, path: String, o: JSONObject): Boolean = send(ctx, path, o.toString().toByteArray(Charsets.UTF_8))

    /** Αποτέλεσμα για το κινητό: μένει στο ρολόι ώσπου να το πάρει το κινητό (και ας είναι μακριά τώρα). */
    suspend fun putResult(ctx: Context, id: String, json: JSONObject): Boolean = try {
        val req = PutDataMapRequest.create(Paths.RESULT + id).apply {
            dataMap.putString(Paths.KEY, json.toString())
            dataMap.putLong("t", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(ctx.applicationContext).putDataItem(req).await()
        true
    } catch (_: Exception) {
        false
    }
}
