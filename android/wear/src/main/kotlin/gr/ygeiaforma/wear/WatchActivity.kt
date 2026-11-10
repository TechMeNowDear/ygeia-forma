package gr.ygeiaforma.wear

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import android.view.WindowManager
import androidx.concurrent.futures.await
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.ExerciseTrackedStatus
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
    private var skipArmedUntil = 0L
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

    /**
     * Ανανέωση της οθόνης: κάθε 1″ κανονικά· στο ambient (Wear OS 6: η οθόνη μένει «ανοιχτή» και αχνή) μία φορά το λεπτό,
     * στην αρχή κάθε λεπτού, χωρίς δευτερόλεπτα (έλεγχος 9/11, W3-08).
     */
    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!visible) return
            syncScreen()
            view.invalidate()
            val now = System.currentTimeMillis()
            view.postDelayed(this, if (view.ambient) 60_000L - now % 60_000L else 1000L)
        }
    }

    /**
     * Ambient χωρίς βιβλιοθήκη: η κατάσταση της οθόνης (DOZE = αχνή «πάντα ανοιχτή», OFF = σβηστή). Μόνο όσο η οθόνη
     * της εφαρμογής είναι ορατή.
     */
    private val displays = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}
        override fun onDisplayChanged(displayId: Int) {
            if (displayId == Display.DEFAULT_DISPLAY) checkAmbient()
        }
    }

    private fun checkAmbient() {
        val st = try {
            getSystemService(DisplayManager::class.java)?.getDisplay(Display.DEFAULT_DISPLAY)?.state
        } catch (_: Exception) {
            null
        } ?: return
        val amb = isAmbientState(st)
        if (amb == view.ambient) return
        view.ambient = amb
        view.removeCallbacks(tickRunnable)
        if (visible) view.post(tickRunnable)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Repo.dropOldKeys(this)
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
        try {
            getSystemService(DisplayManager::class.java)?.registerDisplayListener(displays, null)
        } catch (_: Exception) {
        }
        checkAmbient()
        scope.launch {
            Link.load(this@WatchActivity)
            // Άσκηση που έμεινε μισή από απότομο κλείσιμο (V-A-03) και αποτελέσματα που δεν έφτασαν ακόμα: τώρα. Μόνο αν
            // δεν τρέχει τίποτα εδώ (αλλιώς θα στελνόταν μισή μια προπόνηση που συνεχίζεται, V-A-14).
            if (Repo.running == null && Repo.local == null) {
                recoverIfNeeded()
                // «Σβήσε» από το κινητό που περιμένει (S1/N1): τα παλιά αποτελέσματα δεν ξαναστέλνονται (σβήνονται μόλις
                // επιτρέπεται)· όσα έγιναν μετά από αυτό στέλνονται κανονικά.
                sendPending()
                Link.tryWipe(this@WatchActivity)
            }
            if (joinWhenReady && Repo.phone != null) {
                joinWhenReady = false
                joinPhone()
            }
            redraw()
        }
        view.post(tickRunnable)
    }

    /** Στιγμιότυπο άσκησης χωρίς άσκηση στη μνήμη: η εφαρμογή έκλεισε απότομα. Συνέχεια ή μερικό αποτέλεσμα ([Recovery]). */
    private suspend fun recoverIfNeeded() {
        val o = Repo.readRun(this) ?: return
        // Το κανονικό αποτέλεσμα αυτής της άσκησης περιμένει ήδη: έχει τελειώσει, όχι «συνέχεια» ούτε μερικό από πάνω (S3).
        val id = Repo.runId(o)
        if (id != null && Repo.hasFinalPending(this, id)) {
            Repo.clearRun(this)
            return
        }
        val owned = try {
            HealthServices.getClient(this).exerciseClient.getCurrentExerciseInfoAsync().await().exerciseTrackedStatus ==
                ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS
        } catch (_: Exception) {
            false
        }
        if (Repo.running != null || Repo.local != null) return
        val action = Recovery.decide(owned, o.optString("kind"), o.optBoolean("phone", false), o.has("local"), o.optLong("saved", 0), System.currentTimeMillis())
        try {
            ExerciseService.recover(this, action)
        } catch (_: Exception) {
        }
    }

    /** Αποτελέσματα που δεν μπήκαν ακόμα στο Data Layer (ένα ανά id): τώρα. */
    private suspend fun sendPending() {
        for ((id, o) in Repo.pendingAll(this)) {
            if (!Link.sendable(this, o)) continue
            if (Link.putResult(this, id, o)) Repo.removePending(this, id)
        }
    }

    override fun onStop() {
        visible = false
        try {
            getSystemService(DisplayManager::class.java)?.unregisterDisplayListener(displays)
        } catch (_: Exception) {
        }
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
            Repo.Screen.HOME, Repo.Screen.WALK -> if (Repo.running == "walk") Repo.screen = if (Repo.recoveryUntil > 0) Repo.Screen.RECOVER else Repo.Screen.WALK
                else if (Repo.running != null && s != null) Repo.screen = if (s.restEnd > now) Repo.Screen.REST else Repo.Screen.SET
            else -> {}
        }
        // Οθόνη αναμμένη μόνο στο διάλειμμα (για να φαίνεται η αντίστροφη μέτρηση)· αλλιώς σβήνει κανονικά.
        // Και στο λεπτό αποκατάστασης (αντίστροφη μέτρηση, 9/11).
        if (Repo.screen == Repo.Screen.REST || Repo.screen == Repo.Screen.RECOVER) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
        o.put("sid", s.id).put(Proto.CMD_VERSION, Proto.MAJOR)
        scope.launch { Link.sendJson(this@WatchActivity, Paths.CMD, o) }
    }

    /**
     * Στιγμιότυπο της προπόνησης του ρολογιού σε κάθε ✓ (V-A-03): με την άσκηση της υπηρεσίας, ή μόνο τα σετ αν η
     * υπηρεσία δεν ξεκίνησε (π.χ. χωρίς άδεια). Ποτέ ως «αποτέλεσμα»: στέλνεται μόνο αν η εφαρμογή κλείσει απότομα.
     */
    private fun saveRun() {
        val now = System.currentTimeMillis()
        val o = Repo.captureRun(now) ?: Repo.local?.let { l ->
            JSONObject().put("v", 1).put("kind", "strength").put("phone", false).put("start", l.start).put("saved", now)
                .put("local", l.toState()).also { o -> Repo.alarm.limit?.let { o.put("lim", it) } }
        } ?: return
        val gen = Repo.runGen
        scope.launch(Dispatchers.IO) { Repo.writeRun(this@WatchActivity, o.toString(), gen) }
    }

    override fun startWorkout(id: String) {
        val w = Repo.plan?.workout(id) ?: return
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
        // Με την ώρα του ✓ εδώ: το κινητό τη γράφει όπως είναι (παλμοί ανά σετ), όχι την ώρα που έφτασε (9/11).
        if (s.phone && si >= 0) cmd(JSONObject().put("op", "tick").put("i", i).put("s", si).put("at", now))
        if (!s.phone) saveRun()
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
        else saveRun()
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
        // Δύο πατήματα (έλεγχος 8/11, UX-05): ένα τυχαίο άγγιγμα στο όνομα δεν αλλάζει άσκηση.
        val now = System.currentTimeMillis()
        if (now > skipArmedUntil) {
            skipArmedUntil = now + 3000
            Repo.notice = SKIP_NOTICE
            view.postDelayed({ if (Repo.notice == SKIP_NOTICE) { Repo.notice = null; view.invalidate() } }, 3000)
            return
        }
        skipArmedUntil = 0
        Repo.notice = null
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

    /**
     * «Τέλος» της άσκησης. ΔΕΝ είναι το Activity.finish() (έλεγχος 9/11, V-A-17): το «Πίσω» και το σύρσιμο κλείνουν μόνο
     * την οθόνη· η άσκηση συνεχίζει στην υπηρεσία.
     */
    override fun finishWorkout() {
        val now = System.currentTimeMillis()
        // Στο λεπτό αποκατάστασης «Παράλειψη»: ένα πάτημα (η άσκηση έχει ήδη τελειώσει).
        if (Repo.recoveryUntil > 0) {
            ExerciseService.stop(this)
            return
        }
        // Δύο πατήματα για τέλος (ένα τυχαίο άγγιγμα δεν κλείνει την προπόνηση).
        if (now > finishArmedUntil) {
            finishArmedUntil = now + 3000
            // Σε προπόνηση του κινητού το «Τέλος» κλείνει και εκεί (V-A-09): να το ξέρει πριν το δεύτερο πάτημα.
            // Χωρίς κανένα σετ: το κινητό κρατά την προπόνηση μόνο αν έχει παλμούς, αλλιώς τη σβήνει. Το κείμενο λέει ακριβώς
            // αυτό, με ό,τι ξέρει το ρολόι (S7).
            val msg = finishNotice(Repo.runningPhone, Repo.phone?.setsDone ?: 0, (Repo.hr?.samples?.size ?: 0) > 0)
            Repo.notice = msg
            view.postDelayed({ if (Repo.notice == msg) { Repo.notice = null; view.invalidate() } }, 3000)
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
                val o = s.resultJson(now2, HrStats(now2)).put("lim", Repo.alarm.limit ?: 0)
                Repo.savePending(this, s.id, o)
                Repo.clearRun(this)
                scope.launch { if (Link.putResult(this@WatchActivity, s.id, o)) Repo.removePending(this@WatchActivity, s.id) }
                Repo.screen = Repo.Screen.END
            } else {
                Repo.clearRun(this)
                Repo.screen = Repo.Screen.HOME
            }
        }
    }

    override fun pauseWalk(on: Boolean) {
        ExerciseService.pause(this, on)
    }

    override fun muteAlarm() {
        Repo.alarmMutedUntil = System.currentTimeMillis() + 60_000
    }

    override fun doneOk() {
        Repo.screen = Repo.Screen.HOME
    }
}

private const val SKIP_NOTICE = "Πάτα ξανά: επόμενη άσκηση"
private const val FINISH_NOTICE = "Πάτα ξανά «Τέλος»"
private const val FINISH_PHONE_NOTICE = "Πάτα ξανά: τέλος και στο κινητό"

/** Το μήνυμα πριν από το δεύτερο «Τέλος» (αληθινό σε κάθε περίπτωση, έλεγχος του #91, S7). */
fun finishNotice(phone: Boolean, setsDone: Int, hasHr: Boolean): String = when {
    !phone -> FINISH_NOTICE
    setsDone > 0 -> FINISH_PHONE_NOTICE
    hasHr -> "Κανένα σετ: στο κινητό μένουν μόνο οι παλμοί"
    else -> "Κανένα σετ ούτε παλμοί: δεν αποθηκεύεται"
}

/** Η οθόνη είναι στο ambient (αχνή, «πάντα ανοιχτή») ή σβηστή: καμία ανανέωση ανά δευτερόλεπτο (W3-08). */
fun isAmbientState(state: Int): Boolean =
    state == Display.STATE_DOZE || state == Display.STATE_DOZE_SUSPEND || state == Display.STATE_OFF
