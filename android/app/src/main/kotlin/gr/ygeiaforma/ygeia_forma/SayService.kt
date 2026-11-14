package gr.ygeiaforma.ygeia_forma

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Φωνή του ρολογιού από το κινητό (14/11). Ο χρήστης ακούει συνήθως Spotify από το κινητό με ακουστικά: τότε το «Πρώτο
 * χιλιόμετρο» / «Εκτός εύρους» πρέπει να ακουστεί εκεί, μέσα στη μουσική, όχι από το ηχείο του ρολογιού.
 *
 * Το ρολόι στέλνει «/ygeia/say» `{"id","el","en","until"}`. Το κινητό απαντά «το λέω» (`/ygeia/said` `{"id","ok":true}`)
 * ΜΟΝΟ αφού είναι έτοιμο να μιλήσει (round 14, P1–P3), με αυτή τη σειρά:
 * 1. ακουστικά (ή ηχείο Bluetooth) και πριν από την προθεσμία του ρολογιού·
 * 2. το σύστημα του επιτρέπει να χαμηλώσει τη μουσική (audio focus). Από το Android 17 μια εφαρμογή χωρίς ανοιχτή οθόνη
 *    συνήθως ΔΕΝ το παίρνει και δεν ακούγεται: τότε απαντά «όχι» και το λέει το ρολόι·
 * 3. η μηχανή φωνής έτοιμη μέσα στην προθεσμία·
 * 4. η απάντηση έφυγε.
 * Αλλιώς «όχι», και το λέει το ρολόι: ποτέ καμία φωνή και ποτέ δύο φορές. Η μουσική χαμηλώνει για όσο μιλά και μετά
 * επανέρχεται.
 *
 * Υπηρεσία που ξυπνά ΜΟΝΟ όταν έρθει τέτοιο μήνυμα (μόνο όσο τρέχει άσκηση στο ρολόι)· τίποτα στο παρασκήνιο αλλιώς.
 */
class SayService : WearableListenerService() {
    override fun onMessageReceived(e: MessageEvent) {
        if (e.path != SAY) return
        val o = try {
            JSONObject(String(e.data, Charsets.UTF_8))
        } catch (_: Exception) {
            return
        }
        val id = o.optString("id", "")
        if (id.isEmpty()) return
        val until = o.optLong("until", 0L)
        val el = o.optString("el", "")
        val en = o.optString("en", "")
        var held: PhoneVoice.Held? = null
        if (sayDecision(System.currentTimeMillis(), until, headsetConnected(this)) && (el.isNotEmpty() || en.isNotEmpty())) {
            held = PhoneVoice.prepare(applicationContext, until)
        }
        val ok = held != null && System.currentTimeMillis() < until
        val sent = try {
            val reply = JSONObject().put("id", id).put("ok", ok).toString().toByteArray(Charsets.UTF_8)
            Tasks.await(Wearable.getMessageClient(this).sendMessage(e.sourceNodeId, SAID, reply), 2, TimeUnit.SECONDS)
            true
        } catch (ex: Exception) {
            Log.w(TAG, "said", ex)
            false
        }
        // Η υπηρεσία μένει ζωντανή ώσπου να ειπωθεί η φράση (το πολύ 8″): αλλιώς το σύστημα μπορεί να την κλείσει στη μέση.
        // Αν η απάντηση δεν έφυγε, το ρολόι θα τη πει μόνο του: εδώ σιωπή.
        if (ok && sent) held!!.speak(el, en, 8_000L) else held?.release()
    }

    companion object {
        const val SAY = "/ygeia/say"
        const val SAID = "/ygeia/said"
        private const val TAG = "ygeia-say"

        private val HEADSETS = setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )

        fun headsetConnected(ctx: Context): Boolean = try {
            ctx.getSystemService(AudioManager::class.java)?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.any { it.type in HEADSETS } == true
        } catch (_: Exception) {
            false
        }
    }
}

/**
 * Το κινητό λέει τη φράση μόνο αν έχει ακουστικά και δεν πέρασε η προθεσμία του ρολογιού (τότε θα την έχει πει ήδη το
 * ρολόι: ποτέ δύο φορές). Καθαρή συνάρτηση, με δοκιμές.
 */
fun sayDecision(now: Long, until: Long, headset: Boolean): Boolean = headset && until > 0 && now < until

/** Το «χαμήλωσε τη μουσική» του συστήματος: δόθηκε; Το DELAYED (θα δοθεί αργότερα) μετρά ως όχι. Καθαρή, με δοκιμές. */
fun focusGranted(result: Int?): Boolean = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED

/** Η μηχανή φωνής του κινητού, μία για τη διεργασία· κλείνει 60″ μετά την τελευταία φράση. */
object PhoneVoice {
    private const val TAG = "ygeia-voice"
    private var tts: TextToSpeech? = null
    private var greek = false

    @Volatile
    private var lastUse = 0L
    private val lock = Any()

    private val attrs: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    /** Έτοιμο να μιλήσει: η μηχανή φωνής και η μουσική χαμηλωμένη. Ή [speak] ή [release], μία φορά. */
    class Held internal constructor(
        private val t: TextToSpeech,
        private val am: AudioManager?,
        private val focus: AudioFocusRequest,
        private val greek: Boolean,
    ) {
        /** Λέει τη φράση και περιμένει να τελειώσει (το πολύ [maxMs]). Από νήμα παρασκηνίου, όχι από το κύριο. */
        fun speak(el: String, en: String, maxMs: Long) {
            val text = (if (greek) el else en).ifEmpty { if (greek) en else el }
            val done = CountDownLatch(1)
            try {
                t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) = done.countDown()

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) = done.countDown()

                    override fun onError(utteranceId: String?, errorCode: Int) = done.countDown()
                })
                if (t.speak(text, TextToSpeech.QUEUE_ADD, Bundle(), "p${System.nanoTime()}") == TextToSpeech.ERROR) {
                    // Η μηχανή «πέθανε»: την επόμενη φορά από την αρχή.
                    dropEngine(t)
                } else {
                    done.await(maxMs, TimeUnit.MILLISECONDS)
                }
            } catch (e: Exception) {
                Log.w(TAG, "speak", e)
            } finally {
                release()
            }
        }

        /** Η μουσική ξανά στην ένταση της, και η μηχανή κλείνει σε 60″ αν δεν χρειαστεί ξανά. */
        fun release() {
            try {
                am?.abandonAudioFocusRequest(focus)
            } catch (_: Exception) {
            }
            lastUse = System.currentTimeMillis()
            scheduleClose()
        }
    }

    /**
     * Ετοιμάζεται να μιλήσει ως τις [until] (ms): πρώτα το «χαμήλωσε τη μουσική» (γρήγορο, και από το Android 17 συνήθως
     * «όχι» με την εφαρμογή κλειστή), μετά η μηχανή φωνής. null: δεν μπορεί, ας το πει το ρολόι.
     */
    fun prepare(ctx: Context, until: Long): Held? {
        // Round 14 (P4): να μην κλείσει η μηχανή όσο ετοιμάζεται για νέα φράση.
        main.removeCallbacks(close)
        lastUse = System.currentTimeMillis()
        val am = ctx.getSystemService(AudioManager::class.java)
        val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attrs).build()
        val granted = try {
            focusGranted(am?.requestAudioFocus(focus))
        } catch (_: Exception) {
            false
        }
        if (!granted) {
            scheduleClose()
            return null
        }
        val t = ready(ctx, until - System.currentTimeMillis())
        if (t == null || System.currentTimeMillis() >= until) {
            try {
                am?.abandonAudioFocusRequest(focus)
            } catch (_: Exception) {
            }
            scheduleClose()
            return null
        }
        return Held(t, am, focus, greek)
    }

    private fun ready(ctx: Context, waitMs: Long): TextToSpeech? {
        if (waitMs <= 0) return synchronized(lock) { tts }
        synchronized(lock) {
            tts?.let { return it }
            val init = CountDownLatch(1)
            var ok = false
            val t = try {
                TextToSpeech(ctx.applicationContext) { st ->
                    ok = st == TextToSpeech.SUCCESS
                    init.countDown()
                }
            } catch (e: Exception) {
                Log.w(TAG, "tts", e)
                return null
            }
            if (!init.await(waitMs, TimeUnit.MILLISECONDS) || !ok) {
                try {
                    t.shutdown()
                } catch (_: Exception) {
                }
                return null
            }
            greek = setLocale(t, Locale("el", "GR"))
            if (!greek && !setLocale(t, Locale.UK) && !setLocale(t, Locale.US)) {
                t.shutdown()
                return null
            }
            try {
                val lang = if (greek) "el" else "en"
                val voices = t.voices
                if (voices != null) {
                    // Μόνο φωνές που είναι ήδη στο κινητό (round 14: όχι «δεν έχει κατέβει»).
                    val usable = voices.filter {
                        it.locale.language == lang && !it.isNetworkConnectionRequired &&
                            !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
                    }
                    val name = femaleVoiceName(usable.map { it.name })
                    usable.firstOrNull { it.name == name }?.let { t.voice = it }
                }
                // Λίγο πιο αργή και πιο χαμηλή: πιο ζεστή φωνή (αίτημα χρήστη). Ίδια με το ρολόι.
                t.setSpeechRate(0.92f)
                t.setPitch(0.95f)
                t.setAudioAttributes(attrs)
            } catch (_: Exception) {
            }
            tts = t
            return t
        }
    }

    private fun dropEngine(t: TextToSpeech) {
        synchronized(lock) {
            if (tts === t) tts = null
            try {
                t.shutdown()
            } catch (_: Exception) {
            }
        }
    }

    private fun setLocale(t: TextToSpeech, l: Locale): Boolean = try {
        t.isLanguageAvailable(l) >= TextToSpeech.LANG_AVAILABLE && t.setLanguage(l) >= TextToSpeech.LANG_AVAILABLE
    } catch (_: Exception) {
        false
    }

    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private val close = Runnable {
        synchronized(lock) {
            if (System.currentTimeMillis() - lastUse < 59_000L) return@Runnable
            try {
                tts?.shutdown()
            } catch (_: Exception) {
            }
            tts = null
        }
    }

    private fun scheduleClose() {
        main.removeCallbacks(close)
        main.postDelayed(close, 60_000L)
    }
}

/**
 * Γυναικεία φωνή, αν η μηχανή τη δηλώνει στο όνομα («female», ή «…SMTf00» της Samsung), αλλιώς null (μένει η φωνή του
 * συστήματος). Ίδια με του ρολογιού (Voice.kt).
 */
fun femaleVoiceName(names: List<String>): String? {
    val sorted = names.sorted()
    return sorted.firstOrNull { it.contains("female", ignoreCase = true) }
        ?: sorted.firstOrNull { Regex("SMTf\\d", RegexOption.IGNORE_CASE).containsMatchIn(it) && !it.contains("SMTm", ignoreCase = true) }
}
