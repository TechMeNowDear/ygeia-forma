package gr.ygeiaforma.ygeia_forma

import org.json.JSONObject
import java.time.LocalDate

/**
 * Κανόνες κειμένου και χρωμάτων των widgets της αρχικής οθόνης (round 1, U7-11 … U7-16). Καθαρές συναρτήσεις (χωρίς
 * Android· μόνο org.json και ακέραια χρώματα ARGB), για να ελέγχονται σε απλό JVM (R1F9Test). Τις καλούν ο
 * WidgetRenderer και η HomeWidgets.
 */
object WidgetText {
    /** Λεζάντα της κεντρικής τιμής όταν δεν υπάρχει τιμή της μέρας ή καμία τιμή ακόμα: τι να κάνεις (U7-12, U7-16). */
    const val OPEN_APP = "άνοιξε την εφαρμογή"

    /** Η ίδια, όταν η στενή στήλη δεν τη χωρά (ποτέ «άνοιξε την ε…»). */
    const val OPEN_APP_SHORT = "άνοιξέ με"

    /** Πηγή για τιμές άλλης μέρας μετά τα μεσάνυχτα (πριν: «νέα μέρα · άνοιξε την εφαρμογή», που κοβόταν). */
    const val NEW_DAY = "νέα μέρα"

    /**
     * Πόσο μπορεί να μικρύνει μια μικρή γραμμή (κάτω από 11 sp) πριν κοπεί (U7-11: πριν ως 75%, δηλ. 7,9 sp στα 10,5 sp,
     * που δεν διαβάζονται). Το ίδιο όριο έχει και ο WidgetRenderer στο `fit`.
     */
    const val MIN_SCALE_SMALL = 0.85f

    /**
     * Τιμές «σήμερα» (κίνηση, φαγητό) άλλης μέρας δεν φαίνονται σαν σημερινές (έλεγχος 8/11, DATA-02): μένουν τα ονόματα
     * και το γράφημα, οι τιμές γίνονται «—». Round 1 (U7-12): η πηγή γράφει σκέτο «νέα μέρα» (χωρά σε κάθε μέγεθος) και η
     * λεζάντα της κεντρικής τιμής «άνοιξε την εφαρμογή», που φαίνεται και στο Φαγητό με το «+» (εκεί δεν ζωγραφίζεται πηγή).
     */
    fun forToday(data: JSONObject?, today: LocalDate): JSONObject? {
        val day = data?.optString("day", "") ?: return null
        if (day.isEmpty() || day == today.toString()) return data
        val c = JSONObject(data.toString())
        val m = c.optJSONObject("m") ?: return c
        for (k in m.keys().asSequence().toList()) {
            m.optJSONObject(k)?.apply {
                put("v", "—")
                put("u", "")
                put("cap", OPEN_APP)
                put("capShort", OPEN_APP_SHORT)
                remove("d")
                remove("us")
                remove("r")
            }
        }
        c.remove("bar")
        c.put("src", NEW_DAY)
        return c
    }

    /**
     * U7-11: η γραμμή «▲ συνήθως 6:58 · 7 νύχτες μέσα στο εύρος». Αν δεν χωρά ολόκληρη ([fits]: με το πολύ
     * [MIN_SCALE_SMALL] σμίκρυνση), γίνεται δύο γραμμές («συνήθως…» και η κρίση του εύρους). Ό,τι δεν χωρά δεν γράφεται·
     * ποτέ «· …», που έκοβε την κρίση στη μέση.
     * Round 2 (R2-D-1): η κρίση γράφεται μόνο ΟΛΟΚΛΗΡΗ, με το «N νύχτες» της. Πριν, σε στενή στήλη έχανε το «7 νύχτες» και
     * το «κάτω από το εύρος» του μέσου όρου της εβδομάδας καθόταν κάτω από τη χθεσινή νύχτα (π.χ. «7:16 ώρες» … «κάτω από
     * το εύρος»), σαν κρίση για εκείνη. Καλύτερα τίποτα παρά κρίση χωρίς το τι κρίνει.
     */
    fun usualLines(usual: String?, range: String?, fits: (String) -> Boolean): List<String> {
        val us = usual?.takeIf { it.isNotBlank() }
        val r = range?.takeIf { it.isNotBlank() }
        val parts = listOfNotNull(us, r)
        if (parts.isEmpty()) return emptyList()
        val joined = parts.joinToString(" · ")
        if (fits(joined)) return listOf(joined)
        val out = mutableListOf<String>()
        if (us != null && fits(us)) out += us
        if (r != null && fits(r)) out += r
        return out
    }

    /**
     * Round 2 (R2-U3-04): η πηγή του widget. Όταν η κανονική ([src]) δεν χωρά ούτε με τη μικρότερη επιτρεπτή σμίκρυνση
     * ([fits], π.χ. «καμία πρόσφατη νύχτα» στη στήλη 1×3), η σύντομη ([short], «καμία νύχτα»)· ποτέ «καμία πρόσφατη…».
     */
    fun sourceText(src: String, short: String?, fits: (String) -> Boolean): String =
        if (short.isNullOrEmpty() || fits(src)) src else short

    /**
     * Round 2 (R2-U3-06): ποσότητες που μετριούνται από το μηδέν (βήματα, θερμίδες, γραμμάρια, ΚΑΙ η διάρκεια ύπνου):
     * ράβδοι από το μηδέν, ώστε η αναλογία των υψών να είναι η αναλογία των τιμών (6,5 ώρες = 86% των 7,6, όχι 38%).
     */
    fun zeroBased(kind: String, heroKey: String): Boolean = kind == "move" || kind == "food" || heroKey == "sleepMin"

    /**
     * Round 2 (R2-U3-05): ελάχιστο εύρος των ράβδων, ίδιο με τα γραφήματα του κινητού (Σήμερα/Σώμα: βάρος, λίπος, μύες
     * 3· παλμοί 8· ετοιμότητα 20), ώστε ο θόρυβος της ζυγαριάς (±0,2 kg) να μη μοιάζει με άλματα. 0 = χωρίς ελάχιστο.
     */
    fun minSpanFor(heroKey: String): Float = when (heroKey) {
        "weight", "smm", "ffm", "fatPct" -> 3f
        "sleepHr", "lowHr", "dayHr" -> 8f
        "energy" -> 20f
        else -> 0f
    }

    /**
     * Το ύψος κάθε ράβδου του γραφήματος 7 ημερών ως κλάσμα του ύψους του (0,08–1· null = χωρίς τιμή). [zero]: από το
     * μηδέν. Αλλιώς βάση λίγο κάτω από το χαμηλότερο (όπως πριν: η χαμηλότερη ράβδος 37,5% της ψηλότερης), αλλά με εύρος
     * τουλάχιστον [minSpan] γύρω από τη μέση των τιμών (όπως το `sparkRange` του κινητού).
     */
    fun barFractions(vals: List<Float?>, zero: Boolean, minSpan: Float): List<Float?> {
        val real = vals.filterNotNull()
        if (real.isEmpty()) return vals.map { null }
        var hi = real.max()
        var lo0 = real.min()
        val lo: Float
        if (zero && hi > 0f) {
            lo = 0f
        } else {
            if (hi - lo0 < minSpan) {
                val mid = (hi + lo0) / 2f
                lo0 = mid - minSpan / 2f
                hi = mid + minSpan / 2f
            }
            lo = if (hi == lo0) lo0 - 1f else lo0 - (hi - lo0) * 0.6f
        }
        return vals.map { v -> if (v == null) null else ((v - lo) / (hi - lo)).coerceIn(0.08f, 1f) }
    }

    // ---------------------------------------------------------------- χρώματα (ARGB σε Int)

    private fun ch(c: Int, shift: Int) = (c shr shift) and 0xFF

    /** Σχετική φωτεινότητα κατά WCAG 2.x (η διαφάνεια του χρώματος αγνοείται). */
    fun lum(c: Int): Double {
        fun lin(v: Int): Double {
            val x = v / 255.0
            return if (x <= 0.03928) x / 12.92 else Math.pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(ch(c, 16)) + 0.7152 * lin(ch(c, 8)) + 0.0722 * lin(ch(c, 0))
    }

    /** Αντίθεση δύο αδιαφανών χρωμάτων (1 ως 21). */
    fun contrast(a: Int, b: Int): Double {
        val la = lum(a)
        val lb = lum(b)
        return (maxOf(la, lb) + 0.05) / (minOf(la, lb) + 0.05)
    }

    /** Το [fg] με διαφάνεια [a] πάνω στο αδιαφανές [bg], όπως το ζωγραφίζει ο καμβάς. */
    fun over(fg: Int, bg: Int, a: Float): Int {
        fun mixCh(shift: Int) = Math.round(ch(fg, shift) * a + ch(bg, shift) * (1 - a)).coerceIn(0, 255)
        return (0xFF shl 24) or (mixCh(16) shl 16) or (mixCh(8) shl 8) or mixCh(0)
    }

    /** Οι διαφάνειες του γκρι κειμένου (τίτλος, πηγή, ετικέτες κουτιών), από την πιο απαλή. */
    val MUTED_STEPS = floatArrayOf(0.70f, 0.78f, 0.86f, 0.94f, 1f)

    /**
     * U7-14: η πιο απαλή διαφάνεια του γκρι κειμένου που διαβάζεται (≥ 4,5:1) πάνω σε ΟΛΑ τα [backgrounds] (το φόντο
     * του widget όπως φαίνεται πάνω στην ταπετσαρία, πάνω και κάτω). Πριν ήταν πάντα 70%: 2,6–4,3:1 στα θέματα
     * «Αιγαίο», «Ελιά», «Νύχτα», «Γραφίτης». Αν ούτε τα πλήρη γράμματα φτάνουν, πλήρη.
     */
    fun mutedAlpha(text: Int, backgrounds: IntArray): Float =
        MUTED_STEPS.firstOrNull { a -> backgrounds.all { contrast(over(text, it, a), it) >= 4.5 } } ?: 1f

    /** U7-14: το χρώμα τόνου (95%) για τη γραμμή «συνήθως» μόνο όταν διαβάζεται σε όλα τα [backgrounds]. */
    fun toneReadable(tone: Int, backgrounds: IntArray): Boolean = backgrounds.all { contrast(over(tone, it, 0.95f), it) >= 4.5 }
}
