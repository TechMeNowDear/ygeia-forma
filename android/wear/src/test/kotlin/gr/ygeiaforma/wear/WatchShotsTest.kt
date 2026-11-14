package gr.ygeiaforma.wear

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.io.FileOutputStream

/**
 * Στιγμιότυπα των οθονών του ρολογιού από τον πραγματικό κώδικα (WatchView), σε JVM με Robolectric.
 * Γράφονται στο build/watch-shots/ και το CI τα ανεβάζει για έλεγχο με το μάτι.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WatchShotsTest {
    private val size = 454 // Galaxy Watch Ultra: περίπου 1,5″, 480 px· στρογγυλό

    private val planJson = """
        {"v":1,"hrLimit":140,"today":"A","at":1,
         "workouts":[
          {"id":"A","name":"Προπόνηση Α","minutes":50,"items":[
            {"ex":"db_press","name":"Πιεστικό με αλτήρες","rest":120,"lo":8,"hi":12,"rir":2,
             "sets":[{"load":10.3,"label":"10,3 kg","reps":8},{"load":10.3,"label":"10,3 kg","reps":8},{"load":10.3,"label":"10,3 kg","reps":8}]},
            {"ex":"db_row","name":"Κωπηλασία με αλτήρα","rest":90,"lo":8,"hi":12,"rir":2,
             "sets":[{"load":14.3,"label":"14,3 kg","reps":11},{"load":14.3,"label":"14,3 kg","reps":11},{"load":14.3,"label":"14,3 kg","reps":10}]},
            {"ex":"band_pushdown","name":"Pushdown με λάστιχο","rest":60,"lo":12,"hi":15,"rir":2,
             "sets":[{"load":30,"label":"πράσινο (30 lb)","reps":14}]},
            {"ex":"reverse_crunch","name":"Ανάποδο crunch στον πάγκο","rest":60,"lo":10,"hi":15,"rir":2,
             "sets":[{"label":"","reps":13}]}]},
          {"id":"B","name":"Προπόνηση Β","minutes":56,"items":[
            {"ex":"incline_press","name":"Πιεστικό σε κλίση με αλτήρες","rest":120,"lo":8,"hi":12,"rir":2,"sets":[{"load":7.8,"label":"7,8 kg","reps":8}]}]},
          {"id":"walk","name":"Περπάτημα","minutes":30,"cardio":{"activity":"walk","name":"Περπάτημα","minutes":30,"note":"χαλαρά"}}]}
    """.trimIndent()

    private val noop = object : WatchView.Actions {
        override fun startWorkout(id: String) {}
        override fun startWalk() {}
        override fun joinPhone() {}
        override fun tick() {}
        override fun answer(rir: Int) {}
        override fun reps(delta: Int) {}
        override fun nextExercise() {}
        override fun restPlus() {}
        override fun restStop() {}
        override fun finishWorkout() {}
        override fun pauseWalk(on: Boolean) {}
        override fun muteAlarm() {}
        override fun doneOk() {}
        override fun lastReps(delta: Int) {}
    }

    @After
    fun reset() {
        Repo.plan = null
        Repo.phone = null
        Repo.lastPhone = null
        Repo.local = null
        Repo.notice = null
        Repo.knownLimit = null
        Repo.updateNeeded = false
        Repo.screen = Repo.Screen.HOME
        Repo.resetExercise()
        Repo.alarm.limit = null
        WatchView.noHrSeenNow = false
    }

    /** Έλεγχος premium (M4): με 3 προπονήσεις βαρών το τρίτο κουμπί φτάνει σε όλες, κυκλικά. */
    @Test
    fun allWorkoutsReachable() {
        assertEquals("B", nextStrength(listOf("A", "B", "C"), "A"))
        assertEquals("C", nextStrength(listOf("A", "B", "C"), "B"))
        assertEquals("A", nextStrength(listOf("A", "B", "C"), "C"))
        assertEquals(null, nextStrength(listOf("A"), "A"))
        // Επανέλεγχος: «1 άσκηση», όχι «1 ασκήσεις».
        assertEquals("1 άσκηση", countText(1, "άσκηση", "ασκήσεις"))
        assertEquals("4 ασκήσεις", countText(4, "άσκηση", "ασκήσεις"))
        val three = planJson.replace(
            "{\"id\":\"walk\"",
            "{\"id\":\"C\",\"name\":\"Προπόνηση Γ\",\"minutes\":40,\"items\":[{\"ex\":\"goblet\",\"name\":\"Κάθισμα\",\"rest\":90,\"lo\":8,\"hi\":12,\"rir\":2,\"sets\":[{\"load\":12,\"label\":\"12 kg\",\"reps\":10}]}]},\n          {\"id\":\"walk\"",
        )
        Repo.applyPlan(Plan.parse(three))
        Repo.screen = Repo.Screen.HOME
        // Μετά το Β, το τρίτο κουμπί δείχνει τη Γ (πριν: ξανά την Α, η Γ δεν φαινόταν ποτέ).
        shot("W1d_home_third_workout") { it.chosen = "B" }
    }

    /**
     * Γ3 (13/11): η ερώτηση πριν σταματήσει άσκηση άλλης εφαρμογής. Και τα δύο κουμπιά έχουν όνομα για το TalkBack,
     * περιοχή ≥ 40u (≈ 48 dp) που δεν ακουμπά την άλλη, και κάνουν αυτό που γράφουν.
     */
    @Test
    fun otherAppQuestion() {
        Repo.applyPlan(Plan.parse(planJson))
        Repo.screen = Repo.Screen.HOME
        shot("W9_other_app_ask") { it.otherAppAsk = true }
        val did = mutableListOf<String>()
        val acts = object : WatchView.Actions by noop {
            override fun startHere() { did.add("start") }
            override fun cancelStart() { did.add("cancel") }
            override fun startWorkout(id: String) { did.add("workout") }
            override fun startWalk() { did.add("walk") }
        }
        val v = WatchView(RuntimeEnvironment.getApplication(), acts)
        v.otherAppAsk = true
        val spec = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
        v.measure(spec, spec)
        v.layout(0, 0, size, size)
        v.draw(Canvas(Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)))
        val items = v.a11yItems
        assertEquals(listOf(OtherAppAsk.TEXT, OtherAppAsk.YES, OtherAppAsk.NO), items.map { it.first })
        val p = v.accessibilityNodeProvider
        val yes = android.graphics.Rect()
        val no = android.graphics.Rect()
        @Suppress("DEPRECATION")
        p.createAccessibilityNodeInfo(1)!!.getBoundsInParent(yes)
        @Suppress("DEPRECATION")
        p.createAccessibilityNodeInfo(2)!!.getBoundsInParent(no)
        val u = size / 200f
        assertFalse("$yes / $no", android.graphics.Rect.intersects(yes, no))
        assertTrue("$yes", yes.height() >= 40 * u - 1 && yes.width() >= 40 * u - 1)
        assertTrue("$no", no.height() >= 40 * u - 1 && no.width() >= 40 * u - 1)
        val t0 = android.os.SystemClock.uptimeMillis()
        fun tap(x: Float, y: Float) {
            v.dispatchTouchEvent(android.view.MotionEvent.obtain(t0, t0, android.view.MotionEvent.ACTION_DOWN, x, y, 0))
            v.dispatchTouchEvent(android.view.MotionEvent.obtain(t0, t0 + 50, android.view.MotionEvent.ACTION_UP, x, y, 0))
        }
        // Πάνω στο κείμενο: τίποτα (καμία εκκίνηση από την οθόνη που είναι από κάτω).
        tap(size / 2f, 60 * u)
        assertEquals(emptyList<String>(), did)
        tap(yes.exactCenterX(), yes.exactCenterY())
        tap(no.exactCenterX(), no.exactCenterY())
        assertEquals(listOf("start", "cancel"), did)
    }

    private fun shot(name: String, ambient: Boolean = false, prep: (WatchView) -> Unit = {}) {
        val v = WatchView(RuntimeEnvironment.getApplication(), noop)
        v.ambient = ambient
        prep(v)
        val spec = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
        v.measure(spec, spec)
        v.layout(0, 0, size, size)
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        v.draw(c)
        // Στρογγυλή οθόνη: ό,τι είναι έξω από τον κύκλο δεν φαίνεται στο ρολόι.
        val outside = Path().apply {
            fillType = Path.FillType.INVERSE_WINDING
            addCircle(size / 2f, size / 2f, size / 2f, Path.Direction.CW)
        }
        c.drawPath(outside, Paint().apply { color = Color.parseColor("#2A2F36") })
        val dir = File("build/watch-shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue(File(dir, "$name.png").length() > 1000)
    }

    private fun running(now: Long) {
        Repo.running = "strength"
        Repo.startedAt = now - 18 * 60_000
        Repo.bpm = 128
        Repo.bpmAt = now
        Repo.alarm.limit = 140
    }

    @Test
    fun screens() {
        val now = System.currentTimeMillis()
        Repo.applyPlan(Plan.parse(planJson))

        Repo.screen = Repo.Screen.HOME
        shot("W1_home")
        // Σχέδια 9/11: τα γράμματα ακολουθούν τη ρύθμιση μεγέθους του ρολογιού, ως 1,3×.
        RuntimeEnvironment.setFontScale(1.3f)
        shot("W1c_home_font13")
        RuntimeEnvironment.setFontScale(1f)

        val s = LiveSession.fromPlan(Repo.plan!!.todayWorkout!!, now - 18 * 60_000)
        Repo.local = s
        running(now)
        s.tick(now - 200_000)
        s.tick(now - 100_000)
        s.answer(2, now - 90_000)
        s.restEnd = 0
        Repo.screen = Repo.Screen.SET
        shot("W2_set")
        // Έλεγχος γ2 (W3-09): γράμματα 1,3× στο σετ, διάλειμμα, ρεζέρβα.
        RuntimeEnvironment.setFontScale(1.3f)
        shot("W2b_set_font13")
        RuntimeEnvironment.setFontScale(1f)

        s.restEnd = now + 64_000
        Repo.screen = Repo.Screen.REST
        Repo.bpm = 112
        shot("W3_rest")
        // RT-13: το σετ που μόλις έγινε, με − / + στο διάλειμμα (W2-20: δαχτυλίδι 64″ από 120″).
        s.items[0].sets[1].at = now - 56_000
        s.restLen = 120_000
        shot("W3b_rest_edit_reps")
        RuntimeEnvironment.setFontScale(1.3f)
        shot("W3c_rest_font13")
        RuntimeEnvironment.setFontScale(1f)

        Repo.screen = Repo.Screen.RIR
        shot("W4_rir")
        RuntimeEnvironment.setFontScale(1.3f)
        shot("W4b_rir_font13")
        RuntimeEnvironment.setFontScale(1f)

        Repo.bpm = 143
        Repo.alarm.feed(143, now)
        Repo.alarm.feed(143, now + 6_000)
        shot("W5_alarm")
        // W2-16: χωρίς νέους παλμούς ο αριθμός λέει πόσο παλιός είναι.
        Repo.bpmAt = now - 40_000
        shot("W5b_alarm_stale")
        Repo.bpmAt = now

        // Λάστιχο: μεγάλη ετικέτα στη θέση των κιλών.
        Repo.alarm.feed(100, now + 60_000)
        Repo.alarm.feed(100, now + 60_000)
        Repo.bpm = 118
        s.idx = 2
        Repo.screen = Repo.Screen.SET
        shot("W6_set_band")

        // Δεν φτάνουν παλμοί: φαίνεται καθαρά. Πριν από την αναμονή μόνο «δεν μετριούνται»· μετά (χάθηκαν 45″) και «το
        // όριο δεν σε προσέχει».
        Repo.bpmAt = now - 10_000 - 15_000
        shot("W6a_no_hr_waiting")
        Repo.bpmAt = now - 60_000
        Repo.hrSilent = HrSilence.Silence.LOST
        shot("W6b_no_hr")
        Repo.hrSilent = null
        Repo.bpmAt = now

        Repo.local = null
        Repo.resetExercise()
        Repo.running = "walk"
        Repo.startedAt = now - 1471_000
        Repo.activeSec = 1471
        Repo.meters = 2180.0
        Repo.steps = 3104
        Repo.gps = true
        Repo.bpm = 104
        Repo.bpmAt = now
        Repo.screen = Repo.Screen.WALK
        shot("W7_walk")
        RuntimeEnvironment.setFontScale(1.3f)
        shot("W7g_walk_font13")
        RuntimeEnvironment.setFontScale(1f)

        // 9/11 (V-A-04): περπάτημα με όριο, χωρίς κανέναν παλμό: «το όριο δεν σε προσέχει».
        Repo.alarm.limit = 140
        Repo.bpm = 0
        Repo.bpmAt = 0
        Repo.hrSilent = HrSilence.Silence.NEVER
        shot("W7d_walk_no_hr_limit")
        // Σχέδια 9/11 (7γ): μετά το «Εντάξει» μένει «♥ —» σε κεχριμπάρι.
        shot("W7f_walk_no_hr_after_ok") { it.noHrSeen = true }
        Repo.hrSilent = null
        Repo.bpm = 104
        Repo.bpmAt = now
        Repo.alarm.limit = null

        // 9/11: παύση και λεπτό αποκατάστασης.
        Repo.paused = true
        shot("W7b_walk_paused")
        Repo.paused = false
        // Μ3: το πρώτο «Τέλος» στο περπάτημα: «όσο περπατάς ακόμα», στη θέση του «χωρίς GPS».
        Repo.notice = WALK_FINISH_NOTICE
        shot("W7h_walk_finish_notice")
        // S1: «αργή δόνηση» πρώτη, ολόκληρη σε όλη την οθόνη, μαζί με το μήνυμα για το GPS.
        Repo.notice = withSafety(SLOW_ALARM_TEXT, "Χωρίς GPS: η απόσταση από τα βήματα.")
        Repo.openNotice = true
        shot("W7k_walk_slow_alarm")
        RuntimeEnvironment.setFontScale(1.3f)
        Repo.openNotice = true
        shot("W7l_walk_slow_alarm_font13")
        RuntimeEnvironment.setFontScale(1f)
        Repo.openNotice = false
        // RT-18: μόνο παλμοί.
        Repo.notice = "Μόνο παλμοί σε αυτό το περπάτημα."
        Repo.gps = false
        Repo.meters = 0.0
        Repo.steps = 0
        shot("W7i_walk_hr_only")
        Repo.notice = null
        Repo.gps = true
        Repo.meters = 2180.0
        Repo.steps = 3104
        Repo.endAt = now
        Repo.recoveryUntil = now + 47_000
        Repo.screen = Repo.Screen.RECOVER
        shot("W7c_recovery")
        RuntimeEnvironment.setFontScale(1.3f)
        shot("W7j_recovery_font13")
        RuntimeEnvironment.setFontScale(1f)
        // L7: πάνω από το όριο στο λεπτό αποκατάστασης: «Ξεκουράσου», όχι «Κόψε ρυθμό».
        Repo.alarm.limit = 100
        Repo.alarm.reset()
        Repo.alarm.feed(104, now)
        Repo.alarm.feed(104, now + 6_000)
        shot("W5c_alarm_recovery")
        Repo.alarm.limit = null

        // 9/11 (W3-18): περπάτημα χωρίς όριο: γράφεται «χωρίς όριο».
        Repo.recoveryUntil = 0
        Repo.endAt = 0
        Repo.screen = Repo.Screen.WALK
        Repo.alarm.limit = null
        shot("W7e_walk_no_limit")
        // 12/11 (σχέδια 4γ/4δ): ζώνη περπατήματος, χωρίς όριο γιατρού: στη ζώνη, πάνω, κάτω.
        Repo.zoneAlarm.start(WalkZone(108, 131), Repo.startedEl)
        Repo.bpm = 118
        shot("W7m_walk_zone_in")
        Repo.bpm = 136
        shot("W7n_walk_zone_above")
        Repo.bpm = 98
        shot("W7o_walk_zone_below")
        RuntimeEnvironment.setFontScale(1.3f)
        Repo.bpm = 136
        shot("W7p_walk_zone_above_font13")
        RuntimeEnvironment.setFontScale(1f)
        Repo.bpm = 104
        Repo.zoneAlarm.stop()
        // 9/11 (W3-08): ambient, αχνή οθόνη: λεπτά, χωρίς κουμπιά και χρώματα.
        Repo.alarm.limit = 140
        shot("W10_walk_ambient", ambient = true)
        Repo.alarm.limit = null
        // 14/11: μέσα στο σπίτι (GPS χωρίς σήμα): απόσταση από τα βήματα, με «≈»· και η πράσινη οθόνη του χιλιομέτρου.
        val keepM = Repo.meters
        val keepS = Repo.steps
        Repo.meters = 0.0
        Repo.steps = 812
        Repo.stride = 0.72
        shot("W10d_walk_indoor_steps")
        shot("W10e_walk_indoor_ambient", ambient = true)
        Repo.kmFlashN = 1
        Repo.kmFlashUntil = System.currentTimeMillis() + 60_000
        shot("W10c_walk_km_flash")
        RuntimeEnvironment.setFontScale(1.3f)
        Repo.kmFlashN = 13
        shot("W10f_walk_km_flash13_font13")
        RuntimeEnvironment.setFontScale(1f)
        Repo.kmFlashN = 0
        Repo.kmFlashUntil = 0
        Repo.stride = null
        Repo.meters = keepM
        Repo.steps = keepS

        Repo.resetExercise()
        Repo.screen = Repo.Screen.END
        shot("W8_end")
        // 9/11 (V-A-03): η εφαρμογή είχε κλείσει απότομα· το περπάτημα σώθηκε ως μερικό.
        Repo.notice = "Σώθηκε ως τις 18:42: η εφαρμογή έκλεισε πριν το «Τέλος»."
        shot("W8b_end_recovered")
        RuntimeEnvironment.setFontScale(1.3f)
        shot("W8c_end_recovered_font13")
        RuntimeEnvironment.setFontScale(1f)
        Repo.notice = null

        Repo.screen = Repo.Screen.HOME
        // Round 7 (R7-A8-3): αρχή «τώρα» (με αρχή το 1970 θα ήταν ξεχασμένη και η αρχική δεν θα έδειχνε «Παλμοί εδώ»).
        Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s1","w":"A","name":"Προπόνηση Α","start":$now,"idx":1,
            "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"sets":[{"label":"10,3 kg","reps":8,"done":true}]}]}"""))
        shot("W9_home_phone")
        RuntimeEnvironment.setFontScale(1.3f)
        shot("W9e_home_phone_font13")
        RuntimeEnvironment.setFontScale(1f)

        // 9/11: «Ελεύθερη άσκηση» του κινητού, χωρίς ασκήσεις ακόμα.
        Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s2","w":"_free","name":"Ελεύθερη άσκηση","start":1,"idx":0,"items":[]}"""))
        Repo.screen = Repo.Screen.SET
        shot("W9b_free_pick_on_phone")
        Repo.screen = Repo.Screen.HOME

        // 9/11 (W3-13): «Ελεύθερη άσκηση» με μία άσκηση που τελείωσε: «Διάλεξε επόμενη άσκηση στο κινητό».
        Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s3","w":"_free","name":"Ελεύθερη άσκηση","start":1,"idx":0,
            "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"ra":2,"sets":[{"label":"10,3 kg","reps":8,"done":true},{"label":"10,3 kg","reps":8,"done":true}]}]}"""))
        Repo.running = "strength"
        Repo.runningPhone = true
        Repo.startedAt = now - 23 * 60_000
        Repo.bpm = 118
        Repo.bpmAt = now
        Repo.screen = Repo.Screen.SET
        shot("W9c_free_next_on_phone")
        // Πρόγραμμα του κινητού με όλα τα σετ ✓.
        Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s4","w":"A","name":"Προπόνηση Α","start":1,"idx":0,
            "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"ra":2,"sets":[{"label":"10,3 kg","reps":8,"done":true}]}]}"""))
        shot("W9d_all_done")
        // Ambient σε προπόνηση.
        shot("W10b_set_ambient", ambient = true)
        Repo.resetExercise()

        Repo.applyPhone(null)
        Repo.plan = Plan.parse(planJson)
        // 9/11 (V-A-08): πρόγραμμα από νεότερη έκδοση του κινητού.
        Repo.updateNeeded = true
        Repo.screen = Repo.Screen.HOME
        shot("W12_home_update_needed")
        Repo.updateNeeded = false
        // 9/11 (V-A-06): χωρίς πρόγραμμα στο ρολόι, αλλά με το τελευταίο όριο που ήρθε.
        Repo.plan = null
        Repo.knownLimit = 130
        shot("W1b_home_no_plan_known_limit")
        assertEquals(130, Repo.limitNow())
        Repo.knownLimit = null
        Repo.plan = Plan.parse(planJson)
    }

    /** Έλεγχος του #91 (S7, W3-09): το μήνυμα των δύο πατημάτων χωρά ολόκληρο, σε δύο γραμμές. */
    @Test
    fun finishConfirmNotice() {
        val now = System.currentTimeMillis()
        Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s5","w":"A","name":"Προπόνηση Α","start":1,"idx":0,
            "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"sets":[{"label":"10,3 kg","reps":8},{"label":"10,3 kg","reps":8}]}]}"""))
        Repo.running = "strength"
        Repo.runningPhone = true
        Repo.bpm = 118
        Repo.bpmAt = now
        Repo.screen = Repo.Screen.SET
        assertEquals("Πάτα ξανά: τέλος και στο κινητό", finishNotice(true, 2, true))
        assertEquals("Πάτα ξανά «Τέλος»", finishNotice(false, 0, false))
        Repo.notice = finishNotice(true, 0, true)
        shot("W13_finish_phone_empty")
        Repo.notice = finishNotice(true, 0, false)
        shot("W13c_finish_phone_nothing")
        Repo.notice = finishNotice(true, 1, true)
        shot("W13b_finish_phone")
        Repo.notice = null
        Repo.applyPhone(null)
    }

    /** Έλεγχος του #91 (S3): εγγραφή στιγμιοτύπου που φτάνει μετά το τέλος δεν το «ανασταίνει». */
    @Test
    fun lateSnapshotWriteDoesNotResurrect() {
        val ctx = RuntimeEnvironment.getApplication()
        Repo.clearRun(ctx)
        val gen = Repo.runGen
        Repo.clearRun(ctx) // το τέλος πρόλαβε
        assertFalse(Repo.writeRun(ctx, "{\"kind\":\"walk\",\"start\":5}", gen))
        assertEquals(null, Repo.readRun(ctx))
        assertTrue(Repo.writeRun(ctx, "{\"kind\":\"walk\",\"start\":5}"))
        assertEquals(5L, Repo.readRun(ctx)!!.getLong("start"))
        Repo.clearRun(ctx)
    }

    /** Έλεγχος του #91 (S3): μερικό ποτέ πάνω σε κανονικό αποτέλεσμα που περιμένει ακόμα. */
    @Test
    fun partialNeverOverwritesPendingFinal() {
        val ctx = RuntimeEnvironment.getApplication()
        val t0 = 1_700_000_000_000L
        val final = org.json.JSONObject().put("v", 1).put("id", "walk$t0").put("kind", "cardio").put("end", t0 + 1_800_000)
        Repo.savePending(ctx, "walk$t0", final)
        val snap = org.json.JSONObject().put("v", 1).put("kind", "walk").put("start", t0).put("saved", t0 + 600_000)
        assertEquals("walk$t0", Repo.runId(snap))
        assertTrue(Repo.hasFinalPending(ctx, "walk$t0"))
        Repo.writeRun(ctx, snap.toString())
        assertEquals(null, Repo.finalizeRun(ctx, snap, t0 + 3_600_000, 10_000_000))
        val kept = Repo.pendingAll(ctx).first { it.first == "walk$t0" }.second
        assertEquals(t0 + 1_800_000, kept.getLong("end"))
        assertFalse(kept.has("partial"))
        assertEquals(null, Repo.readRun(ctx))
        assertEquals(null, Repo.running)
        Repo.removePending(ctx, "walk$t0")
        // χωρίς κανονικό σε αναμονή: μερικό, στην αναμονή
        val r = Repo.finalizeRun(ctx, snap, t0 + 3_600_000, 10_000_000)!!
        assertEquals(1, r.second.getInt("partial"))
        assertFalse(Repo.hasFinalPending(ctx, "walk$t0"))
        Repo.removePending(ctx, "walk$t0")
    }

    /** Έλεγχος του #91 (S4): στιγμιότυπο που δεν γίνεται αποτέλεσμα: καμία εξαίρεση, κρατιέται (run.bad.json), μήνυμα. */
    @Test
    fun brokenSnapshotIsKeptNotCrashing() {
        val ctx = RuntimeEnvironment.getApplication()
        java.io.File(ctx.filesDir, "run.bad.json").delete()
        val bad = org.json.JSONObject().put("v", 1).put("kind", "walk") // χωρίς «start»
        Repo.writeRun(ctx, bad.toString())
        assertEquals(null, Repo.finalizeRun(ctx, bad, 5_000_000, 10_000))
        assertEquals(null, Repo.readRun(ctx))
        assertTrue(java.io.File(ctx.filesDir, "run.bad.json").exists())
        assertEquals(Repo.BAD_RUN_NOTICE, Repo.notice)
        assertEquals(null, Repo.running)
    }

    /** Έλεγχος του #91 (S2): μετά από συνέχεια, καμία ψεύτικη δόνηση «κανένας παλμός» πριν περάσουν 30″ από τη συνέχεια. */
    @Test
    fun noFalseNoHrBuzzAfterRecovery() {
        val t0 = 1_700_000_000_000L
        val snap = org.json.JSONObject().put("v", 1).put("kind", "walk").put("start", t0).put("saved", t0 + 1_200_000).put("lim", 140)
        val nowEl = 50_000_000L
        assertTrue(Repo.restoreRun(snap, t0 + 1_230_000, nowEl))
        val s = HrSilence()
        assertFalse(s.check(nowEl + 5_000, Repo.startedEl, 0, live = false, hasLimit = true, paused = false, lostMs = 15_000))
        assertFalse(s.check(nowEl + 29_000, Repo.startedEl, 0, live = false, hasLimit = true, paused = false, lostMs = 15_000))
        assertTrue(s.check(nowEl + 30_000, Repo.startedEl, 0, live = false, hasLimit = true, paused = false, lostMs = 15_000))
    }

    /** Έλεγχος 9/11 (V-A-12): ✓ του ρολογιού που δεν επιβεβαιώθηκε πάει στο αποτέλεσμα και όταν το κινητό έκλεισε πρώτο. */
    @Test
    fun unconfirmedTickTravelsInResultAfterPhoneEnded() {
        val now = 1_700_000_000_000L
        Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s9","w":"A","name":"Α","start":$now,"idx":0,
            "items":[{"ex":"db_press","name":"Π","rest":90,"sets":[{"label":"","reps":8,"done":true},{"label":"","reps":8}]}]}"""))
        Repo.running = "strength"
        Repo.runningPhone = true
        Repo.runningSid = "s9"
        Repo.startedAt = now
        Repo.hr = HrStats(now).also { for (k in 0..30) it.add(110, now + k * 1000L) }
        // ✓ στο ρολόι, που το κινητό δεν είδε ποτέ
        Repo.phone!!.items[0].sets[1].apply { done = true; at = now + 20_000 }
        assertEquals(listOf(0 to 1), Repo.pendingTicks)
        // το κινητό κλείνει την προπόνηση πρώτο
        Repo.applyPhone(null)
        assertTrue(Repo.pendingTicks.isEmpty())
        val r = Results.build(now + 60_000, userEnd = true)!!
        assertEquals("hrs9-$now", r.first)
        val log = r.second.getJSONArray("items").getJSONObject(0).getJSONArray("log")
        assertEquals(1, log.getJSONObject(1).getInt("d"))
        assertEquals(now + 20_000, log.getJSONObject(1).getLong("t"))
        assertEquals(now + 60_000, r.second.getLong("fin"))
        assertEquals("s9", r.second.getString("sid"))
    }

    /**
     * Έλεγχος 9/11 (V-A-03): η άσκηση γράφεται ως στιγμιότυπο και ξαναστήνεται όπως ήταν· ως μερική βγαίνει με το ΙΔΙΟ id.
     */
    @Test
    fun walkSnapshotRestoresAndFinalizesWithSameId() {
        val t0 = 1_700_000_000_000L
        Repo.running = "walk"
        Repo.startedAt = t0
        Repo.gps = true
        Repo.hr = HrStats(t0).also { h -> for (k in 0 until 600) h.add(100 + (k % 10), t0 + k * 1000L) }
        Repo.split = SplitTracker(t0).also { it.update(1500.0, t0 + 900_000, 900.0) }
        Repo.meters = 1500.0
        Repo.steps = 2100
        Repo.cpActiveMs = 600_000
        Repo.cpWall = t0 + 600_000
        Repo.cpRunning = true
        Repo.pauses.add(longArrayOf(t0 + 100_000, t0 + 110_000))
        Repo.alarm.limit = 130
        val snap = Repo.captureRun(t0 + 900_000)!!
        val text = snap.toString()
        Repo.resetExercise()
        Repo.alarm.limit = null
        assertTrue(Repo.restoreRun(org.json.JSONObject(text), t0 + 2_000_000, 5_000_000))
        assertEquals("walk", Repo.running)
        assertEquals(t0, Repo.startedAt)
        assertEquals(130, Repo.alarm.limit)
        assertEquals(1, Repo.splits.size)
        assertEquals(1500.0, Repo.meters, 0.01)
        val r = Results.build(t0 + 2_000_000, partialAt = snap.getLong("saved"))!!
        assertEquals("walk$t0", r.first)
        assertEquals(1, r.second.getInt("partial"))
        assertEquals(t0 + 900_000, r.second.getLong("end"))
        val cardio = r.second.getJSONObject("cardio")
        assertEquals(900, cardio.getLong("sec"))
        assertEquals(1, cardio.getJSONArray("km").length())
        assertEquals(600, r.second.getJSONArray("hr").length())
        assertEquals(130, r.second.getInt("lim"))
    }

    /** Προπόνηση με βάρη του ρολογιού: τα ✓ και η τρέχουσα άσκηση ξαναστήνονται από το στιγμιότυπο. */
    @Test
    fun localWorkoutSnapshotKeepsSets() {
        val now = 1_700_000_000_000L
        val s = LiveSession.fromPlan(Plan.parse(planJson)!!.todayWorkout!!, now)
        s.tick(now + 10_000)
        s.tick(now + 200_000)
        Repo.local = s
        val o = Repo.captureRun(now + 300_000) ?: org.json.JSONObject().put("kind", "strength").put("start", now).put("saved", now + 300_000).put("local", s.toState())
        Repo.local = null
        val back = LiveSession.fromState(o.getJSONObject("local"))!!
        assertEquals(s.id, back.id)
        assertEquals(2, back.setsDone)
        assertEquals(now + 200_000, back.items[0].sets[1].at)
        assertEquals("Πιεστικό με αλτήρες", back.items[0].name)
        assertEquals("10,3 kg", back.items[0].sets[0].label)
    }

    @Test
    fun watchTickKeptUntilPhoneSeesIt() {
        fun phone(done: Boolean) = LiveSession.parsePhone(
            "{\"active\":true,\"id\":\"s1\",\"w\":\"A\",\"name\":\"Α\",\"start\":1,\"idx\":0," +
                "\"items\":[{\"ex\":\"db_press\",\"name\":\"Π\",\"rest\":90,\"sets\":[{\"label\":\"\",\"reps\":8${if (done) ",\"done\":true" else ""}},{\"label\":\"\",\"reps\":8}]}]}",
        )
        Repo.applyPhone(null)
        Repo.applyPhone(phone(false))
        // ✓ στο ρολόι· το κινητό (κλειστή εφαρμογή) στέλνει ακόμα την παλιά κατάσταση, και μετά από ώρα
        Repo.phone!!.items[0].sets[0].apply { done = true; at = 1 }
        Repo.applyPhone(phone(false))
        assertTrue(Repo.phone!!.items[0].sets[0].done)
        assertEquals(listOf(0 to 0), Repo.pendingTicks)
        // το κινητό το είδε: επιβεβαιωμένο, τίποτα για αποστολή
        Repo.applyPhone(phone(true))
        assertTrue(Repo.pendingTicks.isEmpty())
        // ο χρήστης το έβγαλε στο κινητό: βγαίνει κι εδώ
        Repo.applyPhone(phone(false))
        assertFalse(Repo.phone!!.items[0].sets[0].done)
        Repo.applyPhone(null)
    }

    /**
     * Έλεγχος γ2 (W3-09): το TalkBack βρίσκει τι δείχνει η οθόνη και κάθε κουμπί με όνομα, και το διπλό πάτημα το πατά.
     * Τα − / + δεν ακουμπούν πουθενά το ✓ (ένα πάτημα στο «−» δεν γράφει σετ).
     */
    @Test
    fun talkBackAndTouchTargets() {
        val now = System.currentTimeMillis()
        Repo.applyPlan(Plan.parse(planJson))
        Repo.local = LiveSession.fromPlan(Repo.plan!!.todayWorkout!!, now)
        running(now)
        Repo.screen = Repo.Screen.SET
        val did = mutableListOf<String>()
        val acts = object : WatchView.Actions by noop {
            override fun tick() { did.add("tick") }
            override fun reps(delta: Int) { did.add("reps$delta") }
        }
        val v = WatchView(RuntimeEnvironment.getApplication(), acts)
        val spec = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
        v.measure(spec, spec)
        v.layout(0, 0, size, size)
        v.draw(Canvas(Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)))
        val items = v.a11yItems
        assertTrue(items.first().first, items.first().first.startsWith("Παλμοί 128"))
        assertFalse(items.first().second)
        val labels = items.map { it.first }
        assertTrue(labels.toString(), "Έγινε το σετ" in labels && "Μία επανάληψη λιγότερη" in labels && "Τέλος" in labels)
        assertTrue(v.a11yClick(labels.indexOf("Έγινε το σετ")))
        assertEquals(listOf("tick"), did)
        // Κάθε σημείο της περιοχής του «−» πατά «−», ποτέ ✓.
        val p = v.accessibilityNodeProvider
        val minus = android.graphics.Rect()
        @Suppress("DEPRECATION")
        p.createAccessibilityNodeInfo(labels.indexOf("Μία επανάληψη λιγότερη"))!!.getBoundsInParent(minus)
        val check = android.graphics.Rect()
        @Suppress("DEPRECATION")
        p.createAccessibilityNodeInfo(labels.indexOf("Έγινε το σετ"))!!.getBoundsInParent(check)
        assertFalse("$minus / $check", android.graphics.Rect.intersects(minus, check))
        // ≥ 48 dp ≈ 40u (u = πλάτος/200)
        val u = size / 200f
        assertTrue("${minus.height()}", minus.height() >= 40 * u - 1 && minus.width() >= 40 * u - 1)
        did.clear()
        val t0 = android.os.SystemClock.uptimeMillis()
        for (y in listOf(minus.top + 2, minus.centerY(), minus.bottom - 2)) {
            v.dispatchTouchEvent(android.view.MotionEvent.obtain(t0, t0, android.view.MotionEvent.ACTION_DOWN, minus.centerX().toFloat(), y.toFloat(), 0))
            v.dispatchTouchEvent(android.view.MotionEvent.obtain(t0, t0 + 50, android.view.MotionEvent.ACTION_UP, minus.centerX().toFloat(), y.toFloat(), 0))
        }
        assertEquals(listOf("reps-1", "reps-1", "reps-1"), did)
        // 13/11 (Δ2): το ✓ πατιέται και 8u πάνω από το σχήμα του, στη μέση: ύψος 40u ≈ 48 dp. Λίγο πιο πάνω, τίποτα.
        did.clear()
        val mid = size / 2f
        fun tap(x: Float, y: Float) {
            v.dispatchTouchEvent(android.view.MotionEvent.obtain(t0, t0, android.view.MotionEvent.ACTION_DOWN, x, y, 0))
            v.dispatchTouchEvent(android.view.MotionEvent.obtain(t0, t0 + 50, android.view.MotionEvent.ACTION_UP, x, y, 0))
        }
        for (y in listOf(check.top - 7 * u, check.top + 2f, check.bottom - 2f)) tap(mid, y)
        assertEquals(listOf("tick", "tick", "tick"), did)
        assertTrue("${check.height()}", check.height() + 8 * u >= 40 * u - 1)
        tap(mid, check.top - 10 * u)
        assertEquals(3, did.size)
        // Στο ίδιο ύψος, μέσα στην περιοχή του «−»: πάντα «−», ποτέ ✓.
        tap(minus.right - 2f, check.top - 7 * u)
        assertFalse(did.toString(), did.drop(3).contains("tick"))
    }
}
