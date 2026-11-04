package gr.ygeiaforma.ygeia_forma

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors
import kotlin.coroutines.CoroutineContext

/**
 * Όλες οι εργασίες στη βάση (ιστορικό, ημερολόγιο φαγητού, «Τα προϊόντα μου») μία-μία, με τη σειρά που έφτασαν
 * (έλεγχος 4/11, A8): δύο εγγραφές της ίδιας μέρας ή μια διαγραφή και η αναίρεσή της δεν προσπερνούν ποτέ η μία την
 * άλλη (πριν έτρεχαν σε δύο νήματα του IO και η σειρά τους στη βάση δεν ήταν σίγουρη).
 *
 * Έλεγχος 3, E6: ΕΝΑ νήμα (single-thread executor, αυστηρά FIFO), και οι κλήσεις της βάσης ξεκινούν ΚΑΤΕΥΘΕΙΑΝ εδώ
 * από το main thread ([run]). Πριν περνούσαν πρώτα από το Dispatchers.Default (πολλά νήματα), όπου δύο κλήσεις με
 * σειρά Α, Β μπορούσαν να φτάσουν στη βάση ως Β, Α.
 */
object DbQueue {
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, THREAD).apply { isDaemon = true } }
    val dispatcher: CoroutineDispatcher = executor.asCoroutineDispatcher()

    const val THREAD = "ygeia-db"

    /**
     * Τρέχει το [block] στη σειρά της βάσης (με τη σειρά των κλήσεων) και δίνει το κείμενο της απάντησης στο [done],
     * στο [resultContext] (το main thread για τη Flutter). Ό,τι πετάξει το [block] το χειρίζεται ο ίδιος ο block.
     */
    fun run(
        scope: CoroutineScope,
        done: (String) -> Unit,
        resultContext: CoroutineContext = Dispatchers.Main,
        block: suspend () -> String,
    ): Job = scope.launch(dispatcher) {
        val text = block()
        withContext(resultContext) { done(text) }
    }
}
