package gr.ygeiaforma.wear

import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture

/**
 * Tile «Περπάτημα» (αίτημα χρήστη 14/11): ένα σύρσιμο από την πρόσοψη και ένα πάτημα, και ξεκινά περπάτημα, χωρίς να
 * ψάξεις την εφαρμογή στη λίστα. Ανοίγει την εφαρμογή με [EXTRA_START] = [START_WALK] ([WatchActivity.handle]).
 *
 * Σταθερό περιεχόμενο: τίποτα δεν τρέχει στο παρασκήνιο και δεν ζητά ανανέωση· το σύστημα το ζωγραφίζει μόνο όταν το
 * κοιτάς. Αν τρέχει ήδη άσκηση, το πάτημα απλώς ανοίγει την εφαρμογή.
 */
class WalkTileService : TileService() {
    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> =
        CallbackToFutureAdapter.getFuture { c ->
            c.set(
                TileBuilders.Tile.Builder()
                    .setResourcesVersion(RES_VERSION)
                    .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(layout()))
                    .build(),
            )
            "walkTile"
        }

    override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        CallbackToFutureAdapter.getFuture { c ->
            c.set(ResourceBuilders.Resources.Builder().setVersion(RES_VERSION).build())
            "walkTileResources"
        }

    private fun text(s: String, size: Float, color: Int, bold: Boolean = false): LayoutElementBuilders.Text =
        LayoutElementBuilders.Text.Builder()
            .setText(s)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(sp(size))
                    .setColor(argb(color))
                    .setWeight(if (bold) LayoutElementBuilders.FONT_WEIGHT_BOLD else LayoutElementBuilders.FONT_WEIGHT_NORMAL)
                    .build(),
            )
            .build()

    private fun layout(): LayoutElementBuilders.LayoutElement {
        val launch = ActionBuilders.LaunchAction.Builder()
            .setAndroidActivity(
                ActionBuilders.AndroidActivity.Builder()
                    .setPackageName(packageName)
                    .setClassName(WatchActivity::class.java.name)
                    .addKeyToExtraMapping(EXTRA_START, ActionBuilders.AndroidStringExtra.Builder().setValue(START_WALK).build())
                    .build(),
            )
            .build()
        val button = LayoutElementBuilders.Box.Builder()
            .setWidth(dp(156f))
            .setHeight(dp(60f))
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(ModifiersBuilders.Clickable.Builder().setId("walk").setOnClick(launch).build())
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(ORANGE))
                            .setCorner(ModifiersBuilders.Corner.Builder().setRadius(dp(30f)).build())
                            .build(),
                    )
                    .setSemantics(ModifiersBuilders.Semantics.Builder().setContentDescription("Ξεκίνα περπάτημα").build())
                    .build(),
            )
            .addContent(text("Περπάτημα", 19f, WHITE, bold = true))
            .build()
        val column = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(text("Υγεία & Φόρμα", 13f, GRAY))
            .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(10f)).build())
            .addContent(button)
            .build()
        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(column)
            .build()
    }

    companion object {
        const val EXTRA_START = "ygeia.start"
        const val START_WALK = "walk"
        private const val RES_VERSION = "1"
        private const val ORANGE = 0xFFC2410C.toInt()
        private const val WHITE = 0xFFFFFFFF.toInt()
        private const val GRAY = 0xFF9CA3AF.toInt()
    }
}
