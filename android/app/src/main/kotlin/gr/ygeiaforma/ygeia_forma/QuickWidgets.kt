package gr.ygeiaforma.ygeia_forma

import android.content.Context
import android.widget.RemoteViews
import java.time.LocalDate

/**
 * Δύο μικρά widgets αρχικής οθόνης (13/11): «Προπόνηση σήμερα» και «Γρήγορο φαγητό».
 *
 * Απλές διατάξεις με γράμματα (όχι εικόνες): καμία μνήμη για bitmaps (WidgetBudget), ημέρα/νύχτα από τα χρώματα των
 * πόρων (values / values-night), χωρίς οθόνη ρύθμισης. Καμία περιοδική ανανέωση: ζωγραφίζονται όταν η εφαρμογή γράφει
 * το στιγμιότυπο, στα μεσάνυχτα (το ίδιο ξυπνητήρι με τα άλλα widgets) και όταν τα ζητά η αρχική οθόνη.
 */
object QuickWidgets {
    const val WORKOUT = "workout"
    const val QUICK_FOOD = "quickfood"

    fun handles(kind: String) = kind == WORKOUT || kind == QUICK_FOOD

    fun views(ctx: Context, id: Int, kind: String): RemoteViews =
        if (kind == WORKOUT) {
            RemoteViews(ctx.packageName, R.layout.quick_workout_widget).apply {
                val (title, sub) = QuickWidgetRules.workoutLines(HomeWidgets.snapshot(ctx)?.optJSONObject("workout"), LocalDate.now())
                setTextViewText(R.id.qw_title, title)
                setTextViewText(R.id.qw_sub, sub)
                setContentDescription(R.id.qw_root, listOf("Προπόνηση σήμερα", title, sub).filter { it.isNotEmpty() }.joinToString(". "))
                // Ανοίγει την Άσκηση › Προπόνηση (εκεί είναι το «Ξεκίνα»): ένα πάτημα στην αρχική οθόνη δεν ξεκινά προπόνηση κατά λάθος.
                setOnClickPendingIntent(R.id.qw_root, HomeWidgets.open(ctx, id, 0, "w:workout:section:"))
            }
        } else {
            RemoteViews(ctx.packageName, R.layout.quick_food_widget).apply {
                setOnClickPendingIntent(R.id.qf_add, HomeWidgets.open(ctx, id, 0, "w:food:add:"))
                setOnClickPendingIntent(R.id.qf_scan, HomeWidgets.open(ctx, id, 1, "w:food:scan:"))
            }
        }
}
