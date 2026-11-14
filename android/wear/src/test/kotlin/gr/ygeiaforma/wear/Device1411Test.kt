package gr.ygeiaforma.wear

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Δοκιμή στις συσκευές 14/11 (αιτήματα χρήστη): απόσταση χωρίς GPS, κάθε χιλιόμετρο (δόνηση, πράσινη οθόνη, φωνή),
 * «Εκτός εύρους» σε 5″, φωνή στα ακουστικά/κινητό/ρολόι, tile «Περπάτημα». Οι τιμές που περιμένουμε βγαίνουν από τον
 * γραμμένο κανόνα. Όλα τα νούμερα είναι δοκιμαστικά.
 */
class Device1411Test {
    private fun source(name: String): String = File("src/main/kotlin/gr/ygeiaforma/wear/$name").readText()

    // ------------------------------------------------------------------ απόσταση
    @Test
    fun distanceFromGpsWhenItMeasuresOtherwiseFromSteps() {
        // Μέσα στο σπίτι, GPS ανοιχτό χωρίς σήμα: 812 βήματα × 0,72 = 584,64 m, εκτίμηση.
        assertEquals(584.64 to true, shownDistance(0.0, true, 812, 0.72).let { (m, a) -> Math.round(m * 100) / 100.0 to a })
        // Θόρυβος του GPS (6 m) με 812 βήματα: πάλι η εκτίμηση.
        assertTrue(shownDistance(6.0, true, 812, 0.72).second)
        // Έξω: GPS 2.180 m με 2.900 βήματα (εκτίμηση 2.088): το GPS, όχι εκτίμηση.
        assertEquals(2180.0 to false, shownDistance(2180.0, true, 2900, 0.72))
        // GPS που έπιασε στη μέση (200 m από 2.088 εκτίμηση, κάτω από το μισό): η εκτίμηση.
        assertEquals(true, shownDistance(200.0, true, 2900, 0.72).second)
        // Κλειστή τοποθεσία: το Health Services δίνει απόσταση από τα βήματα· «≈».
        assertEquals(1500.0 to true, shownDistance(1500.0, false, 2000, 0.72))
        // Χωρίς μήκος βήματος (παλιό κινητό) και χωρίς GPS: τίποτα.
        assertEquals(0.0, shownDistance(0.0, true, 812, null).first, 0.0)
        assertEquals(0.0, estMeters(812, null), 0.0)
        assertEquals(584.64, estMeters(812, 0.72), 1e-9)
    }

    @Test
    fun strideOnlyWhenSensible() {
        assertNull(strideOrNull(Double.NaN))
        assertNull(strideOrNull(0.3))
        assertNull(strideOrNull(1.5))
        assertEquals(0.72, strideOrNull(0.72)!!, 0.0)
        val j = JSONObject().put("workouts", org.json.JSONArray()).put("stride", 0.73).put("voice", false)
        val p = Plan.parse(j.toString())!!
        assertEquals(0.73, p.stride!!, 0.0)
        assertFalse(p.voice)
        // Παλιό κινητό: φωνή ανοιχτή, καμία εκτίμηση.
        val old = Plan.parse(JSONObject().put("workouts", org.json.JSONArray()).toString())!!
        assertTrue(old.voice)
        assertNull(old.stride)
    }

    @Test
    fun walkLineShowsDistanceAndSteps() {
        assertEquals("≈ 0,58 km · 812 βήματα", walkLine(584.64 to true, 812))
        assertEquals("2,18 km · 2.900 βήματα", walkLine(2180.0 to false, 2900))
        assertEquals("812 βήματα", walkLine(0.0 to false, 812))
        assertEquals("1 βήμα", walkLine(0.0 to false, 1))
        assertEquals("—", walkLine(0.0 to false, 0))
        assertEquals("12.345", thousandsEl(12_345))
    }

    // ------------------------------------------------------------------ χιλιόμετρα
    @Test
    fun kilometreWordsAndAnnouncements() {
        assertEquals("Πρώτο χιλιόμετρο", kmTitle(1))
        assertEquals("Δεύτερο χιλιόμετρο", kmTitle(2))
        assertEquals("Δέκατο τρίτο χιλιόμετρο", kmTitle(13))
        assertEquals("Εικοστό χιλιόμετρο", kmTitle(20))
        assertEquals("Χιλιόμετρο 21", kmTitle(21))
        assertEquals("First kilometer", kmSpeechEn(1))
        assertEquals("Twelfth kilometer", kmSpeechEn(12))
        assertEquals("Kilometer 25", kmSpeechEn(25))
        assertEquals(Say.km(3), "Τρίτο χιλιόμετρο" to "Third kilometer")
        // Κάθε χιλιόμετρο μία φορά, ποτέ προς τα πίσω (π.χ. όταν το GPS πιάσει και η απόσταση μικρύνει).
        assertEquals(0, kmToAnnounce(999.0, 0))
        assertEquals(1, kmToAnnounce(1000.0, 0))
        assertEquals(0, kmToAnnounce(1500.0, 1))
        assertEquals(2, kmToAnnounce(2001.0, 1))
        assertEquals(0, kmToAnnounce(900.0, 1))
        assertEquals(2_000L, KM_FLASH_MS)
    }

    @Test
    fun serviceAnnouncesEachKilometreWithBuzzFlashAndVoice() {
        val svc = source("ExerciseService.kt")
        assertTrue(svc.contains("val k = kmToAnnounce(Repo.shown().first, Repo.kmDone)"))
        assertTrue(svc.contains("Repo.kmFlashUntil = now + KM_FLASH_MS"))
        assertTrue(svc.contains("speak(Say.km(k))"))
        // Ποτέ σε παύση ή στο λεπτό αποκατάστασης.
        assertTrue(svc.contains("if (Repo.running != \"walk\" || Repo.paused || Repo.recoveryUntil > 0 || stopping) return"))
        val view = source("WatchView.kt")
        assertTrue(view.contains("if (kmFlashOn(now)) drawKmFlash(c) else drawAmbient(c, now)"))
    }

    // ------------------------------------------------------------------ ζώνη: 5″ και «Πάλι στη ζώνη»
    @Test
    fun offRangeAfterFiveSecondsAndBackInRange() {
        assertEquals(5_000L, ZONE_HOLD_MS)
        val z = ZoneAlarm()
        z.start(WalkZone(116, 134), 0)
        val t0 = 400_000L
        // 4″ πάνω: τίποτα· στα 5″: δόνηση και «Εκτός εύρους».
        for (k in 0..4) assertEquals("$k″", ZoneAlarm.Buzz.NONE, z.feed(139, t0 + k * 1000L))
        assertEquals(ZoneAlarm.Buzz.UP, z.feed(139, t0 + 5_000L))
        // Στο 133 (μόνο 1 κάτω): όχι ακόμα «πίσω»· στο 131 (3 κάτω): «Πάλι στη ζώνη», μία φορά.
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(133, t0 + 6_000L))
        assertEquals(ZoneAlarm.Buzz.BACK, z.feed(131, t0 + 7_000L))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(125, t0 + 8_000L))
        // Χωρίς δόνηση πριν, κανένα «πίσω».
        val q = ZoneAlarm()
        q.start(WalkZone(116, 134), 0)
        assertEquals(ZoneAlarm.Buzz.NONE, q.feed(120, t0))
        // Ζέσταμα 5′: τίποτα.
        val w = ZoneAlarm()
        w.start(WalkZone(116, 134), 0)
        for (k in 0..20) assertEquals(ZoneAlarm.Buzz.NONE, w.feed(150, k * 1000L))
        // Η υπηρεσία: «Εκτός εύρους» με τη δόνηση, «Πάλι στη ζώνη» μόνο φωνή.
        val svc = source("ExerciseService.kt")
        assertTrue(svc.contains("speak(Say.BACK)"))
        assertTrue(svc.contains("speak(Say.OFF_RANGE)"))
        assertEquals("Εκτός εύρους" to "Off range", Say.OFF_RANGE)
    }

    // ------------------------------------------------------------------ φωνή
    @Test
    fun voicePhrasesAndRecovery() {
        assertEquals("Οι παλμοί σου έπεσαν 18" to "Your heart rate dropped by 18", Say.recovery(18))
        assertNull(Say.recovery(0))
        assertNull(Say.recovery(-3))
        assertEquals("Επόμενο σετ", Say.NEXT_SET.first)
    }

    @Test
    fun femaleVoiceOnlyWhenTheNameSaysSo() {
        assertEquals("el-GR-SMTf00", femaleVoiceName(listOf("el-GR-SMTm00", "el-GR-SMTf00")))
        assertEquals("en-us-female-1", femaleVoiceName(listOf("en-us-x-iom-local", "en-us-female-1")))
        assertNull(femaleVoiceName(listOf("el-gr-x-vfz-local", "el-gr-x-abc-network")))
        assertNull(femaleVoiceName(emptyList()))
    }

    @Test
    fun phoneReplyToSay() {
        assertEquals("s1" to true, sayReply("""{"id":"s1","ok":true}"""))
        assertEquals("s2" to false, sayReply("""{"id":"s2"}"""))
        assertNull(sayReply("""{"ok":true}"""))
        assertNull(sayReply("όχι json"))
        assertEquals("/ygeia/say", Paths.SAY)
        assertEquals("/ygeia/said", Paths.SAID)
        // Όλο μαζί το πολύ 2,5″, μετά μιλά το ρολόι.
        assertEquals(2_500L, SAY_WAIT_MS)
        val link = source("Link.kt")
        assertTrue(link.contains("withTimeoutOrNull(SAY_WAIT_MS) { sendJson(ctx, Paths.SAY, o) && wait.await() } == true"))
        val voice = source("Voice.kt")
        // Ακουστικά στο ρολόι → το ρολόι· αλλιώς ρωτά το κινητό· αλλιώς το ηχείο του ρολογιού. Η μουσική χαμηλώνει.
        assertTrue(voice.contains("if (headsetHere()) {"))
        assertTrue(voice.contains("if (phone) phoneCount++ else speakHere(p)"))
        assertTrue(voice.contains("AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK"))
    }

    // ------------------------------------------------------------------ tile
    @Test
    fun tileStartsAWalk() {
        val tile = source("WalkTileService.kt")
        assertTrue(tile.contains(".addKeyToExtraMapping(EXTRA_START, ActionBuilders.AndroidStringExtra.Builder().setValue(START_WALK).build())"))
        val act = source("WatchActivity.kt")
        assertTrue(act.contains("if (Repo.running == null) startWalk()"))
        assertTrue(act.contains("handle(intent, fresh = savedInstanceState == null)"))
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertTrue(manifest.contains("androidx.wear.tiles.action.BIND_TILE_PROVIDER"))
        assertTrue(manifest.contains("android.intent.action.TTS_SERVICE"))
    }

    // ------------------------------------------------------------------ αποτέλεσμα
    @Test
    fun resultCarriesTheStepDistance() {
        Repo.resetExercise()
        val t = 1_700_000_000_000L
        Repo.running = "walk"
        Repo.startedAt = t
        Repo.steps = 812
        Repo.stride = 0.72
        Repo.gps = true
        val (_, o) = Results.build(t + 428_000)!!
        assertEquals(585L, o.getJSONObject("cardio").getLong("mest"))
        Repo.stride = null
        val (_, o2) = Results.build(t + 428_000)!!
        assertFalse(o2.getJSONObject("cardio").has("mest"))
        Repo.resetExercise()
    }
}
