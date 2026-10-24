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
  final diff = dayOf(now).difference(dayOf(d)).inDays;
  if (diff == 0) return 'Σήμερα';
  if (diff == 1) return 'Χθες';
  if (diff < 7 && diff > 0) return _weekdays[d.weekday - 1];
  return dayMonth(d);
}

String two(int n) => n.toString().padLeft(2, '0');

/// «08:40»
String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

/// 372 → «6 ώ 12 λ»
String hoursMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m λ';
  if (m == 0) return '$h ώ';
  return '$h ώ $m λ';
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

/// Διαφορά λεπτών: «+25 λ», «−1 ώ 5 λ».
String signedMinutes(int v) {
  if (v == 0) return '0 λ';
  return v > 0 ? '+${hoursMinutes(v)}' : '−${hoursMinutes(-v)}';
}
