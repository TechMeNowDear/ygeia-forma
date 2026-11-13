package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Έλεγχος round1 (f2 · S2-1 / S1-9): η αναζήτηση barcode στο Open Food Facts ζητά και τις κατηγορίες του προϊόντος
 * («categories_tags»), ώστε ένα σαρωμένο προϊόν (π.χ. σκέτα καρύδια) να μετρά στην κάρτα «Χοληστερίνη». Τα πεδία που
 * ζητούσε η #100 μένουν όλα, με την ίδια σειρά.
 */
class R1F2Test {
    @Test
    fun offFieldsKeepTheOldOnesAndAddCategories() {
        val old = listOf(
            "code", "product_name", "product_name_el", "generic_name_el", "brands", "quantity", "serving_size",
            "serving_quantity", "nutriments", "nutrition_data_per", "lang",
        )
        val fields = FoodRules.OFF_FIELDS.split(",")
        assertEquals(old + "categories_tags", fields)
        assertEquals("κανένα πεδίο δύο φορές", fields.size, fields.toSet().size)
    }

    @Test
    fun offFieldsAreSafeInTheUrl() {
        // Μπαίνουν όπως είναι στο URL (FoodBridge.offLookup): μόνο λατινικά πεζά, ψηφία, «_» και «,».
        assertTrue(FoodRules.OFF_FIELDS.matches(Regex("^[a-z0-9_,]+$")))
        assertFalse(FoodRules.OFF_FIELDS.contains(" "))
    }
}
