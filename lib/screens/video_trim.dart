/// Cut a video down to part of itself, and — where the server can — change
/// its speed, steady it, or give it a look.
///
/// TWO KINDS OF OPERATION, AND THE DIFFERENCE MATTERS TO THE PERSON.
///
/// A TRIM is lossless. It changes only the index that says where each frame
/// lives, so nothing is re-encoded, nothing is lost, and it is quick. It needs
/// no extra software on the computer and is always available.
///
/// SPEED, STABILISE and COLOUR genuinely re-encode. They take a while, lose a
/// little quality, and need a transcoder the computer may not have — so the
/// app ASKS whether they are available and does not draw the tab when they are
/// not. A control that is always there and sometimes fails is worse than one
/// that appears only when it works.
///
/// THE LIMIT ON A TRIM, SAID OUT LOUD. A lossless cut can only begin on a
/// keyframe, because every frame between keyframes is described as a
/// difference from earlier ones. The server snaps the start BACK to the
/// nearest one — never forward, which would drop frames somebody asked to
/// keep — and tells us where it landed, so the app can say so rather than
/// leaving somebody to wonder why their clip begins early.
library;

import 'package:flutter/material.dart';

import '../api.dart';

class VideoTrimScreen extends StatefulWidget {
  const VideoTrimScreen({
    super.key,
    required this.api,
    required this.photoId,
    required this.videoUrl,
    required this.durationMs,
    this.initial,
  });

  final Api api;
  final int photoId;
  final String videoUrl;
  final int durationMs;
  final Map<String, dynamic>? initial;

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  double _start = 0;
  late double _end;
  bool _busy = false;
  int _tab = 0;

  /// Whether the SERVER has a transcoder. Asked once; the effects tab is not
  /// drawn at all when it does not.
  bool _canFx = false;
  double _speed = 2;
  String _look = 'mono';

  double get _lenSec => widget.durationMs <= 0 ? 0 : widget.durationMs / 1000;

  @override
  void initState() {
    super.initState();
    _end = _lenSec;
    _askEffects();
  }

  Future<void> _askEffects() async {
    try {
      final r = await widget.api.get('/api/gallery/effects/available');
      if (!mounted) return;
      setState(() => _canFx = r is Map && r['available'] == true);
    } catch (_) {
      // Not an error worth showing: it means the effects tab stays hidden,
      // and trimming — the thing they came for — still works.
      if (mounted) setState(() => _canFx = false);
    }
  }

  Future<void> _trim() async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.post('/api/gallery/${widget.photoId}/trim', {
        'start_ms': (_start * 1000).round(),
        'end_ms': (_end * 1000).round(),
      }) as Map;
      if (!mounted) return;
      if (r['snapped'] == true) {
        // Said, not hidden. The clip begins earlier than the handle was left
        // and nothing about the result explains why.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Trimmed — the cut moved back to '
              '${_clock(((r['start_ms'] as num?) ?? 0) / 1000)} '
              'to land on a keyframe'),
        ));
      }
      Navigator.of(context).pop(r['item']);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _effect(Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      final r = await widget.api
          .post('/api/gallery/${widget.photoId}/effect', body) as Map;
      if (!mounted) return;
      Navigator.of(context).pop(r['item']);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _revert() async {
    setState(() => _busy = true);
    try {
      final r = await widget.api
          .post('/api/gallery/${widget.photoId}/edit/revert', const {}) as Map;
      if (!mounted) return;
      Navigator.of(context).pop(r['item']);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static String _clock(num sec) {
    if (sec.isNaN || sec < 0) sec = 0;
    final total = sec.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasEdit = (widget.initial ?? const {}).isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0D),
        foregroundColor: Colors.white,
        title: const Text('Video'),
        actions: [
          if (hasEdit)
            TextButton(
              onPressed: _busy ? null : _revert,
              child: const Text('Use original',
                  style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.movie_outlined,
                        size: 64, color: Colors.white38),
                    const SizedBox(height: 12),
                    // No player here on purpose. The app has no video widget
                    // on this screen, and adding one to scrub a preview is a
                    // separate piece of work — the handles and the clock are
                    // enough to choose a range, and the result is reversible.
                    Text(
                      _lenSec > 0
                          ? '${_clock(_lenSec)} long'
                          : 'Length unknown',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _panel(),
        ],
      ),
    );
  }

  Widget _panel() {
    return Container(
      color: const Color(0xFF151518),
      padding: EdgeInsets.fromLTRB(
          14, 12, 14, 12 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canFx)
            Row(
              children: [
                for (final (i, label) in const [(0, 'Trim'), (1, 'Effects')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _tab == i,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          if (_tab == 0) ..._trimControls(),
          if (_tab == 1 && _canFx) ..._effectControls(),
        ],
      ),
    );
  }

  List<Widget> _trimControls() {
    final len = _lenSec <= 0 ? 1.0 : _lenSec;
    return [
      // The kept span as a bar. Two numbers alone do not show how much of a
      // clip is being thrown away; a bar does it at a glance.
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(children: [
            Positioned(
              left: (_start / len) * w,
              width: ((_end - _start) / len) * w,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ]),
        );
      }),
      const SizedBox(height: 8),
      _slider('Start', _start, len, (v) {
        setState(() => _start = v.clamp(0.0, _end - 0.2));
      }),
      _slider('End', _end, len, (v) {
        setState(() => _end = v.clamp(_start + 0.2, len));
      }),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Keeping ${_clock(_end - _start)} of ${_clock(len)}. The cut is '
          'lossless, so it can only start on a keyframe — the beginning may '
          'move back slightly.',
          style: const TextStyle(color: Color(0xFFFFD9C2), fontSize: 11.5),
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: (_busy || _end - _start < 0.2) ? null : _trim,
            child: Text(_busy ? 'Trimming…' : 'Trim'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _effectControls() {
    return [
      _slider('Speed', _speed, 4, (v) => setState(() => _speed = v),
          min: 0.25, label: '${_speed.toStringAsFixed(2)}×'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _effect({'kind': 'speed', 'factor': _speed}),
            child: const Text('Apply speed'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _effect({'kind': 'stabilise'}),
            child: const Text('Stabilise'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final look in const ['mono', 'noir', 'sepia', 'vivid', 'fade',
            'warm', 'cool'])
            ChoiceChip(
              label: Text(look),
              selected: _look == look,
              onSelected: (_) => setState(() => _look = look),
            ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _effect({'kind': 'colour', 'filter': _look}),
            child: const Text('Apply look'),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'These re-encode the video, so they take a while and lose a little '
          'quality — unlike trimming, which is lossless. “Use original” still '
          'puts the clip back exactly as it arrived.',
          style: TextStyle(color: Color(0xFFFFD9C2), fontSize: 11.5),
        ),
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('Working… this re-encodes the video',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
    ];
  }

  Widget _slider(String name, double value, double max,
      ValueChanged<double> onChanged,
      {double min = 0, String? label}) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(name,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ),
        Expanded(
          child: Slider(
            min: min,
            max: max <= min ? min + 1 : max,
            value: value.clamp(min, max <= min ? min + 1 : max),
            onChanged: _busy ? null : onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(label ?? _clock(value),
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      ],
    );
  }
}
