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
