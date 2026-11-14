package gr.ygeiaforma.wear

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * Φωνή στην άσκηση (απόφαση χρήστη 14/11): «Πρώτο χιλιόμετρο», «Εκτός εύρους», «Επόμενο σετ» κ.λπ. ([Say]).
 *
 * Πού ακούγεται (ο χρήστης ακούει Spotify συνήθως από το κινητό, μερικές φορές από το ρολόι):
 * 1. Ακουστικά συνδεδεμένα στο ρολόι → από το ρολόι (στα ακουστικά).
 * 2. Αλλιώς ρωτά το κινητό ([Link.askPhoneToSay]): αν εκείνο έχει ακουστικά, το λέει εκεί (μέσα στη μουσική).
 * 3. Αλλιώς (κανένα ακουστικό, ή το κινητό δεν απάντησε) → από το ηχείο του ρολογιού.
 * Η μουσική χαμηλώνει για όσο μιλά (audio focus «may duck») και μετά επανέρχεται· δεν σταματά.
 *
 * Μόνο όσο τρέχει άσκηση ([start] από την υπηρεσία, [stopLater] στο τέλος, ώστε να προλάβει να πει την τελευταία φράση)·
 * τίποτα στο παρασκήνιο αλλιώς. Μία για όλη τη διεργασία ([shared]): η υπηρεσία κλείνει πριν τελειώσει η τελευταία φράση.
 */
class Voice private constructor(private val ctx: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val main = Handler(Looper.getMainLooper())
    private val stopRunnable = Runnable { stop() }
    private var tts: TextToSpeech? = null
    private var ready = false
    private var greek = false
    private var pending: Pair<String, String>? = null
    private var focus: AudioFocusRequest? = null
    private val am: AudioManager? = ctx.getSystemService(AudioManager::class.java)

    /** Για τον έλεγχο στη συσκευή: «el», «en», «none» (δεν υπάρχει φωνή στο ρολόι), «init», «off». */
    var status = "off"
        private set

    /** Πόσες φράσεις είπε το ρολόι και πόσες το κινητό (για τον έλεγχο στη συσκευή). */
    var localCount = 0
        private set
    var phoneCount = 0
        private set

    private val attrs: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    /** Ετοιμάζει τη φωνή του ρολογιού από την αρχή της άσκησης (για να μην αργήσει η πρώτη φράση). */
    fun start() {
        main.removeCallbacks(stopRunnable)
        if (tts != null) return
        status = "init"
        tts = try {
            TextToSpeech(ctx.applicationContext) { st -> onInit(st) }
        } catch (e: Exception) {
            Log.w(TAG, "tts", e)
            status = "none"
            null
        }
    }

    private fun onInit(st: Int) {
        val t = tts ?: return
        if (st != TextToSpeech.SUCCESS) {
            status = "none"
            return
        }
        try {
            greek = setLocale(t, Locale("el", "GR"))
            if (!greek && !setLocale(t, Locale.UK) && !setLocale(t, Locale.US)) {
                status = "none"
                return
            }
            pickVoice(t, if (greek) "el" else "en")
            // Λίγο πιο αργή και πιο χαμηλή: πιο ζεστή φωνή (αίτημα χρήστη). Η χροιά είναι της φωνής του συστήματος.
            t.setSpeechRate(VOICE_RATE)
            t.setPitch(VOICE_PITCH)
            t.setAudioAttributes(attrs)
            t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) = releaseFocus()

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = releaseFocus()
            })
            ready = true
            status = if (greek) "el" else "en"
            pending?.let { speakHere(it) }
            pending = null
        } catch (e: Exception) {
            Log.w(TAG, "tts init", e)
            status = "none"
        }
    }

    /** Λέει τη φράση [p] (ελληνικά, αγγλικά) εκεί που θα την ακούσεις. */
    fun say(p: Pair<String, String>) {
        if (headsetHere()) {
            speakHere(p)
            return
        }
        scope.launch {
            val phone = try {
                Link.askPhoneToSay(ctx, p.first, p.second)
            } catch (_: Exception) {
                false
            }
            if (phone) phoneCount++ else speakHere(p)
        }
    }

    private fun speakHere(p: Pair<String, String>) {
        val t = tts
        if (t == null) {
            // Η φωνή δεν ξεκίνησε ακόμα (π.χ. «Επόμενο σετ» πριν από κάθε άλλη φράση): ξεκινά τώρα και τη λέει μόλις ετοιμαστεί.
            start()
            pending = p
            return
        }
        if (!ready) {
            pending = p
            return
        }
        try {
            requestFocus()
            t.speak(if (greek) p.first else p.second, TextToSpeech.QUEUE_ADD, Bundle(), "y${SystemClock.elapsedRealtime()}")
            localCount++
        } catch (e: Exception) {
            Log.w(TAG, "speak", e)
            releaseFocus()
        }
    }

    /** Κλείνει τη φωνή σε [ms] (να προλάβει να πει την τελευταία φράση), εκτός αν ξεκινήσει νέα άσκηση στο μεταξύ. */
    fun stopLater(ms: Long = 8_000L) {
        main.removeCallbacks(stopRunnable)
        main.postDelayed(stopRunnable, ms)
    }

    fun stop() {
        main.removeCallbacks(stopRunnable)
        releaseFocus()
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        ready = false
        pending = null
        if (status != "none") status = "off"
    }

    /** Ακουστικά ή ηχείο Bluetooth συνδεδεμένα στο ρολόι. */
    private fun headsetHere(): Boolean = try {
        am?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.any { it.type in HEADSET_TYPES } == true
    } catch (_: Exception) {
        false
    }

    private fun requestFocus() {
        val a = am ?: return
        val r = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attrs).build()
        focus = r
        try {
            a.requestAudioFocus(r)
        } catch (_: Exception) {
        }
    }

    private fun releaseFocus() {
        val r = focus ?: return
        focus = null
        try {
            am?.abandonAudioFocusRequest(r)
        } catch (_: Exception) {
        }
    }

    companion object {
        @Volatile
        private var instance: Voice? = null

        fun shared(ctx: Context): Voice = instance ?: synchronized(this) {
            instance ?: Voice(ctx.applicationContext).also { instance = it }
        }

        private const val TAG = "ygeia-voice"
        const val VOICE_RATE = 0.92f
        const val VOICE_PITCH = 0.95f

        val HEADSET_TYPES = setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )

        private fun setLocale(t: TextToSpeech, l: Locale): Boolean = try {
            t.isLanguageAvailable(l) >= TextToSpeech.LANG_AVAILABLE && t.setLanguage(l) >= TextToSpeech.LANG_AVAILABLE
        } catch (_: Exception) {
            false
        }

        /** Γυναικεία φωνή, αν η μηχανή του συστήματος έχει και τη δηλώνει στο όνομα ([femaleVoiceName]). */
        private fun pickVoice(t: TextToSpeech, lang: String) {
            try {
                val voices = t.voices ?: return
                val name = femaleVoiceName(voices.filter { it.locale.language == lang && !it.isNetworkConnectionRequired }.map { it.name })
                    ?: return
                voices.firstOrNull { it.name == name }?.let { t.voice = it }
            } catch (_: Exception) {
            }
        }
    }
}

/**
 * Το όνομα μιας γυναικείας φωνής από τα ονόματα που δίνει η μηχανή, ή null (μένει η φωνή του συστήματος). Η μηχανή δεν
 * λέει το φύλο· κάποιες το γράφουν στο όνομα: «female», ή «…SMTf00» της Samsung (f = γυναικεία, m = ανδρική). Καθαρή
 * συνάρτηση, με δοκιμές. Ίδια με του κινητού (PhoneVoice.kt).
 */
fun femaleVoiceName(names: List<String>): String? {
    val sorted = names.sorted()
    return sorted.firstOrNull { it.contains("female", ignoreCase = true) }
        ?: sorted.firstOrNull { Regex("SMTf\\d", RegexOption.IGNORE_CASE).containsMatchIn(it) && !it.contains("SMTm", ignoreCase = true) }
}
