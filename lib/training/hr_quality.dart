/// Ποιότητα των μετρήσεων παλμών μιας προπόνησης (13/11), όπως τη μέτρησε το ίδιο το ρολόι.
/// Το ρολόι μετρά πόσες τιμές ήρθαν με καλή επαφή, πόσες «χαμηλής ακρίβειας» και πόσες χωρίς επαφή (αυτές δεν μπαίνουν
/// πουθενά), και τις στέλνει μέσα στο κείμενο «diag» της προπόνησης: «5s=1 wake=1 q=5400/120/15».
/// Εδώ μόνο διαβάζονται και δείχνονται· μετά από λίγες προπονήσεις αποφασίζεται με αριθμούς αν θα πετιούνται και οι
/// «χαμηλής ακρίβειας» (τελικός έλεγχος, Συμβούλιο 1).
library;

import '../format.dart' show thousands;

class HrQualityCounts {
  const HrQualityCounts(this.ok, this.low, this.bad);
  final int ok, low, bad;
  int get total => ok + low + bad;
}

/// null αν το ρολόι δεν έστειλε καταμέτρηση (παλιότερη έκδοση) ή δεν ήρθε καμία τιμή.
HrQualityCounts? hrQualityFromDiag(String? diag) {
  // Το κινητό κρατά ως 40 χαρακτήρες από το κείμενο του ρολογιού: αν γέμισε, ο τελευταίος αριθμός ίσως κόπηκε· τίποτα.
  if (diag == null || diag.length >= 40) return null;
  final m = RegExp(r'(?:^| )q=(\d{1,9})/(\d{1,9})/(\d{1,9})(?: |$)').firstMatch(diag);
  if (m == null) return null;
  final q = HrQualityCounts(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  return q.total == 0 ? null : q;
}

/// «Μετρήσεις ρολογιού: 5.400 με καλή επαφή · 120 χαμηλής ακρίβειας · 15 χωρίς επαφή (δεν μέτρησαν).»
String hrQualityText(HrQualityCounts q) {
  if (q.low == 0 && q.bad == 0) return 'Μετρήσεις ρολογιού: ${thousands(q.ok)}, όλες με καλή επαφή.';
  return 'Μετρήσεις ρολογιού: ${thousands(q.ok)} με καλή επαφή'
      '${q.low > 0 ? ' · ${thousands(q.low)} χαμηλής ακρίβειας' : ''}'
      '${q.bad > 0 ? ' · ${thousands(q.bad)} χωρίς επαφή (δεν μέτρησαν)' : ''}.';
}
