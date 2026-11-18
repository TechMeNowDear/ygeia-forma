package gr.ygeiaforma.ygeia_forma

import android.content.Context
import org.xmlpull.v1.XmlPullParser
import java.io.File

/**
 * 18/11: πόσα bytes πιάνουν τα αρχεία που πάνε στο αντίγραφο Google (κανόνες «cloud-backup» του
 * data_extraction_rules.xml). Το Android σταματά το αντίγραφο ΣΙΩΠΗΛΑ πάνω από τα 25 MB· ο μετρητής το δείχνει
 * από πριν. Διαβάζει τους ίδιους τους κανόνες, ώστε να μένει πάντα σε συμφωνία με αυτούς.
 * Μόνο μεγέθη αρχείων (stat): χωρίς ανάγνωση περιεχομένου, γρήγορο.
 */
object CloudBackupSize {
    /** -1 αν δεν διαβάστηκαν οι κανόνες. */
    fun bytes(context: Context): Long {
        val id = context.resources.getIdentifier("data_extraction_rules", "xml", context.packageName)
        if (id == 0) return -1
        var total = 0L
        var inCloud = false
        val parser = context.resources.getXml(id)
        try {
            var ev = parser.eventType
            while (ev != XmlPullParser.END_DOCUMENT) {
                if (ev == XmlPullParser.START_TAG) {
                    when (parser.name) {
                        "cloud-backup" -> inCloud = true
                        "include" -> if (inCloud) {
                            val domain = parser.getAttributeValue(null, "domain") ?: ""
                            val path = parser.getAttributeValue(null, "path") ?: ""
                            val f = fileFor(context, domain, path)
                            if (f != null) total += sizeOf(f)
                        }
                    }
                } else if (ev == XmlPullParser.END_TAG && parser.name == "cloud-backup") {
                    inCloud = false
                }
                ev = parser.next()
            }
        } finally {
            parser.close()
        }
        return total
    }

    private fun fileFor(context: Context, domain: String, path: String): File? {
        if (path.isEmpty() || path.contains("..")) return null
        return when (domain) {
            "database" -> context.getDatabasePath(path)
            "file" -> File(context.filesDir, path)
            "sharedpref" -> File(File(context.dataDir, "shared_prefs"), path)
            else -> null
        }
    }

    private fun sizeOf(f: File): Long = when {
        f.isFile -> f.length()
        f.isDirectory -> f.listFiles()?.sumOf { sizeOf(it) } ?: 0L
        else -> 0L
    }
}
