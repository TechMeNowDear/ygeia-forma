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
 * δείχνει το κείμενο που ετοίμασε η εφαρμογή και τελειώνει. Μετά από επανεκκίνηση του κινητού το Android σβήνει τα
 * ξυπνητήρια· ξαναμπαίνει την επόμενη φορά που ανοίγει η εφαρμογή.
 */
object FoodReminder {
    const val CHANNEL = "food_reminder"
    private const val ID = 7320
    private const val REQ = 7321
    private const val EXTRA_TITLE = "title"
    private const val EXTRA_TEXT = "text"

    private fun pending(ctx: Context, title: String?, text: String?, create: Boolean): PendingIntent? {
        val i = Intent(ctx, FoodReminderReceiver::class.java)
        if (title != null) i.putExtra(EXTRA_TITLE, title)
        if (text != null) i.putExtra(EXTRA_TEXT, text)
        val flags = PendingIntent.FLAG_IMMUTABLE or
            (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE)
        return PendingIntent.getBroadcast(ctx, REQ, i, flags)
    }

    /** Βάζει (ή αλλάζει) το ξυπνητήρι στις [atMillis]. */
    fun set(ctx: Context, atMillis: Long, title: String, text: String): Boolean {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return false
        val pi = pending(ctx, title, text, true) ?: return false
        am.setWindow(AlarmManager.RTC_WAKEUP, atMillis, 10 * 60 * 1000L, pi)
        return true
    }

    fun cancel(ctx: Context) {
        val pi = pending(ctx, null, null, false) ?: return
        ctx.getSystemService(AlarmManager::class.java)?.cancel(pi)
        pi.cancel()
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

/** Δείχνει την υπενθύμιση και τελειώνει (λίγα ms). */
class FoodReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val (title, text) = FoodReminder.extras(intent) ?: return
        FoodReminder.show(context.applicationContext, title, text)
    }
}
