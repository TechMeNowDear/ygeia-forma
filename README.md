# Υγεία & Φόρμα

Προσωπική εφαρμογή υγείας, διατροφής και άσκησης (Flutter, Android).

- **Προδιαγραφές:** το έγγραφο «Υγεία & Φόρμα — Προδιαγραφές εφαρμογής» στο Claude.
- **Τελευταία έκδοση:** σελίδα *Releases* › «latest» › αρχείο `.apk`.

## Πώς χτίζεται

Κάθε αλλαγή στο `main` τρέχει το `.github/workflows/android.yml`:

1. Το `flutter create` συμπληρώνει τα αρχεία Android που δεν κρατάμε στο repository.
2. Στο `android/app/build.gradle.kts` προστίθεται το `android/ygeia/app-extra.gradle.kts`
   (Samsung Health Data SDK, minSdk 29, υπογραφή).
3. Βγαίνει APK (arm64) και ανεβαίνει στο Releases ως «latest».

## Φάκελοι

| Φάκελος | Τι έχει |
| --- | --- |
| `lib/` | Η εφαρμογή (Flutter) |
| `android/app/src/main/kotlin/` | Η γέφυρα προς το Samsung Health Data SDK |
| `android/app/libs/` | Το Samsung Health Data SDK 1.1.0 |
| `android/ygeia/` | Οι προσθήκες μας στο Gradle |

## Ασφάλεια

Κανένα κλειδί ή κωδικός μέσα στο repository. Το κλειδί υπογραφής έρχεται από τα
Secrets του GitHub (ή από την προσωρινή μνήμη του GitHub Actions).
