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
/// THE PARCELS ARE THE REAL PHOTOGRAPHS. They used to be coloured squares
/// with a mountain-and-sun glyph drawn on them, which is a picture OF a
/// backup rather than a picture of yours. Handed the thumbnails actually in
/// flight, it flies those instead, and the animation stops being decoration:
/// it is the only place on the screen that shows the photo leaving. The
/// drawn tile stays as the fallback for the moment before a thumbnail has
/// decoded, and for anything that cannot produce one.
///
/// It STOPS when the backup stops. An animation that keeps looping after a run
/// has finished says the work is still going on, and someone watching it will
/// wait for something that already happened.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';


class BackupFlight extends StatefulWidget {
  const BackupFlight({
    super.key,
    required this.running,
    this.photos = const [],
  });

  /// Whether photos are actually moving right now.
  final bool running;

  /// The thumbnails in flight, to fly instead of drawn tiles. Empty is
  /// perfectly normal — before the first has decoded, and on the retry
  /// screen — and the painter falls back to the drawn tile.
  final List<ui.Image> photos;

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
      // Fills the card it sits in rather than perching in the top of it. The
      // painter scales to whatever it is given, so this is the only number
      // that decides how big the whole scene is.
      height: 176,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _FlightPainter(
            t: _c.value,
            running: widget.running,
            photos: widget.photos,
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
    required this.photos,
    required this.dark,
    required this.line,
    required this.ink,
    required this.soft,
  });

  final double t;
  final bool running;
  final List<ui.Image> photos;
  final bool dark;
  final Color line;
  final Color ink;
  final Color soft;

  /// Three parcels, evenly spaced, so there is always one in flight rather
  /// than a gap where nothing is happening.
  ///
  /// Three and not four. Scaling the canvas to fill its box divides the
  /// LOGICAL width by the same factor it multiplies everything else, so the
  /// path between the devices gets shorter in the coordinates the photos are
  /// spaced in — and four tiles at a readable size ended up overlapping in a
  /// heap in the middle. Fewer, bigger, evenly spread reads better than four
  /// stacked on top of each other.
  static const _parcels = 3;

  /// How wide a photo in flight is. Shared by the drawing and by the ends of
  /// the path, which must allow for it or the tile overlaps a device.
  static const _photoW = 28.0;

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

  /// The height everything below was drawn against. The canvas is scaled by
  /// how far it differs, so one number on the widget resizes the whole scene
  /// — devices, photos, dashes and strokes together. Scaling the canvas
  /// rather than every constant is what keeps the proportions right: a 2px
  /// stroke that stayed 2px while the phone doubled would look like a
  /// different drawing.
  static const _designH = 128.0;

  @override
  void paint(Canvas canvas, Size outer) {
    final k = outer.height / _designH;
    canvas.save();
    canvas.scale(k);
    _paintScene(canvas, Size(outer.width / k, outer.height / k));
    canvas.restore();
  }

  void _paintScene(Canvas canvas, Size size) {
    final midY = size.height * 0.48;
    // Half-widths, stated separately: a laptop is wider than a phone, and one
    // shared constant made the flight path start inside the laptop's lid.
    // Logical half-widths. They look small next to the rendered result
    // because the whole canvas is scaled up around them.
    const phoneHalf = 17.0;
    const laptopHalf = 27.0;
    final leftX = phoneHalf + 10;
    final rightX = size.width - laptopHalf - 10;

    // The PARCEL's half-width is part of this, not just the device's. It was
    // not, and once the photos were drawn at a readable size the last one
    // landed on top of the laptop's lid before fading — the tile is 34 wide,
    // so its edge reached 5 pixels past where the path was told to stop.
    const parcelHalf = _photoW / 2;
    final from = leftX + phoneHalf + parcelHalf + 4;
    final to = rightX - laptopHalf - parcelHalf - 4;

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
        final lift = math.sin(p * math.pi) * 15;
        final fade = (math.sin(p * math.pi) * 1.6).clamp(0.0, 1.0);
        // A slight tilt that settles as it lands, so the tiles feel carried
        // rather than slid along a rail.
        final tilt = math.sin(p * math.pi * 2) * 0.12 * (1 - p);
        // One parcel per photo in flight where there are any, so four
        // uploads really are four tiles carrying four different pictures.
        final image = photos.isEmpty ? null : photos[i % photos.length];
        _photo(canvas, Offset(x, midY - lift), fade, _hues[i % _hues.length],
            tilt, image);
      }
    }

    // ---- labels ------------------------------------------------------------
    _label(canvas, 'This phone', Offset(leftX, midY + 40), soft);
    _label(canvas, 'Your computer', Offset(rightX, midY + 40), soft);
  }

  void _photo(Canvas canvas, Offset at, double opacity, Color hue,
      double tilt, ui.Image? image) {
    const w = _photoW;
    const h = w * 0.78;

    // Rotated about its own centre, so the tilt reads as the tile leaning
    // rather than the whole thing drifting off the path.
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(tilt);

    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    // A soft glow underneath, in the tile's own colour. This is what makes it
    // look lit rather than pasted on.
    canvas.drawRRect(
        r.shift(const Offset(0, 2)),
        Paint()
          ..color = hue.withValues(alpha: 0.35 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));

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

    if (image != null) {
      // The real photograph, clipped into the tile and cropped to fill it
      // rather than squashed — a stretched thumbnail is worse than the drawn
      // glyph it replaced.
      canvas.save();
      canvas.clipRRect(r);
      final src = _cover(image, w / h);
      canvas.drawImageRect(image, src, rect,
          Paint()..color = Colors.white.withValues(alpha: opacity));
      canvas.restore();
      // The rim again, over the picture, so overlapping tiles still read as
      // two.
      canvas.drawRRect(
          r,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.9 * opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3);
    } else {
      // A mountain and a sun, so a parcel with no thumbnail yet still reads
      // as a photograph rather than as an abstract square.
      final glyph =
          Paint()..color = Colors.white.withValues(alpha: 0.95 * opacity);
      canvas.drawCircle(const Offset(-7.5, -4.5), 2.8, glyph);
      final tri = Path()
        ..moveTo(-11.5, 8.5)
        ..lineTo(-1.5, -2.5)
        ..lineTo(4.5, 4)
        ..lineTo(8, 0)
        ..lineTo(11.5, 8.5)
        ..close();
      canvas.drawPath(tri, glyph);
    }

    canvas.restore();
  }

  /// The largest centred rectangle of `image` with the tile's aspect ratio,
  /// so the picture is cropped to fit rather than distorted.
  static Rect _cover(ui.Image image, double aspect) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) return Rect.fromLTWH(0, 0, iw, ih);
    if (iw / ih > aspect) {
      final w = ih * aspect;
      return Rect.fromLTWH((iw - w) / 2, 0, w, ih);
    }
    final h = iw / aspect;
    return Rect.fromLTWH(0, (ih - h) / 2, iw, h);
  }

  /// A phone that looks like a phone.
  ///
  /// The old one was a rounded rectangle with two lines on it, which at this
  /// size read as a blank card. What makes a phone recognisable in 34x54
  /// pixels is not detail, it is the RIGHT detail: a dark bezel with a lit
  /// screen inset inside it, the pill cut out at the top, the home bar at the
  /// bottom, and the side buttons breaking the silhouette. Anything more is
  /// invisible at this scale and anything less is a card.
  void _phone(Canvas canvas, Offset c, Color colour) {
    const w = 34.0, h = 56.0;
    final body = Rect.fromCenter(center: c, width: w, height: h);
    final shell = RRect.fromRectAndRadius(body, const Radius.circular(8));

    // A soft drop shadow, so the device sits ON the surface rather than in it.
    canvas.drawRRect(
        shell.shift(const Offset(0, 2)),
        Paint()
          ..color = Colors.black.withValues(alpha: dark ? 0.45 : 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    // The metal shell: a vertical gradient is what reads as a rounded edge
    // catching the light.
    canvas.drawRRect(
        shell,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [const Color(0xFF3A3F45), const Color(0xFF1C1F22)]
                : [const Color(0xFF8E979F), const Color(0xFF5A636B)],
          ).createShader(body));

    // The screen, inset so the bezel shows all the way round.
    final glassRect = body.deflate(2.6);
    final glass = RRect.fromRectAndRadius(glassRect, const Radius.circular(6));
    canvas.drawRRect(
        glass,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colour.withValues(alpha: 0.95),
              Color.lerp(colour, const Color(0xFF0B3D62), 0.55)!,
            ],
          ).createShader(glassRect));

    // A few photo tiles on the screen. This is a backup of PHOTOS, and a
    // blank blue screen says nothing about that.
    canvas.save();
    canvas.clipRRect(glass);
    final tile = Paint()..color = Colors.white.withValues(alpha: 0.22);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 2; col++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(glassRect.left + 3.5 + col * 11.5,
                    glassRect.top + 6.5 + row * 11.5, 9.5, 9.5),
                const Radius.circular(2)),
            tile);
      }
    }
    // A diagonal sheen across the glass.
    canvas.drawPath(
        Path()
          ..moveTo(glassRect.left, glassRect.top + 14)
          ..lineTo(glassRect.right, glassRect.top - 4)
          ..lineTo(glassRect.right, glassRect.top + 6)
          ..lineTo(glassRect.left, glassRect.top + 24)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: 0.10));
    canvas.restore();

    // The pill at the top, drawn in the shell colour so it reads as a cut-out
    // rather than a sticker.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, body.top + 6), width: 11, height: 3.4),
            const Radius.circular(2)),
        Paint()..color = const Color(0xFF15181B).withValues(alpha: 0.92));

    // The home bar.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, body.bottom - 5), width: 13, height: 2),
            const Radius.circular(1)),
        Paint()..color = Colors.white.withValues(alpha: 0.65));

    // Side buttons: two on the left, one longer on the right. They break the
    // outline, which is most of what makes a rectangle read as a device.
    final btn = Paint()
      ..color = dark ? const Color(0xFF2A2E33) : const Color(0xFF6E777F);
    for (final y in [c.dy - 11.0, c.dy - 3.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(body.left - 1.2, y, 1.6, 6),
              const Radius.circular(1)),
          btn);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(body.right - 0.4, c.dy - 8, 1.6, 10),
            const Radius.circular(1)),
        btn);
  }

  /// A laptop that looks like a laptop.
  ///
  /// The old one was a rectangle on a line — which is the icon for a monitor,
  /// not a laptop, and it is what made the pair look like clip art. A laptop
  /// reads from three things at this size: a lid with a visible bezel, a BASE
  /// that is wider than the lid and tapers towards the viewer, and the hinge
  /// line between them. The taper is the part that sells it; a plain
  /// rectangle underneath looks like a shelf.
  void _computer(Canvas canvas, Offset c, Color colour) {
    const lidW = 54.0, lidH = 37.0;
    final lid = Rect.fromCenter(
        center: Offset(c.dx, c.dy - 5), width: lidW, height: lidH);
    final shell = RRect.fromRectAndRadius(lid, const Radius.circular(4.5));

    canvas.drawRRect(
        shell.shift(const Offset(0, 2)),
        Paint()
          ..color = Colors.black.withValues(alpha: dark ? 0.45 : 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    canvas.drawRRect(
        shell,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [const Color(0xFF3A3F45), const Color(0xFF1C1F22)]
                : [const Color(0xFF8E979F), const Color(0xFF5A636B)],
          ).createShader(lid));

    // The screen.
    final scrRect = lid.deflate(2.4);
    final screen = RRect.fromRectAndRadius(scrRect, const Radius.circular(3));
    canvas.drawRRect(
        screen,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colour.withValues(alpha: 0.95),
              Color.lerp(colour, const Color(0xFF07331F), 0.55)!,
            ],
          ).createShader(scrRect));

    // A grid of arrived photos, denser than the phone's: this is where they
    // all end up.
    canvas.save();
    canvas.clipRRect(screen);
    final tile = Paint()..color = Colors.white.withValues(alpha: 0.22);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 5; col++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(scrRect.left + 2.5 + col * 9.9,
                    scrRect.top + 3 + row * 10.2, 8.2, 8.2),
                const Radius.circular(1.6)),
            tile);
      }
    }
    canvas.drawPath(
        Path()
          ..moveTo(scrRect.left, scrRect.top + 12)
          ..lineTo(scrRect.right, scrRect.top - 6)
          ..lineTo(scrRect.right, scrRect.top + 2)
          ..lineTo(scrRect.left, scrRect.top + 20)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: 0.10));
    canvas.restore();

    // The camera dot in the top bezel.
    canvas.drawCircle(Offset(c.dx, lid.top + 1.2), 0.8,
        Paint()..color = Colors.black.withValues(alpha: 0.5));

    // THE BASE, tapering outwards towards the viewer. Wider at the front than
    // the lid is, which is what gives the whole thing depth.
    final baseTop = lid.bottom + 0.5;
    final baseBottom = baseTop + 5.5;
    final base = Path()
      ..moveTo(c.dx - lidW / 2 - 1, baseTop)
      ..lineTo(c.dx + lidW / 2 + 1, baseTop)
      ..lineTo(c.dx + lidW / 2 + 6, baseBottom)
      ..lineTo(c.dx - lidW / 2 - 6, baseBottom)
      ..close();
    canvas.drawPath(
        base,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [const Color(0xFF2F343A), const Color(0xFF474D54)]
                : [const Color(0xFF9AA3AB), const Color(0xFFC3CAD1)],
          ).createShader(Rect.fromLTRB(
              c.dx - lidW / 2 - 6, baseTop, c.dx + lidW / 2 + 6, baseBottom)));

    // The hinge, and the thumb notch in the front edge.
    canvas.drawLine(
        Offset(c.dx - lidW / 2, baseTop + 0.4),
        Offset(c.dx + lidW / 2, baseTop + 0.4),
        Paint()
          ..color = Colors.black.withValues(alpha: dark ? 0.55 : 0.28)
          ..strokeWidth = 1);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, baseBottom), width: 14, height: 2.2),
            const Radius.circular(1.6)),
        Paint()..color = Colors.black.withValues(alpha: dark ? 0.40 : 0.16));
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
      old.t != t ||
      old.running != running ||
      old.dark != dark ||
      !identical(old.photos, photos);
}

