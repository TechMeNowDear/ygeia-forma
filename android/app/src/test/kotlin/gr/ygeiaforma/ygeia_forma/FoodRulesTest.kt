package gr.ygeiaforma.ygeia_forma

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream

/**
 * Τελικός έλεγχος, Συμβούλιο 4: barcode UPC-E (Β2), απάντηση του Open Food Facts που δεν διαβάζεται (Β5) και οι γραμμές
 * μιας επαναφοράς από αντίγραφο (Γ1). Οι κωδικοί είναι δοκιμαστικοί (όχι πραγματικά προϊόντα), εκτός από το παράδειγμα της Wikipedia.
 */
class FoodRulesTest {
    @Test
    fun checkDigitMatchesKnownCodes() {
        // UPC-A 036000291452, EAN-13 4006381333931, EAN-8 73513537 (γνωστά παραδείγματα ψηφίου ελέγχου)
        assertEquals(2, FoodRules.checkDigit("03600029145"))
        assertEquals(1, FoodRules.checkDigit("400638133393"))
        assertEquals(7, FoodRules.checkDigit("7351353"))
        assertNull(FoodRules.checkDigit(""))
        assertNull(FoodRules.checkDigit("12a4"))
    }

    @Test
    fun upceExpandsToTheUpcaTheProductIsStoredUnder() {
        // Το παράδειγμα της σελίδας «Universal Product Code» (Wikipedia): 04252614 ↔ 042100005264
        assertEquals("042100005264", FoodRules.upceToUpca("04252614"))
        // Ένα παράδειγμα ανά κανόνα (τελευταίο από τα έξι ψηφία: 0, 1, 2, 3, 4, 5, 9) και σύστημα 1. Υπολογισμένα
        // ανεξάρτητα, από τον UPC-A προς τα πίσω (scratchpad c4_upce.py, και εξαντλητικά για όλους τους κωδικούς).
        assertEquals("012000003455", FoodRules.upceToUpca("01234505"))
        assertEquals("012100003454", FoodRules.upceToUpca("01234514"))
        assertEquals("012200003453", FoodRules.upceToUpca("01234523"))
        assertEquals("012300000451", FoodRules.upceToUpca("01234531"))
        assertEquals("012340000053", FoodRules.upceToUpca("01234543"))
        assertEquals("012345000058", FoodRules.upceToUpca("01234558"))
        assertEquals("012345000096", FoodRules.upceToUpca("01234596"))
        assertEquals("112345000079", FoodRules.upceToUpca("11234579"))
        // κενά γύρω γύρω από τον σαρωτή
        assertEquals("042100005264", FoodRules.upceToUpca(" 04252614 "))
    }

    @Test
    fun whatIsNotUpceStaysAsItCame() {
        // λάθος ψηφίο ελέγχου: δεν είναι UPC-E (π.χ. EAN-8 που διαβάστηκε ως UPC-E)
        assertNull(FoodRules.upceToUpca("04252615"))
        // λάθος μήκος, γράμματα, σύστημα εκτός 0/1, ψηφία άλλης γραφής
        assertNull(FoodRules.upceToUpca("0425261"))
        assertNull(FoodRules.upceToUpca("042526140"))
        assertNull(FoodRules.upceToUpca("0425261a"))
        assertNull(FoodRules.upceToUpca("24252614"))
        // τα ίδια ψηφία σε αραβική γραφή (από το U+0660): δεν είναι τα 0–9 ενός barcode
        assertNull(FoodRules.upceToUpca("04252614".map { (it - '0' + 0x660).toChar() }.joinToString("")))
        assertNull(FoodRules.upceToUpca(""))
    }

    @Test
    fun everyExpandedCodeHasAValidCheckDigit() {
        // Όλοι οι κωδικοί ενός συστήματος με τελευταίο ψηφίο 0–9: ακριβώς ένα ψηφίο ελέγχου γίνεται δεκτό, και ο UPC-A
        // που βγαίνει έχει 12 ψηφία με σωστό ψηφίο ελέγχου.
        for (k in 0 until 100_000 step 37) {
            val six = k.toString().padStart(6, '0')
            val accepted = (0..9).mapNotNull { FoodRules.upceToUpca("0$six$it") }
            assertEquals(six, 1, accepted.size)
            val a = accepted.single()
            assertEquals(12, a.length)
            assertEquals(a.last() - '0', FoodRules.checkDigit(a.dropLast(1)))
        }
    }

    @Test
    fun replyThatIsNotJsonIsAConnectionProblem() {
        // Β5: ο διακομιστής απαντά 200 με σελίδα HTML (συντήρηση, όριο κλήσεων): «δεν έγινε σύνδεση», όχι άγνωστο σφάλμα
        for (body in listOf("<html><body>Service unavailable</body></html>", "", "   ", "[1,2]", "{\"status\":1,")) {
            val r = FoodRules.offReply(200, body)
            assertFalse(body, r.getBoolean("ok"))
            assertEquals(body, "connection", r.getString("kind"))
        }
        // απάντηση πάνω από το όριο μεγέθους (το σώμα δεν διαβάστηκε)
        val big = FoodRules.offReply(200, null)
        assertFalse(big.getBoolean("ok"))
        assertEquals("connection", big.getString("kind"))
    }

    @Test
    fun knownRepliesStayAsTheyWere() {
        // 404: το προϊόν δεν υπάρχει
        val missing = FoodRules.offReply(404, null)
        assertTrue(missing.getBoolean("ok"))
        assertFalse(missing.getBoolean("found"))
        // άλλος κωδικός HTTP: σύνδεση
        val down = FoodRules.offReply(503, "<html>")
        assertFalse(down.getBoolean("ok"))
        assertEquals("connection", down.getString("kind"))
        assertEquals("HTTP 503", down.getString("message"))
        // JSON χωρίς προϊόν (status 0), ή με «product» που δεν είναι αντικείμενο
        for (body in listOf("{\"status\":0,\"status_verbose\":\"product not found\"}", "{\"status\":1}", "{\"status\":1,\"product\":\"x\"}")) {
            val r = FoodRules.offReply(200, body)
            assertTrue(body, r.getBoolean("ok"))
            assertFalse(body, r.getBoolean("found"))
        }
        // JSON με προϊόν
        val ok = FoodRules.offReply(200, "{\"status\":1,\"product\":{\"product_name\":\"Δοκιμή\",\"nutriments\":{\"energy-kcal_100g\":100}}}")
        assertTrue(ok.getBoolean("ok"))
        assertTrue(ok.getBoolean("found"))
        assertEquals("Δοκιμή", ok.getJSONObject("product").getString("product_name"))
        assertEquals(100, ok.getJSONObject("product").getJSONObject("nutriments").getInt("energy-kcal_100g"))
    }

    @Test
    fun bodyIsReadOnlyUpToTheLimit() {
        val text = "{\"όνομα\":\"γιαούρτι\"}"
        val bytes = text.toByteArray(Charsets.UTF_8)
        // κάτω από το όριο και ακριβώς στο όριο: ολόκληρο, με σωστά ελληνικά
        assertEquals(text, FoodRules.readCapped(ByteArrayInputStream(bytes)))
        assertEquals(text, FoodRules.readCapped(ByteArrayInputStream(bytes), bytes.size))
        // ένα byte πάνω από το όριο: τίποτα
        assertNull(FoodRules.readCapped(ByteArrayInputStream(bytes), bytes.size - 1))
        // μεγάλο σώμα σε πολλά κομμάτια
        val big = ByteArray(100_000) { 'a'.code.toByte() }
        assertEquals(100_000, FoodRules.readCapped(ByteArrayInputStream(big))!!.length)
        assertNull(FoodRules.readCapped(ByteArrayInputStream(big), 99_999))
        assertEquals("", FoodRules.readCapped(ByteArrayInputStream(ByteArray(0))))
    }

    // ------------------------------------------------------------------ Γ1: επαναφορά σε μία συναλλαγή
    @Test
    fun restoreRowsKeepEveryRowAsItCame() {
        val log = """[{"id":"E1","day":"2026-11-01","meal":"lunch","grams":170,"food":{"id":"M1","name":"Γιαούρτι 2%"}},
            {"id":"E2","day":"2026-11-02","grams":50.5}]"""
        val foods = """[{"id":"M1","name":"Γιαούρτι 2%","n":{"kcal":70}}]"""
        val r = FoodRules.restoreRows(log, foods)
        assertEquals(listOf("E1", "E2"), r.log.map { it.first })
        assertEquals(listOf("2026-11-01", "2026-11-02"), r.log.map { it.second })
        assertEquals(listOf("M1"), r.foods.map { it.first })
        // το JSON κάθε γραμμής είναι ολόκληρο, με σωστά ελληνικά και χωρίς να χαθεί πεδίο
        val e1 = JSONObject(r.log[0].third)
        assertEquals("Γιαούρτι 2%", e1.getJSONObject("food").getString("name"))
        assertEquals(170, e1.getInt("grams"))
        assertEquals(50.5, JSONObject(r.log[1].third).getDouble("grams"), 0.0)
        assertEquals(70, JSONObject(r.foods[0].second).getJSONObject("n").getInt("kcal"))
        // άδειοι πίνακες: τίποτα να γραφτεί, χωρίς σφάλμα
        val none = FoodRules.restoreRows("[]", "[]")
        assertTrue(none.log.isEmpty() && none.foods.isEmpty())
    }

    @Test
    fun restoreRowsRefuseTheWholeBatchWhenOneRowIsWrong() {
        val good = """{"id":"E1","day":"2026-11-01"}"""
        val badLogs = listOf(
            """[$good,{"day":"2026-11-01"}]""", // χωρίς id
            """[$good,{"id":"E2"}]""", // χωρίς day
            """[$good,{"id":"","day":"2026-11-01"}]""", // κενό id
            """[$good,{"id":7,"day":"2026-11-01"}]""", // id που δεν είναι κείμενο
            """[$good,{"id":"E2","day":20261101}]""", // day που δεν είναι κείμενο
            """[$good,"σκουπίδι"]""",
            """[$good,null]""",
            """{"id":"E1","day":"2026-11-01"}""", // όχι πίνακας
            "δεν είναι JSON",
        )
        for (log in badLogs) {
            try {
                FoodRules.restoreRows(log, "[]")
                fail(log)
            } catch (_: IllegalArgumentException) {
            } catch (_: org.json.JSONException) {
            }
        }
        for (foods in listOf("""[{"name":"χωρίς id"}]""", """[{"id":""}]""", """[{"id":5}]""", """[42]""", "{}")) {
            try {
                FoodRules.restoreRows("[$good]", foods)
                fail(foods)
            } catch (_: IllegalArgumentException) {
            } catch (_: org.json.JSONException) {
            }
        }
    }
}
