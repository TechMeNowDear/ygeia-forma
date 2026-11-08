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
  'ou': 'u', 'oy': 'u', 'ei': 'i', 'oi': 'i', 'ai': 'e', 'mp': 'b', 'nt': 'd', 'gk': 'g', 'gg': 'g', 'ng': 'g',
  'ch': 'h', 'kh': 'h', 'ph': 'f', 'th': 'th', 'ps': 'ps', 'ks': 'ks', 'tz': 'dz',
  // Χωρίς «au → av» / «eu → ev» (έλεγχος διατροφής M7): το «giaurti» είναι γι-α-ού-ρτι, όχι «γιαβρτι».
  // Το αυ/ευ στο greeklish γράφεται συνήθως av/ev («avgo»), που ταιριάζει ήδη.
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
      // «νγκ» (μάνγκο) = «ng» στο greeklish (mango), που γίνεται g όπως το «γγ».
      if (i + 2 < p.length && p.substring(i, i + 3) == 'νγκ') {
        out.write('g');
        i += 3;
        continue;
      }
      // αυ/ευ: [af]/[ef] πριν από άηχο σύμφωνο ή στο τέλος («λευκό» = lefko, «αυτό» = afto),
      // [av]/[ev] αλλού («αυγό» = avgo). Έλεγχος 8/11, FOOD-03.
      if (two == 'αυ' || two == 'ευ') {
        final next = i + 2 < p.length ? p[i + 2] : '';
        final voiceless = next.isEmpty || 'θκξπστφχψ'.contains(next) || !_grLetters.containsKey(next);
        out.write(two == 'αυ' ? (voiceless ? 'af' : 'av') : (voiceless ? 'ef' : 'ev'));
        i += 2;
        continue;
      }
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

/// Μικρές λέξεις που δεν λένε τι είναι το τρόφιμο (σε φωνητική μορφή): των, με, σε, και, από…
/// Δεν μετρούν ούτε στο όνομα ούτε στην αναζήτηση («τόνος» δεν βρίσκει «…όλων **των** ειδών»).
const _stopWords = {
  'ton', 'tin', 'tis', 'tu', 'to', 'ta', 'ti', 'me', 'se', 'ke', 'i', 'o', 'apo', 'gia',
  'sto', 'sti', 'stin', 'ston', 'stis', 'stus', 'sta', 'ena', 'enas', 'mia',
};

List<String> _allWords(String s) => s.split(RegExp(r'[^a-z0-9α-ω%]+')).where((w) => w.isNotEmpty).toList();

List<String> _words(String s) => _allWords(s).where((w) => !_stopWords.contains(w)).toList();

/// Ρίζα λέξης (σε φωνητική μορφή), για να βρίσκονται πληθυντικοί και πτώσεις:
/// «ντομάτες» = «ντομάτα», «πιπεριές» = «πιπεριά», «φακή» = «φακές», «αμύγδαλο» = «αμύγδαλα».
/// Κλινικός/διατροφικός έλεγχος 4 (N2): χωρίς «ies»/«ia», ώστε «πιπεριές» = «πιπεριά» ≠ «πιπέρι», «μαγιά» ≠ «μάνγκο»,
/// «μοσχαρίσια» = «μοσχαρίσιο», «πρόβεια» = «πρόβειο». Το «κρεμμύδια» = «κρεμμύδι» το κρατά το [_pluralStem].
const _endings = ['es', 'as', 'os', 'is', 'us', 'on', 'a', 'e', 'i', 'o', 's'];

/// Η παλιά ρίζα των «-ια»/«-ιες» (κρεμμύδια → κρεμμύδ-, όπως κρεμμύδι), μόνο με 4+ γράμματα («μαγιά» → «mag» όχι).
/// Ταίριασμα μόνο με χαμηλό βαθμό: «πιπεριές» βγάζει πρώτα τις πιπεριές, το «πιπέρι» μετά.
String? _pluralStem(String w) {
  if (w.contains(RegExp(r'[^a-z]'))) return null;
  for (final e in const ['ies', 'ia']) {
    if (w.endsWith(e) && w.length - e.length >= 4) return w.substring(0, w.length - e.length);
  }
  return null;
}
String stem(String w) {
  if (w.length < 4 || w.contains(RegExp(r'[^a-z]'))) return w;
  for (final e in _endings) {
    if (w.endsWith(e) && w.length - e.length >= 3) return _sameStem[w.substring(0, w.length - e.length)] ?? w.substring(0, w.length - e.length);
  }
  return w;
}

/// Ρίζες με το ίδιο νόημα: «βραστά» = «βρασμένα» (έλεγχος διατροφής M7: «μακαρόνια βραστά» δεν έβρισκε τίποτα).
const _sameStem = {'vrast': 'vrasmen'};

/// Λέξη μετά από «χωρίς» δεν σημαίνει ότι το τρόφιμο είναι αυτό («Σαρδέλα, χωρίς λάδι» δεν είναι λάδι).
const _negation = 'horis';

/// Ευρετήριο: για κάθε τρόφιμο, οι λέξεις του ονόματος και τα άλλα ονόματα σε φωνητική μορφή.
///
/// Τα άλλα ονόματα με πολλές λέξεις ταιριάζουν ΜΟΝΟ ως φράση (δεύτερος έλεγχος διατροφής N1): το «ξερά σύκα»
/// μετρά μόνο όταν η αναζήτηση έχει και το «ξερά» και το «σύκα». Πριν, η σκέτη λέξη «σύκα» έδινε στο ξερό σύκο
/// (261 kcal) τον ίδιο βαθμό με το φρέσκο (68 kcal), και «καφές» έβρισκε «καφέ ρύζι».
class FoodIndex {
  FoodIndex(this.foods)
      : _name = [for (final f in foods) _words(phonetic(f.name))],
        _alias = [
          for (final f in foods)
            [
              for (final a in f.aliases)
                if (_words(phonetic(a)) case final ws when ws.isNotEmpty) ws,
              // Μάρκα: κάθε λέξη μόνη της (όπως πριν).
              for (final w in _words(phonetic(f.brand ?? ''))) [w],
            ],
        ] {
    _nameStem = [for (final ws in _name) [for (final w in ws) stem(w)]];
    _aliasStem = [for (final phrases in _alias) [for (final ws in phrases) [for (final w in ws) stem(w)]]];
  }

  final List<Food> foods;
  final List<List<String>> _name;

  /// Για κάθε τρόφιμο: τα άλλα ονόματα, το καθένα ως λίστα λέξεων (φράση).
  final List<List<List<String>>> _alias;
  late final List<List<String>> _nameStem;
  late final List<List<List<String>>> _aliasStem;

  /// Όπως [_search]· αν δεν βρεθεί τίποτα με λατινικά, δοκιμάζει και τις άλλες συνηθισμένες γραφές του
  /// greeklish: «x» για ξ («xeres» = ξερές), «h» για η («hliosporoi» = ηλιόσποροι), «au» για αυ («augo»).
  /// Η άλλη γραφή δοκιμάζεται και όταν τα αποτελέσματα είναι μόνο αδύναμα ταιριάσματα (π.χ. «xeres» → «Ντοματίνια»
  /// από ρίζα άλλου ονόματος· έλεγχος διατροφής M7), και κρατιέται αν ταιριάζει καλύτερα.
  List<Food> search(String query, {Map<String, double> boost = const {}, int limit = 60}) {
    final (r, top) = _search(query, boost: boost, limit: limit);
    if ((r.isNotEmpty && top >= _weakMatch) || query.contains(RegExp(r'[\u0370-\u03FF\u1F00-\u1FFF]'))) return r;
    final lower = query.toLowerCase();
    var best = r;
    var bestTop = r.isEmpty ? double.negativeInfinity : top;
    final variants = {
      lower.replaceAll('x', 'ks'),
      lower.replaceAll('h', 'i'),
      lower.replaceAll('x', 'ks').replaceAll('h', 'i'),
      // «augo» = αυγό: το au/eu ως αυ/ευ, μόνο ως δεύτερη γραφή (πρώτη είναι το «giaurti» = γιαούρτι).
      lower.replaceAll('au', 'av').replaceAll('eu', 'ev'),
      // «yiaourti», «yaourti» = γιαούρτι: το y/yi στην αρχή λέξης ως «γι» (τρίτος έλεγχος διατροφής N5). Μόνο ως
      // δεύτερη γραφή, άρα το «yogurt» (άλλο όνομα) δεν αλλάζει.
      lower.replaceAll(RegExp(r'\byi?'), 'gi'),
      // «levko» / «avto»: το αυ/ευ γραμμένο με v αντί για f (και ανάποδα).
      lower.replaceAll('ev', 'ef').replaceAll('av', 'af'),
      lower.replaceAll('ef', 'ev').replaceAll('af', 'av'),
    };
    for (final v in variants) {
      if (v == lower) continue;
      final (alt, altTop) = _search(v, boost: boost, limit: limit);
      if (alt.isNotEmpty && altTop > bestTop) {
        best = alt;
        bestTop = altTop;
      }
    }
    return best;
  }

  /// Κάτω από αυτό το καλύτερο αποτέλεσμα είναι μόνο ρίζα ή κομμάτι λέξης (όχι λέξη του ονόματος).
  static const _weakMatch = 5.0;

  /// Ο βαθμός του «κομματιού λέξης» (5+ γράμματα μέσα σε άλλη λέξη): χωρίς προτιμήσεις ως εκεί.
  static const _partOfWord = 2.0;

  /// [boost]: πόσο προτιμάται κάθε τρόφιμο (π.χ. πόσες φορές το έχω φάει). Επιστρέφει και τον βαθμό του πρώτου
  /// (χωρίς τις προτιμήσεις), για να ξέρει το [search] αν το ταίριασμα είναι αδύναμο.
  (List<Food>, double) _search(String query, {Map<String, double> boost = const {}, int limit = 60}) {
    final p = phonetic(query);
    // Μόνο μικρές λέξεις (π.χ. «τυ» στη μέση του «τυρί»): ψάχνουμε με αυτές, για να μη βγαίνει
    // «Δεν βρέθηκε» όσο πληκτρολογώ.
    var q = _words(p);
    if (q.isEmpty) q = _allWords(p);
    if (q.isEmpty) return (const <Food>[], 0.0);
    final qStem = [for (final w in q) stem(w)];
    // Μια φράση πολλών λέξεων ταιριάζει όταν ΚΑΘΕ λέξη της βρίσκεται στην αναζήτηση (ίδια, αρχή της, ή ίδια ρίζα).
    bool phraseInQuery(List<String> words, List<String> stems) {
      for (var k = 0; k < words.length; k++) {
        var found = false;
        for (var j = 0; j < q.length && !found; j++) {
          found = words[k] == q[j] || words[k].startsWith(q[j]) || (qStem[j].length >= 3 && stems[k] == qStem[j]);
        }
        if (!found) return false;
      }
      return true;
    }

    final scored = <(double, int)>[];
    var top = double.negativeInfinity;
    for (var i = 0; i < foods.length; i++) {
      var score = 0.0;
      var all = true;
      // Ποιες φράσεις του τροφίμου ταιριάζουν με την αναζήτηση (οι μονολεκτικές πάντα).
      final phrases = [
        for (var a = 0; a < _alias[i].length; a++)
          if (_alias[i][a].length == 1 || phraseInQuery(_alias[i][a], _aliasStem[i][a])) a,
      ];
      for (final w in q) {
        final ws = stem(w);
        final wp = _pluralStem(w);
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
          } else if (wp != null && _nameStem[i][k] == wp) {
            s = first ? 4 : 3;
          } else if (w.length >= 5 && nw.contains(w)) {
            // Κομμάτι λέξης μόνο για 5+ γράμματα: «κόλα» δεν βρίσκει «σοκολάτα», «πίτα» δεν βρίσκει «χτυπητά».
            s = 2;
          }
          if (s > 0 && k > 0 && _name[i][k - 1] == _negation) s = 1;
          if (s > best) best = s;
        }
        for (final a in phrases) {
          for (var k = 0; k < _alias[i][a].length; k++) {
            final aw = _alias[i][a][k];
            // Τα «άλλα ονόματα» είναι επιλεγμένα με το χέρι: ακριβές ταίριασμα μετρά σχεδόν όσο το όνομα.
            // Ίδια ρίζα μόνο λίγο («φέτα» ≠ «τυρί σε φέτες»).
            final s = aw == w
                ? 9.0
                : aw.startsWith(w)
                    ? 4.0
                    : (ws.length >= 3 && _aliasStem[i][a][k] == ws)
                        ? 3.0
                        : (wp != null && _aliasStem[i][a][k] == wp)
                            ? 2.0
                            : 0.0;
            if (s > best) best = s;
          }
        }
        if (best == 0) {
          all = false;
          break;
        }
        score += best;
      }
      if (!all) continue;
      final f = foods[i];
      final words = score / q.length;
      if (words > top) top = words;
      // Οι προτιμήσεις (βάση, συχνότητα) μόνο για πραγματικό ταίριασμα λέξης, όχι για κομμάτι λέξης (τρίτος έλεγχος
      // διατροφής N4: το +0,5 του γάλακτος 1,5% το ανέβαζε 2ο στο «βούτυρο» από το «…βουτυρωμένο»).
      if (words > _partOfWord) score += (boost[f.id] ?? 0);
      if (f.isMine) score += 1.5; // τα δικά μου πρώτα (έγγραφο › Βάση τροφίμων)
      if (f.isRawWithCooked) score += 1.2; // ζυγίζω ωμά: η ωμή μορφή πριν από τη μαγειρεμένη
      score -= f.name.length / 60; // τα πιο σύντομα ονόματα λίγο πιο πάνω
      scored.add((score, i));
    }
    // Μία ολόκληρη λέξη 5+ γραμμάτων που βρίσκεται μόνο ΜΕΣΑ σε άλλη λέξη (π.χ. «σαλάτα» → «Φρουτοσαλάτα»):
    // κανένα αποτέλεσμα, όχι ένα άσχετο τρόφιμο που μοιάζει με απάντηση (δεύτερος έλεγχος διατροφής N5). Η κάρτα
    // «Δεν βρέθηκε» προτείνει barcode ή υλικά ένα-ένα.
    if (q.length == 1 && q.first.length >= 5 && top <= 2) return (const <Food>[], top);
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return ([for (final s in scored.take(limit)) foods[s.$2]], top);
  }
}
