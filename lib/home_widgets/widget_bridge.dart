import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../food/food_store.dart';
import '../training/training_store.dart';
import 'widget_snapshot.dart';
import 'widget_style.dart';

/// Ένα κανάλι για όλα τα widgets (HomeWidgets.kt, WidgetConfigActivity.kt).
const widgetChannel = MethodChannel('ygeia/widgets');

/// Τι ζήτησε ένα πάτημα σε widget: «today», «health:0», «food:add», «metric:hrv»… Το ακούει το Shell (main.dart).
final widgetOpenRequest = ValueNotifier<String?>(null);

/// Στέλνει το στιγμιότυπο στα widgets όταν αλλάζουν τα δεδομένα: με καθυστέρηση 1,5″ (μαζεύει τις αλλαγές μιας
/// ανάγνωσης) και μόνο αν άλλαξε κάτι. Καμία δουλειά όταν δεν υπάρχει widget (το λέει η Kotlin με «count»).
class WidgetPublisher {
  WidgetPublisher(this.store, this.food, {this.training, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final HealthStore store;
  final FoodStore food;

  /// Για το widget «Προπόνηση σήμερα» (13/11).
  final TrainingStore? training;
  String? _lastWorkout;
  final DateTime Function() _clock;
  Timer? _timer;
  String? _last;

  void start() {
    store.addListener(_schedule);
    food.addListener(_schedule);
    training?.addListener(_trainingChanged);
    widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) widgetOpenRequest.value = call.arguments as String;
      return null;
    });
    unawaited(_takeOpen());
    _schedule();
  }

  Future<void> _takeOpen() async {
    try {
      final o = await widgetChannel.invokeMethod<String>('takeOpen');
      if (o != null && o.isNotEmpty) widgetOpenRequest.value = o;
    } catch (_) {}
  }

  /// Η αποθήκη της προπόνησης ειδοποιεί σε κάθε ✓ και κάθε αλλαγή επαναλήψεων. Τα widgets ξαναζωγραφίζονται μόνο όταν
  /// αλλάζει αυτό που δείχνει το widget (πρόγραμμα, «έγινε σήμερα»), όχι σε κάθε σετ (μπαταρία).
  void _trainingChanged() {
    final t = training;
    if (t == null || !t.ready) return;
    final now = _clock();
    final text = jsonEncode(workoutSnapshot(t, DateTime(now.year, now.month, now.day)));
    if (text == _lastWorkout) return;
    _lastWorkout = text;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), publish);
  }

  Future<void> publish() async {
    try {
      final n = await widgetChannel.invokeMethod<int>('count') ?? 0;
      if (n == 0) return;
      final snap = buildWidgetSnapshot(store, food, _clock(), training: training);
      // Round 7 (A10-1): η σύγκριση ΧΩΡΙΣ το «at» (η ώρα της δημοσίευσης, που δεν τη διαβάζει κανείς): αλλιώς δεν ήταν ποτέ
      // ίδιο και κάθε ειδοποίηση (μέρα στο ημερολόγιο φαγητού, «διαβάζω…», κάθε κομμάτι του ιστορικού) ξαναζωγράφιζε όλα
      // τα widgets. Το «at» μένει στο στιγμιότυπο (ίδια μορφή).
      final key = jsonEncode({...snap}..remove('at'));
      if (key == _last) return;
      await widgetChannel.invokeMethod('update', jsonEncode(snap));
      _last = key;
    } on MissingPluginException {
      // Τεστ ή πλατφόρμα χωρίς widgets.
    } catch (e, st) {
      if (kDebugMode) debugPrint('widgets: $e\n$st');
    }
  }

  void stop() {
    _timer?.cancel();
    store.removeListener(_schedule);
    food.removeListener(_schedule);
    training?.removeListener(_trainingChanged);
  }
}

/// Το widget που ρυθμίζεται: id (0 = μόνο προεπισκόπηση), είδος, μέγεθος σε dp, οι ρυθμίσεις του αν υπάρχουν.
class WidgetTarget {
  const WidgetTarget({required this.id, required this.kind, this.width, this.height, this.style, this.hasData = false});
  final int id;
  final String kind;
  final double? width;
  final double? height;
  final WidgetStyle? style;

  /// Αν υπάρχουν πραγματικές τιμές για αυτό το είδος (αλλιώς η προεπισκόπηση δείχνει παράδειγμα).
  final bool hasData;
}

class WidgetConfigBridge {
  const WidgetConfigBridge();

  Future<WidgetTarget?> target() async {
    try {
      final m = await widgetChannel.invokeMapMethod<String, dynamic>('target');
      if (m == null) return null;
      final kind = WKind.all.contains(m['kind']) ? m['kind'] as String : WKind.sleep;
      final s = m['style'] is String ? WidgetStyle.fromJson(jsonDecode(m['style'] as String) as Map<String, dynamic>) : null;
      return WidgetTarget(
        id: (m['id'] as num?)?.toInt() ?? 0,
        kind: kind,
        width: (m['w'] as num?)?.toDouble(),
        height: (m['h'] as num?)?.toDouble(),
        style: s?.kind == kind ? s : null,
        hasData: m['hasData'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Η εικόνα του widget, όπως θα φανεί στην αρχική οθόνη (ίδιος ζωγράφος).
  Future<Uint8List?> render(WidgetStyle style, double w, double h, {required bool dark}) async {
    try {
      return await widgetChannel.invokeMethod<Uint8List>('render', {
        'style': jsonEncode(style.toJson()),
        'w': w,
        'h': h,
        'dark': dark,
      });
    } catch (_) {
      return null;
    }
  }

  Future<bool> save(int id, WidgetStyle style, {bool applyToAll = false}) async {
    try {
      return await widgetChannel.invokeMethod<bool>('save', {
            'id': id,
            'style': jsonEncode(style.toJson()),
            'all': applyToAll,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancel() async {
    try {
      await widgetChannel.invokeMethod('cancel');
    } catch (_) {}
  }
}
