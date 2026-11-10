package gr.ygeiaforma.wear

import android.content.Context
import android.net.Uri
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import org.json.JSONObject
import java.util.concurrent.TimeUnit

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
        if (path == Paths.WIPE) {
            app?.let { onWipe(it, WipeRule.parseAt(text)) }
            return false
        }
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
    private const val WIPE_PREFS = "ygeia_wipe"
    private const val WIPE_WANT = "want"
    private const val WIPE_DONE = "done"
    private const val WIPE_ACKED = "acked"

    /** Το κινητό ζήτησε «σβήσε»: κρατιέται (σε αρχείο που δεν σβήνεται) και γίνεται μόλις επιτρέπεται ([tryWipe]). */
    private fun onWipe(ctx: Context, at: Long) {
        if (at <= 0L) return
        val sp = ctx.getSharedPreferences(WIPE_PREFS, Context.MODE_PRIVATE)
        if (at > sp.getLong(WIPE_WANT, 0L)) sp.edit().putLong(WIPE_WANT, at).commit()
        tryWipe(ctx)
    }

    /** Περιμένει «σβήσε» που δεν έγινε ακόμα (π.χ. λόγω άσκησης): τότε τα παλιά αποτελέσματα δεν ξαναστέλνονται. */
    fun wipeWanted(ctx: Context): Boolean {
        val sp = ctx.getSharedPreferences(WIPE_PREFS, Context.MODE_PRIVATE)
        return sp.getLong(WIPE_WANT, 0L) > sp.getLong(WIPE_DONE, 0L)
    }

    /**
     * «Διαγραφή όλων» από το κινητό (E3-05· έλεγχος του fix-accuracy, M1/S1/S2). Ποτέ στη μέση άσκησης ή με άσκηση που
     * έμεινε μισή (στιγμιότυπο): τότε περιμένει (ξανακοιτά στο επόμενο άνοιγμα και μετά την ανάκτηση).
     * Σβήνει: αρχεία (run.json, στιγμιότυπα, ό,τι άλλο), ρυθμίσεις του ρολογιού (πρόγραμμα, όριο, αποτελέσματα σε
     * αναμονή) και τα DataItems «/ygeia/…» που έγραψε το ρολόι (αποτελέσματα που δεν πήρε ακόμα το κινητό). Μετά απαντά
     * «/ygeia/wiped» και κλείνει, ώστε να μη μείνει τίποτα στη μνήμη. Μένουν μόνο οι ώρες των διαγραφών (WIPE_PREFS).
     * Αν η διαγραφή έχει ήδη γίνει αλλά η απάντηση δεν έφτασε, ξαναστέλνει μόνο την απάντηση.
     */
    fun tryWipe(ctx: Context) {
        val sp = ctx.getSharedPreferences(WIPE_PREFS, Context.MODE_PRIVATE)
        val at = sp.getLong(WIPE_WANT, 0L)
        val done = sp.getLong(WIPE_DONE, 0L)
        if (WipeRule.shouldAck(at, done, sp.getLong(WIPE_ACKED, 0L))) {
            Thread { if (putWiped(ctx, at)) sp.edit().putLong(WIPE_ACKED, at).commit() }.start()
            return
        }
        val busy = Repo.running != null || Repo.local != null || Repo.readRun(ctx) != null
        if (!WipeRule.shouldWipe(at, done, busy)) return
        try {
            ctx.filesDir.listFiles()?.forEach { it.deleteRecursively() }
            ctx.cacheDir.listFiles()?.forEach { it.deleteRecursively() }
            ctx.getSharedPreferences("ygeia_watch", Context.MODE_PRIVATE).edit().clear().commit()
        } catch (_: Exception) {
        }
        sp.edit().putLong(WIPE_DONE, at).commit()
        // Data Layer σε άλλο νήμα (όχι στο νήμα της οθόνης), με όριο χρόνου· μετά κλείνει.
        Thread {
            try {
                val dc = Wearable.getDataClient(ctx.applicationContext)
                val me = Tasks.await(Wearable.getNodeClient(ctx.applicationContext).localNode, 10, TimeUnit.SECONDS)
                Tasks.await(
                    dc.deleteDataItems(Uri.Builder().scheme("wear").authority(me.id).path("/ygeia/").build(), DataClient.FILTER_PREFIX),
                    10, TimeUnit.SECONDS,
                )
            } catch (_: Exception) {
            }
            if (putWiped(ctx, at)) sp.edit().putLong(WIPE_ACKED, at).commit()
            android.os.Process.killProcess(android.os.Process.myPid())
        }.start()
    }

    private fun putWiped(ctx: Context, at: Long): Boolean = try {
        val req = PutDataMapRequest.create(Paths.WIPED).apply {
            dataMap.putString(Paths.KEY, WipeRule.ackJson(at))
            dataMap.putLong("t", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Tasks.await(Wearable.getDataClient(ctx.applicationContext).putDataItem(req), 10, TimeUnit.SECONDS)
        true
    } catch (_: Exception) {
        false
    }

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
