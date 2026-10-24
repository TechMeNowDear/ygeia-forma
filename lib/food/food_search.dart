/// Αναζήτηση τροφίμων ανεκτική στα λάθη: χωρίς τόνους, κεφαλαία/πεζά, και σε greeklish
/// («ntomata» → Ντομάτα, «kotopoulo» → Κοτόπουλο). Όλα γίνονται στο κινητό, χωρίς δίκτυο.
library;

import 'food_model.dart';

const _accents = {
  'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω',
  'ϊ': 'ι', 'ΐ': 'ι', 'ϋ': 'υ', 'ΰ': 'υ', 'ς': 'σ',
};

/// Πεζά, χωρίς τόνους, τελικό σίγμα → σ.
String plain(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

// Ελληνικά → «φωνητικά» λατινικά. Τα δίψηφα πρώτα.
const _grDigraphs = {
  'ου': 'u', 'ει': 'i', 'οι': 'i', 'υι': 'i', 'αι': 'e',
  'μπ': 'b', 'ντ': 'd', 'γκ': 'g', 'γγ': 'g', 'τσ': 'ts', 'τζ': 'dz',
  'αυ': 'av', 'ευ': 'ev',
};
const _grLetters = {
  'α': 'a', 'β': 'v', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'i', 'θ': 'th', 'ι': 'i',
  'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'ks', 'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's',
  'τ': 't', 'υ': 'i', 'φ': 'f', 'χ': 'h', 'ψ': 'ps', 'ω': 'o',
};

// Greeklish → ίδια «φωνητικά» λατινικά.
const _latDigraphs = {
  'ou': 'u', 'ei': 'i', 'oi': 'i', 'ai': 'e', 'mp': 'b', 'nt': 'd', 'gk': 'g', 'gg': 'g',
  'ch': 'h', 'kh': 'h', 'ph': 'f', 'th': 'th', 'ps': 'ps', 'ks': 'ks', 'tz': 'dz',
  'au': 'av', 'eu': 'ev',
};
const _latLetters = {
  'x': 'h', 'y': 'i', 'w': 'o', 'u': 'u', 'c': 'k', 'q': 'k', 'j': 'g',
};

/// Κοινή «φωνητική» μορφή για ελληνικά και greeklish.
String phonetic(String s) {
  final p = plain(s);
  final out = StringBuffer();
  var i = 0;
  while (i < p.length) {
    final two = i + 1 < p.length ? p.substring(i, i + 2) : '';
    final ch = p[i];
    final isGreek = ch.codeUnitAt(0) >= 0x0370 && ch.codeUnitAt(0) <= 0x03FF;
    if (isGreek) {
      if (_grDigraphs.containsKey(two)) {
        out.write(_grDigraphs[two]);
        i += 2;
        continue;
      }
      out.write(_grLetters[ch] ?? ch);
      i++;
    } else {
      if (_latDigraphs.containsKey(two)) {
        out.write(_latDigraphs[two]);
        i += 2;
        continue;
      }
      // Στο greeklish το «b» είναι «μπ» και το «h» συνήθως «χ» («halvas»).
      out.write(_latLetters[ch] ?? ch);
      i++;
    }
  }
  // Διπλά γράμματα (κκ, λλ, σσ…) μετράνε ως ένα.
  return out.toString().replaceAllMapped(RegExp(r'([a-z])\1+'), (m) => m[1]!);
}

List<String> _words(String s) => s.split(RegExp(r'[^a-z0-9α-ω%]+')).where((w) => w.isNotEmpty).toList();

/// Ευρετήριο: για κάθε τρόφιμο, οι λέξεις του ονόματος και των άλλων ονομάτων σε φωνητική μορφή.
class FoodIndex {
  FoodIndex(this.foods)
      : _name = [for (final f in foods) _words(phonetic(f.name))],
        _alias = [for (final f in foods) _words(phonetic('${f.aliases.join(' ')} ${f.brand ?? ''}'))];

  final List<Food> foods;
  final List<List<String>> _name;
  final List<List<String>> _alias;

  /// [boost]: πόσο προτιμάται κάθε τρόφιμο (π.χ. πόσες φορές το έχω φάει).
  List<Food> search(String query, {Map<String, double> boost = const {}, int limit = 60}) {
    final q = _words(phonetic(query));
    if (q.isEmpty) return const [];
    final scored = <(double, int)>[];
    for (var i = 0; i < foods.length; i++) {
      var score = 0.0;
      var all = true;
      for (final w in q) {
        var best = 0.0;
        for (var k = 0; k < _name[i].length; k++) {
          final nw = _name[i][k];
          if (nw == w) {
            best = k == 0 ? 10 : 8;
          } else if (nw.startsWith(w)) {
            best = best < (k == 0 ? 7 : 5) ? (k == 0 ? 7 : 5) : best;
          } else if (w.length >= 4 && nw.contains(w)) {
            best = best < 2 ? 2 : best;
          }
        }
        for (final aw in _alias[i]) {
          if (aw == w || aw.startsWith(w)) best = best < 4 ? 4 : best;
        }
        if (best == 0) {
          all = false;
          break;
        }
        score += best;
      }
      if (!all) continue;
      final f = foods[i];
      score += (boost[f.id] ?? 0);
      if (f.isMine) score += 1.5; // τα δικά μου πρώτα (έγγραφο › Βάση τροφίμων)
      if (f.isRawWithCooked) score += 1.2; // ζυγίζω ωμά: η ωμή μορφή πριν από τη μαγειρεμένη
      score -= f.name.length / 60; // τα πιο σύντομα ονόματα λίγο πιο πάνω
      scored.add((score, i));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored.take(limit)) foods[s.$2]];
  }
}
