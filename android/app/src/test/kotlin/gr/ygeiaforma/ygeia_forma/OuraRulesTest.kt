package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Απλό JVM (χωρίς συσκευή): οι κανόνες επιστροφής από την Oura και τα προσωρινά αρχεία που σβήνονται. */
class OuraRulesTest {
    @Test
    fun callbackOnlyTheTwoExactForms() {
        assertTrue(OuraRules.isCallback("https", "ygeia-forma.netlify.app", -1, "/oura/callback", null))
        assertTrue(OuraRules.isCallback("ygeiaforma", "oura-callback", -1, "", null))
        assertTrue(OuraRules.isCallback("ygeiaforma", "oura-callback", -1, null, null))
        assertTrue(OuraRules.isCallback("ygeiaforma", "oura-callback", -1, "/", null))

        assertFalse(OuraRules.isCallback("http", "ygeia-forma.netlify.app", -1, "/oura/callback", null))
        assertFalse(OuraRules.isCallback("https", "evil-ygeia-forma.netlify.app", -1, "/oura/callback", null))
        assertFalse(OuraRules.isCallback("https", "ygeia-forma.netlify.app.evil.com", -1, "/oura/callback", null))
        assertFalse(OuraRules.isCallback("https", "ygeia-forma.netlify.app", 443, "/oura/callback", null))
        assertFalse(OuraRules.isCallback("https", "ygeia-forma.netlify.app", -1, "/oura/callback/", null))
        assertFalse(OuraRules.isCallback("https", "ygeia-forma.netlify.app", -1, "/oura/callback2", null))
        assertFalse(OuraRules.isCallback("https", "ygeia-forma.netlify.app", -1, "/oura", null))
        assertFalse(OuraRules.isCallback("https", "ygeia-forma.netlify.app", -1, "/oura/callback", "user"))
        assertFalse(OuraRules.isCallback("ygeiaforma", "oura-callback", -1, "/extra", null))
        assertFalse(OuraRules.isCallback("ygeiaforma", "oura-callback", 1, "", null))
        assertFalse(OuraRules.isCallback("ygeiaforma", "other", -1, "", null))
        assertFalse(OuraRules.isCallback("intent", "oura-callback", -1, "", null))
        assertFalse(OuraRules.isCallback(null, null, -1, null, null))
    }

    @Test
    fun onlyOwnTempFilesAreCleaned() {
        for (n in listOf(
            "sources.json.123456789.tmp", "sources_log.json.1.tmp", "oura_nights.json.42.tmp",
            "oura_tokens.bin.7.tmp", "oura_pending.bin.8.tmp", "oura_connecting.bin.9.tmp",
            // DP-11 (έλεγχος 9/11): και του training.json
            "training.json.123456789.tmp",
        )) assertTrue(n, OuraRules.isOwnTmp(n))
        for (n in listOf(
            "sources.json", "sources.json.tmp", "prefs.json.tmp", "dashboard.json.tmp", "days.json.123.tmp",
            "x.bg.tmp", "sources.json.123", "oura_tokens.bin", "mysources.json.1.tmp", "sources.jsonx.1.tmp",
        )) assertFalse(n, OuraRules.isOwnTmp(n))
    }

    @Test
    fun fileNamesHaveOneSource() {
        assertEquals(OuraRules.NIGHTS_FILE, OuraBridge.NIGHTS_FILE)
        assertEquals(OuraRules.PLAN_FILE, OuraBridge.PLAN_FILE)
        assertEquals(OuraRules.PLAN_LOG_FILE, OuraBridge.PLAN_LOG_FILE)
        assertEquals(
            listOf(
                "oura_nights.json", "sources.json", "sources_log.json", "training.json",
                "oura_tokens.bin", "oura_pending.bin", "oura_connecting.bin",
            ),
            OuraRules.OWN_FILES,
        )
        // Κάθε όνομα του Vault έχει το δικό του προσωρινό που καθαρίζεται.
        for (n in OuraRules.VAULT_NAMES) assertTrue(OuraRules.isOwnTmp("$n.bin.1.tmp"))
    }
}
