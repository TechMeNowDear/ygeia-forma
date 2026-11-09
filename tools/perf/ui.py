#!/usr/bin/env python3
"""Βοηθός για τους ελέγχους σε emulator (smoke.sh, upgrade.sh, measure.sh), μόνο με βιβλιοθήκη της Python.

  python3 -I tools/perf/ui.py find <ui.xml> <κείμενο>   → «x y» του πρώτου στοιχείου που ΠΕΡΙΕΧΕΙ το κείμενο
                                                         (text ή content-desc· προτιμά όσα πατιούνται)· έξοδος 1 αν όχι
  python3 -I tools/perf/ui.py nodes <ui.xml>           → πόσα στοιχεία έχουν κείμενο (0 = η Flutter δεν έδωσε semantics)
  python3 -I tools/perf/ui.py screen <raw>             → ανάλυση στιγμιότυπου «adb exec-out screencap» (χωρίς -p):
                                                         τυπώνει το ποσοστό του πιο συχνού χρώματος και πόσα χρώματα·
                                                         έξοδος 1 αν η οθόνη είναι σχεδόν μονόχρωμη (κενή / γκρι / μόνο
                                                         η οθόνη εκκίνησης)
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


def find(path, want):
    hits = [n for n in _nodes(path) if want in _label(n)]
    if not hits:
        return 1
    hits.sort(key=lambda n: n.get('clickable') != 'true')
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
    sys.exit(2)
