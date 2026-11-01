package gr.ygeiaforma.ygeia_forma

import com.samsung.android.sdk.health.data.HealthDataStore
import com.samsung.android.sdk.health.data.data.HealthDataPoint
import com.samsung.android.sdk.health.data.data.entries.HeartRate
import com.samsung.android.sdk.health.data.data.entries.SleepSession
import com.samsung.android.sdk.health.data.request.DataType
import com.samsung.android.sdk.health.data.request.DataTypes
import com.samsung.android.sdk.health.data.request.LocalDateFilter
import com.samsung.android.sdk.health.data.request.LocalTimeFilter
import com.samsung.android.sdk.health.data.request.LocalTimeGroup
import com.samsung.android.sdk.health.data.request.LocalTimeGroupUnit
import com.samsung.android.sdk.health.data.request.Ordering
import com.samsung.android.sdk.health.data.request.ReadDataRequest
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
class DashboardReader(private val s: HealthDataStore) {

    suspend fun read(grantedNames: Set<String>): JSONObject {
        val now = LocalDateTime.now()
        val today = now.toLocalDate()
        val from = today.minusDays(DAYS.toLong()).atStartOfDay()
        val o = JSONObject()

        fun has(t: DataType) = t.name in grantedNames

        if (has(DataTypes.SLEEP)) o.put("sleep", safe { sleep(from, now) })
        if (has(DataTypes.HEART_RATE)) o.put("heart", safe { heart(from, now) })
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

        fun has(t: DataType) = t.name in grantedNames

        if (has(DataTypes.SLEEP)) o.put("sleep", safe { sleep(from.minusDays(1), to) })
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
        return o
    }

    private fun epochMs(t: LocalDateTime): Long = t.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()

    // ---------- Βήματα ανά λεπτό: [αρχή λεπτού, βήματα] (μόνο λεπτά με βήματα) ----------

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
                if (v != null && v > 0) out.put(JSONArray().put(ms(d.startTime) ?: 0L).put(v))
            }
            token = r.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < 80)
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
            out.put(JSONArray().put(ms(p.startTime) ?: 0L).put(ms(p.endTime) ?: ms(p.startTime) ?: 0L))
        }
        return out
    }

    // ---------- Ύπνος ----------

    private suspend fun sleep(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        for (p in readAll(DataTypes.SLEEP.readDataRequestBuilder, from, to)) {
            val duration: Duration? = p.getValue(DataType.SleepType.DURATION)
            val score: Int? = p.getValue(DataType.SleepType.SLEEP_SCORE)
            val sessions: List<SleepSession>? = p.getValue(DataType.SleepType.SESSIONS)
            val stages = JSONArray()
            for (session in sessions ?: emptyList()) {
                for (stage in session.stages ?: emptyList()) {
                    stages.put(
                        JSONArray()
                            .put(stage.stage?.toString() ?: "UNDEFINED")
                            .put((ms(stage.startTime) ?: 0L))
                            .put((ms(stage.endTime) ?: 0L))
                    )
                }
            }
            out.put(
                JSONObject()
                    .put("start", (ms(p.startTime) ?: 0L))
                    .put("end", ms(p.endTime) ?: ms(p.startTime) ?: 0L)
                    .put("minutes", duration?.toMinutes() ?: JSONObject.NULL)
                    .put("score", score ?: JSONObject.NULL)
                    .put("stages", stages)
            )
        }
        return out
    }

    // ---------- Παλμοί: [αρχή, τέλος, μέσος, ελάχιστος, μέγιστος] ----------

    private suspend fun heart(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        // Το ρολόι μετρά συνεχώς: περισσότερες σελίδες από τα άλλα είδη (όριο 60.000 εγγραφές).
        for (p in readAll(DataTypes.HEART_RATE.readDataRequestBuilder, from, to, maxPages = HEART_MAX_PAGES)) {
            val series: List<HeartRate>? = p.getValue(DataType.HeartRateType.SERIES_DATA)
            if (!series.isNullOrEmpty()) {
                for (h in series) {
                    // Μία άκυρη τιμή (NaN) δεν πρέπει να χαλάει όλη την ανάγνωση: παραλείπεται μόνο αυτή.
                    val avg = h.heartRate
                    if (!avg.isFinite()) continue
                    out.put(
                        JSONArray()
                            .put((ms(h.startTime) ?: 0L))
                            .put((ms(h.endTime) ?: 0L))
                            .put(avg.toDouble())
                            .put(finiteOr(h.min, avg))
                            .put(finiteOr(h.max, avg))
                    )
                }
            } else {
                val avg: Float? = p.getValue(DataType.HeartRateType.HEART_RATE)
                if (avg == null || !avg.isFinite()) continue
                val min: Float? = p.getValue(DataType.HeartRateType.MIN_HEART_RATE)
                val max: Float? = p.getValue(DataType.HeartRateType.MAX_HEART_RATE)
                out.put(
                    JSONArray()
                        .put((ms(p.startTime) ?: 0L))
                        .put(ms(p.endTime) ?: ms(p.startTime) ?: 0L)
                        .put(avg.toDouble())
                        .put(finiteOr(min, avg))
                        .put(finiteOr(max, avg))
                )
            }
        }
        return out
    }

    // ---------- Οξυγόνο: [αρχή, τέλος, μέσο, ελάχιστο, μέγιστο] ----------

    private suspend fun spo2(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        for (p in readAll(DataTypes.BLOOD_OXYGEN.readDataRequestBuilder, from, to)) {
            val avg: Float? = p.getValue(DataType.BloodOxygenType.OXYGEN_SATURATION)
            if (avg == null || !avg.isFinite()) continue
            val min: Float? = p.getValue(DataType.BloodOxygenType.MIN_OXYGEN_SATURATION)
            val max: Float? = p.getValue(DataType.BloodOxygenType.MAX_OXYGEN_SATURATION)
            out.put(
                JSONArray()
                    .put((ms(p.startTime) ?: 0L))
                    .put(ms(p.endTime) ?: ms(p.startTime) ?: 0L)
                    .put(avg.toDouble())
                    .put(finiteOr(min, avg))
                    .put(finiteOr(max, avg))
            )
        }
        return out
    }

    // ---------- Θερμοκρασία δέρματος: [αρχή, τέλος, μέση] ----------

    private suspend fun skinTemp(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        for (p in readAll(DataTypes.SKIN_TEMPERATURE.readDataRequestBuilder, from, to)) {
            val avg: Float? = p.getValue(DataType.SkinTemperatureType.SKIN_TEMPERATURE)
            if (avg == null || avg.isNaN()) continue
            out.put(
                JSONArray()
                    .put((ms(p.startTime) ?: 0L))
                    .put(ms(p.endTime) ?: ms(p.startTime) ?: 0L)
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
                out.put(JSONArray().put((ms(p.startTime) ?: 0L)).put(score.toDouble()))
            }
            token = r.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < MAX_PAGES)
        return out
    }

    // ---------- Σύσταση σώματος (InBody), 2 χρόνια ----------

    private suspend fun body(now: LocalDateTime): JSONArray {
        val out = JSONArray()
        val from = now.minusYears(2)
        for (p in readAll(DataTypes.BODY_COMPOSITION.readDataRequestBuilder, from, now)) {
            val o = JSONObject().put("time", (ms(p.startTime) ?: 0L))
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
            out.put(JSONArray().put((ms(d.startTime) ?: 0L)).put(v))
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
            out.put(JSONArray().put((ms(d.startTime) ?: 0L)).put(f.toDouble()))
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
    ): List<HealthDataPoint> {
        val all = ArrayList<HealthDataPoint>()
        var token: String? = null
        var pages = 0
        do {
            val b = builder
                .setLocalTimeFilter(LocalTimeFilter.of(from, to))
                .setOrdering(Ordering.ASC)
                .setPageSize(PAGE_SIZE)
            if (!token.isNullOrEmpty()) b.setPageToken(token)
            val r = s.readData(b.build())
            all.addAll(r.dataList)
            token = r.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < maxPages)
        // Έμειναν κι άλλες σελίδες: η ανάγνωση είναι μισή. Καλύτερα σφάλμα (η εφαρμογή κρατά τις παλιές
        // τιμές) παρά μισά δεδομένα που θα έμοιαζαν πλήρη.
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

    private companion object {
        const val DAYS = 30
        const val STEP_DAYS = 7
        const val PAGE_SIZE = 1000
        const val MAX_PAGES = 20
        const val HEART_MAX_PAGES = 60

        @Volatile
        var cappedReported = false
    }
}
