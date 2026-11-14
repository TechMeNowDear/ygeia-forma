package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * Round 1 · f3 (απλό JVM, χωρίς συσκευή): χαλασμένο prefs.json (S3-2 / S9-1), ζώνη ώρας της εγγραφής (S3-8) και οι
 * δοκιμές ορίων του S12 για τους κανόνες του DataRules. Όλες οι τιμές είναι φανταστικές.
 */
class R1F3Test {
    @Test
    fun prefsAreReadableOnlyAsAJsonObject() {
        assertTrue(DataRules.prefsReadable("{}"))
        assertTrue(DataRules.prefsReadable("""{"goals":{"v":1,"kcal":2250},"waist":[{"d":"2026-11-20","v":[101.5,101.0]}]}"""))
        assertTrue(DataRules.prefsReadable("  {\"cards\":{}}\n"))
        // Άδειο αρχείο, κομμένο κείμενο, όχι αντικείμενο: χαλασμένο (η Flutter δεν ξεκινά από προεπιλογές).
        assertFalse(DataRules.prefsReadable(""))
        assertFalse(DataRules.prefsReadable("   "))
        assertFalse(DataRules.prefsReadable("{\"goals\":{\"v\":1,"))
        assertFalse(DataRules.prefsReadable("[]"))
        assertFalse(DataRules.prefsReadable("null"))
        assertFalse(DataRules.prefsReadable("42"))
        assertFalse(DataRules.prefsReadable("\"κείμενο\""))
        assertFalse(DataRules.prefsReadable("{\"a\":1}{\"b\":2}"))
    }

    @Test
    fun unreadablePrefsAreSetAsideAndKeptNeverDeleted() {
        val root = Files.createTempDirectory("ygeia-prefs").toFile()
        val f = File(root, "prefs.json")
        // Δεν υπάρχει αρχείο: τίποτα να γίνει.
        assertTrue(DataRules.setAsideUnreadablePrefs(f, 7L))
        assertTrue(root.listFiles()!!.isEmpty())
        // Κομμένο αρχείο: μετονομάζεται σε «.bad» με τα ίδια byte· η θέση του αδειάζει για νέες ρυθμίσεις.
        f.writeText("{\"goals\":{\"v\":1,")
        assertTrue(DataRules.setAsideUnreadablePrefs(f, 7L))
        assertFalse(f.exists())
        assertEquals("{\"goals\":{\"v\":1,", File(root, "prefs.json.bad").readText())
        // Δεύτερη φορά: το πρώτο αντίγραφο ΔΕΝ γράφεται από πάνω· το νέο παίρνει την ώρα στο όνομα.
        f.writeText("")
        assertTrue(DataRules.setAsideUnreadablePrefs(f, 1763000000000L))
        assertFalse(f.exists())
        assertEquals("{\"goals\":{\"v\":1,", File(root, "prefs.json.bad").readText())
        assertEquals("", File(root, "prefs.json.1763000000000.bad").readText())
        root.deleteRecursively()
    }

    @Test
    fun readablePrefsAreNeverSetAside() {
        val root = Files.createTempDirectory("ygeia-prefs").toFile()
        val f = File(root, "prefs.json")
        val text = """{"goals":{"v":1,"kcal":2250},"me":{"by":1985}}"""
        f.writeText(text)
        assertFalse("αρχείο που διαβάζεται δεν μετακινείται ποτέ", DataRules.setAsideUnreadablePrefs(f, 7L))
        assertEquals(text, f.readText())
        assertFalse(File(root, "prefs.json.bad").exists())
        root.deleteRecursively()
    }

    @Test
    fun recordZoneOffsetInMinutes() {
        // S3-8: +2 ώρες (Αθήνα, χειμώνας), +3 (καλοκαίρι), −5 (Νέα Υόρκη), +5:30, UTC.
        assertEquals(120, DataRules.offsetMinutes(7200))
        assertEquals(180, DataRules.offsetMinutes(10800))
        assertEquals(-300, DataRules.offsetMinutes(-18000))
        assertEquals(330, DataRules.offsetMinutes(19800))
        assertEquals(0, DataRules.offsetMinutes(0))
        // Τα άκρα των ζωνών (±18 ώρες) μετρούν· πιο έξω ή χωρίς τιμή: null (η Flutter κρατά τη ζώνη του κινητού).
        assertEquals(1080, DataRules.offsetMinutes(64800))
        assertEquals(-1080, DataRules.offsetMinutes(-64800))
        assertNull(DataRules.offsetMinutes(64801))
        assertNull(DataRules.offsetMinutes(-64801))
        assertNull(DataRules.offsetMinutes(null))
    }

    @Test
    fun scaleAppSameExamplesAsDart() {
        // S12-16: τα ίδια παραδείγματα με το test/r1_f3_test.dart («ζυγαριά InBody»).
        for (app in listOf("com.inbody2014.inbody", "kr.co.InBody.x", "COM.INBODY.APP")) assertTrue(app, DataRules.isScaleApp(app))
        for (app in listOf("com.sec.android.app.shealth", "com.samsung.android.wear.shealth", "com.google.android.apps.healthdata", "")) {
            assertFalse(app, DataRules.isScaleApp(app))
        }
        assertFalse(DataRules.isScaleApp(null))
    }

    @Test
    fun resultStartPriorityAndWipeBoundaries() {
        // Το «start» κερδίζει το id· το id μόνο με τη μορφή του ρολογιού· αλλιώς η ώρα που γράφτηκε.
        assertEquals(1763000000000L, DataRules.resultStart("""{"id":"walk1762000000000","start":1763000000000}""", 5L))
        assertEquals(1762000000000L, DataRules.resultStart("""{"id":"walk1762000000000"}""", 5L))
        assertEquals(1762000000000L, DataRules.resultStart("""{"id":"w1762000000000"}""", 5L))
        assertEquals(1762000000000L, DataRules.resultStart("""{"id":"hrs12-1762000000000"}""", 5L))
        assertEquals(5L, DataRules.resultStart("""{"id":"x1762000000000"}""", 5L))
        assertEquals(5L, DataRules.resultStart("""{"id":"walk12345678"}""", 5L))
        assertEquals(5L, DataRules.resultStart("""{"start":"1763000000000"}""", 5L))
        // Ακριβώς στη στιγμή της διαγραφής: ΔΕΝ είναι «πριν».
        assertFalse(DataRules.droppedByWipe(1763000000000L, 1763000000000L))
        assertTrue(DataRules.droppedByWipe(1762999999999L, 1763000000000L))
        assertFalse(DataRules.writtenBeforeWipe(1763000000000L, 1763000000000L))
        assertTrue(DataRules.writtenBeforeWipe(1762999999999L, 1763000000000L))
        assertFalse(DataRules.writtenBeforeWipe(1L, 0L))
    }

    @Test
    fun widgetTargetsAndPreviewSizeAtTheLimits() {
        assertEquals("w:sleep:section:", DataRules.widgetOpenTarget("w:sleep:section:"))
        assertEquals("w:food:add:M1_abc.2", DataRules.widgetOpenTarget("w:food:add:M1_abc.2"))
        assertEquals("w:workout:today:" + "a".repeat(32), DataRules.widgetOpenTarget("w:workout:today:" + "a".repeat(32)))
        assertNull(DataRules.widgetOpenTarget("w:workout:today:" + "a".repeat(33)))
        assertNull(DataRules.widgetOpenTarget("w:labs:section:"))
        assertNull(DataRules.widgetOpenTarget("w:sleep:delete:"))
        assertNull(DataRules.widgetOpenTarget("w:sleep:section:../x"))
        assertNull(DataRules.widgetOpenTarget("https://example.com"))
        assertNull(DataRules.widgetOpenTarget(null))
        assertNull(DataRules.previewDp(39))
        assertEquals(40.0, DataRules.previewDp(40)!!, 0.0)
        assertEquals(1200.0, DataRules.previewDp(1200)!!, 0.0)
        assertNull(DataRules.previewDp(1201))
    }

    @Test
    fun sleepSessionsWithoutUsableTimesAreSkippedNotInvented() {
        // Συνεδρία με τέλος πριν από την αρχή, ή χωρίς χρόνους και χωρίς φάσεις: παραλείπεται· η άλλη μένει όπως είναι.
        val good = DataRules.SessionIn(1_000L, 61_000L, null, emptyList())
        val backwards = DataRules.SessionIn(90_000L, 80_000L, 3L, emptyList())
        val empty = DataRules.SessionIn(null, null, null, emptyList())
        assertEquals(
            listOf(DataRules.SleepOut(1_000L, 61_000L, 1L, null, emptyList())),
            DataRules.splitSleep(0L, 200_000L, 3L, 70, listOf(backwards, good, empty)),
        )
        // Καμία συνεδρία δεν στέκει: μένει η εγγραφή ολόκληρη, με τη βαθμολογία της.
        assertEquals(
            listOf(DataRules.SleepOut(0L, 200_000L, 3L, 70, emptyList())),
            DataRules.splitSleep(0L, 200_000L, 3L, 70, listOf(backwards, empty)),
        )
    }
}
