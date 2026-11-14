package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Απλό JVM: η φωνή του ρολογιού από το κινητό (14/11, SayService.kt). Δοκιμαστικοί αριθμοί. */
class SayServiceTest {
    @Test
    fun phoneSpeaksOnlyWithHeadphonesAndBeforeTheWatchDeadline() {
        val now = 1_700_000_000_000L
        assertTrue(sayDecision(now, now + 2_000, headset = true))
        // Χωρίς ακουστικά στο κινητό: το λέει το ρολόι.
        assertFalse(sayDecision(now, now + 2_000, headset = false))
        // Πέρασε η προθεσμία: το έχει πει ήδη το ρολόι, όχι δεύτερη φορά.
        assertFalse(sayDecision(now, now - 1, headset = true))
        assertFalse(sayDecision(now, 0, headset = true))
        assertEquals("/ygeia/say", SayService.SAY)
        assertEquals("/ygeia/said", SayService.SAID)
    }

    /**
     * Round 14 (Android 17): «το λέω» μόνο αν το σύστημα επέτρεψε να χαμηλώσει η μουσική (με την εφαρμογή κλειστή συνήθως
     * όχι) και η μηχανή φωνής είναι έτοιμη· αλλιώς «όχι» και το λέει το ρολόι. Ποτέ σιωπή, ποτέ δύο φορές.
     */
    @Test
    fun saysYesOnlyWhenReadyToSpeak() {
        assertTrue(focusGranted(1))
        assertFalse(focusGranted(0)) // FAILED
        assertFalse(focusGranted(2)) // DELAYED
        assertFalse(focusGranted(null))
        val src = File("src/main/kotlin/gr/ygeiaforma/ygeia_forma/SayService.kt").takeIf { it.exists() }
            ?: File("android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/SayService.kt")
        assertTrue(src.path, src.exists())
        val s = src.readText()
        // Η σειρά: πρώτα έτοιμο (focus + μηχανή), μετά η απάντηση, και μιλά μόνο αν η απάντηση έφυγε.
        assertTrue(s.indexOf("held = PhoneVoice.prepare(applicationContext, until)") < s.indexOf("sendMessage(e.sourceNodeId, SAID, reply)"))
        assertTrue(s.contains("if (ok && sent) held!!.speak(el, en, 8_000L) else held?.release()"))
        assertTrue(s.contains("KEY_FEATURE_NOT_INSTALLED"))
    }

    @Test
    fun femaleVoiceFromTheName() {
        assertEquals("el-GR-SMTf00", femaleVoiceName(listOf("el-GR-SMTm00", "el-GR-SMTf00")))
        assertEquals("en-GB-female", femaleVoiceName(listOf("en-gb-x-rjs-local", "en-GB-female")))
        assertNull(femaleVoiceName(listOf("el-gr-x-vfz-local")))
    }

    @Test
    fun manifestRegistersTheServiceOnlyForTheSayPath() {
        val patch = File("../../tools/android/patch_manifest.py").takeIf { it.exists() } ?: File("tools/android/patch_manifest.py")
        if (!patch.exists()) return
        val s = patch.readText()
        assertTrue(s.contains("android:name=\".SayService\""))
        assertTrue(s.contains("android:path=\"/ygeia/say\""))
        assertTrue(s.contains("android.intent.action.TTS_SERVICE"))
    }
}
