package gr.ygeiaforma.ygeia_forma

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Σύνδεση Oura: η επιστροφή από τη σελίδα της Oura (ygeiaforma://oura-callback?code=…&state=…) έρχεται εδώ.
 * Μικρή, διάφανη οθόνη που δεν μένει: δίνει τη διεύθυνση στην εφαρμογή (OuraBridge) και φέρνει μπροστά την
 * εφαρμογή όπως το εικονίδιο της αρχικής (ίδια εργασία, τίποτα δεν κλείνει), και τελειώνει.
 * Έτσι η MainActivity μένει ακριβώς όπως ήταν (launchMode, επιλογέας αρχείων, άδειες Samsung).
 */
class OuraCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(i: Intent?) {
        try {
            if (OuraBridge.isCallback(i)) i?.dataString?.let { OuraBridge.receive(it) }
            packageManager.getLaunchIntentForPackage(packageName)?.let {
                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(it)
            }
        } catch (e: Throwable) {
            ErrorQueue.report(e, "oura-callback")
        } finally {
            finish()
        }
    }
}
