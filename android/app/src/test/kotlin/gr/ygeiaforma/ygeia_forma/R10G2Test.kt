package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Round 10 · g2: R10-B2-1 (νέο action για το πάτημα widget, ώστε τα widgets που ήταν ήδη στην αρχική οθόνη να πάρουν
 * νέο PendingIntent με CLEAR_TOP). Καθαρό JVM: οι δοκιμές της εφαρμογής κινητού τρέχουν χωρίς Android (ούτε Robolectric),
 * άρα το ίδιο το PendingIntent δεν φτιάχνεται εδώ· ελέγχεται η σταθερά από την οποία το φτιάχνει το HomeWidgets.open.
 */
class R10G2Test {
    @Test
    fun widgetTapActionNoLongerMatchesTheOldPendingIntents() {
        // Ως το #108 το action ήταν «gr.ygeiaforma.WIDGET_OPEN.<id>.<part>». Το Android ταιριάζει ένα PendingIntent με
        // action/component/requestCode (Intent.filterEquals), όχι με τις σημαίες του Intent: με το ίδιο action το
        // FLAG_UPDATE_CURRENT θα κρατούσε το παλιό PendingIntent με τις παλιές σημαίες (χωρίς CLEAR_TOP).
        val old = "gr.ygeiaforma.WIDGET_OPEN."
        assertEquals("gr.ygeiaforma.WIDGET_OPEN2.", HomeWidgets.OPEN_ACTION)
        assertFalse(HomeWidgets.OPEN_ACTION.startsWith(old))
        // Κανένα νέο action (widget 7, μέρος 0/1) δεν είναι ίδιο με κάποιο παλιό.
        for (part in 0..1) {
            val now = "${HomeWidgets.OPEN_ACTION}7.$part"
            assertFalse(now == "${old}7.$part")
            assertTrue(now.endsWith("7.$part"))
        }
        // Οι σημαίες μένουν αυτές του R9-A10-2 (NEW_TASK | SINGLE_TOP | CLEAR_TOP).
        assertEquals(0x10000000 or 0x20000000 or 0x04000000, HomeWidgets.OPEN_FLAGS)
    }
}
