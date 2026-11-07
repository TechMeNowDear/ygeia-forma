import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../home_widgets/widget_bridge.dart';
import '../home_widgets/widget_style.dart';
import '../theme.dart';
import '../widgets.dart';

/// Η εφαρμογή της οθόνης ρύθμισης widget (ανοίγει η WidgetConfigActivity, όχι η κύρια εφαρμογή): ελαφριά, χωρίς
/// ανάγνωση δεδομένων· την εικόνα τη ζωγραφίζει η Kotlin με τις τελευταίες τιμές.
class WidgetConfigApp extends StatelessWidget {
  const WidgetConfigApp({super.key, this.bridge = const WidgetConfigBridge(), this.initial});
  final WidgetConfigBridge bridge;

  /// Για τα τεστ: το widget χωρίς να ρωτηθεί η Kotlin.
  final WidgetTarget? initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Widget',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, Aigaio.day(null)),
      darkTheme: buildTheme(Brightness.dark, Aigaio.night(null)),
      home: WidgetConfigPage(bridge: bridge, initial: initial),
    );
  }
}

class WidgetConfigPage extends StatefulWidget {
  const WidgetConfigPage({super.key, required this.bridge, this.initial});
  final WidgetConfigBridge bridge;
  final WidgetTarget? initial;

  @override
  State<WidgetConfigPage> createState() => _WidgetConfigPageState();
}

class _WidgetConfigPageState extends State<WidgetConfigPage> {
  WidgetTarget? _target;
  late WidgetStyle _s;
  int _size = 2;
  int _tab = 0;
  bool _all = false;
  bool _saving = false;
  Uint8List? _image;
  bool _rendered = false;
  Timer? _debounce;
  int _renderSeq = 0;

  @override
  void initState() {
    super.initState();
    _s = WidgetStyle(kind: WKind.sleep);
    if (widget.initial != null) {
      _apply(widget.initial!);
    } else {
      widget.bridge.target().then((t) {
        if (!mounted) return;
        setState(() => _apply(t ?? const WidgetTarget(id: 0, kind: WKind.sleep)));
      });
    }
  }

  void _apply(WidgetTarget t) {
    _target = t;
    _s = t.style ?? WidgetStyle(kind: t.kind);
    // Προεπισκόπηση στο πραγματικό σχήμα του widget, αν το ξέρουμε.
    if (t.width != null && t.height != null) {
      final w = t.width!, h = t.height!;
      _size = w < 120 ? 0 : (h >= w * 1.45 ? 1 : (w >= h * 1.7 ? 3 : 2));
    }
    _render();
  }

  WSize get _sz => wSizes[_size];

  void _change(void Function() f) {
    setState(f);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), _render);
  }

  Future<void> _render() async {
    final seq = ++_renderSeq;
    final dark = MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    final img = await widget.bridge.render(_s, _sz.w, _sz.h, dark: dark);
    if (!mounted || seq != _renderSeq) return;
    setState(() {
      _image = img;
      _rendered = true;
    });
  }

  Future<void> _save() async {
    final t = _target;
    if (t == null || t.id == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.bridge.save(t.id, _s, applyToAll: _all);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Δεν αποθηκεύτηκε. Δοκίμασε ξανά.')));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = _target;
    final isNew = t != null && t.id != 0 && t.style == null;
    final preview = _Preview(
      image: _image,
      loading: !_rendered,
      size: _sz,
      sample: t != null && !t.hasData,
      sizes: [
        for (final (i, z) in wSizes.indexed)
          ChoiceChip(
            label: Text(z.name),
            selected: _size == i,
            onSelected: (_) => _change(() => _size = i),
          ),
      ],
    );
    final options = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          key: const ValueKey('wc-tabs'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Περιεχόμενο', style: TextStyle(fontFamily: 'Inter'))),
            ButtonSegment(value: 1, label: Text('Εμφάνιση', style: TextStyle(fontFamily: 'Inter'))),
          ],
          selected: {_tab},
          onSelectionChanged: (v) => setState(() => _tab = v.first),
        ),
        const SizedBox(height: 12),
        if (_tab == 0) ..._content(c) else ..._look(c),
      ],
    );
    final saveBar = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              key: const ValueKey('wc-all'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _all,
              onChanged: (v) => setState(() => _all = v ?? false),
              title: const Text('Ίδια εμφάνιση σε όλα τα widgets'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            FilledButton(
              key: const ValueKey('wc-save'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _saving ? null : _save,
              child: Text(t == null || t.id == 0 ? 'Κλείσιμο' : (isNew ? 'Προσθήκη στην αρχική οθόνη' : 'Αποθήκευση')),
            ),
          ],
        ),
      ),
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.bridge.cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Widget · ${WKind.title(_s.kind)}'),
          leading: IconButton(
            tooltip: 'Άκυρο',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => widget.bridge.cancel(),
          ),
        ),
        bottomNavigationBar: saveBar,
        body: LayoutBuilder(builder: (context, k) {
          const pad = EdgeInsets.fromLTRB(16, 4, 16, 16);
          if (k.maxWidth < 760) {
            return ListView(padding: pad, children: [preview, const SizedBox(height: 14), options]);
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: pad,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: SingleChildScrollView(child: preview)),
                    const SizedBox(width: 20),
                    Expanded(child: SingleChildScrollView(child: options)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------- Περιεχόμενο
  List<Widget> _content(Aigaio c) {
    final metrics = wMetrics[_s.kind]!;
    final name = {for (final m in metrics) m.key: m.name};
    final max = _sz.maxValues;
    final chosen = _s.values.where((k) => k != _s.hero).toList();
    return [
      _Group(title: 'Κεντρική τιμή', children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in metrics)
            ChoiceChip(
              label: Text(m.name),
              selected: _s.hero == m.key,
              onSelected: (_) => _change(() => _s.hero = m.key),
            ),
        ]),
      ]),
      _Group(
        title: 'Τιμές στα κουτάκια',
        trailing: Switch(
          value: _s.showValues,
          onChanged: (v) => _change(() => _s.showValues = v),
        ),
        hint: _s.showValues
            ? 'Σε αυτό το μέγεθος χωρούν $max. Με τη σειρά που τις επιλέγεις· πάτα την κουκκίδα για χρώμα.'
            : 'Χωρίς κουτάκια: μόνο η κεντρική τιμή.',
        children: [
          if (_s.showValues)
            for (final m in metrics)
              if (m.key != _s.hero)
                _ValueRow(
                  name: m.name,
                  order: chosen.contains(m.key) ? chosen.indexOf(m.key) + 1 : null,
                  shown: chosen.contains(m.key) && chosen.indexOf(m.key) < max,
                  color: _s.valueColors[m.key],
                  onToggle: () => _change(() {
                    if (_s.values.contains(m.key)) {
                      _s.values.remove(m.key);
                      _s.valueColors.remove(m.key);
                    } else {
                      _s.values.add(m.key);
                    }
                  }),
                  onColor: () => _pickValueColor(m.key, name[m.key]!),
                ),
        ],
      ),
      _Group(title: 'Γράφημα 7 ημερών', trailing: Switch(value: _s.showSpark, onChanged: (v) => _change(() => _s.showSpark = v)),
          hint: 'Της κεντρικής τιμής, όπου χωράει.', children: const []),
      _Group(
          title: '«Συνήθως» και εύρος',
          trailing: Switch(value: _s.showUsual, onChanged: (v) => _change(() => _s.showUsual = v)),
          hint: 'Βελάκι πάνω ή κάτω από τα συνηθισμένα σου, και πού είσαι στο εύρος όπου υπάρχει.',
          children: const []),
      _Group(title: 'Το πάτημα ανοίγει', children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, l) in [
            if (_s.kind == WKind.food) (WTap.add, 'Προσθήκη φαγητού'),
            (WTap.section, 'Την ενότητα'),
            (WTap.metric, 'Τη σελίδα της κεντρικής τιμής'),
            (WTap.today, 'Το «Σήμερα»'),
          ])
            ChoiceChip(label: Text(l), selected: _s.tap == v, onSelected: (_) => setState(() => _s.tap = v)),
        ]),
      ]),
    ];
  }

  // ---------------------------------------------------------------- Εμφάνιση
  List<Widget> _look(Aigaio c) {
    final custom = _s.theme == 'custom';
    final wall = _s.theme == wWallpaperTheme;
    return [
      _Group(title: 'Χρώματα', children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in wThemes)
            _Swatch(
              label: t.name,
              colors: [Color(t.c1), Color(t.c2)],
              accent: Color(t.acc),
              selected: _s.theme == t.id,
              onTap: () => _change(() => _s.applyTheme(t)),
            ),
          _Swatch(
            label: 'Ταπετσαρία',
            colors: const [Color(0xFF4F6E92), Color(0xFF22324A)],
            accent: const Color(0xFFF0B48F),
            icon: Icons.wallpaper_rounded,
            selected: wall,
            onTap: () => _change(() => _s.theme = wWallpaperTheme),
          ),
          _Swatch(
            label: 'Δικά μου',
            colors: [Color(_s.c1), Color(_s.c2)],
            accent: Color(_s.acc),
            icon: Icons.tune_rounded,
            selected: custom,
            onTap: () => _change(() => _s.theme = 'custom'),
          ),
        ]),
        if (wall) ...[
          const SizedBox(height: 8),
          Text('Τα χρώματα έρχονται από την ταπετσαρία σου και αλλάζουν μαζί με το ανοιχτό ή σκοτεινό θέμα του κινητού.',
              style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4)),
        ],
        if (custom) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _ColorButton(label: 'Φόντο πάνω', color: Color(_s.c1), onTap: () => _pick('Φόντο πάνω', _s.c1, (v) => _s.c1 = v))),
            const SizedBox(width: 8),
            Expanded(child: _ColorButton(label: 'Φόντο κάτω', color: Color(_s.c2), onTap: () => _pick('Φόντο κάτω', _s.c2, (v) => _s.c2 = v))),
            const SizedBox(width: 8),
            Expanded(child: _ColorButton(label: 'Τόνος', color: Color(_s.acc), onTap: () => _pick('Τόνος', _s.acc, (v) => _s.acc = v))),
          ]),
        ],
      ]),
      if (!wall)
        _Group(title: 'Φόντο', children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Διαβάθμιση', style: TextStyle(fontFamily: 'Inter'))),
              ButtonSegment(value: false, label: Text('Μονόχρωμο', style: TextStyle(fontFamily: 'Inter'))),
            ],
            selected: {_s.gradient},
            onSelectionChanged: (v) => _change(() => _s.gradient = v.first),
          ),
          if (_s.gradient) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final (i, icon, l) in const [
                (0, Icons.south_rounded, 'Από πάνω'),
                (1, Icons.south_east_rounded, 'Διαγώνια'),
                (2, Icons.east_rounded, 'Από αριστερά'),
                (3, Icons.north_east_rounded, 'Από κάτω αριστερά'),
              ])
                ChoiceChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(l),
                  selected: _s.direction == i,
                  onSelected: (_) => _change(() => _s.direction = i),
                ),
            ]),
          ],
        ]),
      _Group(title: 'Διαφάνεια φόντου', children: [
        _SliderRow(
          value: _s.opacity.toDouble(),
          min: 0,
          max: 100,
          text: '${_s.opacity}%',
          onChanged: (v) => _change(() => _s.opacity = v.round()),
        ),
      ]),
      _Group(title: 'Γωνίες', children: [
        _SliderRow(
          value: _s.radius.toDouble(),
          min: 0,
          max: 32,
          text: '${_s.radius}',
          onChanged: (v) => _change(() => _s.radius = v.round()),
        ),
      ]),
      _Group(title: 'Γράμματα', children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, l) in const [(0.9, 'Μικρά'), (1.0, 'Κανονικά'), (1.12, 'Μεγάλα')])
            ChoiceChip(label: Text(l), selected: _s.fontScale == v, onSelected: (_) => _change(() => _s.fontScale = v)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (int? v, l) in const [(null, 'Αυτόματο χρώμα'), (0xFFFFFFFF, 'Ανοιχτά'), (0xFF17141F, 'Σκούρα')])
            ChoiceChip(label: Text(l), selected: _s.textColor == v, onSelected: (_) => _change(() => _s.textColor = v)),
        ]),
        const SizedBox(height: 6),
        Text('Στο αυτόματο, τα γράμματα γίνονται ανοιχτά ή σκούρα για να διαβάζονται πάντα.',
            style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4)),
      ]),
      _Group(title: 'Λεπτομέρειες', children: [
        _SwitchRow('Λάμψη στη γωνία', _s.glow, (v) => _change(() => _s.glow = v)),
        _SwitchRow('Περίγραμμα', _s.border, (v) => _change(() => _s.border = v)),
        _SwitchRow('Σκιά', _s.shadow, (v) => _change(() => _s.shadow = v)),
        _SwitchRow('Τίτλος', _s.showTitle, (v) => _change(() => _s.showTitle = v)),
        _SwitchRow('Πηγή και ώρα', _s.showSource, (v) => _change(() => _s.showSource = v)),
        _SwitchRow('Χρωματιστή κουκκίδα', _s.showDot, (v) => _change(() => _s.showDot = v)),
      ]),
    ];
  }

  Future<void> _pick(String title, int current, void Function(int v) set) async {
    final v = await showColorSheet(context, title, Color(current));
    if (v != null) _change(() => set(v.toARGB32()));
  }

  Future<void> _pickValueColor(String key, String name) async {
    final c = Aigaio.of(context);
    final v = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Χρώμα: $name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _Dot(color: null, onTap: () => Navigator.pop(context, -1), label: 'Αυτόματο'),
                for (final x in wValueColors) _Dot(color: Color(x), onTap: () => Navigator.pop(context, x)),
                _Dot(
                  color: null,
                  icon: Icons.colorize_rounded,
                  label: 'Άλλο',
                  onTap: () async {
                    final p = await showColorSheet(context, name, Color(_s.valueColors[key] ?? wValueColors.first));
                    if (context.mounted) Navigator.pop(context, p?.toARGB32());
                  },
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (v == null) return;
    _change(() {
      if (v == -1) {
        _s.valueColors.remove(key);
      } else {
        _s.valueColors[key] = v;
      }
    });
  }
}

/// Επιλογή χρώματος με τρία ρυθμιστικά (απόχρωση, ένταση, φωτεινότητα): χωρίς βιβλιοθήκη, με μεγάλα χειριστήρια.
Future<Color?> showColorSheet(BuildContext context, String title, Color start) {
  var hsv = HSVColor.fromColor(start);
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(builder: (context, set) {
      final c = Aigaio.of(context);
      final color = hsv.toColor();
      Widget slider(String label, double v, double max, void Function(double) on, List<Color> track) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
              const SizedBox(height: 4),
              Container(
                height: 14,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), gradient: LinearGradient(colors: track)),
              ),
              Slider(value: v, max: max, onChanged: (x) => set(() => on(x))),
            ],
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.hairline))),
                const SizedBox(width: 14),
                Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text))),
              ]),
              const SizedBox(height: 14),
              slider('Απόχρωση', hsv.hue, 360, (x) => hsv = hsv.withHue(x),
                  [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()]),
              slider('Ένταση', hsv.saturation, 1, (x) => hsv = hsv.withSaturation(x),
                  [hsv.withSaturation(0).toColor(), hsv.withSaturation(1).toColor()]),
              slider('Φωτεινότητα', hsv.value, 1, (x) => hsv = hsv.withValue(x),
                  [hsv.withValue(0).toColor(), hsv.withValue(1).toColor()]),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context, color),
                child: const Text('Εντάξει'),
              ),
            ],
          ),
        ),
      );
    }),
  );
}

class _Preview extends StatelessWidget {
  const _Preview({required this.image, required this.loading, required this.size, required this.sizes, required this.sample});
  final Uint8List? image;
  final bool loading;
  final WSize size;
  final List<Widget> sizes;
  final bool sample;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 360,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppCard.radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3E5A7E), Color(0xFF8A6A7A), Color(0xFF2B3550)],
            ),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (context, k) {
            // Σε κλίμακα ώστε να χωρά, με τις αναλογίες του πραγματικού widget.
            final scale = [1.0, (k.maxWidth) / size.w, (k.maxHeight) / size.h].reduce((a, b) => a < b ? a : b);
            final w = size.w * scale, h = size.h * scale;
            return SizedBox(
              width: w,
              height: h,
              child: image == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(18)),
                      child: Center(
                        child: loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.widgets_rounded, color: Colors.white70, size: 32),
                      ),
                    )
                  : Image.memory(image!, gaplessPlayback: true, fit: BoxFit.contain, semanticLabel: 'Προεπισκόπηση widget'),
            );
          }),
        ),
        const SizedBox(height: 8),
        if (sample)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Παράδειγμα τιμών: οι δικές σου φαίνονται μόλις ανοίξεις μία φορά την εφαρμογή.',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
          ),
        Wrap(spacing: 6, runSpacing: 6, children: sizes),
        const SizedBox(height: 4),
        Text('Το μέγεθος το αλλάζεις στην αρχική οθόνη, με παρατεταμένο πάτημα και σύρσιμο των άκρων.',
            style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.4)),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.trailing, this.hint});
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text))),
              if (trailing != null) trailing!,
            ]),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint!, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4)),
            ],
            if (children.isNotEmpty) const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.name, required this.order, required this.shown, required this.color, required this.onToggle, required this.onColor});
  final String name;
  final int? order;
  final bool shown;
  final int? color;
  final VoidCallback onToggle;
  final VoidCallback onColor;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final on = order != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Checkbox(value: on, onChanged: (_) => onToggle()),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: name, style: TextStyle(fontSize: 15, color: c.text)),
              if (on && !shown) TextSpan(text: '  · δεν χωρά', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
            ])),
          ),
          if (on)
            Semantics(
              button: true,
              label: 'Χρώμα για $name',
              child: InkResponse(
                onTap: onColor,
                radius: 22,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color == null ? null : Color(color!),
                        border: Border.all(color: c.hairline, width: 2),
                      ),
                      child: color == null ? Icon(Icons.auto_awesome_rounded, size: 13, color: c.textSecondary) : null,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.colors, required this.accent, required this.selected, required this.onTap, this.icon});
  final String label;
  final List<Color> colors;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
                border: Border.all(color: selected ? c.primary : c.hairline, width: selected ? 3 : 1),
              ),
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.all(6),
              child: icon != null
                  ? Center(child: Icon(icon, size: 20, color: Colors.white))
                  : Container(width: 12, height: 12, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.text)),
          ]),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Container(height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
        ]),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.onTap, this.label, this.icon});
  final Color? color;
  final VoidCallback onTap;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      button: true,
      label: label ?? 'Χρώμα',
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: c.hairline, width: 2)),
            child: color == null ? Icon(icon ?? Icons.auto_awesome_rounded, size: 20, color: c.textSecondary) : null,
          ),
          if (label != null) Text(label!, style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
        ]),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.value, required this.min, required this.max, required this.text, required this.onChanged});
  final double value;
  final double min;
  final double max;
  final String text;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Row(children: [
      Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged)),
      SizedBox(width: 48, child: Text(text, textAlign: TextAlign.end, style: TextStyle(color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]))),
    ]);
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: TextStyle(fontSize: 15, color: c.text)),
      value: value,
      onChanged: onChanged,
    );
  }
}
