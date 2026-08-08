/// Photos flying from the phone to the computer, while a backup runs.
///
/// A progress bar answers "how far", and nothing on the screen answered "what
/// is actually happening". People asked whether the photos were being sent
/// somewhere else — a reasonable thing to wonder about an app whose whole
/// promise is that they are not. Two named devices with the photos travelling
/// between them says it in one glance: from this phone, to YOUR computer, and
/// nowhere in between.
///
/// It draws itself — no asset, no package. A Lottie file would be another
/// dependency, another few hundred kilobytes in the download, and one more
/// thing to have gone stale when the brand colour changes.
///
/// It STOPS when the backup stops. An animation that keeps looping after a run
/// has finished says the work is still going on, and someone watching it will
/// wait for something that already happened.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class BackupFlight extends StatefulWidget {
  const BackupFlight({super.key, required this.running});

  /// Whether photos are actually moving right now.
  final bool running;

  @override
  State<BackupFlight> createState() => _BackupFlightState();
}

class _BackupFlightState extends State<BackupFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.running) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant BackupFlight old) {
    super.didUpdateWidget(old);
    if (widget.running && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.running && _c.isAnimating) {
      // stop(), not reset(): the parcels finish where they are rather than
      // snapping back to the phone, which reads as the transfer being undone.
      _c.stop();
    }
  }

  @override
  void dispose() {
    // A ticker left running holds the whole screen alive and keeps the phone's
    // display pipeline busy for a backup that ended minutes ago.
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 96,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _FlightPainter(
            t: _c.value,
            running: widget.running,
            dark: dark,
            line: Theme.of(context).colorScheme.outlineVariant,
            ink: Theme.of(context).colorScheme.onSurface,
            soft: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FlightPainter extends CustomPainter {
  _FlightPainter({
    required this.t,
    required this.running,
    required this.dark,
    required this.line,
    required this.ink,
    required this.soft,
  });

  final double t;
  final bool running;
  final bool dark;
  final Color line;
  final Color ink;
  final Color soft;

  /// Three parcels, evenly spaced along the path, so there is always one in
  /// flight rather than a gap where nothing is happening.
  static const _parcels = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * 0.52;
    const deviceW = 34.0;
    final leftX = 26.0;
    final rightX = size.width - 26.0;

    // ---- the dotted path between them -------------------------------------
    final path = Paint()
      ..color = line
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final from = leftX + deviceW / 2 + 8;
    final to = rightX - deviceW / 2 - 8;
    for (var x = from; x < to; x += 9) {
      canvas.drawLine(Offset(x, midY), Offset(x + 3.5, midY), path);
    }

    // ---- the two devices ---------------------------------------------------
    _phone(canvas, Offset(leftX, midY), soft);
    _computer(canvas, Offset(rightX, midY), soft);

    // ---- the photos in flight ---------------------------------------------
    if (running) {
      for (var i = 0; i < _parcels; i++) {
        final p = (t + i / _parcels) % 1.0;
        // Ease out at the end so a parcel settles into the computer instead of
        // arriving at full speed and vanishing.
        final eased = 1 - math.pow(1 - p, 1.7).toDouble();
        final x = from + (to - from) * eased;
        // A gentle arc, and a fade at both ends so nothing pops into existence
        // in the middle of the empty line.
        final lift = math.sin(p * math.pi) * 13;
        final fade = (math.sin(p * math.pi) * 1.6).clamp(0.0, 1.0);
        _photo(canvas, Offset(x, midY - lift), fade, p);
      }
    }

    // ---- labels ------------------------------------------------------------
    _label(canvas, 'This phone', Offset(leftX, midY + 30), soft);
    _label(canvas, 'Your computer', Offset(rightX, midY + 30), soft);
  }

  void _photo(Canvas canvas, Offset at, double opacity, double p) {
    const w = 19.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: at, width: w, height: w * 0.82),
      const Radius.circular(4),
    );
    canvas.drawRRect(
        r,
        Paint()
          ..shader = const LinearGradient(colors: [kBrand, kBrand2])
              .createShader(r.outerRect)
          ..color = Colors.white.withValues(alpha: opacity));
    // A tiny mountain-and-sun, so the parcel reads as a photograph rather than
    // as an abstract square.
    final glyph = Paint()..color = Colors.white.withValues(alpha: 0.9 * opacity);
    canvas.drawCircle(Offset(at.dx - 4, at.dy - 2.6), 1.7, glyph);
    final tri = Path()
      ..moveTo(at.dx - 6.5, at.dy + 5)
      ..lineTo(at.dx - 0.5, at.dy - 1.5)
      ..lineTo(at.dx + 6.5, at.dy + 5)
      ..close();
    canvas.drawPath(tri, glyph);
  }

  void _phone(Canvas canvas, Offset c, Color colour) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 28, height: 46),
      const Radius.circular(6),
    );
    canvas.drawRRect(body, Paint()..color = colour.withValues(alpha: 0.16));
    canvas.drawRRect(
        body,
        Paint()
          ..color = colour.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
    canvas.drawLine(Offset(c.dx - 4, c.dy + 17), Offset(c.dx + 4, c.dy + 17),
        Paint()
          ..color = colour.withValues(alpha: 0.55)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round);
  }

  void _computer(Canvas canvas, Offset c, Color colour) {
    final screen = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(c.dx, c.dy - 5), width: 44, height: 30),
      const Radius.circular(4),
    );
    canvas.drawRRect(screen, Paint()..color = colour.withValues(alpha: 0.16));
    canvas.drawRRect(
        screen,
        Paint()
          ..color = colour.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
    // The stand.
    canvas.drawLine(Offset(c.dx - 9, c.dy + 14), Offset(c.dx + 9, c.dy + 14),
        Paint()
          ..color = colour.withValues(alpha: 0.55)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(c.dx, c.dy + 10), Offset(c.dx, c.dy + 14),
        Paint()
          ..color = colour.withValues(alpha: 0.55)
          ..strokeWidth = 1.8);
  }

  void _label(Canvas canvas, String text, Offset centre, Color colour) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: colour, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(centre.dx - tp.width / 2, centre.dy));
  }

  @override
  bool shouldRepaint(covariant _FlightPainter old) =>
      old.t != t || old.running != running || old.dark != dark;
}
