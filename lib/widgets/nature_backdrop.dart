import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A bright, flat Salesforce-style nature world painted behind EVERY screen
/// (mounted once via MaterialApp.builder, with scaffolds transparent). It mirrors
/// the web app's backdrop: sky, fluffy clouds, a sun, snow-capped blue mountains,
/// a pine forest, a green meadow, a lake and a cute bear — kept faint so cards
/// and text stay legible. Re-colours to dusk in dark mode.
///
/// It is alive, gently: the sky warms at dawn and dusk from the device clock, and
/// the clouds and birds drift on a slow 60s cycle. The motion is ambient, never
/// demanding, and it costs almost nothing to run:
///   * ONE painter, isolated in a RepaintBoundary, so scrolling content never
///     repaints because a cloud moved.
///   * frames stop entirely when the app is backgrounded (battery), and never
///     start at all under the system "reduce motion" setting (accessibility) —
///     the scene simply holds still, which is the whole scene minus the drift.
class NatureBackdrop extends StatefulWidget {
  const NatureBackdrop({super.key});

  @override
  State<NatureBackdrop> createState() => _NatureBackdropState();
}

class _NatureBackdropState extends State<NatureBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // 60s is slow enough that the drift reads as a breeze, not a carousel. The
  // controller drives a value 0..1; the painter turns it into a gentle sway.
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.repeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No frames while the app is not in front — a backdrop nobody is looking at
    // must not spin the GPU and warm the phone.
    if (state == AppLifecycleState.resumed) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduce = MediaQuery.of(context).disableAnimations;
    // Honour "reduce motion": freeze on a neutral mid-drift and stay there.
    if (reduce && _c.isAnimating) {
      _c.stop();
    } else if (!reduce && !_c.isAnimating) {
      _c.repeat();
    }

    final sky = _sky(dark, DateTime.now().hour);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // A full round trip out and back, so clouds sway rather than snap at
          // the loop seam. Centred on 0.5; the painter reads (drift - 0.5).
          final drift =
              reduce ? 0.5 : 0.5 + 0.5 * math.sin(_c.value * 2 * math.pi);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: sky,
                stops: const [0.0, 0.36, 0.7, 1.0],
              ),
            ),
            child: CustomPaint(
              painter: _World(dark: dark, drift: drift),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }

  /// The sky, warmed at dawn and dusk. Dark mode keeps its own dusk palette; the
  /// tint only shifts the top two stops so the meadow at the bottom stays green.
  List<Color> _sky(bool dark, int hour) {
    if (dark) {
      return const [
        Color(0xFF11203D),
        Color(0xFF15294B),
        Color(0xFF122A22),
        Color(0xFF0E2318),
      ];
    }
    const day = [
      Color(0xFF7FC4F5),
      Color(0xFFC4E6FF),
      Color(0xFFE9F7F0),
      Color(0xFFDFF1DF),
    ];
    const dawn = [
      Color(0xFFF7C9A0),
      Color(0xFFFCE1D0),
      Color(0xFFEAF3E6),
      Color(0xFFDFF1DF),
    ];
    const dusk = [
      Color(0xFFF3B58C),
      Color(0xFFF6D3C4),
      Color(0xFFE7EEDF),
      Color(0xFFDCEAD6),
    ];
    if (hour < 8 || hour >= 20) return dawn; // early / late — soft warm light
    if (hour >= 17) return dusk; // evening — amber warmth
    return day; // the bright middle of the day
  }
}

class _World extends CustomPainter {
  _World({required this.dark, required this.drift});
  final bool dark;

  /// 0..1, centred on 0.5. Clouds and birds translate by (drift - 0.5) × a small
  /// amplitude — nearer things move more than far ones, so it parallaxes.
  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const a = 0.5; // faint, so content stays readable
    final u = (w / 400).clamp(0.8, 1.8);
    final land = (h * 0.34).clamp(220.0, 360.0);
    final top = h - land;

    // The sway, in device pixels. Positive drifts right.
    final sway = (drift - 0.5) * 2; // -1..1

    Color c(int light, int darkC) => Color(dark ? darkC : light);
    Paint fill(int l, int d, [double op = a]) =>
        Paint()..color = c(l, d).withValues(alpha: op);

    // sun — barely moves, it is the farthest thing
    final sunX = w * 0.82 + sway * 3 * u;
    canvas.drawCircle(Offset(sunX, h * 0.13), 46 * u, fill(0xFFFFD23E, 0xFFD9BE6A, 0.16));
    canvas.drawCircle(Offset(sunX, h * 0.13), 26 * u, fill(0xFFFFD23E, 0xFFD9BE6A, 0.55));

    // fluffy clouds — the main drifting element
    void cloud(double cx, double cy, double s, double op) {
      final p = fill(0xFFFFFFFF, 0xFF47618F, op);
      canvas.drawCircle(Offset(cx - 26 * s, cy), 16 * s, p);
      canvas.drawCircle(Offset(cx, cy - 10 * s), 22 * s, p);
      canvas.drawCircle(Offset(cx + 26 * s, cy), 16 * s, p);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 34 * s, cy - 2 * s, 68 * s, 18 * s),
          Radius.circular(9 * s),
        ),
        p,
      );
    }

    cloud(w * 0.26 + sway * 16 * u, h * 0.15, 1.0 * u, 0.8);
    cloud(w * 0.66 + sway * 11 * u, h * 0.1, 0.82 * u, 0.65);
    cloud(w * 0.92 + sway * 7 * u, h * 0.24, 0.68 * u, 0.5);

    // birds — light, so they move the most
    final bird = Paint()
      ..color = c(0xFF7EA0E2, 0xFF7A89A6).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * u
      ..strokeCap = StrokeCap.round;
    void fly(double x, double y, double s) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(x + 6 * s, y - 6 * s, x + 12 * s, y)
          ..quadraticBezierTo(x + 18 * s, y - 6 * s, x + 24 * s, y),
        bird,
      );
    }

    fly(w * 0.4 + sway * 22 * u, h * 0.19, 1.0 * u);
    fly(w * 0.49 + sway * 22 * u, h * 0.16, 0.8 * u);

    // snow-capped blue mountains (peaks are a fraction of the land band)
    final mh = land * 0.62;
    canvas.drawPath(
      Path()..moveTo(w * 0.02, top)..lineTo(w * 0.24, top - mh * 0.72)..lineTo(w * 0.46, top)..close(),
      fill(0xFFA6C2EE, 0xFF45608C),
    );
    canvas.drawPath(
      Path()..moveTo(w * 0.34, top)..lineTo(w * 0.6, top - mh)..lineTo(w * 0.9, top)..close(),
      fill(0xFF7EA0E2, 0xFF35496B),
    );
    final snow = fill(0xFFFFFFFF, 0xFFD6E2F5);
    canvas.drawPath(
      Path()..moveTo(w * 0.24, top - mh * 0.72)..lineTo(w * 0.285, top - mh * 0.52)..lineTo(w * 0.195, top - mh * 0.52)..close(),
      snow,
    );
    canvas.drawPath(
      Path()..moveTo(w * 0.6, top - mh)..lineTo(w * 0.65, top - mh * 0.74)..lineTo(w * 0.55, top - mh * 0.74)..close(),
      snow,
    );

    // meadow — three green layers
    void hill(double y, Color colour) {
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..quadraticBezierTo(w * 0.25, y - land * 0.12, w * 0.5, y - land * 0.03)
          ..quadraticBezierTo(w * 0.78, y + land * 0.07, w, y - land * 0.05)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close(),
        Paint()..color = colour.withValues(alpha: a),
      );
    }

    hill(top + land * 0.06, c(0xFFA9E7A6, 0xFF338057));
    hill(top + land * 0.34, c(0xFF74D187, 0xFF266647));

    // a lake nestled in the hills
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.72, top + land * 0.3), width: w * 0.42, height: 18 * u),
      fill(0xFF6FC3EA, 0xFF3F8FD0, 0.6),
    );

    hill(top + land * 0.64, c(0xFF4CB972, 0xFF1C5038));

    // a pine forest
    void pine(double cx, double cy, double s) {
      canvas.drawRect(Rect.fromLTWH(cx - 3 * s, cy, 6 * s, 15 * s), fill(0xFF8A5A3B, 0xFF6A452C));
      canvas.drawPath(
        Path()..moveTo(cx, cy - 44 * s)..lineTo(cx + 18 * s, cy - 12 * s)..lineTo(cx - 18 * s, cy - 12 * s)..close(),
        fill(0xFF2F9C63, 0xFF2F8F5C),
      );
      canvas.drawPath(
        Path()..moveTo(cx, cy - 30 * s)..lineTo(cx + 21 * s, cy + 6 * s)..lineTo(cx - 21 * s, cy + 6 * s)..close(),
        fill(0xFF23794C, 0xFF226B48),
      );
    }

    pine(w * 0.12, top + land * 0.42, 1.0 * u);
    pine(w * 0.21, top + land * 0.56, 0.8 * u);
    pine(w * 0.9, top + land * 0.46, 1.0 * u);

    // a cute bear on the meadow
    canvas.save();
    canvas.translate(w * 0.26, top + land * 0.78);
    canvas.scale(u);
    final bear = fill(0xFFD99F5C, 0xFFB07F45, 0.62);
    final bear2 = fill(0xFFBD8144, 0xFF8F6534, 0.62);
    final face = fill(0xFFF2D7AB, 0xFFD9BD8E, 0.62);
    final dot = Paint()..color = const Color(0xFF3A2A1A).withValues(alpha: 0.5);
    canvas.drawOval(Rect.fromCenter(center: const Offset(-11, 5), width: 14, height: 9), bear2);
    canvas.drawOval(Rect.fromCenter(center: const Offset(11, 5), width: 14, height: 9), bear2);
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -6), width: 32, height: 28), bear);
    canvas.drawCircle(const Offset(-11, -23), 5, bear);
    canvas.drawCircle(const Offset(11, -23), 5, bear);
    canvas.drawCircle(const Offset(0, -19), 12, bear);
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -14), width: 13, height: 10), face);
    canvas.drawCircle(const Offset(-4.5, -21), 1.6, dot);
    canvas.drawCircle(const Offset(4.5, -21), 1.6, dot);
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -16), width: 3.8, height: 2.6), dot);
    canvas.restore();

    // wildflowers
    final stem = Paint()
      ..color = c(0xFF23794C, 0xFF226B48).withValues(alpha: a)
      ..strokeWidth = 2 * u
      ..strokeCap = StrokeCap.round;
    void flower(double x, double y, bool alt) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 8 * u), stem);
      canvas.drawCircle(Offset(x, y - 2 * u), 3.6 * u,
          fill(alt ? 0xFFFFD23E : 0xFFFF7EB0, alt ? 0xFFD9BE6A : 0xFFD16B95, 0.66));
    }

    flower(w * 0.1, top + land * 0.86, false);
    flower(w * 0.52, top + land * 0.9, true);
    flower(w * 0.82, top + land * 0.87, false);
  }

  @override
  bool shouldRepaint(covariant _World old) =>
      old.dark != dark || old.drift != drift;
}
