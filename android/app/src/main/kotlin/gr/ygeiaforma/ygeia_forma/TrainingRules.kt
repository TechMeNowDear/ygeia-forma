package gr.ygeiaforma.ygeia_forma

/**
 * Κανόνες της προπόνησης στο κινητό χωρίς τύπους Android, ώστε να ελέγχονται σε απλό JVM (android/app/src/test).
 * Τελικός έλεγχος, Συμβούλιο 5 (U-2): το διάλειμμα.
 */
object TrainingRules {
    /** Το πολύ τόσο μακριά μπαίνει το ξυπνητήρι ενός διαλείμματος (το πρόγραμμα δέχεται ως 10′· τα «+30″» το μεγαλώνουν). */
    const val MAX_REST_MS = 60 * 60 * 1000L

    /**
     * Πότε χτυπά το τέλος του διαλείμματος, σε χρόνο από την εκκίνηση του κινητού (SystemClock.elapsedRealtime, που
     * μετρά και όσο το κινητό κοιμάται): τώρα [nowElapsed] + όσα χιλιοστά μένουν [left]. Αρνητικό ή παράλογα μεγάλο
     * [left] (χαλασμένη ώρα) δεν δίνει ποτέ ξυπνητήρι στο παρελθόν ή σε μέρες από τώρα.
     */
    fun restTrigger(nowElapsed: Long, left: Long): Long = nowElapsed + left.coerceIn(0L, MAX_REST_MS)
}
