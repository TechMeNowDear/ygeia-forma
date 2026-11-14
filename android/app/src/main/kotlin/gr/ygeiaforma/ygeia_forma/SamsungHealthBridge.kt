package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import com.samsung.android.sdk.health.data.HealthDataService
import com.samsung.android.sdk.health.data.HealthDataStore
import com.samsung.android.sdk.health.data.data.AggregateOperation
import com.samsung.android.sdk.health.data.data.Field
import com.samsung.android.sdk.health.data.data.HealthDataPoint
import com.samsung.android.sdk.health.data.data.entries.SleepSession
import com.samsung.android.sdk.health.data.error.ErrorCode
import com.samsung.android.sdk.health.data.error.HealthDataException
import com.samsung.android.sdk.health.data.error.ResolvablePlatformException
import com.samsung.android.sdk.health.data.permission.AccessType
import com.samsung.android.sdk.health.data.permission.Permission
import com.samsung.android.sdk.health.data.request.AggregateRequest
import com.samsung.android.sdk.health.data.request.DataType
import com.samsung.android.sdk.health.data.request.DataTypes
import com.samsung.android.sdk.health.data.request.LocalDateFilter
import com.samsung.android.sdk.health.data.request.LocalTimeFilter
import com.samsung.android.sdk.health.data.request.LocalTimeGroup
import com.samsung.android.sdk.health.data.request.LocalTimeGroupUnit
import com.samsung.android.sdk.health.data.request.Ordering
import com.samsung.android.sdk.health.data.request.ReadDataRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Γέφυρα προς το Samsung Health Data SDK (μόνο ανάγνωση).
 * Η Flutter πλευρά καλεί μεθόδους στο κανάλι «ygeia/samsung» και παίρνει πίσω JSON κείμενο.
 * Κάθε ανάγνωση εδώ γίνεται όταν το ζητήσει η οθόνη· στο παρασκήνιο διαβάζει μόνο ο RefreshWorker.
 */
class SamsungHealthBridge(
    private val activity: Activity,
    private val scope: CoroutineScope,
) : MethodChannel.MethodCallHandler {

    private var cachedStore: HealthDataStore? = null
    @Volatile private var pendingResolution: ResolvablePlatformException? = null
    private val deviceNames = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val deviceWatch = java.util.concurrent.ConcurrentHashMap<String, Boolean>()

    private fun store(): HealthDataStore =
        cachedStore ?: HealthDataService.getStore(activity.applicationContext).also { cachedStore = it }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> respond(result) { status() }
            // Ανοίγει οθόνη της Samsung: στο main thread.
            "requestPermissions" -> respondMain(result) { requestPermissions() }
            "readAll" -> respond(result) { readAll(call.argument<Int>("days") ?: 30) }
            "dashboard" -> respondText(result) { dashboard() }
            "readRange" -> respond(result) {
                readRange(call.argument<String>("from") ?: "", call.argument<String>("to") ?: "")
            }
            // Βάση: όλες οι εγγραφές και αναγνώσεις μία-μία, με τη σειρά που ζητήθηκαν (A8, DbQueue).
            "saveDays" -> respondDb(result) {
                val json = call.argument<String>("json") ?: "[]"
                withContext(DbQueue.dispatcher) { dayStore.save(JSONArray(json)) }
                JSONObject().put("ok", true)
            }
            "loadDays" -> respondDb(result) {
                val rows = withContext(DbQueue.dispatcher) { dayStore.loadAll() }
                JSONObject().put("ok", true).put("days", rows)
            }
            "clearDays" -> respondDb(result) {
                withContext(DbQueue.dispatcher) { dayStore.clear() }
                JSONObject().put("ok", true)
            }
            // Η βάση βρέθηκε χαλασμένη και κρατήθηκε αντίγραφο (A7): {"ok", "corrupt": ώρα σε ms ή null, "seen": αν η
            // κάρτα της έκλεισε, "partial": αν η επαναφορά δεν διάβασε όλα}. Round 8 (R8-A9-2, f4): το σημάδι της βλάβης
            // μένει και μετά το «Εντάξει». Round 9 (R9-A12-2, f4): η απάντηση από καθαρή συνάρτηση ([DbSalvage.status]).
            "dbStatus" -> respondDb(result) {
                val dir = activity.applicationContext.noBackupFilesDir
                withContext(DbQueue.dispatcher) { DbSalvage.status(dir) }
            }
            // R8-A9-2: «Εντάξει» = η κάρτα της βλάβης «at» έκλεισε. Δεν σβήνει το σημάδι της βλάβης (η επαναφορά συνεχίζει).
            "dbStatusSeen" -> respondDb(result) {
                val ctx = activity.applicationContext
                val asked = (call.argument<Any>("at") as? Number)?.toLong()
                withContext(DbQueue.dispatcher) {
                    (asked ?: DayStore.corruptAt(ctx))?.let { DayStore.markSeen(ctx, it) }
                }
                JSONObject().put("ok", true)
            }
            "savePdf" -> respond(result) {
                val pages = call.argument<List<ByteArray>>("pages") ?: emptyList()
                val name = call.argument<String>("name") ?: "ygeia-anafora.pdf"
                // Round 9 (R9-U4-4, f4): γεμάτος χώρος → «kind: full» (ελληνικό μήνυμα στη Flutter, όχι το κείμενο της
                // Java), όπως το αντίγραφο (R7-A9-5). Κάθε άλλο σφάλμα πηγαίνει στις αναφορές σφαλμάτων όπως πριν.
                try {
                    val uri = withContext(Dispatchers.IO) { PdfExporter.save(activity, pages, name) }
                    // R7-U4-3: δεύτερο PDF την ίδια μέρα → το σύστημα το ονομάζει «… (1).pdf»· η οθόνη δείχνει το πραγματικό όνομα.
                    val shown = withContext(Dispatchers.IO) { BackupFiles.displayName(activity, uri) } ?: name
                    JSONObject().put("ok", true).put("uri", uri.toString()).put("name", shown)
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    val kind = BackupRules.failKind(e)
                    if (kind == "other") throw e
                    JSONObject().put("ok", false).put("kind", kind)
                }
            }
            "sharePdf", "openPdf" -> {
                val json = try {
                    val uri = android.net.Uri.parse(call.argument<String>("uri") ?: "")
                    if (call.method == "sharePdf") PdfExporter.share(activity, uri) else PdfExporter.open(activity, uri)
                    JSONObject().put("ok", true)
                } catch (e: Throwable) {
                    errorJson(e)
                }
                result.success(json.toString())
            }
            // Μερικά MB: ανάγνωση εκτός main thread (A9).
            "cachedDashboard" -> respondText(result) { withContext(Dispatchers.IO) { readFile(DASHBOARD_FILE) ?: "{}" } }
            "loadPrefs" -> result.success(loadPrefsText())
            "savePrefs" -> respond(result) {
                val json = call.argument<String>("json") ?: "{}"
                // Το όνομα της αναφοράς μένει μόνο στο κινητό (noBackupFilesDir), έξω από το αντίγραφο Google.
                val (shared, own) = DataRules.splitDeviceOnlyPrefs(json)
                // Round 1 (S9-5): πρώτα το prefs.json (στόχοι, στοιχεία, ζώνη, μέση) και χωριστά το μικρό ιδιωτικό αρχείο·
                // πριν, μια αποτυχία στο ιδιωτικό αρχείο άφηνε άγραφες και όλες τις ρυθμίσεις. Αν αποτύχει οποιοδήποτε: «write».
                val ok = withContext(Dispatchers.IO) {
                    val main = writeFile(PREFS_FILE, shared)
                    writeDevicePrefs(own) && main
                }
                if (ok) JSONObject().put("ok", true) else JSONObject().put("ok", false).put("kind", "write")
            }
            // Round 1 (S3-2 / S9-1): «Ξεκίνα με νέες ρυθμίσεις» μετά από χαλασμένο prefs.json: το αρχείο κρατιέται ως «.bad».
            "prefsSetAside" -> respond(result) {
                val ok = withContext(Dispatchers.IO) { setAsidePrefs() }
                if (ok) JSONObject().put("ok", true) else JSONObject().put("ok", false).put("kind", "write")
            }
            "resolve" -> {
                val r = pendingResolution
                if (r != null) {
                    pendingResolution = null
                    r.resolve(activity)
                }
                result.success(JSONObject().put("ok", r != null).toString())
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Όπως [respond], για απαντήσεις που είναι ήδη κείμενο JSON. Όλη η δουλειά (ανάγνωση, χτίσιμο, σειριοποίηση μερικών
     * MB) εκτός main thread (A9)· μόνο η απάντηση στη Flutter γίνεται στο main thread, όπως πρέπει.
     */
    private fun respondText(result: MethodChannel.Result, block: suspend () -> String) {
        scope.launch {
            val text = withContext(Dispatchers.Default) {
                try {
                    block()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    errorJson(e).toString()
                }
            }
            result.success(text)
        }
    }

    /** Η δουλειά και η σειριοποίηση εκτός main thread (A9). */
    private fun respond(result: MethodChannel.Result, block: suspend () -> JSONObject) =
        respondText(result) { block().toString() }

    /** Έλεγχος 3, E6: εργασία της βάσης ΚΑΤΕΥΘΕΙΑΝ στη σειρά της ([DbQueue.run]), αυστηρά με τη σειρά των κλήσεων. */
    private fun respondDb(result: MethodChannel.Result, block: suspend () -> JSONObject) {
        DbQueue.run(scope, { result.success(it) }) {
            try {
                block().toString()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                errorJson(e).toString()
            }
        }
    }

    /** Για ό,τι ανοίγει οθόνη (άδειες Samsung): στο main thread. */
    private fun respondMain(result: MethodChannel.Result, block: suspend () -> JSONObject) {
        scope.launch {
            val json = try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                errorJson(e)
            }
            result.success(json.toString())
        }
    }

    // ---------- Κατάσταση και άδειες ----------

    private suspend fun status(): JSONObject {
        val granted = store().getGrantedPermissions(permissions)
        return JSONObject()
            .put("ok", true)
            .put("granted", granted.size)
            .put("total", permissions.size)
    }

    private suspend fun requestPermissions(): JSONObject {
        val granted = store().requestPermissions(permissions, activity)
        return JSONObject()
            .put("ok", true)
            .put("granted", granted.size)
            .put("total", permissions.size)
    }

    // ---------- Δεδομένα για τις οθόνες ----------

    private val dayStore by lazy { DayStore.get(activity.applicationContext) }

    private suspend fun readRange(from: String, to: String): JSONObject {
        val s = store()
        val names = s.getGrantedPermissions(permissions).map { it.dataType.name }.toSet()
        return SleepPolicy.reader(activity, s)
            .readRange(names, java.time.LocalDate.parse(from), java.time.LocalDate.parse(to))
            .put("ok", true)
            .put("granted", names.size)
            .put("total", permissions.size)
    }

    private suspend fun dashboard(): String {
        val s = store()
        val granted = s.getGrantedPermissions(permissions)
        val names = granted.map { it.dataType.name }.toSet()
        // Round 7 (R7-A10-4): το «readAt» το βάζει ο DashboardReader (η αρχή της ανάγνωσης)· όχι εδώ, με την ώρα του τέλους.
        val o = SleepPolicy.reader(activity, s).read(names)
            .put("ok", true)
            .put("granted", granted.size)
            .put("total", permissions.size)
        // Το JSON (μερικά MB) φτιάχνεται μία φορά, εκτός main thread (όλο το dashboard() τρέχει εκτός, A9).
        val text = o.toString()
        // Βοηθητικό αντίγραφο (ξαναδιαβάζεται): χωρίς «σφράγισμα» στον δίσκο σε κάθε ανανέωση.
        if (granted.isNotEmpty()) withContext(Dispatchers.IO) { writeFile(DASHBOARD_FILE, text, sync = false) }
        return text
    }

    // «Δεν υπάρχει αρχείο» = {} (προεπιλογές). Αρχείο που υπάρχει αλλά δεν διαβάστηκε = σφάλμα,
    // ώστε η εφαρμογή να μη γράψει προεπιλογές πάνω στις ρυθμίσεις.
    private fun loadPrefsText(): String {
        val shared = try {
            val f = java.io.File(activity.filesDir, PREFS_FILE)
            if (f.exists()) f.readText() else "{}"
        } catch (e: Throwable) {
            return """{"ok":false,"kind":"read"}"""
        }
        // Round 1 (S3-2 / S9-1): αρχείο που υπάρχει αλλά δεν είναι αντικείμενο JSON (άδειο, κομμένο, «[]») = χαλασμένο.
        // Η εφαρμογή το λέει στον χρήστη και δεν γράφει τίποτα από πάνω του· το αρχείο μένει στη θέση του ως τότε.
        if (!DataRules.prefsReadable(shared)) return """{"ok":false,"kind":"corrupt"}"""
        val own = try {
            val f = devicePrefsFile()
            if (f.exists()) f.readText() else null
        } catch (e: Throwable) {
            null
        }
        return DataRules.mergeDeviceOnlyPrefs(shared, own)
    }

    private fun devicePrefsFile() = java.io.File(activity.noBackupFilesDir, DataRules.DEVICE_PREFS_FILE)

    /** Δες [DataRules.setAsideUnreadablePrefs]. Με το ίδιο κλείδωμα με το [writeFile]: ποτέ στη μέση μιας εγγραφής. */
    @Synchronized
    private fun setAsidePrefs(): Boolean =
        DataRules.setAsideUnreadablePrefs(java.io.File(activity.filesDir, PREFS_FILE), System.currentTimeMillis())

    /** Τα ιδιωτικά κλειδιά των ρυθμίσεων (ή σβήσιμο του αρχείου όταν δεν υπάρχουν πια). `false` αν απέτυχε. */
    /** Δες [DataRules.splitDeviceOnlyPrefs]: null = μένει όπως είναι (E6), «{}» = σβήνεται, αλλιώς γράφεται. */
    private fun writeDevicePrefs(own: String?): Boolean =
        try {
            val f = devicePrefsFile()
            when (own) {
                null -> true
                DataRules.DEVICE_PREFS_DELETE -> !f.exists() || f.delete()
                else -> OuraBridge.atomicWrite(f, own.toByteArray(Charsets.UTF_8))
            }
        } catch (e: Throwable) {
            false
        }

    private fun readFile(name: String): String? =
        try {
            val f = java.io.File(activity.filesDir, name)
            if (f.exists()) f.readText() else null
        } catch (e: Throwable) {
            null
        }

    /**
     * Γράφει πρώτα σε προσωρινό αρχείο, το «σφραγίζει» στον δίσκο (sync) και μετά το μετονομάζει:
     * μια διακοπή ρεύματος αφήνει είτε το παλιό είτε το νέο αρχείο, ποτέ μισό. `false` αν απέτυχε.
     */
    @Synchronized
    private fun writeFile(name: String, text: String, sync: Boolean = true): Boolean =
        try {
            val f = java.io.File(activity.filesDir, name)
            val tmp = java.io.File(activity.filesDir, "$name.tmp")
            java.io.FileOutputStream(tmp).use { out ->
                out.write(text.toByteArray(Charsets.UTF_8))
                out.flush()
                if (sync) out.fd.sync()
            }
            tmp.renameTo(f)
        } catch (e: Throwable) {
            false
        }

    // ---------- Ανάγνωση ----------

    private suspend fun readAll(days: Int): JSONObject {
        val s = store()
        val grantedNames = s.getGrantedPermissions(permissions).map { it.dataType.name }.toSet()
        val to = LocalDateTime.now()
        val from = to.minusDays(days.toLong())

        val types = JSONArray()
        for ((key, type) in readTypes) {
            val o = JSONObject().put("key", key)
            if (type.name !in grantedNames) {
                types.put(o.put("state", "no_permission"))
                continue
            }
            try {
                // Η ζυγαριά δεν χρησιμοποιείται κάθε μέρα: για τη σύσταση σώματος κοιτάμε έναν χρόνο πίσω.
                val typeFrom = if (key == "body_composition") to.minusDays(365) else from
                o.put("days", java.time.temporal.ChronoUnit.DAYS.between(typeFrom, to))
                readOne(s, type, typeFrom, to, o)
                // Πόσες μετρούν στην εφαρμογή (A2): ύπνος/παλμοί/οξυγόνο/θερμοκρασία μόνο από ρολόι (το ίδιο φίλτρο της
                // Samsung με την κανονική ανάγνωση), ζυγίσεις μόνο από την InBody. Οι υπόλοιπες αγνοούνται.
                if (o.optString("state") == "ok") {
                    val counted = when {
                        key in DataRules.WATCH_ONLY -> countWith(s, type, typeFrom, to, DashboardReader.WATCH)
                        key == "body_composition" -> {
                            val src = o.optJSONArray("sources") ?: JSONArray()
                            (0 until src.length()).sumOf { i ->
                                val x = src.getJSONObject(i)
                                if (DataRules.isScaleApp(x.optString("app"))) x.optInt("count") else 0
                            }
                        }
                        else -> null
                    }
                    if (counted != null) o.put("counted", counted).put("ignored", (o.optInt("count") - counted).coerceAtLeast(0))
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                o.put("state", "error").put("error", errorJson(e))
            }
            types.put(o)
        }

        // Round 7 (R7-A10-3): βήματα και θερμίδες της κάρτας «Σήμερα» για ΤΗ ΜΕΡΑ του «readAt» (ως αυτή τη στιγμή), όχι για
        // όποια μέρα είναι όταν φτάσει η κάθε ερώτηση· η Flutter δείχνει στα «Βήματα» μόνο την τιμή αυτής της μέρας.
        val day = to.toLocalDate()
        val today = JSONObject()
        if (DataTypes.STEPS.name in grantedNames) {
            try {
                today.put("stepsByDay", dailySteps(s, 7, day))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                today.put("stepsError", errorJson(e))
            }
        } else {
            today.put("stepsError", JSONObject().put("kind", "no_permission"))
        }
        if (DataTypes.ACTIVITY_SUMMARY.name in grantedNames) {
            putToday(s, today, "totalCalories", DataType.ActivitySummaryType.TOTAL_CALORIES_BURNED, day, to)
            putToday(s, today, "activeCalories", DataType.ActivitySummaryType.TOTAL_ACTIVE_CALORIES_BURNED, day, to)
            putToday(s, today, "activeTime", DataType.ActivitySummaryType.TOTAL_ACTIVE_TIME, day, to)
            putToday(s, today, "distance", DataType.ActivitySummaryType.TOTAL_DISTANCE, day, to)
        }

        return JSONObject()
            .put("ok", true)
            .put("days", days)
            .put("readAt", to.withNano(0).toString())
            .put("types", types)
            .put("today", today)
    }

    private suspend fun readOne(
        s: HealthDataStore,
        type: DataType,
        from: LocalDateTime,
        to: LocalDateTime,
        o: JSONObject,
    ) {
        var count = 0
        var latest: HealthDataPoint? = null
        val sources = LinkedHashMap<String, Int>()
        val seen = HashSet<String>()
        val fields = type.allFields
        var token: String? = null
        var pages = 0

        do {
            val request = buildRequest(type, from, to, token)
            if (request == null) {
                o.put("state", "unsupported")
                return
            }
            val response = s.readData(request)
            for (p in response.dataList) {
                count++
                if (latest == null) latest = p
                val key = (p.dataSource?.appId ?: "") + "|" + (p.dataSource?.deviceId ?: "")
                sources[key] = (sources[key] ?: 0) + 1
                if (seen.size < fields.size) {
                    for (f in fields) {
                        if (f.name !in seen && valueOf(p, f) != null) seen.add(f.name)
                    }
                }
            }
            token = response.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < MAX_PAGES)

        val last = latest
        if (count == 0 || last == null) {
            o.put("state", "empty")
            return
        }

        val fieldArray = JSONArray()
        for (f in fields) {
            val v = describe(valueOf(last, f))
            fieldArray.put(
                JSONObject()
                    .put("name", f.name)
                    .put("value", v ?: JSONObject.NULL)
                    .put("seen", f.name in seen)
            )
        }

        val sourceArray = JSONArray()
        for ((key, n) in sources) {
            val app = key.substringBefore("|")
            val deviceId = key.substringAfter("|")
            val src = JSONObject()
                .put("app", app)
                .put("device", deviceName(s, deviceId))
                .put("count", n)
            // Αν η πηγή μετρά στην εφαρμογή (A2): ρολόι για τα είδη του ρολογιού, InBody για τις ζυγίσεις.
            val key = readTypes.firstOrNull { it.second == type }?.first
            if (key != null && key in DataRules.WATCH_ONLY) src.put("counts", deviceWatch[deviceId] == true)
            if (key == "body_composition") src.put("counts", DataRules.isScaleApp(app))
            sourceArray.put(src)
        }

        o.put("state", "ok")
            .put("count", count)
            .put("capped", !token.isNullOrEmpty())
            .put("latest", localText(last.startTime))
            .put("fields", fieldArray)
            .put("sources", sourceArray)
    }

    /** Πόσες εγγραφές δίνει η Samsung με το φίλτρο πηγής [source] (για το «Τι φτάνει»). */
    private suspend fun countWith(
        s: HealthDataStore,
        type: DataType,
        from: LocalDateTime,
        to: LocalDateTime,
        source: com.samsung.android.sdk.health.data.request.ReadSourceFilter,
    ): Int {
        var n = 0
        var token: String? = null
        var pages = 0
        do {
            val request = buildRequest(type, from, to, token, source) ?: return 0
            val response = s.readData(request)
            n += response.dataList.size
            token = response.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < MAX_PAGES)
        return n
    }

    @Suppress("UNCHECKED_CAST")
    private fun buildRequest(
        type: DataType,
        from: LocalDateTime,
        to: LocalDateTime,
        token: String?,
        source: com.samsung.android.sdk.health.data.request.ReadSourceFilter? = null,
    ): ReadDataRequest<HealthDataPoint>? {
        val readable = type as? DataType.Readable<*, *> ?: return null
        return when (val builder = readable.readDataRequestBuilder) {
            is ReadDataRequest.DualTimeBuilder<*> -> {
                val b = (builder as ReadDataRequest.DualTimeBuilder<HealthDataPoint>)
                    .setLocalTimeFilter(LocalTimeFilter.of(from, to))
                    .setOrdering(Ordering.DESC)
                    .setPageSize(PAGE_SIZE)
                if (source != null) b.setSourceFilter(source)
                if (!token.isNullOrEmpty()) b.setPageToken(token)
                b.build()
            }
            is ReadDataRequest.LocalDateBuilder<*> -> {
                // Round 1 (S3-4): το τέλος του LocalDateFilter ΔΕΝ περιλαμβάνεται (όπως στο DashboardReader.energy)·
                // χωρίς το +1 η σημερινή μέρα (π.χ. το σημερινό Energy Score) έμενε έξω από το «Τι φτάνει».
                val b = (builder as ReadDataRequest.LocalDateBuilder<HealthDataPoint>)
                    .setLocalDateFilter(LocalDateFilter.of(from.toLocalDate(), to.toLocalDate().plusDays(1)))
                    .setOrdering(Ordering.DESC)
                    .setPageSize(PAGE_SIZE)
                if (!token.isNullOrEmpty()) b.setPageToken(token)
                b.build()
            }
            else -> null
        }
    }

    private suspend fun dailySteps(s: HealthDataStore, days: Int, today: LocalDate): JSONArray {
        val request = DataType.StepsType.TOTAL.requestBuilder
            .setLocalTimeFilterWithGroup(
                LocalTimeFilter.of(
                    today.minusDays((days - 1).toLong()).atStartOfDay(),
                    today.plusDays(1).atStartOfDay(),
                ),
                LocalTimeGroup.of(LocalTimeGroupUnit.DAILY, 1),
            )
            .setOrdering(Ordering.DESC)
            .build()
        val array = JSONArray()
        for (d in s.aggregateData(request).dataList) {
            array.put(
                JSONObject()
                    .put("date", localDate(d.startTime))
                    .put("value", d.value ?: JSONObject.NULL)
            )
        }
        return array
    }

    private suspend fun <T : Any> putToday(
        s: HealthDataStore,
        target: JSONObject,
        key: String,
        op: AggregateOperation<T, AggregateRequest.LocalTimeBuilder<T>>,
        day: LocalDate,
        until: LocalDateTime,
    ) {
        try {
            val request = op.requestBuilder
                .setLocalTimeFilter(LocalTimeFilter.of(day.atStartOfDay(), until))
                .build()
            val value = s.aggregateData(request).dataList.firstOrNull()?.value
            target.put(key, describe(value) ?: JSONObject.NULL)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            target.put(key, JSONObject.NULL)
        }
    }

    // ---------- Βοηθητικά ----------

    private suspend fun deviceName(s: HealthDataStore, id: String): String {
        if (id.isEmpty()) return ""
        deviceNames[id]?.let { return it }
        val name = try {
            val d = s.getDeviceManager().getDevice(id)
            deviceWatch[id] = d?.deviceType == com.samsung.android.sdk.health.data.device.DeviceGroup.WATCH
            listOfNotNull<String>(d?.name, d?.model).firstOrNull { it.isNotBlank() } ?: ""
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            ""
        }
        deviceNames[id] = name
        return name
    }

    private fun localText(i: Instant?): String =
        if (i == null) "" else LocalDateTime.ofInstant(i, ZoneId.systemDefault()).withNano(0).toString()

    private fun localDate(i: Instant?): String =
        if (i == null) "" else LocalDateTime.ofInstant(i, ZoneId.systemDefault()).toLocalDate().toString()

    @Suppress("UNCHECKED_CAST")
    private fun valueOf(p: HealthDataPoint, f: Field<*>): Any? =
        try {
            p.getValue(f as Field<Any?>)
        } catch (e: Throwable) {
            null
        }

    private fun describe(v: Any?): String? = when (v) {
        null -> null
        is Float -> if (v.isNaN()) null else String.format(java.util.Locale.US, "%.2f", v)
        is Double -> if (v.isNaN()) null else String.format(java.util.Locale.US, "%.2f", v)
        is Duration -> "${v.toMinutes()} min"
        is Instant -> LocalDateTime.ofInstant(v, ZoneId.systemDefault()).withNano(0).toString()
        is List<*> -> describeList(v)
        is Enum<*> -> v.name
        else -> v.toString()
    }

    private fun describeList(list: List<*>): String {
        if (list.isEmpty()) return "0 items"
        val first = list.first()
        if (first is SleepSession) {
            val minutesByStage = LinkedHashMap<String, Long>()
            for (item in list) {
                val session = item as? SleepSession ?: continue
                for (stage in session.stages ?: emptyList()) {
                    val name = stage.stage?.toString() ?: "?"
                    val minutes = Duration.between(stage.startTime, stage.endTime).toMinutes()
                    minutesByStage[name] = (minutesByStage[name] ?: 0L) + minutes
                }
            }
            val stages = minutesByStage.entries.joinToString(", ") { "${it.key} ${it.value} min" }
            return "${list.size} sessions" + if (stages.isNotEmpty()) "; $stages" else ""
        }
        return "${list.size} items"
    }

    private fun errorJson(e: Throwable): JSONObject {
        val o = JSONObject().put("ok", false)
        if (e is HealthDataException) {
            val code = e.errorCode ?: -1
            o.put("code", code)
                .put("message", e.errorMessage ?: e.message ?: "")
                .put("kind", kindOf(code))
            if (e is ResolvablePlatformException && e.hasResolution) {
                pendingResolution = e
                o.put("resolvable", true)
            }
        } else {
            // Τα σφάλματα του Samsung Health (άδειες, σύνδεση) είναι αναμενόμενα· αναφέρονται μόνο τα δικά μας.
            ErrorQueue.report(e, "samsung")
            o.put("code", -1)
                .put("message", e.toString())
                .put("kind", "other")
        }
        return o
    }

    private fun kindOf(code: Int): String = when (code) {
        ErrorCode.ERR_PLATFORM_NOT_INSTALLED -> "not_installed"
        ErrorCode.ERR_OLD_VERSION_PLATFORM -> "old_version"
        ErrorCode.ERR_PLATFORM_DISABLED -> "disabled"
        ErrorCode.ERR_PLATFORM_NOT_INITIALIZED -> "not_initialized"
        ErrorCode.ERR_NO_USER_PERMISSION -> "no_permission"
        ErrorCode.ERR_INVALID_CALLER,
        ErrorCode.ERR_ACCESS_CONTROL,
        ErrorCode.ERR_INVALID_PLATFORM_SIGNATURE -> "not_allowed"
        ErrorCode.ERR_CONNECTION_FAIL,
        ErrorCode.ERR_CONNECTION_TIMEOUT,
        ErrorCode.ERR_PLATFORM_DISCONNECTED -> "connection"
        else -> "other"
    }

    companion object {
        /**
         * Τύποι που διαβάζονται εγγραφή-εγγραφή: ΜΟΝΟ όσα διαβάζει το [DashboardReader] (έλεγχος 9/11, E3-06 / V-B-02:
         * ελαχιστοποίηση δεδομένων, GDPR άρθρο 5(1)(γ), και ο κανόνας του Play «όχι άδειες που δεν χρειάζονται»).
         * Πίεση, θερμοκρασία σώματος, γλυκόζη, νερό, διατροφή της Samsung, άπνοια και ακανόνιστος ρυθμός ΔΕΝ ζητούνται
         * πια (η ανάγνωσή τους έφυγε με την #85). Νέο είδος μπαίνει εδώ μόνο μαζί με τη λειτουργία που το δείχνει·
         * η δοκιμή `fix_accuracy_test.dart` ελέγχει ότι οι δύο λίστες συμφωνούν.
         */
        val readTypes: List<Pair<String, DataType>> = listOf(
            "sleep" to DataTypes.SLEEP,
            "heart_rate" to DataTypes.HEART_RATE,
            "body_composition" to DataTypes.BODY_COMPOSITION,
            "exercise" to DataTypes.EXERCISE,
            "energy_score" to DataTypes.ENERGY_SCORE,
            "blood_oxygen" to DataTypes.BLOOD_OXYGEN,
            "skin_temperature" to DataTypes.SKIN_TEMPERATURE,
            "floors_climbed" to DataTypes.FLOORS_CLIMBED,
        )

        /** Τύποι που δίνουν μόνο σύνολα (π.χ. βήματα ανά μέρα). */
        val aggregateTypes: List<Pair<String, DataType>> = listOf(
            "steps" to DataTypes.STEPS,
            "activity_summary" to DataTypes.ACTIVITY_SUMMARY,
        )

        val permissions: Set<Permission> =
            (readTypes + aggregateTypes).map { Permission.of(it.second, AccessType.READ) }.toSet()

        const val DASHBOARD_FILE = "dashboard.json"
        const val PREFS_FILE = "prefs.json"
        const val PAGE_SIZE = 1000
        const val MAX_PAGES = 20
    }
}
