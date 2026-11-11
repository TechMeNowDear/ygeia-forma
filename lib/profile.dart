/// «Τα στοιχεία μου» (7/11): ό,τι χρειάζεται για τα εύρη αναφοράς, τους στόχους και τις μέρες ζυγίσματος. Μένουν μόνο
/// στο κινητό (στις ρυθμίσεις, κλειδί «me») και στο χειροκίνητο αντίγραφο ασφαλείας.
///
/// Απόφαση 11/11: ζύγισμα 3 φορές την εβδομάδα (Δευτέρα, Τετάρτη, Παρασκευή πρωί) και μέση με μεζούρα την Παρασκευή.
class Profile {
  const Profile({
    this.birthYear,
    this.birthMonth,
    this.sex,
    this.heightCm,
    this.weighDays = defaultWeighDays,
    this.waistDay = DateTime.friday,
  });

  /// Έτος και μήνας γέννησης (αρκούν για την ηλικία· η μέρα δεν χρειάζεται).
  final int? birthYear;
  final int? birthMonth;

  /// «m» ή «f»: οι δημοσιευμένοι πίνακες (π.χ. λίπος) δίνουν χωριστά όρια για άνδρες και γυναίκες.
  final String? sex;

  /// Ύψος σε εκατοστά (για τον δείκτη μάζας σώματος και το υγιές βάρος).
  final double? heightCm;

  /// Οι μέρες ζυγίσματος (DateTime.monday … DateTime.sunday). Τουλάχιστον μία.
  final Set<int> weighDays;

  /// Η μέρα της μέσης με μεζούρα.
  final int waistDay;

  static const defaultWeighDays = {DateTime.monday, DateTime.wednesday, DateTime.friday};

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

  Profile copyWith({int? birthYear, int? birthMonth, String? sex, double? heightCm, Set<int>? weighDays, int? waistDay}) => Profile(
        birthYear: birthYear ?? this.birthYear,
        birthMonth: birthMonth ?? this.birthMonth,
        sex: sex ?? this.sex,
        heightCm: heightCm ?? this.heightCm,
        weighDays: weighDays == null || weighDays.isEmpty ? this.weighDays : weighDays,
        waistDay: waistDay ?? this.waistDay,
      );

  Map<String, dynamic> toJson() => {
        if (birthYear != null) 'by': birthYear,
        if (birthMonth != null) 'bm': birthMonth,
        if (sex != null) 'sex': sex,
        if (heightCm != null) 'h': heightCm,
        'wds': (weighDays.toList()..sort()),
        'wad': waistDay,
        // Για παλιότερη έκδοση της εφαρμογής (μία μέρα ζυγίσματος): η μέρα της μέσης.
        'wd': waistDay,
      };

  static Profile fromJson(Object? j) {
    if (j is! Map) return const Profile();
    int? i(Object? v) => v is num ? v.toInt() : null;
    bool day(int? d) => d != null && d >= 1 && d <= 7;
    final by = i(j['by']);
    final bm = i(j['bm']);
    final h = j['h'] is num ? (j['h'] as num).toDouble() : null;
    final wd = i(j['wd']);
    final wds = <int>{
      if (j['wds'] is List)
        for (final x in j['wds'] as List)
          if (day(i(x))) i(x)!,
    };
    final wad = i(j['wad']);
    // Από την έκδοση με μία μέρα ζυγίσματος (7/11): η προεπιλογή ήταν Παρασκευή. Αν ο χρήστης είχε διαλέξει άλλη μέρα,
    // κρατιέται αυτή· αλλιώς ισχύει η απόφαση 11/11 (Δευτέρα, Τετάρτη, Παρασκευή).
    final Set<int> days = wds.isNotEmpty
        ? wds
        : (day(wd) && wd != DateTime.friday ? {wd!} : defaultWeighDays);
    return Profile(
      birthYear: by != null && by >= 1900 && by <= 2100 ? by : null,
      birthMonth: bm != null && bm >= 1 && bm <= 12 ? bm : null,
      sex: j['sex'] == 'm' || j['sex'] == 'f' ? j['sex'] as String : null,
      heightCm: h != null && h >= 100 && h <= 250 ? h : null,
      weighDays: days,
      waistDay: day(wad) ? wad! : (day(wd) ? wd! : DateTime.friday),
    );
  }
}

/// Ονόματα ημερών για τη μέρα ζυγίσματος (DateTime.monday = 1).
const weekdayNames = ['Δευτέρα', 'Τρίτη', 'Τετάρτη', 'Πέμπτη', 'Παρασκευή', 'Σάββατο', 'Κυριακή'];
const weekdayChips = ['Δε', 'Τρ', 'Τε', 'Πε', 'Πα', 'Σα', 'Κυ'];
const monthNames = [
  'Ιανουάριος', 'Φεβρουάριος', 'Μάρτιος', 'Απρίλιος', 'Μάιος', 'Ιούνιος',
  'Ιούλιος', 'Αύγουστος', 'Σεπτέμβριος', 'Οκτώβριος', 'Νοέμβριος', 'Δεκέμβριος',
];
