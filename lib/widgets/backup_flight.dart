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
    this.done = false,
    this.filled = true,
    this.level = 0,
    this.photos = const [],
    this.onDark = false,
  });

  /// Whether the computer has anything on it.
  ///
  /// The laptop was always drawn with a lit screen full of photographs, which
  /// is fine three states out of four and a flat contradiction in the fourth:
  /// a red block reading "Nothing was sent" over a picture of a computer full
  /// of pictures. People believe the drawing — it is the part they look at
  /// first — so the drawing has to be true.
  final bool filled;

  /// HOW FULL THE COMPUTER IS, 0 to 1 — and the reason the picture is worth
  /// looking at rather than merely watching. A grid of identical squares says
  /// "a computer with photographs on it" whatever is happening; a level that
  /// rises as the run proceeds says how far it has got, in the one place on
  /// the screen somebody is already looking.
  final double level;

  /// Whether photos are actually moving right now.
  final bool running;

  /// The run FINISHED, and the photographs are on the computer.
  ///
  /// Stopping the loop was only half of it: a scene with a dashed, empty path
  /// between two devices says "nothing is happening", which is also what it
  /// says before anybody has pressed the button. Those are opposite facts and
  /// the drawing could not tell them apart. Arrived draws the path solid and
  /// puts a tick on the computer, so the picture agrees with the words above
  /// it instead of quietly contradicting them.
  final bool done;

  /// The thumbnails in flight, to fly instead of drawn tiles. Empty is
  /// perfectly normal — before the first has decoded, and on the retry
  /// screen — and the painter falls back to the drawn tile.
  final List<ui.Image> photos;

  /// Drawn on a dark surface, whatever the app's theme is.
  ///
  /// The scene picks its shells and label colour from the theme's brightness,
  /// which is right until it is placed on a deep hero card in a light app —
  /// where a pale phone body and grey labels disappear. This says "the
  /// surface under me is dark", which is a different question from "the app
  /// is in dark mode".
  final bool onDark;

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
    final dark = widget.onDark ||
        Theme.of(context).brightness == Brightness.dark;
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
            arrived: widget.done,
            filled: widget.filled,
            level: widget.level,
            photos: widget.photos,
            dark: dark,
            line: widget.onDark
                ? Colors.white24
                : Theme.of(context).colorScheme.outlineVariant,
            ink: widget.onDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            soft: widget.onDark
                ? Colors.white70
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// The device labels' preferred size, and the floor they may shrink to.
///
/// Public so the fitting rule can be asserted rather than eyeballed. A
/// screenshot cannot judge this one: `flutter test` ships no font, so the
/// labels render as filled boxes whose widths are nothing like a real
/// phone's — which is exactly the kind of thing that "looked fine" and then
/// ran off the edge of a real screen.
const double kFlightLabelPt = 10.5;

/// Below this it stops being readable, so the label is allowed to touch the
/// gutter rather than shrink further. Reached only by a translation far
/// longer than anything English produces.
const double kFlightLabelMinPt = 7.5;

/// Lay a device label out at a given size. Shared by the painter and its test
/// so both measure the same thing.
TextPainter layOutLabel(String text, Color colour, double pt) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colour, fontSize: pt, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

/// The largest size at which [text] fits [budget], never above
/// [kFlightLabelPt] and never below [kFlightLabelMinPt].
///
/// One step, computed rather than searched: type width scales linearly with
/// size, so the ratio lands inside on the first go and a loop would only
/// spend layouts arriving at the same answer.
double fitLabelPt(String text, Color colour, double budget) {
  if (budget <= 0) return kFlightLabelMinPt;
  final w = layOutLabel(text, colour, kFlightLabelPt).width;
  if (w <= budget) return kFlightLabelPt;
  return (kFlightLabelPt * budget / w)
      .clamp(kFlightLabelMinPt, kFlightLabelPt)
      .toDouble();
}

class _FlightPainter extends CustomPainter {
  _FlightPainter({
    required this.t,
    required this.running,
    required this.arrived,
    required this.filled,
    required this.level,
    required this.photos,
    required this.dark,
    required this.line,
    required this.ink,
    required this.soft,
  });

  final double t;
  final bool running;
  final bool arrived;
  final bool filled;
  final double level;
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
    if (arrived) {
      // Unbroken, because the journey is over. A dashed line is a line with
      // gaps in it, and gaps are what "still going" looks like.
      canvas.drawLine(Offset(from, midY), Offset(to, midY), dash);
    } else {
      final drift = running ? (t * 10) % 10 : 0.0;
      for (var x = from + drift - 10; x < to; x += 10) {
        final a = x.clamp(from, to);
        final b = (x + 4).clamp(from, to);
        if (b > a) canvas.drawLine(Offset(a, midY), Offset(b, midY), dash);
      }
    }

    // ---- the two devices ---------------------------------------------------
    // Each in its own colour rather than both grey: the phone is where the
    // photos are, the computer is where they are going, and colour is what
    // makes that read at a glance.
    _phone(canvas, Offset(leftX, midY), const Color(0xFF0176D3));
    // Unlit and empty when nothing has reached it. Slate rather than green,
    // and the grid of arrived photos drops away with the colour.
    _computer(canvas, Offset(rightX, midY),
        filled ? const Color(0xFF16A06A) : const Color(0xFF454C54));

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

    // ---- the tick, once they have all arrived ------------------------------
    // On the COMPUTER, not floating in the middle. Where a confirmation is
    // placed is half of what it says: on the computer it means "they are
    // here", anywhere else it is a generic success mark that could as easily
    // be about the phone.
    if (arrived) {
      final at = Offset(rightX + laptopHalf - 4, midY - 22);
      canvas.drawCircle(
          at.translate(0, 1.5),
          6.5,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(at, 6.5, Paint()..color = Colors.white);
      canvas.drawPath(
          Path()
            ..moveTo(at.dx - 3.0, at.dy + 0.2)
            ..lineTo(at.dx - 0.8, at.dy + 2.4)
            ..lineTo(at.dx + 3.2, at.dy - 2.4),
          Paint()
            ..color = const Color(0xFF14795A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.9
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }

    // ---- labels ------------------------------------------------------------
    _label(canvas, 'This phone', Offset(leftX, midY + 40), soft, size.width);
    _label(canvas, 'Your computer', Offset(rightX, midY + 40), soft,
        size.width);
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

  /// THE TWO DEVICES, MADE TO LOOK LIKE DEVICES.
  ///
  /// Two attempts came before this. The first was hardware clip-art — grey
  /// bodies, a green computer, a blue phone, tile grids. The second went the
  /// other way and drew them flat, thin outlines and a tinted face, which was
  /// cleaner and still did not look like anything you could pick up.
  ///
  /// What actually makes a 34-pixel rectangle read as a phone is not detail,
  /// it is the four things the eye uses to tell metal and glass from paint:
  ///
  ///   * THE SCREEN IS NEARLY BLACK. A real screen is dark and lit from
  ///     within. Filling it with a brand colour is the single thing that made
  ///     the earlier ones look like icons.
  ///   * ONE LIGHT SOURCE, top-left. The body is a gradient along that
  ///     diagonal and carries a bright hairline on the lit edge, which is what
  ///     a rounded metal rim does and what nothing else does.
  ///   * A REFLECTION across the glass — a soft diagonal band, low enough to
  ///     be felt rather than seen.
  ///   * A TIGHT CONTACT SHADOW directly under the device, not a halo around
  ///     it. A blurred ring in every direction says "sticker"; a short dark
  ///     ellipse under the bottom edge says the thing is standing there.
  ///
  /// Everything else — buttons breaking the silhouette, the camera dot, the
  /// keyboard deck in perspective — is secondary, and all of it is drawn in
  /// neutral metal so it reads the same whatever colour the panel behind it
  /// happens to be.

  /// The metal of a body, lit from the top-left.
  Shader _metal(Rect r) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xFF6E757E), Color(0xFF353A41), Color(0xFF23272C)]
            : const [Color(0xFFCFD4DA), Color(0xFF9BA2AA), Color(0xFF6E757D)],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(r);

  /// A screen: nearly black, with the device's own glow in it, then whatever
  /// content it is showing, then the reflection over the top.
  void _glass(Canvas canvas, RRect g, Color glow, void Function() content) {
    final rect = g.outerRect;
    canvas.drawRRect(g, Paint()..color = const Color(0xFF0A0C0F));

    // The light the screen itself makes, strongest where the content is.
    canvas.save();
    canvas.clipRRect(g);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              glow.withValues(alpha: 0.38),
              glow.withValues(alpha: 0.06),
            ],
          ).createShader(rect));
    content();

    // The reflection. A band across the upper third, which is where a sheet of
    // glass under a ceiling light actually catches it.
    canvas.drawPath(
        Path()
          ..moveTo(rect.left, rect.top + rect.height * 0.46)
          ..lineTo(rect.right, rect.top - rect.height * 0.06)
          ..lineTo(rect.right, rect.top + rect.height * 0.16)
          ..lineTo(rect.left, rect.top + rect.height * 0.68)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: 0.055));
    canvas.restore();

    // The black rim where the glass meets the frame.
    canvas.drawRRect(
        g,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
  }

  /// A short dark ellipse under the bottom edge. See the note above: this is
  /// what makes a drawing stand on the panel instead of float over it.
  void _contact(Canvas canvas, Offset centre, double width) {
    canvas.drawOval(
        Rect.fromCenter(center: centre, width: width, height: 5),
        Paint()
          ..color = Colors.black.withValues(alpha: dark ? 0.38 : 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }

  /// The lit hairline along the top-left edge of a metal body.
  void _rimLight(Canvas canvas, RRect body) {
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRRect(
        body.deflate(0.4),
        Paint()
          ..color = Colors.white.withValues(alpha: dark ? 0.30 : 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1);
    // Cut the highlight back to the lit side by laying a soft dark wash over
    // the opposite corner.
    canvas.drawRect(
        body.outerRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.5),
            ],
            stops: const [0.0, 0.35, 1.0],
          ).createShader(body.outerRect)
          ..blendMode = BlendMode.dstOut);
    canvas.restore();
  }

  void _phone(Canvas canvas, Offset c, Color colour) {
    const w = 33.0, h = 58.0;
    final body = Rect.fromCenter(center: c, width: w, height: h);
    final shell = RRect.fromRectAndRadius(body, const Radius.circular(8.5));

    _contact(canvas, Offset(c.dx, body.bottom - 1), w * 0.92);

    // Side buttons first, so they sit UNDER the body edge and read as part of
    // the frame rather than as pills stuck to it.
    final btn = Paint()
      ..shader = _metal(Rect.fromLTWH(body.left - 2, body.top, 4, h));
    for (final y in [c.dy - 13.0, c.dy - 4.5]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(body.left - 1.3, y, 2.2, 7),
              const Radius.circular(1.1)),
          btn);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(body.right - 0.9, c.dy - 9, 2.2, 11),
            const Radius.circular(1.1)),
        btn);

    canvas.drawRRect(shell, Paint()..shader = _metal(body));
    _rimLight(canvas, shell);

    final glassRect = body.deflate(2.2);
    final glass = RRect.fromRectAndRadius(glassRect, const Radius.circular(6.8));
    _glass(canvas, glass, colour, () {
      // Photographs on the screen, in two columns — this is a backup OF
      // photographs and a dark rectangle says that to nobody.
      final tile = Paint()..color = colour.withValues(alpha: 0.62);
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 2; col++) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(glassRect.left + 2.6 + col * 12.6,
                      glassRect.top + 7 + row * 11.2, 11, 9.4),
                  const Radius.circular(1.6)),
              tile);
        }
      }
    });

    // The island, slightly inset from the top the way a real one is.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, body.top + 6), width: 11, height: 3.4),
            const Radius.circular(1.8)),
        Paint()..color = const Color(0xFF05070A));

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, body.bottom - 4.6), width: 12, height: 1.8),
            const Radius.circular(1)),
        Paint()..color = Colors.white.withValues(alpha: 0.5));
  }

  /// A laptop, open, seen slightly from above — which is the only angle at
  /// which a keyboard deck reads as a keyboard deck and not as a shelf.
  void _computer(Canvas canvas, Offset c, Color colour) {
    const lidW = 54.0, lidH = 35.0;
    final lid = Rect.fromCenter(
        center: Offset(c.dx, c.dy - 8), width: lidW, height: lidH);
    final shell = RRect.fromRectAndRadius(lid, const Radius.circular(3.4));

    const deckDrop = 6.5;
    final deckTop = lid.bottom;
    final deckBottom = deckTop + deckDrop;
    const overhang = 7.0;

    _contact(canvas, Offset(c.dx, deckBottom + 0.5), lidW + overhang * 2);

    canvas.drawRRect(shell, Paint()..shader = _metal(lid));
    _rimLight(canvas, shell);

    final scrRect = lid.deflate(2.2);
    final screen = RRect.fromRectAndRadius(scrRect, const Radius.circular(1.8));
    _glass(canvas, screen, colour, () {
      // THE LEVEL, as photographs arriving rather than a colour wash: the
      // tiles light up row by row from the bottom as the run proceeds, so the
      // screen shows what has landed instead of merely how far along it is.
      const cols = 5, rows = 3;
      final lit = filled ? (level.clamp(0.0, 1.0) * rows * cols).ceil() : 0;
      final tw = (scrRect.width - 3) / cols;
      final th = (scrRect.height - 3) / rows;
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < cols; col++) {
          // Counted from the bottom row upwards.
          final index = (rows - 1 - row) * cols + col;
          final on = index < lit;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(scrRect.left + 1.5 + col * tw,
                      scrRect.top + 1.5 + row * th, tw - 1.2, th - 1.2),
                  const Radius.circular(1.2)),
              Paint()
                ..color = on
                    ? colour.withValues(alpha: 0.78)
                    : Colors.white.withValues(alpha: 0.05));
        }
      }
    });

    // The camera, in the bezel above the screen.
    canvas.drawCircle(Offset(c.dx, lid.top + 1.1), 0.75,
        Paint()..color = const Color(0xFF05070A));

    // THE DECK, in perspective: wider at the front than the lid, because that
    // is what a keyboard seen from slightly above does.
    final deck = Path()
      ..moveTo(c.dx - lidW / 2, deckTop)
      ..lineTo(c.dx + lidW / 2, deckTop)
      ..lineTo(c.dx + lidW / 2 + overhang, deckBottom)
      ..lineTo(c.dx - lidW / 2 - overhang, deckBottom)
      ..close();
    canvas.drawPath(
        deck,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF2B3036), Color(0xFF50575F)]
                : const [Color(0xFF878E96), Color(0xFFC6CCD3)],
          ).createShader(Rect.fromLTRB(
              c.dx - lidW / 2 - overhang, deckTop,
              c.dx + lidW / 2 + overhang, deckBottom)));

    // The keyboard well, and the trackpad in front of it. Two shapes is all
    // there is room for, and two shapes is all it takes.
    final well = Path()
      ..moveTo(c.dx - lidW / 2 + 4, deckTop + 1.2)
      ..lineTo(c.dx + lidW / 2 - 4, deckTop + 1.2)
      ..lineTo(c.dx + lidW / 2 - 1, deckTop + 4.2)
      ..lineTo(c.dx - lidW / 2 + 1, deckTop + 4.2)
      ..close();
    canvas.drawPath(
        well, Paint()..color = Colors.black.withValues(alpha: 0.30));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, deckTop + 5.3), width: 15, height: 1.8),
            const Radius.circular(0.9)),
        Paint()..color = Colors.black.withValues(alpha: 0.18));

    // The hinge, and the lit front lip.
    canvas.drawLine(
        Offset(c.dx - lidW / 2, deckTop + 0.4),
        Offset(c.dx + lidW / 2, deckTop + 0.4),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..strokeWidth = 1);
    canvas.drawLine(
        Offset(c.dx - lidW / 2 - overhang + 1, deckBottom - 0.4),
        Offset(c.dx + lidW / 2 + overhang - 1, deckBottom - 0.4),
        Paint()
          ..color = Colors.white.withValues(alpha: dark ? 0.22 : 0.5)
          ..strokeWidth = 0.9);
  }

  void _label(Canvas canvas, String text, Offset centre, Color colour,
      double width) {
    // SHRINK TO FIT, rather than only sliding sideways.
    //
    // This clamped the x position and left the size alone, which keeps the
    // label's LEFT edge on the canvas and does nothing whatever about its
    // right one: once the text is wider than the space, the clamp bottoms out
    // at x=2 and the rest simply runs off the edge. On a 390pt phone "Your
    // computer" cleared the edge by about four pixels, which is not fitting,
    // it is luck — and any narrower phone spent it.
    //
    // Half the canvas each, so the two labels also cannot meet in the middle.
    // That is a second failure the old version could not express: both were
    // free to grow toward each other and the only thing keeping "This phone"
    // and "Your computer" apart was that English happens to make them short.
    final budget = width / 2 - 6;

    final tp = layOutLabel(text, colour, fitLabelPt(text, colour, budget));

    // Then centre it under its device, and keep it on the canvas — still
    // needed, because a label that had to stop at the minimum size can be
    // wider than its budget.
    final maxX = (width - tp.width - 2).clamp(2.0, double.infinity);
    final x = (centre.dx - tp.width / 2).clamp(2.0, maxX);
    tp.paint(canvas, Offset(x, centre.dy));
  }

  @override
  bool shouldRepaint(covariant _FlightPainter old) =>
      old.t != t ||
      old.running != running ||
      old.arrived != arrived ||
      old.filled != filled ||
      old.level != level ||
      old.dark != dark ||
      !identical(old.photos, photos);
}

