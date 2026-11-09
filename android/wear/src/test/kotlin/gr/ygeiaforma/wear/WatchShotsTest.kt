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
    }

    private fun shot(name: String, ambient: Boolean = false) {
        val v = WatchView(RuntimeEnvironment.getApplication(), noop)
        v.ambient = ambient
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

        val s = LiveSession.fromPlan(Repo.plan!!.todayWorkout!!, now - 18 * 60_000)
        Repo.local = s
        running(now)
        s.tick(now - 200_000)
        s.tick(now - 100_000)
        s.answer(2, now - 90_000)
        s.restEnd = 0
        Repo.screen = Repo.Screen.SET
        shot("W2_set")

        s.restEnd = now + 64_000
        Repo.screen = Repo.Screen.REST
        Repo.bpm = 112
        shot("W3_rest")

        Repo.screen = Repo.Screen.RIR
        shot("W4_rir")

        Repo.bpm = 143
        Repo.alarm.feed(143, now)
        Repo.alarm.feed(143, now + 6_000)
        shot("W5_alarm")

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

        // 9/11 (V-A-04): περπάτημα με όριο, χωρίς κανέναν παλμό: «το όριο δεν σε προσέχει».
        Repo.alarm.limit = 140
        Repo.bpm = 0
        Repo.bpmAt = 0
        Repo.hrSilent = HrSilence.Silence.NEVER
        shot("W7d_walk_no_hr_limit")
        Repo.hrSilent = null
        Repo.bpm = 104
        Repo.bpmAt = now
        Repo.alarm.limit = null

        // 9/11: παύση και λεπτό αποκατάστασης.
        Repo.paused = true
        shot("W7b_walk_paused")
        Repo.paused = false
        Repo.endAt = now
        Repo.recoveryUntil = now + 47_000
        Repo.screen = Repo.Screen.RECOVER
        shot("W7c_recovery")

        // 9/11 (W3-18): περπάτημα χωρίς όριο: γράφεται «χωρίς όριο».
        Repo.recoveryUntil = 0
        Repo.endAt = 0
        Repo.screen = Repo.Screen.WALK
        Repo.alarm.limit = null
        shot("W7e_walk_no_limit")
        // 9/11 (W3-08): ambient, αχνή οθόνη: λεπτά, χωρίς κουμπιά και χρώματα.
        Repo.alarm.limit = 140
        shot("W10_walk_ambient", ambient = true)
        Repo.alarm.limit = null

        Repo.resetExercise()
        Repo.screen = Repo.Screen.END
        shot("W8_end")
        // 9/11 (V-A-03): η εφαρμογή είχε κλείσει απότομα· το περπάτημα σώθηκε ως μερικό.
        Repo.notice = "Το περπάτημα σώθηκε ως τις 18:42: η εφαρμογή έκλεισε πριν το «Τέλος»."
        shot("W8b_end_recovered")
        Repo.notice = null

        Repo.screen = Repo.Screen.HOME
        Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s1","w":"A","name":"Προπόνηση Α","start":1,"idx":1,
            "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"sets":[{"label":"10,3 kg","reps":8,"done":true}]}]}"""))
        shot("W9_home_phone")

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
}
