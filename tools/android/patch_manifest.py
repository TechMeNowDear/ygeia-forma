#!/usr/bin/env python3
"""Προσθήκες στο AndroidManifest.xml που φτιάχνει το «flutter create» (δεν το κρατάμε στο repository).

Για τη σύνδεση με το Oura (απόφαση 2/11, διόρθωση μετά τον έλεγχο):
1. Μικρή οθόνη OuraCallbackActivity για τη διεύθυνση επιστροφής (OAuth redirect), με δύο ακριβείς μορφές:
   - App Link https://ygeia-forma.netlify.app/oura/callback (autoVerify, assetlinks.json στο Netlify),
   - ygeiaforma://oura-callback (custom scheme, εφεδρική).
   Η MainActivity ΔΕΝ αλλάζει (μένει όπως τη φτιάχνει η Flutter: launchMode, επιλογέας αρχείων, άδειες Samsung).
2. <queries> για browser (https), όπως θέλει το Android 11+ για να βλέπει ποιος ανοίγει συνδέσμους.
3. Κανόνες αντιγράφου Google (έλεγχος 4/11, A10): μόνο βάση, ρυθμίσεις, σχέδιο πηγών, νύχτες Oura
   (tools/android/xml → res/xml: data_extraction_rules.xml, backup_rules.xml)· όχι το βοηθητικό αρχείο, όχι tokens.

Τρέχει όσες φορές θέλουμε (δεν προσθέτει δεύτερη φορά). Σταματά με σφάλμα αν δεν βρει ό,τι περιμένει.
Χρήση: python3 tools/android/patch_manifest.py android/app/src/main/AndroidManifest.xml
"""
import os
import re
import shutil
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    s = f.read()

CALLBACK = (
    "\n        <!-- Σύνδεση Oura: επιστροφή από τη σελίδα της Oura (OAuth). Δίνει τον κωδικό στην εφαρμογή και κλείνει. -->\n"
    "        <activity\n"
    '            android:name=".OuraCallbackActivity"\n'
    '            android:exported="true"\n'
    '            android:noHistory="true"\n'
    '            android:excludeFromRecents="true"\n'
    '            android:taskAffinity=""\n'
    '            android:theme="@android:style/Theme.Translucent.NoTitleBar">\n'
    '            <intent-filter android:autoVerify="true">\n'
    '                <action android:name="android.intent.action.VIEW"/>\n'
    '                <category android:name="android.intent.category.DEFAULT"/>\n'
    '                <category android:name="android.intent.category.BROWSABLE"/>\n'
    '                <data android:scheme="https" android:host="ygeia-forma.netlify.app" android:path="/oura/callback"/>\n'
    "            </intent-filter>\n"
    "            <intent-filter>\n"
    '                <action android:name="android.intent.action.VIEW"/>\n'
    '                <category android:name="android.intent.category.DEFAULT"/>\n'
    '                <category android:name="android.intent.category.BROWSABLE"/>\n'
    '                <data android:scheme="ygeiaforma" android:host="oura-callback"/>\n'
    "            </intent-filter>\n"
    "        </activity>"
)
BROWSER = (
    "\n        <!-- Σύνδεση Oura: άνοιγμα της σελίδας σύνδεσης στον browser. -->\n"
    "        <intent>\n"
    '            <action android:name="android.intent.action.VIEW"/>\n'
    '            <category android:name="android.intent.category.BROWSABLE"/>\n'
    '            <data android:scheme="https"/>\n'
    "        </intent>"
)

if not re.search(r'<activity\b[^>]*android:name="\.MainActivity"', s, re.S):
    sys.exit("Δεν βρέθηκε η MainActivity στο manifest")
before_main = re.search(r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>', s, re.S).group(0)

if ".OuraCallbackActivity" not in s:
    if "</application>" not in s:
        sys.exit("Δεν βρέθηκε το τέλος του application")
    s = s.replace("</application>", CALLBACK.lstrip("\n") + "\n    </application>", 1)

if "<!-- Σύνδεση Oura: άνοιγμα" not in s:
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>" + BROWSER, 1)
    else:
        s = s.replace("</manifest>", "    <queries>" + BROWSER + "\n    </queries>\n</manifest>", 1)

# Τα αρχεία των κανόνων (το res/ το φτιάχνει το «flutter create» και δεν το κρατάμε στο repository).
xml_src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xml")
xml_dst = os.path.join(os.path.dirname(os.path.abspath(path)), "res", "xml")
os.makedirs(xml_dst, exist_ok=True)
for name in ("data_extraction_rules.xml", "backup_rules.xml"):
    shutil.copyfile(os.path.join(xml_src, name), os.path.join(xml_dst, name))

BACKUP = ('android:allowBackup="true"', 'android:fullBackupContent="@xml/backup_rules"',
          'android:dataExtractionRules="@xml/data_extraction_rules"')
app_tag = re.search(r"<application\b[^>]*>", s, re.S)
if not app_tag:
    sys.exit("Δεν βρέθηκε το application")
tag = app_tag.group(0)
if "android:fullBackupContent" in tag or "android:dataExtractionRules" in tag or "android:allowBackup" in tag:
    if not all(a in tag for a in BACKUP):
        sys.exit("Το application έχει ήδη άλλους κανόνες αντιγράφου")
else:
    s = s.replace(tag, tag.replace("<application", "<application\n        " + "\n        ".join(BACKUP), 1), 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(s)

# Έλεγχος: όλα στη θέση τους, και η MainActivity ακριβώς όπως ήταν.
after_main = re.search(r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>', s, re.S).group(0)
if after_main != before_main:
    sys.exit("Η MainActivity άλλαξε· δεν έπρεπε")
for needle in ('android:name=".OuraCallbackActivity"', 'android:scheme="ygeiaforma"', 'android:host="oura-callback"',
               'android:host="ygeia-forma.netlify.app"', 'android:path="/oura/callback"', 'android:autoVerify="true"',
               "<!-- Σύνδεση Oura: άνοιγμα") + BACKUP:
    if needle not in s:
        sys.exit("Λείπει μετά την αλλαγή: " + needle)
if s.count('android:scheme="ygeiaforma"') != 1:
    sys.exit("Η επιστροφή ygeiaforma:// δηλώθηκε δύο φορές")
if s.count('android:host="ygeia-forma.netlify.app"') != 1:
    sys.exit("Το App Link δηλώθηκε δύο φορές")
print("Manifest: OuraCallbackActivity (https App Link + ygeiaforma://oura-callback), queries https, κανόνες αντιγράφου· "
      "MainActivity χωρίς αλλαγή")
