package gr.ygeiaforma.ygeia_forma

import java.io.File
import java.time.LocalDate

/**
 * Κανόνες δεδομένων χωρίς τύπους Android ή του Samsung SDK, ώστε να ελέγχονται σε απλό JVM (android/app/src/test).
 * Έλεγχος 4/11, κομμάτι A.
 */
object DataRules {
    /**
     * Είδη που διαβάζονται ΜΟΝΟ από το ρολόι (A2): ύπνος, παλμοί, οξυγόνο, θερμοκρασία δέρματος. Ό,τι άλλο υπάρχει
     * στη Samsung Health για αυτά (π.χ. ύπνος/παλμοί του Oura μέσω Health Connect, μετρήσεις του κινητού) δεν
     * διαβάζεται ποτέ. Ονόματα όπως στο «Τι φτάνει» (SamsungHealthBridge.readTypes).
     */
    val WATCH_ONLY = setOf("sleep", "heart_rate", "blood_oxygen", "skin_temperature")

    /** Ζυγίσεις μόνο από την εφαρμογή της InBody (ίδιος κανόνας με το isScaleApp στη Flutter). */
    fun isScaleApp(appId: String?): Boolean = appId?.lowercase()?.contains("inbody") == true

    /** Πώς διαβάστηκε το όριο ύπνου του ρολογιού από το αρχείο του σχεδίου πηγών. */
    data class SleepLimit(val until: LocalDate?, val error: Boolean)

    /**
     * Από το αρχείο του σχεδίου πηγών («sources.json»):
     * - δεν υπάρχει → χωρίς όριο (όπως πριν από το Oura),
     * - υπάρχει αλλά δεν διαβάζεται → ΣΦΑΛΜΑ (A15): ο ύπνος του ρολογιού δεν διαβάζεται, και η εφαρμογή το ξέρει ως
     *   «δεν διαβάστηκε» (όχι «δεν κοιμήθηκες»), οπότε δεν σβήνει τιμές ύπνου.
     * [read]: διαβάζει το κείμενο (μπορεί να πετάξει).
     */
    fun sleepLimit(exists: Boolean, read: () -> String, sleepUntilOf: (String) -> String): SleepLimit {
        if (!exists) return SleepLimit(null, false)
        return try {
            val v = sleepUntilOf(read())
            if (v.isEmpty()) SleepLimit(null, false)
            else if (v.length == 10) SleepLimit(LocalDate.parse(v), false)
            else SleepLimit(null, true)
        } catch (e: Throwable) {
            SleepLimit(null, true)
        }
    }

    /**
     * Χαλασμένη βάση (C8): κλείνει ΜΟΝΟ αν είναι ανοιχτή. Στο πρώτο άνοιγμα το Android καλεί τον χειριστή πριν ανοίξει η
     * βάση και μετά ξαναδοκιμάζει στο ίδιο αντικείμενο: ένα close() τότε θα έκανε το άνοιγμα να αποτύχει.
     */
    fun closeIfOpen(isOpen: Boolean, close: () -> Unit) {
        if (!isOpen) return
        try {
            close()
        } catch (_: Throwable) {
        }
    }

    /**
     * C14 (R13): το μήνυμα ενός σφάλματος για το Sentry. Τα org.json και τα require() βάζουν στο μήνυμα κομμάτι από τα
     * δεδομένα (π.χ. «Value {...} of type ...»): για αυτά μόνο ο τύπος, χωρίς μήνυμα.
     */
    fun reportableMessage(className: String, message: String): String =
        if (className == "org.json.JSONException" || className == "java.lang.IllegalArgumentException") "" else message

    /** C14 (R14): νέο κλειδί στο Keystore όταν το παλιό δεν ανακτάται πια. */
    fun regenerateKeyOn(e: Throwable): Boolean =
        e is java.security.UnrecoverableKeyException ||
            e.javaClass.name == "android.security.keystore.KeyPermanentlyInvalidatedException"

    /** C14 (R12): η επιστροφή της Oura σβήνεται από την αναμονή μόνο όταν η Flutter απάντησε «success». */
    fun callbackDelivered(outcome: String): Boolean = outcome == "success"

    /** Όνομα αντιγράφου μιας χαλασμένης βάσης (A7): ποτέ δεν σβήνεται, κρατιέται με την ώρα. */
    fun corruptName(name: String, ms: Long): String = "$name.corrupt-$ms"

    /**
     * Μετακινεί μια χαλασμένη βάση (και τα -wal/-shm/-journal της) στον φάκελο [dir] με την ώρα στο όνομα, ώστε να
     * ανοίξει καινούργια χωρίς να χαθεί τίποτα. Επιστρέφει το αντίγραφο της κύριας βάσης (ή null αν δεν υπήρχε).
     */
    fun keepCorrupt(db: File, dir: File, ms: Long): File? {
        dir.mkdirs()
        var main: File? = null
        // C14 (R11): πρώτα τα -wal/-shm/-journal και τελευταία η κύρια βάση· αλλιώς, αν αποτύχει η μετακίνηση του -wal,
        // η καινούργια βάση θα «έπαιζε» το παλιό -wal και θα χαλούσε κι αυτή.
        for (suffix in listOf("-wal", "-shm", "-journal", "")) {
            val f = File(db.path + suffix)
            if (!f.exists()) continue
            val to = File(dir, corruptName(db.name + suffix, ms))
            if (!f.renameTo(to)) {
                f.copyTo(to, overwrite = false)
                f.delete()
            }
            if (suffix.isEmpty()) main = to
        }
        return main
    }

    /** Μία φάση ύπνου (όνομα όπως η Samsung, π.χ. «LIGHT»· χρόνοι σε ms). */
    data class StageIn(val stage: String, val start: Long, val end: Long)

    /** Μία συνεδρία (SleepSession) μέσα σε μια εγγραφή ύπνου της Samsung· οποιοδήποτε πεδίο μπορεί να λείπει. */
    data class SessionIn(val start: Long?, val end: Long?, val minutes: Long?, val stages: List<StageIn>)

    /** Μία εγγραφή ύπνου όπως πηγαίνει στη Flutter. */
    data class SleepOut(val start: Long, val end: Long, val minutes: Long?, val score: Int?, val stages: List<StageIn>)

    /**
     * Έλεγχος 2, C2: μία εγγραφή ύπνου της Samsung μπορεί να έχει πολλές συνεδρίες (όταν ξυπνάς για ώρα). Βγαίνει ΜΙΑ
     * εγγραφή ανά συνεδρία, με τα δικά της όρια, διάρκεια και φάσεις, ώστε το κενό ανάμεσα να μη μετρά ποτέ ως ύπνος
     * (ούτε στους παλμούς/οξυγόνο της νύχτας) και μια συνεδρία χωρίς φάσεις να φαίνεται χωριστά. Η βαθμολογία της
     * Samsung αφορά όλη την εγγραφή: μπαίνει μόνο όταν η συνεδρία είναι μία.
     */
    fun splitSleep(start: Long, end: Long, minutes: Long?, score: Int?, sessions: List<SessionIn>): List<SleepOut> {
        if (sessions.size <= 1) return listOf(SleepOut(start, end, minutes, score, sessions.firstOrNull()?.stages ?: emptyList()))
        val out = ArrayList<SleepOut>()
        for (x in sessions) {
            val a = x.start ?: x.stages.minOfOrNull { it.start } ?: continue
            val b = x.end ?: x.stages.maxOfOrNull { it.end } ?: continue
            if (b <= a) continue
            out.add(SleepOut(a, b, x.minutes ?: ((b - a) / 60000), null, x.stages))
        }
        if (out.isEmpty()) return listOf(SleepOut(start, end, minutes, score, sessions.flatMap { it.stages }))
        return out.sortedBy { it.start }
    }

    /**
     * Έλεγχος 2, C6: το φίλτρο «μόνο ρολόι» δεν βρήκε καμία εγγραφή, ενώ χωρίς φίλτρο υπάρχουν στο ίδιο διάστημα. Αυτό
     * είναι σφάλμα ανάγνωσης (π.χ. το ρολόι δεν αναγνωρίζεται ως ρολόι μετά από αλλαγή κινητού), όχι «δεν κοιμήθηκες»:
     * η εφαρμογή κρατά το ιστορικό και το λέει στο «Τι φτάνει».
     */
    fun watchFilterEmpty(filtered: Int, unfiltered: Int): Boolean = filtered == 0 && unfiltered > 0

    /** Το μήνυμα του σφάλματος [watchFilterEmpty] (η Flutter το αναγνωρίζει με αυτό το κλειδί). */
    const val WATCH_FILTER_EMPTY = "watch_filter_empty"

    /**
     * Μόνο αυτές οι σελίδες ανοίγουν στον browser από την εφαρμογή (σύνδεση Oura): η σελίδα σύνδεσης για νέες
     * εφαρμογές (developer.ouraring.com/authorize, A13), η κλασική και ο διακομιστής v2.
     */
    val ALLOWED_HOSTS = setOf("developer.ouraring.com", "cloud.ouraring.com", "api.ouraring.com")
}
