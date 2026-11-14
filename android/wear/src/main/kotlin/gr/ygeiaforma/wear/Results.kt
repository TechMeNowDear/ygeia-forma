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
                // 14/11: η απόσταση από τα βήματα (βήματα × μήκος βήματος), για περπάτημα χωρίς GPS. Νέο πεδίο: το παλιό
                // κινητό το αγνοεί. Το κινητό διαλέγει ποια δείχνει με τον ίδιο κανόνα ([shownDistance]).
                estMeters(Repo.steps, Repo.stride).takeIf { it >= 10 }?.let { cardio.put("mest", Math.round(it)) }
                // Η ζώνη που ίσχυε στο περπάτημα (12/11). Νέο πεδίο: το παλιό κινητό το αγνοεί.
                Repo.zoneAlarm.zone?.let { cardio.put("zone", it.toJson()) }
                // Το περπάτημα του προγράμματος της μέρας που ΞΕΚΙΝΗΣΕ (έλεγχος 13/11, round 7, R7-A8-6), όχι της μέρας που
                // γράφεται το αποτέλεσμα (μετά τα μεσάνυχτα, ή μερικό που γράφεται μέρες μετά).
                val w = Repo.plan?.walkOn(Repo.startedAt)
                id to LiveSession(id, w?.id ?: "walk", w?.name ?: "Περπάτημα", Repo.startedAt, emptyList()).resultJson(end, hr, cardio)
            }
            local != null && local.setsDone > 0 -> local.id to local.resultJson(end0, hr)
            Repo.runningPhone -> {
                // Η προπόνηση γράφτηκε στο κινητό· εδώ οι παλμοί, και τα σετ όπως τα ξέρει το ρολόι: αν το κινητό έχασε
                // κάποιο ✓, το συμπληρώνει (έλεγχος 8/11) — και όταν το κινητό έκλεισε πρώτο την προπόνηση (V-A-12).
                val sid = Repo.runningSid ?: Repo.phone?.id ?: Repo.lastPhoneId
                if (sid.isNullOrEmpty()) return null
                // Και όταν στο μεταξύ το κινητό ξεκίνησε άλλη προπόνηση ([Repo.endedPhone], έλεγχος 13/11, round 7, R7-A8-2).
                val src = Repo.phoneById(sid)
                val items = src?.resultJson(end0, hr)?.optJSONArray("items")
                if (items != null && src != null) markConfirmed(items, src)
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
        // Τελικός έλεγχος (Συμβούλιο 1, Σ1): μαζί και πόσες τιμές παλμών ήρθαν καλές / χαμηλής ακρίβειας / άχρηστες
        // («q=5400/120/15»), μέσα στο ίδιο κείμενο: κανένα νέο πεδίο, το παλιό κινητό το διαβάζει όπως πριν.
        val diag = Repo.hrQuality.withDiag(Repo.diag)
        if (diag.isNotEmpty()) o.put("diag", diag)
        Repo.lastErr?.let { o.put("err", it.take(120)) }
        // Το όριο που ίσχυε στην άσκηση (έλεγχος 9/11, V-B-04· 0 = χωρίς όριο). Νέο πεδίο: το παλιό κινητό το αγνοεί.
        o.put("lim", Repo.alarm.limit ?: 0)
        if (partialAt != null) o.put("partial", 1)
        if (endReason != null) o.put("endR", endReason)
        return result
    }

    /**
     * Έλεγχος 14/11, round 8 (R8-A8-2): στο αποτέλεσμα των παλμών μιας προπόνησης του κινητού ([items], ίδια σειρά με τα
     * [LiveSession.items] και τα σετ τους, από το [LiveSession.resultJson]), «c»: 1 σε κάθε ✓ που το κινητό είχε ήδη δει
     * ([SetT.confirmed]). Έτσι το κινητό ξέρει ότι ένα τέτοιο ✓ που δεν έχει πια το έβγαλε ο χρήστης εκεί (και το ρολόι δεν
     * πρόλαβε να το μάθει), και δεν το ξαναβάζει· συμπληρώνει μόνο τα ✓ που έγιναν στο ρολόι και δεν τα είδε ποτέ. Ίδιος
     * κανόνας με το [keepWatchEdits]. Νέο, προαιρετικό πεδίο: το παλιό κινητό το αγνοεί.
     */
    internal fun markConfirmed(items: JSONArray, s: LiveSession) {
        for ((i, item) in s.items.withIndex()) {
            val log = items.optJSONObject(i)?.optJSONArray("log") ?: continue
            for ((k, set) in item.sets.withIndex()) {
                if (set.done && set.confirmed) log.optJSONObject(k)?.put("c", 1)
            }
        }
    }
}
