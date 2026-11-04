package gr.ygeiaforma.ygeia_forma

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Έλεγχος 3, E6: οι εργασίες της βάσης τρέχουν σε ΕΝΑ νήμα, αυστηρά με τη σειρά των κλήσεων. */
class DbQueueTest {
    @Test
    fun dbWorkRunsStrictlyInCallOrderOnOneThread() {
        val scope = CoroutineScope(Job())
        val n = 500
        val ran = Collections.synchronizedList(ArrayList<Int>())
        val answered = Collections.synchronizedList(ArrayList<String>())
        val threads = Collections.synchronizedSet(HashSet<String>())
        val latch = CountDownLatch(n)
        for (i in 0 until n) {
            DbQueue.run(scope, { answered.add(it); latch.countDown() }, Dispatchers.Unconfined) {
                threads.add(Thread.currentThread().name)
                // Η πρώτη εργασία αργεί: καμία επόμενη δεν την προσπερνά.
                if (i == 0) Thread.sleep(50)
                ran.add(i)
                "$i"
            }
        }
        assertTrue(latch.await(10, TimeUnit.SECONDS))
        assertEquals((0 until n).toList(), ran.toList())
        assertEquals((0 until n).map { "$it" }, answered.toList())
        assertEquals(setOf(DbQueue.THREAD), threads.toSet())
    }
}
