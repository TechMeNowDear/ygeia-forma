package gr.ygeiaforma.ygeia_forma

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore

/**
 * Αναφορά PDF χωρίς βιβλιοθήκες: οι σελίδες ζωγραφίζονται στη Flutter (ίδια εμφάνιση με την εφαρμογή),
 * έρχονται εδώ ως PNG και μπαίνουν σε σελίδες A4 με το PdfDocument του Android.
 * Αποθήκευση στις Λήψεις μέσω MediaStore (χωρίς άδεια αποθήκευσης).
 */
object PdfExporter {
    // A4 σε στιγμές PDF (1/72 ίντσας).
    private const val A4_W = 595
    private const val A4_H = 842

    fun save(context: Context, pages: List<ByteArray>, fileName: String): Uri {
        val doc = PdfDocument()
        try {
            val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
            pages.forEachIndexed { i, png ->
                val page = doc.startPage(PdfDocument.PageInfo.Builder(A4_W, A4_H, i + 1).create())
                val bmp = BitmapFactory.decodeByteArray(png, 0, png.size)
                    ?: throw IllegalStateException("Σελίδα ${i + 1}: άκυρη εικόνα")
                page.canvas.drawBitmap(
                    bmp,
                    Rect(0, 0, bmp.width, bmp.height),
                    RectF(0f, 0f, A4_W.toFloat(), A4_H.toFloat()),
                    paint,
                )
                bmp.recycle()
                doc.finishPage(page)
            }

            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Δεν δημιουργήθηκε αρχείο στις Λήψεις")
            try {
                resolver.openOutputStream(uri)?.use { doc.writeTo(it) }
                    ?: throw IllegalStateException("Δεν άνοιξε το αρχείο για γράψιμο")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Throwable) {
                resolver.delete(uri, null, null)
                throw e
            }
            return uri
        } finally {
            doc.close()
        }
    }

    fun share(context: Context, uri: Uri) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, "Αποστολή αναφοράς"))
    }

    fun open(context: Context, uri: Uri) {
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/pdf")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(view, "Άνοιγμα αναφοράς"))
    }
}
