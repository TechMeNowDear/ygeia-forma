package gr.ygeiaforma.ygeia_forma

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * «Τα φαγητά μου» (15/11): οι γραμμές μιας εγγραφής «όλα μαζί» (όλα τα υλικά ενός φαγητού σε μία συναλλαγή) ελέγχονται
 * ΠΡΙΝ γραφτεί οτιδήποτε, και το προσωρινό αρχείο του dishes.json είναι «δικό μας» (σβήνεται αν μια εγγραφή διακόπηκε).
 */
class DishRulesTest {
    @Test
    fun putAllKeepsEveryRowAsItIs() {
        val rows = FoodRules.putAllRows(
            """[{"id":"a","day":"2026-11-16","grams":12.5,"dish":{"id":"D1","grp":"g1","k":"pot","q":350}},""" +
                """{"id":"b","day":"2026-11-16","grams":3}]"""
        )
        assertEquals(2, rows.size)
        assertEquals("a", rows[0].first)
        assertEquals("2026-11-16", rows[0].second)
        // Το σημάδι του φαγητού μένει μέσα στο JSON της καταχώρισης.
        assertEquals("g1", JSONObject(rows[0].third).getJSONObject("dish").getString("grp"))
        assertEquals("b", rows[1].first)
    }

    @Test
    fun putAllStopsBeforeWritingAnythingWrong() {
        for (bad in listOf(
            "[]",
            """[{"id":"","day":"2026-11-16"}]""",
            """[{"id":"a"}]""",
            """[{"id":"a","day":"2026-11-16"},{"id":"a","day":"2026-11-16"}]""",
            """["x"]""",
        )) {
            try {
                FoodRules.putAllRows(bad)
                fail("Έπρεπε να σταματήσει: $bad")
            } catch (_: IllegalArgumentException) {
            } catch (_: org.json.JSONException) {
            }
        }
    }

    @Test
    fun deleteAllNeedsRealIds() {
        assertEquals(listOf("a", "b"), FoodRules.idList("""["a","b"]"""))
        for (bad in listOf("[]", """[""]""", """[1]""", """[null]""")) {
            try {
                FoodRules.idList(bad)
                fail("Έπρεπε να σταματήσει: $bad")
            } catch (_: IllegalArgumentException) {
            }
        }
    }

    @Test
    fun dishesTempFileIsOurs() {
        assertTrue(OuraRules.isOwnTmp("dishes.json.123456789.tmp"))
        assertFalse(OuraRules.isOwnTmp("dishes.json"))
        assertFalse(OuraRules.isOwnTmp("dishes.json.bad"))
    }
}
