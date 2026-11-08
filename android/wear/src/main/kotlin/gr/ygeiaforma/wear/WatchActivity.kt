package gr.ygeiaforma.wear

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONObject

/** Η μία οθόνη της εφαρμογής του ρολογιού. Ό,τι μετράει ζει στην [ExerciseService]· εδώ μόνο εικόνα και πατήματα. */
class WatchActivity : Activity(), WatchView.Actions {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var view: WatchView
    private var pending: (() -> Unit)? = null
    private var joinWhenReady = false
    private var finishArmedUntil = 0L
    private var visible = false

    private val redraw: () -> Unit = {
        // Το κινητό άνοιξε την εφαρμογή πριν φτάσει η προπόνησή του: μπαίνει μόλις φτάσει.
        if (joinWhenReady && Repo.phone != null && Repo.running == null) {
            joinWhenReady = false
            joinPhone()
        }
        syncScreen()
        if (::view.isInitialized) view.invalidate()
    }

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!visible) return
            syncScreen()
            view.invalidate()
            view.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        view = WatchView(this, this)
        setContentView(view)
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** Άνοιγμα από το κινητό («Ξεκίνα» εκεί): μπαίνει στην προπόνηση του κινητού με παλμούς. */
    private fun handle(i: Intent?) {
        if (i?.data?.host == "session") joinWhenReady = true
    }

    override fun onStart() {
        super.onStart()
        visible = true
        Link.attach(this)
        Repo.listen(redraw)
        scope.launch {
            Link.load(this@WatchActivity)
            // Αποτέλεσμα που έμεινε από απότομο κλείσιμο: στέλνεται τώρα.
            if (Repo.running == null) {
                Repo.takeSnapshot(this@WatchActivity)?.let { s ->
                    val o = try { JSONObject(s) } catch (_: Exception) { null }
                    val id = o?.optString("id").orEmpty()
                    if (o != null && id.isNotEmpty() && !Link.putResult(this@WatchActivity, id, o)) Repo.snapshot(this@WatchActivity, o)
                }
            }
            if (joinWhenReady && Repo.phone != null) {
                joinWhenReady = false
                joinPhone()
            }
            redraw()
        }
        view.post(tickRunnable)
    }

    override fun onStop() {
        visible = false
        view.removeCallbacks(tickRunnable)
        Repo.unlisten(redraw)
        Link.detach(this)
        super.onStop()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    /** Η οθόνη ακολουθεί την κατάσταση (π.χ. ✓ στο κινητό → διάλειμμα και εδώ). */
    private fun syncScreen() {
        val now = System.currentTimeMillis()
        val s = Repo.session
        when (Repo.screen) {
            Repo.Screen.REST -> if (s == null || s.restEnd <= now) Repo.screen = if (s == null) Repo.Screen.HOME else Repo.Screen.SET
            Repo.Screen.SET -> if (s == null && Repo.running == null) Repo.screen = Repo.Screen.HOME
                else if (s != null && s.phone && s.restEnd > now) Repo.screen = Repo.Screen.REST
            Repo.Screen.HOME -> if (Repo.running == "walk") Repo.screen = Repo.Screen.WALK
                else if (Repo.running != null && s != null) Repo.screen = if (s.restEnd > now) Repo.Screen.REST else Repo.Screen.SET
            else -> {}
        }
        // Οθόνη αναμμένη μόνο στο διάλειμμα (για να φαίνεται η αντίστροφη μέτρηση)· αλλιώς σβήνει κανονικά.
        if (Repo.screen == Repo.Screen.REST) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    // ------------------------------------------------------------------ άδειες
    private fun withPermissions(walk: Boolean, then: () -> Unit) {
        val want = mutableListOf(ExerciseService.heartPermission, Manifest.permission.ACTIVITY_RECOGNITION)
        if (Build.VERSION.SDK_INT >= 33) want.add(Manifest.permission.POST_NOTIFICATIONS)
        if (walk) {
            want.add(Manifest.permission.ACCESS_FINE_LOCATION)
            want.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        val missing = want.filter { !ExerciseService.has(this, it) }
        if (missing.isEmpty()) {
            then()
        } else {
            pending = then
            requestPermissions(missing.toTypedArray(), 7)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val p = pending
        pending = null
        // Ό,τι κι αν απάντησε: η προπόνηση γράφεται· χωρίς άδεια απλώς δεν μετρά παλμούς/GPS (το λέει η οθόνη).
        p?.invoke()
    }

    // ------------------------------------------------------------------ ενέργειες
    private fun cmd(o: JSONObject) {
        val s = Repo.phone ?: return
        o.put("sid", s.id)
        scope.launch { Link.sendJson(this@WatchActivity, Paths.CMD, o) }
    }

    override fun startWorkout(id: String) {
        val w = Repo.plan?.workout(id) ?: return
        if (Repo.plan?.approved != true) return
        withPermissions(false) {
            Repo.notice = null
            Repo.local = LiveSession.fromPlan(w, System.currentTimeMillis())
            Repo.screen = Repo.Screen.SET
            ExerciseService.start(this, "strength", false)
            redraw()
        }
    }

    override fun startWalk() {
        withPermissions(true) {
            Repo.notice = null
            Repo.screen = Repo.Screen.WALK
            ExerciseService.start(this, "walk", false)
            redraw()
        }
    }

    override fun joinPhone() {
        if (Repo.phone == null) return
        withPermissions(false) {
            Repo.notice = null
            val s = Repo.phone
            Repo.screen = if (s != null && s.restEnd > System.currentTimeMillis()) Repo.Screen.REST else Repo.Screen.SET
            ExerciseService.start(this, "strength", true)
            redraw()
        }
    }

    override fun tick() {
        val s = Repo.session ?: return
        val now = System.currentTimeMillis()
        val i = s.idx
        val si = s.current?.nextSet ?: -1
        val next = s.tick(now)
        if (s.phone && si >= 0) cmd(JSONObject().put("op", "tick").put("i", i).put("s", si))
        if (!s.phone) Repo.snapshot(this, s.resultJson(now, Repo.hr ?: HrStats(now)))
        Repo.screen = when (next) {
            LiveSession.Next.REST -> if (s.restEnd > now) Repo.Screen.REST else Repo.Screen.SET
            LiveSession.Next.ASK_RIR -> Repo.Screen.RIR
            LiveSession.Next.SET -> Repo.Screen.SET
            LiveSession.Next.END -> Repo.Screen.SET
        }
    }

    override fun answer(rir: Int) {
        val s = Repo.session ?: return
        val now = System.currentTimeMillis()
        val (next, i) = s.answer(rir, now)
        if (s.phone) cmd(JSONObject().put("op", "rir").put("i", i).put("v", rir))
        else Repo.snapshot(this, s.resultJson(now, Repo.hr ?: HrStats(now)))
        if (next == LiveSession.Next.END && !s.phone) {
            ExerciseService.stop(this)
            return
        }
        Repo.screen = if (s.restEnd > now) Repo.Screen.REST else Repo.Screen.SET
    }

    override fun reps(delta: Int) {
        val s = Repo.session ?: return
        val it = s.current ?: return
        val si = it.nextSet
        if (si < 0) return
        val set = it.sets[si]
        set.reps = (set.reps + delta).coerceIn(0, 99)
        if (s.phone) cmd(JSONObject().put("op", "reps").put("i", s.idx).put("s", si).put("v", set.reps))
    }

    override fun nextExercise() {
        val s = Repo.session ?: return
        s.skip()
        if (s.phone) cmd(JSONObject().put("op", "goto").put("i", s.idx))
        Repo.screen = Repo.Screen.SET
    }

    override fun restPlus() {
        val s = Repo.session ?: return
        val now = System.currentTimeMillis()
        s.restEnd = maxOf(now, s.restEnd) + 30_000
        if (s.phone) cmd(JSONObject().put("op", "rest").put("v", "plus"))
    }

    override fun restStop() {
        val s = Repo.session ?: return
        s.restEnd = 0
        if (s.phone) cmd(JSONObject().put("op", "rest").put("v", "stop"))
        Repo.screen = Repo.Screen.SET
    }

    override fun finish() {
        val now = System.currentTimeMillis()
        // Δύο πατήματα για τέλος (ένα τυχαίο άγγιγμα δεν κλείνει την προπόνηση).
        if (now > finishArmedUntil) {
            finishArmedUntil = now + 3000
            Repo.notice = "Πάτα ξανά «Τέλος»"
            view.postDelayed({ if (Repo.notice == "Πάτα ξανά «Τέλος»") { Repo.notice = null; view.invalidate() } }, 3000)
            return
        }
        finishArmedUntil = 0
        Repo.notice = null
        if (Repo.running != null) {
            ExerciseService.stop(this)
        } else {
            // Χωρίς υπηρεσία (π.χ. δεν δόθηκε καμία άδεια): η προπόνηση γράφεται κανονικά, χωρίς παλμούς.
            val s = Repo.local
            Repo.local = null
            if (s != null && s.setsDone > 0) {
                val now2 = System.currentTimeMillis()
                val o = s.resultJson(now2, HrStats(now2))
                Repo.snapshot(this, o)
                scope.launch { if (Link.putResult(this@WatchActivity, s.id, o)) Repo.snapshot(this@WatchActivity, null) }
                Repo.screen = Repo.Screen.END
            } else {
                Repo.screen = Repo.Screen.HOME
            }
        }
    }

    override fun muteAlarm() {
        Repo.alarmMutedUntil = System.currentTimeMillis() + 60_000
    }

    override fun feel() {
        Repo.symBack = Repo.screen
        Repo.symSent = false
        Repo.screen = Repo.Screen.SYM
        redraw()
    }

    override fun feelBack() {
        Repo.screen = Repo.symBack
        redraw()
    }

    /** «Σταμάτησα»: γράφεται στο κινητό (μένει ώσπου να το πάρει) και σταματά η μέτρηση. */
    override fun feelStop() {
        val now = System.currentTimeMillis()
        val o = JSONObject().put("v", 1).put("kind", "sym").put("at", now)
        Repo.phone?.id?.let { o.put("sid", it) }
        scope.launch { Link.putResult(this@WatchActivity, "sym$now", o) }
        Repo.symSent = true
        // Η δική του προπόνηση/περπάτημα: σταματά και γράφεται ό,τι έγινε. Του κινητού: τη σταματά το κινητό.
        if (Repo.running != null && !Repo.runningPhone) {
            ExerciseService.stop(this)
        } else if (Repo.running == null && Repo.local != null) {
            val s = Repo.local!!
            Repo.local = null
            if (s.setsDone > 0) {
                val r = s.resultJson(now, HrStats(now))
                Repo.snapshot(this, r)
                scope.launch { if (Link.putResult(this@WatchActivity, s.id, r)) Repo.snapshot(this@WatchActivity, null) }
            }
        }
        Repo.screen = Repo.Screen.SYM
        redraw()
    }

    override fun doneOk() {
        Repo.symSent = false
        Repo.screen = Repo.Screen.HOME
    }
}
