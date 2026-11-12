package gr.ygeiaforma.ygeia_forma

import com.google.gson.JsonObject
import com.google.gson.JsonParser
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
        if (className in NO_MESSAGE) "" else message

    /**
     * Έλεγχος 9/11 (E3-19, P2-18): το ίδιο και για ΚΑΘΕ υποκλάση. Π.χ. το NumberFormatException είναι
     * IllegalArgumentException και το μήνυμά του είναι το κείμενο που δεν διαβάστηκε («For input string: "82,4"»).
     */
    fun reportableMessage(cls: Class<*>, message: String): String =
        if (generateSequence(cls) { it.superclass }.any { it.name in NO_MESSAGE }) "" else message

    private val NO_MESSAGE = setOf("org.json.JSONException", "java.lang.IllegalArgumentException")

    /**
     * Έλεγχος 9/11 (E3-24): ό,τι έρχεται στη MainActivity ως «ygeia_open» από άλλη εφαρμογή περνά μόνο αν έχει ακριβώς
     * τη μορφή που φτιάχνουν τα widgets («w:<είδος>:<πάτημα>:<τιμή>», HomeWidgets.views). Αλλιώς αγνοείται.
     */
    fun widgetOpenTarget(raw: String?): String? =
        raw?.takeIf { it.length <= 64 && WIDGET_OPEN.matches(it) }

    private val WIDGET_OPEN = Regex("^w:(sleep|move|food|body|workout):(section|today|add|metric|scan):[A-Za-z0-9_.]{0,32}$")

    /** Μέγεθος προεπισκόπησης από extras («ygeia_w/h», για τον έλεγχο στο emulator): μόνο λογικές τιμές σε dp. */
    fun previewDp(v: Int): Double? = v.takeIf { it in 40..1200 }?.toDouble()

    /**
     * «Διαγραφή όλων» (έλεγχος του fix-accuracy, M1): πότε ξεκίνησε η άσκηση ενός αποτελέσματος του ρολογιού. Από το
     * «start» (περπάτημα/προπόνηση του ρολογιού) ή από το id («walk<ms>», «w<ms>», «hr<sid>-<ms>»)· αλλιώς [putAt] (πότε
     * γράφτηκε το DataItem). Χωρίς org.json (καθαρός Kotlin, για τις δοκιμές JVM).
     */
    fun resultStart(json: String, putAt: Long): Long {
        Regex("\"start\"\\s*:\\s*(\\d{9,15})").find(json)?.let { return it.groupValues[1].toLong() }
        val id = Regex("\"id\"\\s*:\\s*\"([^\"]{1,80})\"").find(json)?.groupValues?.get(1)
        if (id != null) {
            Regex("^(?:walk|w)(\\d{9,15})$").find(id)?.let { return it.groupValues[1].toLong() }
            Regex("^hr.*-(\\d{9,15})$").find(id)?.let { return it.groupValues[1].toLong() }
        }
        return putAt
    }

    /** DataItem «/ygeia/…» γραμμένο ([t], το πεδίο «t») πριν από τη διαγραφή [wipeAt]: σβήνεται (N3). */
    fun writtenBeforeWipe(t: Long, wipeAt: Long): Boolean = wipeAt > 0 && t < wipeAt

    /** Αποτέλεσμα του ρολογιού από άσκηση πριν από τη «Διαγραφή όλων» ([wipeAt], 0 = καμία): δεν μπαίνει, σβήνεται. */
    fun droppedByWipe(start: Long, wipeAt: Long): Boolean = wipeAt > 0 && start < wipeAt

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

    /**
     * Έλεγχος 3, E4: η ανάγνωση του αρχείου νυχτών του Oura ως {"state": missing|ok|error, "json"}. Ένα σφάλμα
     * ανάγνωσης ΔΕΝ είναι «δεν υπάρχει» (τότε η Flutter δεν ξαναγράφει το αρχείο ούτε σβήνει παλμούς μέρας).
     */
    fun nightsState(exists: Boolean, read: () -> String): String {
        val o = JsonObject()
        if (!exists) {
            o.addProperty("state", "missing")
            return o.toString()
        }
        try {
            val text = read()
            o.addProperty("state", "ok")
            o.addProperty("json", text)
        } catch (e: Throwable) {
            o.addProperty("state", "error")
        }
        return o.toString()
    }

    /** Τι κάνει το Vault με το κλειδί του Keystore (έλεγχος 3, E6). */
    enum class KeyAction { USE, RETRY, FAIL, GENERATE }

    /**
     * Νέο κλειδί ΜΟΝΟ όταν το alias δεν υπάρχει. Υπάρχει αλλά δεν βρέθηκε το κλειδί (προσωρινό): ξανά ως [maxAttempts]
     * φορές, μετά σφάλμα — ποτέ αντικατάσταση (θα χανόταν η δυνατότητα να διαβαστούν τα tokens).
     */
    fun keyAction(aliasExists: Boolean, keyFound: Boolean, attempt: Int, maxAttempts: Int): KeyAction = when {
        keyFound -> KeyAction.USE
        !aliasExists -> KeyAction.GENERATE
        attempt < maxAttempts -> KeyAction.RETRY
        else -> KeyAction.FAIL
    }

    /** Τι σημαίνει ένα άδειο αποτέλεσμα με φίλτρο ρολογιού ([watchFilterEmpty]). */
    enum class FilterOutcome { OK, ERROR, NON_WATCH }

    /**
     * Έλεγχος 3, E3: το C6 ισχύει ΜΟΝΟ για την κανονική ανάγνωση των τελευταίων 30 ημερών ([recent]), όπου περιμένουμε
     * δεδομένα ρολογιού: εκεί είναι σφάλμα (το ιστορικό μένει). Σε κομμάτι συμπλήρωσης/επανανάγνωσης ένα άδειο
     * αποτέλεσμα με φίλτρο σημαίνει «δεν υπάρχουν δεδομένα ρολογιού εδώ» (π.χ. πριν από το ρολόι, από κινητό ή
     * βραχιόλι): δεκτό, χωρίς ξαναδοκιμές, σημειωμένο ως [FilterOutcome.NON_WATCH].
     */
    fun filterOutcome(filtered: Int, unfiltered: Int, recent: Boolean): FilterOutcome = when {
        !watchFilterEmpty(filtered, unfiltered) -> FilterOutcome.OK
        recent -> FilterOutcome.ERROR
        else -> FilterOutcome.NON_WATCH
    }

    /** Το μήνυμα του σφάλματος [watchFilterEmpty] (η Flutter το αναγνωρίζει με αυτό το κλειδί). */
    const val WATCH_FILTER_EMPTY = "watch_filter_empty"

    /**
     * Μόνο αυτές οι σελίδες ανοίγουν στον browser από την εφαρμογή (σύνδεση Oura): η σελίδα σύνδεσης για νέες
     * εφαρμογές (developer.ouraring.com/authorize, A13), η κλασική και ο διακομιστής v2.
     */
    val ALLOWED_HOSTS = setOf("developer.ouraring.com", "cloud.ouraring.com", "api.ouraring.com")

    /**
     * Ρυθμίσεις που μένουν ΜΟΝΟ σε αυτό το κινητό (συγχώνευση 4/11): το όνομα για την αναφορά προς τον γιατρό.
     * Το prefs.json μπαίνει στο αντίγραφο Google και στη μεταφορά σε νέο κινητό (backup_rules.xml,
     * data_extraction_rules.xml)· αυτά τα κλειδιά γράφονται χωριστά στο noBackupFilesDir ([DEVICE_PREFS_FILE]),
     * που το Android δεν βάζει ποτέ σε αντίγραφο. Η Flutter δεν αλλάζει: στέλνει και διαβάζει ένα ενιαίο JSON.
     */
    val DEVICE_ONLY_PREFS = setOf("reportName")
    const val DEVICE_PREFS_FILE = "device_prefs.json"

    /**
     * Χωρίζει το JSON των ρυθμίσεων: (ό,τι πάει στο prefs.json, τι γίνεται με το ιδιωτικό αρχείο):
     * - null: κανένα από τα [DEVICE_ONLY_PREFS] δεν υπάρχει στο JSON → το αρχείο του κινητού ΜΕΝΕΙ όπως είναι
     *   (έλεγχος 3, E6: ρυθμίσεις από προεπιλογές μετά από χαλασμένο prefs.json δεν σβήνουν το όνομα),
     * - [DEVICE_PREFS_DELETE] («{}»): υπάρχουν αλλά κενά (null) → το αρχείο σβήνεται (ο χρήστης έσβησε το όνομα),
     * - αλλιώς το JSON με τις τιμές → γράφεται.
     * Μη έγκυρο JSON (ή όχι αντικείμενο): ως έχει, χωρίς τίποτα ιδιωτικό (ποτέ δεν χάνονται ρυθμίσεις).
     */
    fun splitDeviceOnlyPrefs(json: String): Pair<String, String?> {
        val o = parseObject(json) ?: return json to null
        val own = JsonObject()
        var present = false
        for (k in DEVICE_ONLY_PREFS) {
            val v = o.remove(k) ?: continue
            present = true
            if (!v.isJsonNull) own.add(k, v)
        }
        return o.toString() to (if (!present) null else own.toString())
    }

    /** Το «σβήσε το ιδιωτικό αρχείο» του [splitDeviceOnlyPrefs]. */
    const val DEVICE_PREFS_DELETE = "{}"

    /**
     * Ενώνει το prefs.json με τα ιδιωτικά κλειδιά του κινητού. Τα ιδιωτικά υπερισχύουν· παλιό prefs.json που έχει
     * ακόμα το κλειδί (πριν από τον χωρισμό) το κρατά, ώσπου η επόμενη αποθήκευση να το μεταφέρει. Αν το prefs.json
     * δεν διαβάζεται ως αντικείμενο (π.χ. σφάλμα ανάγνωσης), επιστρέφεται ως έχει.
     */
    fun mergeDeviceOnlyPrefs(prefs: String, deviceOnly: String?): String {
        if (deviceOnly == null) return prefs
        val o = parseObject(prefs) ?: return prefs
        val d = parseObject(deviceOnly) ?: return prefs
        for (k in DEVICE_ONLY_PREFS) {
            val v = d.get(k) ?: continue
            o.add(k, v)
        }
        return o.toString()
    }

    private fun parseObject(json: String): JsonObject? = try {
        val e = JsonParser.parseString(json)
        if (e.isJsonObject) e.asJsonObject else null
    } catch (_: Throwable) {
        null
    }
}
