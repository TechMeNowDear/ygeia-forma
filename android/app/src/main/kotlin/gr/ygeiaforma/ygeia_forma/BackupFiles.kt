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
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Δεν δημιουργήθηκε αρχείο στις Λήψεις")
        try {
            resolver.openOutputStream(uri)?.use { it.write(json.toByteArray(Charsets.UTF_8)) }
                ?: throw IllegalStateException("Δεν άνοιξε το αρχείο για γράψιμο")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Throwable) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri
    }

    fun read(context: Context, uri: Uri): String {
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Δεν άνοιξε το αρχείο")
        // Όριο ασφαλείας: ένα αντίγραφο χρόνων είναι λίγα MB· κάτι πολύ μεγαλύτερο δεν είναι δικό μας.
        if (bytes.size > 50 * 1024 * 1024) throw IllegalStateException("Πολύ μεγάλο αρχείο")
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
