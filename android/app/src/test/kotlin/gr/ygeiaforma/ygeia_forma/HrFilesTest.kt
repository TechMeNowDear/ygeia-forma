package gr.ygeiaforma.ygeia_forma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

/** Έλεγχος 9/11 (V-A-02): οι παλμοί κάθε προπόνησης σε δικό της αρχείο· ποτέ έξω από τον φάκελο. */
class HrFilesTest {
    @Test
    fun writeReadListDelete() {
        val dir = Files.createTempDirectory("hr").toFile()
        assertTrue(HrFiles.list(dir).isEmpty())
        assertTrue(HrFiles.write(dir, "w-walk1700000000000", "{\"v\":1}"))
        assertTrue(HrFiles.write(dir, "s1700000000001", "{\"v\":1,\"n\":2}"))
        assertEquals("{\"v\":1}", HrFiles.read(dir, "w-walk1700000000000"))
        assertEquals(listOf("s1700000000001", "w-walk1700000000000"), HrFiles.list(dir))
        // ξαναγράφεται ατομικά (κανένα προσωρινό δεν μένει)
        assertTrue(HrFiles.write(dir, "s1700000000001", "{\"v\":1,\"n\":3}"))
        assertEquals("{\"v\":1,\"n\":3}", HrFiles.read(dir, "s1700000000001"))
        assertTrue(dir.listFiles()!!.none { it.name.endsWith(".tmp") })
        assertTrue(HrFiles.delete(dir, "s1700000000001"))
        assertNull(HrFiles.read(dir, "s1700000000001"))
        assertTrue(HrFiles.delete(dir, "δεν-υπάρχει"))
        assertEquals(listOf("w-walk1700000000000"), HrFiles.list(dir))
        dir.deleteRecursively()
    }

    @Test
    fun onlySafeIds() {
        val dir = Files.createTempDirectory("hr").toFile()
        for (bad in listOf("", "..", ".", "../training", "a/b", "a\\b", "x.tmp")) {
            assertFalse(bad, HrFiles.validId(bad))
            assertFalse(bad, HrFiles.write(dir, bad, "{}"))
            assertNull(HrFiles.read(dir, bad))
        }
        assertTrue(HrFiles.validId("w-walk1700000000000"))
        assertTrue(HrFiles.validId("s1700000000001"))
        dir.deleteRecursively()
    }

    /** Έλεγχος του #91 (S1): αρχείο που δεν διαβάζεται κρατιέται στην άκρη, δεν σβήνεται, δεν γράφεται από πάνω. */
    @Test
    fun unreadableFileIsSetAsideNotDeleted() {
        val dir = Files.createTempDirectory("hr").toFile()
        assertTrue(HrFiles.write(dir, "s1", "{χαλασμένο"))
        assertEquals("s1.json.bad", HrFiles.setAside(dir, "s1"))
        assertNull(HrFiles.read(dir, "s1"))
        assertEquals("{χαλασμένο", java.io.File(dir, "s1.json.bad").readText())
        assertTrue(HrFiles.list(dir).isEmpty())
        // νέο αρχείο με το ίδιο id: το παλιό μένει όπως ήταν
        assertTrue(HrFiles.write(dir, "s1", "{\"v\":1}"))
        assertEquals("s1.json.42.bad", HrFiles.setAside(dir, "s1", now = 42))
        assertEquals("{χαλασμένο", java.io.File(dir, "s1.json.bad").readText())
        assertNull(HrFiles.setAside(dir, "δεν-υπάρχει"))
        assertNull(HrFiles.setAside(dir, "../x"))
        dir.deleteRecursively()
    }

    @Test
    fun staleTempFilesAreCleaned() {
        val dir = Files.createTempDirectory("hr").toFile()
        val old = java.io.File(dir, "s1.json.123.tmp").apply { writeText("x") }
        old.setLastModified(1_000)
        val fresh = java.io.File(dir, "s2.json.456.tmp").apply { writeText("x") }
        HrFiles.list(dir, now = fresh.lastModified() + 10_000)
        assertFalse(old.exists())
        assertTrue(fresh.exists())
        dir.deleteRecursively()
    }
}
