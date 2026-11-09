/// Αναζήτηση τροφίμων ανεκτική στα λάθη: χωρίς τόνους, κεφαλαία/πεζά, και σε greeklish
/// («ntomata» → Ντομάτα, «kotopoulo» → Κοτόπουλο). Όλα γίνονται στο κινητό, χωρίς δίκτυο.
library;

import 'dart:math' as math;

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
/// Έλεγχος 9/11 (Υ3): και η γενική σε -ου/-ιού/-εως («στήθος κοτόπουλου», «χυμός πορτοκαλιού», «ολικής αλέσεως»).
const _endings = ['eos', 'es', 'as', 'os', 'is', 'us', 'iu', 'on', 'a', 'e', 'i', 'o', 'u', 's'];

/// Η παλιά ρίζα των «-ια»/«-ιες» (κρεμμύδια → κρεμμύδ-, όπως κρεμμύδι), μόνο με 4+ γράμματα («μαγιά» → «mag» όχι).
/// Ταίριασμα μόνο με χαμηλό βαθμό: «πιπεριές» βγάζει πρώτα τις πιπεριές, το «πιπέρι» μετά.
String? _pluralStem(String w) {
  if (w.contains(RegExp(r'[^a-z]'))) return null;
  for (final e in const ['ies', 'ia']) {
    if (w.endsWith(e) && w.length - e.length >= 4) return w.substring(0, w.length - e.length);
  }
  return null;
}

/// [synonyms]: και οι ρίζες με το ίδιο νόημα ([_sameStem]). Χωρίς αυτές μόνο για το «ακριβές ταίριασμα όλης της
/// αναζήτησης» (το «φούρνου» βρίσκει το «ψητό», αλλά δεν είναι ακριβώς το «κοτόπουλο φούρνου»).
String stem(String w, {bool synonyms = true}) {
  if (w.length < 4 || w.contains(RegExp(r'[^a-z]'))) return w;
  for (final e in _endings) {
    if (w.endsWith(e) && w.length - e.length >= 3) {
      final b = w.substring(0, w.length - e.length);
      return synonyms ? (_sameStem[b] ?? b) : b;
    }
  }
  return w;
}

/// Ρίζες με το ίδιο νόημα: «βραστά» = «βρασμένα» (έλεγχος διατροφής M7), «άσπρο» = «λευκό», «γάλακτος» = «γάλα»,
/// «κρέατος» = «κρέας», «φούρνου» = «σχάρας» = «ψητό» (έλεγχος 9/11, Υ3).
const _sameStem = {
  'vrast': 'vrasmen',
  'aspr': 'lefk',
  'galakt': 'gal',
  'kreat': 'kre',
  'furn': 'psit',
  'shar': 'psit',
};

/// Λέξη μετά από «χωρίς» δεν σημαίνει ότι το τρόφιμο είναι αυτό («Σαρδέλα, χωρίς λάδι» δεν είναι λάδι).
const _negation = 'horis';

/// Ίδια ρίζα, άλλο νόημα (έλεγχος 9/11, Υ2): «τσίπουρο» (ποτό) ≠ «τσιπούρα» (ψάρι).
const _homonyms = [
  {'tsipuro', 'tsipuru'},
];

bool _homonym(String a, String b) {
  for (final g in _homonyms) {
    if (g.contains(a) != g.contains(b)) return true;
  }
  return false;
}

/// Λέξεις που λένε κομμάτι ή μορφή και όχι ποιο τρόφιμο είναι: δεν χρειάζεται να ταιριάξουν
/// («φιλέτο σολομού» → σολομός). Μετρούν μόνο αν ταιριάζουν.
final _optional = {
  for (final w in const ['φιλέτο', 'φιλέτα', 'φιλετάκι', 'φιλετάκια', 'κομμάτι', 'κομμάτια', 'μερίδα', 'σπιτικό', 'σπιτικός',
    'σπιτική', 'σπιτικά', 'σπιτικές', 'σπιτικοί'])
    phonetic(w),
};

/// «Σημαδεμένες» παραλλαγές, με πολύ περισσότερο αλάτι ή ζάχαρη ανά 100 g από το απλό τρόφιμο (έλεγχος 9/11, Ν1):
/// πάνε κάτω από το απλό, εκτός αν η αναζήτηση τις ζητά («μπακαλιάρος παστός», «σύκα ξερά»).
final _marked = {for (final w in const ['παστός', 'αλατισμένος', 'αλίπαστος', 'καπνιστός', 'μαρινάτος']) stem(phonetic(w))};
final _markedCat = {
  'Αποξηραμένα φρούτα': [for (final w in const ['ξερά', 'αποξηραμένα']) stem(phonetic(w))],
};
const _markedPenalty = 3.0;

/// Όλη η αναζήτηση είναι ακριβώς ένα άλλο όνομα ή η «κεφαλή» του ονόματος (ό,τι είναι πριν από την παρένθεση ή το
/// κόμμα): «σύκο» → «Σύκο (φρέσκο)», όχι «Σύκο ξερό»· «λάδι ελιάς» → ελαιόλαδο· «μπιζέλια» → αρακάς.
const _exactBonus = 4.0;

/// Κατηγορίες: «ψάρι» φέρνει τα ψάρια, «κρέας» το κρέας (έλεγχος 9/11, Υ3). Μόνο όταν η λέξη δεν ταιριάζει αλλιώς στο
/// τρόφιμο· βαθμός κάτω από την πρώτη λέξη ονόματος, αλλά πάνω από ρίζα σε άλλη λέξη («φρούτα» → τα φρούτα πριν από
/// το «Ζελέ φρούτων»).
const _catTerms = {
  'Κρέας': ['κρέας', 'κρέατα'],
  'Πουλερικά': ['πουλερικά', 'πουλερικό', 'κρέας'],
  'Αλλαντικά': ['αλλαντικά', 'αλλαντικό'],
  'Ψάρια': ['ψάρι', 'ψάρια'],
  'Θαλασσινά': ['θαλασσινά', 'θαλασσινό'],
  'Γαλακτοκομικά': ['γαλακτοκομικά', 'γαλακτοκομικό'],
  'Τυριά': ['τυρί', 'τυριά'],
  'Αυγά': ['αυγό', 'αυγά'],
  'Όσπρια': ['όσπρια', 'όσπριο'],
  'Λαχανικά': ['λαχανικά', 'λαχανικό', 'ζαρζαβατικά'],
  'Πατάτες': ['πατάτα', 'πατάτες'],
  'Φρούτα': ['φρούτο', 'φρούτα'],
  'Αποξηραμένα φρούτα': ['αποξηραμένα φρούτα', 'ξερά φρούτα', 'αποξηραμένα'],
  'Ξηροί καρποί': ['ξηροί καρποί', 'ξηρός καρπός', 'ξηροκάρπια'],
  'Σπόροι': ['σπόροι', 'σπόρος'],
  'Δημητριακά': ['δημητριακά'],
  'Ζυμαρικά': ['ζυμαρικά'],
  'Γλυκά': ['γλυκά', 'γλυκό'],
  'Ροφήματα': ['ροφήματα', 'ρόφημα', 'ποτά', 'ποτό'],
  'Σάλτσες': ['σάλτσες', 'σάλτσα'],
  'Καρυκεύματα': ['καρυκεύματα', 'μπαχαρικά'],
  'Έτοιμα φαγητά': ['έτοιμο φαγητό', 'έτοιμα φαγητά'],
  'Συμπληρώματα': ['συμπληρώματα', 'συμπλήρωμα'],
};
const _catScore = 6.0;

/// Συστατικό μετά από «με» («Πουρές πατάτας (με γάλα και βούτυρο)»): μετρά λίγο, όπως το κομμάτι λέξης. Αλλιώς το
/// «λαχανικά» θα έβγαζε πρώτη την «πίτα … με λαχανικά» και το «βούτυρο» τον πουρέ.
const _ingredientCap = 2.0;

/// Λέξεις τρόπου μαγειρέματος: αν η αναζήτηση βρει αποτέλεσμα μόνο χωρίς αυτές («χταπόδι ψητό»), οι μαγειρεμένες
/// μορφές μπαίνουν πρώτες.
final _cooking = {
  for (final w in const ['ψητό', 'βραστό', 'βρασμένο', 'σχάρας', 'φούρνου', 'τηγανητό', 'μαγειρεμένο', 'ατμού', 'στιφάδο',
    'κοκκινιστό', 'πανέ'])
    stem(phonetic(w)),
};

final _tokenSplit = RegExp(r'[^0-9a-zα-ωάέήίόύώϊϋΐΰς%]+');

/// Για κάθε λέξη του ονόματος (ίδια σειρά με τις λέξεις του ευρετηρίου): αν είναι συστατικό μετά από «με».
List<bool> _ingredientFlags(String name) {
  final out = <bool>[];
  for (final seg in phonetic(name).split(RegExp(r'[(),]'))) {
    var after = false;
    for (final t in _allWords(seg)) {
      if (t == 'me') {
        after = true;
        continue;
      }
      if (_stopWords.contains(t)) continue;
      out.add(after);
    }
  }
  return out;
}

/// Απόσταση το πολύ ενός γράμματος: αντικατάσταση, προσθήκη, αφαίρεση ή αντιμετάθεση δύο διπλανών.
bool _oneEdit(String a, String b) {
  if (a == b) return true;
  final la = a.length, lb = b.length;
  if ((la - lb).abs() > 1) return false;
  if (la == lb) {
    final d = [for (var k = 0; k < la; k++) if (a[k] != b[k]) k];
    if (d.length == 1) return true;
    return d.length == 2 && d[1] == d[0] + 1 && a[d[0]] == b[d[1]] && a[d[1]] == b[d[0]];
  }
  final s = la < lb ? a : b, l = la < lb ? b : a;
  var k = 0;
  while (k < s.length && s[k] == l[k]) {
    k++;
  }
  return s.substring(k) == l.substring(k + 1);
}

/// Αποτέλεσμα αναζήτησης, με ό,τι χρειάστηκε για να βρεθεί κάτι.
class FoodSearchResult {
  const FoodSearchResult(this.foods,
      {this.ignored = const [], this.corrected = const {}, this.kept = const [], this.droppedFood = false});
  final List<Food> foods;

  /// Οι λέξεις (όπως γράφτηκαν) με τις οποίες βρέθηκαν τα αποτελέσματα, όταν κάποιες αγνοήθηκαν.
  final List<String> kept;

  /// Αγνοήθηκε λέξη που είναι τρόφιμο της βάσης, δηλαδή η πρώτη λέξη κάποιου ονόματος (π.χ. «γιαούρτι με μέλι» →
  /// γιαούρτι): τα αποτελέσματα είναι άλλο τρόφιμο. Όχι για επίθετα («μήλο πράσινο») ή άγνωστες λέξεις («ελληνικός»).
  final bool droppedFood;

  /// Λέξεις της αναζήτησης που αγνοήθηκαν (όπως γράφτηκαν), γιατί με αυτές δεν βρισκόταν τίποτα.
  final List<String> ignored;

  /// Λέξη με ένα λάθος γράμμα → η λέξη που βρέθηκε («κοτόπολο» → «κοτόπουλο»).
  final Map<String, String> corrected;

  static const empty = FoodSearchResult(<Food>[]);
}

/// Ευρετήριο: για κάθε τρόφιμο, οι λέξεις του ονόματος, τα άλλα ονόματα και η κατηγορία, σε φωνητική μορφή.
///
/// Τα άλλα ονόματα με πολλές λέξεις ταιριάζουν ΜΟΝΟ ως φράση (δεύτερος έλεγχος διατροφής N1): το «ξερά σύκα»
/// μετρά μόνο όταν η αναζήτηση έχει και το «ξερά» και το «σύκα». Πριν, η σκέτη λέξη «σύκα» έδινε στο ξερό σύκο
/// (261 kcal) τον ίδιο βαθμό με το φρέσκο (68 kcal), και «καφές» έβρισκε «καφέ ρύζι».
///
/// Κατάταξη (έλεγχος 9/11, Υ2), από το πιο ισχυρό στο πιο αδύναμο:
/// 1. όλη η αναζήτηση είναι ακριβώς ένα άλλο όνομα ή η κεφαλή του ονόματος (+4)·
/// 2. κάθε λέξη: πρώτη λέξη ονόματος 10, άλλη λέξη 8, άλλο όνομα 9, αρχή/ρίζα 7–2, κατηγορία 6·
/// 3. τροποποιητές: παστό/αλατισμένο/καπνιστό/μαρινάτο/αποξηραμένο φρούτο −3 όταν δεν ζητήθηκε, ωμό με μαγειρεμένες
///    μορφές +1,2, τα δικά μου +1,5, προτιμήσεις και ιστορικό, μήκος ονόματος·
/// 4. σε ισοπαλία, η σειρά της λίστας (η Dart δεν ταξινομεί «σταθερά»· χωρίς αυτό η σειρά άλλαζε από κινητό σε κινητό).
/// Η ίδια λογική υπάρχει σε Python (tools/food/search_port.py)· το test/food_search_fix_test.dart ελέγχει ότι συμφωνούν.
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
        ],
        _cat = [
          for (final f in foods) [for (final t in _catTerms[f.cat] ?? const <String>[]) _words(phonetic(t))],
        ],
        _head = [for (final f in foods) _words(phonetic(f.name.split(RegExp(r'[(,]')).first))],
        _ingredient = [for (final f in foods) _ingredientFlags(f.name)] {
    _nameStem = [for (final ws in _name) [for (final w in ws) stem(w)]];
    _aliasStem = [for (final phrases in _alias) [for (final ws in phrases) [for (final w in ws) stem(w)]]];
    _aliasBase = [
      for (final phrases in _alias) [for (final ws in phrases) [for (final w in ws) stem(w, synonyms: false)]],
    ];
    _catStem = [for (final phrases in _cat) [for (final ws in phrases) [for (final w in ws) stem(w)]]];
    _headBase = [for (final ws in _head) [for (final w in ws) stem(w, synonyms: false)]];
    _foodHeads = {for (final ws in _name) if (ws.isNotEmpty) stem(ws.first)};
    _markedOf = [
      for (var i = 0; i < foods.length; i++)
        {
          for (final s in _nameStem[i])
            if (_marked.contains(s)) s,
          ...?_markedCat[foods[i].cat],
        },
    ];
    final vocab = <String, String>{};
    for (final f in foods) {
      for (final src in [f.name, ...f.aliases]) {
        for (final raw in src.toLowerCase().split(_tokenSplit)) {
          if (raw.isEmpty) continue;
          final ws = _words(phonetic(raw));
          if (ws.length == 1 && ws.first.length >= 6) vocab.putIfAbsent(ws.first, () => raw);
        }
      }
    }
    _vocab = vocab;
    _vocabSorted = vocab.keys.toList()..sort();
  }

  final List<Food> foods;
  final List<List<String>> _name;

  /// Για κάθε τρόφιμο: τα άλλα ονόματα, το καθένα ως λίστα λέξεων (φράση).
  final List<List<List<String>>> _alias;
  final List<List<List<String>>> _cat;
  final List<List<String>> _head;
  final List<List<bool>> _ingredient;
  late final List<List<String>> _nameStem;
  late final List<List<List<String>>> _aliasStem;
  late final List<List<List<String>>> _aliasBase;
  late final List<List<List<String>>> _catStem;
  late final List<List<String>> _headBase;
  late final List<Set<String>> _markedOf;

  /// Ρίζες της πρώτης λέξης κάθε ονόματος: «λέξη που είναι τρόφιμο» (ρύζι, μέλι, ζάχαρη, χοιρινό).
  late final Set<String> _foodHeads;

  /// Λέξεις (6+ γράμματα) των ονομάτων σε φωνητική μορφή → όπως γράφονται, για τη διόρθωση ενός γράμματος.
  late final Map<String, String> _vocab;
  late final List<String> _vocabSorted;

  List<Food> search(String query, {Map<String, double> boost = const {}, int limit = 60}) =>
      find(query, boost: boost, limit: limit).foods;

  /// Όπως [search], και αν δεν βρεθεί τίποτα (έλεγχος 9/11, Υ3 και V-C-11):
  /// 1. διορθώνει ένα λάθος γράμμα σε λέξη 6+ γραμμάτων που δεν ταιριάζει πουθενά («κοτόπολο», «γιαουτρι»)·
  /// 2. αφήνει έξω τις λέξεις που δεν ταιριάζουν σε κανένα τρόφιμο («μέλι θυμαρίσιο» → μέλι)·
  /// 3. αν κάθε λέξη ταιριάζει κάπου αλλά όχι όλες μαζί, αφήνει έξω μία (κρατά το καλύτερο ταίριασμα).
  /// Η οθόνη λέει ποια λέξη αγνοήθηκε ή διορθώθηκε, για να μη μοιάζει ότι βρέθηκε ακριβώς αυτό.
  FoodSearchResult find(String query, {Map<String, double> boost = const {}, int limit = 60}) {
    final r = _withVariants(query, boost: boost, limit: limit);
    if (r.isNotEmpty) return FoodSearchResult(r);
    final p = phonetic(query);
    var q = _words(p);
    if (q.isEmpty) q = _allWords(p);
    if (q.isEmpty) return FoodSearchResult.empty;
    // Πώς γράφτηκε κάθε λέξη, για το μήνυμα («χωρίς τη λέξη «θυμαρίσιο»»).
    final typed = <String, String>{};
    for (final raw in query.toLowerCase().split(_tokenSplit)) {
      for (final w in _allWords(phonetic(raw))) {
        typed.putIfAbsent(w, () => raw);
      }
    }
    String show(String w) => typed[w] ?? _vocab[w] ?? w;
    // Η αναζήτηση λέει «χωρίς»: μόνο τότε μια λέξη μετά το «χωρίς» στο όνομα μετρά ως ταίριασμα.
    final neg = q.contains(_negation);

    // 1. Ένα λάθος γράμμα.
    final corrected = <String, String>{};
    final q2 = [...q];
    for (var k = 0; k < q.length; k++) {
      final w = q[k];
      // Λέξη που υπάρχει ήδη στα ονόματα (π.χ. μέσα σε φράση) δεν είναι λάθος γράμμα («καλαμάκι» ≠ «καλαμάρι»).
      if (w.length < 6 || _vocab.containsKey(w) || _matchesAny(w, neg)) continue;
      for (final v in _vocabSorted) {
        if (v != w && v[0] == w[0] && _oneEdit(w, v)) {
          q2[k] = v;
          corrected[typed[w] ?? w] = _vocab[v]!;
          break;
        }
      }
    }
    if (corrected.isNotEmpty) {
      final (r1, _) = _search(q2.join(' '), boost: boost, limit: limit, isPhonetic: true);
      if (r1.isNotEmpty) return FoodSearchResult(r1, corrected: corrected);
    }
    // 2. Χωρίς τις λέξεις που δεν ταιριάζουν πουθενά.
    final keep = [for (final w in q2) if (_matchesAny(w, neg)) w];
    final dropped = [for (final w in q2) if (!_matchesAny(w, neg)) w];
    if (keep.isNotEmpty && dropped.isNotEmpty) {
      final (r2, _) = _search(keep.join(' '),
          boost: boost, limit: limit, isPhonetic: true, cookedFirst: dropped.any((w) => _cooking.contains(stem(w))));
      if (r2.isNotEmpty) {
        // Οι λέξεις αυτού του βήματος δεν υπάρχουν πουθενά στη βάση, άρα δεν είναι τρόφιμο της βάσης (droppedFood = false).
        // Αν αλλάζουν τη διατροφή («σόγιας», «μπάρα»), την έντονη προειδοποίηση τη βγάζει η οθόνη από τη λέξη.
        return FoodSearchResult(r2,
            ignored: [for (final w in dropped) show(w)], kept: [for (final w in keep) show(w)], corrected: corrected);
      }
    }
    // 3. Χωρίς μία λέξη — ποτέ χωρίς την ΠΡΩΤΗ (το ίδιο το τρόφιμο): «σοκολάτα χωρίς ζάχαρη» δεν γίνεται «μούσλι χωρίς
    // ζάχαρη», «ψωμί χωρίς αλάτι» δεν γίνεται «ρύζι χωρίς αλάτι» (ανεξάρτητος έλεγχος του fix-food, 3.1).
    if (keep.length >= 2) {
      List<Food>? best;
      var bestTop = double.negativeInfinity;
      String? left;
      for (var k = 1; k < keep.length; k++) {
        final rest = [...keep.sublist(0, k), ...keep.sublist(k + 1)];
        final (r3, top) = _search(rest.join(' '),
            boost: boost, limit: limit, isPhonetic: true, cookedFirst: _cooking.contains(stem(keep[k])));
        if (r3.isNotEmpty && (best == null || top > bestTop)) {
          best = r3;
          bestTop = top;
          left = keep[k];
        }
      }
      if (best != null) {
        return FoodSearchResult(best,
            ignored: [for (final w in dropped) show(w), show(left!)],
            kept: [for (final w in keep) if (w != left) show(w)],
            corrected: corrected,
            droppedFood: _foodHeads.contains(stem(left)));
      }
      // 3β. Μόνο η πρώτη λέξη (το τρόφιμο), χωρίς τους προσδιορισμούς.
      final (r4, _) = _search(keep.first, boost: boost, limit: limit, isPhonetic: true);
      if (r4.isNotEmpty) {
        return FoodSearchResult(r4,
            ignored: [for (final w in dropped) show(w), for (final w in keep.skip(1)) show(w)],
            kept: [show(keep.first)],
            corrected: corrected,
            droppedFood: keep.skip(1).any((w) => _foodHeads.contains(stem(w))));
      }
    }
    return FoodSearchResult.empty;
  }

  /// Ταιριάζει η λέξη σε κάποιο τρόφιμο (με το όνομα, ένα μονολεκτικό άλλο όνομα ή την κατηγορία);
  bool _matchesAny(String w, bool negQuery) {
    final ws = stem(w), wp = _pluralStem(w);
    for (var i = 0; i < foods.length; i++) {
      if (_wordScore(i, w, ws, wp, null, null, negQuery) > 0) return true;
    }
    return false;
  }

  /// Όπως [_search]· αν δεν βρεθεί τίποτα με λατινικά, δοκιμάζει και τις άλλες συνηθισμένες γραφές του
  /// greeklish: «x» για ξ («xeres» = ξερές), «h» για η («hliosporoi» = ηλιόσποροι), «au» για αυ («augo»).
  /// Η άλλη γραφή δοκιμάζεται και όταν τα αποτελέσματα είναι μόνο αδύναμα ταιριάσματα (π.χ. «xeres» → «Ντοματίνια»
  /// από ρίζα άλλου ονόματος· έλεγχος διατροφής M7), και κρατιέται αν ταιριάζει καλύτερα.
  List<Food> _withVariants(String query, {Map<String, double> boost = const {}, int limit = 60}) {
    final (r, top) = _search(query, boost: boost, limit: limit);
    if ((r.isNotEmpty && top >= _weakMatch) || query.contains(RegExp(r'[Ͱ-Ͽἀ-῿]'))) return r;
    final lower = query.toLowerCase();
    var best = r;
    var bestTop = r.isEmpty ? double.negativeInfinity : top;
    // «leuko», «leyko», «gayros» = λευκό, γαύρος: το au/eu/ay/ey πριν από σύμφωνο ως αυ/ευ (έλεγχος 9/11, Χ1),
    // και μετά το v/f όπως στη «λευκό» (lefko). Μόνο ως δεύτερη γραφή: το «giaurti» μένει γιαούρτι.
    final chain = lower.replaceAllMapped(RegExp(r'([ae])[uy](?=[b-df-hj-np-tv-z])'), (m) => '${m[1]}v');
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
      chain,
      chain.replaceAll('ev', 'ef').replaceAll('av', 'af'),
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

  /// Πόσο ταιριάζει μία λέξη της αναζήτησης στο τρόφιμο [i]. [phrases]/[catPhrases]: ποια άλλα ονόματα και
  /// κατηγορίες μετρούν· null = μόνο τα μονολεκτικά (για το «ταιριάζει κάπου;»).
  /// [negQuery]: η αναζήτηση έχει «χωρίς».
  double _wordScore(int i, String w, String ws, String? wp, List<int>? phrases, List<int>? catPhrases, bool negQuery) {
    var best = 0.0;
    final name = _name[i];
    for (var k = 0; k < name.length; k++) {
      final nw = name[k];
      final first = k == 0;
      var s = 0.0;
      if (nw == w) {
        s = first ? 10 : 8;
      } else if (_homonym(w, nw)) {
        s = 0;
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
      // Λέξη μετά το «χωρίς» στο όνομα: ταιριάζει (λίγο) μόνο αν και η αναζήτηση λέει «χωρίς» — αλλιώς το «αυγό σε λάδι»
      // έβρισκε σιωπηλά το «αυγό χωρίς λάδι» (ανεξάρτητος έλεγχος του fix-food, 3.2).
      if (s > 0 && k > 0 && name[k - 1] == _negation) s = negQuery ? 1 : 0;
      if (s > _ingredientCap && k < _ingredient[i].length && _ingredient[i][k]) s = _ingredientCap;
      if (s > best) best = s;
    }
    final aliases = phrases ?? [for (var a = 0; a < _alias[i].length; a++) if (_alias[i][a].length == 1) a];
    for (final a in aliases) {
      for (var k = 0; k < _alias[i][a].length; k++) {
        final aw = _alias[i][a][k];
        // Τα «άλλα ονόματα» είναι επιλεγμένα με το χέρι: ακριβές ταίριασμα μετρά σχεδόν όσο το όνομα.
        // Ίδια ρίζα μόνο λίγο («φέτα» ≠ «τυρί σε φέτες»).
        final s = aw == w
            ? 9.0
            : _homonym(w, aw)
                ? 0.0
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
      final cats = catPhrases ?? [for (var c = 0; c < _cat[i].length; c++) if (_cat[i][c].length == 1) c];
      for (final c in cats) {
        for (var k = 0; k < _cat[i][c].length; k++) {
          if (_cat[i][c][k] == w || (ws.length >= 3 && _catStem[i][c][k] == ws)) best = _catScore;
        }
      }
    }
    return best;
  }

  /// [boost]: πόσο προτιμάται κάθε τρόφιμο (π.χ. πόσες φορές το έχω φάει). Επιστρέφει και τον βαθμό του πρώτου
  /// (χωρίς τις προτιμήσεις), για να ξέρει το [search] αν το ταίριασμα είναι αδύναμο.
  /// [isPhonetic]: η [query] είναι ήδη σε φωνητική μορφή. [cookedFirst]: οι μαγειρεμένες μορφές πρώτες.
  (List<Food>, double) _search(
    String query, {
    Map<String, double> boost = const {},
    int limit = 60,
    bool isPhonetic = false,
    bool cookedFirst = false,
  }) {
    final p = isPhonetic ? query : phonetic(query);
    // Μόνο μικρές λέξεις (π.χ. «τυ» στη μέση του «τυρί»): ψάχνουμε με αυτές, για να μη βγαίνει
    // «Δεν βρέθηκε» όσο πληκτρολογώ.
    var q = _words(p);
    if (q.isEmpty) q = _allWords(p);
    if (q.isEmpty) return (const <Food>[], 0.0);
    final qStem = [for (final w in q) stem(w)];
    final qBase = [for (final w in q) stem(w, synonyms: false)];
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

    // Όλη η αναζήτηση = αυτή η φράση (ίδιες λέξεις ή ρίζες, με οποιαδήποτε σειρά).
    bool sameAsQuery(List<String> words, List<String> bases) {
      if (words.length != q.length) return false;
      final used = <int>{};
      for (var j = 0; j < q.length; j++) {
        var hit = -1;
        for (var k = 0; k < words.length && hit < 0; k++) {
          if (!used.contains(k) && (words[k] == q[j] || (qBase[j].length >= 3 && bases[k] == qBase[j]))) hit = k;
        }
        if (hit < 0) return false;
        used.add(hit);
      }
      return true;
    }

    final required = {for (final w in q) if (!_optional.contains(w)) w};
    final neg = q.contains(_negation);
    if (required.isEmpty) required.addAll(q);

    final scored = <(double, int)>[];
    var top = double.negativeInfinity;
    for (var i = 0; i < foods.length; i++) {
      var score = 0.0;
      var all = true;
      var counted = 0;
      // Ποιες φράσεις του τροφίμου ταιριάζουν με την αναζήτηση (οι μονολεκτικές πάντα).
      final phrases = [
        for (var a = 0; a < _alias[i].length; a++)
          if (_alias[i][a].length == 1 || phraseInQuery(_alias[i][a], _aliasStem[i][a])) a,
      ];
      final catPhrases = [
        for (var c = 0; c < _cat[i].length; c++)
          if (_cat[i][c].length == 1 || phraseInQuery(_cat[i][c], _catStem[i][c])) c,
      ];
      for (final w in q) {
        final best = _wordScore(i, w, stem(w), _pluralStem(w), phrases, catPhrases, neg);
        if (best == 0) {
          if (required.contains(w)) {
            all = false;
            break;
          }
          continue;
        }
        score += best;
        counted++;
      }
      if (!all) continue;
      final f = foods[i];
      final words = score / math.max(1, counted);
      if (words > top) top = words;
      // Οι προτιμήσεις (βάση, συχνότητα) μόνο για πραγματικό ταίριασμα λέξης, όχι για κομμάτι λέξης (τρίτος έλεγχος
      // διατροφής N4: το +0,5 του γάλακτος 1,5% το ανέβαζε 2ο στο «βούτυρο» από το «…βουτυρωμένο»).
      if (words > _partOfWord) score += (boost[f.id] ?? 0);
      var exact = sameAsQuery(_head[i], _headBase[i]);
      for (var a = 0; a < _alias[i].length && !exact; a++) {
        exact = sameAsQuery(_alias[i][a], _aliasBase[i][a]);
      }
      if (exact) score += _exactBonus;
      final marked = _markedOf[i];
      if (marked.isNotEmpty &&
          !q.any((w) => marked.contains(stem(w)) || (w.length >= 3 && marked.any((m) => m.startsWith(w))))) {
        score -= _markedPenalty;
      }
      if (f.isMine) score += 1.5; // τα δικά μου πρώτα (έγγραφο › Βάση τροφίμων)
      if (f.isRawWithCooked) score += 1.2; // ζυγίζω ωμά: η ωμή μορφή πριν από τη μαγειρεμένη
      if (cookedFirst && f.rawId != null) score += 2.5;
      score -= f.name.length / 60; // τα πιο σύντομα ονόματα λίγο πιο πάνω
      scored.add((score, i));
    }
    // Μία ολόκληρη λέξη 5+ γραμμάτων που βρίσκεται μόνο ΜΕΣΑ σε άλλη λέξη (π.χ. «σαλάτα» → «Φρουτοσαλάτα»):
    // κανένα αποτέλεσμα, όχι ένα άσχετο τρόφιμο που μοιάζει με απάντηση (δεύτερος έλεγχος διατροφής N5). Η κάρτα
    // «Δεν βρέθηκε» προτείνει barcode ή υλικά ένα-ένα.
    if (q.length == 1 && q.first.length >= 5 && top <= 2) return (const <Food>[], top);
    // Σε ισοπαλία, η σειρά της λίστας (σταθερή σε κάθε κινητό).
    scored.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return ([for (final s in scored.take(limit)) foods[s.$2]], top);
  }
}
