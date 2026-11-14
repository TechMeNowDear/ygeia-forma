package gr.ygeiaforma.ygeia_forma

import android.content.ContentValues
import android.content.Context
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Τοπική μνήμη: μία γραμμή ανά μέρα με τη σύνοψή της (JSON), στη βάση SQLite του Android.
 * Μικρό μέγεθος (λίγα KB τον χρόνο), καμία εξωτερική βιβλιοθήκη.
 * Οι συνόψεις υπολογίζονται στη Flutter πλευρά· εδώ μόνο αποθηκεύονται.
 */
class DayStore private constructor(context: Context) :
    SQLiteOpenHelper(context, "ygeia.db", null, 2, KeepCorruptDb(context.applicationContext)) {

    companion object {
        @Volatile private var instance: DayStore? = null

        /** Μία σύνδεση με τη βάση για όλη την εφαρμογή. */
        fun get(context: Context): DayStore =
            instance ?: synchronized(this) {
                instance ?: DayStore(context.applicationContext).also { instance = it }
            }

        /**
         * Σημάδι «η βάση χάλασε, κρατήθηκε αντίγραφο» (ώρα σε ms). Όχι στο αντίγραφο Google. Round 8 (R8-A9-2): μένει και
         * όταν ο χρήστης κλείσει την κάρτα ([markSeen]), ώσπου να το αντικαταστήσει νέα βλάβη ή να γίνει «Διαγραφή όλων».
         */
        internal fun marker(context: Context) = java.io.File(context.noBackupFilesDir, DbSalvage.CORRUPT)

        fun corruptAt(context: Context): Long? = DbSalvage.corruptAt(context.noBackupFilesDir)

        /**
         * Round 8 (R8-A9-2, f4): «Εντάξει» στην κάρτα της βλάβης [at] κρύβει ΜΟΝΟ την κάρτα. Το σημάδι [marker] μένει, ώστε
         * η επαναφορά του φαγητού και η νέα ανάγνωση του ιστορικού να ξαναδοκιμάζονται ώσπου να γίνουν. Πριν το «Εντάξει»
         * έσβηνε το σημάδι: αν η πρώτη προσπάθεια είχε αποτύχει (π.χ. γεμάτος χώρος), δεν ξαναγινόταν ποτέ.
         * Όλα αυτά σβήνονται με τη «Διαγραφή όλων» (noBackupFilesDir). Round 9 (R9-A12-2): ο κανόνας στο [DbSalvage.markSeen].
         */
        fun markSeen(context: Context, at: Long) = DbSalvage.markSeen(context.noBackupFilesDir, at)

        /** Round 7 (R7-A9-1): ότι το φαγητό ξαναμπήκε μετά από τη βλάβη ([DbSalvage.doneText]). */
        private fun salvagedMarker(context: Context) = java.io.File(context.noBackupFilesDir, DbSalvage.SALVAGED)

        /** Round 8 (R8-A9-3): ό,τι σβήστηκε μετά από τη βλάβη, ώσπου να τελειώσει η επαναφορά ([DbSalvage.removedLine]). */
        private fun removedFile(context: Context) = java.io.File(context.noBackupFilesDir, "salvage_removed")

        private fun readOrNull(f: java.io.File): String? = try {
            f.takeIf { it.exists() }?.readText()
        } catch (_: Throwable) {
            null
        }

        /**
         * Round 7 (R7-A9-1, f4): μετά από βλάβη, οι γραμμές του ημερολογίου φαγητού και των «Τα προϊόντα μου» που
         * διαβάζονται από το αρχείο που κρατήθηκε για τη βλάβη [at] ([KeepCorruptDb]). Διαβάζεται ένα ΑΝΤΙΓΡΑΦΟ του (με
         * το -wal/-journal του, στα κανονικά ονόματα), ώστε το κρατημένο να μην αλλάζει ποτέ· με χειριστή βλάβης που δεν
         * σβήνει τίποτα. Τίποτα δεν γράφεται εδώ· τις γράφει η Flutter με την «restorePut». «done»: έγινε ήδη.
         * Round 8 (R8-A9-1, f4): η ανάγνωση γίνεται σε μικρά κομμάτια ([DbSalvage.read]): μια χαλασμένη σελίδα χάνει μόνο
         * τις δικές της γραμμές (πριν, στο Android, δεν διαβαζόταν ΤΙΠΟΤΑ από τον πίνακα). «complete»: διαβάστηκαν όλα·
         * «lost»: σημεία που δεν διαβάστηκαν. R8-A9-3: όσα σβήστηκαν μετά από τη βλάβη δεν ξαναμπαίνουν.
         */
        fun salvageRead(context: Context, at: Long): JSONObject {
            val out = JSONObject().put("ok", true)
            val mark = readOrNull(salvagedMarker(context))
            val done = DbSalvage.parseDone(mark, at)
            if (done != null) return out.put("done", true).put("entries", done.first).put("foods", done.second)
            // Round 9 (R9-A9-3, f4): με σημάδι του #105, ο πίνακας που ξαναμπήκε ΤΟΤΕ δεν ξαναδιαβάζεται ([DbSalvage.oldDone]).
            val old = DbSalvage.oldDone(mark, at)
            val removed = DbSalvage.parseRemoved(readOrNull(removedFile(context)), at)
            val log = JSONArray()
            val foods = JSONArray()
            var skipped = 0
            var lost = 0
            var complete = true
            val work = java.io.File(context.noBackupFilesDir, "salvage")
            try {
                work.deleteRecursively()
                val copy = DbSalvage.copyKept(java.io.File(context.noBackupFilesDir, "corrupt"), work, at)
                out.put("found", copy != null)
                val db = copy?.let { openKept(it) }
                if (copy != null && db == null) {
                    out.put("unreadable", true)
                    complete = false
                }
                if (db != null) {
                    try {
                        val a = if (old.first) null else DbSalvage.read(sqlRows(db, "food_log"), removed.first, log)
                        val b = if (old.second) null else DbSalvage.read(sqlRows(db, "my_foods"), removed.second, foods)
                        for (r in listOfNotNull(a, b)) {
                            skipped += r.skipped
                            lost += r.lost
                            if (!r.complete) complete = false
                        }
                        // Round 9 (R9-A9-B1): και μια γραμμή που δεν διαβάστηκε σωστά (χωρίς id ή όχι JSON) είναι κάτι
                        // που λείπει· η κάρτα το λέει ([DbSalvage.partial]).
                        if (skipped > 0) complete = false
                    } finally {
                        try {
                            db.close()
                        } catch (_: Throwable) {
                        }
                    }
                }
            } finally {
                work.deleteRecursively()
            }
            return out.put("entries", log).put("foods", foods).put("skipped", skipped).put("lost", lost)
                .put("complete", complete)
        }

        /**
         * Σημειώνει ότι το φαγητό της βλάβης [at] ξαναμπήκε ([entries] καταχωρίσεις, [foods] προϊόντα), με τον κανόνα
         * ανάγνωσης ([DbSalvage.RULES]) και αν διαβάστηκαν όλα ([complete]): μια ανάγνωση που δεν διάβασε όλα
         * ξαναγίνεται με έναν επόμενο, καλύτερο κανόνα (R8-A9-1).
         */
        fun salvageDone(context: Context, at: Long, entries: Int, foods: Int, complete: Boolean) {
            salvagedMarker(context).writeText(DbSalvage.doneText(at, entries, foods, complete))
            // Διαβάστηκαν όλα: δεν θα ξαναδιαβαστεί ποτέ, άρα οι διαγραφές που κρατήθηκαν γι' αυτό δεν χρειάζονται πια.
            if (complete) {
                try {
                    removedFile(context).delete()
                } catch (_: Throwable) {
                }
            }
        }

        /**
         * Round 8 (R8-A9-3, f4): μια καταχώριση ([kind] 'e') ή ένα προϊόν ('f') σβήστηκε. Όσο υπάρχει βλάβη της οποίας το
         * αρχείο μπορεί ακόμα να ξαναδιαβαστεί, το [id] γράφεται εδώ, ώστε να μην ξαναμπεί από το κρατημένο αρχείο ούτε σε
         * επόμενο άνοιγμα (πριν το κρατούσε μόνο η μνήμη της Flutter: αν η εφαρμογή έκλεινε πριν την επαναφορά, ο μουσακάς
         * που έσβησες ξαναγύριζε). Χωρίς βλάβη: μόνο ένας έλεγχος ύπαρξης αρχείου.
         */
        fun noteRemoved(context: Context, kind: Char, id: String) {
            try {
                val at = corruptAt(context) ?: return
                if (DbSalvage.finished(readOrNull(salvagedMarker(context)), at)) return
                val line = DbSalvage.removedLine(at, kind, id) ?: return
                removedFile(context).appendText(line)
            } catch (_: Throwable) {
            }
        }

        private fun openKept(f: java.io.File): SQLiteDatabase? {
            // Ποτέ σβήσιμο (ο προεπιλεγμένος χειριστής του Android θα έσβηνε το αρχείο)· είναι αντίγραφο του κρατημένου.
            val quiet = DatabaseErrorHandler { }
            for (flags in intArrayOf(SQLiteDatabase.OPEN_READONLY, SQLiteDatabase.OPEN_READWRITE)) {
                try {
                    return SQLiteDatabase.openDatabase(f.path, null, flags, quiet)
                } catch (_: Throwable) {
                }
            }
            return null
        }

        /**
         * Round 8 (R8-A9-1): οι γραμμές του [table] (σταθερό όνομα, όχι τιμή χρήστη) με rowid από ένα όριο και μετά, το πολύ
         * τόσες: ένα ΜΙΚΡΟ ερώτημα κάθε φορά. Οι αριθμοί μπαίνουν ως κείμενο στο SQL (είναι δικοί μας Long, όχι τιμές χρήστη),
         * ώστε η σύγκριση με το rowid να είναι αριθμητική και να χρησιμοποιεί το δέντρο του πίνακα.
         */
        private fun sqlRows(db: SQLiteDatabase, table: String) = DbSalvage.RowSource { from, limit ->
            db.rawQuery("SELECT rowid, id, json FROM $table WHERE rowid >= $from ORDER BY rowid LIMIT $limit", null).use { c ->
                val rows = ArrayList<DbSalvage.Row>()
                while (c.moveToNext()) rows.add(DbSalvage.Row(c.getLong(0), c.getString(1), c.getString(2)))
                rows
            }
        }
    }

    // Ένας πίνακας μόνο προστίθεται σε κάθε έκδοση· μια παλιότερη έκδοση της εφαρμογής ανοίγει τη βάση χωρίς σφάλμα.
    override fun onDowngrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}


    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE days (" +
                "date TEXT PRIMARY KEY, " + // «2026-10-24»
                "json TEXT NOT NULL, " +
                "updated INTEGER NOT NULL)"
        )
        createFoodTables(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Κάθε αλλαγή προσθέτει πίνακες· τίποτα δεν σβήνεται.
        if (oldVersion < 2) createFoodTables(db)
    }

    private fun createFoodTables(db: SQLiteDatabase) {
        // Ημερολόγιο φαγητού: μία γραμμή ανά καταχώριση. Το JSON κρατά και τα θρεπτικά ανά 100 g
        // όπως ήταν τη στιγμή της καταχώρισης, ώστε το ιστορικό να μην αλλάζει αν ενημερωθεί η βάση.
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS food_log (" +
                "id TEXT PRIMARY KEY, day TEXT NOT NULL, json TEXT NOT NULL, updated INTEGER NOT NULL)"
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS food_log_day ON food_log(day)")
        // Δικά μου τρόφιμα (barcode, ετικέτα, χειροκίνητα).
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS my_foods (" +
                "id TEXT PRIMARY KEY, json TEXT NOT NULL, updated INTEGER NOT NULL)"
        )
    }

    /** [{"date": "2026-10-24", "data": {...}}, ...] — αντικαθιστά όσες μέρες υπάρχουν ήδη. */
    fun save(rows: JSONArray) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            for (i in 0 until rows.length()) {
                val row = rows.optJSONObject(i) ?: continue
                val date = row.optString("date")
                val data = row.optJSONObject("data") ?: continue
                if (date.isEmpty()) continue
                val v = ContentValues()
                v.put("date", date)
                v.put("json", data.toString())
                v.put("updated", now)
                db.insertWithOnConflict("days", null, v, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Όλες οι μέρες, παλιότερη πρώτη. */
    fun loadAll(): JSONArray {
        val out = JSONArray()
        readableDatabase.rawQuery("SELECT date, json FROM days ORDER BY date", null).use { c ->
            while (c.moveToNext()) {
                val data = try {
                    JSONObject(c.getString(1))
                } catch (e: Throwable) {
                    continue
                }
                out.put(JSONObject().put("date", c.getString(0)).put("data", data))
            }
        }
        return out
    }

    // ---------- Ημερολόγιο φαγητού ----------

    fun logPut(id: String, day: String, json: String) {
        val v = ContentValues()
        v.put("id", id)
        v.put("day", day)
        v.put("json", json)
        v.put("updated", System.currentTimeMillis())
        writableDatabase.insertWithOnConflict("food_log", null, v, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun logDelete(id: String) {
        writableDatabase.delete("food_log", "id = ?", arrayOf(id))
    }

    /** Καταχωρίσεις στο [from, to] (ημερομηνίες «2026-10-24»), παλιότερη πρώτη. */
    fun logRange(from: String, to: String): JSONArray {
        val out = JSONArray()
        readableDatabase.rawQuery(
            "SELECT json FROM food_log WHERE day >= ? AND day <= ? ORDER BY day, updated", arrayOf(from, to)
        ).use { c ->
            while (c.moveToNext()) {
                try {
                    out.put(JSONObject(c.getString(0)))
                } catch (e: Throwable) {
                    // χαλασμένη γραμμή: παραλείπεται
                }
            }
        }
        return out
    }

    fun myFoodPut(id: String, json: String) {
        val v = ContentValues()
        v.put("id", id)
        v.put("json", json)
        v.put("updated", System.currentTimeMillis())
        writableDatabase.insertWithOnConflict("my_foods", null, v, SQLiteDatabase.CONFLICT_REPLACE)
    }

    /**
     * Επαναφορά από αντίγραφο (τελικός έλεγχος, Συμβούλιο 4, Γ1): όλες οι καταχωρίσεις [log] (id, μέρα, JSON) και τα
     * προϊόντα [foods] (id, JSON) σε ΜΙΑ συναλλαγή: ή γράφονται όλα ή, αν κάτι αποτύχει στη μέση, τίποτα. Πριν γράφονταν
     * ένα-ένα (μία κλήση και μία συναλλαγή το καθένα)· μια διακοπή άφηνε μισή επαναφορά.
     * Ό,τι υπάρχει ήδη στο κινητό με το ίδιο id μένει όπως είναι (CONFLICT_IGNORE): η επαναφορά μόνο προσθέτει.
     * Επιστρέφει πόσες καταχωρίσεις και πόσα προϊόντα γράφτηκαν.
     */
    fun restoreFood(log: List<Triple<String, String, String>>, foods: List<Pair<String, String>>): Pair<Int, Int> {
        val db = writableDatabase
        val now = System.currentTimeMillis()
        var entries = 0
        var products = 0
        db.beginTransaction()
        try {
            for ((id, day, json) in log) {
                val v = ContentValues()
                v.put("id", id)
                v.put("day", day)
                v.put("json", json)
                v.put("updated", now)
                if (db.insertWithOnConflict("food_log", null, v, SQLiteDatabase.CONFLICT_IGNORE) != -1L) entries++
            }
            for ((id, json) in foods) {
                val v = ContentValues()
                v.put("id", id)
                v.put("json", json)
                v.put("updated", now)
                if (db.insertWithOnConflict("my_foods", null, v, SQLiteDatabase.CONFLICT_IGNORE) != -1L) products++
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return entries to products
    }

    fun myFoodDelete(id: String) {
        writableDatabase.delete("my_foods", "id = ?", arrayOf(id))
    }

    fun myFoods(): JSONArray {
        val out = JSONArray()
        readableDatabase.rawQuery("SELECT json FROM my_foods ORDER BY updated DESC", null).use { c ->
            while (c.moveToNext()) {
                try {
                    out.put(JSONObject(c.getString(0)))
                } catch (e: Throwable) {
                }
            }
        }
        return out
    }

    fun clear() {
        writableDatabase.delete("days", null, null)
    }
}

/**
 * Χαλασμένη βάση (A7): ΠΟΤΕ διαγραφή (ο προεπιλεγμένος χειριστής του Android σβήνει το αρχείο, μαζί το ημερολόγιο
 * φαγητού και «Τα προϊόντα μου» που δεν ξαναδιαβάζονται από πουθενά). Το αρχείο μετακινείται με την ώρα στο όνομα
 * (noBackupFilesDir/corrupt), ανοίγει καινούργια βάση, η εφαρμογή δείχνει κάρτα και το Sentry μαθαίνει μόνο το είδος.
 */
private class KeepCorruptDb(private val context: Context) : DatabaseErrorHandler {
    override fun onCorruption(dbObj: SQLiteDatabase) {
        val path = dbObj.path
        // Έλεγχος 2, C8: το Android ξαναδοκιμάζει το άνοιγμα στο ΙΔΙΟ αντικείμενο μετά από εδώ· αν δεν είναι ανοιχτό
        // ακόμα, ένα close() το «κλείνει» οριστικά και το πρώτο άνοιγμα αποτυγχάνει (όπως ο DefaultDatabaseErrorHandler).
        DataRules.closeIfOpen(dbObj.isOpen) { dbObj.close() }
        val now = System.currentTimeMillis()
        try {
            if (path != null && path != ":memory:") {
                DataRules.keepCorrupt(java.io.File(path), java.io.File(context.noBackupFilesDir, "corrupt"), now)
            }
            DayStore.marker(context).writeText(now.toString())
        } catch (_: Throwable) {
        }
        ErrorQueue.report(IllegalStateException("Η βάση χάλασε· κρατήθηκε αντίγραφο"), "database")
    }
}

/**
 * Round 7 (R7-A9-1, f4): οι κανόνες της ανάγνωσης του αρχείου που κρατήθηκε μετά από βλάβη, χωρίς Android (ελέγχονται
 * σε απλό JVM). Το κρατημένο αρχείο ΔΕΝ αλλάζει ποτέ: διαβάζεται ένα αντίγραφό του.
 */
object DbSalvage {
    const val DB = "ygeia.db"

    /** Τα σημάδια στον φάκελο noBackupFilesDir (εκτός αντιγράφου Google· σβήνονται με τη «Διαγραφή όλων»). */
    const val CORRUPT = "db_corrupt"
    const val SEEN = "db_corrupt_seen"
    const val SALVAGED = "db_salvaged"

    /**
     * Αντιγράφει το κρατημένο αρχείο της βλάβης [at] από τον [dir] στον [work], με τα κανονικά ονόματα («ygeia.db»,
     * «ygeia.db-wal», «ygeia.db-journal»), ώστε η SQLite να διαβάσει και ό,τι ήταν ακόμα στο -wal. Το -shm δεν χρειάζεται
     * (ξαναφτιάχνεται). Επιστρέφει το αντίγραφο της κύριας βάσης, ή null αν δεν υπάρχει κρατημένο αρχείο.
     * Round 9 (R9-A9-1, f4): στο αντίγραφο διορθώνεται ο αριθμός σελίδων της κεφαλίδας ([fixPageCount]).
     */
    fun copyKept(dir: File, work: File, at: Long): File? {
        val main = File(dir, DataRules.corruptName(DB, at))
        if (!main.isFile) return null
        work.mkdirs()
        for (suffix in listOf("", "-wal", "-journal")) {
            val f = File(dir, DataRules.corruptName(DB + suffix, at))
            if (f.isFile) f.copyTo(File(work, DB + suffix), overwrite = true)
        }
        val copy = File(work, DB)
        fixPageCount(copy)
        return copy
    }

    /**
     * Round 9 (R9-A9-1, f4): στο ΑΝΤΙΓΡΑΦΟ [f] της χαλασμένης βάσης (ποτέ στο κρατημένο αρχείο), αν η κεφαλίδα λέει
     * περισσότερες σελίδες από όσες έχει το αρχείο (αρχείο κομμένο στο τέλος, ή ένα bit στο πεδίο των σελίδων), το πεδίο
     * ακυρώνεται και η SQLite μετρά τις σελίδες από το μέγεθος του αρχείου. Αλλιώς η SQLite αρνείται ΚΑΘΕ ερώτημα (src/btree.c,
     * lockBtree: «nPage > nPageFile» → SQLITE_CORRUPT) και δεν διαβαζόταν τίποτα, ούτε οι σελίδες που υπάρχουν. Ο αριθμός
     * σελίδων (bytes 28–31) ισχύει μόνο όταν ο μετρητής αλλαγών (24–27) είναι ίσος με το «version-valid-for» (92–95)
     * (sqlite.org/fileformat2.html, «In-header database size»)· αλλάζει μόνο το 92–95. Επιστρέφει αν άλλαξε κάτι.
     */
    fun fixPageCount(f: File): Boolean = try {
        java.io.RandomAccessFile(f, "rw").use { raf -> patchPageCount(raf) }
    } catch (_: Throwable) {
        false
    }

    private fun patchPageCount(raf: java.io.RandomAccessFile): Boolean {
        val len = raf.length()
        if (len < 100) return false
        val h = ByteArray(100)
        raf.seek(0)
        raf.readFully(h)
        if (String(h, 0, 16, Charsets.US_ASCII) != "SQLite format 3\u0000") return false
        val raw = ((h[16].toInt() and 0xff) shl 8) or (h[17].toInt() and 0xff)
        val pageSize = if (raw == 1) 65_536 else raw
        if (pageSize < 512 || (pageSize and (pageSize - 1)) != 0) return false
        val pages = u32(h, 28)
        val filePages = (len + pageSize - 1) / pageSize
        if (pages <= filePages) return false
        // Ήδη άκυρο: η SQLite μετρά ήδη από το μέγεθος του αρχείου.
        if (u32(h, 24) != u32(h, 92)) return false
        val v = (u32(h, 24) + 1) and 0xffffffffL
        raf.seek(92)
        raf.write(byteArrayOf((v ushr 24).toByte(), (v ushr 16).toByte(), (v ushr 8).toByte(), v.toByte()))
        return true
    }

    private fun u32(b: ByteArray, at: Int): Long =
        ((b[at].toLong() and 0xff) shl 24) or ((b[at + 1].toLong() and 0xff) shl 16) or
            ((b[at + 2].toLong() and 0xff) shl 8) or (b[at + 3].toLong() and 0xff)

    /**
     * Round 8 (R8-A9-1, f4): ο κανόνας ανάγνωσης του κρατημένου αρχείου. 1 = #105: ένας δρομέας για όλο τον πίνακα· στο
     * Android ο δρομέας μετρά πρώτα ΟΛΕΣ τις γραμμές (SQLiteCursor.fillWindow με countAllRows), άρα μία χαλασμένη σελίδα,
     * όπου κι αν ήταν, έκανε την ανάγνωση να μη δώσει καμία γραμμή. 2 = σε μικρά κομμάτια ([read]).
     * 3 = round 9 (f4): κεφαλίδα κομμένου αρχείου ([fixPageCount], R9-A9-1), η νεότερη γραμμή κάθε id (R9-A9-2), και
     * καμία καλή σελίδα ανάμεσα σε δύο χαλασμένες περιοχές δεν χάνεται (R9-A9-4). Μια ανάγνωση με κανόνα 2 που δεν
     * διάβασε όλα ξαναγίνεται μία φορά.
     * 4 = round 10 (R10-B6-1, g4): και όταν η χαλασμένη περιοχή φτάνει ως το τέλος του πίνακα (κομμένο αρχείο), οι καλές
     * σελίδες ανάμεσα διαβάζονται ([read], βήμα 3). Μια ανάγνωση με κανόνα 3 που δεν διάβασε όλα ξαναγίνεται μία φορά.
     */
    const val RULES = 4

    /** Γραμμές ανά ερώτημα: λίγες, ώστε ένα ερώτημα να αγγίζει μόνο λίγες σελίδες του πίνακα. */
    const val CHUNK = 64

    /** Όριο ερωτημάτων ανά πίνακα (≈ 3 εκατομμύρια γραμμές): μια παθολογική βλάβη δεν κρατά τη βάση απασχολημένη ώρες. */
    const val MAX_QUERIES = 50_000

    /**
     * Round 9 (R9-A9-4, f4): μετά από ένα σημείο που δεν διαβάζεται, τόσα rowid εξετάζονται ένα-ένα (μια σελίδα έχει
     * ≈ 3 καταχωρίσεις): το τέλος μιας μικρής χαλασμένης περιοχής βρίσκεται ακριβώς, και όταν ακολουθεί δεύτερη λίγο πιο κάτω.
     */
    const val GAP = 64

    /**
     * Round 9 (R9-A9-4, f4): πόσα rowid, το πολύ, εξετάζονται ένα-ένα ανάμεσα σε μια μεγάλη χαλασμένη περιοχή και στο
     * σημείο που βρήκαν τα διπλάσια βήματα (αυτά «πηδούν» πάνω από καλές σελίδες ανάμεσα σε δύο χαλασμένες περιοχές).
     */
    const val BACKFILL = 8_192

    /**
     * Το σημάδι «έγινε»: ώρα της βλάβης, καταχωρίσεις και προϊόντα που ξαναμπήκαν, κανόνας ανάγνωσης ([RULES]) και αν
     * διαβάστηκαν όλα (1) ή όχι (0).
     */
    fun doneText(at: Long, entries: Int, foods: Int, complete: Boolean): String =
        "$at $entries $foods $RULES ${if (complete) 1 else 0}"

    /**
     * (καταχωρίσεις, προϊόντα) αν η επαναφορά της βλάβης [at] έγινε και δεν χρειάζεται να ξαναγίνει· αλλιώς (άλλη βλάβη,
     * χαλασμένο, κανένα) null. Round 8 (R8-A9-1): το σημάδι του #105 («ώρα καταχωρίσεις προϊόντα», κανόνας 1) δεν μετρά:
     * εκείνη η ανάγνωση μπορεί να μη διάβασε τίποτα από το αρχείο, άρα ξαναγίνεται μία φορά (το «restorePut» δεν γράφει
     * δεύτερη φορά ό,τι υπάρχει ήδη). Μια ανάγνωση που δεν διάβασε όλα ξαναγίνεται όταν ο κανόνας γίνει νεότερος.
     * Round 9 (R9-A9-3): εκτός αν τότε ξαναμπήκαν ΚΑΙ καταχωρίσεις ΚΑΙ προϊόντα ([oldDone]): έγινε.
     */
    fun parseDone(text: String?, at: Long): Pair<Int, Int>? {
        val p = text?.trim()?.split(' ') ?: return null
        if (p.size == 3) {
            val old = oldDone(text, at)
            return if (old.first && old.second) p[1].toInt() to p[2].toInt() else null
        }
        if (p.size != 5 || p[0].toLongOrNull() != at) return null
        val entries = p[1].toIntOrNull() ?: return null
        val foods = p[2].toIntOrNull() ?: return null
        val rules = p[3].toIntOrNull() ?: return null
        val complete = when (p[4]) {
            "1" -> true
            "0" -> false
            else -> return null
        }
        if (!complete && rules < RULES) return null
        return entries to foods
    }

    /** Η ανάγνωση της βλάβης [at] τελείωσε με ΟΛΑ (δεν θα ξαναγίνει ποτέ, με κανέναν κανόνα). */
    fun finished(text: String?, at: Long): Boolean {
        val p = text?.trim()?.split(' ') ?: return false
        if (p.size == 3) return oldDone(text, at).let { it.first && it.second }
        return p.size == 5 && p[0].toLongOrNull() == at && p[3].toIntOrNull() != null && p[4] == "1"
    }

    /**
     * Round 9 (R9-A9-3, f4): με το σημάδι του #105 («ώρα καταχωρίσεις προϊόντα») για τη βλάβη [at], ποιοι πίνακες
     * ξαναμπήκαν ΤΟΤΕ: (καταχωρίσεις, προϊόντα). Αυτοί δεν ξαναδιαβάζονται: ό,τι έσβησε ο χρήστης μετά από εκείνη την
     * επαναφορά δεν είναι στη λίστα διαγραφών (το #105 δεν την είχε) και θα ξαναέμπαινε. Η ανάγνωση του #105 ήταν «όλα ή
     * τίποτα» ανά πίνακα (ο δρομέας του Android μετρά πρώτα όλες τις γραμμές), άρα «τότε ξαναμπήκαν > 0» σημαίνει ότι
     * διαβάστηκε όλος. Ένας πίνακας με 0 (π.χ. η ανάγνωση απέτυχε) ξαναδιαβάζεται. Εξαίρεση που μένει: βλάβη που βρέθηκε
     * ενώ η εφαρμογή ήταν ανοιχτή, όπου οι καταχωρίσεις των 90 ημερών της μνήμης μετρούν κι αυτές· τότε όσες ήταν μόνο
     * στο αρχείο και πιο παλιές από 90 μέρες δεν ξαναδιαβάζονται (μια παλιά καταχώριση που λείπει είναι λιγότερο κακό από
     * μια διαγραμμένη που ξαναμπαίνει σε πρόσφατη μέρα, με λάθος θερμίδες). Άλλο σημάδι: (false, false).
     */
    fun oldDone(text: String?, at: Long): Pair<Boolean, Boolean> {
        val p = text?.trim()?.split(' ') ?: return false to false
        if (p.size != 3 || p[0].toLongOrNull() != at) return false to false
        return ((p[1].toIntOrNull() ?: 0) > 0) to ((p[2].toIntOrNull() ?: 0) > 0)
    }

    /**
     * Round 9 (R9-A9-B1, f4): η επαναφορά της βλάβης [at] έγινε, αλλά κάτι από το κρατημένο αρχείο δεν διαβάστηκε
     * (σημάδι «… 0»: σελίδες που δεν διαβάζονται, αρχείο που δεν ανοίγει, γραμμές χαλασμένες). Η κάρτα το λέει.
     */
    fun partial(text: String?, at: Long): Boolean {
        val p = text?.trim()?.split(' ') ?: return false
        return p.size == 5 && p[0].toLongOrNull() == at && p[3].toIntOrNull() != null && p[4] == "0"
    }

    /** Round 8 (R8-A9-2): η κάρτα της βλάβης [at] έκλεισε ([text]: το περιεχόμενο του σημαδιού «έκλεισε»). */
    fun isSeen(text: String?, at: Long): Boolean = text?.trim()?.toLongOrNull() == at

    private fun textOf(f: File): String? = try {
        f.takeIf { it.isFile }?.readText()
    } catch (_: Throwable) {
        null
    }

    /** Η ώρα (ms) της βλάβης της βάσης που κρατήθηκε, από τα σημάδια του [dir] (noBackupFilesDir)· null: καμία. */
    fun corruptAt(dir: File): Long? = textOf(File(dir, CORRUPT))?.trim()?.toLongOrNull()

    /** Round 8 (R8-A9-2): «Εντάξει» στην κάρτα της βλάβης [at]: γράφει μόνο «η κάρτα έκλεισε» ([status] → «seen»). */
    fun markSeen(dir: File, at: Long) {
        try {
            File(dir, SEEN).writeText(at.toString())
        } catch (_: Throwable) {
        }
    }

    /**
     * Round 9 (R9-A12-2, f4): η απάντηση του «dbStatus» της γέφυρας, από τα σημάδια του [dir] (noBackupFilesDir):
     * {"ok", "corrupt": ώρα της βλάβης ή null, "seen": αν η κάρτα της έκλεισε, "partial": αν η επαναφορά δεν διάβασε όλα}.
     * Καθαρή συνάρτηση (ελέγχεται σε JVM με προσωρινό φάκελο), ώστε η γέφυρα να μην έχει δική της λογική.
     */
    fun status(dir: File): JSONObject {
        val at = corruptAt(dir)
        val seen = at != null && isSeen(textOf(File(dir, SEEN)), at)
        val notAll = at != null && partial(textOf(File(dir, SALVAGED)), at)
        return JSONObject().put("ok", true).put("corrupt", at ?: JSONObject.NULL).put("seen", seen).put("partial", notAll)
    }

    /**
     * Round 8 (R8-A9-3): μία γραμμή «ώρα είδος id» για ό,τι σβήστηκε μετά από τη βλάβη [at] ([kind] 'e' καταχώριση, 'f'
     * προϊόν). null για id που δεν γράφεται σωστά σε μία γραμμή (κενό ή με αλλαγή γραμμής).
     */
    fun removedLine(at: Long, kind: Char, id: String): String? =
        if (id.isEmpty() || id.contains('\n') || id.contains('\r') || (kind != 'e' && kind != 'f')) null else "$at $kind $id\n"

    /**
     * (καταχωρίσεις, προϊόντα) που σβήστηκαν μετά από τη βλάβη [at]. Μόνο ολόκληρες γραμμές (με «\n» στο τέλος): μια
     * γραμμή που κόπηκε στη μέση της εγγραφής δεν εξαιρεί λάθος id. Γραμμές άλλης βλάβης αγνοούνται.
     */
    fun parseRemoved(text: String?, at: Long): Pair<Set<String>, Set<String>> {
        val entries = HashSet<String>()
        val foods = HashSet<String>()
        if (text != null) {
            val lines = text.split('\n')
            // Το τελευταίο κομμάτι δεν έχει «\n» μετά: είναι κενό ή μισή γραμμή.
            for (line in lines.dropLast(1)) {
                val p = line.split(' ', limit = 3)
                if (p.size != 3 || p[0].toLongOrNull() != at || p[2].isEmpty()) continue
                when (p[1]) {
                    "e" -> entries.add(p[2])
                    "f" -> foods.add(p[2])
                }
            }
        }
        return entries to foods
    }

    /** Μία γραμμή του πίνακα όπως διαβάστηκε. */
    class Row(val rowid: Long, val id: String?, val json: String?)

    /**
     * Οι γραμμές με rowid ≥ [from], με σειρά rowid, το πολύ [limit]. Πετά αν το ερώτημα συναντήσει χαλασμένη σελίδα.
     * «≥» και όχι «>»: η SQLite ψάχνει τη σελίδα του ίδιου του ορίου, άρα ένα όριο ακριβώς μετά από μια χαλασμένη σελίδα
     * διαβάζει από την επόμενη (με «>» θα κατέβαινε στη χαλασμένη και θα χανόταν και η πρώτη γραμμή μετά από αυτήν).
     */
    fun interface RowSource {
        fun rows(from: Long, limit: Int): List<Row>
    }

    /**
     * [skipped]: γραμμές που δεν διαβάστηκαν σωστά (χωρίς id ή όχι JSON)· [lost]: σημεία του πίνακα που δεν διαβάστηκαν·
     * [complete]: διαβάστηκαν όλα τα σημεία του πίνακα.
     */
    data class Read(val skipped: Int, val lost: Int, val complete: Boolean)

    /**
     * Round 8 (R8-A9-1, f4): διαβάζει όλο τον πίνακα σε κομμάτια των [chunk] γραμμών (σειρά rowid), ώστε μια χαλασμένη
     * σελίδα να χάνει μόνο τις δικές της γραμμές. Σε σφάλμα: μία-μία ως το χαλασμένο σημείο· μετά βρίσκει το πρώτο όριο
     * από όπου ξαναδιαβάζεται και συνεχίζει. Κάθε id μία φορά στο [out], όχι όσα είναι στο [removed]. Οι πίνακες της
     * εφαρμογής δεν ορίζουν ποτέ rowid: η SQLite δίνει 1, 2, … (αρχή: rowid ≥ 0).
     *
     * Round 9 (f4):
     * - R9-A9-2: ίδιο id σε δύο γραμμές (μια σελίδα έμεινε με το παλιό της περιεχόμενο μετά από διόρθωση) → μετρά η
     *   γραμμή με το ΜΕΓΑΛΥΤΕΡΟ rowid: κάθε αλλαγή γράφεται με «INSERT OR REPLACE», που σβήνει την παλιά γραμμή και δίνει
     *   στη νέα rowid μεγαλύτερο από όλα όσα υπάρχουν. Πριν κρατιόταν η πρώτη, δηλαδή η εκδοχή ΠΡΙΝ από τη διόρθωση
     *   (π.χ. 300 g αντί για 150 g). Αν η νεότερη δεν διαβάζεται, δεν μπαίνει η παλιά στη θέση της (μετρά στα [Read.skipped]).
     * - R9-A9-4: μετά από σημείο που δεν διαβάζεται, πρώτα τα επόμενα [GAP] rowid ένα-ένα· πιο πέρα διπλάσια βήματα ως ένα
     *   σημείο που διαβάζεται και δυαδική αναζήτηση για το όριό του, και μετά ([BACKFILL]) ένα-ένα όσα rowid πήδηξαν τα
     *   βήματα, ώστε να βρεθεί το ΠΡΩΤΟ σημείο που διαβάζεται. Πριν, μια καλή σελίδα ανάμεσα σε δύο χαλασμένες περιοχές
     *   χανόταν όταν ένα βήμα έπεφτε στη δεύτερη.
     * - R10-B6-1 (round 10, g4): το ίδιο ένα-ένα και όταν ΚΑΝΕΝΑ βήμα δεν διαβάζεται ως το Long.MAX_VALUE (χαλασμένη
     *   περιοχή ως το τέλος του πίνακα, π.χ. κομμένο αρχείο). Πριν τελείωνε εκεί και χάνονταν οι καλές σελίδες ανάμεσα.
     *   Κόστος: το πολύ ≈ [GAP] + 64 + [BACKFILL] ερωτήματα στο τέλος του πίνακα (ελεγμένο σε πραγματική SQLite 3.53).
     */
    fun read(source: RowSource, removed: Set<String>, out: JSONArray, chunk: Int = CHUNK, maxQueries: Int = MAX_QUERIES): Read {
        // id → (rowid, γραμμή· null αν δεν διαβάζεται), με τη σειρά που πρωτοβρέθηκε κάθε id.
        val best = LinkedHashMap<String, Pair<Long, JSONObject?>>()
        var skipped = 0
        var lost = 0
        var queries = 0
        var from = 0L

        fun ask(start: Long, limit: Int): List<Row>? {
            queries++
            return try {
                source.rows(start, limit)
            } catch (_: Throwable) {
                null
            }
        }

        fun take(r: Row) {
            val id = r.id
            if (id == null) {
                skipped++
                return
            }
            if (id in removed) return
            val prev = best[id]
            if (prev != null && prev.first > r.rowid) return
            val row = try {
                JSONObject(r.json ?: "")
            } catch (_: Throwable) {
                null
            }
            best[id] = r.rowid to row
        }

        fun done(complete: Boolean): Read {
            for (v in best.values) {
                val row = v.second
                if (row == null) skipped++ else out.put(row)
            }
            return Read(skipped, lost, complete)
        }

        // Το επόμενο όριο μετά από τη γραμμή [rowid]: πάντα μπροστά (και σε χαλασμένη σελίδα με rowid εκτός σειράς).
        fun next(rowid: Long): Long = maxOf(if (rowid == Long.MAX_VALUE) rowid else rowid + 1, if (from == Long.MAX_VALUE) from else from + 1)

        // [a] + [b] (και τα δύο ≥ 0) χωρίς υπερχείλιση: το πολύ Long.MAX_VALUE.
        fun plus(a: Long, b: Long): Long = if (b >= Long.MAX_VALUE - a) Long.MAX_VALUE else a + b

        while (queries < maxQueries) {
            val rows = ask(from, chunk)
            if (rows != null) {
                for (r in rows) take(r)
                if (rows.size < chunk) return done(lost == 0)
                from = next(rows.last().rowid)
                continue
            }
            // Χαλασμένο σημείο μέσα στις επόμενες γραμμές: μία-μία ως αυτό.
            var bad = false
            for (i in 0 until chunk) {
                val one = ask(from, 1)
                if (one == null) {
                    bad = true
                    break
                }
                if (one.isEmpty()) return done(lost == 0)
                take(one[0])
                from = next(one[0].rowid)
            }
            if (!bad) continue
            // Η γραμμή στο [from] δεν διαβάζεται: το ΠΡΩΤΟ όριο x > from από όπου διαβάζεται το «rowid ≥ x».
            lost++
            val start = from
            // (1) Τα επόμενα GAP rowid ένα-ένα.
            var near = -1L
            for (i in 1..GAP) {
                if (queries >= maxQueries) return done(false)
                val x = plus(start, i.toLong())
                if (ask(x, 1) != null) {
                    near = x
                    break
                }
                // Τίποτα δεν διαβάζεται ως το τέλος.
                if (x == Long.MAX_VALUE) return done(false)
            }
            if (near >= 0) {
                from = near
                continue
            }
            // (2) Πιο πέρα: διπλάσια βήματα ως ένα σημείο που διαβάζεται, μετά δυαδική αναζήτηση για το όριό του.
            var fail = plus(start, GAP.toLong())
            var ok = Long.MAX_VALUE
            var found = false
            var step = 2L * GAP
            while (true) {
                if (queries >= maxQueries) return done(false)
                val x = plus(start, step)
                if (ask(x, 1) != null) {
                    ok = x
                    found = true
                    break
                }
                // Round 10 (R10-B6-1, g4): κανένα βήμα δεν διαβάζεται ως το τέλος (το δεξιότερο φύλλο χαλασμένο ή κομμένο:
                // ένα όριο μετά από όλες τις γραμμές κατεβαίνει σε αυτό). Δεν τελειώνει εδώ: οι καλές σελίδες ανάμεσα
                // (συχνά οι ΝΕΟΤΕΡΕΣ γραμμές, σε σελίδες που ελευθερώθηκαν νωρίτερα στο αρχείο) βρίσκονται ένα-ένα στο (3).
                if (x == Long.MAX_VALUE) break
                fail = x
                step = if (step >= Long.MAX_VALUE / 2) Long.MAX_VALUE else step * 2
            }
            while (found && ok - fail > 1 && queries < maxQueries) {
                val m = fail + (ok - fail) / 2
                if (ask(m, 1) != null) ok = m else fail = m
            }
            // (3) Όσα rowid πήδηξαν τα βήματα, ένα-ένα από αριστερά: το πρώτο που διαβάζεται, αν υπάρχει πριν από το [ok].
            var far = -1L
            var x = plus(start, GAP.toLong())
            var n = 0
            while (n < BACKFILL && queries < maxQueries) {
                x++
                if (x >= ok) break
                n++
                if (ask(x, 1) != null) {
                    far = x
                    break
                }
            }
            // Τίποτα δεν διαβάζεται ως το τέλος (ούτε βήμα ούτε ένα-ένα): τελείωσε, χωρίς να διαβαστούν όλα.
            if (far < 0 && !found) return done(false)
            from = if (far >= 0) far else ok
        }
        return done(false)
    }
}
