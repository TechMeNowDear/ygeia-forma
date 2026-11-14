package gr.ygeiaforma.wear

import android.content.Context
import android.net.Uri
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Πόσο περιμένει το ρολόι την απάντηση του κινητού στο «πες το» (14/11) πριν μιλήσει το ίδιο. */
const val SAY_WAIT_MS = 2_500L

/** Η απάντηση του κινητού στο «πες το»: (id, ok) ή null. Καθαρή συνάρτηση, με δοκιμές. */
fun sayReply(text: String): Pair<String, Boolean>? = try {
    val o = JSONObject(text)
    val id = o.optStringOrNull("id")
    if (id == null) null else id to o.optBoolean("ok", false)
} catch (_: Exception) {
    null
}

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

    /** «Κοιτάζω» από το κινητό (W3-15): ως πότε, και ότι το κινητό το ξέρει (μένει, για τις επόμενες φορές). */
    private val messages = MessageClient.OnMessageReceivedListener { e: MessageEvent ->
        // 14/11: η απάντηση του κινητού στο «πες το» ([askPhoneToSay]).
        if (e.path == Paths.SAID) {
            sayReply(String(e.data, Charsets.UTF_8))?.let { (id, ok) -> sayWaits.remove(id)?.complete(ok) }
            return@OnMessageReceivedListener
        }
        if (e.path != Paths.WATCHING) return@OnMessageReceivedListener
        val ttl = watchingTtl(String(e.data, Charsets.UTF_8))
        Repo.watchingUntil = if (ttl > 0) System.currentTimeMillis() + ttl else 0L
        if (!Repo.phoneKnowsWatching) {
            Repo.phoneKnowsWatching = true
            app?.getSharedPreferences("ygeia_watch", Context.MODE_PRIVATE)?.edit()?.putBoolean(WATCH_KNOWN, true)?.apply()
        }
    }

    fun attach(ctx: Context) {
        app = ctx.applicationContext
        Repo.loadLimit(ctx.applicationContext)
        if (users++ == 0) {
            Wearable.getDataClient(ctx.applicationContext).addListener(listener)
            Wearable.getMessageClient(ctx.applicationContext).addListener(messages)
            Repo.phoneKnowsWatching = ctx.applicationContext.getSharedPreferences("ygeia_watch", Context.MODE_PRIVATE).getBoolean(WATCH_KNOWN, false)
        }
    }

    fun detach(ctx: Context) {
        if (users > 0 && --users == 0) {
            Wearable.getDataClient(ctx.applicationContext).removeListener(listener)
            Wearable.getMessageClient(ctx.applicationContext).removeListener(messages)
        }
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
        // Έλεγχος του fix-accuracy (N3): μετά από «σβήσε», παλιό πρόγραμμα/όριο του κινητού που έμεινε στο Data Layer
        // (π.χ. κρασάρισμα του κινητού στη μέση) δεν ξαναμπαίνει.
        val t = try {
            DataMapItem.fromDataItem(item).dataMap.getLong("t", 0L)
        } catch (_: Exception) {
            0L
        }
        val ctx0 = app
        if (ctx0 != null && WipeRule.staleFromPhone(t, ctx0.getSharedPreferences(WIPE_PREFS, Context.MODE_PRIVATE).getLong(WIPE_DONE, 0L))) {
            return false
        }
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
    /** Το κινητό στέλνει «κοιτάζω» (W3-15). Σβήνεται με τη «Διαγραφή όλων»· ξαναγράφεται στο επόμενο «κοιτάζω». */
    private const val WATCH_KNOWN = "watchKnown"

    /** Το κινητό ζήτησε «σβήσε»: κρατιέται (σε αρχείο που δεν σβήνεται) και γίνεται μόλις επιτρέπεται ([tryWipe]). */
    private fun onWipe(ctx: Context, at: Long) {
        if (at <= 0L) return
        val sp = ctx.getSharedPreferences(WIPE_PREFS, Context.MODE_PRIVATE)
        if (at > sp.getLong(WIPE_WANT, 0L)) sp.edit().putLong(WIPE_WANT, at).commit()
        tryWipe(ctx)
    }

    /**
     * Αποτέλεσμα σε αναμονή που επιτρέπεται να σταλεί τώρα: αν περιμένει «σβήσε», μόνο όσα έγιναν μετά από αυτό (N1)·
     * τα παλιά σβήνονται με τη διαγραφή.
     */
    fun sendable(ctx: Context, o: JSONObject): Boolean {
        val sp = ctx.getSharedPreferences(WIPE_PREFS, Context.MODE_PRIVATE)
        val want = sp.getLong(WIPE_WANT, 0L)
        return want <= sp.getLong(WIPE_DONE, 0L) || WipeRule.keepAfterWipe(o.toString(), 0L, want)
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
        // N1: μόνο ό,τι έγινε πριν από τη διαγραφή. Αποτελέσματα σε αναμονή από ασκήσεις μετά το [at] μένουν.
        val keep = try {
            Repo.pendingAll(ctx).filter { (_, o) -> WipeRule.keepAfterWipe(o.toString(), 0L, at) }
        } catch (_: Exception) {
            emptyList()
        }
        try {
            ctx.filesDir.listFiles()?.forEach { if (it.lastModified() < at) it.deleteRecursively() }
            ctx.cacheDir.listFiles()?.forEach { it.deleteRecursively() }
            // Πρόγραμμα, όριο, αναμονές (N3: και το όριο που θυμόταν το ρολόι)· μετά ξαναμπαίνουν μόνο οι νεότερες.
            ctx.getSharedPreferences("ygeia_watch", Context.MODE_PRIVATE).edit().clear().commit()
            for ((id, o) in keep) Repo.savePending(ctx, id, o)
        } catch (_: Exception) {
        }
        sp.edit().putLong(WIPE_DONE, at).commit()
        // Data Layer σε άλλο νήμα (όχι στο νήμα της οθόνης), με όριο χρόνου· μετά κλείνει.
        Thread {
            try {
                val dc = Wearable.getDataClient(ctx.applicationContext)
                val me = Tasks.await(Wearable.getNodeClient(ctx.applicationContext).localNode, 10, TimeUnit.SECONDS)
                // Τα DataItems του ρολογιού: όλα τα παλιά· αποτελέσματα από ασκήσεις μετά το [at] μένουν (N1).
                val old = mutableListOf<Uri>()
                val buf = Tasks.await(dc.dataItems, 10, TimeUnit.SECONDS)
                try {
                    for (item in buf) {
                        val u = item.uri
                        val p = u.path ?: continue
                        if (u.host != me.id || !p.startsWith("/ygeia/") || p == Paths.WIPED) continue
                        if (p.startsWith(Paths.RESULT)) {
                            val m = DataMapItem.fromDataItem(item).dataMap
                            if (WipeRule.keepAfterWipe(m.getString(Paths.KEY) ?: "", m.getLong("t", 0L), at)) continue
                        }
                        old.add(u)
                    }
                } finally {
                    buf.release()
                }
                for (u in old) Tasks.await(dc.deleteDataItems(u), 10, TimeUnit.SECONDS)
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
        val slow = ctx.getSharedPreferences("ygeia_watch", Context.MODE_PRIVATE).getBoolean(SLOW, false)
        val text = ackJson(p.hrLimit, p.at, slow).toString()
        val key = "${p.hrLimit ?: 0}/${p.at}/$slow"
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
    fun ackJson(limit: Int?, planAt: Long, slow: Boolean = false): JSONObject =
        JSONObject().put("v", Proto.MAJOR).put("lim", limit ?: 0).put("planAt", planAt).also { if (slow) it.put("slow", 1) }

    private const val SLOW = "slow"

    /**
     * Το ρολόι έμαθε (στην αρχή μιας άσκησης) αν στέλνει παλμούς αργά με σβηστή οθόνη (έλεγχος του γ2, S1): κρατιέται και
     * πάει στο κινητό με το «/ygeia/wstate» («slow»: 1), για την κάρτα ορίου εκεί. Μόνο όταν αλλάζει.
     */
    fun setSlow(ctx: Context, slow: Boolean) {
        val sp = ctx.getSharedPreferences("ygeia_watch", Context.MODE_PRIVATE)
        if (sp.getBoolean(SLOW, false) == slow) return
        sp.edit().putBoolean(SLOW, slow).apply()
        val p = Repo.plan ?: Plan(Repo.knownLimit, null, null, emptyList(), 0)
        ack(ctx, p)
    }

    /** Το πολύ τόσο για την ανάγνωση στο άνοιγμα (έλεγχος 13/11, S8-09). */
    const val LOAD_TIMEOUT_MS = 5_000L

    /**
     * Διαβάζει ό,τι έχει ήδη στείλει το κινητό (στο άνοιγμα). Με όριο χρόνου (S8-09): πίσω από αυτή την ανάγνωση περιμένουν
     * η ανάκτηση μιας μισής άσκησης και η αποστολή των αποτελεσμάτων· αν οι υπηρεσίες της Google δεν απαντήσουν, το άνοιγμα
     * συνεχίζει με ό,τι υπάρχει (οι αλλαγές έρχονται έτσι κι αλλιώς και από τον ακροατή).
     */
    suspend fun load(ctx: Context) {
        try {
            val buf = withTimeoutOrNull(LOAD_TIMEOUT_MS) { Wearable.getDataClient(ctx.applicationContext).dataItems.await() } ?: return
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

    /** Το πολύ τόσο για ένα μήνυμα προς το κινητό (τελικός έλεγχος, Συμβούλιο 4, W-1). */
    const val SEND_TIMEOUT_MS = 5_000L

    /**
     * Μήνυμα σε όσα συνδεδεμένα κινητά υπάρχουν. false αν δεν βρέθηκε κανένα, ή αν οι υπηρεσίες της Google δεν απάντησαν
     * σε [SEND_TIMEOUT_MS]. Με όριο χρόνου (W-1): οι εντολές της οθόνης φεύγουν μία-μία ([WatchActivity], κλείδωμα)· ένα
     * μήνυμα που δεν απαντά ποτέ θα κρατούσε πίσω του όλα τα επόμενα.
     */
    suspend fun send(ctx: Context, path: String, data: ByteArray): Boolean = try {
        withTimeoutOrNull(SEND_TIMEOUT_MS) {
            val nodes = Wearable.getNodeClient(ctx.applicationContext).connectedNodes.await()
            val mc = Wearable.getMessageClient(ctx.applicationContext)
            var ok = false
            for (n in nodes) {
                try {
                    mc.sendMessage(n.id, path, data).await()
                    ok = true
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (_: Exception) {
                }
            }
            ok
        } == true
    } catch (_: Exception) {
        false
    }

    suspend fun sendJson(ctx: Context, path: String, o: JSONObject): Boolean = send(ctx, path, o.toString().toByteArray(Charsets.UTF_8))

    private val sayWaits = java.util.concurrent.ConcurrentHashMap<String, kotlinx.coroutines.CompletableDeferred<Boolean>>()
    private var sayNext = 0L

    /**
     * Ζητά από το κινητό να πει τη φράση (14/11, [Voice]). true μόνο αν το κινητό απάντησε «το λέω» μέσα σε [SAY_WAIT_MS]
     * (έχει ακουστικά). Το «until» λέει στο κινητό να μην τη πει αργότερα (τότε θα την έχει πει ήδη το ρολόι).
     */
    suspend fun askPhoneToSay(ctx: Context, el: String, en: String): Boolean {
        if (users == 0) return false // δεν ακούμε απαντήσεις: μιλά το ρολόι
        val id = "s${System.currentTimeMillis()}-${sayNext++}"
        val wait = kotlinx.coroutines.CompletableDeferred<Boolean>()
        sayWaits[id] = wait
        try {
            val o = JSONObject().put("v", 1).put("id", id).put("el", el).put("en", en)
                .put("until", System.currentTimeMillis() + SAY_WAIT_MS)
            // Όλο μαζί (αποστολή και απάντηση) το πολύ [SAY_WAIT_MS]: κινητό μακριά → μιλά αμέσως το ρολόι.
            return withTimeoutOrNull(SAY_WAIT_MS) { sendJson(ctx, Paths.SAY, o) && wait.await() } == true
        } finally {
            sayWaits.remove(id)
        }
    }

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
