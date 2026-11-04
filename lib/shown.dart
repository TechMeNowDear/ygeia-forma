/// Τιμές «όπως φαίνονται»: ΕΝΑΣ κανόνας για όλες τις οθόνες (τρίτος έλεγχος, συνέπεια F1/F3/F4).
///
/// - Η διαφορά δύο νούμερων βγαίνει πάντα από τα νούμερα όπως φαίνονται (στρογγυλεμένα), ποτέ από τις ακατέργαστες
///   τιμές: «82,2 kg» και «83,4 kg» δίνουν «−1,2», όχι «−1,1» (F3).
/// - «Όπως συνήθως» λέγεται ΜΟΝΟ όταν αυτή η διαφορά είναι 0· αλλιώς «+N» ή «−N» (F1). Πριν, η Σήμερα του Oura έλεγε
///   «όπως συνήθως» για 60 με συνήθως 59 (όριο ±2) ενώ η Καρδιά έλεγε «+1 bpm · συνήθως 59».
/// - Το μέσο οξυγόνο δεν στρογγυλεύεται ποτέ προς τα πάνω στο 90% (F4): 89,5 → «89,5», όχι «90».
library;

import 'format.dart';

/// Η τιμή όπως φαίνεται με [digits] δεκαδικά.
double shownValue(double v, [int digits = 0]) =>
    digits == 0 ? v.roundToDouble() : double.parse(v.toStringAsFixed(digits));

/// Η διαφορά [value] − [usual] από τα νούμερα όπως φαίνονται (χωρίς υπόλοιπα κινητής υποδιαστολής: 0,1 − 0,3 = −0,2).
double shownDiff(double value, double usual, [int digits = 0]) =>
    shownValue(shownValue(value, digits) - shownValue(usual, digits), digits);

/// «Όπως συνήθως» μόνο όταν η διαφορά των νούμερων που φαίνονται είναι 0.
bool asUsual(double value, double usual, [int digits = 0]) => shownDiff(value, usual, digits) == 0;

const asUsualText = 'Όπως συνήθως';

/// Διαφορά με πρόσημο, όπως φαίνεται: «+2», «−1», «+0,3». Με [digits] = 0 ακέραιος.
String signedShown(double diff, [int digits = 0]) {
  final d = shownValue(diff, digits);
  if (d == 0) return '0';
  final abs = digits == 0 ? d.abs().round().toString() : dec(d.abs(), digits);
  return d > 0 ? '+$abs' : '−$abs';
}

/// Διάρκεια ύπνου σε σχέση με το «συνήθως» (σε λεπτά, όπως φαίνεται η διάρκεια): ίδιος κανόνας, «Όσο κοιμάσαι
/// συνήθως» μόνο για 0 λεπτά διαφορά.
String sleepVsUsualText(int diffMinutes) =>
    diffMinutes == 0 ? 'Όσο κοιμάσαι συνήθως' : '${moreLessMinutes(diffMinutes)} από ό,τι συνήθως';

/// Μέσο οξυγόνο της νύχτας: ακέραιο, εκτός αν η στρογγυλοποίηση θα το ανέβαζε στο 90% (89,5 → «89,5»). Η χαμηλότερη
/// μέτρηση έχει δικό της κανόνα ([lowestText] στο oxygen_note.dart: ποτέ προς τα πάνω).
String spo2AvgText(double v) {
  if (v < 90 && v.round() >= 90) {
    final f = (v * 10 + 1e-9).floorToDouble() / 10;
    return dec(f, 1);
  }
  return v.round().toString();
}

/// Κοινές φράσεις (UX U3/U4: η ίδια έννοια με την ίδια λέξη σε κάθε οθόνη).
/// Κενό της Samsung χωρίς βήματα, με παλμούς σαν του ύπνου.
const possibleSleepPhrase = 'ίσως ύπνος χωρίς καταγραφή (δεν μετρά)';

/// Η χαμηλότερη μεμονωμένη μέτρηση οξυγόνου της νύχτας.
const lowestSpo2Label = 'χαμηλότερη μέτρηση';

/// Η θερμοκρασία του Oura είναι ήδη απόκλιση από το δικό του «συνηθισμένο» (τρίτος έλεγχος F2): η εφαρμογή τη
/// δείχνει όπως είναι, με αυτή την ετικέτα, σε κάθε κάρτα.
const ouraTempDeviationLabel = 'απόκλιση από το συνηθισμένο (Oura)';
