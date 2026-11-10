
// ---------------------------------------------------------------------------
// Υγεία & Φόρμα: προσθήκες στο android/app/build.gradle.kts.
// Το GitHub Actions φτιάχνει το βασικό αρχείο με «flutter create» και
// κολλάει αυτό το κομμάτι στο τέλος του. Δεν το αλλάζουμε με το χέρι εκεί.
// ---------------------------------------------------------------------------

apply(plugin = "kotlin-parcelize")

android {
    // Ρητά (έλεγχος 9/11, E3-23): μια νέα Flutter δεν αλλάζει σιωπηλά το επίπεδο Android της εφαρμογής. Το 36
    // (Android 16) είναι ό,τι είχε ήδη η #89 από το πρότυπο της Flutter 3.47.9· το ίδιο έχει και το ρολόι.
    // Ό,τι αλλάζει με το 36 ισχύει ήδη (edge-to-edge, predictive back, ειδοποιήσεις με άδεια). Αλλαγή του αριθμού
    // = νέος έλεγχος των αλλαγών συμπεριφοράς του Android (developer.android.com/about/versions/*/behavior-changes-*).
    compileSdk = 36
    defaultConfig {
        // Το Samsung Health Data SDK θέλει Android 10 (API 29) και πάνω.
        minSdk = 29
        targetSdk = 36
    }
}

// Σταθερό κλειδί υπογραφής, ώστε κάθε νέα έκδοση να μπαίνει πάνω στην παλιά χωρίς απεγκατάσταση. Το κλειδί δεν
// βρίσκεται ποτέ μέσα στο repository. Στο CI ΔΕΝ μπαίνει στο χτίσιμο: την υπογραφή την κάνει μόνο το job «sign»
// με apksigner (tools/ci/sign_apks.sh, έλεγχος 9/11). Αυτό το μπλοκ μένει για χτίσιμο με το κλειδί σε υπολογιστή.
val ygeiaKeystorePath: String? = System.getenv("YGEIA_KEYSTORE")
val ygeiaKeystorePassword: String? = System.getenv("YGEIA_KEYSTORE_PASSWORD")
if (ygeiaKeystorePath != null && ygeiaKeystorePassword != null && file(ygeiaKeystorePath).exists()) {
    android {
        signingConfigs {
            create("ygeia") {
                storeFile = file(ygeiaKeystorePath)
                storePassword = ygeiaKeystorePassword
                keyAlias = "ygeia"
                keyPassword = ygeiaKeystorePassword
            }
        }
        buildTypes {
            getByName("release") {
                signingConfig = signingConfigs.getByName("ygeia")
            }
        }
    }
}

dependencies {
    implementation(files("libs/samsung-health-data-api-1.1.0.aar"))
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Ανανέωση στο παρασκήνιο κάθε 3 ώρες (RefreshWorker), με τους κανόνες μπαταρίας του Android.
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    // Σκανάρισμα barcode από το Google Play services (χωρίς άδεια κάμερας, χωρίς δική μας κάμερα).
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    // Ρολόι (8/11): σύνδεση με την εφαρμογή Wear OS (πρόγραμμα, παλμοί, ✓) και άνοιγμά της από το κινητό.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("androidx.wear:wear-remote-interactions:1.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
    // Μόνο για τους ελέγχους Kotlin σε απλό JVM (android/app/src/test): δεν μπαίνει ποτέ στην εφαρμογή.
    testImplementation("junit:junit:4.13.2")
}
