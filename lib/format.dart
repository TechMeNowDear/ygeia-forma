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

/// Τίτλος κάρτας με ημερομηνία όταν η τιμή ΔΕΝ είναι της μέρας που περιμένει ο χρήστης (έλεγχος 4/11, A11):
/// «Θερμίδες που έκαψες · Τρ 3/11». [day]: η μέρα της τιμής (για τιμές νύχτας: το πρωί που τελείωσε)·
/// [expected]: η μέρα που θα ήταν «φρέσκια» (σήμερα, ή για τη νύχτα το σημερινό πρωί). Χωρίς τιμή: σκέτος τίτλος.
String datedTitle(String title, DateTime? day, DateTime expected) =>
    day == null || sameDay(day, expected) ? title : '$title · ${shortDayDate(day)}';

String two(int n) => n.toString().padLeft(2, '0');

/// «08:40»
String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String _hours(int h) => h == 1 ? '1 ώρα' : '$h ώρες';
String _minutes(int m) => m == 1 ? '1 λεπτό' : '$m λεπτά';

/// 372 → «6 ώρες 12 λεπτά», 60 → «1 ώρα», 1 → «1 λεπτό», −5 → «−5 λεπτά».
String hoursMinutes(int minutes) {
  if (minutes < 0) return '−${hoursMinutes(-minutes)}';
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

/// 82.2 → «82,2». Ποτέ «-0,0»: μια τιμή που στρογγυλεύεται στο μηδέν γράφεται χωρίς πρόσημο.
String dec(num v, [int digits = 1]) {
  final s = v.toStringAsFixed(digits);
  final zero = double.parse(s) == 0;
  return (zero && s.startsWith('-') ? s.substring(1) : s).replaceAll('.', ',');
}

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
/// Σύντομη διάρκεια για στενές στήλες: 436 → «7 ώρ. 16 λεπ.», 22 → «22 λεπ.», 420 → «7 ώρ.».
String hoursMinutesShort(int minutes) {
  if (minutes < 0) return '−${hoursMinutesShort(-minutes)}';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m λεπ.';
  return m == 0 ? '$h ώρ.' : '$h ώρ. $m λεπ.';
}

String moreLessMinutes(int v) {
  if (v == 0) return 'ίδια διάρκεια';
  return v > 0 ? '${hoursMinutes(v)} περισσότερο' : '${hoursMinutes(-v)} λιγότερο';
}

/// Διαφορά λεπτών με πρόσημο: «+25 λεπτά».
String signedMinutes(int v) {
  if (v == 0) return '0 λεπτά';
  return v > 0 ? '+${hoursMinutes(v)}' : '−${hoursMinutes(-v)}';
}

/// Χρονόμετρο (σχέδια 9/11): 1471 → «24:31», 3730 → «1:02:10». Στρογγυλεύει πρώτα, άρα ποτέ «10:60».
String clock(num seconds) {
  final t = seconds.round().abs();
  final h = t ~/ 3600, m = t % 3600 ~/ 60, r = t % 60;
  final s = h > 0 ? '$h:${two(m)}:${two(r)}' : '$m:${two(r)}';
  return seconds.round() < 0 ? '−$s' : s;
}

/// Ρυθμός, ίδιος σε κινητό, ρολόι και PDF (σχέδια 9/11): 675 → «11:15 /km». Στρογγυλεύει ΠΡΙΝ χωρίσει σε λεπτά
/// και δευτερόλεπτα: 659,5 → «11:00 /km», ποτέ «10:60».
String paceText(num secPerKm) => '${clock(secPerKm)} /km';

/// «Καλημέρα» / «Καλησπέρα» ανάλογα με την ώρα.
String greeting(DateTime now) => (now.hour >= 4 && now.hour < 13) ? 'Καλημέρα' : 'Καλησπέρα';

/// «1 καταχώριση» / «3 καταχωρίσεις».
String countText(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

/// Κεφαλαία ελληνικά χωρίς τόνους («Προπόνηση» → «ΠΡΟΠΟΝΗΣΗ»), όπως γράφονται σωστά (έλεγχος 8/11, UX-14).
String upperGr(String s) {
  const strip = {'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω', 'ΐ': 'ϊ', 'ΰ': 'ϋ',
    'Ά': 'Α', 'Έ': 'Ε', 'Ή': 'Η', 'Ί': 'Ι', 'Ό': 'Ο', 'Ύ': 'Υ', 'Ώ': 'Ω'};
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(strip[ch] ?? ch);
  }
  return b.toString().toUpperCase();
}
