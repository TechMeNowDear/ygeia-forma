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
        val est = estMeters(812, 0.72) // 584,64 m
        assertEquals(584.64, est, 1e-9)
        // Μέσα στο σπίτι, GPS ανοιχτό χωρίς σήμα (0 m) ή με θόρυβο (6 m): από τα βήματα.
        assertTrue(useEstimate(0.0, true, est, null))
        assertTrue(useEstimate(6.0, true, est, null))
        assertEquals(584.64 to true, shownDistance(0.0, true, 812, 0.72, true).let { (m, a) -> Math.round(m * 100) / 100.0 to a })
        // Έξω: GPS 2.180 m με εκτίμηση 2.088 m: το GPS.
        assertFalse(useEstimate(2180.0, true, 2088.0, null))
        assertEquals(2180.0 to false, shownDistance(2180.0, true, 2900, 0.72, false))
        // Υστέρηση (round 14, W10): από τα βήματα στο GPS μόνο στο 80%, πίσω στα βήματα μόνο κάτω από το 50%.
        assertTrue(useEstimate(600.0, true, 1000.0, true)) // 60%: μένει στα βήματα
        assertTrue(useEstimate(600.0, true, 1000.0, null))
        assertFalse(useEstimate(800.0, true, 1000.0, true)) // 80%: GPS
        assertFalse(useEstimate(600.0, true, 1000.0, false)) // από GPS, 60%: μένει GPS
        assertTrue(useEstimate(490.0, true, 1000.0, false)) // κάτω από 50%: βήματα
        // Κλειστή τοποθεσία: το Health Services (από τα βήματα του ρολογιού), με «≈».
        assertFalse(useEstimate(1500.0, false, 1440.0, null))
        assertEquals(1500.0 to true, shownDistance(1500.0, false, 2000, 0.72, false))
        // Χωρίς μήκος βήματος (παλιό κινητό): ούτε εκτίμηση ούτε «0,00».
        assertFalse(useEstimate(0.0, true, estMeters(812, null), null))
        assertEquals(0.0, shownDistance(0.0, true, 812, null, false).first, 0.0)
        // Η απόσταση της οθόνης δεν πάει πέρα-δώθε γύρω από το όριο: 1.008 m βήματα, GPS 500 → 510 → 505.
        var prev: Boolean? = null
        val shown = mutableListOf<Double>()
        for (g in listOf(0.0, 500.0, 510.0, 505.0, 520.0)) {
            prev = useEstimate(g, true, 1008.0, prev)
            shown.add(if (prev) 1008.0 else g)
        }
        assertEquals(listOf(1008.0, 1008.0, 1008.0, 1008.0, 1008.0), shown)
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
        assertTrue(p.voiceKnown)
        // Παλιό κινητό: φωνή ανοιχτή, καμία εκτίμηση, και δεν ρωτιέται να πει φράσεις (δεν θα απαντούσε· round 14).
        val old = Plan.parse(JSONObject().put("workouts", org.json.JSONArray()).toString())!!
        assertTrue(old.voice)
        assertFalse(old.voiceKnown)
        assertNull(old.stride)
    }

    @Test
    fun walkLineShowsDistanceAndSteps() {
        // Απόσταση και ρυθμός (αίτημα χρήστη 14/11, μετά το round 14), από κάτω τα βήματα.
        assertEquals("≈ 0,58 km · 12:12 /km" to "812 βήματα", walkLines(584.64 to true, 812, 428))
        assertEquals("2,18 km · 11:15 /km" to "2.900 βήματα", walkLines(2180.0 to false, 2900, 1471))
        // Λιγότερο από 50 m: χωρίς ρυθμό (θα ήταν θόρυβος).
        assertEquals("≈ 0,04 km" to "60 βήματα", walkLines(40.0 to true, 60, 30))
        assertEquals("812 βήματα" to null, walkLines(0.0 to false, 812, 428))
        assertEquals("1 βήμα" to null, walkLines(0.0 to false, 1, 1))
        assertEquals("—" to null, walkLines(0.0 to false, 0, 0))
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
        assertTrue(view.contains("if (kmFlashOn(now)) drawKmFlash(c, now) else drawAmbient(c, now)"))
        // Round 14: στην αχνή οθόνη πράσινα γράμματα σε μαύρο, και τέλος στα 2″ (όχι ως το επόμενο λεπτό).
        assertTrue(view.contains("if (!ambient) c.drawColor(green)"))
        assertTrue(view.contains("postInvalidateDelayed((Repo.kmFlashUntil - now).coerceIn(0L, KM_FLASH_MS) + 50L)"))
        // Στον δίσκο αμέσως: μετά από απότομο κλείσιμο δεν ξαναλέει το ίδιο χιλιόμετρο.
        assertTrue(svc.indexOf("saveRun(force = true)", svc.indexOf("speak(Say.km(k))")) - svc.indexOf("speak(Say.km(k))") < 200)
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
        // Στο 133 (μόνο 1 κάτω): όχι ακόμα «πίσω». Στο 131 (3 κάτω) ξαναοπλίζεται· «Πάλι στη ζώνη» αφού μείνει μέσα 10″
        // (round 14), μία φορά.
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(133, t0 + 6_000L))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(131, t0 + 7_000L))
        for (k in 8..16) assertEquals("$k″", ZoneAlarm.Buzz.NONE, z.feed(125, t0 + k * 1000L))
        assertEquals(ZoneAlarm.Buzz.BACK, z.feed(125, t0 + 17_000L))
        assertEquals(ZoneAlarm.Buzz.NONE, z.feed(125, t0 + 18_000L))
        // Ξανά πάνω αμέσως: όχι νέο «Εκτός εύρους» πριν περάσει 1 λεπτό από το προηγούμενο (round 14: όχι φλυαρία).
        for (k in 20..64) assertEquals("$k″", ZoneAlarm.Buzz.NONE, z.feed(139, t0 + k * 1000L))
        assertEquals(ZoneAlarm.Buzz.UP, z.feed(139, t0 + 65_000L))
        // Γύρω από το πάνω όριο (6″ στο 136, 4″ στο 131, για 2 λεπτά): πριν 12 δονήσεις και 24 φράσεις, τώρα 2 δονήσεις
        // (μία το λεπτό το πολύ) και καμία φωνή «Πάλι στη ζώνη» (ποτέ 10″ μέσα).
        val o = ZoneAlarm()
        o.start(WalkZone(116, 134), 0)
        val events = mutableListOf<ZoneAlarm.Buzz>()
        for (k in 0..120) o.feed(if (k % 10 < 6) 136 else 131, t0 + k * 1000L).takeIf { it != ZoneAlarm.Buzz.NONE }?.let { events.add(it) }
        assertEquals(listOf(ZoneAlarm.Buzz.UP, ZoneAlarm.Buzz.UP), events)
        // Μετά από παύση, συνέχεια κάτω από τη ζώνη: όχι «Πάλι στη ζώνη» (round 14, W6).
        val p = ZoneAlarm()
        p.start(WalkZone(116, 134), 0)
        for (k in 0..5) p.feed(139, t0 + k * 1000L)
        p.feed(125, t0 + 6_000L)
        p.hold()
        for (k in 0..30) assertEquals(ZoneAlarm.Buzz.NONE, p.feed(95, t0 + 300_000L + k * 1000L))
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
        assertEquals("Οι παλμοί σου έπεσαν κατά 18" to "Your heart rate dropped by 18", Say.recovery(18))
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
        // Όλο μαζί το πολύ 2,5″, μετά μιλά το ρολόι. Το κινητό απαντά «το λέω» μόνο ως 1″ πριν (να προλάβει να φτάσει).
        assertEquals(2_500L, SAY_WAIT_MS)
        assertEquals(1_000L, SAY_REPLY_MS)
        val link = source("Link.kt")
        assertTrue(link.contains("withTimeoutOrNull(SAY_WAIT_MS) { sendJson(ctx, Paths.SAY, o, nearbyOnly = true) && wait.await() } == true"))
        assertTrue(link.contains(".put(\"until\", System.currentTimeMillis() + SAY_WAIT_MS - SAY_REPLY_MS)"))
        assertTrue(link.contains("if (nearbyOnly && !n.isNearby) continue"))
        val voice = source("Voice.kt")
        // Ακουστικά στο ρολόι → το ρολόι· αλλιώς ρωτά το κινητό· αλλιώς το ηχείο του ρολογιού. Η μουσική χαμηλώνει.
        assertTrue(voice.contains("if (headsetHere() || !askPhone) {"))
        assertTrue(voice.contains("if (phone) phoneCount++ else speakHere(p)"))
        assertTrue(voice.contains("AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK"))
        // Round 14: η σύνδεση ακούει την απάντηση όσο περιμένει· η φωνή κλείνει μόνη της όταν δεν την κρατά η άσκηση.
        assertTrue(voice.contains("Link.attach(ctx)") && voice.contains("Link.detach(ctx)"))
        assertTrue(voice.contains("private fun idleStop()"))
        assertTrue(voice.contains("KEY_FEATURE_NOT_INSTALLED"))
        val svc = source("ExerciseService.kt")
        // «Ξεκινάμε» μόνο αφού ξεκίνησε η μέτρηση· η πτώση των παλμών αφού έρθουν οι τελευταίες τιμές.
        assertTrue(svc.indexOf("if (walk) speak(Say.START)") > svc.indexOf("val gpsOk = startForegroundOrWithoutGps(n, type, location)"))
        assertTrue(svc.indexOf("if (recoveryDone) speak(") > svc.indexOf("hsCall(\"clear\") { client.clearUpdateCallbackAsync(callback).await() }"))
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
        Repo.updateDistanceSource()
        val (_, o) = Results.build(t + 428_000)!!
        assertEquals(585L, o.getJSONObject("cardio").getLong("mest"))
        // Όταν η οθόνη έδειχνε GPS: χωρίς «mest» (το κινητό δείχνει ό,τι το ρολόι).
        Repo.meters = 700.0
        Repo.updateDistanceSource()
        val (_, o1) = Results.build(t + 428_000)!!
        assertFalse(o1.getJSONObject("cardio").has("mest"))
        Repo.meters = 0.0
        Repo.stride = null
        Repo.updateDistanceSource()
        val (_, o2) = Results.build(t + 428_000)!!
        assertFalse(o2.getJSONObject("cardio").has("mest"))
        Repo.resetExercise()
    }
}
