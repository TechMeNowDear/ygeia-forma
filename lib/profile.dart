/// «Τα στοιχεία μου» (7/11): ό,τι χρειάζεται για τα εύρη αναφοράς και τη μέρα ζυγίσματος. Μένουν μόνο στο κινητό
/// (στις ρυθμίσεις, κλειδί «me») και στο χειροκίνητο αντίγραφο ασφαλείας.
class Profile {
  const Profile({this.birthYear, this.birthMonth, this.sex, this.heightCm, this.weighDay = DateTime.friday});

  /// Έτος και μήνας γέννησης (αρκούν για την ηλικία· η μέρα δεν χρειάζεται).
  final int? birthYear;
  final int? birthMonth;

  /// «m» ή «f»: οι δημοσιευμένοι πίνακες (π.χ. λίπος) δίνουν χωριστά όρια για άνδρες και γυναίκες.
  final String? sex;

  /// Ύψος σε εκατοστά (για τον δείκτη μάζας σώματος και το υγιές βάρος).
  final double? heightCm;

  /// Η μέρα του εβδομαδιαίου ζυγίσματος (DateTime.monday … DateTime.sunday). Απόφαση 7/11: Παρασκευή.
  final int weighDay;

  bool get male => sex == 'm';
  bool get female => sex == 'f';

  /// Πλήρη έτη τη μέρα [day]. null αν λείπει η γέννηση.
  int? ageOn(DateTime day) {
    final y = birthYear;
    if (y == null) return null;
    final m = birthMonth ?? 1;
    var age = day.year - y;
    if (day.month < m) age--;
    return age < 0 ? null : age;
  }

  Profile copyWith({int? birthYear, int? birthMonth, String? sex, double? heightCm, int? weighDay}) => Profile(
        birthYear: birthYear ?? this.birthYear,
        birthMonth: birthMonth ?? this.birthMonth,
        sex: sex ?? this.sex,
        heightCm: heightCm ?? this.heightCm,
        weighDay: weighDay ?? this.weighDay,
      );

  Map<String, dynamic> toJson() => {
        if (birthYear != null) 'by': birthYear,
        if (birthMonth != null) 'bm': birthMonth,
        if (sex != null) 'sex': sex,
        if (heightCm != null) 'h': heightCm,
        'wd': weighDay,
      };

  static Profile fromJson(Object? j) {
    if (j is! Map) return const Profile();
    int? i(Object? v) => v is num ? v.toInt() : null;
    final by = i(j['by']);
    final bm = i(j['bm']);
    final h = j['h'] is num ? (j['h'] as num).toDouble() : null;
    final wd = i(j['wd']);
    return Profile(
      birthYear: by != null && by >= 1900 && by <= 2100 ? by : null,
      birthMonth: bm != null && bm >= 1 && bm <= 12 ? bm : null,
      sex: j['sex'] == 'm' || j['sex'] == 'f' ? j['sex'] as String : null,
      heightCm: h != null && h >= 100 && h <= 250 ? h : null,
      weighDay: wd != null && wd >= 1 && wd <= 7 ? wd : DateTime.friday,
    );
  }
}

/// Ονόματα ημερών για τη μέρα ζυγίσματος (DateTime.monday = 1).
const weekdayNames = ['Δευτέρα', 'Τρίτη', 'Τετάρτη', 'Πέμπτη', 'Παρασκευή', 'Σάββατο', 'Κυριακή'];
const weekdayShort = ['Δε', 'Τρ', 'Τε', 'Πε', 'Πα', 'Σα', 'Κυ'];
const monthNames = [
  'Ιανουάριος', 'Φεβρουάριος', 'Μάρτιος', 'Απρίλιος', 'Μάιος', 'Ιούνιος',
  'Ιούλιος', 'Αύγουστος', 'Σεπτέμβριος', 'Οκτώβριος', 'Νοέμβριος', 'Δεκέμβριος',
];
