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
        if (has(DataTypes.ENERGY_SCORE)) o.put("energy", safe { energy(today) })
        if (has(DataTypes.BODY_COMPOSITION)) o.put("body", safe { body(now) })
        if (has(DataTypes.STEPS)) o.put("steps", safe { steps(today) })
        if (has(DataTypes.FLOORS_CLIMBED)) o.put("floors", safe { floors(from, now) })
        if (has(DataTypes.ACTIVITY_SUMMARY)) o.put("activity", safe { activity(today) })
        return o
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
        for (p in readAll(DataTypes.HEART_RATE.readDataRequestBuilder, from, to)) {
            val series: List<HeartRate>? = p.getValue(DataType.HeartRateType.SERIES_DATA)
            if (!series.isNullOrEmpty()) {
                for (h in series) {
                    out.put(
                        JSONArray()
                            .put((ms(h.startTime) ?: 0L))
                            .put((ms(h.endTime) ?: 0L))
                            .put(h.heartRate.toDouble())
                            .put(h.min.toDouble())
                            .put(h.max.toDouble())
                    )
                }
            } else {
                val avg: Float? = p.getValue(DataType.HeartRateType.HEART_RATE)
                if (avg == null || avg.isNaN()) continue
                val min: Float? = p.getValue(DataType.HeartRateType.MIN_HEART_RATE)
                val max: Float? = p.getValue(DataType.HeartRateType.MAX_HEART_RATE)
                out.put(
                    JSONArray()
                        .put((ms(p.startTime) ?: 0L))
                        .put(ms(p.endTime) ?: ms(p.startTime) ?: 0L)
                        .put(avg.toDouble())
                        .put((min ?: avg).toDouble())
                        .put((max ?: avg).toDouble())
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
            if (avg == null || avg.isNaN()) continue
            val min: Float? = p.getValue(DataType.BloodOxygenType.MIN_OXYGEN_SATURATION)
            val max: Float? = p.getValue(DataType.BloodOxygenType.MAX_OXYGEN_SATURATION)
            out.put(
                JSONArray()
                    .put((ms(p.startTime) ?: 0L))
                    .put(ms(p.endTime) ?: ms(p.startTime) ?: 0L)
                    .put(avg.toDouble())
                    .put((min ?: avg).toDouble())
                    .put((max ?: avg).toDouble())
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

    private suspend fun energy(today: LocalDate): JSONArray {
        val out = JSONArray()
        var token: String? = null
        var pages = 0
        do {
            val b = DataTypes.ENERGY_SCORE.readDataRequestBuilder
                .setLocalDateFilter(LocalDateFilter.of(today.minusDays(DAYS.toLong()), today.plusDays(1)))
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

    private suspend fun steps(today: LocalDate): JSONArray {
        val request = DataType.StepsType.TOTAL.requestBuilder
            .setLocalTimeFilterWithGroup(
                LocalTimeFilter.of(today.minusDays(DAYS.toLong()).atStartOfDay(), today.plusDays(1).atStartOfDay()),
                LocalTimeGroup.of(LocalTimeGroupUnit.DAILY, 1),
            )
            .setOrdering(Ordering.ASC)
            .build()
        val out = JSONArray()
        for (d in s.aggregateData(request).dataList) {
            val v: Long? = d.value
            out.put(JSONArray().put((ms(d.startTime) ?: 0L)).put(v ?: 0L))
        }
        return out
    }

    // ---------- Όροφοι: [αρχή, όροφοι] ----------

    private suspend fun floors(from: LocalDateTime, to: LocalDateTime): JSONArray {
        val out = JSONArray()
        for (p in readAll(DataTypes.FLOORS_CLIMBED.readDataRequestBuilder, from, to)) {
            val f: Float? = p.getValue(DataType.FloorsClimbedType.FLOOR)
            if (f == null || f.isNaN()) continue
            out.put(JSONArray().put((ms(p.startTime) ?: 0L)).put(f.toDouble()))
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
        } while (!token.isNullOrEmpty() && pages < MAX_PAGES)
        return all
    }

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
        const val PAGE_SIZE = 1000
        const val MAX_PAGES = 10
    }
}
