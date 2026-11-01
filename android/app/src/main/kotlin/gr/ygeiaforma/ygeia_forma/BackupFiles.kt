package gr.ygeiaforma.ygeia_forma

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore

/**
 * Αντίγραφο ασφαλείας (JSON) στις Λήψεις μέσω MediaStore, χωρίς άδεια αποθήκευσης,
 * και ανάγνωση αρχείου που διάλεξε ο χρήστης (το ανοίγει η MainActivity με τον επιλογέα του συστήματος).
 */
object BackupFiles {
    fun save(context: Context, json: String, fileName: String): Uri {
        val resolver = context.contentResolver
        // «.gz»: συμπιεσμένο (περίπου 10 φορές μικρότερο), ώστε ακόμα κι ένα αντίγραφο χρόνων να μένει μικρό.
        val gz = fileName.endsWith(".gz")
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, if (gz) "application/gzip" else "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Δεν δημιουργήθηκε αρχείο στις Λήψεις")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                if (gz) java.util.zip.GZIPOutputStream(out).use { it.write(json.toByteArray(Charsets.UTF_8)) }
                else out.write(json.toByteArray(Charsets.UTF_8))
            } ?: throw IllegalStateException("Δεν άνοιξε το αρχείο για γράψιμο")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Throwable) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri
    }

    /** Το όνομα που πήρε τελικά το αρχείο (αν υπήρχε ήδη, το σύστημα βάζει «(1)»). */
    fun displayName(context: Context, uri: Uri): String? =
        try {
            context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (e: Throwable) {
            null
        }

    fun read(context: Context, uri: Uri): String {
        // Όριο ασφαλείας: ένα αντίγραφο χρόνων είναι λίγα MB· κάτι πολύ μεγαλύτερο δεν είναι δικό μας.
        // Διαβάζεται κομμάτι-κομμάτι, ώστε ένα τεράστιο αρχείο να σταματά πριν γεμίσει τη μνήμη.
        // Όριο μετά την αποσυμπίεση (ένα αντίγραφο πολλών ετών είναι λίγες δεκάδες MB το πολύ).
        val limit = 100 * 1024 * 1024
        val bytes = context.contentResolver.openInputStream(uri)?.use { raw ->
            // Συμπιεσμένο (gzip, ξεκινά με 1f 8b) ή απλό JSON (τα αντίγραφα πριν από την έκδοση 61).
            val buffered = java.io.BufferedInputStream(raw)
            buffered.mark(2)
            val b1 = buffered.read()
            val b2 = buffered.read()
            buffered.reset()
            val input: java.io.InputStream =
                if (b1 == 0x1f && b2 == 0x8b) java.util.zip.GZIPInputStream(buffered) else buffered
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(64 * 1024)
            var total = 0
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                total += n
                if (total > limit) throw IllegalStateException("Πολύ μεγάλο αρχείο")
                out.write(buf, 0, n)
            }
            out.toByteArray()
        } ?: throw IllegalStateException("Δεν άνοιξε το αρχείο")
        return String(bytes, Charsets.UTF_8)
    }

    fun share(context: Context, uri: Uri) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, "Αποστολή αντιγράφου"))
    }
}
