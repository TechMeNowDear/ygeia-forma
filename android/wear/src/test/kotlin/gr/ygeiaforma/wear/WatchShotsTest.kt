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
        override fun finish() {}
        override fun pauseWalk(on: Boolean) {}
        override fun muteAlarm() {}
        override fun doneOk() {}
    }

    @After
    fun reset() {
        Repo.plan = null
        Repo.phone = null
        Repo.local = null
        Repo.notice = null
        Repo.screen = Repo.Screen.HOME
        Repo.resetExercise()
        Repo.alarm.limit = null
    }

    private fun shot(name: String) {
        val v = WatchView(RuntimeEnvironment.getApplication(), noop)
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

        // Δεν φτάνουν παλμοί: φαίνεται καθαρά.
        Repo.bpmAt = now - 60_000
        shot("W6b_no_hr")
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

        // 9/11: παύση και λεπτό αποκατάστασης.
        Repo.paused = true
        shot("W7b_walk_paused")
        Repo.paused = false
        Repo.endAt = now
        Repo.recoveryUntil = now + 47_000
        Repo.screen = Repo.Screen.RECOVER
        shot("W7c_recovery")

        Repo.resetExercise()
        Repo.screen = Repo.Screen.END
        shot("W8_end")

        Repo.screen = Repo.Screen.HOME
        Repo.applyPhone(LiveSession.parsePhone("""{"active":true,"id":"s1","w":"A","name":"Προπόνηση Α","start":1,"idx":1,
            "items":[{"ex":"db_press","name":"Πιεστικό","rest":90,"sets":[{"label":"10,3 kg","reps":8,"done":true}]}]}"""))
        shot("W9_home_phone")

        Repo.applyPhone(null)
        Repo.plan = Plan.parse(planJson)
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
