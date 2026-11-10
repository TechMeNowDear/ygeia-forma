package gr.ygeiaforma.wear

import org.json.JSONArray
import org.json.JSONObject

/**
 * Το αποτέλεσμα μιας άσκησης για το κινητό, από την κατάσταση στο [Repo]. Ίδια μορφή με πριν· μόνο νέα, προαιρετικά πεδία
 * (το παλιό κινητό τα αγνοεί). Καθαρός Kotlin (χωρίς Android), για να ελέγχεται σε JVM.
 *
 * Σταθερό id ανά άσκηση (όνομα του DataItem): ένα περπάτημα = ένα αποτέλεσμα, όσες φορές κι αν γραφτεί (έλεγχος 9/11,
 * V-A-03). Οι παλμοί μιας προπόνησης του κινητού έχουν id ανά «Παλμοί εδώ» («hr<sid>-<αρχή>»), ώστε το δεύτερο κομμάτι
 * να μη σβήνει το πρώτο (V-A-11).
 */
object Results {
    /**
     * [now]: τώρα. [partialAt]: η άσκηση δεν τελείωσε κανονικά (η εφαρμογή έκλεισε απότομα): τέλος = το τελευταίο
     * στιγμιότυπο και «partial» = 1. [userEnd]: ο χρήστης πάτησε «Τέλος» στο ρολόι· σε προπόνηση του κινητού γράφεται
     * «fin» (η ώρα), ώστε να τελειώσει και εκεί (V-A-09). [endReason]: το Health Services την τελείωσε για άλλο λόγο
     * (π.χ. άλλη εφαρμογή, V-A-16).
     */
    fun build(now: Long, partialAt: Long? = null, userEnd: Boolean = false, endReason: Int? = null): Pair<String, JSONObject>? {
        val end0 = partialAt ?: now
        val hr = Repo.hr ?: HrStats(if (Repo.startedAt > 0) Repo.startedAt else end0)
        val local = Repo.local
        val result: Pair<String, JSONObject> = when {
            Repo.running == "walk" -> {
                val id = "walk${Repo.startedAt}"
                val end = if (Repo.endAt > 0) Repo.endAt else end0
                Repo.pauses.lastOrNull()?.let { if (it[1] == 0L) it[1] = end }
                fun sec(ms: Long) = ((ms - Repo.startedAt) / 1000)
                // Χωρίς κανένα σημείο ελέγχου από το Health Services (π.χ. δεν ξεκίνησε η μέτρηση): ο χρόνος από την ώρα, όχι 0 (W2-11).
                val sec = if (Repo.cpWall > 0 || Repo.activeSec > 0) Repo.activeSecNow(end) else wallActiveSec(Repo.startedAt, end, Repo.pauses)
                val cardio = JSONObject().put("activity", "walk").put("sec", sec).put("m", finite(Repo.meters))
                    .put("steps", Repo.steps).put("gps", Repo.gps)
                    .put("km", JSONArray().also { a -> for (k in Repo.splits) a.put(JSONArray().put(k[0]).put(sec(k[1]))) })
                    .put("pz", JSONArray().also { a -> for (p in Repo.pauses) a.put(JSONArray().put(sec(p[0])).put(sec(p[1]))) })
                hr.recovery()?.let { (e, m) -> cardio.put("hrr", JSONObject().put("e", e).put("m", m)) }
                val w = Repo.plan?.todayWorkout?.takeIf { it.isCardio }
                id to LiveSession(id, w?.id ?: "walk", w?.name ?: "Περπάτημα", Repo.startedAt, emptyList()).resultJson(end, hr, cardio)
            }
            local != null && local.setsDone > 0 -> local.id to local.resultJson(end0, hr)
            Repo.runningPhone -> {
                // Η προπόνηση γράφτηκε στο κινητό· εδώ οι παλμοί, και τα σετ όπως τα ξέρει το ρολόι: αν το κινητό έχασε
                // κάποιο ✓, το συμπληρώνει (έλεγχος 8/11) — και όταν το κινητό έκλεισε πρώτο την προπόνηση (V-A-12).
                val sid = Repo.runningSid ?: Repo.phone?.id ?: Repo.lastPhoneId
                if (sid.isNullOrEmpty()) return null
                val src = listOfNotNull(Repo.phone, Repo.lastPhone).firstOrNull { it.id == sid }
                val items = src?.resultJson(end0, hr)?.optJSONArray("items")
                val id = "hr$sid-${Repo.startedAt}"
                val o = JSONObject().put("v", 1).put("kind", "hr").put("sid", sid).put("id", id)
                hr.writeTo(o)
                if (items != null) o.put("items", items)
                if (userEnd) o.put("fin", end0)
                id to o
            }
            else -> return null
        }
        val o = result.second
        // Για τον έλεγχο στη συσκευή: πώς ήρθαν οι παλμοί και το μεγαλύτερο κενό (φαίνεται στη σύνοψη του κινητού).
        // Μετά από απότομο κλείσιμο (μερικό ή συνέχεια) τα κενά δεν είναι γνωστά (ο μετρητής ξεκίνησε από τη συνέχεια):
        // κανένα «hrGap»/«hrDel» αντί για ψεύτικο «ήρθαν όλοι μαζί» (έλεγχος του γ2, S2)· «hrRec» = 1 για τη σύνοψη.
        val gapsKnown = partialAt == null && !Repo.restored
        if (Repo.hrMode.isNotEmpty()) o.put("hrMode", Repo.hrMode)
        if (Repo.hrMode.isNotEmpty() && gapsKnown) o.put("hrGap", Repo.hrGaps.maxGapSec)
        // Έλεγχος γ2 (W2-08/W2-14): πόσες παραδόσεις παλμών, τι μπορεί το ρολόι, και το σφάλμα που σταμάτησε τη μέτρηση.
        // Νέα πεδία: το παλιό κινητό τα αγνοεί.
        if (Repo.hrMode.isNotEmpty() && gapsKnown) o.put("hrDel", Repo.hrGaps.deliveries)
        if (!gapsKnown) o.put("hrRec", 1)
        if (Repo.diag.isNotEmpty()) o.put("diag", Repo.diag)
        Repo.lastErr?.let { o.put("err", it.take(120)) }
        // Το όριο που ίσχυε στην άσκηση (έλεγχος 9/11, V-B-04· 0 = χωρίς όριο). Νέο πεδίο: το παλιό κινητό το αγνοεί.
        o.put("lim", Repo.alarm.limit ?: 0)
        if (partialAt != null) o.put("partial", 1)
        if (endReason != null) o.put("endR", endReason)
        return result
    }
}
