#!/usr/bin/env python3
"""Προσθήκες στο AndroidManifest.xml που φτιάχνει το «flutter create» (δεν το κρατάμε στο repository).

Για τη σύνδεση με το Oura (απόφαση 2/11):
1. MainActivity σε launchMode="singleTask": η επιστροφή από τον browser έρχεται στην ίδια οθόνη (onNewIntent),
   όχι σε δεύτερο αντίγραφο της εφαρμογής.
2. intent-filter για τη διεύθυνση επιστροφής ygeiaforma://oura-callback (OAuth redirect).
3. <queries> για browser (https), όπως θέλει το Android 11+ για να βλέπει ποιος ανοίγει συνδέσμους.

Τρέχει όσες φορές θέλουμε (δεν προσθέτει δεύτερη φορά). Σταματά με σφάλμα αν δεν βρει ό,τι περιμένει.
Χρήση: python3 tools/android/patch_manifest.py android/app/src/main/AndroidManifest.xml
"""
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    s = f.read()

CALLBACK = (
    "\n            <!-- Σύνδεση Oura: επιστροφή από τη σελίδα της Oura (OAuth). -->\n"
    "            <intent-filter>\n"
    '                <action android:name="android.intent.action.VIEW"/>\n'
    '                <category android:name="android.intent.category.DEFAULT"/>\n'
    '                <category android:name="android.intent.category.BROWSABLE"/>\n'
    '                <data android:scheme="ygeiaforma" android:host="oura-callback"/>\n'
    "            </intent-filter>"
)
BROWSER = (
    "\n        <!-- Σύνδεση Oura: άνοιγμα της σελίδας σύνδεσης στον browser. -->\n"
    "        <intent>\n"
    '            <action android:name="android.intent.action.VIEW"/>\n'
    '            <category android:name="android.intent.category.BROWSABLE"/>\n'
    '            <data android:scheme="https"/>\n'
    "        </intent>"
)

# Το στοιχείο της MainActivity (από «<activity» ως το «>» του ανοίγματος).
m = re.search(r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>', s, re.S)
if not m:
    sys.exit("Δεν βρέθηκε η MainActivity στο manifest")
tag = m.group(0)
if 'android:launchMode="' in tag:
    new_tag = re.sub(r'android:launchMode="[^"]*"', 'android:launchMode="singleTask"', tag)
else:
    new_tag = tag.replace("<activity", '<activity\n            android:launchMode="singleTask"', 1)
s = s[: m.start()] + new_tag + s[m.end() :]

if 'android:scheme="ygeiaforma"' not in s:
    start = s.find(new_tag)
    end = s.find("</activity>", start)
    if end < 0:
        sys.exit("Δεν βρέθηκε το τέλος της MainActivity")
    s = s[:end].rstrip() + CALLBACK + "\n        " + s[end:]

if 'android:scheme="https"' not in s:
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>" + BROWSER, 1)
    else:
        s = s.replace("</manifest>", "    <queries>" + BROWSER + "\n    </queries>\n</manifest>", 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(s)

# Έλεγχος: όλα στη θέση τους.
for needle in ('android:launchMode="singleTask"', 'android:scheme="ygeiaforma"', 'android:host="oura-callback"', 'android:scheme="https"'):
    if needle not in s:
        sys.exit("Λείπει μετά την αλλαγή: " + needle)
print("Manifest: singleTask, ygeiaforma://oura-callback, queries https")
