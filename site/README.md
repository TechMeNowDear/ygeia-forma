# Ιστότοπος ygeia-forma.netlify.app

Ο μικρός στατικός ιστότοπος της εφαρμογής. Βρίσκεται εδώ **μόνο για ιστορικό αλλαγών**: δεν υπάρχει workflow
που να τον ανεβάζει.

- **Ανέβασμα:** με το χέρι, σέρνοντας τον φάκελο `site/` (drag and drop) στο Netlify project `ygeia-forma`
  (Deploys › «Drag and drop your site output folder here»). Το `README.md` δεν πειράζει αν ανέβει.
- **Σελίδες:** αρχική (`index.html`), απόρρητο (`privacy/`), όροι (`terms/`), η επιστροφή από την Oura
  (`oura/callback/` και `oura/callback.js`, που περνά το query στο `ygeiaforma://oura-callback`), `style.css`,
  και οι κεφαλίδες ασφαλείας στο `_headers`.
- **`.well-known/assetlinks.json`** (App Link για το `https://ygeia-forma.netlify.app/oura/callback`): το
  `sha256_cert_fingerprints` πρέπει να είναι **ακριβώς** το αποτύπωμα του κλειδιού που υπογράφει το release APK.
  Το δείχνει το χτίσιμο του `main` στο GitHub Actions, στην ειδοποίηση «Αποτύπωμα κλειδιού» (SHA-256), και
  προειδοποιεί αν δεν ταιριάζει με αυτό το αρχείο. Αν αλλάξει το κλειδί, ενημερώνεται εδώ και ξανανεβαίνει.
- Μετά από κάθε ανέβασμα: άνοιξε το https://ygeia-forma.netlify.app/.well-known/assetlinks.json (πρέπει να φαίνεται
  JSON) και το https://ygeia-forma.netlify.app/oura/callback?code=TEST&state=TEST (το `?code=…&state=…` πρέπει να
  μείνει, και η σελίδα να προσπαθήσει να ανοίξει την εφαρμογή).
