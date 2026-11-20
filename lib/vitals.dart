/// Πίεση, σάκχαρο και καρδιογραφήματα, γραμμένα με το χέρι (16/11).
///
/// - Πίεση: μεγάλη/μικρή (mmHg) και σφυγμοί, από πιεσόμετρο του σπιτιού. Ο μέσος όρος 7 ημερών συγκρίνεται με το όριο
///   για μετρήσεις στο σπίτι (ESC 2024: 135/85). Μία μέτρηση μόνη της δεν χαρακτηρίζεται.
/// - Σάκχαρο: mg/dL, με το πότε μετρήθηκε (νηστεία, μετά το φαγητό, τυχαία). Ο μετρητής του σπιτιού δεν κάνει διάγνωση.
/// - Καρδιογράφημα: το αποτέλεσμα όπως το έδειξε το ρολόι (το Samsung Health δεν το δίνει σε άλλες εφαρμογές).
///
/// Αρχείο vitals.json (ατομική εγγραφή, στο αντίγραφο Google και στην «Εξαγωγή αντιγράφου»). Χαλασμένο αρχείο μπαίνει
/// στην άκρη, ποτέ δεν σβήνεται.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'food/food_channel.dart';

enum VitalKind { bp, glucose, ecg }

/// Πότε μετρήθηκε το σάκχαρο.
enum GlucoseWhen { fasting, after, random }

/// Το αποτέλεσμα του καρδιογραφήματος του ρολογιού (όπως το γράφει η εφαρμογή ECG της Samsung).
enum EcgResult { sinus, afib, inconclusive, poor }

String glucoseWhenText(GlucoseWhen w) => switch (w) {
      GlucoseWhen.fasting => 'νηστεία',
      GlucoseWhen.after => '2 ώρες μετά το φαγητό',
      GlucoseWhen.random => 'τυχαία',
    };

String ecgText(EcgResult r) => switch (r) {
      EcgResult.sinus => 'Φλεβοκομβικός ρυθμός',
      EcgResult.afib => 'Κολπική μαρμαρυγή',
      EcgResult.inconclusive => 'Ασαφές',
      EcgResult.poor => 'Κακή καταγραφή',
    };

class Vital {
  const Vital({
    required this.id,
    required this.kind,
    required this.at,
    this.sys,
    this.dia,
    this.pulse,
    this.glucose,
    this.when,
    this.ecg,
    this.note,
  });

  final String id;
  final VitalKind kind;
  final DateTime at;

  /// Πίεση (mmHg) και σφυγμοί.
  final int? sys, dia, pulse;

  /// Σάκχαρο (mg/dL).
  final double? glucose;
  final GlucoseWhen? when;
  final EcgResult? ecg;
  final String? note;

  Map<String, Object> toJson() => {
        'id': id,
        'k': kind.name,
        'at': at.millisecondsSinceEpoch,
        if (sys != null) 'sys': sys!,
        if (dia != null) 'dia': dia!,
        if (pulse != null) 'pulse': pulse!,
        if (glucose != null) 'glu': glucose!,
        if (when != null) 'when': when!.name,
        if (ecg != null) 'ecg': ecg!.name,
        if (note != null && note!.isNotEmpty) 'note': note!,
      };

  /// null αν δεν είναι σωστή (λάθος είδος, τιμές έξω από όσα μετρά μια συσκευή).
  static Vital? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], k = j['k'], at = j['at'];
    if (id is! String || id.isEmpty || at is! int) return null;
    final kind = VitalKind.values.where((x) => x.name == k).firstOrNull;
    if (kind == null) return null;
    final note = j['note'] is String ? j['note'] as String : null;
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    switch (kind) {
      case VitalKind.bp:
        final s = j['sys'], d = j['dia'], p = j['pulse'];
        if (s is! int || d is! int || bpProblem(s, d, p is int ? p : null) != null) return null;
        return Vital(id: id, kind: kind, at: t, sys: s, dia: d, pulse: p is int ? p : null, note: note);
      case VitalKind.glucose:
        final g = j['glu'];
        final w = GlucoseWhen.values.where((x) => x.name == j['when']).firstOrNull;
        if (g is! num || w == null || glucoseProblem(g.toDouble()) != null) return null;
        return Vital(id: id, kind: kind, at: t, glucose: g.toDouble(), when: w, note: note);
      case VitalKind.ecg:
        final r = EcgResult.values.where((x) => x.name == j['ecg']).firstOrNull;
        if (r == null) return null;
        return Vital(id: id, kind: kind, at: t, ecg: r, note: note);
    }
  }
}

/// Τιμές που δεν βγάζει πιεσόμετρο (λάθος πληκτρολόγησης): το λέει, δεν γράφεται.
String? bpProblem(int sys, int dia, int? pulse) {
  if (sys < 60 || sys > 260) return 'Η μεγάλη (συστολική) θέλει αριθμό από 60 ως 260.';
  if (dia < 30 || dia > 160) return 'Η μικρή (διαστολική) θέλει αριθμό από 30 ως 160.';
  if (dia >= sys) return 'Η μικρή πρέπει να είναι μικρότερη από τη μεγάλη.';
  if (pulse != null && (pulse < 25 || pulse > 230)) return 'Οι σφυγμοί θέλουν αριθμό από 25 ως 230.';
  return null;
}

String? glucoseProblem(double g) => g < 20 || g > 600 ? 'Το σάκχαρο θέλει αριθμό από 20 ως 600 mg/dL.' : null;

/// Όριο για τον μέσο όρο μετρήσεων στο σπίτι (ESC 2024).
const homeBpSys = 135, homeBpDia = 85;

/// Κάτω όριο της «αυξημένης» πίεσης στο σπίτι (ESC 2024: ΑΠΟ 120/70 και κάτω από 135/85· «μη αυξημένη» κάτω από
/// 120 ΚΑΙ κάτω από 70). Έλεγχος 20/11 (K3-S-04 / K3C-02): το 120 και το 70 ακριβώς είναι ήδη «αυξημένη».
const homeBpElevSys = 120, homeBpElevDia = 70;

/// Έλεγχος 20/11 (K3-S-05): μέσος όρος σπιτιού από 160/100 και πάνω παίρνει και χρόνο («μέσα σε λίγες μέρες»). Η ESC
/// 2024 ζητά για 160–179/100–109 στο ιατρείο επιβεβαίωση «το συντομότερο, μέσα σε 1 μήνα»· όταν ο ίδιος ο μέσος όρος
/// του σπιτιού είναι τόσο, η επιβεβαίωση έχει γίνει. Δική μας, συντηρητική μεταφορά (όχι όριο της οδηγίας για το σπίτι).
const homeBpHighSys = 160, homeBpHighDia = 100;

/// Πολύ υψηλή πίεση (ESC 2024: από 180/110 έλεγχος για υπερτασική κρίση): το όριο της [bpNote] για ΜΙΑ μέτρηση, και από
/// τον ανεξάρτητο έλεγχο 20/11 (K3-review R5) και για τον μέσο όρο («μίλα σήμερα με γιατρό», όπως λέει κάθε μέτρηση).
const bpVeryHighSys = 180, bpVeryHighDia = 110;

/// Έλεγχος 17/11 (Κ6-H2): χαρακτηρισμός μόνο με μετρήσεις σε τόσες διαφορετικές μέρες και τόσες συνολικά (πρωτόκολλο
/// ESH 2021 / ESC 2024: 2 μετρήσεις πρωί και βράδυ, 7 μέρες, ποτέ λιγότερες από 3).
const bpMinDays = 3, bpMinReadings = 12;

/// Μέσος όρος πίεσης των τελευταίων [days] ημερών (ως και [now]), ή null χωρίς μετρήσεις. [d]: σε πόσες μέρες.
({double sys, double dia, int n, int d})? bpAverage(Iterable<Vital> all, DateTime now, {int days = 7}) {
  final from = DateTime(now.year, now.month, now.day - (days - 1));
  final list = [for (final v in all) if (v.kind == VitalKind.bp && !v.at.isBefore(from) && !v.at.isAfter(now)) v];
  if (list.isEmpty) return null;
  return (
    sys: list.fold(0.0, (a, v) => a + v.sys!) / list.length,
    dia: list.fold(0.0, (a, v) => a + v.dia!) / list.length,
    n: list.length,
    d: {for (final v in list) DateTime(v.at.year, v.at.month, v.at.day)}.length,
  );
}

/// Ο μέσος όρος και, με αρκετές μετρήσεις ([bpMinDays], [bpMinReadings]), τι σημαίνει κατά ESC 2024: κάτω από 120/70,
/// «αυξημένη» (Κ6-M1: πριν «κάτω από το όριο», που καθησύχαζε άδικα), ή από 135/85 και πάνω.
String bpAverageText(({double sys, double dia, int n, int d}) a) {
  final s = a.sys.round(), d = a.dia.round();
  final head = bpAverageHead(a);
  if (a.d < bpMinDays || a.n < bpMinReadings) {
    return '$head Λίγες μετρήσεις για συμπέρασμα. Μέτρα πρωί και βράδυ, 2 φορές κάθε φορά, για 7 μέρες (τουλάχιστον 3).';
  }
  if (s >= bpVeryHighSys || d >= bpVeryHighDia) {
    return '$head $bpVeryHighSys/$bpVeryHighDia και πάνω: πολύ υψηλή. Μίλα σήμερα με γιατρό· με πόνο στο στήθος ή στην '
        'πλάτη, δύσπνοια, μούδιασμα ή αδυναμία, δυσκολία στην ομιλία, θόλωμα στην όραση ή πολύ δυνατό πονοκέφαλο, 166 ή 112.';
  }
  if (s >= homeBpHighSys || d >= homeBpHighDia) {
    return '$head $homeBpHighSys/$homeBpHighDia και πάνω: πολύ πάνω από το όριο των $homeBpSys/$homeBpDia για μετρήσεις '
        'στο σπίτι (ESC 2024). Δείξ\' το στον γιατρό σου μέσα σε λίγες μέρες.';
  }
  if (s >= homeBpSys || d >= homeBpDia) {
    return '$head $homeBpSys/$homeBpDia και πάνω: πάνω από το όριο για μετρήσεις στο σπίτι (ESC 2024). Δείξ\' το στον '
        'γιατρό σου.';
  }
  if (s >= homeBpElevSys || d >= homeBpElevDia) {
    return '$head Από $homeBpElevSys/$homeBpElevDia ως κάτω από $homeBpSys/$homeBpDia: «αυξημένη» κατά ESC 2024. Με '
        'κάπνισμα ή οικογενειακό ιστορικό, δείξ\' το στον γιατρό σου.';
  }
  return '$head Κάτω από $homeBpElevSys/$homeBpElevDia: όχι αυξημένη (ESC 2024).';
}

/// «Μέσος όρος 7 ημερών: 128/82 (14 μετρήσεις σε 5 μέρες).»
String bpAverageHead(({double sys, double dia, int n, int d}) a) {
  final n = a.n == 1 ? '1 μέτρηση' : '${a.n} μετρήσεις';
  return 'Μέσος όρος 7 ημερών: ${a.sys.round()}/${a.dia.round()} ($n σε ${a.d == 1 ? '1 μέρα' : '${a.d} μέρες'}).';
}

/// Έλεγχος 20/11 (K3-S-11): η ίδια γραμμή για την ΑΝΑΦΟΡΑ ΤΟΥ ΓΙΑΤΡΟΥ. Μόνο οι αριθμοί και τα όρια· καμία προτροπή προς
/// τον ασθενή («δείξ' το στον γιατρό σου», «μέτρα πρωί και βράδυ») και κανένας χαρακτηρισμός της εφαρμογής.
String bpAverageReportText(({double sys, double dia, int n, int d}) a) {
  final head = bpAverageHead(a);
  if (a.d < bpMinDays || a.n < bpMinReadings) {
    return '$head Λίγες μετρήσεις για συμπέρασμα (λιγότερες από $bpMinReadings ή σε λιγότερες από $bpMinDays μέρες).';
  }
  return '$head Όρια για μετρήσεις στο σπίτι (ESC 2024): «αυξημένη» από $homeBpElevSys/$homeBpElevDia, υπέρταση από '
      '$homeBpSys/$homeBpDia.';
}

/// Πολύ υψηλή μέτρηση (16/11): από 180/110 (ESC 2024: σοβαρή υπέρταση). Μία μέτρηση μόνη της δεν είναι διάγνωση, αλλά
/// σε αυτά τα νούμερα λέγεται αμέσως τι να κάνεις.
String? bpNote(Vital v) {
  if (v.kind != VitalKind.bp || (v.sys! < bpVeryHighSys && v.dia! < bpVeryHighDia)) return null;
  // Κ6-L1: τα συμπτώματα της AHA (και πλάτη, μούδιασμα, ομιλία, πονοκέφαλος).
  return 'Πολύ υψηλή. Ξαναμέτρησε σε 5 λεπτά, ήρεμος. Αν μένει τόσο ψηλά, μίλα σήμερα με γιατρό· με πόνο στο στήθος ή '
      'στην πλάτη, δύσπνοια, μούδιασμα ή αδυναμία, δυσκολία στην ομιλία, θόλωμα στην όραση ή πολύ δυνατό πονοκέφαλο, 166 '
      'ή 112.';
}

/// Έλεγχος 20/11 (K3-S-02): οι σφυγμοί του πιεσόμετρου είναι παλμοί ΗΡΕΜΙΑΣ (καθιστός, 5 λεπτά), ακριβώς αυτό για το
/// οποίο το ⓘ των παλμών λέει «συχνά πάνω από 100: μίλα με τον γιατρό σου». Πάνω από 100 σε ηρεμία = ταχυκαρδία (κλασικός
/// ορισμός· BHF: «πάνω από 100 είναι πολύ γρήγορα για τους περισσότερους»)· κάτω από 40 ξύπνιος = πολύ αργοί (δική μας
/// επιλογή, χωρίς πηγή για το 40· κάτω από 60 μπορεί να είναι φυσιολογικό σε αθλητές, γι' αυτό «αν δεν είναι το
/// συνηθισμένο σου»). Πάνω από [restPulseVeryHigh] που μένει και μετά την ηρεμία: γιατρός την ίδια μέρα, όπως λέει το
/// κείμενο του ΗΚΓ (K3-review R4). Μόνο μια γραμμή δίπλα στη μέτρηση, όπως η [bpNote]· όχι ειδοποίηση.
const restPulseHigh = 100, restPulseLow = 40, restPulseVeryHigh = 120;

String? pulseNote(Vital v) {
  final p = v.pulse;
  if (v.kind != VitalKind.bp || p == null) return null;
  if (p > restPulseVeryHigh) {
    return 'Σφυγμοί πάνω από $restPulseVeryHigh σε ηρεμία. Ξαναμέτρησε μετά από 5 λεπτά ήρεμος, χωρίς τσιγάρο ή καφέ '
        'πριν. Αν μένουν πάνω από $restPulseVeryHigh, μίλα με γιατρό την ίδια μέρα· με πόνο στο στήθος, δύσπνοια, ζάλη ή '
        'λιποθυμία, 166 ή 112.';
  }
  if (p > restPulseHigh) {
    return 'Σφυγμοί πάνω από $restPulseHigh σε ηρεμία. Ξαναμέτρησε μετά από 5 λεπτά ήρεμος, χωρίς τσιγάρο ή καφέ πριν. Αν '
        'βγαίνει συχνά έτσι, πες το στον γιατρό σου· με πόνο στο στήθος, δύσπνοια, ζάλη ή λιποθυμία, 166 ή 112.';
  }
  if (p < restPulseLow) {
    return 'Πολύ αργοί σφυγμοί. Ξαναμέτρησε (το πιεσόμετρο μπορεί να μετρήσει λάθος). Αν μένουν κάτω από $restPulseLow '
        'και δεν είναι το συνηθισμένο σου, μίλα σήμερα με γιατρό· με ζάλη, λιποθυμία, δύσπνοια ή πόνο στο στήθος, 166 ή 112.';
  }
  return null;
}

/// Κάτω από τόσο το σάκχαρο λέγεται «χαμηλό» και χωρίς φάρμακα για τον διαβήτη (έλεγχος 20/11, K3-S-06). Το 70 είναι το
/// «επίπεδο 1» της ADA για ανθρώπους σε αγωγή· χωρίς αγωγή η Endocrine Society (Cryer 2009) θέλει συμπτώματα και τιμή
/// κάτω από 55 mg/dL, και ο μετρητής έχει απόκλιση ως ±15 mg/dL (ISO 15197): ένα αληθινό 80 μπορεί να φανεί 66.
const glucoseLow = 70, glucoseVeryLow = 55;

/// Σημείωση για μία μέτρηση σακχάρου (μόνο ό,τι είναι καθαρό· όχι διάγνωση).
/// Έλεγχος 17/11 (Κ6-H3, M2, L2): και πολύ υψηλό σε κάθε περίσταση (πριν: τίποτα αν δεν ήταν νηστείας), τρία σκαλιά
/// νηστείας (ADA), και ότι ο μετρητής του σπιτιού έχει απόκλιση (ISO 15197: ±15 mg/dL κάτω από 100).
String? glucoseNote(Vital v) {
  final g = v.glucose!.round();
  if (g < glucoseVeryLow) {
    return 'Κάτω από $glucoseVeryLow mg/dL: χαμηλό σάκχαρο. Πάρε 15 g γρήγορη ζάχαρη (π.χ. 150 ml χυμό) και ξαναμέτρησε σε '
        '15 λεπτά με καθαρά χέρια· αν δεν συνέρχεσαι ή έχεις σύγχυση, 166 ή 112. Πες το στον γιατρό σου.';
  }
  if (g < glucoseLow) {
    return 'Κάτω από $glucoseLow mg/dL. Ξαναμέτρησε με καθαρά χέρια (ο μετρητής έχει απόκλιση ως ±15 mg/dL). Αν νιώθεις '
        'καλά και δεν παίρνεις φάρμακα για το σάκχαρο, μια τιμή $glucoseVeryLow–${glucoseLow - 1} συνήθως δεν σημαίνει κάτι. '
        'Με συμπτώματα (τρέμουλο, ιδρώτας, σύγχυση): 15 g γρήγορη ζάχαρη (π.χ. 150 ml χυμό), ξαναμέτρησε σε 15 λεπτά· αν '
        'δεν συνέρχεσαι, 166 ή 112. Αν παίρνεις ινσουλίνη ή χάπια που ρίχνουν το σάκχαρο: 15 g ζάχαρη τώρα, και χωρίς '
        'συμπτώματα, και πες το στον γιατρό σου. Αν βγαίνει συχνά, πες το στον γιατρό σου.';
  }
  if (g >= 250) {
    return 'Πολύ υψηλό. Ξαναμέτρησε με καθαρά, στεγνά χέρια. Αν μένει ψηλά, μίλα σήμερα με γιατρό· με εμετό, έντονη '
        'δίψα, σύγχυση ή δύσπνοια, 166 ή 112.';
  }
  if (v.when == GlucoseWhen.fasting) {
    if (g < 100) {
      return 'Νηστείας κάτω από 100 mg/dL. Ο μετρητής έχει απόκλιση ως ±15 mg/dL· η διάγνωση γίνεται με εξέταση αίματος '
          '(γλυκόζη νηστείας, HbA1c).';
    }
    if (g < 126) {
      return 'Νηστείας 100–125: περιοχή προδιαβήτη (ADA), αν το επιβεβαιώσει εξέταση αίματος. Πες το στον γιατρό σου.';
    }
    return 'Νηστείας 126 και πάνω: περιοχή διαβήτη (ADA). Χρειάζεται εξέταση αίματος σύντομα· ο μετρητής δεν κάνει '
        'διάγνωση.';
  }
  if (g >= 200) {
    return '200 και πάνω: πες το σύντομα στον γιατρό σου, ειδικά αν έχεις δίψα, πολυουρία ή απώλεια βάρους. Ο μετρητής '
        'του σπιτιού δεν κάνει διάγνωση.';
  }
  return null;
}

/// Έλεγχος 17/11 (Κ6-M3): τι να κάνεις με το αποτέλεσμα του καρδιογραφήματος (όπως οι οδηγίες της Samsung).
/// Έλεγχος 20/11 (K3-S-07 και K3-review R3, οδηγίες χρήσης Samsung ECG): στην παλιά εφαρμογή (ως v1.2) «Ασαφές» = παλμοί
/// κάτω από 50, πάνω από 100 χωρίς μαρμαρυγή ή πάνω από 120, ή ρυθμός που δεν είναι ούτε φλεβοκομβικός ούτε μαρμαρυγή.
/// Στη v1.3 (οδηγίες CE 12/2024) = κάτω από 50 ή πάνω από 150, και υπάρχουν δύο νέα αποτελέσματα («Υψηλός καρδιακός
/// ρυθμός», «Κολπική μαρμαρυγή με υψηλό καρδιακό ρυθμό», 100–150) που η λίστα μας ΔΕΝ έχει (ιδέα, θέλει συμφωνία). Γι'
/// αυτό το κείμενο δεν γράφει αριθμούς που αλλάζουν με την έκδοση. «Ασαφές» δεν σημαίνει «εντάξει», και η μαρμαρυγή
/// παίρνει χρόνο («λίγες μέρες»).
String ecgNote(EcgResult r) => switch (r) {
      EcgResult.afib => 'Το ρολόι έδειξε κολπική μαρμαρυγή: δεν είναι διάγνωση, αλλά δείξ\' το στον γιατρό σου μέσα σε λίγες '
          'μέρες (κράτα και το PDF του Samsung Health Monitor). Με πόνο στο στήθος, λιποθυμία ή δύσπνοια, 166 ή 112.',
      EcgResult.inconclusive => 'Ασαφές: βγαίνει και όταν οι παλμοί είναι πολύ αργοί (κάτω από 50) ή πολύ γρήγοροι, ή όταν ο '
          'ρυθμός δεν είναι ούτε φλεβοκομβικός ούτε μαρμαρυγή· δεν σημαίνει «εντάξει». Ηρέμησε 5–10 λεπτά και ξανακάνε τη μέτρηση. Αν '
          'βγαίνει συχνά, πες το στον γιατρό σου· με φτερούγισμα, ζάλη ή παλμούς πάνω από 120 σε ηρεμία, μίλα με γιατρό την '
          'ίδια μέρα.',
      EcgResult.poor => 'Κακή καταγραφή: χέρι ακίνητο στο τραπέζι, δάχτυλο σταθερά στο κουμπί, ξανά.',
      EcgResult.sinus => 'Φλεβοκομβικός ρυθμός τη στιγμή της μέτρησης· δεν αποκλείει έμφραγμα ή άλλη καρδιοπάθεια.',
    };

abstract class VitalsIO {
  Future<({String state, String? json})> read();
  Future<bool> write(String json);
  Future<String?> setAside();
}

class ChannelVitalsIO implements VitalsIO {
  const ChannelVitalsIO();
  @override
  Future<({String state, String? json})> read() async {
    final r = await FoodChannel.vitalsRead();
    if (r['ok'] != true) return (state: r['kind'] == 'not_android' ? 'missing' : 'error', json: null);
    final j = r['json'];
    if (r['state'] == 'ok' && j is String) return (state: 'ok', json: j);
    // Απάντηση χωρίς αρχείο (ή από παλιό κανάλι χωρίς «state»): δεν υπάρχει αρχείο ακόμα.
    return (state: 'missing', json: null);
  }

  @override
  Future<bool> write(String json) async => (await FoodChannel.vitalsWrite(json))['ok'] == true;

  @override
  Future<String?> setAside() async {
    final r = await FoodChannel.vitalsBad();
    return r['ok'] == true && r['name'] is String ? r['name'] as String : null;
  }
}

class MemoryVitalsIO implements VitalsIO {
  MemoryVitalsIO([this.json]);
  String? json;
  bool failWrites = false;
  @override
  Future<({String state, String? json})> read() async => json == null ? (state: 'missing', json: null) : (state: 'ok', json: json);
  @override
  Future<bool> write(String j) async {
    if (failWrites) return false;
    json = j;
    return true;
  }

  @override
  Future<String?> setAside() async {
    json = null;
    return 'vitals.json.bad';
  }
}

class VitalsStore extends ChangeNotifier {
  VitalsStore({VitalsIO? io}) : _io = io ?? const ChannelVitalsIO();
  final VitalsIO _io;

  static VitalsStore? _main;
  static VitalsStore get main => _main ??= VitalsStore()..ensureLoaded();

  List<Vital> _all = const [];
  List<Object?> _bad = const [];
  bool read = false;
  String? error;

  /// Όλες, νεότερη πρώτη.
  List<Vital> get all => _all;
  List<Vital> of(VitalKind k) => [for (final v in _all) if (v.kind == k) v];

  Future<void>? _loading;

  /// Περιμένει να διαβαστεί το αρχείο (16/11, έλεγχος: η εξαγωγή αντιγράφου και η επαναφορά δεν περίμεναν, και οι
  /// μετρήσεις έλειπαν σιωπηλά). Αν η ανάγνωση απέτυχε, ξαναδοκιμάζει.
  Future<void> ensureLoaded() async {
    if (read) return;
    await (_loading ??= load());
    _loading = null;
  }

  Future<void> load() async {
    final r = await _io.read();
    if (r.state == 'missing') {
      _all = const [];
      read = true;
      notifyListeners();
      return;
    }
    if (r.state != 'ok') {
      read = false;
      error = 'Δεν διαβάστηκαν οι μετρήσεις. Δοκίμασε ξανά αργότερα.';
      notifyListeners();
      return;
    }
    Object? j;
    try {
      j = jsonDecode(r.json!);
    } catch (_) {
      j = null;
    }
    final list = j is Map ? j['items'] : null;
    if (list is! List) {
      final name = await _io.setAside();
      read = name != null;
      _all = const [];
      error = name == null ? 'Δεν διαβάστηκαν οι μετρήσεις.' : 'Το αρχείο των μετρήσεων δεν διαβαζόταν· κρατήθηκε ($name).';
      notifyListeners();
      return;
    }
    final ok = <Vital>[], bad = <Object?>[];
    final ids = <String>{};
    for (final x in list) {
      final v = Vital.fromJson(x);
      if (v == null || !ids.add(v.id)) {
        bad.add(x);
      } else {
        ok.add(v);
      }
    }
    _all = ok..sort((a, b) => b.at.compareTo(a.at));
    _bad = bad;
    read = true;
    notifyListeners();
  }

  String _json(List<Vital> list) => jsonEncode({
        'v': 1,
        'items': [for (final v in list) v.toJson(), ..._bad],
      });

  Future<bool> _save(List<Vital> next) async {
    if (!read) return false;
    final before = _all;
    final after = _all = [...next]..sort((a, b) => b.at.compareTo(a.at));
    notifyListeners();
    if (await _io.write(_json(after))) {
      error = null;
      return true;
    }
    // Μόνο αν δεν άλλαξε κάτι άλλο στο μεταξύ (16/11, έλεγχος: αλλιώς σβηνόταν μια νεότερη αλλαγή που γράφτηκε).
    if (identical(_all, after)) _all = before;
    error = 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.';
    notifyListeners();
    return false;
  }

  Future<bool> add(Vital v) => _save([..._all.where((x) => x.id != v.id), v]);
  Future<bool> remove(Vital v) => _save([..._all.where((x) => x.id != v.id)]);

  /// Για την «Εξαγωγή αντιγράφου».
  /// Και οι γραμμές που δεν διαβάστηκαν, όπως είναι (16/11, έλεγχος: αλλιώς χάνονταν μετά από «Διαγραφή όλων»).
  List<Object?> forBackup() => [for (final v in _all) v.toJson(), ..._bad];

  /// Επαναφορά: μπαίνουν όσες λείπουν (ίδιο id = ίδια μέτρηση). Πόσες μπήκαν, ή -1 αν δεν γράφτηκε.
  Future<int> importItems(Object? j) async {
    if (j is! List || j.isEmpty) return 0;
    await ensureLoaded();
    if (!read) return -1;
    final have = {for (final v in _all) v.id};
    final add = [for (final x in j) if (Vital.fromJson(x) case final v? when have.add(v.id)) v];
    if (add.isEmpty) return 0;
    return await _save([..._all, ...add]) ? add.length : -1;
  }

  static String newId() => 'v${DateTime.now().microsecondsSinceEpoch}';
}
