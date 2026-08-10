/// Drag down the edge of the gallery to travel by month and year.
///
/// A scrollbar answers "how far through am I" and a photo library is not read
/// that way — nobody wants to be 62% of the way down, they want August last
/// year. Twenty thousand photos is a great many flicks, and the alternative
/// people actually use is giving up and searching.
///
/// It shows the date under your thumb WHILE you drag, so you aim at a month
/// rather than scrubbing and checking. Only appears once there is enough to
/// scroll through: a rail beside forty photos is clutter over a problem nobody
/// has.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class DateScrubber extends StatefulWidget {
  const DateScrubber({
    super.key,
    required this.controller,
    required this.labelAt,
    this.minExtent = 2400,
  });

  final ScrollController controller;

  /// The date to show for a fraction (0..1) of the way down. The gallery knows
  /// its own grouping; this widget deliberately knows nothing about photos.
  final String Function(double fraction) labelAt;

  /// Below this many pixels of scrollable content the rail hides itself.
  final double minExtent;

  @override
  State<DateScrubber> createState() => _DateScrubberState();
}

class _DateScrubberState extends State<DateScrubber> {
  bool _dragging = false;
  double _fraction = 0;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final p = widget.controller.position;
    final show = p.maxScrollExtent > widget.minExtent;
    final f = p.maxScrollExtent <= 0
        ? 0.0
        : (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
    // Only rebuild when something a person can see has changed. A setState per
    // scroll frame over a grid this size is a stutter.
    if (show != _visible || (!_dragging && (f - _fraction).abs() > 0.004)) {
      setState(() {
        _visible = show;
        _fraction = f;
      });
    }
  }

  void _jumpTo(double fraction, double railHeight) {
    if (!widget.controller.hasClients) return;
    final p = widget.controller.position;
    // jumpTo, not animateTo: while a thumb is moving, an animation is always
    // chasing a target that has already moved and the grid never settles.
    widget.controller.jumpTo((p.maxScrollExtent * fraction).clamp(0.0, p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: 46,
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          const knob = 46.0;
          final y = (_fraction * (h - knob)).clamp(0.0, h - knob);
          return Stack(children: [
            Positioned(
              top: y,
              right: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => setState(() => _dragging = true),
                onVerticalDragUpdate: (d) {
                  final f = ((y + d.localPosition.dy - knob / 2) / (h - knob))
                      .clamp(0.0, 1.0);
                  setState(() => _fraction = f);
                  _jumpTo(f, h);
                },
                onVerticalDragEnd: (_) => setState(() => _dragging = false),
                onVerticalDragCancel: () => setState(() => _dragging = false),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // The date, to the LEFT of the knob — under a thumb it would
                  // be covered by the thumb, which is the one place it cannot
                  // be read.
                  if (_dragging)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: kBrand,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                              color: kBrand.withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Text(widget.labelAt(_fraction),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ),
                  Container(
                    width: 34,
                    height: knob,
                    decoration: BoxDecoration(
                      color: _dragging
                          ? kBrand
                          : theme.colorScheme.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: softShadow(
                          theme.brightness == Brightness.dark),
                    ),
                    child: Icon(Icons.drag_handle,
                        size: 19,
                        color: _dragging
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
