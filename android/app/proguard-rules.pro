# Samsung Health Data SDK: κρατάμε τις δημόσιες κλάσεις του αυτούσιες.
-keep class com.samsung.android.sdk.health.data.** { *; }
-dontwarn com.samsung.android.sdk.health.data.**

# Το SDK αναφέρει κλάσεις data binding που δεν χρησιμοποιεί στην πράξη.
-dontwarn androidx.databinding.**

# Gson (το χρησιμοποιεί εσωτερικά το SDK).
-keepattributes Signature, *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }

# Η γέφυρά μας προς τη Flutter.
-keep class gr.ygeiaforma.** { *; }

# Google code scanner (ML Kit μέσω Google Play services): βρίσκει τα κομμάτια του με reflection.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_code_scanner.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.firebase.components.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# WorkManager (ανανέωση στο παρασκήνιο, RefreshWorker): η βάση του (Room) και οι βοηθητικές του κλάσεις
# δημιουργούνται με reflection. Χωρίς αυτούς τους κανόνες η #62 έκλεινε στο άνοιγμα
# (NoSuchMethodException: WorkDatabase_Impl.<init>).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
