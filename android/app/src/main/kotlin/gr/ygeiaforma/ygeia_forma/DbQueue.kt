package gr.ygeiaforma.ygeia_forma

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi

/**
 * Όλες οι εργασίες στη βάση (ιστορικό, ημερολόγιο φαγητού, «Τα προϊόντα μου») μία-μία, με τη σειρά που έφτασαν
 * (έλεγχος 4/11, A8): δύο εγγραφές της ίδιας μέρας ή μια διαγραφή και η αναίρεσή της δεν προσπερνούν ποτέ η μία την
 * άλλη (πριν έτρεχαν σε δύο νήματα του IO και η σειρά τους στη βάση δεν ήταν σίγουρη).
 */
object DbQueue {
    @OptIn(ExperimentalCoroutinesApi::class)
    val dispatcher: CoroutineDispatcher = Dispatchers.IO.limitedParallelism(1)
}
