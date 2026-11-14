#!/usr/bin/env python3
"""Βοηθός για τους ελέγχους σε emulator (smoke.sh, upgrade.sh, measure.sh), μόνο με βιβλιοθήκη της Python.

  python3 -I tools/perf/ui.py find <ui.xml> <κείμενο>   → «x y» του πρώτου στοιχείου που ΠΕΡΙΕΧΕΙ το κείμενο
                                                         (text ή content-desc· προτιμά όσα πατιούνται)· έξοδος 1 αν όχι
  python3 -I tools/perf/ui.py nodes <ui.xml>           → πόσα στοιχεία έχουν κείμενο (0 = η Flutter δεν έδωσε semantics)
  python3 -I tools/perf/ui.py screen <raw>             → ανάλυση στιγμιότυπου «adb exec-out screencap» (χωρίς -p):
                                                         τυπώνει το ποσοστό του πιο συχνού χρώματος και πόσα χρώματα·
                                                         έξοδος 1 αν η οθόνη είναι σχεδόν μονόχρωμη (κενή / γκρι / μόνο
                                                         η οθόνη εκκίνησης)
  python3 -I tools/perf/ui.py anr <ui.xml>             → αν η οθόνη δείχνει παράθυρο «… isn't responding» ΑΛΛΗΣ
                                                         διεργασίας (π.χ. «System UI»): τυπώνει το όνομά της, έξοδος 0·
                                                         αλλιώς (ή αν είναι η δική μας εφαρμογή) έξοδος 1
"""
import struct
import sys
import xml.etree.ElementTree as ET
from collections import Counter


def _nodes(path):
    try:
        return list(ET.parse(path).getroot().iter('node'))
    except (ET.ParseError, OSError):
        return []


def _label(n):
    return (n.get('text') or '') + '\n' + (n.get('content-desc') or '')


def _first(n):
    return [(n.get('text') or '').split('\n')[0].strip(), (n.get('content-desc') or '').split('\n')[0].strip()]


def _bottom(n):
    try:
        return int(n.get('bounds', '').split('][')[1].split(',')[1].rstrip(']'))
    except (IndexError, ValueError):
        return 0


def find(path, want):
    hits = [n for n in _nodes(path) if want in _label(n)]
    if not hits:
        return 1
    # Προτίμηση (έλεγχος 9/11, S-10): 1) η ΠΡΩΤΗ γραμμή είναι ακριβώς το κείμενο (π.χ. η καρτέλα «Άσκηση», όχι μια κάρτα
    # «Άσκηση σήμερα…»), 2) πατιέται, 3) το χαμηλότερο στην οθόνη (η κάτω μπάρα είναι κάτω από το περιεχόμενο).
    hits.sort(key=lambda n: (want not in _first(n), n.get('clickable') != 'true', -_bottom(n)))
    b = hits[0].get('bounds', '')
    try:
        (x1, y1), (x2, y2) = [tuple(int(v) for v in p.split(',')) for p in b.strip('[]').split('][')]
    except ValueError:
        return 1
    print((x1 + x2) // 2, (y1 + y2) // 2)
    return 0


def nodes(path):
    print(sum(1 for n in _nodes(path) if _label(n).strip()))
    return 0


# Γύρος 7: στον emulator του CI το «System UI isn't responding» βγαίνει μερικές φορές αμέσως μετά την εκκίνηση, πάνω από
# όλα, και το uiautomator βλέπει μόνο αυτό (3 αποτυχίες στη σειρά, ενώ η ίδια έκδοση πέρασε σε άλλο runner). Δεν είναι
# της εφαρμογής: ο έλεγχος πατά «Wait» και συνεχίζει, με προειδοποίηση. Αν το παράθυρο είναι για τη ΔΙΚΗ μας εφαρμογή
# (το όνομά της ή το πακέτο), ΔΕΝ το αγγίζει: ο έλεγχος αποτυγχάνει κανονικά.
OWN = ('Υγεία', 'Φόρμα', 'ygeia', 'ygeiaforma')


def anr(path):
    for n in _nodes(path):
        t = (n.get('text') or '').strip()
        for tail in (" isn't responding", ' δεν αποκρίνεται'):
            if t.endswith(tail):
                who = t[:-len(tail)].strip()
                if any(o.lower() in who.lower() for o in OWN):
                    return 1
                print(who)
                return 0
    return 1


def screen(path, limit=0.97):
    data = open(path, 'rb').read()
    if len(data) < 16:
        print('κενό στιγμιότυπο')
        return 1
    w, h, fmt = struct.unpack('<III', data[:12])
    # Από το Android 9 η κεφαλίδα έχει και χρωματικό χώρο (16 bytes)· αλλιώς 12.
    head = 16 if len(data) >= 16 + w * h * 4 else 12
    px = data[head:head + w * h * 4]
    if len(px) < w * h * 4 or w == 0 or h == 0:
        print(f'άγνωστη μορφή στιγμιότυπου ({w}x{h}, {len(data)} bytes)')
        return 1
    # Δείγμα: κάθε 8ο pixel σε κάθε 8η γραμμή, χωρίς τη γραμμή κατάστασης (πάνω 5%) και την πλοήγηση (κάτω 5%).
    c = Counter()
    for y in range(h // 20, h - h // 20, 8):
        row = y * w * 4
        for x in range(0, w, 8):
            i = row + x * 4
            c[px[i:i + 3]] += 1
    total = sum(c.values())
    top = c.most_common(1)[0][1] / total
    print(f'{w}x{h} · πιο συχνό χρώμα {top:.0%} · {len(c)} χρώματα')
    return 1 if top >= limit else 0


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'find':
        sys.exit(find(sys.argv[2], sys.argv[3]))
    if cmd == 'nodes':
        sys.exit(nodes(sys.argv[2]))
    if cmd == 'screen':
        sys.exit(screen(sys.argv[2]))
    if cmd == 'anr':
        sys.exit(anr(sys.argv[2]))
    sys.exit(2)
