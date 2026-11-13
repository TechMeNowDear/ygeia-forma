package gr.ygeiaforma.ygeia_forma

import com.samsung.android.sdk.health.data.HealthDataStore
import com.samsung.android.sdk.health.data.data.HealthDataPoint
import com.samsung.android.sdk.health.data.data.entries.HeartRate
import com.samsung.android.sdk.health.data.data.entries.OxygenSaturation
import com.samsung.android.sdk.health.data.data.entries.SleepSession
import com.samsung.android.sdk.health.data.request.DataType
import com.samsung.android.sdk.health.data.request.DataTypes
import com.samsung.android.sdk.health.data.request.LocalDateFilter
import com.samsung.android.sdk.health.data.request.LocalTimeFilter
import com.samsung.android.sdk.health.data.request.LocalTimeGroup
import com.samsung.android.sdk.health.data.request.LocalTimeGroupUnit
import com.samsung.android.sdk.health.data.request.Ordering
import com.samsung.android.sdk.health.data.request.ReadDataRequest
import com.samsung.android.sdk.health.data.request.ReadSourceFilter
import com.samsung.android.sdk.health.data.device.DeviceGroup
import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime

/**
 * Διαβάζει ό,τι χρειάζονται οι οθόνες, σε απλή μορφή (χρόνοι σε millis).
 * Οι υπολογισμοί (νύχτες, μέσοι όροι) γίνονται στη Flutter πλευρά.
 */
class DashboardReader(
    private val s: HealthDataStore,
    /**
     * Ως ποια νύχτα (μαζί) διαβάζεται ο ύπνος του ρολογιού (απόφαση 2/11): μετά τη σύνδεση του Oura ο ύπνος
     * έρχεται μόνο από το δαχτυλίδι, και του ρολογιού διαβάζεται μόνο για τη «Σύγκριση πηγών» τις πρώτες 14 μέρες.
     * null = χωρίς όριο (όπως πριν από το Oura). Δες [SleepPolicy].
     */
    private val sleepUntil: LocalDate? = null,
    /** Λεπτά κάτω από 90% από τις αναλυτικές μετρήσεις οξυγόνου: μόνο μετά από σύνδεση Oura (όπως πριν, αλλιώς). */
    private val spo2Series: Boolean = false,
    /**
     * Το αρχείο του σχεδίου πηγών υπάρχει αλλά δεν διαβάστηκε (A15): ο ύπνος γυρίζει ως σφάλμα («δεν διαβάστηκε»),
     * ποτέ ως άδεια λίστα που θα έμοιαζε με «δεν κοιμήθηκες» και θα έσβηνε τιμές ύπνου.
     */
    private val sleepPolicyError: Boolean = false,
    /** Πόσες μέρες παλμών στην κανονική ανάγνωση (ο RefreshWorker διαβάζει λιγότερες, A12). */
    private val heartDays: Int = DAYS,
    /** Πόσες μέρες ζυγίσεων (η εφαρμογή: 10 χρόνια· ο RefreshWorker: 30 μέρες, A12). */
    private val bodyDays: Long = 3653,
) {

    /**
     * Έλεγχος 3, E3: true στην κανονική ανάγνωση (30 μέρες), false σε κομμάτι ιστορικού ([readRange]). Μόνο στην
     * κανονική το «φίλτρο ρολογιού άδειο» είναι σφάλμα· στο κομμάτι σημειώνεται στο [nonWatch] («nonWatch» στο JSON).
     */
    private var recent = true
    private val nonWatch = java.util.LinkedHashSet<String>()

    /** Το τέλος της ανάγνωσης ύπνου: 18:00 της τελευταίας επιτρεπτής νύχτας (μετά αρχίζει η επόμενη νύχτα). */
    private fun sleepEnd(to: LocalDateTime): LocalDateTime {
        val cut = sleepUntil?.atTime(18, 0) ?: return to
        return if (cut.isBefore(to)) cut else to
    }

    /** Ύπνος στο [from, to), κομμένος στο όριο· κενή λίστα αν το όριο είναι πριν από την αρχή. */
    private suspend fun sleepLimited(from: LocalDateTime, to: LocalDateTime): JSONArray {
        if (sleepPolicyError) throw IllegalStateException("Δεν διαβάστηκε το σχέδιο πηγών")
        val end = sleepEnd(to)
        return if (!end.isAfter(from)) JSONArray() else sleep(from, end)
    }

    suspend fun read(grantedNames: Set<String>): JSONObject {
        val now = LocalDateTime.now()
        val today = now.toLocalDate()
        val from = today.minusDays(DAYS.toLong()).atStartOfDay()
        val o = JSONObject()

        fun has(t: DataType) = t.name in grantedNames

        if (has(DataTypes.SLEEP)) o.put("sleep", safe { sleepLimited(from, now) })
        if (has(DataTypes.HEART_RATE)) o.put("heart", safe { heart(today.minusDays(heartDays.toLong()).atStartOfDay(), now) })
        if (has(DataTypes.BLOOD_OXYGEN)) o.put("spo2", safe { spo2(from, now) })
        if (has(DataTypes.SKIN_TEMPERATURE)) o.put("skinTemp", safe { skinTemp(from, now) })
        if (has(DataTypes.ENERGY_SCORE)) o.put("energy", safe { energy(today.minusDays(DAYS.toLong()), today.plusDays(1)) })
        if (has(DataTypes.BODY_COMPOSITION)) o.put("body", safe { body(now) })
        if (has(DataTypes.STEPS)) o.put("steps", safe { steps(from, today.plusDays(1).atStartOfDay()) })
        if (has(DataTypes.FLOORS_CLIMBED)) o.put("floors", safe { floors(from, now) })
        if (has(DataTypes.ACTIVITY_SUMMARY)) {
            o.put("activity", safe { activity(today) })
            o.put("activityDaily", safe { activityDaily(from, today.plusDays(1).atStartOfDay()) })
        }
        if (has(DataTypes.STEPS)) {
            val stepsFrom = today.minusDays(STEP_DAYS.toLong()).atStartOfDay()
            o.put("stepsMin", safe { stepsByMinute(stepsFrom, now) })
            o.put("stepsFrom", epochMs(stepsFrom))
        }
        if (has(DataTypes.EXERCISE)) o.put("exercise", safe { exercise(from, now) })
        return o
    }

    /**
     * Τα ίδια δεδομένα για ένα παλιότερο διάστημα [fromDate, toDate) — για το ιστορικό (Τάσεις).
     * Ο ύπνος διαβάζεται και την προηγούμενη μέρα, ώστε να πιάνεται η πρώτη νύχτα.
     */
    suspend fun readRange(grantedNames: Set<String>, fromDate: LocalDate, toDate: LocalDate): JSONObject {
        val from = fromDate.atStartOfDay()
        val to = toDate.atStartOfDay()
        val o = JSONObject()
        recent = false
        nonWatch.clear()

        fun has(t: DataType) = t.name in grantedNames

        if (has(DataTypes.SLEEP)) o.put("sleep", safe { sleepLimited(from.minusDays(1), to) })
        if (has(DataTypes.HEART_RATE)) o.put("heart", safe { heart(from.minusDays(1), to) })
        if (has(DataTypes.BLOOD_OXYGEN)) o.put("spo2", safe { spo2(from.minusDays(1), to) })
        if (has(DataTypes.SKIN_TEMPERATURE)) o.put("skinTemp", safe { skinTemp(from.minusDays(1), to) })
        if (has(DataTypes.ENERGY_SCORE)) o.put("energy", safe { energy(fromDate, toDate) })
        if (has(DataTypes.STEPS)) {
            o.put("steps", safe { steps(from, to) })
            // Από την προηγούμενη μέρα, όπως ο ύπνος: για τα κενά της πρώτης νύχτας του διαστήματος.
            o.put("stepsMin", safe { stepsByMinute(from.minusDays(1), to) })
            o.put("stepsFrom", epochMs(from.minusDays(1)))
        }
        if (has(DataTypes.FLOORS_CLIMBED)) o.put("floors", safe { floors(from, to) })
        if (has(DataTypes.ACTIVITY_SUMMARY)) o.put("activityDaily", safe { activityDaily(from, to) })
        if (has(DataTypes.EXERCISE)) o.put("exercise", safe { exercise(from.minusDays(1), to) })
        o.put("readAt", epochMs(to.minusSeconds(1)))
        // E3: είδη με δεδομένα στο κομμάτι, αλλά κανένα από ρολόι (δεκτό ως «χωρίς δεδομένα ρολογιού»).
        o.put("nonWatch", JSONArray(nonWatch.toList()))
        // Έλεγχος 4 (red team M1): η πρώτη εγγραφή ύπνου ρολογιού όλου του ιστορικού (null = καμία). Η εφαρμογή δέχεται
        // τον ύπνο «από άλλη συσκευή» μόνο για κομμάτι πριν από αυτήν· μία σελίδα μίας εγγραφής, μόνο όταν χρειάζεται.
        if ("sleep" in nonWatch) o.put("firstWatchSleep", safe { firstWatchSleep() })
        return o
    }

    /** Η αρχή (ms) της πρώτης εγγραφής ύπνου ρολογιού στα τελευταία 10 χρόνια, ή JSONObject.NULL αν δεν υπάρχει. */
    private suspend fun firstWatchSleep(): Any {
        val now = LocalDateTime.now()
        val b = DataTypes.SLEEP.readDataRequestBuilder
            .setLocalTimeFilter(LocalTimeFilter.of(now.minusDays(3660), now))
            .setOrdering(Ordering.ASC)
            .setPageSize(1)
        b.setSourceFilter(WATCH)
        val first = s.readData(b.build()).dataList.firstOrNull() ?: return JSONObject.NULL
        return ms(first.startTime) ?: JSONObject.NULL
    }

    private fun epochMs(t: LocalDateTime): Long = t.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()

    // ---------- Βήματα ανά λεπτό: [αρχή λεπτού, βήματα] (μόνο λεπτά με βήματα) ----------

    /** Βήματα ανά λεπτό. Αν έμειναν σελίδες μετά το όριο, ΣΦΑΛΜΑ (A15): λεπτά που κόπηκαν θα έμοιαζαν «χωρίς βήματα». */
    private suspend fun stepsByMinute(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        val filter = LocalTimeFilter.of(from, to)
        var token: String? = null
        var pages = 0
        do {
            val b = DataType.StepsType.TOTAL.requestBuilder
                .setLocalTimeFilterWithGroup(filter, LocalTimeGroup.of(LocalTimeGroupUnit.MINUTELY, 1))
                .setOrdering(Ordering.ASC)
                .setPageSize(PAGE_SIZE)
            if (!token.isNullOrEmpty()) b.setPageToken(token)
            val r = s.aggregateData(b.build())
            for (d in r.dataList) {
                val v: Long? = d.value
                val t = ms(d.startTime) ?: continue
                if (v != null && v > 0) out.put(JSONArray().put(t).put(v))
            }
            token = r.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < 80)
        if (!token.isNullOrEmpty()) throw IllegalStateException("Πάρα πολλά λεπτά βημάτων (όριο ${80 * PAGE_SIZE})")
        return out
    }

    // ---------- Δραστηριότητα ανά μέρα: [ημέρα, ενεργά λεπτά, θερμίδες] ----------

    private suspend fun activityDaily(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val group = LocalTimeGroup.of(LocalTimeGroupUnit.DAILY, 1)
        val filter = LocalTimeFilter.of(from, to)
        val minutes = HashMap<Long, Long>()
        val calories = HashMap<Long, Double>()
        try {
            val r = s.aggregateData(
                DataType.ActivitySummaryType.TOTAL_ACTIVE_TIME.requestBuilder
                    .setLocalTimeFilterWithGroup(filter, group).setPageSize(400).build()
            )
            for (d in r.dataList) {
                val k = ms(d.startTime) ?: continue
                val v: Duration? = d.value
                if (v != null) minutes[k] = v.toMinutes()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
        }
        try {
            val r = s.aggregateData(
                DataType.ActivitySummaryType.TOTAL_CALORIES_BURNED.requestBuilder
                    .setLocalTimeFilterWithGroup(filter, group).setPageSize(400).build()
            )
            for (d in r.dataList) {
                val k = ms(d.startTime) ?: continue
                val v: Float? = d.value
                if (v != null && !v.isNaN()) calories[k] = v.toDouble()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
        }
        val out = JSONArray()
        for (k in (minutes.keys + calories.keys).toSortedSet()) {
            out.put(
                JSONArray()
                    .put(k)
                    .put(minutes[k] ?: JSONObject.NULL)
                    .put(calories[k] ?: JSONObject.NULL)
            )
        }
        return out
    }

    // ---------- Ασκήσεις: [αρχή, τέλος] ----------

    private suspend fun exercise(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        for (p in readAll(DataTypes.EXERCISE.readDataRequestBuilder, from, to)) {
            val a = ms(p.startTime) ?: continue
            out.put(JSONArray().put(a).put(ms(p.endTime) ?: a))
        }
        return out
    }

    // ---------- Ύπνος ----------

    private suspend fun sleep(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        for (p in readAll(DataTypes.SLEEP.readDataRequestBuilder, from, to, source = WATCH, unfiltered = DataTypes.SLEEP.readDataRequestBuilder, kind = "sleep")) {
            val start = ms(p.startTime) ?: continue
            val duration: Duration? = p.getValue(DataType.SleepType.DURATION)
            val score: Int? = p.getValue(DataType.SleepType.SLEEP_SCORE)
            val sessions: List<SleepSession>? = p.getValue(DataType.SleepType.SESSIONS)
            val input = (sessions ?: emptyList()).map { session ->
                DataRules.SessionIn(
                    ms(session.startTime),
                    ms(session.endTime),
                    session.duration?.toMinutes(),
                    (session.stages ?: emptyList()).mapNotNull { stage ->
                        val a = ms(stage.startTime) ?: return@mapNotNull null
                        val b = ms(stage.endTime) ?: return@mapNotNull null
                        DataRules.StageIn(stage.stage?.toString() ?: "UNDEFINED", a, b)
                    },
                )
            }
            // Round 1 (S3-8): η ζώνη ώρας της ίδιας της εγγραφής («off», λεπτά): η ώρα ύπνου/ξυπνήματος μένει η ώρα του
            // τόπου όπου κοιμήθηκες, ακόμα κι αν το ιστορικό ξαναδιαβαστεί με το κινητό σε άλλη ζώνη. Πρόσθετο κλειδί.
            val off = DataRules.offsetMinutes(p.zoneOffset?.totalSeconds)
            val recEnd = ms(p.endTime) ?: start
            // C2: μία εγγραφή ανά συνεδρία (το κενό ανάμεσα δεν μετρά ποτέ ως ύπνος).
            for (r in DataRules.splitSleep(start, recEnd, duration?.toMinutes(), score, input)) {
                val stages = JSONArray()
                for (x in r.stages) stages.put(JSONArray().put(x.stage).put(x.start).put(x.end))
                val o = JSONObject()
                    .put("start", r.start)
                    .put("end", r.end)
                    .put("minutes", r.minutes ?: JSONObject.NULL)
                    .put("score", r.score ?: JSONObject.NULL)
                    .put("stages", stages)
                if (off != null) {
                    o.put("off", off)
                    // Round 2 (R2-B-1): η ΜΙΑ ζώνη της Samsung ισχύει για όλη την εγγραφή· η Flutter κρίνει «σπίτι ή ταξίδι»
                    // μία φορά, με την αρχή και το τέλος της εγγραφής πριν χωριστεί σε κομμάτια. Πρόσθετα κλειδιά.
                    o.put("recStart", start).put("recEnd", recEnd)
                }
                out.put(o)
            }
        }
        return out
    }

    // ---------- Παλμοί: [αρχή, τέλος, μέσος, ελάχιστος, μέγιστος] ----------

    private suspend fun heart(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        // Το ρολόι μετρά συνεχώς: περισσότερες σελίδες από τα άλλα είδη (όριο 60.000 εγγραφές).
        for (p in readAll(DataTypes.HEART_RATE.readDataRequestBuilder, from, to, maxPages = HEART_MAX_PAGES, source = WATCH, unfiltered = DataTypes.HEART_RATE.readDataRequestBuilder, kind = "heart")) {
            val series: List<HeartRate>? = p.getValue(DataType.HeartRateType.SERIES_DATA)
            if (!series.isNullOrEmpty()) {
                for (h in series) {
                    // Μία άκυρη τιμή (NaN) δεν πρέπει να χαλάει όλη την ανάγνωση: παραλείπεται μόνο αυτή.
                    val avg = h.heartRate
                    if (!avg.isFinite()) continue
                    val a = ms(h.startTime) ?: continue
                    out.put(
                        JSONArray()
                            .put(a)
                            .put(ms(h.endTime) ?: a)
                            .put(avg.toDouble())
                            .put(finiteOr(h.min, avg))
                            .put(finiteOr(h.max, avg))
                    )
                }
            } else {
                val avg: Float? = p.getValue(DataType.HeartRateType.HEART_RATE)
                if (avg == null || !avg.isFinite()) continue
                val a = ms(p.startTime) ?: continue
                val min: Float? = p.getValue(DataType.HeartRateType.MIN_HEART_RATE)
                val max: Float? = p.getValue(DataType.HeartRateType.MAX_HEART_RATE)
                out.put(
                    JSONArray()
                        .put(a)
                        .put(ms(p.endTime) ?: a)
                        .put(avg.toDouble())
                        .put(finiteOr(min, avg))
                        .put(finiteOr(max, avg))
                )
            }
        }
        return out
    }

    // ---------- Οξυγόνο: [αρχή, τέλος, μέσο, ελάχιστο, μέγιστο, (δευτερόλεπτα κάτω από 90%)] ----------

    private suspend fun spo2(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        for (p in readAll(DataTypes.BLOOD_OXYGEN.readDataRequestBuilder, from, to, source = WATCH, unfiltered = DataTypes.BLOOD_OXYGEN.readDataRequestBuilder, kind = "spo2")) {
            val avg: Float? = p.getValue(DataType.BloodOxygenType.OXYGEN_SATURATION)
            if (avg == null || !avg.isFinite()) continue
            val a = ms(p.startTime) ?: continue
            val min: Float? = p.getValue(DataType.BloodOxygenType.MIN_OXYGEN_SATURATION)
            val max: Float? = p.getValue(DataType.BloodOxygenType.MAX_OXYGEN_SATURATION)
            val row = JSONArray()
                .put(a)
                .put(ms(p.endTime) ?: a)
                .put(avg.toDouble())
                .put(finiteOr(min, avg))
                .put(finiteOr(max, avg))
            if (spo2Series) below90(p)?.let { row.put(it) }
            out.put(row)
        }
        return out
    }

    /**
     * Δευτερόλεπτα με οξυγόνο κάτω από 90%, από τις αναλυτικές μετρήσεις — μόνο όταν βγαίνει με σιγουριά:
     * κάθε μέτρηση πρέπει να έχει διάρκεια (τέλος μετά την αρχή). Αλλιώς null (δεν το δείχνουμε).
     */
    private fun below90(p: HealthDataPoint): Long? = try {
        val series: List<OxygenSaturation>? = p.getValue(DataType.BloodOxygenType.SERIES_DATA)
        if (series.isNullOrEmpty()) {
            null
        } else {
            var total = 0L
            var ok = true
            for (x in series) {
                val a = x.startTime
                val b = x.endTime
                if (a == null || b == null || !b.isAfter(a)) {
                    ok = false
                    break
                }
                if (x.oxygenSaturation.isFinite() && x.oxygenSaturation < 90f) total += Duration.between(a, b).seconds
            }
            if (ok) total else null
        }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        null
    }

    // ---------- Θερμοκρασία δέρματος: [αρχή, τέλος, μέση] ----------

    private suspend fun skinTemp(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        for (p in readAll(DataTypes.SKIN_TEMPERATURE.readDataRequestBuilder, from, to, source = WATCH, unfiltered = DataTypes.SKIN_TEMPERATURE.readDataRequestBuilder, kind = "skinTemp")) {
            val avg: Float? = p.getValue(DataType.SkinTemperatureType.SKIN_TEMPERATURE)
            if (avg == null || avg.isNaN()) continue
            val a = ms(p.startTime) ?: continue
            out.put(
                JSONArray()
                    .put(a)
                    .put(ms(p.endTime) ?: a)
                    .put(avg.toDouble())
            )
        }
        return out
    }

    // ---------- Energy Score: [ημέρα σε millis, βαθμός] ----------

    private suspend fun energy(fromDate: LocalDate, toDate: LocalDate): JSONArray {
        val out = JSONArray()
        var token: String? = null
        var pages = 0
        do {
            val b = DataTypes.ENERGY_SCORE.readDataRequestBuilder
                .setLocalDateFilter(LocalDateFilter.of(fromDate, toDate))
                .setOrdering(Ordering.ASC)
                .setPageSize(PAGE_SIZE)
            if (!token.isNullOrEmpty()) b.setPageToken(token)
            val r = s.readData(b.build())
            for (p in r.dataList) {
                val score: Float? = p.getValue(DataType.EnergyScoreType.ENERGY_SCORE)
                if (score == null || score.isNaN()) continue
                val a = ms(p.startTime) ?: continue
                out.put(JSONArray().put(a).put(score.toDouble()))
            }
            token = r.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < MAX_PAGES)
        return out
    }

    // ---------- Σύσταση σώματος (ζυγίσεις), 10 χρόνια (όπως το ιστορικό) ----------
    // Διαβάζονται όλες με την εφαρμογή που τις έγραψε («app»): η Flutter κρατά ΜΟΝΟ της InBody (A2) και μετρά τις
    // άλλες, ώστε να φαίνεται ότι αγνοήθηκαν.

    private suspend fun body(now: LocalDateTime): JSONArray {
        val out = JSONArray()
        val from = now.minusDays(bodyDays)
        for (p in readAll(DataTypes.BODY_COMPOSITION.readDataRequestBuilder, from, now)) {
            val t = ms(p.startTime) ?: continue
            val o = JSONObject().put("time", t)
            putFloat(o, "weight", p.getValue(DataType.BodyCompositionType.WEIGHT))
            putFloat(o, "fatPct", p.getValue(DataType.BodyCompositionType.BODY_FAT))
            putFloat(o, "fatKg", p.getValue(DataType.BodyCompositionType.BODY_FAT_MASS))
            putFloat(o, "smm", p.getValue(DataType.BodyCompositionType.SKELETAL_MUSCLE_MASS))
            putFloat(o, "ffm", p.getValue(DataType.BodyCompositionType.FAT_FREE_MASS))
            putFloat(o, "bmi", p.getValue(DataType.BodyCompositionType.BODY_MASS_INDEX))
            putFloat(o, "water", p.getValue(DataType.BodyCompositionType.TOTAL_BODY_WATER))
            val bmr: Int? = p.getValue(DataType.BodyCompositionType.BASAL_METABOLIC_RATE)
            if (bmr != null) o.put("bmr", bmr)
            o.put("app", p.dataSource?.appId ?: "")
            // Round 1 (S3-8): η ζώνη ώρας της ζύγισης («off», λεπτά): η μέρα και η ώρα της μένουν όπως ζυγίστηκες, και με
            // το κινητό σε άλλη ζώνη (πριν, μια πρωινή ζύγιση μπορούσε να γραφτεί στην προηγούμενη μέρα). Πρόσθετο κλειδί.
            DataRules.offsetMinutes(p.zoneOffset?.totalSeconds)?.let { o.put("off", it) }
            out.put(o)
        }
        return out
    }

    // ---------- Βήματα ανά μέρα: [ημέρα σε millis, βήματα] ----------

    private suspend fun steps(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val request = DataType.StepsType.TOTAL.requestBuilder
            .setLocalTimeFilterWithGroup(LocalTimeFilter.of(from, to), LocalTimeGroup.of(LocalTimeGroupUnit.DAILY, 1))
            .setOrdering(Ordering.ASC)
            .setPageSize(400)
            .build()
        val out = JSONArray()
        for (d in s.aggregateData(request).dataList) {
            // Μέρα χωρίς τιμή = δεν μετρήθηκε (όχι «0 βήματα»).
            val v: Long = d.value ?: continue
            val a = ms(d.startTime) ?: continue
            out.put(JSONArray().put(a).put(v))
        }
        return out
    }

    // ---------- Όροφοι ανά μέρα: [ημέρα σε millis, όροφοι] ----------
    // Το σύνολο της Samsung (όπως στα βήματα), ώστε κινητό και ρολόι να μη μετρώνται δύο φορές.

    private suspend fun floors(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val request = DataType.FloorsClimbedType.TOTAL.requestBuilder
            .setLocalTimeFilterWithGroup(LocalTimeFilter.of(from, to), LocalTimeGroup.of(LocalTimeGroupUnit.DAILY, 1))
            .setOrdering(Ordering.ASC)
            .setPageSize(400)
            .build()
        val out = JSONArray()
        for (d in s.aggregateData(request).dataList) {
            val f: Float = d.value ?: continue
            if (!f.isFinite()) continue
            val a = ms(d.startTime) ?: continue
            out.put(JSONArray().put(a).put(f.toDouble()))
        }
        return out
    }

    // ---------- Δραστηριότητα σήμερα ----------

    private suspend fun activity(today: LocalDate): JSONObject {
        val filter = LocalTimeFilter.of(today.atStartOfDay(), LocalDateTime.now())
        val o = JSONObject()
        tryPut(o, "calories") {
            s.aggregateData(
                DataType.ActivitySummaryType.TOTAL_CALORIES_BURNED.requestBuilder.setLocalTimeFilter(filter).build()
            ).dataList.firstOrNull()?.value?.toDouble()
        }
        tryPut(o, "activeCalories") {
            s.aggregateData(
                DataType.ActivitySummaryType.TOTAL_ACTIVE_CALORIES_BURNED.requestBuilder.setLocalTimeFilter(filter).build()
            ).dataList.firstOrNull()?.value?.toDouble()
        }
        tryPut(o, "activeMinutes") {
            s.aggregateData(
                DataType.ActivitySummaryType.TOTAL_ACTIVE_TIME.requestBuilder.setLocalTimeFilter(filter).build()
            ).dataList.firstOrNull()?.value?.toMinutes()
        }
        tryPut(o, "distance") {
            s.aggregateData(
                DataType.ActivitySummaryType.TOTAL_DISTANCE.requestBuilder.setLocalTimeFilter(filter).build()
            ).dataList.firstOrNull()?.value?.toDouble()
        }
        return o
    }

    // ---------- Βοηθητικά ----------

    private suspend fun readAll(
        builder: ReadDataRequest.DualTimeBuilder<HealthDataPoint>,
        from: LocalDateTime,
        to: LocalDateTime,
        maxPages: Int = MAX_PAGES,
        source: ReadSourceFilter? = null,
        /** Καινούργιος builder του ίδιου είδους ΧΩΡΙΣ φίλτρο, για τον έλεγχο C6 (null = χωρίς έλεγχο). */
        unfiltered: ReadDataRequest.DualTimeBuilder<HealthDataPoint>? = null,
        /** Το όνομα του είδους στο JSON (για το «nonWatch» του E3). */
        kind: String = "",
    ): List<HealthDataPoint> {
        val all = ArrayList<HealthDataPoint>()
        var token: String? = null
        var pages = 0
        do {
            val b = builder
                .setLocalTimeFilter(LocalTimeFilter.of(from, to))
                .setOrdering(Ordering.ASC)
                .setPageSize(PAGE_SIZE)
            if (source != null) b.setSourceFilter(source)
            if (!token.isNullOrEmpty()) b.setPageToken(token)
            val r = s.readData(b.build())
            all.addAll(r.dataList)
            token = r.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < maxPages)
        // Έμειναν κι άλλες σελίδες: η ανάγνωση είναι μισή. Καλύτερα σφάλμα (η εφαρμογή κρατά τις παλιές
        // τιμές) παρά μισά δεδομένα που θα έμοιαζαν πλήρη.
        // C6: με φίλτρο «μόνο ρολόι» καμία εγγραφή — υπάρχουν όμως χωρίς φίλτρο; Τότε σφάλμα (η εφαρμογή κρατά το
        // ιστορικό), όχι άδεια λίστα. Μόνο όταν βγήκε άδειο: μία σελίδα μίας εγγραφής, σχεδόν χωρίς κόστος.
        if (unfiltered != null && all.isEmpty()) {
            val probe = unfiltered
                .setLocalTimeFilter(LocalTimeFilter.of(from, to))
                .setOrdering(Ordering.ASC)
                .setPageSize(1)
            when (DataRules.filterOutcome(0, s.readData(probe.build()).dataList.size, recent)) {
                DataRules.FilterOutcome.ERROR -> throw IllegalStateException(DataRules.WATCH_FILTER_EMPTY)
                DataRules.FilterOutcome.NON_WATCH -> nonWatch.add(kind)
                DataRules.FilterOutcome.OK -> {}
            }
        }
        if (!token.isNullOrEmpty()) {
            val e = IllegalStateException("Πάρα πολλές εγγραφές (όριο ${maxPages * PAGE_SIZE})")
            // Να το μάθουμε (Sentry), μία φορά ανά άνοιγμα της εφαρμογής: κάθε επόμενη ανάγνωση θα κοπεί ξανά.
            if (!cappedReported) {
                cappedReported = true
                ErrorQueue.report(e, "samsung")
            }
            throw e
        }
        return all
    }

    private fun finiteOr(v: Float?, fallback: Float): Double =
        (if (v != null && v.isFinite()) v else fallback).toDouble()

    private fun ms(i: java.time.Instant?): Long? = i?.toEpochMilli()

    private fun putFloat(o: JSONObject, key: String, v: Float?) {
        if (v != null && !v.isNaN()) o.put(key, v.toDouble())
    }

    private suspend fun tryPut(o: JSONObject, key: String, block: suspend () -> Any?) {
        try {
            val v = block()
            if (v != null) o.put(key, v)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Λείπει άδεια ή δεδομένο: απλώς δεν το δείχνουμε.
        }
    }

    private suspend fun <T : Any> safe(block: suspend () -> T): Any =
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            JSONObject().put("error", e.toString())
        }

    companion object {
        /**
         * Μόνο ό,τι μέτρησε ρολόι (A2, οδηγός «Read data» της Samsung: ReadSourceFilter.fromDeviceType(DeviceGroup.WATCH)).
         * Για ύπνο, παλμούς, οξυγόνο, θερμοκρασία (DataRules.WATCH_ONLY): όχι Oura μέσω Health Connect, όχι κινητό.
         */
        val WATCH: ReadSourceFilter get() = ReadSourceFilter.fromDeviceType(DeviceGroup.WATCH)

        const val DAYS = 30
        const val STEP_DAYS = 7
        const val PAGE_SIZE = 1000
        const val MAX_PAGES = 20
        const val HEART_MAX_PAGES = 60

        @Volatile
        private var cappedReported = false
    }
}
