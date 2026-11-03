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

## Αναφορά σφαλμάτων (Sentry)

- Project `ygeia-forma` στο Sentry (org `techme-7f`, περιοχή EU), χωρίς βιβλιοθήκη: απλό HTTP στο envelope endpoint.
- `lib/error_report.dart`: πιάνει σφάλματα της Flutter (`FlutterError.onError`) και ό,τι ξεφεύγει
  (`PlatformDispatcher.onError`). `ErrorQueue.kt`: κρασαρίσματα Kotlin και σφάλματα στις γέφυρες
  (όχι τα αναμενόμενα του Samsung Health ή του δικτύου).
- Στέλνει **μόνο** σφάλμα (πρώτη γραμμή, ως 300 χαρακτήρες), στοίβα, οθόνη (π.χ. «Διατροφή › Ημερολόγιο › Ποσότητα»),
  έκδοση (`ygeia-forma@0.1.N`), μοντέλο συσκευής, έκδοση Android. Ποτέ δεδομένα υγείας ή φαγητού.
- Μπαταρία: τίποτα συνεχές. Αποστολή μόνο όταν γίνει σφάλμα, 5 δευτερόλεπτα μετά το άνοιγμα και όταν επιστρέφω στην εφαρμογή.
- Χωρίς ίντερνετ: ουρά αρχείων στη συσκευή (`files/errq`, το πολύ 20)· το ίδιο σφάλμα μία φορά το λεπτό· το πολύ 30 αποστολές τη μέρα.
- Νέα οθόνη: δώσε όνομα με `settings: const RouteSettings(name: '…')` (ή `routeSettings:` στα φύλλα), για να φαίνεται στο Sentry.
- Δοκιμή: commit με `[sentry-test]` στο μήνυμα (ή χειροκίνητο χτίσιμο με «Στείλε και ένα δοκιμαστικό σφάλμα»)
  στέλνει πραγματικό σφάλμα με τον ίδιο κώδικα (`test/sentry_live_test.dart`).
- Το DSN μέσα στον κώδικα **δεν** είναι μυστικό: επιτρέπει μόνο αποστολή σφαλμάτων, όχι ανάγνωση.

## Oura Ring 5

- Πηγές: ένας πίνακας στο `lib/sources.dart` (μία πηγή ανά μέτρηση, ποτέ ανάμειξη). Από τη μέρα της σύνδεσης ο ύπνος,
  οι παλμοί/HRV/αναπνοές ύπνου, η θερμοκρασία και η ετοιμότητα έρχονται μόνο από το Oura· οξυγόνο, βήματα, παλμοί μέρας
  από το ρολόι· βάρος από την InBody. Οι τιμές του Oura αποθηκεύονται με πρόθεμα `o.` στο ιστορικό.
- Σύνδεση: OAuth2 με PKCE, χωρίς Client Secret (`lib/oura/`). Ρυθμίσεις σε ένα σημείο: `lib/oura/config.dart`
  (`ouraClientId`, `ouraTokenProxy`, `ouraOAuth`). Scope μόνο `daily`. Tokens κρυπτογραφημένα (AES-GCM, Android Keystore) στο `noBackupFilesDir`.
- Τη μέρα του δαχτυλιδιού: εγγραφή εφαρμογής στο https://cloud.ouraring.com/oauth/applications με Redirect URI
  `https://ygeia-forma.netlify.app/oura/callback` (App Link· εναλλακτική `ygeiaforma://oura-callback`, αλλαγή μίας
  γραμμής στο `ouraRedirectUri`), scope μόνο `daily`, και το Client ID στο `ouraClientId`.
- Το manifest (από το `flutter create`) συμπληρώνεται από το `tools/android/patch_manifest.py`: μικρή οθόνη
  `OuraCallbackActivity` για την επιστροφή και `<queries>` για browser. Η MainActivity δεν αλλάζει.
- Το σχέδιο πηγών έχει δικό του αρχείο (`sources.json`, `lib/plan_file.dart`), ανεξάρτητο από τις ρυθμίσεις.
  Κάθε αλλαγή πηγής ισχύει από το βράδυ της μέρας που γίνεται.
- Έλεγχος με το sandbox της Oura: job «oura-sandbox» στο `check.yml` (`test/oura_sandbox_live_test.dart`).
