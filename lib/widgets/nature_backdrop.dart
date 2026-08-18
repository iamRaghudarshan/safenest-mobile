import 'package:flutter/material.dart';

/// A full nature world painted behind EVERY screen (mounted once via
/// MaterialApp.builder, with scaffolds transparent). It mirrors the web app's
/// app-wide backdrop: sky, clouds, birds, a sun, snow-capped mountains, a pine
/// forest, rolling hills, a deer and a rabbit — kept faint so cards and text
/// stay legible. Re-colours to dusk in dark mode.
class NatureBackdrop extends StatelessWidget {
  const NatureBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sky = dark
        ? const [Color(0xFF0E1B34), Color(0xFF122142), Color(0xFF112A22), Color(0xFF0E2318)]
        : const [Color(0xFFBFE4FF), Color(0xFFE2F1FF), Color(0xFFEEF7EF), Color(0xFFDFF1DF)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: sky,
          stops: const [0.0, 0.34, 0.68, 1.0],
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
    const a = 0.46; // faint, so content stays readable
    final top = h * 0.58; // the land occupies the bottom ~42%

    Color c(int light, int darkC) => Color(dark ? darkC : light);
    Paint fill(int l, int d, [double op = a]) =>
        Paint()..color = c(l, d).withValues(alpha: op);

    // sun
    canvas.drawCircle(Offset(w * 0.82, h * 0.15), w * 0.13,
        fill(0xFFFFD76B, 0xFFD9BE6A, 0.16));
    canvas.drawCircle(Offset(w * 0.82, h * 0.15), w * 0.075,
        fill(0xFFFFD76B, 0xFFD9BE6A, 0.55));

    // clouds
    void cloud(double cx, double cy, double s, double op) {
      final p = fill(0xFFFFFFFF, 0xFF3D5680, op);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: 90 * s, height: 40 * s), p);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + 30 * s, cy - 9 * s), width: 58 * s, height: 34 * s), p);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - 28 * s, cy - 4 * s), width: 48 * s, height: 28 * s), p);
    }

    cloud(w * 0.22, h * 0.16, 1.0, 0.7);
    cloud(w * 0.58, h * 0.11, 0.8, 0.6);
    cloud(w * 0.9, h * 0.26, 0.7, 0.5);

    // birds
    final bird = Paint()
      ..color = c(0xFF5B6B86, 0xFF7A89A6).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
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

    fly(w * 0.36, h * 0.2, 1.0);
    fly(w * 0.44, h * 0.17, 0.8);
    fly(w * 0.3, h * 0.19, 0.7);

    // mountains + snow caps
    canvas.drawPath(
      Path()..moveTo(w * 0.06, top)..lineTo(w * 0.26, top - h * 0.22)..lineTo(w * 0.46, top)..close(),
      fill(0xFFB9C9DF, 0xFF33435F),
    );
    canvas.drawPath(
      Path()..moveTo(w * 0.38, top)..lineTo(w * 0.62, top - h * 0.30)..lineTo(w * 0.86, top)..close(),
      fill(0xFFA7BAD6, 0xFF2B3A54),
    );
    final snow = fill(0xFFFFFFFF, 0xFF9FB0CC);
    canvas.drawPath(
      Path()..moveTo(w * 0.26, top - h * 0.22)..lineTo(w * 0.30, top - h * 0.15)..lineTo(w * 0.22, top - h * 0.15)..close(),
      snow,
    );
    canvas.drawPath(
      Path()..moveTo(w * 0.62, top - h * 0.30)..lineTo(w * 0.67, top - h * 0.21)..lineTo(w * 0.57, top - h * 0.21)..close(),
      snow,
    );

    // three rolling hills
    void hill(double y, Color colour) {
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..quadraticBezierTo(w * 0.25, y - h * 0.045, w * 0.5, y - h * 0.012)
          ..quadraticBezierTo(w * 0.78, y + h * 0.028, w, y - h * 0.018)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close(),
        Paint()..color = colour.withValues(alpha: a),
      );
    }

    hill(top + h * 0.02, c(0xFFC2E7C7, 0xFF244A37));
    hill(top + h * 0.13, c(0xFF96D9A6, 0xFF1D3F2E));
    hill(top + h * 0.24, c(0xFF77C98B, 0xFF173425));

    // a pine forest
    void pine(double x, double y, double s) {
      canvas.drawRect(Rect.fromLTWH(x - 3 * s, y, 6 * s, 15 * s),
          fill(0xFF8A5A3B, 0xFF6A452C));
      canvas.drawPath(
        Path()..moveTo(x, y - 44 * s)..lineTo(x + 18 * s, y - 12 * s)..lineTo(x - 18 * s, y - 12 * s)..close(),
        fill(0xFF4FAF7F, 0xFF2F7D59),
      );
      canvas.drawPath(
        Path()..moveTo(x, y - 30 * s)..lineTo(x + 21 * s, y + 6 * s)..lineTo(x - 21 * s, y + 6 * s)..close(),
        fill(0xFF3D9268, 0xFF245F43),
      );
    }

    pine(w * 0.16, top + h * 0.10, 1.0);
    pine(w * 0.24, top + h * 0.16, 0.8);
    pine(w * 0.86, top + h * 0.13, 1.0);
    pine(w * 0.76, top + h * 0.19, 0.85);

    // a deer grazing
    final deer = fill(0xFFB98A5E, 0xFF8A5F3E, 0.55);
    canvas.save();
    canvas.translate(w * 0.52, top + h * 0.14);
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -13), width: 30, height: 16), deer);
    for (final dx in [-11.0, -4.0, 5.0, 9.0]) {
      canvas.drawRect(Rect.fromLTWH(dx, -9, 3, 14), deer);
    }
    canvas.drawPath(
      Path()..moveTo(13, -18)..quadraticBezierTo(22, -20, 22, -31)..lineTo(26, -31)..quadraticBezierTo(28, -18, 18, -12)..close(),
      deer,
    );
    canvas.drawCircle(const Offset(25, -33), 5, deer);
    final antler = Paint()
      ..color = deer.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(22, -37), const Offset(19, -46), antler);
    canvas.drawLine(const Offset(28, -37), const Offset(31, -46), antler);
    canvas.restore();

    // a rabbit in the foreground
    final rab = fill(0xFF9AA6BA, 0xFF59637A, 0.55);
    canvas.save();
    canvas.translate(w * 0.24, top + h * 0.30);
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -8), width: 20, height: 17), rab);
    canvas.drawCircle(const Offset(9, -14), 5.5, rab);
    canvas.drawOval(Rect.fromCenter(center: const Offset(7, -23), width: 4.5, height: 13), rab);
    canvas.drawOval(Rect.fromCenter(center: const Offset(12, -23), width: 4.5, height: 13), rab);
    canvas.drawCircle(const Offset(-9, -5), 3.5, fill(0xFFFFFFFF, 0xFF9FB0CC, 0.6));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _World old) => old.dark != dark;
}
