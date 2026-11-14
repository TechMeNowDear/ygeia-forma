// Εφαρμογή ρολογιού (Wear OS) της «Υγεία & Φόρμα». Ίδιο applicationId και ίδιο κλειδί υπογραφής με το κινητό
// (το θέλει η σύνδεση κινητού–ρολογιού και το Play Console). Χτίζεται χωριστά: ./gradlew :wear:assembleRelease
// (το settings.gradle.kts του «flutter create» παίρνει include(":wear") μόνο στο βήμα του ρολογιού στο CI).
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val ygeiaBuild = (System.getenv("YGEIA_BUILD") ?: "1").toInt()

android {
    namespace = "gr.ygeiaforma.wear"
    // 37 = Android 17 (Wear OS 7, το Galaxy Watch Ultra 2 του χρήστη· σημείωση fix-sdk37).
    compileSdk = 37

    defaultConfig {
        applicationId = "gr.ygeiaforma.ygeia_forma"
        // Wear OS 3 και πάνω (Health Services).
        minSdk = 30
        targetSdk = 37
        // Χωριστή αρίθμηση από το κινητό (το Play Console θέλει μοναδικό αριθμό σε κάθε αρχείο).
        versionCode = 1_000_000 + ygeiaBuild
        versionName = "0.1.$ygeiaBuild"
    }

    val keystore: String? = System.getenv("YGEIA_KEYSTORE")
    val password: String? = System.getenv("YGEIA_KEYSTORE_PASSWORD")
    if (keystore != null && password != null && file(keystore).exists()) {
        signingConfigs {
            create("ygeia") {
                storeFile = file(keystore)
                storePassword = password
                keyAlias = "ygeia"
                keyPassword = password
            }
        }
        buildTypes.getByName("release").signingConfig = signingConfigs.getByName("ygeia")
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.isIncludeAndroidResources = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    // Παλμοί, απόσταση, βήματα όσο τρέχει άσκηση (μόνο τότε).
    implementation("androidx.health:health-services-client:1.1.0")
    // Σύνδεση με το κινητό.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    // Ένδειξη «άσκηση σε εξέλιξη» στην πρόσοψη του ρολογιού.
    implementation("androidx.wear:wear-ongoing:1.0.0")
    // Tile «Περπάτημα» (14/11): επίσημη βιβλιοθήκη των tiles· δεν τρέχει τίποτα στο παρασκήνιο.
    implementation("androidx.wear.tiles:tiles:1.4.1")
    implementation("androidx.wear.protolayout:protolayout:1.2.1")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.2.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
    // Μόνο για τους ελέγχους σε απλό JVM: το org.json του Android είναι «άδειο» εκεί.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    // Στιγμιότυπα των οθονών του ρολογιού σε JVM (WatchShotsTest), χωρίς ρολόι ή emulator.
    testImplementation("org.robolectric:robolectric:4.14.1")
}
