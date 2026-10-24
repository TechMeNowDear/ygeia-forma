package gr.ygeiaforma.ygeia_forma

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject

/**
 * Τοπική μνήμη: μία γραμμή ανά μέρα με τη σύνοψή της (JSON), στη βάση SQLite του Android.
 * Μικρό μέγεθος (λίγα KB τον χρόνο), καμία εξωτερική βιβλιοθήκη.
 * Οι συνόψεις υπολογίζονται στη Flutter πλευρά· εδώ μόνο αποθηκεύονται.
 */
class DayStore private constructor(context: Context) : SQLiteOpenHelper(context, "ygeia.db", null, 2) {

    companion object {
        @Volatile private var instance: DayStore? = null

        /** Μία σύνδεση με τη βάση για όλη την εφαρμογή. */
        fun get(context: Context): DayStore =
            instance ?: synchronized(this) {
                instance ?: DayStore(context.applicationContext).also { instance = it }
            }
    }


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
