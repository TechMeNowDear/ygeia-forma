package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * Round 11 · h1: R11-C4-2 (1) — η δοκιμή του R10-B2-1 έλεγχε μόνο τη σταθερά [HomeWidgets.OPEN_ACTION] και έφτιαχνε μόνη
 * της τα actions· η επαναφορά του `open()` στο παλιό action («gr.ygeiaforma.WIDGET_OPEN.<id>.<μέρος>») δεν κοκκίνιζε
 * τίποτα. Τώρα το `open()` παίρνει το action από το [WidgetText.openAction] (καθαρό Kotlin, χωρίς Android), που ελέγχεται
 * εδώ με τις αναμενόμενες τιμές γραμμένες με το χέρι.
 */
class R11H1Test {
    @Test
    fun widgetTapActionIsTheNewOneForEveryWidgetAndPart() {
        assertEquals("gr.ygeiaforma.WIDGET_OPEN2.7.0", WidgetText.openAction(7, 0))
        assertEquals("gr.ygeiaforma.WIDGET_OPEN2.7.1", WidgetText.openAction(7, 1))
        assertEquals("gr.ygeiaforma.WIDGET_OPEN2.123.0", WidgetText.openAction(123, 0))
        // Κανένα δεν είναι ίδιο με το action ως το #108 (τότε το FLAG_UPDATE_CURRENT θα κρατούσε το παλιό PendingIntent).
        for (id in listOf(1, 7, 42)) {
            for (part in 0..1) {
                assertFalse(WidgetText.openAction(id, part) == "gr.ygeiaforma.WIDGET_OPEN.$id.$part")
            }
        }
        // Δύο widgets / δύο μέρη δεν μοιράζονται action.
        assertFalse(WidgetText.openAction(1, 0) == WidgetText.openAction(1, 1))
        assertFalse(WidgetText.openAction(1, 0) == WidgetText.openAction(10, 0))
    }
}
