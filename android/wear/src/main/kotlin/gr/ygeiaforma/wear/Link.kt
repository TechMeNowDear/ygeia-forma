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

    private val listener = DataClient.OnDataChangedListener { events: DataEventBuffer ->
        var any = false
        for (e in events) {
            if (e.type != DataEvent.TYPE_CHANGED) continue
            any = apply(e.dataItem) || any
        }
        if (any) Repo.changed()
    }

    fun attach(ctx: Context) {
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
        return when (item.uri.path) {
            Paths.PLAN -> {
                Repo.setPlan(Plan.parse(text))
                true
            }
            Paths.SESSION -> {
                Repo.setPhone(LiveSession.parsePhone(text))
                true
            }
            else -> false
        }
    }

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
