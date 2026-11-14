package gr.ygeiaforma.ygeia_forma

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Round 7 · f5: widgets της αρχικής οθόνης. U1-6 (η πηγή πάνω στη «λάμψη»), A10-2 (η Κίνηση από την ανάγνωση στο
 * παρασκήνιο σε νέα μέρα), U1-10 (πηγή «Samsung»). Καθαρό JVM. Φανταστικές τιμές (δημόσιο repo).
 */
class R7F5Test {
    // ------------------------------------------------------------------------------------------- U1-6: λάμψη και πηγή

    /** Τα έτοιμα θέματα του widget_style.dart (`wThemes`): c1, c2, τόνος, διαφάνεια %. */
    private val themes = listOf(
        "bordeaux" to intArrayOf(0xFF4A070C.toInt(), 0xFF050203.toInt(), 0xFFFF9C8A.toInt(), 92),
        "aegean" to intArrayOf(0xFF1D5BD8.toInt(), 0xFF0A1A3F.toInt(), 0xFF7FD3FF.toInt(), 85),
        "night" to intArrayOf(0xFF2A3C96.toInt(), 0xFF141C45.toInt(), 0xFF8C9CFF.toInt(), 90),
        "olive" to intArrayOf(0xFF5E7E2E.toInt(), 0xFF1C2610.toInt(), 0xFFC9E08A.toInt(), 85),
        "graphite" to intArrayOf(0xFF3A3D46.toInt(), 0xFF111216.toInt(), 0xFFF2CC5C.toInt(), 80),
        "paper" to intArrayOf(0xFFFFFFFF.toInt(), 0xFFEFEAE6.toInt(), 0xFFA3202A.toInt(), 92),
    )

    private class Seen(val text: Int, val top: Int, val bottom: Int, val acc: Int, val full: Float)

    /** Όπως το `init` του WidgetRenderer.Painter (διαβάθμιση ↓, αυτόματο χρώμα γραμμάτων). */
    private fun seen(t: IntArray, dark: Boolean): Seen {
        val (c1, c2, acc, opPct) = t.toList()
        val op = opPct / 100f
        val wall = if (dark) 0xFF1A1A1E.toInt() else 0xFFE9E6E2.toInt()
        val mid = WidgetText.over(c2, c1, 0.55f)
        val seenMid = WidgetText.over(mid, wall, op)
        val text = if (WidgetText.lum(seenMid) > 0.33) 0xFF17141F.toInt() else 0xFFF7F4FF.toInt()
        val full = (if (WidgetText.lum(c1) > 0.08) 0.24f else 0.38f) * op
        return Seen(text, WidgetText.over(c1, wall, op), WidgetText.over(c2, wall, op), acc, full)
    }

    /**
     * Για κάθε έτοιμο θέμα, σε σκοτεινή και ανοιχτή ταπετσαρία: η πηγή (γκρι γράμματα) πάνω στο κέντρο της λάμψης
     * διαβάζεται όσο και χωρίς λάμψη, ως 4,5:1. Πριν (python, /home/claude/scratch/f5r7/glow2.py): 2,73–4,35:1 σε 10 από
     * τις 12 περιπτώσεις.
     */
    @Test
    fun sourceOnGlowReadable() {
        for ((name, t) in themes) {
            for (dark in listOf(true, false)) {
                val s = seen(t, dark)
                val g = WidgetText.glowAlpha(s.text, s.acc, s.top, s.full)
                assertTrue("$name/$dark", g in 0f..s.full)
                val glowBg = WidgetText.over(s.acc, s.top, g)
                val behind = if (g > 0f) intArrayOf(s.top, s.bottom, glowBg) else intArrayOf(s.top, s.bottom)
                val a = WidgetText.mutedAlpha(s.text, behind)
                val src = WidgetText.contrast(WidgetText.over(s.text, glowBg, a), glowBg)
                val target = minOf(4.5, WidgetText.contrast(s.text, s.top))
                assertTrue("$name/${if (dark) "σκοτεινή" else "ανοιχτή"}: $src < $target", src >= target - 1e-9)
            }
        }
    }

    /** Όπου διαβάζεται, η λάμψη μένει ολόκληρη (η προεπιλογή «Μπορντό»)· αλλιώς μικραίνει όσο χρειάζεται (python). */
    @Test
    fun glowKeptWhereReadable() {
        val bordeaux = seen(themes[0].second, dark = true)
        assertEquals(bordeaux.full, WidgetText.glowAlpha(bordeaux.text, bordeaux.acc, bordeaux.top, bordeaux.full), 1e-6f)
        val oliveDark = seen(themes[3].second, dark = true)
        // python: πλήρη γράμματα πάνω στη λάμψη 3,78 / 4,10 / 4,41 / 4,81:1 (× 1 / 0,75 / 0,5 / 0,25) → 0,25.
        assertEquals(oliveDark.full * 0.25f, WidgetText.glowAlpha(oliveDark.text, oliveDark.acc, oliveDark.top, oliveDark.full), 1e-6f)
        val graphiteLight = seen(themes[4].second, dark = false)
        // python: 3,62 / 4,06 / 4,56:1 → 0,5.
        assertEquals(
            graphiteLight.full * 0.5f,
            WidgetText.glowAlpha(graphiteLight.text, graphiteLight.acc, graphiteLight.top, graphiteLight.full),
            1e-6f,
        )
        // «Ελιά» σε ανοιχτή ταπετσαρία: ούτε χωρίς λάμψη δεν φτάνει 4,5 (3,40:1)· η λάμψη δεν το κάνει χειρότερο: καμία.
        val oliveLight = seen(themes[3].second, dark = false)
        assertEquals(0f, WidgetText.glowAlpha(oliveLight.text, oliveLight.acc, oliveLight.top, oliveLight.full), 0f)
    }

    // ------------------------------------------------------------------------- A10-2 / U1-10: Κίνηση στο παρασκήνιο

    private val zone: ZoneId = ZoneId.of("Europe/Athens")

    private fun ms(y: Int, mo: Int, d: Int, h: Int, mi: Int) = LocalDateTime.of(y, mo, d, h, mi).atZone(zone).toInstant().toEpochMilli()

    private fun entry(l: String, v: String, u: String) = JSONObject().put("l", l).put("v", v).put("u", u)

    /** Το «move» όπως το έγραψε η εφαρμογή Πέμ 12/11 21:00 (χθες 11/11: 3.000 βήματα, «κάτω από το εύρος»). */
    private fun yesterdayMove(): JSONObject = JSONObject()
        .put("src", "Samsung · 21:00").put("srcShort", "21:00").put("at", ms(2026, 11, 12, 21, 0)).put("day", "2026-11-12")
        .put(
            "m",
            JSONObject()
                .put(
                    "steps",
                    entry("Βήματα", "12.000", "").put("cap", "χθες 3.000").put("r", "χθες κάτω από το εύρος")
                        .put("s", JSONArray(listOf(7000, 8000, 9000, 6000, 5000, 3000, 12000))),
                )
                .put("activeKcal", entry("Ενεργές", "640", " kcal"))
                .put("totalKcal", entry("Σύνολο", "2.810", " kcal"))
                .put("activeMin", entry("Ενεργός", "95", " λεπτά"))
                .put("distance", entry("Απόσταση", "9,1", " km"))
                .put("dayHr", entry("Παλμοί χθες", "74", " bpm")),
        )

    private fun stepsArr(vararg e: Pair<Long, Int>) = JSONArray(e.map { JSONArray(listOf(it.first, it.second)) })

    /** Νέα μέρα, με βήματα σήμερα: η κρίση της προχθεσινής ΔΕΝ μένει δίπλα στα χθεσινά βήματα. */
    @Test
    fun newDayDropsYesterdaysVerdict() {
        val today = LocalDate.of(2026, 11, 13)
        val dash = JSONObject().put("readAt", ms(2026, 11, 13, 9, 30))
            .put("steps", stepsArr(ms(2026, 11, 12, 12, 0) to 12000, ms(2026, 11, 13, 9, 0) to 1500))
            .put("activity", JSONObject().put("activeCalories", 287.6).put("calories", 1210.4).put("activeMinutes", 18).put("distance", 1100.0))
        val move = WidgetText.moveFromDashboard(yesterdayMove(), dash, today, zone)!!
        val steps = move.getJSONObject("m").getJSONObject("steps")
        assertEquals("1.500", steps.getString("v"))
        assertEquals("χθες 12.000", steps.getString("cap"))
        assertFalse("πριν: «χθες κάτω από το εύρος» για 12.000 βήματα", steps.has("r"))
        val s = steps.getJSONArray("s")
        assertEquals(7, s.length())
        for (i in 0 until 5) assertTrue(s.isNull(i))
        assertEquals(12000.0, s.getDouble(5), 0.0)
        assertEquals(1500.0, s.getDouble(6), 0.0)
        // Στρογγύλευση όπως η εφαρμογή (287,6 → 288· πριν 287).
        assertEquals("288", move.getJSONObject("m").getJSONObject("activeKcal").getString("v"))
        assertEquals("1.210", move.getJSONObject("m").getJSONObject("totalKcal").getString("v"))
        assertEquals("1,1", move.getJSONObject("m").getJSONObject("distance").getString("v"))
        assertFalse(move.getJSONObject("m").has("dayHr"))
        assertEquals("2026-11-13", move.getString("day"))
        assertEquals("Samsung · 09:30", move.getString("src"))
        assertEquals("09:30", move.getString("srcShort"))
        assertEquals(ms(2026, 11, 13, 9, 30), move.getLong("at"))
    }

    /** Νέα μέρα, νωρίς, χωρίς βήματα και χωρίς σύνολα της Samsung ακόμα: τίποτα από τη χθεσινή ως σημερινό. */
    @Test
    fun newDayWithoutDataCarriesNothing() {
        val today = LocalDate.of(2026, 11, 13)
        val dash = JSONObject().put("readAt", ms(2026, 11, 13, 6, 20))
            .put("steps", stepsArr(ms(2026, 11, 12, 12, 0) to 12000))
            .put("activity", JSONObject())
        val move = WidgetText.moveFromDashboard(yesterdayMove(), dash, today, zone)!!
        val m = move.getJSONObject("m")
        for (k in listOf("steps", "activeKcal", "totalKcal", "activeMin", "distance", "dayHr", "floors")) {
            assertFalse("$k: πριν έμενε η τιμή της 12/11 με ημερομηνία 13/11", m.has(k))
        }
        assertEquals("2026-11-13", move.getString("day"))
    }

    /** Ίδια μέρα: ό,τι δεν ήρθε αυτή τη φορά μένει (είναι της ίδιας μέρας), όπως πριν. */
    @Test
    fun sameDayKeepsMissing() {
        val today = LocalDate.of(2026, 11, 12)
        val dash = JSONObject().put("readAt", ms(2026, 11, 12, 22, 0))
            .put("steps", stepsArr(ms(2026, 11, 11, 12, 0) to 3000, ms(2026, 11, 12, 21, 50) to 12400))
            .put("activity", JSONObject().put("calories", 2900.0))
        val move = WidgetText.moveFromDashboard(yesterdayMove(), dash, today, zone)!!
        val m = move.getJSONObject("m")
        assertEquals("12.400", m.getJSONObject("steps").getString("v"))
        assertEquals("χθες κάτω από το εύρος", m.getJSONObject("steps").getString("r"))
        assertEquals("2.900", m.getJSONObject("totalKcal").getString("v"))
        assertEquals("640", m.getJSONObject("activeKcal").getString("v"))
        assertEquals("9,1", m.getJSONObject("distance").getString("v"))
        assertTrue(m.has("dayHr"))
    }

    /** Ανάγνωση όχι νεότερη από το στιγμιότυπο: καμία αλλαγή. Χωρίς στιγμιότυπο κίνησης: από την αρχή. */
    @Test
    fun olderReadChangesNothing() {
        val dash = JSONObject().put("readAt", ms(2026, 11, 12, 20, 0)).put("steps", JSONArray())
        assertNull(WidgetText.moveFromDashboard(yesterdayMove(), dash, LocalDate.of(2026, 11, 12), zone))
        val fresh = WidgetText.moveFromDashboard(null, dash, LocalDate.of(2026, 11, 12), zone)!!
        assertEquals(0, fresh.getJSONObject("m").length())
        assertEquals("Samsung · 20:00", fresh.getString("src"))
    }
}
