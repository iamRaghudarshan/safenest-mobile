import 'package:flutter/material.dart';

/// A bright, flat Salesforce-style nature world painted behind EVERY screen
/// (mounted once via MaterialApp.builder, with scaffolds transparent). It mirrors
/// the web app's backdrop: sky, fluffy clouds, a sun, snow-capped blue mountains,
/// a pine forest, a green meadow, a lake and a cute bear — kept faint so cards
/// and text stay legible. Re-colours to dusk in dark mode.
class NatureBackdrop extends StatelessWidget {
  const NatureBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sky = dark
        ? const [Color(0xFF11203D), Color(0xFF15294B), Color(0xFF122A22), Color(0xFF0E2318)]
        : const [Color(0xFF7FC4F5), Color(0xFFC4E6FF), Color(0xFFE9F7F0), Color(0xFFDFF1DF)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: sky,
          stops: const [0.0, 0.36, 0.7, 1.0],
        ),
      ),
      child: CustomPaint(painter: _World(dark: dark), child: const SizedBox.expand()),
    );
  }
}

class _World extends CustomPainter {
  _World({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const a = 0.5; // faint, so content stays readable
    // Every decorative element is sized in this unit so the scene keeps its
    // proportions on any phone (a design width of 400, like the web viewBox).
    final u = (w / 400).clamp(0.8, 1.8);
    // The land occupies the bottom of the screen; a fixed band reads better than a
    // fraction on very tall phones, but is bounded so it never dominates a short one.
    final land = (h * 0.34).clamp(220.0, 360.0);
    final top = h - land;

    Color c(int light, int darkC) => Color(dark ? darkC : light);
    Paint fill(int l, int d, [double op = a]) => Paint()..color = c(l, d).withValues(alpha: op);

    // sun
    canvas.drawCircle(Offset(w * 0.82, h * 0.13), 46 * u, fill(0xFFFFD23E, 0xFFD9BE6A, 0.16));
    canvas.drawCircle(Offset(w * 0.82, h * 0.13), 26 * u, fill(0xFFFFD23E, 0xFFD9BE6A, 0.55));

    // fluffy clouds
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

    cloud(w * 0.26, h * 0.15, 1.0 * u, 0.8);
    cloud(w * 0.66, h * 0.1, 0.82 * u, 0.65);
    cloud(w * 0.92, h * 0.24, 0.68 * u, 0.5);

    // birds
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

    fly(w * 0.4, h * 0.19, 1.0 * u);
    fly(w * 0.49, h * 0.16, 0.8 * u);

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
  bool shouldRepaint(covariant _World old) => old.dark != dark;
}
