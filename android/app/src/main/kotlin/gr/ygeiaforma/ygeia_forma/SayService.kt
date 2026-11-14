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
 * Το ρολόι στέλνει «/ygeia/say» `{"id","el","en","until"}`. Αν το κινητό έχει ακουστικά (ή ηχείο Bluetooth) και δεν
 * πέρασε η προθεσμία, απαντά αμέσως «το λέω» (`/ygeia/said` `{"id","ok":true}`) και το λέει· αλλιώς «όχι», και το λέει
 * το ρολόι. Η μουσική χαμηλώνει για όσο μιλά (audio focus «may duck») και μετά επανέρχεται.
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
        val ok = sayDecision(System.currentTimeMillis(), until, headsetConnected(this))
        try {
            val reply = JSONObject().put("id", id).put("ok", ok).toString().toByteArray(Charsets.UTF_8)
            Tasks.await(Wearable.getMessageClient(this).sendMessage(e.sourceNodeId, SAID, reply), 2, TimeUnit.SECONDS)
        } catch (ex: Exception) {
            Log.w(TAG, "said", ex)
        }
        // Η υπηρεσία μένει ζωντανή ώσπου να ειπωθεί η φράση (το πολύ 8″): αλλιώς το σύστημα μπορεί να την κλείσει στη μέση.
        if (ok) PhoneVoice.speakBlocking(applicationContext, o.optString("el", ""), o.optString("en", ""), 8_000L)
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

/** Η μηχανή φωνής του κινητού, μία για τη διεργασία· κλείνει 60″ μετά την τελευταία φράση. */
object PhoneVoice {
    private const val TAG = "ygeia-voice"
    private var tts: TextToSpeech? = null
    private var greek = false
    private var lastUse = 0L
    private val lock = Any()

    private val attrs: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    /** Λέει τη φράση και περιμένει να τελειώσει (το πολύ [maxMs]). Από νήμα παρασκηνίου, όχι από το κύριο. */
    fun speakBlocking(ctx: Context, el: String, en: String, maxMs: Long) {
        val t = ready(ctx, 3_000L) ?: return
        val text = if (greek) el else en
        if (text.isEmpty()) return
        val am = ctx.getSystemService(AudioManager::class.java)
        val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attrs).build()
        val done = CountDownLatch(1)
        try {
            t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) = done.countDown()

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = done.countDown()
            })
            am?.requestAudioFocus(focus)
            t.speak(text, TextToSpeech.QUEUE_ADD, Bundle(), "p${System.nanoTime()}")
            done.await(maxMs, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            Log.w(TAG, "speak", e)
        } finally {
            try {
                am?.abandonAudioFocusRequest(focus)
            } catch (_: Exception) {
            }
            lastUse = System.currentTimeMillis()
            scheduleClose()
        }
    }

    private fun ready(ctx: Context, waitMs: Long): TextToSpeech? {
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
                    val name = femaleVoiceName(voices.filter { it.locale.language == lang && !it.isNetworkConnectionRequired }.map { it.name })
                    voices.firstOrNull { it.name == name }?.let { t.voice = it }
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
