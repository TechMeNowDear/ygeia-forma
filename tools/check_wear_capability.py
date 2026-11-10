"""Έλεγχος του APK του ρολογιού: να έχει τη δυνατότητα «ygeia_watch» (android_wear_capabilities).

Χωρίς αυτή το κινητό δεν βρίσκει ποτέ την εφαρμογή του ρολογιού (το #85 βγήκε έτσι: τη έσβησε η σμίκρυνση
πόρων). Χρήση: python3 -I tools/check_wear_capability.py <apk>

Έλεγχος γ2 (W3-19): με το aapt2 του Android SDK ελέγχεται ότι υπάρχει ο ίδιος ο πίνακας
«array/android_wear_capabilities» και ότι μέσα του είναι το «ygeia_watch» (πριν: μόνο ότι η λέξη βρίσκεται κάπου στους
πόρους). Χωρίς aapt2 (τοπικά): ο παλιός, απλός έλεγχος· στο CI το aapt2 είναι υποχρεωτικό.
"""
import glob
import os
import subprocess
import sys
import zipfile

apk = sys.argv[1]
want = 'ygeia_watch'


def fail(msg):
    print(f'::error title=Ρολόι::{msg}')
    sys.exit(1)


data = zipfile.ZipFile(apk).read('resources.arsc')
if want.encode('utf-8') not in data and want.encode('utf-16-le') not in data:
    fail(f'Το {apk} δεν έχει τη δυνατότητα «{want}»· το κινητό δεν θα βρει το ρολόι.')


def find_aapt2():
    for env in ('ANDROID_HOME', 'ANDROID_SDK_ROOT'):
        root = os.environ.get(env)
        if not root:
            continue
        found = sorted(glob.glob(os.path.join(root, 'build-tools', '*', 'aapt2')))
        if found:
            return found[-1]
    return None


aapt2 = find_aapt2()
if aapt2 is None:
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        fail('Δεν βρέθηκε το aapt2 του Android SDK για τον έλεγχο του android_wear_capabilities.')
    print(f'{apk}: δυνατότητα «{want}» υπάρχει (χωρίς aapt2: μόνο απλός έλεγχος)')
    sys.exit(0)

out = subprocess.run([aapt2, 'dump', 'resources', apk], capture_output=True, text=True, check=False)
if out.returncode != 0:
    fail(f'aapt2 dump resources απέτυχε: {out.stderr.strip()[:300]}')
lines = out.stdout.splitlines()
at = [i for i, line in enumerate(lines) if 'array/android_wear_capabilities' in line]
if not at:
    fail(f'Το {apk} δεν έχει τον πίνακα «android_wear_capabilities»· το κινητό δεν θα βρει το ρολόι.')
# Οι τιμές του πίνακα είναι στις αμέσως επόμενες γραμμές (ως την επόμενη «resource»).
ok = False
for i in at:
    for line in lines[i + 1:i + 12]:
        if line.strip().startswith('resource '):
            break
        if want in line:
            ok = True
if not ok:
    fail(f'Ο πίνακας «android_wear_capabilities» του {apk} δεν έχει το «{want}».')
print(f'{apk}: πίνακας android_wear_capabilities με «{want}» (aapt2)')
