package gr.ygeiaforma.ygeia_forma

import java.io.File
import java.io.FileOutputStream

/**
 * Οι παλμοί κάθε προπόνησης σε δικό της μικρό αρχείο, filesDir/hr/<id>.json (έλεγχος 9/11, V-A-02): όχι μέσα στο
 * training.json, που γράφεται σε κάθε ✓. Γράφονται μία φορά και διαβάζονται μόνο όταν ανοίγει η σύνοψη.
 * Χωρίς τύπους Android, για να ελέγχεται σε απλό JVM.
 */
object HrFiles {
    const val DIR = "hr"

    /** Μόνο απλά ονόματα (ids προπονήσεων): ποτέ «..», «/» ή κάτι που βγαίνει από τον φάκελο. */
    fun validId(id: String): Boolean = id.isNotEmpty() && id.length <= 120 && id.all { it.isLetterOrDigit() || it == '-' || it == '_' || it == '.' } &&
        id != "." && id != ".." && !id.endsWith(".tmp")

    private fun file(dir: File, id: String) = File(dir, "$id.json")

    /** («ok», κείμενο), («missing», null) ή («error», null): το κινητό δεν γράφει πάνω σε αρχείο που δεν διάβασε. */
    fun readState(dir: File, id: String): Pair<String, String?> {
        if (!validId(id)) return "missing" to null
        val f = file(dir, id)
        return try {
            if (!f.exists()) "missing" to null else "ok" to f.readText()
        } catch (_: Throwable) {
            "error" to null
        }
    }

    fun read(dir: File, id: String): String? {
        if (!validId(id)) return null
        val f = file(dir, id)
        return try {
            if (f.isFile) f.readText() else null
        } catch (_: Throwable) {
            null
        }
    }

    /** Ατομική εγγραφή (προσωρινό αρχείο + μετονομασία, με fsync). */
    @Synchronized
    fun write(dir: File, id: String, text: String): Boolean {
        if (!validId(id)) return false
        return try {
            dir.mkdirs()
            val f = file(dir, id)
            val tmp = File(dir, "$id.json.${System.nanoTime()}.tmp")
            FileOutputStream(tmp).use { out ->
                out.write(text.toByteArray(Charsets.UTF_8))
                out.flush()
                out.fd.sync()
            }
            val ok = tmp.renameTo(f)
            if (!ok) tmp.delete()
            ok
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Αρχείο που δεν διαβάζεται: μετονομάζεται σε «<id>.json.bad» (ή «<id>.json.<ώρα>.bad» αν υπάρχει ήδη) και κρατιέται·
     * ποτέ δεν σβήνεται και ποτέ δεν γράφεται από πάνω (έλεγχος του #91, S1). Το νέο όνομα, ή null αν δεν έγινε.
     */
    @Synchronized
    fun setAside(dir: File, id: String, now: Long = System.currentTimeMillis()): String? {
        if (!validId(id)) return null
        val f = file(dir, id)
        if (!f.exists()) return null
        var bad = File(dir, "$id.json.bad")
        if (bad.exists()) bad = File(dir, "$id.json.$now.bad")
        return try {
            if (f.renameTo(bad)) bad.name else null
        } catch (_: Throwable) {
            null
        }
    }

    /** true και όταν δεν υπήρχε. */
    @Synchronized
    fun delete(dir: File, id: String): Boolean {
        if (!validId(id)) return false
        val f = file(dir, id)
        return !f.exists() || f.delete()
    }

    /** Τα ids που έχουν αρχείο. Καθαρίζει και προσωρινά αρχεία εγγραφών που διακόπηκαν (παλαιότερα από 1 ώρα). */
    fun list(dir: File, now: Long = System.currentTimeMillis()): List<String> {
        val files = dir.listFiles() ?: return emptyList()
        val out = mutableListOf<String>()
        for (f in files) {
            val n = f.name
            if (n.endsWith(".tmp")) {
                if (f.lastModified() < now - 3_600_000L) f.delete()
                continue
            }
            if (n.endsWith(".json")) {
                val id = n.removeSuffix(".json")
                if (validId(id)) out.add(id)
            }
        }
        return out.sorted()
    }
}
