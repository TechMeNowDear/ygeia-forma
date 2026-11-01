/// Ελληνική μορφοποίηση ημερομηνιών, ωρών και αριθμών (χωρίς βιβλιοθήκες).
library;

const _weekdays = ['Δευτέρα', 'Τρίτη', 'Τετάρτη', 'Πέμπτη', 'Παρασκευή', 'Σάββατο', 'Κυριακή'];
const _weekdaysShort = ['Δευ', 'Τρί', 'Τετ', 'Πέμ', 'Παρ', 'Σάβ', 'Κυρ'];
const _monthsGen = [
  'Ιανουαρίου', 'Φεβρουαρίου', 'Μαρτίου', 'Απριλίου', 'Μαΐου', 'Ιουνίου',
  'Ιουλίου', 'Αυγούστου', 'Σεπτεμβρίου', 'Οκτωβρίου', 'Νοεμβρίου', 'Δεκεμβρίου',
];
const _monthsShort = ['Ιαν', 'Φεβ', 'Μαρ', 'Απρ', 'Μαΐ', 'Ιουν', 'Ιουλ', 'Αυγ', 'Σεπ', 'Οκτ', 'Νοε', 'Δεκ'];

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ημερολογιακές μέρες από το [a] ως το [b] (σωστά και στην αλλαγή ώρας, όπου μια μέρα κρατά 23 ή 25 ώρες).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// «Σάββατο 24 Οκτωβρίου»
String longDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_monthsGen[d.month - 1]}';

/// «Σάβ 24/10»
String shortDayDate(DateTime d) => '${_weekdaysShort[d.weekday - 1]} ${d.day}/${d.month}';

/// «Σάβ»
String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

/// «22 Αυγ»
String dayMonth(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

/// «22 Αυγ 2026»
String dayMonthYear(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]} ${d.year}';

/// «Σήμερα», «Χθες» ή «Πέμπτη».
String relativeDay(DateTime d, DateTime now) {
  final diff = daysBetween(d, now);
  if (diff == 0) return 'Σήμερα';
  if (diff == 1) return 'Χθες';
  if (diff < 7 && diff > 0) return _weekdays[d.weekday - 1];
  return dayMonth(d);
}

String two(int n) => n.toString().padLeft(2, '0');

/// «08:40»
String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String _hours(int h) => h == 1 ? '1 ώρα' : '$h ώρες';
String _minutes(int m) => m == 1 ? '1 λεπτό' : '$m λεπτά';

/// 372 → «6 ώρες 12 λεπτά», 60 → «1 ώρα», 1 → «1 λεπτό».
String hoursMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return _minutes(m);
  if (m == 0) return _hours(h);
  return '${_hours(h)} ${_minutes(m)}';
}

/// Χωριστά ο αριθμός και η λέξη, για μεγάλα νούμερα: [('6', 'ώρες'), ('12', 'λεπτά')].
List<(String, String)> hoursMinutesParts(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return [
    if (h > 0) ('$h', h == 1 ? 'ώρα' : 'ώρες'),
    if (m > 0 || h == 0) ('$m', m == 1 ? 'λεπτό' : 'λεπτά'),
  ];
}

/// 82.2 → «82,2»
String dec(num v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// 12345 → «12.345»
String thousands(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return v < 0 ? '−$b' : b.toString();
}

/// Διαφορά με πρόσημο: «+1,2», «−0,4», «0».
String signedDec(num v, [int digits = 1]) {
  final r = double.parse(v.toStringAsFixed(digits));
  if (r == 0) return '0';
  return r > 0 ? '+${dec(r, digits)}' : '−${dec(-r, digits)}';
}

/// Διαφορά λεπτών: «25 λεπτά περισσότερα», «1 ώρα 5 λεπτά λιγότερα».
String moreLessMinutes(int v) {
  if (v == 0) return 'ίδια διάρκεια';
  return v > 0 ? '${hoursMinutes(v)} περισσότερο' : '${hoursMinutes(-v)} λιγότερο';
}

/// Διαφορά λεπτών με πρόσημο: «+25 λεπτά».
String signedMinutes(int v) {
  if (v == 0) return '0 λεπτά';
  return v > 0 ? '+${hoursMinutes(v)}' : '−${hoursMinutes(-v)}';
}

/// «Καλημέρα» / «Καλησπέρα» ανάλογα με την ώρα.
String greeting(DateTime now) => (now.hour >= 4 && now.hour < 13) ? 'Καλημέρα' : 'Καλησπέρα';

/// «1 καταχώριση» / «3 καταχωρίσεις».
String countText(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';
