#!/usr/bin/env python3
"""Έλεγχος ενός υπογεγραμμένου APK πριν φτάσει στο κινητό ή στο ρολόι (έλεγχος 9/11, V-A-20).

Χρήση: python3 -I tools/ci/apk_check.py <αναμενόμενο SHA-256 πιστοποιητικού> <έξοδος «apksigner verify --print-certs -v»> <apk>

Αποτυγχάνει αν:
- το πιστοποιητικό δεν είναι ΑΚΡΙΒΩΣ το σταθερό (ένα άλλο κλειδί = η έκδοση δεν μπαίνει πάνω στην παλιά, και η
  απεγκατάσταση σβήνει τα δεδομένα· το ρολόι δεν μιλά με το κινητό),
- υπάρχουν περισσότεροι από ένας υπογράφοντες,
- λείπει η υπογραφή v2 (όπως όλες οι εκδόσεις ως την #89: μόνο v2),
- μια ασυμπίεστη βιβλιοθήκη .so δεν είναι στοιχισμένη στα 16 KB (Android 15+ σε συσκευές με σελίδες 16 KB).
Μόνο βιβλιοθήκη της Python· δεν τυπώνει τίποτα μυστικό (το πιστοποιητικό είναι δημόσιο).
"""
import re
import struct
import sys
import zipfile


def so_misaligned(path):
    bad = []
    n = 0
    with open(path, 'rb') as f, zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if not info.filename.endswith('.so') or info.compress_type != zipfile.ZIP_STORED:
                continue
            n += 1
            f.seek(info.header_offset)
            h = f.read(30)
            name_len, extra_len = struct.unpack('<HH', h[26:30])
            data = info.header_offset + 30 + name_len + extra_len
            if data % 16384:
                bad.append(info.filename)
    return n, bad


def main():
    want, verify_log, apk = sys.argv[1].lower().replace(':', ''), sys.argv[2], sys.argv[3]
    text = open(verify_log, encoding='utf-8', errors='replace').read()
    errors = []
    if not re.search(r'Verified using v2 scheme \(APK Signature Scheme v2\): true', text):
        errors.append('δεν υπάρχει υπογραφή v2')
    # «Signer #1 certificate SHA-256 digest: …» (η μορφή αλλάζει λίγο ανάμεσα σε εκδόσεις του apksigner: δεκτά και
    # κεφαλαία και άνω-κάτω τελείες).
    signers = [(m.group(1).strip(), m.group(2).replace(':', '').lower())
               for m in re.finditer(r'^(Signer[^\n]*?) certificate SHA-256 digest: ([0-9a-fA-F:]{64,95})\s*$', text, re.M)]
    count = re.search(r'Number of signers: (\d+)', text)
    n_signers = int(count.group(1)) if count else len({s[0] for s in signers})
    if n_signers != 1 or not signers:
        errors.append(f'περιμέναμε έναν υπογράφοντα, βρέθηκαν {n_signers}')
    got = signers[0][1] if signers else ''
    if got != want:
        errors.append(f'άλλο πιστοποιητικό: {got[:12] or "κανένα"}… αντί για {want[:12]}…')
    n, bad = so_misaligned(apk)
    if bad:
        errors.append('βιβλιοθήκες χωρίς στοίχιση 16 KB: ' + ', '.join(bad))
    schemes = ', '.join(v for v in ('v1', 'v2', 'v3', 'v4')
                        if re.search(rf'Verified using {v} scheme[^:]*: true', text)) or 'καμία'
    if errors:
        for e in errors:
            print(f'::error title=Υπογραφή {apk}::{e}')
        # Μόνο δημόσια στοιχεία (σχήματα, πλήθος, αποτυπώματα πιστοποιητικού) για διάγνωση.
        for line in text.splitlines():
            if re.match(r'(Verifie|Number of signers|Signer|WARNING|ERROR|DOES NOT VERIFY)', line) and 'DN:' not in line:
                print('  ' + line[:200])
        sys.exit(1)
    print(f'{apk}: πιστοποιητικό {got[:12]}… σωστό · σχήματα {schemes} · {n} βιβλιοθήκες .so στοιχισμένες στα 16 KB')


if __name__ == '__main__':
    main()
