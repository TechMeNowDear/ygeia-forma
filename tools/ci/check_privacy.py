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
# παρακάτω έλεγαν ότι μια νύχτα/μια βόλτα ήταν «πραγματική» ή έλεγαν το ιατρικό ιστορικό του ιδιοκτήτη. Οι ίδιες οι
# πραγματικές τιμές ΔΕΝ γράφονται εδώ (αλλιώς αυτό το αρχείο θα τις ξαναδημοσίευε): ελέγχονται ως αποτύπωμα SHA-256.
# Είναι μόνο τιμές που ήδη υπάρχουν στο δημόσιο ιστορικό του git (δεν προσθέτουν τίποτα νέο). Το αποτύπωμα ενός μικρού
# αριθμού βρίσκεται με δοκιμές: σκοπός είναι να μη γράφονται ξανά ανοιχτά στο repository, όχι να είναι μυστικές.
import hashlib


def _print(kind, value):
    return hashlib.sha256(f'ygeia-forma/R7-A11-1|{kind}|{value}'.encode()).hexdigest()[:20]


OWNER_PRINTS = {
    'by': {'38bafc149377b0cc5c63'},                              # έτος γέννησης
    'h': {'21f38547313768c70ae3', 'f0357eab4f6ecf97ce36'},       # ύψος (και η παλιότερη τιμή του)
    'spo2': {'81cc66be27666709036a', 'cd2172d5438115c98087'},    # τα δύο πραγματικά ελάχιστα οξυγόνου (μαζί)
    'dated': {'c86e877f2d9933f16296', 'eb3ff6a4735fa824336a'},   # «η/μ: τιμή%» των δύο νυχτών
}
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
CODE_EXT = ('.dart', '.kt')
_num = re.compile(r'(?<![\w.,])(\d{1,3}(?:[.,]\d+)?)(?![\w])')
_pct = re.compile(r'(?<![\w.,])(\d{1,3}(?:[.,]\d+)?)\s?%')
_oxygen = re.compile(r'spo2|oxygen|οξυγόν', re.IGNORECASE)
_by = re.compile(r'(?:birthYear\s*:\s*|["\']by["\']\s*:\s*)(\d{4})\b')
_height = re.compile(r'(?:heightCm\s*:\s*|["\']h["\']\s*:\s*)(\d{2,3}(?:\.\d+)?)\b')
_dated = re.compile(r'(\d{1,2}/\d{1,2}): (\d{2,3}(?:,\d+)?)%')


def _norm(tok):
    try:
        x = float(tok.replace(',', '.'))
    except ValueError:
        return tok
    return str(int(x)) if x == int(x) else f'{x:g}'


def _scan_owner(rel, text):
    code = rel.endswith(CODE_EXT) and not rel.startswith('tools/')
    spo2_file = set()
    for no, line in enumerate(text.split('\n'), 1):
        where = f'{rel}:{no}'
        for pat, why in OWNER_PHRASES:
            if re.search(pat, line, re.IGNORECASE):
                errors.append(f'Δημόσιο repo: {where}: {why} (R7-A11-1)')
        if not code:
            continue
        for y in _by.findall(line):
            if _print('by', y) in OWNER_PRINTS['by']:
                errors.append(f'Δημόσιο repo: {where}: πραγματικό έτος γέννησης του ιδιοκτήτη· βάλε επινοημένο (R7-A11-1)')
        for v in _height.findall(line):
            if _print('h', _norm(v)) in OWNER_PRINTS['h']:
                errors.append(f'Δημόσιο repo: {where}: πραγματικό ύψος του ιδιοκτήτη· βάλε επινοημένο (R7-A11-1)')
        for d, v in _dated.findall(line):
            if _print('dated', f'{d}:{_norm(v)}') in OWNER_PRINTS['dated']:
                errors.append(f'Δημόσιο repo: {where}: πραγματική νύχτα (μέρα και οξυγόνο) του ιδιοκτήτη (R7-A11-1)')
        # Οξυγόνο: γραμμή που μιλά για οξυγόνο (ή αριθμοί με «%»), όχι κάθε λίστα αριθμών (π.χ. δείγμα ετοιμότητας).
        oxygen = bool(_oxygen.search(line))
        prints = {_print('spo2', _norm(t)) for t in (_num.findall(line) if oxygen else _pct.findall(line))}
        if OWNER_PRINTS['spo2'] <= prints:
            errors.append(f'Δημόσιο repo: {where}: τα δύο πραγματικά ελάχιστα οξυγόνου μαζί· βάλε επινοημένα (R7-A11-1)')
        if oxygen:
            spo2_file |= prints & OWNER_PRINTS['spo2']
    if code and OWNER_PRINTS['spo2'] <= spo2_file:
        errors.append(f'Δημόσιο repo: {rel}: τα δύο πραγματικά ελάχιστα οξυγόνου στο ίδιο αρχείο· βάλε επινοημένα (R7-A11-1)')


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
need('dpa.gr' in page, 'Λείπει η Αρχή Προστασίας Δεδομένων (δικαίωμα καταγγελίας)')
need('Επικοινωνία' in greek, 'Λείπει η ενότητα «Επικοινωνία»')

if errors:
    for e in errors:
        print(f'::error title=Πολιτική απορρήτου::{e}')
    sys.exit(1)
print(f'Πολιτική απορρήτου: συμφωνεί με τον κώδικα (Oura: {scopes}; Samsung: {sum(len(re.findall(r"DataTypes", b)) for b in lists)} είδη)')
