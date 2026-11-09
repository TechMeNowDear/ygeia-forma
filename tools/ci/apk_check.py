#!/usr/bin/env python3
"""Έλεγχος ενός υπογεγραμμένου APK πριν φτάσει στο κινητό ή στο ρολόι (έλεγχος 9/11, V-A-20).

Χρήση: python3 -I tools/ci/apk_check.py <αναμενόμενο SHA-256 πιστοποιητικού> <έξοδος «apksigner verify --print-certs -v»> <apk>

Αποτυγχάνει αν:
- το πιστοποιητικό δεν είναι ΑΚΡΙΒΩΣ το σταθερό (ένα άλλο κλειδί = η έκδοση δεν μπαίνει πάνω στην παλιά, και η
  απεγκατάσταση σβήνει τα δεδομένα· το ρολόι δεν μιλά με το κινητό),
- υπάρχουν περισσότεροι από ένας υπογράφοντες,
- λείπει η υπογραφή v2 (όπως όλες οι εκδόσεις ως την #89: μόνο v2),
- μια ασυμπίεστη βιβλιοθήκη .so δεν είναι στοιχισμένη στα 16 KB (Android 15+ σε συσκευές με σελίδες 16 KB),
- οποιοδήποτε άλλο ασυμπίεστο αρχείο δεν είναι στοιχισμένο στα 4 byte, ή το resources.arsc είναι συμπιεσμένο
  (το Android 11+ με targetSdk ≥ 30 ΔΕΝ εγκαθιστά τέτοιο APK — έλεγχος 9/11, M-1),
- το package δεν είναι gr.ygeiaforma.ygeia_forma ή ο versionCode δεν είναι ο αναμενόμενος (με το aapt2, στο sign_apks.sh).
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


def stored_misaligned(path):
    """Ασυμπίεστα αρχεία που δεν ξεκινούν σε όριο 4 byte, και συμπιεσμένο resources.arsc."""
    bad = []
    with open(path, 'rb') as f, zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if info.compress_type != zipfile.ZIP_STORED:
                if info.filename == 'resources.arsc':
                    bad.append('resources.arsc (συμπιεσμένο)')
                continue
            f.seek(info.header_offset)
            h = f.read(30)
            name_len, extra_len = struct.unpack('<HH', h[26:30])
            if (info.header_offset + 30 + name_len + extra_len) % 4:
                bad.append(info.filename)
    return bad


def v2_certificates(path):
    """Τα πιστοποιητικά (SHA-256 του DER) του πρώτου κάθε υπογράφοντα στο APK Signing Block v2, χωρίς εργαλεία.
    Η κρυπτογραφική επαλήθευση γίνεται από το apksigner· εδώ μόνο ΠΟΙΟ κλειδί υπέγραψε."""
    import hashlib
    data = open(path, 'rb').read()
    eocd = data.rfind(b'PK\x05\x06')
    if eocd < 0:
        return None
    cd_off = struct.unpack('<I', data[eocd + 16:eocd + 20])[0]
    if data[cd_off - 16:cd_off] != b'APK Sig Block 42':
        return None
    size = struct.unpack('<Q', data[cd_off - 24:cd_off - 16])[0]
    block = data[cd_off - size - 8:cd_off - 24]  # τα ζεύγη (μετά το πρώτο μέγεθος, πριν από το τελικό μέγεθος+magic)
    pos, value = 8, None
    while pos + 12 <= len(block):
        n, i = struct.unpack('<QI', block[pos:pos + 12])
        if i == 0x7109871a:
            value = block[pos + 12:pos + 8 + n]
        pos += 8 + n
    if value is None:
        return None

    def seq(b):
        out, p = [], 4
        end = 4 + struct.unpack('<I', b[:4])[0]
        while p < end:
            n = struct.unpack('<I', b[p:p + 4])[0]
            out.append(b[p + 4:p + 4 + n])
            p += 4 + n
        return out

    certs = []
    for signer in seq(value):
        signed = signer[4:4 + struct.unpack('<I', signer[:4])[0]]
        digests_len = struct.unpack('<I', signed[:4])[0]
        cert_list = seq(signed[4 + digests_len:])
        certs.append(hashlib.sha256(cert_list[0]).hexdigest() if cert_list else '')
    return certs


def main():
    want, verify_log, apk = sys.argv[1].lower().replace(':', ''), sys.argv[2], sys.argv[3]
    text = open(verify_log, encoding='utf-8', errors='replace').read()
    errors = []
    if not re.search(r'Verified using v2 scheme \(APK Signature Scheme v2\): true', text):
        errors.append('δεν υπάρχει υπογραφή v2')
    if not re.search(r'^Verifies\s*$', text, re.M):
        errors.append('το apksigner δεν επαλήθευσε την υπογραφή')
    # Ποιο κλειδί υπέγραψε: από το ίδιο το APK (η μορφή της εξόδου του apksigner αλλάζει από έκδοση σε έκδοση).
    certs = v2_certificates(apk) or []
    if len(certs) != 1:
        errors.append(f'περιμέναμε έναν υπογράφοντα v2, βρέθηκαν {len(certs)}')
    got = certs[0] if certs else ''
    if got != want:
        errors.append(f'άλλο πιστοποιητικό: {got[:12] or "κανένα"}… αντί για {want[:12]}…')
    n, bad = so_misaligned(apk)
    if bad:
        errors.append('βιβλιοθήκες χωρίς στοίχιση 16 KB: ' + ', '.join(bad))
    bad4 = stored_misaligned(apk)
    if bad4:
        errors.append('αρχεία χωρίς στοίχιση 4 byte (το Android δεν θα το εγκαταστήσει): ' + ', '.join(bad4[:5]))
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
    print(f'{apk}: πιστοποιητικό {got[:12]}… σωστό · σχήματα {schemes} · ασυμπίεστα στοιχισμένα (4 B) · {n} βιβλιοθήκες .so στα 16 KB')


if __name__ == '__main__':
    main()
