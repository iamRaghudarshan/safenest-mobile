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

  /// Four parcels, evenly spaced, so there is always one in flight rather than
  /// a gap where nothing is happening.
  static const _parcels = 4;

  /// Each photo in its own colour, cycled.
  ///
  /// Four identical brand-purple tiles read as one thing blinking; four
  /// different ones read as a stream of photographs, which is what it is. These
  /// are the module colours the rest of the app already uses, so it is more
  /// colour without becoming a different palette.
  static const _hues = <Color>[
    Color(0xFF0176D3), // brand
    Color(0xFF16A06A), // ok green
    Color(0xFFE8A413), // warn amber
    Color(0xFF0EA5E9), // sky
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * 0.52;
    const deviceW = 34.0;
    final leftX = 26.0;
    final rightX = size.width - 26.0;

    final from = leftX + deviceW / 2 + 8;
    final to = rightX - deviceW / 2 - 8;

    // ---- the path between them ---------------------------------------------
    // Dashes that travel with the parcels rather than sitting still, and a
    // colour that runs from the phone's end to the computer's, so the whole
    // strip has a direction even in a still screenshot.
    final strip = Rect.fromLTRB(from, midY - 2, to, midY + 2);
    final shader = const LinearGradient(
      colors: [Color(0xFF0176D3), Color(0xFF0EA5E9), Color(0xFF16A06A)],
    ).createShader(strip);
    final dash = Paint()
      ..shader = shader
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final drift = running ? (t * 10) % 10 : 0.0;
    for (var x = from + drift - 10; x < to; x += 10) {
      final a = x.clamp(from, to);
      final b = (x + 4).clamp(from, to);
      if (b > a) canvas.drawLine(Offset(a, midY), Offset(b, midY), dash);
    }

    // ---- the two devices ---------------------------------------------------
    // Each in its own colour rather than both grey: the phone is where the
    // photos are, the computer is where they are going, and colour is what
    // makes that read at a glance.
    _phone(canvas, Offset(leftX, midY), const Color(0xFF0176D3));
    _computer(canvas, Offset(rightX, midY), const Color(0xFF16A06A));

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
        // A slight tilt that settles as it lands, so the tiles feel carried
        // rather than slid along a rail.
        final tilt = math.sin(p * math.pi * 2) * 0.12 * (1 - p);
        _photo(canvas, Offset(x, midY - lift), fade, _hues[i % _hues.length],
            tilt);
      }
    }

    // ---- labels ------------------------------------------------------------
    _label(canvas, 'This phone', Offset(leftX, midY + 30), soft);
    _label(canvas, 'Your computer', Offset(rightX, midY + 30), soft);
  }

  void _photo(
      Canvas canvas, Offset at, double opacity, Color hue, double tilt) {
    const w = 22.0;
    const h = w * 0.8;

    // Rotated about its own centre, so the tilt reads as the tile leaning
    // rather than the whole thing drifting off the path.
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(tilt);

    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(5));

    // A soft glow underneath, in the tile's own colour. This is what makes it
    // look lit rather than pasted on.
    canvas.drawRRect(
        r.shift(const Offset(0, 2)),
        Paint()
          ..color = hue.withValues(alpha: 0.35 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));

    canvas.drawRRect(
        r,
        Paint()
          ..shader = LinearGradient(
            colors: [hue, Color.lerp(hue, Colors.white, 0.42)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect));

    // A white rim, so two tiles overlapping still read as two.
    canvas.drawRRect(
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3);

    // A mountain and a sun, so the parcel reads as a photograph rather than as
    // an abstract square.
    final glyph = Paint()..color = Colors.white.withValues(alpha: 0.95 * opacity);
    canvas.drawCircle(const Offset(-5, -3), 1.9, glyph);
    final tri = Path()
      ..moveTo(-7.5, 5.5)
      ..lineTo(-1, -1.5)
      ..lineTo(3, 2.5)
      ..lineTo(5.5, 0)
      ..lineTo(7.5, 5.5)
      ..close();
    canvas.drawPath(tri, glyph);

    canvas.restore();
  }

  void _phone(Canvas canvas, Offset c, Color colour) {
    final rect = Rect.fromCenter(center: c, width: 30, height: 48);
    final body = RRect.fromRectAndRadius(rect, const Radius.circular(7));
    canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            colors: [
              colour.withValues(alpha: 0.28),
              colour.withValues(alpha: 0.10)
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(rect));
    canvas.drawRRect(
        body,
        Paint()
          ..color = colour.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
    // The home line, and a speaker slot — enough to read as a phone.
    final ink = Paint()
      ..color = colour.withValues(alpha: 0.85)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(c.dx - 5, c.dy + 18), Offset(c.dx + 5, c.dy + 18), ink);
    canvas.drawLine(
        Offset(c.dx - 4, c.dy - 19), Offset(c.dx + 4, c.dy - 19), ink);
  }

  void _computer(Canvas canvas, Offset c, Color colour) {
    final rect = Rect.fromCenter(center: Offset(c.dx, c.dy - 5), width: 46, height: 32);
    final screen = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(
        screen,
        Paint()
          ..shader = LinearGradient(
            colors: [
              colour.withValues(alpha: 0.28),
              colour.withValues(alpha: 0.10)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect));
    canvas.drawRRect(
        screen,
        Paint()
          ..color = colour.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
    final ink = Paint()
      ..color = colour.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // The stand.
    canvas.drawLine(Offset(c.dx - 10, c.dy + 15), Offset(c.dx + 10, c.dy + 15), ink);
    canvas.drawLine(Offset(c.dx, c.dy + 11), Offset(c.dx, c.dy + 15), ink);
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

