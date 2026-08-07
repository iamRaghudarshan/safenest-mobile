/// `.skel-*` — placeholder cards while a list loads.
///
/// WHY THIS INSTEAD OF A SPINNER
/// The web app has never shown a bare spinner on a list screen, and the comment
/// in Scaffold.tsx says why: "showing the shape of what is coming reads as
/// loading far more clearly than a lone spinner on a blank screen." A centred
/// grey circle on an empty page is indistinguishable from a screen that has
/// broken, and on a phone talking to a laptop over a home network that wait is
/// long enough for the difference to matter.
///
/// The shimmer is the same 1.4s sweep, built from --ink-faint at 14% and 26% so
/// it works in both themes without a second set of greys.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 3});
  final int count;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
      itemCount: widget.count,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: softShadow(dark),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _Shimmer(_c, width: 42, height: 42, radius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Shimmer(_c, widthFactor: 0.52, height: 11),
                  const SizedBox(height: 7),
                  _Shimmer(_c, widthFactor: 0.34, height: 9),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            _Shimmer(_c, widthFactor: 0.68, height: 15),
          ]),
        ),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer(this.controller,
      {this.width, this.widthFactor, required this.height, this.radius = 6});

  final Animation<double> controller;
  final double? width;
  final double? widthFactor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final faint = Theme.of(context).colorScheme.outline;
    final low = faint.withValues(alpha: 0.14);
    final high = faint.withValues(alpha: 0.26);

    final bar = AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        // background-size: 400% and a sweep across it — the same movement the
        // CSS keyframes make, expressed as a shifting gradient stop.
        final t = controller.value * 2 - 0.5;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: [low, high, low],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );

    if (widthFactor == null) return bar;
    return FractionallySizedBox(
        alignment: Alignment.centerLeft, widthFactor: widthFactor, child: bar);
  }
}
