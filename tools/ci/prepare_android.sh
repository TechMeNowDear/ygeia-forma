#!/usr/bin/env bash
# Συμπληρώνει τα αρχεία Android που δεν κρατάμε στο repository (ΕΝΑ σημείο για android.yml, check.yml, perf.yml
# και για το παλιό δέντρο της δοκιμής αναβάθμισης, ώστε να χτίζονται όλα με τον ίδιο τρόπο).
#
# Χρήση: bash tools/ci/prepare_android.sh [φάκελος έργου]   (προεπιλογή: ο τρέχων)
# Χρησιμοποιεί τα αρχεία ΤΟΥ φακέλου (android/ygeia/app-extra.gradle.kts, tools/android/patch_manifest.py), άρα ένα
# παλιό δέντρο χτίζεται με τους δικούς του κανόνες.
#
# Υπογραφή: εδώ ΔΕΝ υπάρχει κλειδί. Το APK βγαίνει με το προσωρινό κλειδί debug του runner και υπογράφεται με το
# σταθερό κλειδί ΜΟΝΟ στο job «sign» του android.yml (tools/ci/sign_apks.sh), έλεγχος 9/11 (V-A-20).
set -euo pipefail
root="${1:-.}"
cd "$root"

flutter create --org gr.ygeiaforma --project-name ygeia_forma --platforms android .
test -f android/app/build.gradle.kts || { echo "Λείπει το android/app/build.gradle.kts"; exit 1; }

# Μία φορά μόνο (αν το script ξανατρέξει στον ίδιο φάκελο, δεν μπαίνει δεύτερη φορά).
if ! grep -q 'Υγεία & Φόρμα: προσθήκες' android/app/build.gradle.kts; then
  cat android/ygeia/app-extra.gradle.kts >> android/app/build.gradle.kts
fi

m=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="ygeia_forma"/android:label="Υγεία \&amp; Φόρμα"/' "$m"
# Διαδίκτυο: για το Open Food Facts (barcode), τη σύνδεση Oura και την αναφορά σφαλμάτων (Sentry).
grep -q 'android.permission.INTERNET' "$m" || \
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$m"
# Σύνδεση Oura, widgets, κανόνες αντιγράφου (η MainActivity δεν αλλάζει).
python3 tools/android/patch_manifest.py "$m"
grep -n 'android:label\|INTERNET' "$m" | head -5
