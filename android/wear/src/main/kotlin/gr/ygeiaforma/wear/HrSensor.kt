package gr.ygeiaforma.wear

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock

/**
 * Εφεδρεία για την ειδοποίηση ορίου (8/11): απευθείας ο αισθητήρας παλμών, ΜΟΝΟ όταν το ρολόι δεν υποστηρίζει
 * παράδοση παλμών ανά 5″ με σβηστή οθόνη (BatchingMode.HEART_RATE_5_SECONDS) και υπάρχει όριο γιατρού,
 * και μόνο όσο τρέχει η άσκηση. Αισθητήρας «αφύπνισης» (wake-up), για να έρχονται τιμές και με σβηστή οθόνη·
 * μικρή ομαδοποίηση στο υλικό ([MAX_LATENCY_US]) ώστε ο επεξεργαστής να ξυπνά ανά ~2″ και όχι κάθε τιμή.
 *
 * Οι τιμές πάνε μόνο στην ειδοποίηση και στην ένδειξη· οι μετρήσεις της προπόνησης έρχονται από το Health Services.
 */
class HrSensor(private val ctx: Context, private val onBpm: (bpm: Int, at: Long) -> Unit) : SensorEventListener {
    private var sm: SensorManager? = null

    /** true αν ξεκίνησε (υπάρχει αισθητήρας και δέχτηκε την εγγραφή). */
    fun start(): Boolean {
        val m = ctx.getSystemService(SensorManager::class.java) ?: return false
        val s = m.getDefaultSensor(Sensor.TYPE_HEART_RATE, true) ?: m.getDefaultSensor(Sensor.TYPE_HEART_RATE) ?: return false
        val ok = try {
            m.registerListener(this, s, SAMPLING_US, MAX_LATENCY_US)
        } catch (_: SecurityException) {
            false
        }
        if (ok) sm = m
        return ok
    }

    fun stop() {
        sm?.unregisterListener(this)
        sm = null
    }

    override fun onSensorChanged(e: SensorEvent) {
        if (e.sensor.type != Sensor.TYPE_HEART_RATE || e.values.isEmpty()) return
        // Χωρίς επαφή ή αναξιόπιστη: όχι τιμή (το «δεν μετριούνται» βγαίνει από την έλλειψη τιμών).
        if (e.accuracy == SensorManager.SENSOR_STATUS_NO_CONTACT || e.accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE) return
        val bpm = Math.round(e.values[0])
        if (bpm !in 26..249) return
        onBpm(bpm, sensorWallTime(e.timestamp, System.currentTimeMillis(), SystemClock.elapsedRealtimeNanos()))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    companion object {
        private const val SAMPLING_US = 1_000_000
        private const val MAX_LATENCY_US = 2_000_000
    }
}
