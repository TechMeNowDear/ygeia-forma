package gr.ygeiaforma.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * «Δοκιμή φωνής» (αίτημα χρήστη 15/11): ίδιος δρόμος με το περπάτημα, αποτέλεσμα στο ρολόι και στο κινητό.
 */
class VoiceTestTest {
    private fun source(name: String) = File("src/main/kotlin/gr/ygeiaforma/wear/$name").readText()

    @Test
    fun resultCodes() {
        // Κινητό: ακούστηκε εκεί, ό,τι κι αν ισχύει στο ρολόι.
        assertEquals(VoiceTest.PHONE, VoiceTest.code(VoiceRoute.PHONE, "none", false, true))
        assertEquals(VoiceTest.NO_VOICE, VoiceTest.code(VoiceRoute.WATCH, "none", null, false))
        assertEquals(VoiceTest.REFUSED, VoiceTest.code(VoiceRoute.WATCH, "el", false, false))
        assertEquals(VoiceTest.MUTED, VoiceTest.code(VoiceRoute.WATCH, "el", true, true))
        assertEquals(VoiceTest.HEADSET, VoiceTest.code(VoiceRoute.WATCH_HEADSET, "el", true, false))
        assertEquals(VoiceTest.SPEAKER, VoiceTest.code(VoiceRoute.WATCH, "el", true, false))
        // Δεν ήρθε ακόμα απάντηση (δεν πρέπει να συμβεί): ηχείο ρολογιού.
        assertEquals(VoiceTest.SPEAKER, VoiceTest.code(null, "el", true, false))
        // Αρκετός χρόνος για το «ρώτα το κινητό» (2,5″) πριν κριθεί.
        assertTrue(VoiceTest.SETTLE_MS > SAY_WAIT_MS)
    }

    @Test
    fun wordsInFull() {
        assertEquals("Δοκιμή φωνής σε 1 δευτερόλεπτο. Στο κινητό πάτα το κουμπί της αρχικής οθόνης.", VoiceTest.countdown(1))
        assertTrue(VoiceTest.countdown(10).startsWith("Δοκιμή φωνής σε 10 δευτερόλεπτα."))
        for (c in listOf(VoiceTest.HEADSET, VoiceTest.PHONE, VoiceTest.SPEAKER, VoiceTest.NO_VOICE, VoiceTest.REFUSED, VoiceTest.MUTED, VoiceTest.BUSY)) {
            assertTrue(c, VoiceTest.result(c).endsWith("."))
        }
        assertEquals("Δοκιμή φωνής" to "Voice test", Say.TEST)
    }

    @Test
    fun resultGoesToThePhone() {
        val j = Link.ackJson(0, 5, vt = 1_700_000_000_000L to VoiceTest.SPEAKER)
        assertEquals(1_700_000_000_000L, j.getJSONObject("vt").getLong("at"))
        assertEquals("ws", j.getJSONObject("vt").getString("w"))
        assertFalse(Link.ackJson(0, 5).has("vt"))
        // Το κινητό δείχνει το κουμπί μόνο σε ρολόι που ξέρει τη δοκιμή.
        assertEquals(1, Link.ackJson(0, 5).getInt("vtok"))
        // Και ξαναστέλνεται όταν αλλάζει (το «κλειδί» έχει τον χρόνο της δοκιμής).
        assertTrue(source("Link.kt").contains("val key = \"\${p.hrLimit ?: 0}/\${p.at}/\$slow/vt\$vtAt\""))
    }

    @Test
    fun openedFromThePhoneWithTheScreenOn() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertTrue(manifest.contains("android:host=\"voicetest\""))
        val act = source("WatchActivity.kt")
        assertTrue(act.contains("if (i?.data?.host == \"voicetest\" && fresh) voiceTestPending = true"))
        assertTrue(act.contains("System.currentTimeMillis() < voiceTestUntil"))
        // Ίδιος δρόμος με το περπάτημα: ρωτά το κινητό μόνο αν ξέρει να απαντά.
        assertTrue(act.contains("voice.say(Say.TEST, askPhone = Repo.plan?.voiceKnown == true) { route = it }"))
        // Η φωνή κλείνει πάντα μετά (όχι αν στο μεταξύ ξεκίνησε άσκηση).
        assertTrue(act.contains("if (Repo.running == null) voice.stopLater()"))
        val voice = source("Voice.kt")
        assertTrue(voice.contains("a.requestAudioFocus(r) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED"))
    }
}
