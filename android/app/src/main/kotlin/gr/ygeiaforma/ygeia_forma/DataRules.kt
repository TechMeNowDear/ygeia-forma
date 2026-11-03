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

    /** Όνομα αντιγράφου μιας χαλασμένης βάσης (A7): ποτέ δεν σβήνεται, κρατιέται με την ώρα. */
    fun corruptName(name: String, ms: Long): String = "$name.corrupt-$ms"

    /**
     * Μετακινεί μια χαλασμένη βάση (και τα -wal/-shm/-journal της) στον φάκελο [dir] με την ώρα στο όνομα, ώστε να
     * ανοίξει καινούργια χωρίς να χαθεί τίποτα. Επιστρέφει το αντίγραφο της κύριας βάσης (ή null αν δεν υπήρχε).
     */
    fun keepCorrupt(db: File, dir: File, ms: Long): File? {
        dir.mkdirs()
        var main: File? = null
        for (suffix in listOf("", "-wal", "-shm", "-journal")) {
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

    /**
     * Μόνο αυτές οι σελίδες ανοίγουν στον browser από την εφαρμογή (σύνδεση Oura): η σελίδα σύνδεσης για νέες
     * εφαρμογές (developer.ouraring.com/authorize, A13), η κλασική και ο διακομιστής v2.
     */
    val ALLOWED_HOSTS = setOf("developer.ouraring.com", "cloud.ouraring.com", "api.ouraring.com")
}
