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
import os
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


def grab(pat, text, what, flags=0, group=1):
    """Ό,τι ζητά το pattern· αν δεν βρεθεί, καθαρό μήνυμα (όχι traceback): άλλαξε ο κώδικας και ο έλεγχος θέλει ενημέρωση."""
    m = re.search(pat, text, flags)
    if not m:
        errors.append(f'Δεν βρέθηκε {what} — άλλαξε ο κώδικας; ενημέρωσε το tools/ci/check_privacy.py')
        return ''
    return m.group(group)


# --- Oura: οι άδειες που ζητούνται ---
cfg = read('lib/oura/config.dart')
scopes = grab(r"const ouraScopes = '([^']*)';", cfg, 'το ouraScopes στο lib/oura/config.dart').strip()
if not scopes:
    name = grab(r'const ouraOAuth = OuraOAuthEndpoints\.(\w+);', cfg, 'το ouraOAuth στο lib/oura/config.dart')
    block = grab(rf'static const {name} = OuraOAuthEndpoints\._\((.*?)\);', cfg, f'το OuraOAuthEndpoints.{name}', re.S) if name else ''
    args = re.findall(r"'([^']*)'", block)
    # Η σειρά των ορισμάτων: authorize, token, revoke, scopes, revokeParam.
    scopes = args[3] if len(args) >= 4 else ''
    need(scopes, f'Δεν βρέθηκαν τα scopes του OuraOAuthEndpoints.{name}')
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

# --- Ανάγνωση στο παρασκήνιο (έλεγχος 13/11, U4-8): όσο υπάρχει ο RefreshWorker, η πολιτική λέει ότι η εφαρμογή διαβάζει
# το Samsung Health και χωρίς να είναι ανοιχτή. ---
worker = 'android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/RefreshWorker.kt'
if os.path.exists(f'{ROOT}/{worker}') and 'PeriodicWorkRequestBuilder<RefreshWorker>' in read(worker):
    need('στο παρασκήνιο' in greek, 'Samsung: η εφαρμογή διαβάζει και στο παρασκήνιο (RefreshWorker)· η πολιτική πρέπει να το λέει')
    need('in the background' in english, 'Samsung: η ανάγνωση στο παρασκήνιο λείπει από το αγγλικό κείμενο')

# --- Μεσάζων Oura ---
proxy = grab(r"const ouraTokenProxy = '([^']*)';", cfg, 'το ouraTokenProxy στο lib/oura/config.dart')
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

# Διακόπτης στις Ρυθμίσεις (έλεγχος 9/11, E3-05): αν υπάρχει στον κώδικα, η πολιτική λέει πώς κλείνει.
if 'Future<bool> setEnabled(' in rep:
    need('«Αναφορές σφαλμάτων»' in greek, 'Sentry: υπάρχει διακόπτης «Αναφορές σφαλμάτων»· η πολιτική πρέπει να λέει πώς κλείνει')
    need('turn them off' in english, 'Sentry: ο διακόπτης λείπει από το αγγλικό κείμενο')

# --- Διαγραφή μέσα στην εφαρμογή (E3-05) ---
import pathlib
if pathlib.Path(f'{ROOT}/lib/pages/privacy_page.dart').exists() and 'Διαγραφή όλων των δεδομένων' in read('lib/pages/privacy_page.dart'):
    need('«Διαγραφή όλων των δεδομένων»' in greek, 'Διαγραφή: η εφαρμογή έχει «Διαγραφή όλων των δεδομένων»· η πολιτική πρέπει να τη λέει')
    need('Delete all data' in english, 'Διαγραφή: λείπει από το αγγλικό κείμενο')

# --- «Αναφορά για έλεγχο» (Round 7, R7-A11-2): αρχείο στις Λήψεις με ΟΛΑ τα δεδομένα (και της Oura), που ο χρήστης
# στέλνει μόνος του. Όσο υπάρχει στον κώδικα, η πολιτική το λέει (στη λίστα των αρχείων και στη «Διαγραφή»). ---
if pathlib.Path(f'{ROOT}/lib/diagnostics.dart').exists():
    need('«Αναφορά για έλεγχο»' in greek, 'Αναφορά για έλεγχο: η εφαρμογή φτιάχνει αυτό το αρχείο· η πολιτική πρέπει να το λέει')
    need('diagnostics' in english, 'Αναφορά για έλεγχο: λείπει από το αγγλικό κείμενο (diagnostics)')

# --- Η «Αναφορά για γιατρό» (PDF) με δεδομένα της Oura (Round 9, R9-A11-1) ---
# Η πολιτική έλεγε ότι τα δεδομένα της Oura μπαίνουν «μόνο» στην «Αναφορά για έλεγχο», ενώ το PDF για τον γιατρό έχει
# ύπνο, HRV, παλμούς, αναπνοές και οξυγόνο του Oura (lib/report.dart, reportKeysFor). Όσο το κάνει ο κώδικας, η ενότητα
# «Oura» της πολιτικής το λέει, και το αγγλικό κείμενο λέει ότι το PDF έχει δεδομένα της Oura.
if re.search(r'reportKeysFor\(SourcePlan plan\)\s*=>\s*plan\.hasOura', read('lib/report.dart')):
    oura_gr = grab(r'<h3>Oura</h3>(.*?)<h3>', greek, 'η ενότητα «Oura» της πολιτικής', re.S)
    need('«Αναφορά για γιατρό»' in oura_gr,
         'Oura: τα δεδομένα της μπαίνουν και στην «Αναφορά για γιατρό» (PDF)· η ενότητα «Oura» της πολιτικής πρέπει να το λέει')
    need(re.search(r'doctor PDFs[^.]*Oura', english),
         'Oura: λείπει από το αγγλικό κείμενο ότι το PDF για τον γιατρό έχει δεδομένα της Oura («doctor PDFs … Oura»)')

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
if '<device-transfer' in rules:
    need('νέο κινητό' in greek, 'Αντίγραφο: η μεταφορά σε νέο κινητό (device-transfer) πρέπει να γράφεται')
    need('device-to-device' in english, 'Αντίγραφο: η μεταφορά σε νέο κινητό λείπει από το αγγλικό κείμενο')

# --- Κάθε υπηρεσία στο διαδίκτυο που καλεί ο κώδικας πρέπει να είναι γνωστή (και γραμμένη στην πολιτική) ---
KNOWN_HOSTS = {
    'ouraring.com': 'Oura', 'netlify.app': 'Netlify', 'openfoodfacts.org': 'Open Food Facts', 'sentry.io': 'Sentry',
}
# Διευθύνσεις που υπάρχουν στον κώδικα αλλά η εφαρμογή ΔΕΝ τις καλεί (σύνδεσμοι πηγών που ανοίγει ο χρήστης, User-Agent).
NOT_CONTACTED = {
    'ciqual.anses.fr': 'σύνδεσμος πηγής (food_sources.dart)', 'fdc.nal.usda.gov': 'σύνδεσμος πηγής (food_sources.dart)',
    'github.com': 'μόνο μέσα στο User-Agent προς το Open Food Facts',
    'www.apache.org': 'μόνο κείμενο στη σελίδα «Άδειες λογισμικού» (privacy_page.dart)',
}
import os
for base in ('lib', 'android/app/src/main', 'android/wear/src/main'):
    for dirpath, _, files in os.walk(f'{ROOT}/{base}'):
        for fn in files:
            if not fn.endswith(('.dart', '.kt', '.java')):
                continue
            with open(os.path.join(dirpath, fn), encoding='utf-8', errors='replace') as f:
                src = f.read()
            for host in set(re.findall(r'https://([a-z0-9.-]+\.[a-z]{2,})', src)):
                if host in NOT_CONTACTED:
                    continue
                known = [k for k in KNOWN_HOSTS if host == k or host.endswith('.' + k)]
                if not known:
                    errors.append(f'Νέα υπηρεσία στο {base}/…/{fn}: {host} — γράψ\' τη στην πολιτική και στη λίστα KNOWN_HOSTS')
                else:
                    need(KNOWN_HOSTS[known[0]] in greek, f'{host}: η πολιτική πρέπει να αναφέρει {KNOWN_HOSTS[known[0]]}')

# --- Δημόσιο repository: κανένα πραγματικό δεδομένο υγείας ή στοιχείο του ιδιοκτήτη (round 7, R7-A11-1) ---
# Σχόλια και δοκιμές περιγράφουν κανόνες, ποτέ ένα πρόσωπο, και οι τιμές των δοκιμών είναι επινοημένες. Οι φράσεις
# παρακάτω έλεγαν ότι μια νύχτα/μια βόλτα ήταν «πραγματική» ή έλεγαν το ιατρικό ιστορικό του ιδιοκτήτη.
# Round 8 (R8-A11-1): ΚΑΜΙΑ πραγματική τιμή εδώ, ούτε ως «αποτύπωμα». Ο γύρος 7 έλεγχε συγκεκριμένες τιμές με SHA-256
# και δημόσιο «αλάτι»· για λίγες χιλιάδες δυνατές τιμές (έτος, ύψος, οξυγόνο) το αποτύπωμα αντιστρέφεται σε κλάσματα του
# δευτερολέπτου, άρα το αρχείο ξαναδημοσίευε τις τιμές, μάλιστα με ετικέτα. Μένουν μόνο οι φράσεις.
OWNER_PHRASES = [
    (r'ιδιοκτήτ', '«ιδιοκτήτης»: σχόλια και δοκιμές περιγράφουν κανόνες, όχι ένα πρόσωπο'),
    (r'λόγος της επίσκεψης', 'ιατρικό ιστορικό («λόγος της επίσκεψης»)'),
    (r'επίσκεψη στον', 'ιατρικό ιστορικό («επίσκεψη στον …»)'),
    (r'καρδιολόγ', 'ιατρικό ιστορικό («καρδιολόγος»): γράψε «γιατρός» και τον κανόνα'),
    (r'πραγματικ(?:ή|ές) νύχτ', 'δεδομένα δοκιμής ως «πραγματική νύχτα»'),
    (r'νύχτα του χρήστη|του χρήστη \(\d{1,2}:\d\d', 'δεδομένα δοκιμής ως «του χρήστη» (νύχτα, ώρες)'),
    (r'πραγματική σημείωση', 'δεδομένα δοκιμής ως «πραγματική σημείωση»'),
]
SELF = os.path.normpath('tools/ci/check_privacy.py')
TEXT_EXT = ('.dart', '.kt', '.kts', '.java', '.py', '.js', '.mjs', '.sh', '.xml', '.json', '.yml', '.yaml', '.md', '.txt')


def _scan_owner(rel, text):
    for no, line in enumerate(text.split('\n'), 1):
        for pat, why in OWNER_PHRASES:
            if re.search(pat, line, re.IGNORECASE):
                errors.append(f'Δημόσιο repo: {rel}:{no}: {why} (R7-A11-1)')


for base in ('lib', 'test', 'android/app/src', 'android/wear/src', 'tools', 'assets/exercises'):
    for dirpath, dirs, files in os.walk(f'{ROOT}/{base}'):
        dirs[:] = [d for d in dirs if d not in ('build', 'out', '.gradle', 'node_modules')]
        for fn in files:
            if not fn.endswith(TEXT_EXT):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.normpath(os.path.relpath(path, ROOT)).replace(os.sep, '/')
            if rel == SELF.replace(os.sep, '/'):
                continue
            with open(path, encoding='utf-8', errors='replace') as f:
                _scan_owner(rel, f.read())

# --- Γενικά ---
need(re.search(r'Τελευταία ενημέρωση: \d{1,2} \w+ 20\d\d', page), 'Λείπει η «Τελευταία ενημέρωση: …»')

# --- Ημερομηνία της πολιτικής (round 8, R8-A11-5) ---
# Η πολιτική υπόσχεται «αυτή η σελίδα ενημερώνεται πρώτα, με νέα ημερομηνία». Ο γύρος 7 άλλαξε το κείμενο και άφησε την
# παλιά ημερομηνία. Το tools/ci/privacy_stamp.txt κρατά το αποτύπωμα (SHA-256) της σελίδας χωρίς τη γραμμή της ημερομηνίας
# και την ημερομηνία της: κάθε αλλαγή στη σελίδα σταματά το χτίσιμο ώσπου να μπει νέα ημερομηνία και νέο αποτύπωμα.
# (Χωρίς git και ώρες: δεν αποτυγχάνει ποτέ επειδή ένα commit έγινε μετά τα μεσάνυχτα ή μπήκε στο main άλλη μέρα.)
import hashlib

_date = re.search(r'Τελευταία ενημέρωση: ([^<]*)<', page)
_shown = _date.group(1).strip() if _date else ''
_body = re.sub(r'Τελευταία ενημέρωση: [^<]*<', 'Τελευταία ενημέρωση: <', page)
_now = hashlib.sha256(_body.encode('utf-8')).hexdigest()
_stamp_path = f'{ROOT}/tools/ci/privacy_stamp.txt'
_stamp = open(_stamp_path, encoding='utf-8').read().split(maxsplit=1) if os.path.exists(_stamp_path) else []
if len(_stamp) != 2 or _stamp[0] != _now or _stamp[1].strip() != _shown:
    errors.append('Η πολιτική απορρήτου άλλαξε (ή άλλαξε η ημερομηνία της) χωρίς να ενημερωθεί το tools/ci/privacy_stamp.txt. '
                  'Αν άλλαξε το κείμενο, βάλε πρώτα στη σελίδα «Τελευταία ενημέρωση:» τη μέρα της αλλαγής· μετά γράψε στο '
                  f'tools/ci/privacy_stamp.txt τη γραμμή: {_now} {_shown}')
need('dpa.gr' in page, 'Λείπει η Αρχή Προστασίας Δεδομένων (δικαίωμα καταγγελίας)')
need('Επικοινωνία' in greek, 'Λείπει η ενότητα «Επικοινωνία»')

if errors:
    for e in errors:
        print(f'::error title=Πολιτική απορρήτου::{e}')
    sys.exit(1)
print(f'Πολιτική απορρήτου: συμφωνεί με τον κώδικα (Oura: {scopes}; Samsung: {sum(len(re.findall(r"DataTypes", b)) for b in lists)} είδη)')
