import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../pages/category.dart' show TabChip;
import '../theme.dart';
import 'ex_data.dart';
import 'ex_painter.dart';

/// Για τα στιγμιότυπα/τεστ: η κίνηση ξεκινά σταματημένη.
class ExClock {
  static bool frozen = false;
}

ExColors exColorsOf(BuildContext context) {
  final c = Aigaio.of(context);
  return ExColors.of(dark: c.dark, accent: c.exercise, good: c.good);
}

/// Όνομα όψης από τη γωνία.
String exViewName(double yaw) {
  final a = ((yaw % 360) + 360) % 360;
  if (a < 30 || a > 330) return 'Μπροστά';
  if ((a - 180).abs() < 30) return 'Πίσω';
  if ((a - 90).abs() <= 25 || (a - 270).abs() <= 25) return 'Πλάι';
  return a > 90 && a < 270 ? 'Πίσω λοξά' : 'Λοξά';
}

/// Η κινούμενη εικόνα μιας άσκησης, με κουμπιά: παύση, αργή κίνηση, όψη, μύες, οδηγοί.
/// Σύρε οριζόντια πάνω στην εικόνα για να γυρίσεις τη φιγούρα.
class ExPlayer extends StatefulWidget {
  const ExPlayer({super.key, required this.ex, this.phase});
  final Ex ex;

  /// Η τρέχουσα φάση του ρυθμού (για να ανάβουν τα σημεία προσοχής).
  final ValueNotifier<int>? phase;

  @override
  State<ExPlayer> createState() => _ExPlayerState();
}

class _ExPlayerState extends State<ExPlayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _repaint = ValueNotifier<int>(0);
  final _cache = ExPaintCache();
  Duration? _last;
  double _t = 0, _p = 0;
  late double _yaw;
  bool _playing = true, _slow = false, _muscles = true, _guides = true, _second = false;
  int _phase = 0;

  Ex get ex => widget.ex;

  @override
  void initState() {
    super.initState();
    _yaw = ex.yaw;
    // Στιγμιότυπο: στη μέση της πρώτης φάσης.
    _phase = -1;
    _seek(ex.tempo.first.sec * 0.6);
    _publish();
    if (ExClock.frozen) {
      _playing = false;
    } else {
      _ticker.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // «Λιγότερη κίνηση» στις ρυθμίσεις του κινητού: ξεκινά αργά και σταματημένη.
    if (MediaQuery.of(context).disableAnimations && _playing && !ExClock.frozen) {
      _playing = false;
      _slow = true;
      _ticker.stop();
    }
  }

  @override
  void didUpdateWidget(ExPlayer old) {
    super.didUpdateWidget(old);
    if (old.ex != widget.ex) {
      _yaw = ex.yaw;
      _second = false;
      _seek(ex.tempo.first.sec * 0.6);
      _publish();
    }
  }

  /// Πηγαίνει στον χρόνο t· επιστρέφει true αν άλλαξε φάση.
  bool _seek(double t) {
    _t = t;
    final (p, i) = ex.at(_t);
    _p = p;
    _repaint.value++;
    if (i == _phase) return false;
    _phase = i;
    return true;
  }

  void _publish() {
    final n = widget.phase;
    if (n == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) n.value = _phase;
    });
  }

  void _tick(Duration now) {
    final dt = _last == null ? 0.0 : (now - _last!).inMicroseconds / 1e6;
    _last = now;
    if (_seek(_t + dt.clamp(0.0, 0.1) * (_slow ? 0.4 : 1.0))) {
      setState(() {});
      widget.phase?.value = _phase;
    }
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _last = null;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _view() {
    setState(() {
      _second = !_second;
      _yaw = _second ? ex.yaw2 : ex.yaw;
    });
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final colors = exColorsOf(context);
    final elev = _second ? ex.elev2 : ex.elev;
    final nearDefault = !_second && (_yaw - ex.yaw).abs() < 12;
    final other = exViewName(_second ? ex.yaw : ex.yaw2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Κινούμενη εικόνα: ${ex.name}. ${ex.tempo[_phase].name}.',
          image: true,
          child: GestureDetector(
            onTap: _toggle,
            onDoubleTap: () {
              setState(() => _yaw = _second ? ex.yaw2 : ex.yaw);
              _repaint.value++;
            },
            onHorizontalDragUpdate: (d) {
              _yaw -= d.delta.dx * 0.5;
              _repaint.value++;
              setState(() {});
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1.22,
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: ValueKey('ex-anim-${ex.id}'),
                    painter: ExPainter(
                      ex: ex,
                      p: _p,
                      yaw: _yaw,
                      elev: elev,
                      colors: colors,
                      muscles: _muscles,
                      guides: _guides && nearDefault,
                      cache: _cache,
                      pAt: () => _p,
                      yawAt: () => _yaw,
                      repaint: _repaint,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                ex.tempo[_phase].name,
                key: const ValueKey('ex-phase'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.exercise),
              ),
            ),
            IconButton.filled(
              key: const ValueKey('ex-play'),
              style: IconButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid),
              tooltip: _playing ? 'Παύση' : 'Συνέχεια',
              onPressed: _toggle,
              icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final chip in <Widget>[
            TabChip(label: 'Αργά', selected: _slow, solid: c.exerciseSolid, onTap: () => setState(() => _slow = !_slow)),
            TabChip(key: const ValueKey('ex-view'), label: other, selected: false, solid: c.exerciseSolid, onTap: _view),
            TabChip(label: 'Μύες', selected: _muscles, solid: c.exerciseSolid, onTap: () {
              setState(() => _muscles = !_muscles);
              _repaint.value++;
            }),
            if (ex.anim.guides.isNotEmpty)
              TabChip(label: 'Οδηγοί', selected: _guides, solid: c.exerciseSolid, onTap: () {
                setState(() => _guides = !_guides);
                _repaint.value++;
              }),
            ])
              IntrinsicWidth(child: chip),
          ],
        ),
        if (_muscles) ...[
          const SizedBox(height: 10),
          Row(children: [
            _Swatch(colors.primary),
            const SizedBox(width: 6),
            Text('κύριοι μύες', style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(width: 14),
            _Swatch(colors.secondary),
            const SizedBox(width: 6),
            Text('βοηθητικοί', style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ]),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)));
}

/// Μικρή στατική εικόνα της άσκησης (για τη λίστα).
class ExThumb extends StatelessWidget {
  const ExThumb({super.key, required this.ex, this.size = 64});
  final Ex ex;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Κοντά στο τέλος της πρώτης φάσης: εκεί φαίνεται τι κάνει η άσκηση.
    final t = ex.tempo.first;
    final p = t.from + 0.75 * (t.to - t.from);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: ExPainter(ex: ex, p: p, yaw: ex.yaw, elev: ex.elev, colors: exColorsOf(context)),
          ),
        ),
      ),
    );
  }
}
