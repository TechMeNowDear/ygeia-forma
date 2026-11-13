package gr.ygeiaforma.ygeia_forma

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * Round 1 · f9: κανόνες κειμένου και χρωμάτων των widgets της αρχικής οθόνης (WidgetText, QuickWidgetRules).
 * Καθαρό JVM. Φανταστικές τιμές (δημόσιο repo).
 */
class R1F9Test {
    private val today = LocalDate.of(2026, 11, 16)

    /** U7-12: μετά τα μεσάνυχτα, χθεσινές τιμές → «—», σύντομη πηγή, και λεζάντα που λέει τι να κάνεις. */
    @Test
    fun forTodayTellsWhatToDo() {
        val data = JSONObject().put("day", "2026-11-15").put("src", "ρολόι · 22:10")
            .put("bar", org.json.JSONArray().put(1).put(2).put(3))
            .put(
                "m",
                JSONObject()
                    .put("steps", JSONObject().put("l", "Βήματα").put("v", "8.012").put("u", "").put("cap", "χθες 6.389").put("d", 1).put("us", "συνήθως 7.000").put("r", "μέσα στο εύρος"))
                    .put("activeMin", JSONObject().put("l", "Ενεργός").put("v", "34").put("u", " λεπτά")),
            )
        val c = WidgetText.forToday(data, today)!!
        assertEquals("νέα μέρα", c.optString("src"))
        assertFalse(c.has("bar"))
        val steps = c.getJSONObject("m").getJSONObject("steps")
        assertEquals("—", steps.optString("v"))
        assertEquals("", steps.optString("u"))
        assertEquals("άνοιξε την εφαρμογή", steps.optString("cap"))
        assertEquals("άνοιξέ με", steps.optString("capShort"))
        assertFalse(steps.has("d") || steps.has("us") || steps.has("r"))
        assertEquals("Βήματα", steps.optString("l"))
        assertEquals("—", c.getJSONObject("m").getJSONObject("activeMin").optString("v"))
        // Το αρχικό δεν αλλάζει· η σημερινή μέρα και χωρίς «day» μένουν όπως είναι.
        assertEquals("8.012", data.getJSONObject("m").getJSONObject("steps").optString("v"))
        val fresh = JSONObject().put("day", today.toString()).put("m", JSONObject())
        assertTrue(WidgetText.forToday(fresh, today) === fresh)
        val noDay = JSONObject().put("m", JSONObject())
        assertTrue(WidgetText.forToday(noDay, today) === noDay)
        assertNull(WidgetText.forToday(null, today))
    }

    /** U7-11: η κρίση «μέσα/κάτω από το εύρος» δεν κόβεται ποτέ με «…»· δύο γραμμές. Round 2 (R2-D-1): ποτέ χωρίς το «N νύχτες». */
    @Test
    fun usualLinesNeverCutTheVerdict() {
        val us = "▲ συνήθως 6:58"
        val r = "7 νύχτες μέσα στο εύρος"
        // Πλάτος ανά χαρακτήρα σταθερό (1 μονάδα), για να είναι προβλέψιμο.
        fun fitsIn(w: Int): (String) -> Boolean = { it.length <= w }
        assertEquals(listOf("$us · $r"), WidgetText.usualLines(us, r, fitsIn(60)))
        assertEquals(listOf(us, r), WidgetText.usualLines(us, r, fitsIn(r.length)))
        assertEquals(listOf(us), WidgetText.usualLines(us, r, fitsIn(us.length)))
        // Ό,τι δεν χωρά ούτε μόνο του δεν γράφεται (όχι «· …»).
        assertEquals(emptyList<String>(), WidgetText.usualLines("▲ συνήθως 7 ώρες 10 λεπτά", r, fitsIn(14)))
        assertEquals(emptyList<String>(), WidgetText.usualLines(us, r, fitsIn(3)))
        // Μία νύχτα (ενικός) και κρίση χωρίς νύχτες.
        assertEquals(emptyList<String>(), WidgetText.usualLines(null, "1 νύχτα κάτω από το εύρος", fitsIn(17)))
        assertEquals(listOf("χθες μέσα στο εύρος"), WidgetText.usualLines(null, "χθες μέσα στο εύρος", fitsIn(30)))
        assertEquals(emptyList<String>(), WidgetText.usualLines(null, "", fitsIn(30)))
        for (w in 1..60) {
            for (line in WidgetText.usualLines(us, r, fitsIn(w))) {
                assertFalse(line.endsWith("…"))
                assertTrue(line.length <= w)
            }
        }
    }

    /** U7-14: το γκρι κείμενο διαβάζεται (≥ 4,5:1) σε κάθε έτοιμο θέμα, πάνω σε σκούρα και ανοιχτή ταπετσαρία. */
    @Test
    fun mutedTextIsReadableOnEveryTheme() {
        // Ίδιες τιμές με το lib/home_widgets/widget_style.dart (wThemes): c1, c2, τόνος, αδιαφάνεια.
        val themes = listOf(
            longArrayOf(0xFF4A070C, 0xFF050203, 0xFFFF9C8A, 92),
            longArrayOf(0xFF1D5BD8, 0xFF0A1A3F, 0xFF7FD3FF, 85),
            longArrayOf(0xFF2A3C96, 0xFF141C45, 0xFF8C9CFF, 90),
            longArrayOf(0xFF5E7E2E, 0xFF1C2610, 0xFFC9E08A, 85),
            longArrayOf(0xFF3A3D46, 0xFF111216, 0xFFF2CC5C, 80),
            longArrayOf(0xFFFFFFFF, 0xFFEFEAE6, 0xFFA3202A, 92),
        )
        for (t in themes) {
            for (wall in intArrayOf(0xFF1A1A1E.toInt(), 0xFFE9E6E2.toInt())) {
                val op = t[3] / 100f
                val top = WidgetText.over(t[0].toInt(), wall, op)
                val bottom = WidgetText.over(t[1].toInt(), wall, op)
                val mid = WidgetText.over(WidgetText.over(t[1].toInt(), t[0].toInt(), 0.55f), wall, op)
                // Αυτόματο χρώμα γραμμάτων, όπως ο WidgetRenderer: σκούρα σε φωτεινό φόντο, αλλιώς ανοιχτά.
                val text = if (WidgetText.lum(mid) > 0.33) 0xFF17141F.toInt() else 0xFFF7F4FF.toInt()
                val behind = intArrayOf(top, bottom)
                val a = WidgetText.mutedAlpha(text, behind)
                val best = behind.minOf { WidgetText.contrast(text, it) }
                if (best >= 4.5) {
                    for (bg in behind) assertTrue("θέμα ${t[0]}: ${WidgetText.contrast(WidgetText.over(text, bg, a), bg)}", WidgetText.contrast(WidgetText.over(text, bg, a), bg) >= 4.5)
                } else {
                    assertEquals(1f, a, 0f)
                }
                assertTrue(a >= 0.70f)
            }
        }
        // Ο υπολογισμός της αντίθεσης: #767676 σε λευκό = 4,54 (γνωστή τιμή WCAG).
        assertEquals(4.54, WidgetText.contrast(0xFF767676.toInt(), 0xFFFFFFFF.toInt()), 0.01)
        // Ο τόνος του «Αιγαίο» σε ανοιχτή ταπετσαρία δεν διαβάζεται (U7-14: 2,87:1) → γράμματα.
        val aegeanLight = intArrayOf(WidgetText.over(0xFF1D5BD8.toInt(), 0xFFE9E6E2.toInt(), 0.85f), WidgetText.over(0xFF0A1A3F.toInt(), 0xFFE9E6E2.toInt(), 0.85f))
        assertFalse(WidgetText.toneReadable(0xFF7FD3FF.toInt(), aegeanLight))
        // Ο τόνος του «Μπορντό» σε σκούρα ταπετσαρία διαβάζεται.
        val bordeauxDark = intArrayOf(WidgetText.over(0xFF4A070C.toInt(), 0xFF1A1A1E.toInt(), 0.92f), WidgetText.over(0xFF050203.toInt(), 0xFF1A1A1E.toInt(), 0.92f))
        assertTrue(WidgetText.toneReadable(0xFFFF9C8A.toInt(), bordeauxDark))
    }

    /** U7-17 α: η επικεφαλίδα «ΠΡΟΠΟΝΗΣΗ ΣΗΜΕΡΑ» μόνο όταν χωρούν τρεις γραμμές. */
    @Test
    fun workoutHead() {
        assertTrue(QuickWidgetRules.workoutHeadFits(0, 1f))
        assertTrue(QuickWidgetRules.workoutHeadFits(80, 1f))
        assertTrue(QuickWidgetRules.workoutHeadFits(76, 1f))
        assertFalse(QuickWidgetRules.workoutHeadFits(72, 1f))
        assertFalse(QuickWidgetRules.workoutHeadFits(80, 1.3f))
        assertTrue(QuickWidgetRules.workoutHeadFits(100, 1.3f))
    }
}
