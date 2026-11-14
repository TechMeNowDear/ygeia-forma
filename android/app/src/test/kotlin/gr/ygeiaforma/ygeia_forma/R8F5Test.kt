package gr.ygeiaforma.ygeia_forma

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * Round 8 · f5: widgets της αρχικής οθόνης. R8-U1-3 («96%» κολλητά), R8-U1-7 (σμίκρυνση κειμένου ποτέ κάτω από το όριο),
 * R8-A10-2 (η προεπισκόπηση της ρύθμισης με τον κανόνα της μέρας). Καθαρό JVM. Φανταστικές τιμές (δημόσιο repo).
 */
class R8F5Test {
    // ------------------------------------------------------------------------------------------- U1-3: «96%», «82,2 kg»

    @Test
    fun percentIsGluedLikeTheApp() {
        assertEquals("%", WidgetText.unitText("%"))
        assertEquals(" kg", WidgetText.unitText("kg"))
        assertEquals(" ώρες", WidgetText.unitText("ώρες"))
        assertEquals("", WidgetText.unitText(""))
        // Ο WidgetRenderer γράφει «τιμή + unitText(μονάδα)»: «96%», «25,4%», «82,2 kg».
        assertEquals("96%", "96" + WidgetText.unitText("%"))
        assertEquals("25,4%", "25,4" + WidgetText.unitText("%"))
        assertEquals("82,2 kg", "82,2" + WidgetText.unitText("kg"))
    }

    // ------------------------------------------------------------------------------------------- U1-7: όριο σμίκρυνσης

    /** Ο παλιός βρόχος του WidgetRenderer (`while (… && size > base * floor) size -= base * 0,05f`), μόνο για σύγκριση. */
    private fun oldFinalScale(base: Float, floor: Float): Float {
        var size = base
        while (size > base * floor) size -= base * 0.05f
        return size / base
    }

    /** Ο νέος: το τελευταίο βήμα όταν το κείμενο δεν χωρά ποτέ. */
    private fun newFinalScale(base: Float, floor: Float): Float {
        var size = base
        for (k in 1..WidgetText.shrinkSteps(floor)) size = base * WidgetText.shrinkScale(k)
        return size / base
    }

    @Test
    fun shrinkStopsExactlyAtTheFloor() {
        assertEquals(3, WidgetText.shrinkSteps(WidgetText.MIN_SCALE_SMALL))
        assertEquals(5, WidgetText.shrinkSteps(0.75f))
        assertEquals(8, WidgetText.shrinkSteps(0.6f))
        var oldBelow = 0
        // Πυκνότητες 2,0–3,5 × «Γράμματα» 0,9/1/1,12/1,3 × μεγέθη 9–13 sp (όπως ο renderer: v · d · fs).
        for (d in listOf(2.0f, 2.25f, 2.5f, 2.625f, 2.75f, 3.0f, 3.5f)) {
            for (fs in listOf(0.9f, 1.0f, 1.12f, 1.3f)) {
                for (v in listOf(9f, 9.5f, 10f, 10.5f, 11f, 11.5f, 12f, 12.5f, 13f)) {
                    val base = v * d * fs
                    for (floor in listOf(WidgetText.MIN_SCALE_SMALL, 0.75f, 0.6f)) {
                        val s = newFinalScale(base, floor)
                        assertTrue("$d/$fs/$v/$floor: $s", s >= floor - 1e-4f)
                        assertTrue("$d/$fs/$v/$floor: $s", s <= floor + 1e-4f)
                        if (oldFinalScale(base, floor) < floor - 0.01f) oldBelow++
                    }
                }
            }
        }
        // Η δοκιμή έχει νόημα: ο παλιός βρόχος έπεφτε ένα βήμα κάτω από το όριο (π.χ. 2,0 × 0,9 × 9 sp → 80% αντί για 85%).
        assertTrue("ο παλιός βρόχος: $oldBelow", oldBelow > 0)
    }

    // ------------------------------------------------------------------------------------------- A10-2: προεπισκόπηση

    private val sample = JSONObject().put("src", "παράδειγμα").put("m", JSONObject().put("steps", JSONObject().put("v", "6.389")))

    private fun move(day: String) = JSONObject()
        .put("day", day)
        .put("src", "Samsung · 21:00")
        .put("srcShort", "21:00")
        .put(
            "m",
            JSONObject().put("steps", JSONObject().put("l", "Βήματα").put("v", "12.000").put("u", "").put("cap", "χθες 9.100")),
        )

    @Test
    fun previewShowsWhatTheWidgetShows() {
        val today = LocalDate.of(2026, 11, 17)
        // Χθεσινή «Κίνηση» (Δευ 16/11 21:00), Τρί 17/11 08:00: «—» και «νέα μέρα», όχι 12.000 σαν σημερινά.
        val stale = WidgetText.previewData(move("2026-11-16"), today) { sample }
        val steps = stale.getJSONObject("m").getJSONObject("steps")
        assertEquals("—", steps.optString("v"))
        assertEquals(WidgetText.OPEN_APP, steps.optString("cap"))
        assertEquals(WidgetText.NEW_DAY, stale.optString("src"))
        assertFalse(stale.has("srcShort"))
        // Ίδια μέρα: όπως είναι.
        val fresh = move("2026-11-17")
        val same = WidgetText.previewData(fresh, today) { sample }
        assertEquals("12.000", same.getJSONObject("m").getJSONObject("steps").optString("v"))
        assertEquals("Samsung · 21:00", same.optString("src"))
        // Χωρίς καμία τιμή (ή χωρίς στιγμιότυπο): το παράδειγμα.
        assertTrue(WidgetText.previewData(JSONObject().put("m", JSONObject()), today) { sample } === sample)
        assertTrue(WidgetText.previewData(null, today) { sample } === sample)
    }
}
