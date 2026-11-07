import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Η βιβλιοθήκη ασκήσεων: κείμενα και κίνηση (θέσεις 3D σε [n] σημεία της κίνησης).
/// Τα δεδομένα τα παράγει το tools/exercises/build.js στο assets/exercises/exercises.json.
class ExLibrary {
  ExLibrary._(this.n, this.list);

  final int n;
  final List<Ex> list;

  Ex? byId(String id) {
    for (final e in list) {
      if (e.id == id) return e;
    }
    return null;
  }

  static ExLibrary? _cache;
  static Future<ExLibrary>? _loading;

  /// Ήδη φορτωμένη (για συγχρονισμένη χρήση), αλλιώς null.
  static ExLibrary? get loaded => _cache;

  /// Φορτώνει μία φορά. Η ανάλυση του JSON γίνεται σε άλλο isolate, για να μην κολλήσει η οθόνη.
  static Future<ExLibrary> load({AssetBundle? bundle, bool inline = false}) {
    if (_cache != null) return Future.value(_cache);
    return _loading ??= () async {
      final text = await (bundle ?? rootBundle).loadString('assets/exercises/exercises.json');
      final json = inline ? jsonDecode(text) as Map<String, dynamic> : await compute(_decode, text);
      return _cache = ExLibrary.fromJson(json);
    }();
  }

  static Map<String, dynamic> _decode(String s) => jsonDecode(s) as Map<String, dynamic>;

  factory ExLibrary.fromJson(Map<String, dynamic> j) {
    final n = j['n'] as int;
    return ExLibrary._(n, [for (final e in j['ex'] as List) Ex.fromJson(e as Map<String, dynamic>, n)]);
  }
}

/// Μία φάση του ρυθμού: από [from] σε [to] (0 = αρχή, 1 = τέλος της κίνησης) σε [sec] δευτερόλεπτα.
class ExPhase {
  const ExPhase(this.from, this.to, this.sec, this.name);
  final double from, to, sec;
  final String name;
}

class ExMuscle {
  const ExMuscle(this.id, this.name, this.note);
  final String id, name, note;
}

class ExCue {
  const ExCue(this.text, this.phases);
  final String text;
  final List<int> phases;
}

/// Ομάδες με τη σειρά που φαίνονται.
const exGroups = <String, String>{
  'chest': 'Στήθος',
  'arms': 'Χέρια',
  'abs': 'Κοιλιακοί',
  'back': 'Πλάτη',
  'shoulders': 'Ώμοι',
  'legs': 'Πόδια',
};

class Ex {
  Ex({
    required this.id,
    required this.name,
    required this.en,
    required this.group,
    required this.equip,
    required this.caution,
    required this.yaw,
    required this.elev,
    required this.yaw2,
    required this.elev2,
    required this.tempo,
    required this.primary,
    required this.secondary,
    required this.feel,
    required this.setup,
    required this.steps,
    required this.cues,
    required this.mistakes,
    required this.tips,
    required this.alt,
    required this.anim,
  });

  final String id, name, en, group, equip, feel;
  final String? caution;
  final double yaw, elev, yaw2, elev2;
  final List<ExPhase> tempo;
  final List<ExMuscle> primary, secondary;
  final List<String> setup, steps, mistakes, tips, alt;
  final List<ExCue> cues;
  final ExAnim anim;

  String get groupName => exGroups[group] ?? group;
  double get cycle => tempo.fold(0.0, (a, p) => a + p.sec);

  /// 1 = κύριος, 2 = βοηθητικός, 0 = δεν δουλεύει εδώ.
  int tone(String muscle) {
    if (primary.any((m) => m.id == muscle)) return 1;
    if (secondary.any((m) => m.id == muscle)) return 2;
    return 0;
  }

  /// Θέση στην κίνηση (p) και φάση για χρόνο [t] δευτερολέπτων από την αρχή.
  (double, int) at(double t) {
    final total = cycle;
    var s = total <= 0 ? 0.0 : t % total;
    for (var i = 0; i < tempo.length; i++) {
      final ph = tempo[i];
      if (s < ph.sec || i == tempo.length - 1) {
        final k = ph.sec <= 0 ? 1.0 : (s / ph.sec).clamp(0.0, 1.0);
        final e = 0.5 - 0.5 * math.cos(math.pi * k);
        return (ph.from + (ph.to - ph.from) * e, i);
      }
      s -= ph.sec;
    }
    return (0, 0);
  }

  factory Ex.fromJson(Map<String, dynamic> j, int n) {
    List<String> strs(String k) => [for (final s in (j[k] as List? ?? const [])) s as String];
    List<ExMuscle> mus(String k) => [
          for (final m in (j[k] as List? ?? const []))
            ExMuscle((m as List)[0] as String, m[1] as String, m.length > 2 ? m[2] as String : ''),
        ];
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return Ex(
      id: j['id'] as String,
      name: j['name'] as String,
      en: j['en'] as String? ?? '',
      group: j['group'] as String,
      equip: j['equip'] as String,
      caution: j['caution'] as String?,
      yaw: d('yaw', 90),
      elev: d('elev', 8),
      yaw2: d('yaw2', 0),
      elev2: d('elev2', 8),
      tempo: [
        for (final t in j['tempo'] as List)
          ExPhase((t[0] as num).toDouble(), (t[1] as num).toDouble(), (t[2] as num).toDouble(), t[3] as String),
      ],
      primary: mus('primary'),
      secondary: mus('secondary'),
      feel: j['feel'] as String,
      setup: strs('setup'),
      steps: strs('steps'),
      cues: [for (final c in j['cues'] as List) ExCue(c[0] as String, [for (final i in c[1] as List) i as int])],
      mistakes: strs('mistakes'),
      tips: strs('tips'),
      alt: strs('alt'),
      anim: ExAnim.fromJson(j['anim'] as Map<String, dynamic>, n),
    );
  }
}

/// Τα δεδομένα της κίνησης: σταθερά σημεία + σημεία που αλλάζουν ανά δείγμα (σε mm).
class ExAnim {
  ExAnim({
    required this.n,
    required this.stat,
    required this.frames,
    required this.ns,
    required this.nd,
    required this.joints,
    required this.prims,
    required this.muscles,
    required this.guides,
  });

  final int n, ns, nd;
  final Float32List stat;
  final List<Float32List> frames;

  /// Οι αρθρώσεις του σώματος με τη σειρά του [exBody].
  final List<int> joints;
  final List<ExPrim> prims;
  final List<ExMus> muscles;
  final List<ExGuide> guides;

  int get count => ns + nd;

  /// Όλα τα σημεία (x, y, z σε μέτρα) στη θέση p ∈ [0, 1], με γραμμική παρεμβολή ανάμεσα στα δείγματα.
  Float32List points(double p, [Float32List? into]) {
    final out = into != null && into.length == count * 3 ? into : Float32List(count * 3);
    for (var k = 0; k < ns * 3; k++) {
      out[k] = stat[k];
    }
    final t = p.clamp(0.0, 1.0) * (n - 1);
    final i = t.floor().clamp(0, n - 2);
    final f = t - i;
    final a = frames[i], b = frames[i + 1];
    final o = ns * 3;
    for (var k = 0; k < nd * 3; k++) {
      out[o + k] = a[k] + (b[k] - a[k]) * f;
    }
    return out;
  }

  factory ExAnim.fromJson(Map<String, dynamic> j, int n) {
    Float32List mm(List l) {
      final f = Float32List(l.length);
      for (var i = 0; i < l.length; i++) {
        f[i] = (l[i] as num) / 1000.0;
      }
      return f;
    }

    return ExAnim(
      n: n,
      ns: j['ns'] as int,
      nd: j['nd'] as int,
      stat: mm(j['stat'] as List),
      frames: [for (final f in j['f'] as List) mm(f as List)],
      joints: [for (final i in j['j'] as List) i as int],
      prims: [for (final p in j['prims'] as List) ExPrim.fromJson(p as Map<String, dynamic>)],
      muscles: [for (final m in j['mus'] as List) ExMus.fromJson(m as Map<String, dynamic>)],
      guides: [for (final g in j['guides'] as List) ExGuide.fromJson(g as Map<String, dynamic>)],
    );
  }
}

/// Τα ονόματα των αρθρώσεων, με τη σειρά του πεδίου «j».
const exBody = [
  'pelvis', 'hipL', 'hipR', 'waist', 'belly', 'chest', 'shC', 'shL', 'shR', 'neckTop', 'head', 'nose',
  'elbL', 'elbR', 'wriL', 'wriR', 'grpL', 'grpR', 'kneeL', 'kneeR', 'ankL', 'ankR', 'heelL', 'heelR', 'toeL', 'toeR',
];

/// Σχήμα εξοπλισμού: box (8 γωνίες), rod (κύλινδρος), disc (δίσκος), ball, poly (γραμμή).
class ExPrim {
  ExPrim({required this.kind, required this.pts, this.a = -1, this.b = -1, this.c = -1, this.n = -1,
      this.r = 0, this.w = 0, required this.col, this.rim, this.z = 0, this.wall = false});
  final String kind;
  final List<int> pts;
  final int a, b, c, n;
  final double r, w, z;
  final Color col;
  final Color? rim;
  final bool wall;

  factory ExPrim.fromJson(Map<String, dynamic> j) {
    int i(String k) => (j[k] as num?)?.toInt() ?? -1;
    return ExPrim(
      kind: j['k'] as String,
      pts: [for (final p in (j['p'] as List? ?? const [])) p as int],
      a: i('a'),
      b: i('b'),
      c: i('c'),
      n: i('n'),
      r: (j['r'] as num?)?.toDouble() ?? 0,
      w: (j['w'] as num?)?.toDouble() ?? 0,
      z: (j['z'] as num?)?.toDouble() ?? 0,
      col: exColor(j['col'] as String? ?? '#000000'),
      rim: j['rim'] == null ? null : exColor(j['rim'] as String),
      wall: j['wall'] != null,
    );
  }
}

/// Μυς: έλλειψη με κέντρο c και άκρα αξόνων u, v, πάνω στο τμήμα [host].
class ExMus {
  ExMus(this.id, this.host, this.c, this.u, this.v);
  final String id, host;
  final int c, u, v;
  factory ExMus.fromJson(Map<String, dynamic> j) =>
      ExMus(j['m'] as String, j['h'] as String, j['c'] as int, j['u'] as int, j['v'] as int);
}

/// Οδηγός: γραμμή a–b (διακεκομμένη αν [dashed]) και ετικέτα στο σημείο c.
class ExGuide {
  ExGuide(this.a, this.b, this.c, this.color, this.label, this.dashed);
  final int a, b, c;
  final String color;
  final String? label;
  final bool dashed;
  factory ExGuide.fromJson(Map<String, dynamic> j) =>
      ExGuide(j['a'] as int, j['b'] as int, j['c'] as int, j['col'] as String, j['l'] as String?, j['d'] == true);
}

Color exColor(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

@visibleForTesting
void resetExLibraryForTests() {
  ExLibrary._cache = null;
  ExLibrary._loading = null;
}
