/// «Νιώθω κάτι»: συμπτώματα στην άσκηση ή στην καθημερινότητα, σε δύο βαθμίδες (έλεγχος 8/11,
/// δεύτερη ιατρική γνώμη: AHA/ACSM, Fletcher 2013, Riebe 2015, Thompson 2007).
///
/// Κόκκινα: σταμάτα, κάθισε, μην οδηγήσεις· η προπόνηση κλειδώνει μέχρι «Με είδε γιατρός».
/// Πορτοκαλί: σταματά η σημερινή, γράφεται, χωρίς κλείδωμα· δεύτερη φορά μέσα σε 14 μέρες = κόκκινο.
library;

class SymptomDef {
  const SymptomDef(this.code, this.text, {required this.red, this.callNow = false});
  final String code;
  final String text;
  final bool red;

  /// «Πάρε τώρα 166», χωρίς να περιμένεις τα 5 λεπτά.
  final bool callNow;
}

// Έλεγχος #2 (8/11): ο πόνος στο στήθος μετρά και σε ηρεμία (AHA/ACC 2021, Gulati)· ζάλη στην προσπάθεια
// κλειδώνει από την πρώτη φορά (Fletcher 2013)· νέα: λαχάνιασμα σε ηρεμία/ξαπλωμένος, πρήξιμο αστραγάλων.
// Οι παλιοί κωδικοί κρατούν το νόημά τους στις παλιές καταγραφές ([legacySymptoms]): η ορθοστατική ζάλη έχει νέο
// κωδικό ('dizzyup'), ώστε το παλιό 'dizzy' να μη διαβάζεται διαφορετικά στο ιστορικό και στην αναφορά.
const redSymptoms = [
  SymptomDef('chest', 'Πόνος, πίεση, βάρος ή σφίξιμο στο στήθος (ή σε λαιμό, σαγόνι, χέρι, πλάτη, στομάχι), στην προσπάθεια ή σε ηρεμία',
      red: true),
  SymptomDef('faint', 'Λιποθύμησα ή κόντεψα να λιποθυμήσω', red: true, callNow: true),
  SymptomDef('breath', 'Λαχάνιασμα πολύ μεγαλύτερο από την προσπάθεια, ή λαχάνιασμα σε ηρεμία ή όταν ξαπλώνω', red: true),
  SymptomDef('palp', 'Η καρδιά χτυπά ακανόνιστα ή πολύ γρήγορα και δεν ηρεμεί στο διάλειμμα', red: true),
  SymptomDef('dizzyx', 'Ζάλη την ώρα της προσπάθειας', red: true),
  SymptomDef('headache', 'Ξαφνικός πολύ δυνατός πονοκέφαλος', red: true, callNow: true),
  SymptomDef('stroke', 'Μούδιασμα ή αδυναμία στη μία πλευρά, στραβό στόμα, μπερδεμένη ομιλία', red: true, callNow: true),
];

const amberSymptoms = [
  SymptomDef('dizzyup', 'Ζάλη όταν σηκώνομαι, που περνά όταν κάτσω', red: false),
  SymptomDef('nausea', 'Ναυτία', red: false),
  SymptomDef('sweat', 'Κρύος ιδρώτας χωρίς λόγο', red: false),
  SymptomDef('tired', 'Ασυνήθιστη κούραση', red: false),
  SymptomDef('swell', 'Πρησμένοι αστράγαλοι, ή πήρα πάνω από 2 κιλά μέσα σε 3 μέρες', red: false),
  SymptomDef('other', 'Κάτι άλλο που με ανησυχεί', red: false),
];

/// Παλιοί κωδικοί που δεν προσφέρονται πια, αλλά διαβάζονται με το αρχικό τους κείμενο.
const legacySymptoms = [
  SymptomDef('dizzy', 'Ζάλη που περνά όταν κάτσω', red: false),
];

/// «166 τώρα»: ένα σύμπτωμα που το θέλει μόνο του, ή στήθος/ταχυπαλμία μαζί με ό,τι δείχνει οξύ επεισόδιο
/// (ιδρώτας, ναυτία, ζάλη, λαχάνιασμα: AHA warning signs, ESC 2023 ACS, NICE CG95).
bool callNowFor(Iterable<String> codes) {
  final s = codes.toSet();
  if (s.any((c) => symptomDef(c)?.callNow ?? false)) return true;
  const withChest = {'nausea', 'sweat', 'dizzy', 'dizzyup', 'dizzyx', 'breath', 'palp'};
  const withPalp = {'dizzy', 'dizzyup', 'dizzyx', 'breath', 'chest'};
  if (s.contains('chest') && s.any(withChest.contains)) return true;
  if (s.contains('palp') && s.any(withPalp.contains)) return true;
  return false;
}

/// Πατήθηκε «Νιώθω κάτι» στο ρολόι, χωρίς λεπτομέρειες ακόμα (τις ρωτά το κινητό).
const watchCode = 'watch';

SymptomDef? symptomDef(String code) {
  for (final d in [...redSymptoms, ...amberSymptoms, ...legacySymptoms]) {
    if (d.code == code) return d;
  }
  return null;
}

class Symptom {
  Symptom({required this.at, required this.code, this.sid, this.where});
  final DateTime at;
  final String code;

  /// Η προπόνηση που έτρεχε, αν έτρεχε.
  final String? sid;

  /// 'session' | 'walk' | 'day' | 'watch' | 'check'
  final String? where;

  bool get red => symptomDef(code)?.red ?? false;
  String get text => symptomDef(code)?.text ?? (code == watchCode ? '«Νιώθω κάτι» στο ρολόι' : code);

  Map<String, dynamic> toJson() => {'at': at.millisecondsSinceEpoch, 'c': code, if (sid != null) 'sid': sid, if (where != null) 'w': where};
  factory Symptom.fromJson(Map<String, dynamic> j) => Symptom(
        at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        code: j['c'] as String? ?? '',
        sid: j['sid'] as String?,
        where: j['w'] as String?,
      );
}

/// Τι σημαίνει μια καταγραφή.
enum SymptomOutcome { none, amber, red }
