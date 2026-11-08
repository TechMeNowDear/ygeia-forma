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

const redSymptoms = [
  SymptomDef('chest', 'Πόνος, πίεση ή σφίξιμο στο στήθος (ή λαιμό, σαγόνι, χέρι, πλάτη) που ήρθε με την προσπάθεια', red: true),
  SymptomDef('faint', 'Λιποθύμησα ή κόντεψα να λιποθυμήσω', red: true, callNow: true),
  SymptomDef('breath', 'Λαχάνιασμα πολύ μεγαλύτερο από την προσπάθεια, που δεν περνά με ξεκούραση', red: true),
  SymptomDef('palp', 'Η καρδιά χτυπά ακανόνιστα ή πολύ γρήγορα και δεν ηρεμεί στο διάλειμμα', red: true),
  SymptomDef('headache', 'Ξαφνικός πολύ δυνατός πονοκέφαλος', red: true, callNow: true),
  SymptomDef('stroke', 'Μούδιασμα ή αδυναμία στη μία πλευρά, στραβό στόμα, μπερδεμένη ομιλία', red: true, callNow: true),
];

const amberSymptoms = [
  SymptomDef('dizzy', 'Ζάλη που περνά όταν κάτσω', red: false),
  SymptomDef('nausea', 'Ναυτία', red: false),
  SymptomDef('tired', 'Ασυνήθιστη κούραση', red: false),
];

/// Πατήθηκε «Νιώθω κάτι» στο ρολόι, χωρίς λεπτομέρειες ακόμα (τις ρωτά το κινητό).
const watchCode = 'watch';

SymptomDef? symptomDef(String code) {
  for (final d in [...redSymptoms, ...amberSymptoms]) {
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
