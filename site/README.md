# Ιστότοπος ygeia-forma.netlify.app

Ο μικρός ιστότοπος της εφαρμογής και ο μεσάζων σύνδεσης με την Oura.

## Ανέβασμα

Το Netlify project `ygeia-forma` είναι συνδεδεμένο με αυτό το repository (base directory `site`). Κάθε push στο
`main` ανεβάζει μόνο του:
- τις στατικές σελίδες από το `site/public/`
- τη function `site/netlify/functions/oura-token.mjs` στη διεύθυνση `/api/oura/token`

Ρυθμίσεις στο `site/netlify.toml`.

## Σελίδες (`site/public/`)

- αρχική (`index.html`), απόρρητο (`privacy/`), όροι (`terms/`), `style.css`
- η επιστροφή από την Oura (`oura/callback/` και `oura/callback.js`, που περνά το query στο
  `ygeiaforma://oura-callback`)
- κεφαλίδες ασφαλείας στο `_headers`
- `.well-known/assetlinks.json` (App Link για το `https://ygeia-forma.netlify.app/oura/callback`): το
  `sha256_cert_fingerprints` πρέπει να είναι **ακριβώς** το αποτύπωμα του κλειδιού που υπογράφει το release APK. Το
  χτίσιμο του `main` το δείχνει («Αποτύπωμα κλειδιού») και προειδοποιεί αν δεν ταιριάζει.
- Δύο ίδια αντίγραφα του `assetlinks.json` (στη ρίζα και στο `.well-known`) με `_redirects`, γιατί το παλιό
  ανέβασμα με drag and drop παρέλειπε τους κρυφούς φακέλους. Πρέπει να μένουν ίδια (το ελέγχει το `test/site_test.dart`).

## Μεσάζων Oura (`/api/oura/token`)

Η Oura ζητά Client Secret στην ανταλλαγή κωδικού και στην ανανέωση. Το secret **δεν μπαίνει ποτέ** στην εφαρμογή ή
στον κώδικα: ζει μόνο ως μεταβλητή περιβάλλοντος του Netlify.

- `OURA_CLIENT_SECRET` (υποχρεωτική, Secret, scope Functions): το Client Secret από το developer.ouraring.com.
- `OURA_TOKEN_URL` (προαιρετική): πού προωθείται. Προεπιλογή `https://api.ouraring.com/oauth/token`. Επιτρέπεται και το
  `https://api.ouraring.com/v2/oauth/token`. Αλλάζει χωρίς νέα έκδοση της εφαρμογής, αλλά θέλει νέο deploy.

Τι κάνει ο μεσάζων:
- δέχεται μόνο POST για το δικό μας Client ID
- στην ανταλλαγή κωδικού απαιτεί PKCE (`code_verifier`) και μία από τις δύο δηλωμένες διευθύνσεις επιστροφής
- προσθέτει το secret και προωθεί το αίτημα στην Oura μία φορά
- επιστρέφει την απάντηση της Oura χωρίς cache

Δεν αποθηκεύει και δεν καταγράφει τίποτα, και δεν βλέπει δεδομένα υγείας.
