package gr.ygeiaforma.ygeia_forma

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Βραδινή υπενθύμιση φαγητού (16/11): ΜΙΑ ειδοποίηση τη μέρα, μόνο αν η μέρα έχει πολύ λίγες θερμίδες.
 *
 * Τίποτα δεν τρέχει στο παρασκήνιο: η εφαρμογή (Flutter) αποφασίζει, κάθε φορά που αλλάζει το ημερολόγιο, ΑΝ και ΠΟΤΕ
 * χρειάζεται υπενθύμιση, και βάζει ένα ξυπνητήρι του Android (όχι ακριβές: [AlarmManager.setWindow], παράθυρο 10
 * λεπτών, χωρίς ειδική άδεια). Αν η μέρα συμπληρωθεί, το ξυπνητήρι σβήνει. Όταν χτυπήσει, ο [FoodReminderReceiver]
 * δείχνει το κείμενο που ετοίμασε η εφαρμογή και τελειώνει.
 *
 * Επανεκκίνηση (αποφάσεις 20/11): το Android σβήνει τα ξυπνητήρια όταν κλείνει το κινητό. Γι' αυτό η ώρα και το κείμενο
 * κρατιούνται σε ένα μικρό αρχείο ρυθμίσεων, και ο [FoodReminderBootReceiver] τα ξαναβάζει μία φορά μετά την εκκίνηση
 * (ή μετά από ενημέρωση της εφαρμογής). Τίποτα δεν τρέχει συνεχώς· αν η ώρα πέρασε όσο ήταν κλειστό, δεν χτυπά αργά.
 */
object FoodReminder {
    const val CHANNEL = "food_reminder"
    private const val ID = 7320
    private const val REQ = 7321
    private const val EXTRA_TITLE = "title"
    private const val EXTRA_TEXT = "text"
    internal const val EXTRA_AT = "at"
    internal const val EXTRA_NEXT = "next"
    private const val PREFS = "food_reminder"
    private const val P_AT = "at"
    private const val P_TITLE = "title"
    private const val P_TEXT = "text"
    private const val P_NEXT = "next"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun pending(
        ctx: Context, title: String?, text: String?, create: Boolean, at: Long = 0L, next: String? = null,
    ): PendingIntent? {
        val i = Intent(ctx, FoodReminderReceiver::class.java)
        if (title != null) i.putExtra(EXTRA_TITLE, title)
        if (text != null) i.putExtra(EXTRA_TEXT, text)
        // K6C-02: η ώρα του ξυπνητηριού και το κείμενο της επόμενης μέρας, για να ξαναμπεί μόνο του όταν χτυπήσει.
        if (at > 0L) i.putExtra(EXTRA_AT, at)
        if (next != null) i.putExtra(EXTRA_NEXT, next)
        val flags = PendingIntent.FLAG_IMMUTABLE or
            (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE)
        return PendingIntent.getBroadcast(ctx, REQ, i, flags)
    }

    /**
     * Βάζει (ή αλλάζει) το ξυπνητήρι στις [atMillis]. [next]: το κείμενο της υπενθύμισης της ΕΠΟΜΕΝΗΣ μέρας, αν η
     * εφαρμογή δεν ανοίξει ως τότε (K6C-02, [FoodReminderReceiver]).
     */
    fun set(ctx: Context, atMillis: Long, title: String, text: String, next: String? = null): Boolean {
        if (!arm(ctx, atMillis, title, text, next)) return false
        prefs(ctx).edit().putLong(P_AT, atMillis).putString(P_TITLE, title).putString(P_TEXT, text)
            .apply { if (next != null) putString(P_NEXT, next) else remove(P_NEXT) }
            .apply()
        return true
    }

    private fun arm(ctx: Context, atMillis: Long, title: String, text: String, next: String? = null): Boolean {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return false
        val pi = pending(ctx, title, text, true, atMillis, next) ?: return false
        am.setWindow(AlarmManager.RTC_WAKEUP, atMillis, 10 * 60 * 1000L, pi)
        return true
    }

    fun cancel(ctx: Context) {
        forget(ctx)
        val pi = pending(ctx, null, null, false) ?: return
        ctx.getSystemService(AlarmManager::class.java)?.cancel(pi)
        pi.cancel()
    }

    /** Η υπενθύμιση χτύπησε ή σβήστηκε: τίποτα για ξανάβαλμα μετά από επανεκκίνηση. */
    internal fun forget(ctx: Context) {
        prefs(ctx).edit().clear().apply()
    }

    /** Μετά την εκκίνηση: ξαναβάζει την υπενθύμιση, μόνο αν η ώρα της δεν πέρασε ([FoodReminderBootReceiver]). */
    internal fun restore(ctx: Context, now: Long = System.currentTimeMillis()) {
        val p = prefs(ctx)
        val at = p.getLong(P_AT, 0L)
        val title = p.getString(P_TITLE, null)
        val text = p.getString(P_TEXT, null)
        if (!FoodReminderRules.restoreAt(at, now) || title == null || text == null) {
            forget(ctx)
            return
        }
        arm(ctx, at, title, text, p.getString(P_NEXT, null))
    }

    fun canNotify(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    internal fun show(ctx: Context, title: String, text: String) {
        if (!canNotify(ctx)) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Υπενθύμιση φαγητού", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Μία το βράδυ, μόνο όταν η μέρα έχει πολύ λίγο φαγητό γραμμένο."
                },
            )
        }
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val tap = open?.let { PendingIntent.getActivity(ctx, REQ, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .apply { if (tap != null) setContentIntent(tap) }
            .build()
        nm.notify(ID, n)
    }

    internal fun extras(i: Intent): Pair<String, String>? {
        val t = i.getStringExtra(EXTRA_TITLE) ?: return null
        val x = i.getStringExtra(EXTRA_TEXT) ?: return null
        return t to x
    }
}

/** Κανόνες χωρίς Android (δοκιμές JVM). */
object FoodReminderRules {
    /** Ξαναμπαίνει μόνο ώρα που δεν πέρασε (και όχι πάνω από 2 μέρες μπροστά: παλιό ή χαλασμένο αρχείο). */
    fun restoreAt(at: Long, now: Long): Boolean = at > now && at - now <= 2L * 24 * 60 * 60 * 1000

    /** Μόνο τα μηνύματα του συστήματος για εκκίνηση και ενημέρωση της εφαρμογής. */
    val actions = setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)

    /**
     * Έλεγχος 20/11 (K6C-02): η ίδια ώρα ΤΟΙΧΟΥ την επόμενη μέρα μετά το [at] που είναι μετά το [now] (σε αλλαγή ώρας
     * 23 ή 25 ώρες αργότερα, όχι 24). 0 αν το [at] δεν είναι ώρα.
     */
    fun nextDay(at: Long, now: Long, zone: java.time.ZoneId): Long {
        if (at <= 0L) return 0L
        var t = java.time.Instant.ofEpochMilli(at).atZone(zone)
        // Το πολύ λίγες επαναλήψεις: το ξυπνητήρι χτυπά μέσα σε 10 λεπτά από την ώρα του.
        repeat(400) {
            t = t.plusDays(1)
            val ms = t.toInstant().toEpochMilli()
            if (ms > now) return ms
        }
        return 0L
    }
}

/**
 * Δείχνει την υπενθύμιση και τελειώνει (λίγα ms).
 *
 * Έλεγχος 20/11 (K6C-02): και βάζει την υπενθύμιση της επόμενης μέρας, ίδια ώρα. Πριν, μετά το πρώτο χτύπημα δεν υπήρχε
 * επόμενο ώσπου να ξανανοίξει η εφαρμογή: ακριβώς τις μέρες που την ξεχνάς δεν ερχόταν καμία υπενθύμιση. Αν η εφαρμογή
 * ανοίξει στο μεταξύ, η Flutter ξαναϋπολογίζει ώρα και κείμενο (ή τη σβήνει) όπως πάντα.
 */
class FoodReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val (title, text) = FoodReminder.extras(intent) ?: return
        val app = context.applicationContext
        FoodReminder.forget(app)
        FoodReminder.show(app, title, text)
        val next = FoodReminderRules.nextDay(
            intent.getLongExtra(FoodReminder.EXTRA_AT, 0L), System.currentTimeMillis(), java.time.ZoneId.systemDefault(),
        )
        val nextText = intent.getStringExtra(FoodReminder.EXTRA_NEXT)
        if (next > 0L && nextText != null) FoodReminder.set(app, next, title, nextText, nextText)
    }
}

/** Μετά από επανεκκίνηση ή ενημέρωση: ξαναβάζει την υπενθύμιση (λίγα ms, μία φορά). */
class FoodReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in FoodReminderRules.actions) return
        FoodReminder.restore(context.applicationContext)
    }
}
