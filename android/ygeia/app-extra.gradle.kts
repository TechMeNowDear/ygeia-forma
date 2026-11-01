
// ---------------------------------------------------------------------------
// Υγεία & Φόρμα: προσθήκες στο android/app/build.gradle.kts.
// Το GitHub Actions φτιάχνει το βασικό αρχείο με «flutter create» και
// κολλάει αυτό το κομμάτι στο τέλος του. Δεν το αλλάζουμε με το χέρι εκεί.
// ---------------------------------------------------------------------------

apply(plugin = "kotlin-parcelize")

android {
    defaultConfig {
        // Το Samsung Health Data SDK θέλει Android 10 (API 29) και πάνω.
        minSdk = 29
    }
}

// Σταθερό κλειδί υπογραφής, ώστε κάθε νέα έκδοση να μπαίνει πάνω στην παλιά
// χωρίς απεγκατάσταση. Το κλειδί δεν βρίσκεται ποτέ μέσα στο repository:
// το φέρνει το GitHub Actions (από Secrets ή από την προσωρινή μνήμη του).
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
}
