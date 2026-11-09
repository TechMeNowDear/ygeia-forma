#!/usr/bin/env python3
"""Η πολιτική απορρήτου (site/public/privacy/index.html) λέει την αλήθεια για ό,τι κάνει ο κώδικας (έλεγχος 9/11, V-A-23).

Η πολιτική έλεγε «μόνο την άδεια daily» ενώ η εφαρμογή ζητούσε «daily spo2». Αυτός ο έλεγχος διαβάζει τον κώδικα και
αποτυγχάνει αν η πολιτική ΔΕΝ αναφέρει κάτι που η εφαρμογή κάνει:
- κάθε άδεια (scope) της Oura που ζητείται (lib/oura/config.dart),
- κάθε είδος δεδομένων της Samsung Health που ζητείται (SamsungHealthBridge.kt: readTypes + aggregateTypes),
- τον μεσάζοντα Oura στο Netlify και ότι τρέχει στις ΗΠΑ,
- το Sentry και την περιοχή του (από τη διεύθυνση στο lib/error_report.dart),
- τον σαρωτή barcode της Google (ML Kit) και το Open Food Facts,
- το GPS του ρολογιού (αν το ζητά το manifest του ρολογιού),
- το αντίγραφο της Google με κρυπτογράφηση από άκρη σε άκρη (κανόνες αντιγράφου).
Όταν προστεθεί νέο είδος δεδομένων ή νέα υπηρεσία, ο έλεγχος σταματά το χτίσιμο ώσπου να γραφτεί στην πολιτική.
Χρήση: python3 -I tools/ci/check_privacy.py   (από τη ρίζα του repository)
"""
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
PAGE = f'{ROOT}/site/public/privacy/index.html'


def read(p):
    with open(f'{ROOT}/{p}', encoding='utf-8') as f:
        return f.read()


page = read('site/public/privacy/index.html')
greek = page.split('lang="en"')[0]
english = page[len(greek):]
errors = []


def need(cond, msg):
    if not cond:
        errors.append(msg)


# --- Oura: οι άδειες που ζητούνται ---
cfg = read('lib/oura/config.dart')
scopes = re.search(r"const ouraScopes = '([^']*)';", cfg).group(1).strip()
if not scopes:
    name = re.search(r'const ouraOAuth = OuraOAuthEndpoints\.(\w+);', cfg).group(1)
    block = re.search(rf'static const {name} = OuraOAuthEndpoints\._\((.*?)\);', cfg, re.S).group(1)
    scopes = re.findall(r"'([^']*)'", block)[3]
for sc in scopes.split():
    need(f'«{sc}»' in greek, f'Oura: η εφαρμογή ζητά την άδεια «{sc}», αλλά η πολιτική (ελληνικά) δεν την αναφέρει')
    need(f'"{sc}"' in english, f'Oura: η άδεια "{sc}" λείπει από το αγγλικό κείμενο')

# --- Samsung Health: κάθε είδος που ζητείται ---
SAMSUNG = {
    'SLEEP': 'ύπνο', 'HEART_RATE': 'παλμούς', 'BODY_COMPOSITION': 'σύσταση σώματος', 'EXERCISE': 'άσκηση',
    'ENERGY_SCORE': 'energy score', 'BLOOD_OXYGEN': 'οξυγόνο αίματος', 'SKIN_TEMPERATURE': 'θερμοκρασία δέρματος',
    'BLOOD_PRESSURE': 'αρτηριακή πίεση', 'BODY_TEMPERATURE': 'θερμοκρασία σώματος', 'BLOOD_GLUCOSE': 'γλυκόζη',
    'WATER_INTAKE': 'νερό', 'NUTRITION': 'διατροφή της Samsung Health', 'FLOORS_CLIMBED': 'ορόφους',
    'SLEEP_APNEA': 'άπνοια', 'IRREGULAR_HEART_RHYTHM_NOTIFICATION': 'ακανόνιστου καρδιακού ρυθμού',
    'STEPS': 'βήματα', 'ACTIVITY_SUMMARY': 'σύνοψη δραστηριότητας',
}
bridge = read('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/SamsungHealthBridge.kt')
lists = re.findall(r'val (?:readTypes|aggregateTypes)[^=]*= listOf\((.*?)\n\s*\)', bridge, re.S)
need(lists, 'Samsung: δεν βρέθηκαν τα readTypes/aggregateTypes στο SamsungHealthBridge.kt (άλλαξε ο κώδικας;)')
for t in sorted({t for block in lists for t in re.findall(r'DataTypes\.(\w+)', block)}):
    if t not in SAMSUNG:
        errors.append(f'Samsung: νέο είδος δεδομένων {t}· γράψ\' το στην πολιτική και στη λίστα SAMSUNG του {sys.argv[0]}')
    else:
        need(SAMSUNG[t] in greek, f'Samsung: η εφαρμογή ζητά {t}, αλλά η πολιτική δεν λέει «{SAMSUNG[t]}»')

# --- Μεσάζων Oura ---
proxy = re.search(r"const ouraTokenProxy = '([^']*)';", cfg).group(1)
if 'netlify' in proxy:
    need('Netlify' in greek and 'ΗΠΑ' in greek, 'Oura: ο μεσάζων τρέχει στο Netlify (ΗΠΑ)· η πολιτική πρέπει να το λέει')
    need('US' in english, 'Oura: το αγγλικό κείμενο πρέπει να λέει ότι ο μεσάζων είναι στις ΗΠΑ (US)')

# --- Sentry ---
rep = read('lib/error_report.dart')
m = re.search(r'https://[^/]*\.ingest\.(\w+)\.sentry\.io', rep)
if m:
    need('Sentry' in greek, 'Sentry: η εφαρμογή στέλνει αναφορές, η πολιτική δεν το λέει')
    region = {'de': 'ΕΕ', 'us': 'ΗΠΑ'}.get(m.group(1), m.group(1))
    need(region in greek.split('Sentry', 1)[-1][:600], f'Sentry: η περιοχή ({region}) πρέπει να γράφεται δίπλα στο Sentry')

# --- Barcode ---
extra = read('android/ygeia/app-extra.gradle.kts')
if 'play-services-code-scanner' in extra:
    need('ML Kit' in greek and 'Google Play services' in greek, 'Barcode: ο σαρωτής της Google (ML Kit) πρέπει να γράφεται')
food = read('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/FoodBridge.kt')
if 'openfoodfacts.org' in food:
    need('Open Food Facts' in greek, 'Barcode: το Open Food Facts πρέπει να γράφεται')

# --- Ρολόι ---
wear = read('android/wear/src/main/AndroidManifest.xml')
if 'ACCESS_FINE_LOCATION' in wear:
    need('GPS' in greek, 'Ρολόι: ζητά τοποθεσία (GPS)· η πολιτική πρέπει να το λέει')
if 'READ_HEART_RATE' in wear or 'BODY_SENSORS' in wear:
    need('ρολόι μετρά παλμούς' in greek, 'Ρολόι: μετρά παλμούς· η πολιτική πρέπει να το λέει')

# --- Αντίγραφο Google ---
rules = read('tools/android/xml/data_extraction_rules.xml')
if '<cloud-backup' in rules:
    need('αντίγραφο της Google' in greek or 'Αυτόματο αντίγραφο της Google' in greek, 'Αντίγραφο: το αντίγραφο της Google πρέπει να γράφεται')
    if 'disableIfNoEncryptionCapabilities="true"' in rules:
        need('κρυπτογράφηση από άκρη σε άκρη' in greek, 'Αντίγραφο: να λέει «κρυπτογράφηση από άκρη σε άκρη»')

# --- Γενικά ---
need(re.search(r'Τελευταία ενημέρωση: \d{1,2} \w+ 20\d\d', page), 'Λείπει η «Τελευταία ενημέρωση: …»')
need('dpa.gr' in page, 'Λείπει η Αρχή Προστασίας Δεδομένων (δικαίωμα καταγγελίας)')
need('Επικοινωνία' in greek, 'Λείπει η ενότητα «Επικοινωνία»')

if errors:
    for e in errors:
        print(f'::error title=Πολιτική απορρήτου::{e}')
    sys.exit(1)
print(f'Πολιτική απορρήτου: συμφωνεί με τον κώδικα (Oura: {scopes}; Samsung: {sum(len(re.findall(r"DataTypes", b)) for b in lists)} είδη)')
