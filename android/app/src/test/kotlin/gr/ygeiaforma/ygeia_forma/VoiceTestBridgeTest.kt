package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** «Δοκιμή φωνής» (15/11): το κινητό ανοίγει την εφαρμογή στο ρολόι με «ygeiaforma-wear://voicetest». */
class VoiceTestBridgeTest {
    @Test
    fun opensTheWatchForTheTest() {
        val src = File("src/main/kotlin/gr/ygeiaforma/ygeia_forma/WearBridge.kt").takeIf { it.exists() }
            ?: File("android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/WearBridge.kt")
        assertTrue(src.path, src.exists())
        val s = src.readText()
        assertTrue(s.contains("\"voiceTest\" -> scope.launch { result.success(openWatch(\"voicetest\")) }"))
        assertTrue(s.contains("setData(Uri.parse(\"ygeiaforma-wear://\$host\"))"))
        val manifest = File("../wear/src/main/AndroidManifest.xml").takeIf { it.exists() }
            ?: File("android/wear/src/main/AndroidManifest.xml")
        if (manifest.exists()) assertTrue(manifest.readText().contains("android:host=\"voicetest\""))
    }
}
