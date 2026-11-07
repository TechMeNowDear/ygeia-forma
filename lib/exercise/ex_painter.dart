import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'ex_data.dart';

/// Χρώματα της σκηνής (ανοιχτό/σκούρο θέμα). Ο εξοπλισμός κρατά τα πραγματικά του χρώματα,
/// με τα πολύ σκούρα λίγο πιο ανοιχτά στο σκούρο θέμα για να φαίνονται.
class ExColors {
  const ExColors({
    required this.figure,
    required this.far,
    required this.stage,
    required this.floor,
    required this.accent,
    required this.good,
    required this.labelBg,
    required this.dark,
    this.primary = const Color(0xFFDC2626),
    this.secondary = const Color(0xFFFDBA74),
  });
  final Color figure, far, stage, floor, accent, good, labelBg, primary, secondary;
  final bool dark;

  factory ExColors.of({required bool dark, required Color accent, required Color good}) => dark
      ? ExColors(
          figure: const Color(0xFFCBD5E1), far: const Color(0xFF5B6B82), stage: const Color(0xFF0F182A),
          floor: const Color(0xFF223049), accent: accent, good: good, labelBg: const Color(0xD90F182A), dark: true)
      : ExColors(
          figure: const Color(0xFF1E293B), far: const Color(0xFF94A3B8), stage: const Color(0xFFEEF2F7),
          floor: const Color(0xFFD6DCE6), accent: accent, good: good, labelBg: const Color(0xD9FFFFFF), dark: false);

  Color equip(Color c) {
    if (!dark) return c;
    final l = c.computeLuminance();
    return l < 0.06 ? Color.lerp(c, const Color(0xFF94A3B8), 0.45)! : c;
  }
}

/// Κάμερα: περιστροφή γύρω από τον κατακόρυφο άξονα (yaw: 0 = μπροστά, 90 = από τα δεξιά του ασκούμενου)
/// και λίγο από ψηλά (elev). Ορθογραφική προβολή.
class ExCamera {
  ExCamera(double yaw, double elev) {
    final y = yaw * math.pi / 180, e = elev * math.pi / 180;
    fx = math.sin(y) * math.cos(e);
    fy = -math.sin(e);
    fz = -math.cos(y) * math.cos(e);
    rx = math.cos(y);
    rz = math.sin(y);
    // u = r × f
    ux = 0 * fz - rz * fy;
    uy = rz * fx - rx * fz;
    uz = rx * fy - 0 * fx;
  }
  late final double fx, fy, fz, rx, rz, ux, uy, uz;

  double right(double x, double z) => x * rx + z * rz;
  double up(double x, double y, double z) => x * ux + y * uy + z * uz;
  double depth(double x, double y, double z) => x * fx + y * fy + z * fz;
}

/// Κλίμακα και θέση ώστε όλη η κίνηση να χωράει, ίδια σε όλα τα καρέ (να μη «χοροπηδάει»).
class ExFit {
  const ExFit(this.s, this.ox, this.oy);
  final double s, ox, oy;

  static ExFit compute(Ex ex, ExCamera cam, Size size) {
    final a = ex.anim;
    var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    void acc(Float32List P, int k) {
      final x = cam.right(P[3 * k], P[3 * k + 2]), y = cam.up(P[3 * k], P[3 * k + 1], P[3 * k + 2]);
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }

    Float32List? buf;
    for (var i = 0; i < a.n; i++) {
      buf = a.points(i / (a.n - 1), buf);
      for (final k in a.joints) {
        acc(buf, k);
      }
    }
    final P = a.points(0, buf);
    for (final pr in a.prims) {
      if (pr.kind == 'box' && pr.z >= 0.4) continue; // τοίχος/πάτωμα
      for (final k in [...pr.pts, pr.a, pr.b, pr.c]) {
        if (k >= 0) acc(P, k);
      }
    }
    const pad = 0.16;
    x0 -= pad;
    x1 += pad;
    y0 -= 0.05;
    y1 += pad;
    final s = math.min(size.width / (x1 - x0), size.height / (y1 - y0));
    return ExFit(s, size.width / 2 - s * (x0 + x1) / 2, size.height / 2 + s * (y0 + y1) / 2);
  }
}

class ExPainter extends CustomPainter {
  ExPainter({
    required this.ex,
    required this.p,
    required this.yaw,
    required this.elev,
    required this.colors,
    this.muscles = true,
    this.guides = false,
    this.cache,
    this.pAt,
    this.yawAt,
    super.repaint,
  });

  final Ex ex;
  final double p, yaw, elev;
  final ExColors colors;
  final bool muscles, guides;

  /// Προαιρετική μνήμη για την κλίμακα και τα σημεία (για την κινούμενη εικόνα, 60 καρέ το δευτερόλεπτο).
  final ExPaintCache? cache;

  /// Αν δοθεί, η θέση (και η όψη) διαβάζεται από εδώ σε κάθε καρέ, αντί για [p] και [yaw].
  final double Function()? pAt;
  final double Function()? yawAt;

  static const _limbs = [
    ('thigh', 'hip', 'knee', .078, .056),
    ('shank', 'knee', 'ank', .055, .04),
    ('foot', 'heel', 'toe', .036, .026),
    ('uarm', 'sh', 'elb', .05, .04),
    ('farm', 'elb', 'wri', .04, .03),
    ('hand', 'wri', 'grp', .03, .03),
  ];
  static const _torso = [('hipL', .085), ('hipR', .085), ('belly', .125), ('waist', .115), ('chest', .12), ('shL', .066), ('shR', .066)];
  static const _headR = 0.062 * 1.77;

  @override
  void paint(Canvas canvas, Size size) {
    final pp = pAt?.call() ?? p;
    final yw = yawAt?.call() ?? yaw;
    final cam = ExCamera(yw, elev);
    final c = cache ?? ExPaintCache();
    final fit = c.fit(ex, yw, elev, size, cam);
    _cam = cam;
    _fit = fit;
    final a = ex.anim;
    final P = c.points(a, pp);
    final s = fit.s;

    Offset pr(int k) => Offset(fit.ox + s * cam.right(P[3 * k], P[3 * k + 2]), fit.oy - s * cam.up(P[3 * k], P[3 * k + 1], P[3 * k + 2]));
    Offset prv(double x, double y, double z) => Offset(fit.ox + s * cam.right(x, z), fit.oy - s * cam.up(x, y, z));
    double dep(int k) => cam.depth(P[3 * k], P[3 * k + 1], P[3 * k + 2]);
    final J = <String, int>{for (var i = 0; i < exBody.length; i++) exBody[i]: a.joints[i]};

    canvas.drawRect(Offset.zero & size, Paint()..color = colors.stage);
    canvas.drawPath(
      Path()..addPolygon([prv(-1.8, 0, -1.8), prv(1.8, 0, -1.8), prv(1.8, 0, 1.8), prv(-1.8, 0, 1.8)], true),
      Paint()..color = colors.floor,
    );

    final outline = Paint()
      ..color = colors.stage
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;

    // Η μακρινή πλευρά πιο ανοιχτή.
    var farL = false, farR = false;
    final dL = dep(J['hipL']!) + dep(J['shL']!), dR = dep(J['hipR']!) + dep(J['shR']!);
    if ((dL - dR).abs() > 0.06) {
      if (dL > dR) {
        farL = true;
      } else {
        farR = true;
      }
    }

    final items = <_Item>[];
    final hosts = <String, _Item>{};
    final torsoD = (dep(J['chest']!) + dep(J['belly']!)) / 2;
    hosts['torso'] = _Item(torsoD, () {
      final path = _hull([for (final t in _torso) (pr(J[t.$1]!), t.$2 * s)]);
      canvas.drawPath(path, Paint()..color = colors.figure);
      canvas.drawPath(path, outline);
    });
    for (final side in const ['L', 'R']) {
      final far = side == 'L' ? farL : farR;
      for (final l in _limbs) {
        final ia = J['${l.$2}$side']!, ib = J['${l.$3}$side']!;
        hosts['${l.$1}$side'] = _Item((dep(ia) + dep(ib)) / 2, () {
          final path = _capsule(pr(ia), pr(ib), l.$4 * s, l.$5 * s);
          canvas.drawPath(path, Paint()..color = far ? colors.far : colors.figure);
          canvas.drawPath(path, outline);
        });
      }
    }
    hosts['neck'] = _Item(dep(J['neckTop']!), () {
      canvas.drawPath(_capsule(pr(J['shC']!), pr(J['neckTop']!), .05 * s, .045 * s), Paint()..color = colors.figure);
    });
    hosts['head'] = _Item(dep(J['head']!), () {
      final o = pr(J['head']!);
      canvas.drawCircle(o, _headR * s, Paint()..color = colors.figure);
      canvas.drawCircle(o, _headR * s, outline);
    });

    // Μύες: ζωγραφίζονται αμέσως μετά το τμήμα τους.
    final onHost = <String, List<(ExMus, Color)>>{};
    if (muscles) {
      for (final m in a.muscles) {
        final t = ex.tone(m.id);
        if (t == 0) continue;
        (onHost[m.host] ??= []).add((m, t == 1 ? colors.primary : colors.secondary));
      }
    }
    hosts.forEach((name, it) {
      final list = onHost[name];
      final isFar = name != 'torso' && ((name.endsWith('L') && farL) || (name.endsWith('R') && farR));
      items.add(_Item(it.d, () {
        it.draw();
        if (list == null) return;
        for (final (m, col) in list) {
          _muscle(canvas, P, m, cam, s, pr, col, isFar);
        }
      }));
    });

    final figD = dep(J['pelvis']!);
    for (final q in a.prims) {
      final d = _primDepth(q, dep);
      if (q.wall && d < figD) continue; // ο τοίχος μπροστά από την κάμερα δεν ζωγραφίζεται
      items.add(_Item(d + q.z, () => _prim(canvas, q, P, pr, s)));
    }
    items.sort((x, y) => y.d.compareTo(x.d));
    for (final it in items) {
      it.draw();
    }
    if (guides) {
      for (final g in a.guides) {
        _guide(canvas, size, g, pr, s);
      }
    }
  }

  double _primDepth(ExPrim q, double Function(int) dep) {
    if (q.pts.isNotEmpty) return q.pts.fold(0.0, (t, k) => t + dep(k)) / q.pts.length;
    if (q.kind == 'rod') return (dep(q.a) + dep(q.b)) / 2;
    return dep(q.c);
  }

  void _prim(Canvas canvas, ExPrim q, Float32List P, Offset Function(int) pr, double s) {
    final col = colors.equip(q.col);
    switch (q.kind) {
      case 'box':
        final path = _hull([for (final k in q.pts) (pr(k), 0.0)]);
        canvas.drawPath(path, Paint()..color = col);
        canvas.drawPath(path, Paint()
          ..color = const Color(0x40000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
      case 'rod':
        canvas.drawPath(_capsule(pr(q.a), pr(q.b), q.r * s, q.r * s), Paint()..color = col);
      case 'ball':
        canvas.drawCircle(pr(q.c), q.r * s, Paint()..color = col);
      case 'poly':
        final path = Path();
        for (var i = 0; i < q.pts.length; i++) {
          final o = pr(q.pts[i]);
          i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, q.w * s)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
      case 'disc':
        final cx = P[3 * q.c], cy = P[3 * q.c + 1], cz = P[3 * q.c + 2];
        var nx = P[3 * q.n] - cx, ny = P[3 * q.n + 1] - cy, nz = P[3 * q.n + 2] - cz;
        final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= nl;
        ny /= nl;
        nz /= nl;
        // u ⟂ n, v = n × u
        final ref = ny.abs() < 0.9 ? (0.0, 1.0, 0.0) : (1.0, 0.0, 0.0);
        var ux = ny * ref.$3 - nz * ref.$2, uy = nz * ref.$1 - nx * ref.$3, uz = nx * ref.$2 - ny * ref.$1;
        final ul = math.sqrt(ux * ux + uy * uy + uz * uz);
        ux /= ul;
        uy /= ul;
        uz /= ul;
        final vx = ny * uz - nz * uy, vy = nz * ux - nx * uz, vz = nx * uy - ny * ux;
        final cam = _cam!;
        final pts = <Offset>[];
        for (var i = 0; i < 24; i++) {
          final t = i / 24 * 2 * math.pi;
          final co = math.cos(t) * q.r, si = math.sin(t) * q.r;
          final x = cx + ux * co + vx * si, y = cy + uy * co + vy * si, z = cz + uz * co + vz * si;
          pts.add(Offset(_fit!.ox + s * cam.right(x, z), _fit!.oy - s * cam.up(x, y, z)));
        }
        final path = Path()..addPolygon(pts, true);
        canvas.drawPath(path, Paint()..color = col);
        canvas.drawPath(path, Paint()
          ..color = colors.equip(q.rim ?? q.col)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, 0.012 * s));
    }
  }

  // Η κάμερα και η κλίμακα του τρέχοντος καρέ (για τους δίσκους, που προβάλλουν δικά τους σημεία).
  ExCamera? _cam;
  ExFit? _fit;

  void _muscle(Canvas canvas, Float32List P, ExMus m, ExCamera cam, double s, Offset Function(int) pr, Color color, bool isFar) {
    final cx = P[3 * m.c], cy = P[3 * m.c + 1], cz = P[3 * m.c + 2];
    final ux = P[3 * m.u] - cx, uy = P[3 * m.u + 1] - cy, uz = P[3 * m.u + 2] - cz;
    final vx = P[3 * m.v] - cx, vy = P[3 * m.v + 1] - cy, vz = P[3 * m.v + 2] - cz;
    var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nl == 0) return;
    nx /= nl;
    ny /= nl;
    nz /= nl;
    final facing = -(nx * cam.fx + ny * cam.fy + nz * cam.fz);
    if (facing < -0.3) return; // στην πίσω πλευρά: δεν φαίνεται από εδώ
    final alpha = math.min(1.0, (facing + 0.3) / 0.4) * (isFar ? 0.7 : 1.0);
    final pts = <Offset>[];
    for (var i = 0; i < 20; i++) {
      final t = i / 20 * 2 * math.pi;
      final co = math.cos(t), si = math.sin(t);
      final x = cx + ux * co + vx * si, y = cy + uy * co + vy * si, z = cz + uz * co + vz * si;
      pts.add(Offset(_fit!.ox + s * cam.right(x, z), _fit!.oy - s * cam.up(x, y, z)));
    }
    final path = Path()..addPolygon(pts, true);
    final col = color.withValues(alpha: alpha);
    canvas.drawPath(path, Paint()..color = col);
    canvas.drawPath(path, Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(2, 0.014 * s));
  }

  void _guide(Canvas canvas, Size size, ExGuide g, Offset Function(int) pr, double s) {
    final col = g.color == 'good' ? colors.good : colors.accent;
    final a = pr(g.a), b = pr(g.b);
    final paint = Paint()
      ..color = col
      ..strokeWidth = math.max(2, 0.008 * s)
      ..style = PaintingStyle.stroke;
    if (g.dashed) {
      final d = b - a, len = d.distance;
      final u = d / len;
      for (var t = 0.0; t < len; t += 15) {
        canvas.drawLine(a + u * t, a + u * math.min(len, t + 8), paint);
      }
    } else {
      canvas.drawLine(a, b, paint);
    }
    final label = g.label;
    if (label == null) return;
    final fs = math.max(11.0, math.min(15.0, 0.034 * s));
    final tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(fontFamily: 'Inter', color: col, fontSize: fs, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: size.width * 0.7);
    final at = pr(g.c);
    final x = (at.dx - tp.width / 2).clamp(6.0, math.max(6.0, size.width - tp.width - 6)).toDouble();
    final y = (at.dy - tp.height).clamp(6.0, math.max(6.0, size.height - tp.height - 6)).toDouble();
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x - 5, y - 3, tp.width + 10, tp.height + 6), const Radius.circular(6)),
      Paint()..color = colors.labelBg,
    );
    tp.paint(canvas, Offset(x, y));
    tp.dispose();
  }

  static Path _capsule(Offset a, Offset b, double r1, double r2) {
    final d = b - a, l = d.distance;
    if (l <= (r1 - r2).abs() + 0.5) {
      return Path()..addOval(Rect.fromCircle(center: r1 > r2 ? a : b, radius: math.max(r1, r2)));
    }
    final th = math.atan2(d.dy, d.dx), al = math.acos(((r1 - r2) / l).clamp(-1.0, 1.0));
    return Path()
      ..arcTo(Rect.fromCircle(center: a, radius: r1), th + al, 2 * math.pi - 2 * al, true)
      ..arcTo(Rect.fromCircle(center: b, radius: r2), th - al, 2 * al, false)
      ..close();
  }

  static Path _hull(List<(Offset, double)> circles) {
    final pts = <Offset>[];
    for (final (c, r) in circles) {
      if (r <= 0) {
        pts.add(c);
        continue;
      }
      for (var i = 0; i < 16; i++) {
        final a = i / 16 * 2 * math.pi;
        pts.add(c + Offset(r * math.cos(a), r * math.sin(a)));
      }
    }
    pts.sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double cr(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lo = <Offset>[], up = <Offset>[];
    for (final q in pts) {
      while (lo.length >= 2 && cr(lo[lo.length - 2], lo.last, q) <= 0) {
        lo.removeLast();
      }
      lo.add(q);
    }
    for (final q in pts.reversed) {
      while (up.length >= 2 && cr(up[up.length - 2], up.last, q) <= 0) {
        up.removeLast();
      }
      up.add(q);
    }
    lo.removeLast();
    up.removeLast();
    return Path()..addPolygon([...lo, ...up], true);
  }

  @override
  bool shouldRepaint(ExPainter old) =>
      old.ex != ex || old.p != p || old.yaw != yaw || old.elev != elev || old.colors != colors ||
      old.muscles != muscles || old.guides != guides || pAt != null;
}

class _Item {
  _Item(this.d, this.draw);
  final double d;
  final void Function() draw;
}

/// Κρατά την κλίμακα ανά όψη/μέγεθος και ένα buffer για τα σημεία, ώστε η κίνηση να μη δημιουργεί σκουπίδια μνήμης.
class ExPaintCache {
  String? _key;
  ExFit? _fitv;
  Float32List? _buf;

  ExFit fit(Ex ex, double yaw, double elev, Size size, ExCamera cam) {
    final k = '${ex.id}:${yaw.toStringAsFixed(1)}:$elev:${size.width.round()}x${size.height.round()}';
    if (k != _key || _fitv == null) {
      _key = k;
      _fitv = ExFit.compute(ex, cam, size);
    }
    return _fitv!;
  }

  Float32List points(ExAnim a, double p) => _buf = a.points(p, _buf);
}
