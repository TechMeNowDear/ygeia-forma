package gr.ygeiaforma.ygeia_forma

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Κανόνες του φαγητού χωρίς τύπους Android ή Google, ώστε να ελέγχονται σε απλό JVM (android/app/src/test).
 * Τελικός έλεγχος, Συμβούλιο 4: barcode UPC-E (Β2), απάντηση του Open Food Facts που δεν διαβάζεται (Β5) και οι γραμμές
 * μιας επαναφοράς από αντίγραφο (Γ1).
 */
object FoodRules {
    /** Το πολύ τόσο διαβάζεται από μια απάντηση του Open Food Facts (ένα προϊόν με τα πεδία που ζητάμε είναι λίγα KB). */
    const val OFF_MAX_BYTES = 2 * 1024 * 1024

    /**
     * Τα πεδία που ζητάμε από το Open Food Facts για ένα προϊόν. Έλεγχος round1 (S2-1 / S1-9): και οι κατηγορίες του
     * («categories_tags»), ώστε ένα σαρωμένο προϊόν να μετρά στην κάρτα «Χοληστερίνη» ως ξηροί καρποί, όσπρια ή ψάρι
     * (lib/food/off.dart, cholKindFromOffTags). Τα υπόλοιπα πεδία όπως πριν.
     */
    const val OFF_FIELDS = "code,product_name,product_name_el,generic_name_el,brands,quantity,serving_size," +
        "serving_quantity,nutriments,nutrition_data_per,lang,categories_tags"

    /**
     * Το ψηφίο ελέγχου GTIN για το [body] (τα ψηφία χωρίς το ψηφίο ελέγχου): από δεξιά, βάρη 3, 1, 3, 1…· το ψηφίο είναι
     * όσο λείπει ως το επόμενο πολλαπλάσιο του 10. null αν το [body] δεν είναι μόνο ψηφία.
     */
    fun checkDigit(body: String): Int? {
        if (body.isEmpty() || !body.all { it in '0'..'9' }) return null
        var sum = 0
        for ((n, ch) in body.reversed().withIndex()) sum += (ch - '0') * (if (n % 2 == 0) 3 else 1)
        return (10 - sum % 10) % 10
    }

    /**
     * UPC-E (ο «σύντομος» κωδικός σε μικρές συσκευασίες, κυρίως αμερικανικές) → UPC-A 12 ψηφίων, με τον οποίο είναι
     * γραμμένο το προϊόν στο Open Food Facts. Ο σαρωτής δίνει 8 ψηφία: σύστημα (0 ή 1), έξι ψηφία, ψηφίο ελέγχου. Το
     * τελευταίο από τα έξι λέει πού μπαίνουν τα μηδενικά (προδιαγραφή GS1):
     * - 0, 1, 2: κατασκευαστής «ab» + αυτό + «00», προϊόν «00cde»
     * - 3: κατασκευαστής «abc00», προϊόν «000de»
     * - 4: κατασκευαστής «abcd0», προϊόν «0000e»
     * - 5–9: κατασκευαστής «abcde», προϊόν «0000» + αυτό
     * Το ψηφίο ελέγχου είναι το ίδιο και στις δύο μορφές: αν δεν συμφωνεί, null (δεν είναι UPC-E· μένει όπως ήρθε).
     * Πριν (ως το Συμβούλιο 3) τα 8 ψηφία ενός UPC-E πήγαιναν στο Open Food Facts σαν EAN-8 και το προϊόν «δεν υπήρχε».
     */
    fun upceToUpca(raw: String): String? {
        val c = raw.trim()
        if (c.length != 8 || !c.all { it in '0'..'9' }) return null
        val system = c[0]
        if (system != '0' && system != '1') return null
        val six = c.substring(1, 7)
        val maker: String
        val product: String
        when (six[5]) {
            '0', '1', '2' -> {
                maker = six.substring(0, 2) + six[5] + "00"
                product = "00" + six.substring(2, 5)
            }
            '3' -> {
                maker = six.substring(0, 3) + "00"
                product = "000" + six.substring(3, 5)
            }
            '4' -> {
                maker = six.substring(0, 4) + "0"
                product = "0000" + six[4]
            }
            else -> {
                maker = six.substring(0, 5)
                product = "0000" + six[5]
            }
        }
        val body = "$system$maker$product"
        val check = checkDigit(body) ?: return null
        if (c[7] - '0' != check) return null
        return body + check
    }

    /**
     * Διαβάζει το πολύ [max] bytes ως κείμενο UTF-8· null αν η απάντηση είναι μεγαλύτερη (δεν είναι προϊόν: π.χ. σελίδα
     * σφάλματος ή κάτι που δεν περιμέναμε). Πριν διαβαζόταν ολόκληρη, όσο μεγάλη κι αν ήταν.
     */
    fun readCapped(input: InputStream, max: Int = OFF_MAX_BYTES): String? {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(16 * 1024)
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            if (out.size() + n > max) return null
            out.write(buf, 0, n)
        }
        return String(out.toByteArray(), Charsets.UTF_8)
    }

    /**
     * Η απάντηση του Open Food Facts (κωδικός HTTP [status], σώμα [body]) όπως τη θέλει η Flutter:
     * - 404, ή JSON χωρίς προϊόν → {"ok": true, "found": false} («δεν υπάρχει στο Open Food Facts»)
     * - JSON με προϊόν → {"ok": true, "found": true, "product": …}
     * - κάθε άλλος κωδικός, κενό ή πολύ μεγάλο σώμα ([body] null), ή σώμα που δεν είναι JSON → {"ok": false,
     *   "kind": "connection"} («δεν έγινε σύνδεση»).
     * Το τελευταίο είναι η διόρθωση (Β5): όταν ο διακομιστής απαντά 200 με σελίδα HTML (συντήρηση, όριο κλήσεων), το
     * σώμα δεν είναι JSON. Πριν αυτό έβγαινε ως άγνωστο σφάλμα «other» και πήγαινε και στην αναφορά σφαλμάτων, ενώ είναι
     * πρόβλημα σύνδεσης και όχι της εφαρμογής.
     */
    fun offReply(status: Int, body: String?): JSONObject {
        if (status == 404) return JSONObject().put("ok", true).put("found", false)
        if (status !in 200..299) return connection("HTTP $status")
        if (body == null) return connection("HTTP $status: too large")
        val j = try {
            JSONObject(body)
        } catch (_: JSONException) {
            return connection("HTTP $status: not JSON")
        }
        val product = j.optJSONObject("product")
        if (j.optInt("status", 0) != 1 || product == null) return JSONObject().put("ok", true).put("found", false)
        return JSONObject().put("ok", true).put("found", true).put("product", product)
    }

    /** Οι γραμμές μιας επαναφοράς, έτοιμες για τη βάση: καταχωρίσεις (id, μέρα, JSON) και προϊόντα (id, JSON). */
    class RestoreRows(val log: List<Triple<String, String, String>>, val foods: List<Pair<String, String>>)

    /**
     * Διαβάζει ό,τι στέλνει η Flutter για επαναφορά από αντίγραφο (Συμβούλιο 4, Γ1): δύο πίνακες JSON, [logJson] με
     * καταχωρίσεις και [foodsJson] με προϊόντα. Κάθε καταχώριση θέλει «id» και «day», κάθε προϊόν «id» (κείμενο, όχι
     * κενό), όπως στις «logPut» και «myFoodPut». Αν έστω ένα στοιχείο δεν είναι σωστό, πετά σφάλμα και ΔΕΝ γράφεται
     * τίποτα: καλύτερα καμία επαναφορά από μια μισή. Το JSON κάθε γραμμής γράφεται όπως ήρθε.
     */
    fun restoreRows(logJson: String, foodsJson: String): RestoreRows {
        val log = JSONArray(logJson)
        val foods = JSONArray(foodsJson)
        val outLog = ArrayList<Triple<String, String, String>>(log.length())
        for (i in 0 until log.length()) {
            val o = log.optJSONObject(i)
            val id = (o?.opt("id") as? String).orEmpty()
            val day = (o?.opt("day") as? String).orEmpty()
            require(o != null && id.isNotEmpty() && day.isNotEmpty()) { "Επαναφορά: καταχώριση ${i + 1} χωρίς id ή day" }
            outLog.add(Triple(id, day, o.toString()))
        }
        val outFoods = ArrayList<Pair<String, String>>(foods.length())
        for (i in 0 until foods.length()) {
            val o = foods.optJSONObject(i)
            val id = (o?.opt("id") as? String).orEmpty()
            require(o != null && id.isNotEmpty()) { "Επαναφορά: προϊόν ${i + 1} χωρίς id" }
            outFoods.add(id to o.toString())
        }
        return RestoreRows(outLog, outFoods)
    }

    private fun connection(message: String): JSONObject =
        JSONObject().put("ok", false).put("kind", "connection").put("message", message)
}
