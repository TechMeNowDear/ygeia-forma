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
class DayStore(context: Context) : SQLiteOpenHelper(context, "ygeia.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE days (" +
                "date TEXT PRIMARY KEY, " + // «2026-10-24»
                "json TEXT NOT NULL, " +
                "updated INTEGER NOT NULL)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Πρώτη έκδοση· οι μελλοντικές αλλαγές θα προστίθενται εδώ χωρίς να σβήνονται δεδομένα.
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

    fun clear() {
        writableDatabase.delete("days", null, null)
    }
}
