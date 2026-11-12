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

    /**
     * Πόσο άργησε ως τώρα το «τέλος διαλείμματος» σε αυτό το κινητό (13/11): το μετρά το ίδιο το κινητό, κάθε φορά που
     * χτυπά, και μπαίνει στην «Αναφορά για έλεγχο». Έτσι η απόφαση για την άδεια «Ξυπνητήρια και υπενθυμίσεις» βγαίνει από
     * αριθμούς. [count]: πόσες φορές χτύπησε· [sumMs], [maxMs], [lastMs]: καθυστέρηση σε χιλιοστά· [over2s]: πόσες φορές
     * άργησε πάνω από 2 δευτερόλεπτα· [alarms]: πόσες φορές χτύπησε από το ξυπνητήρι (οι υπόλοιπες: από τον χρονοδιακόπτη).
     */
    class RestLate(
        val count: Int = 0,
        val sumMs: Long = 0,
        val maxMs: Long = 0,
        val lastMs: Long = 0,
        val over2s: Int = 0,
        val alarms: Int = 0,
    ) {
        /** Μία ακόμα φορά. Αρνητική καθυστέρηση (χτύπησε λίγο νωρίτερα) μετρά 0· παράλογα μεγάλη κόβεται στη μία ώρα. */
        fun add(lateMs: Long, viaAlarm: Boolean): RestLate {
            val l = lateMs.coerceIn(0L, MAX_REST_MS)
            return RestLate(
                count = if (count == Int.MAX_VALUE) count else count + 1,
                sumMs = if (sumMs > Long.MAX_VALUE - l) sumMs else sumMs + l,
                maxMs = maxOf(maxMs, l),
                lastMs = l,
                over2s = over2s + if (l > 2000 && over2s < Int.MAX_VALUE) 1 else 0,
                alarms = alarms + if (viaAlarm && alarms < Int.MAX_VALUE) 1 else 0,
            )
        }

        val avgMs: Long get() = if (count <= 0) 0 else sumMs / count

        fun encode(): String = "$count;$sumMs;$maxMs;$lastMs;$over2s;$alarms"

        companion object {
            /** Ό,τι δεν διαβάζεται (άδειο, χαλασμένο, αρνητικά) μετρά ως «καμία μέτρηση ακόμα». */
            fun decode(s: String?): RestLate {
                val p = s?.split(';') ?: return RestLate()
                if (p.size != 6) return RestLate()
                val n = p.map { it.toLongOrNull() ?: return RestLate() }
                if (n.any { it < 0 } || n[0] > Int.MAX_VALUE || n[4] > n[0] || n[5] > n[0] || n[2] > MAX_REST_MS || n[3] > n[2]) return RestLate()
                return RestLate(n[0].toInt(), n[1], n[2], n[3], n[4].toInt(), n[5].toInt())
            }
        }
    }
}
