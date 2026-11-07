// Widgets αρχικής οθόνης (απόφαση χρήστη 7/11): τι δείχνει και πώς φαίνεται κάθε widget.
//
// Το σχήμα το ζωγραφίζει ΕΝΑΣ ζωγράφος, στην Kotlin (WidgetRenderer.kt), και για την αρχική οθόνη και για την
// προεπισκόπηση της οθόνης ρύθμισης· εδώ είναι μόνο οι επιλογές (JSON) και οι κατάλογοι.

/// Τα τέσσερα είδη widget.
class WKind {
  static const sleep = 'sleep';
  static const move = 'move';
  static const food = 'food';
  static const body = 'body';
  static const all = [sleep, move, food, body];

  static String title(String k) => switch (k) {
        sleep => 'Ύπνος',
        move => 'Κίνηση',
        food => 'Φαγητό',
        _ => 'Σώμα',
      };
}

/// Μία τιμή που μπορεί να μπει στο widget: κλειδί του στιγμιότυπου (widget_snapshot.dart) και όνομα στη ρύθμιση.
class WMetric {
  const WMetric(this.key, this.name);
  final String key;
  final String name;
}

/// Οι τιμές κάθε είδους, με τη σειρά που φαίνονται στη ρύθμιση. Η πρώτη είναι η προεπιλεγμένη κεντρική τιμή.
const wMetrics = <String, List<WMetric>>{
  WKind.sleep: [
    WMetric('sleepMin', 'Διάρκεια ύπνου'),
    WMetric('energy', 'Ετοιμότητα'),
    WMetric('sleepScore', 'Σκορ ύπνου'),
    WMetric('hrv', 'HRV'),
    WMetric('sleepHr', 'Παλμοί στον ύπνο'),
    WMetric('lowHr', 'Χαμηλότεροι παλμοί'),
    WMetric('ringSpo2', 'Οξυγόνο (μέσος όρος)'),
    WMetric('breath', 'Αναπνοές'),
    WMetric('skinTemp', 'Θερμοκρασία'),
  ],
  WKind.move: [
    WMetric('steps', 'Βήματα'),
    WMetric('activeKcal', 'Ενεργές θερμίδες'),
    WMetric('totalKcal', 'Σύνολο θερμίδων'),
    WMetric('activeMin', 'Ενεργός χρόνος'),
    WMetric('floors', 'Όροφοι'),
    WMetric('distance', 'Απόσταση'),
    WMetric('dayHr', 'Παλμοί ξύπνιος (χθες)'),
  ],
  WKind.food: [
    WMetric('kcal', 'Θερμίδες'),
    WMetric('protein', 'Πρωτεΐνη'),
    WMetric('carbs', 'Υδατάνθρακες'),
    WMetric('fat', 'Λιπαρά'),
    WMetric('fiber', 'Ίνες'),
    WMetric('salt', 'Αλάτι'),
    WMetric('sugars', 'Σάκχαρα'),
  ],
  WKind.body: [
    WMetric('weight', 'Βάρος'),
    WMetric('fatPct', 'Λίπος'),
    WMetric('smm', 'Σκελετικοί μύες'),
    WMetric('ffm', 'Άλιπη μάζα'),
    WMetric('bmr', 'Μεταβολισμός ηρεμίας'),
    WMetric('bmi', 'Δείκτης μάζας σώματος'),
    WMetric('water', 'Νερό σώματος'),
  ],
};

/// Οι προεπιλεγμένες τιμές στα κουτάκια (χωρίς την κεντρική).
const wDefaultValues = <String, List<String>>{
  WKind.sleep: ['energy', 'sleepScore', 'hrv', 'ringSpo2', 'sleepHr', 'breath'],
  WKind.move: ['activeKcal', 'totalKcal', 'activeMin', 'floors', 'distance', 'dayHr'],
  WKind.food: ['protein', 'carbs', 'fat', 'fiber', 'salt', 'sugars'],
  WKind.body: ['fatPct', 'smm', 'ffm', 'bmr', 'bmi', 'water'],
};

/// Έτοιμα χρώματα: φόντο πάνω, φόντο κάτω, τόνος. «Μπορντό» η προεπιλογή (απόφαση χρήστη 7/11).
class WTheme {
  const WTheme(this.id, this.name, this.c1, this.c2, this.acc, this.op);
  final String id;
  final String name;
  final int c1;
  final int c2;
  final int acc;
  final int op;
}

const wThemes = <WTheme>[
  WTheme('bordeaux', 'Μπορντό', 0xFF4A070C, 0xFF050203, 0xFFFF9C8A, 92),
  WTheme('aegean', 'Αιγαίο', 0xFF1D5BD8, 0xFF0A1A3F, 0xFF7FD3FF, 85),
  WTheme('night', 'Νύχτα', 0xFF2A3C96, 0xFF141C45, 0xFF8C9CFF, 90),
  WTheme('olive', 'Ελιά', 0xFF5E7E2E, 0xFF1C2610, 0xFFC9E08A, 85),
  WTheme('graphite', 'Γραφίτης', 0xFF3A3D46, 0xFF111216, 0xFFF2CC5C, 80),
  WTheme('paper', 'Χαρτί', 0xFFFFFFFF, 0xFFEFEAE6, 0xFFA3202A, 92),
];

/// «Ταπετσαρία»: χρώματα από την ταπετσαρία (Material You) και ανοιχτό/σκοτεινό μαζί με το κινητό.
/// Τα υπολογίζει η Kotlin τη στιγμή της ζωγραφικής.
const wWallpaperTheme = 'wallpaper';

/// Χρώματα για «χρώμα ανά τιμή» (απαλά, διαβάζονται σε σκούρο και ανοιχτό φόντο).
const wValueColors = <int>[
  0xFFFF9C8A, 0xFFF2CC5C, 0xFF7DDB9C, 0xFF7FD3FF, 0xFFA9B4FF, 0xFFE9A6FF, 0xFFFFFFFF, 0xFF17141F,
];

/// Τι ανοίγει το πάτημα.
class WTap {
  static const section = 'section';
  static const today = 'today';
  static const metric = 'metric';
  static const add = 'add';
}

/// Οι ρυθμίσεις ενός widget. Αποθηκεύονται στην Kotlin ανά widget (SharedPreferences «home_widgets»).
class WidgetStyle {
  WidgetStyle({
    required this.kind,
    String? hero,
    List<String>? values,
    Map<String, int>? valueColors,
    this.theme = 'bordeaux',
    this.c1 = 0xFF4A070C,
    this.c2 = 0xFF050203,
    this.acc = 0xFFFF9C8A,
    this.textColor,
    this.gradient = true,
    this.direction = 0,
    this.opacity = 92,
    this.radius = 22,
    this.fontScale = 1.0,
    this.glow = true,
    this.border = true,
    this.shadow = false,
    this.showTitle = true,
    this.showSource = true,
    this.showDot = true,
    this.showValues = true,
    this.showSpark = true,
    this.showUsual = true,
    String? tap,
  })  : hero = hero ?? wMetrics[kind]!.first.key,
        values = values ?? List.of(wDefaultValues[kind]!),
        valueColors = valueColors ?? {},
        tap = tap ?? (kind == WKind.food ? WTap.add : WTap.section);

  final String kind;
  String hero;

  /// Οι τιμές στα κουτάκια, με σειρά. Το widget δείχνει όσες χωρούν στο μέγεθός του (στήλη 1×3: 5, στήλη 2×4: 6,
  /// μικρό και φαρδύ: 4).
  List<String> values;

  /// Χρώμα ανά τιμή (κλειδί → ARGB). Χωρίς χρώμα: η πρώτη στον τόνο, οι άλλες στο χρώμα των γραμμάτων.
  Map<String, int> valueColors;

  /// Έτοιμο θέμα (id του [wThemes]), «custom» ή [wWallpaperTheme].
  String theme;
  int c1, c2, acc;

  /// null = αυτόματα (ανοιχτά ή σκούρα γράμματα ανάλογα με το φόντο).
  int? textColor;

  /// Διαβάθμιση από το [c1] στο [c2]· αλλιώς μονόχρωμο [c1].
  bool gradient;

  /// Κατεύθυνση διαβάθμισης: 0 ↓, 1 ↘, 2 →, 3 ↗.
  int direction;

  /// 0–100: πόσο αδιάφανο είναι το φόντο.
  int opacity;

  /// Γωνίες σε dp (0–32).
  int radius;
  double fontScale;
  bool glow, border, shadow;
  bool showTitle, showSource, showDot, showValues, showSpark, showUsual;
  String tap;

  WidgetStyle copy() => WidgetStyle.fromJson(toJson());

  void applyTheme(WTheme t) {
    theme = t.id;
    c1 = t.c1;
    c2 = t.c2;
    acc = t.acc;
    opacity = t.op;
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'hero': hero,
        'values': values,
        'valueColors': valueColors,
        'theme': theme,
        'c1': c1,
        'c2': c2,
        'acc': acc,
        if (textColor != null) 'text': textColor,
        'gradient': gradient,
        'dir': direction,
        'op': opacity,
        'rad': radius,
        'fs': fontScale,
        'glow': glow,
        'border': border,
        'shadow': shadow,
        'title': showTitle,
        'src': showSource,
        'dot': showDot,
        'vals': showValues,
        'spark': showSpark,
        'usual': showUsual,
        'tap': tap,
      };

  static WidgetStyle fromJson(Map<String, dynamic> j) {
    final kind = WKind.all.contains(j['kind']) ? j['kind'] as String : WKind.sleep;
    final keys = {for (final m in wMetrics[kind]!) m.key};
    int i(String k, int d, [int lo = -0x7fffffff, int hi = 0x7fffffff]) {
      final v = j[k];
      return v is num ? v.toInt().clamp(lo, hi) : d;
    }

    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    final s = WidgetStyle(kind: kind);
    if (keys.contains(j['hero'])) s.hero = j['hero'] as String;
    if (j['values'] is List) s.values = [for (final v in j['values'] as List) if (v is String && keys.contains(v)) v];
    if (j['valueColors'] is Map) {
      s.valueColors = {
        for (final e in (j['valueColors'] as Map).entries)
          if (e.key is String && keys.contains(e.key) && e.value is num) e.key as String: (e.value as num).toInt(),
      };
    }
    if (j['theme'] is String) s.theme = j['theme'] as String;
    s.c1 = i('c1', s.c1);
    s.c2 = i('c2', s.c2);
    s.acc = i('acc', s.acc);
    s.textColor = j['text'] is num ? (j['text'] as num).toInt() : null;
    s.gradient = b('gradient', true);
    s.direction = i('dir', 0, 0, 3);
    s.opacity = i('op', s.opacity, 0, 100);
    s.radius = i('rad', 22, 0, 32);
    s.fontScale = j['fs'] is num ? (j['fs'] as num).toDouble().clamp(0.8, 1.3) : 1.0;
    s.glow = b('glow', true);
    s.border = b('border', true);
    s.shadow = b('shadow', false);
    s.showTitle = b('title', true);
    s.showSource = b('src', true);
    s.showDot = b('dot', true);
    s.showValues = b('vals', true);
    s.showSpark = b('spark', true);
    s.showUsual = b('usual', true);
    if (const [WTap.section, WTap.today, WTap.metric, WTap.add].contains(j['tap'])) s.tap = j['tap'] as String;
    if (s.kind != WKind.food && s.tap == WTap.add) s.tap = WTap.section;
    return s;
  }
}

/// Μεγέθη για την προεπισκόπηση (σε dp, όπως τα δίνει συνήθως η αρχική οθόνη της Samsung).
class WSize {
  const WSize(this.name, this.w, this.h, this.maxValues);
  final String name;
  final double w;
  final double h;
  final int maxValues;
}

const wSizes = <WSize>[
  WSize('Στήλη 1×3', 92, 300, 5),
  WSize('Στήλη 2×4', 180, 400, 6),
  WSize('Μικρό 2×2', 180, 190, 4),
  WSize('Φαρδύ 4×2', 370, 190, 4),
];
