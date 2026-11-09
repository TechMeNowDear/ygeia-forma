/// Οι παλμοί μιας προπόνησης σε δικό της μικρό αρχείο (έλεγχος 9/11, V-A-02): όχι μέσα στο training.json, που γράφεται
/// σε κάθε ✓. Συμπαγής μορφή: ~2,7 bytes ανά τιμή αντί για ~10 («[1234,118],»).
///
/// `{"v":1,"n":<πλήθος>,"s0":<πρώτο δευτερόλεπτο>,"e":"<base64>"}` — για κάθε τιμή, με τη σειρά του χρόνου: η διαφορά
/// δευτερολέπτων από την προηγούμενη (varint, χωρίς πρόσημο) και οι παλμοί (1 byte).
library;

import 'dart:convert';
import 'dart:typed_data';

const hrFileVersion = 1;

/// Ταξινομημένο αντίγραφο, χωρίς ό,τι δεν είναι ζεύγος.
List<List<int>> sortedHr(Iterable<List<int>> hr) => [
      for (final p in hr)
        if (p.length == 2) [p[0], p[1]],
    ]..sort((a, b) => a[0].compareTo(b[0]));

String encodeHr(List<List<int>> hr) {
  final s = sortedHr(hr);
  final b = BytesBuilder(copy: false);
  final s0 = s.isEmpty ? 0 : s.first[0];
  var prev = s0;
  for (final p in s) {
    var d = p[0] - prev;
    prev = p[0];
    // varint (7 bits ανά byte)
    while (d >= 0x80) {
      b.addByte((d & 0x7f) | 0x80);
      d >>= 7;
    }
    b.addByte(d);
    final v = p[1];
    b.addByte(v < 0 ? 0 : (v > 255 ? 255 : v));
  }
  return jsonEncode({'v': hrFileVersion, 'n': s.length, 's0': s0, 'e': base64.encode(b.takeBytes())});
}

/// Οι τιμές από το αρχείο· κενή λίστα αν δεν διαβάζεται (το αρχείο μένει όπως είναι). Δέχεται και απλό
/// `[[sec,bpm],…]` (ίδια μορφή με το παλιό «hr» του training.json).
List<List<int>> decodeHr(String? text) {
  if (text == null || text.isEmpty) return [];
  try {
    final j = jsonDecode(text);
    if (j is List) {
      return [
        for (final p in j)
          if (p is List && p.length == 2 && p[0] is num && p[1] is num) [(p[0] as num).toInt(), (p[1] as num).toInt()],
      ];
    }
    if (j is! Map || j['e'] is! String) return [];
    final v = j['v'];
    if (v is num && v > hrFileVersion) return [];
    final bytes = base64.decode(j['e'] as String);
    var t = (j['s0'] as num?)?.toInt() ?? 0;
    final out = <List<int>>[];
    var i = 0;
    while (i < bytes.length) {
      var d = 0, shift = 0;
      while (i < bytes.length) {
        final x = bytes[i++];
        d |= (x & 0x7f) << shift;
        shift += 7;
        if (x < 0x80) break;
      }
      if (i >= bytes.length) break;
      t += d;
      out.add([t, bytes[i++]]);
    }
    return out;
  } catch (_) {
    return [];
  }
}
