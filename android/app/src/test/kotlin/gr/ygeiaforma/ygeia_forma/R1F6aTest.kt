package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * Round 1 (f6a · S9-9): το training.json που δεν διαβάζεται μπαίνει στην άκρη — μετονομασία, ποτέ σβήσιμο, ποτέ από πάνω
 * σε άλλο «.bad». Όλα τα δεδομένα είναι δοκιμαστικά.
 */
class R1F6aTest {
    @Test
    fun setAsideRenamesAndKeepsTheText() {
        val dir = Files.createTempDirectory("tr").toFile()
        val f = File(dir, "training.json")
        f.writeText("{χαλασμένο")
        assertEquals("training.json.bad", TrainingRules.setAside(f, 1_700_000_000_000L))
        assertFalse(f.exists())
        assertEquals("{χαλασμένο", File(dir, "training.json.bad").readText())
        dir.deleteRecursively()
    }

    @Test
    fun secondSetAsideNeverOverwritesTheFirst() {
        val dir = Files.createTempDirectory("tr").toFile()
        val f = File(dir, "training.json")
        f.writeText("πρώτο")
        assertEquals("training.json.bad", TrainingRules.setAside(f, 1L))
        f.writeText("δεύτερο")
        assertEquals("training.json.2.bad", TrainingRules.setAside(f, 2L))
        assertEquals("πρώτο", File(dir, "training.json.bad").readText())
        assertEquals("δεύτερο", File(dir, "training.json.2.bad").readText())
        // και τρίτη φορά την ίδια στιγμή: τίποτα δεν αλλάζει (το αρχείο μένει όπως είναι)
        f.writeText("τρίτο")
        File(dir, "training.json.3.bad").writeText("παλιό")
        assertNull(TrainingRules.setAside(f, 3L))
        assertEquals("τρίτο", f.readText())
        assertEquals("παλιό", File(dir, "training.json.3.bad").readText())
        dir.deleteRecursively()
    }

    @Test
    fun missingFileOrFolderDoesNothing() {
        val dir = Files.createTempDirectory("tr").toFile()
        assertNull(TrainingRules.setAside(File(dir, "training.json")))
        assertTrue(dir.listFiles()!!.isEmpty())
        // φάκελος με το ίδιο όνομα: δεν είναι αρχείο, δεν μετονομάζεται
        val sub = File(dir, "training.json")
        assertTrue(sub.mkdir())
        assertNull(TrainingRules.setAside(sub))
        assertTrue(sub.isDirectory)
        dir.deleteRecursively()
    }
}
