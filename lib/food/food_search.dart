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
  'ou': 'u', 'ei': 'i', 'oi': 'i', 'ai': 'e', 'mp': 'b', 'nt': 'd', 'gk': 'g', 'gg': 'g', 'ng': 'g',
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

/// Ρίζα λέξης (σε φωνητική μορφή), για να βρίσκονται πληθυντικοί και πτώσεις:
/// «ντομάτες» = «ντομάτα», «πιπεριές» = «πιπεριά», «φακή» = «φακές», «αμύγδαλο» = «αμύγδαλα».
const _endings = ['ies', 'ia', 'es', 'as', 'os', 'is', 'us', 'on', 'a', 'e', 'i', 'o', 's'];
String stem(String w) {
  if (w.length < 4 || w.contains(RegExp(r'[^a-z]'))) return w;
  for (final e in _endings) {
    if (w.endsWith(e) && w.length - e.length >= 3) return w.substring(0, w.length - e.length);
  }
  return w;
}

/// Λέξη μετά από «χωρίς» δεν σημαίνει ότι το τρόφιμο είναι αυτό («Σαρδέλα, χωρίς λάδι» δεν είναι λάδι).
const _negation = 'horis';

/// Ευρετήριο: για κάθε τρόφιμο, οι λέξεις του ονόματος και των άλλων ονομάτων σε φωνητική μορφή.
class FoodIndex {
  FoodIndex(this.foods)
      : _name = [for (final f in foods) _words(phonetic(f.name))],
        _alias = [for (final f in foods) _words(phonetic('${f.aliases.join(' ')} ${f.brand ?? ''}'))] {
    _nameStem = [for (final ws in _name) [for (final w in ws) stem(w)]];
    _aliasStem = [for (final ws in _alias) [for (final w in ws) stem(w)]];
  }

  final List<Food> foods;
  final List<List<String>> _name;
  final List<List<String>> _alias;
  late final List<List<String>> _nameStem;
  late final List<List<String>> _aliasStem;

  /// Όπως [_search]· αν δεν βρεθεί τίποτα με λατινικά, δοκιμάζει και τις άλλες συνηθισμένες γραφές του
  /// greeklish: «x» για ξ («xeres» = ξερές) και «h» για η («hliosporoi» = ηλιόσποροι).
  List<Food> search(String query, {Map<String, double> boost = const {}, int limit = 60}) {
    final r = _search(query, boost: boost, limit: limit);
    if (r.isNotEmpty || query.contains(RegExp(r'[\u0370-\u03FF\u1F00-\u1FFF]'))) return r;
    final lower = query.toLowerCase();
    for (final v in {lower.replaceAll('x', 'ks'), lower.replaceAll('h', 'i'), lower.replaceAll('x', 'ks').replaceAll('h', 'i')}) {
      if (v == lower) continue;
      final alt = _search(v, boost: boost, limit: limit);
      if (alt.isNotEmpty) return alt;
    }
    return r;
  }

  /// [boost]: πόσο προτιμάται κάθε τρόφιμο (π.χ. πόσες φορές το έχω φάει).
  List<Food> _search(String query, {Map<String, double> boost = const {}, int limit = 60}) {
    final q = _words(phonetic(query));
    if (q.isEmpty) return const [];
    final scored = <(double, int)>[];
    for (var i = 0; i < foods.length; i++) {
      var score = 0.0;
      var all = true;
      for (final w in q) {
        final ws = stem(w);
        var best = 0.0;
        for (var k = 0; k < _name[i].length; k++) {
          final nw = _name[i][k];
          final first = k == 0;
          var s = 0.0;
          if (nw == w) {
            s = first ? 10 : 8;
          } else if (nw.startsWith(w)) {
            s = first ? 7 : 5;
          } else if (ws.length >= 3 && _nameStem[i][k] == ws) {
            s = first ? 7 : 5;
          } else if (w.length >= 4 && nw.contains(w)) {
            s = 2;
          }
          if (s > 0 && k > 0 && _name[i][k - 1] == _negation) s = 1;
          if (s > best) best = s;
        }
        for (var k = 0; k < _alias[i].length; k++) {
          final aw = _alias[i][k];
          // Τα «άλλα ονόματα» είναι επιλεγμένα με το χέρι: ακριβές ταίριασμα μετρά σχεδόν όσο το όνομα.
          final s = aw == w
              ? 9.0
              : (ws.length >= 3 && _aliasStem[i][k] == ws)
                  ? 6.0
                  : aw.startsWith(w)
                      ? 4.0
                      : 0.0;
          if (s > best) best = s;
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
