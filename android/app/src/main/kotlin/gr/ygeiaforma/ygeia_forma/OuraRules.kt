package gr.ygeiaforma.ygeia_forma

/**
 * Οι κανόνες του Oura στο Android χωρίς τύπους Android (Intent, Uri), ώστε να ελέγχονται σε απλό JVM
 * (android/app/src/test). Το OuraBridge τους καλεί.
 */
object OuraRules {
    const val SCHEME = "ygeiaforma"
    const val HOST = "oura-callback"
    const val HTTPS_HOST = "ygeia-forma.netlify.app"
    const val HTTPS_PATH = "/oura/callback"

    /** Τα αρχεία μας (στο filesDir ή στο noBackupFilesDir/oura). Το προσωρινό είναι «όνομα.<αριθμός>.tmp». */
    val OWN_FILES = listOf(
        "oura_nights.json", "sources.json", "sources_log.json",
        "oura_tokens.bin", "oura_pending.bin", "oura_connecting.bin",
    )

    /** Μόνο οι δύο ακριβείς μορφές: https://ygeia-forma.netlify.app/oura/callback ή ygeiaforma://oura-callback. */
    fun isCallback(scheme: String?, host: String?, port: Int, path: String?, userInfo: String?): Boolean {
        if (userInfo != null || port != -1) return false
        return when (scheme) {
            "https" -> host == HTTPS_HOST && path == HTTPS_PATH
            SCHEME -> host == HOST && (path.isNullOrEmpty() || path == "/")
            else -> false
        }
    }

    /** Προσωρινό αρχείο από δική μας εγγραφή που διακόπηκε (μόνο αυτά σβήνονται στην εκκίνηση). */
    fun isOwnTmp(name: String): Boolean =
        name.endsWith(".tmp") && OWN_FILES.any { name.startsWith("$it.") && name.length > it.length + ".tmp".length + 1 }
}
