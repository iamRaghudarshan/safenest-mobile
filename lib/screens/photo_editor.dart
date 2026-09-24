/// Crop, rotate, adjust, filter and draw on a photo.
///
/// THE RULE, THE SAME ONE THE SERVER ENFORCES: the file the device sent is
/// never overwritten. Every edit is rendered from a pristine copy kept beside
/// it, so a second crop cuts the ORIGINAL again rather than cropping a crop,
/// and "Use original" is always available. See backend/app/photoedit.py.
///
/// WHY THE PREVIEW IS LOCAL AND THE RENDER IS NOT. Dragging a slider has to
/// feel immediate or nobody explores it, and asking a household PC to
/// re-render a twelve-megapixel JPEG for every pixel of slider travel is a
/// screen that stutters. So the phone approximates with a colour matrix and a
/// transform; Save asks the server for the real thing, which is the only
/// version that ever touches the file.
///
/// EVERY COORDINATE IS A FRACTION of the picture — never a pixel. The phone
/// knows the size it happens to be DISPLAYING at, and the server knows the
/// size the photo actually is; sending pixels would mean the two disagreeing
/// about which size that was, and a crop landing somewhere nobody chose.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';

/// The named looks, and the colour matrix that approximates each one for the
/// preview. The server has the authoritative versions in photoedit.py; these
/// only have to be close enough to choose by.
const Map<String, String> kFilterNames = {
  'none': 'Original',
  'vivid': 'Vivid',
  'warm': 'Warm',
  'cool': 'Cool',
  'fade': 'Fade',
  'mono': 'Mono',
  'noir': 'Noir',
  'sepia': 'Sepia',
};

const Map<String, Color> kMarkColours = {
  'red': Color(0xFFE53935),
  'orange': Color(0xFFF57C00),
  'yellow': Color(0xFFFDD835),
  'green': Color(0xFF43A047),
  'blue': Color(0xFF1E88E5),
  'purple': Color(0xFF8E44AD),
  'black': Color(0xFF18181B),
  'white': Color(0xFFFFFFFF),
};

/// Tools, in the order they appear. `redact` is last and on purpose: it is the
/// only one that destroys pixels, and it should not sit under a thumb that
/// meant to reach for the pen.
const List<(String, IconData, String)> kMarkTools = [
  ('pen', Icons.edit, 'Pen'),
  ('highlight', Icons.brush, 'Highlighter'),
  ('arrow', Icons.north_east, 'Arrow'),
  ('rect', Icons.crop_square, 'Box'),
  ('ellipse', Icons.circle_outlined, 'Circle'),
  ('text', Icons.title, 'Text'),
  ('redact', Icons.square, 'Redact'),
];

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({
    super.key,
    required this.api,
    required this.photoId,
    required this.imageUrl,
    this.initial,
  });

  final Api api;
  final int photoId;

  /// Already signed by the server, so it needs no header.
  final String imageUrl;

  /// The edit already applied, so the sliders open where they were left
  /// rather than at zero over a picture that is visibly not unedited.
  final Map<String, dynamic>? initial;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  late Map<String, dynamic> _edit;
  int _tab = 0;
  bool _busy = false;

  // Markup being drawn right now. Held apart from _edit until the finger
  // lifts: committing every move would make Undo step back one POINT at a
  // time instead of one mark.
  Map<String, dynamic>? _wip;
  String _tool = 'pen';
  String _colour = 'red';

  final GlobalKey _frame = GlobalKey();

  @override
  void initState() {
    super.initState();
    _edit = Map<String, dynamic>.from(widget.initial ?? const {});
  }

  double _num(String key, double fallback) {
    final v = _edit[key];
    return v is num ? v.toDouble() : fallback;
  }

  List<Map<String, dynamic>> get _marks =>
      ((_edit['markup'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

  void _setMarks(List<Map<String, dynamic>> next) {
    setState(() {
      if (next.isEmpty) {
        _edit.remove('markup');
      } else {
        _edit['markup'] = next;
      }
    });
  }

  void _set(String key, Object? value) {
    setState(() {
      if (value == null) {
        _edit.remove(key);
      } else {
        _edit[key] = value;
      }
    });
  }

  // ----------------------------------------------------------- geometry

  /// Where a touch falls, as a fraction of the PICTURE — not of the screen.
  Offset? _fractionOf(Offset global) {
    final box = _frame.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0 || box.size.height <= 0) return null;
    final local = box.globalToLocal(global);
    return Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
  }

  // ----------------------------------------------------------- saving

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.post('/api/gallery/${widget.photoId}/edit',
          {'edit': _edit}) as Map;
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

  // ----------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final hasEdit = (widget.initial ?? const {}).isNotEmpty;
    return Scaffold(
      // Dark whatever the theme says: judging a crop or a filter against a
      // light surround means judging it against the wrong one, which is why
      // every editor that does this is dark.
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0D),
        foregroundColor: Colors.white,
        title: const Text('Edit'),
        actions: [
          if (hasEdit)
            TextButton(
              onPressed: _busy ? null : _revert,
              child: const Text('Use original',
                  style: TextStyle(color: Colors.white70)),
            ),
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _stage()),
          _panel(),
        ],
      ),
    );
  }

  Widget _stage() {
    final crop = _edit['crop'] as Map?;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: GestureDetector(
          onPanStart: (d) {
            final p = _fractionOf(d.globalPosition);
            if (p == null) return;
            if (_tab == 3) {
              if (_tool == 'text') {
                _askText(p);
                return;
              }
              setState(() => _wip = {
                    't': _tool,
                    'c': _colour,
                    'w': _tool == 'highlight' ? 0.022 : 0.007,
                    'p': [
                      [p.dx, p.dy]
                    ],
                  });
            } else if (_tab == 0) {
              setState(() {
                _edit['crop'] = {
                  'x': p.dx,
                  'y': p.dy,
                  'w': 0.0,
                  'h': 0.0,
                  '_ax': p.dx,
                  '_ay': p.dy,
                };
              });
            }
          },
          onPanUpdate: (d) {
            final p = _fractionOf(d.globalPosition);
            if (p == null) return;
            if (_tab == 3 && _wip != null) {
              setState(() {
                final pts = (_wip!['p'] as List).cast<List>();
                final freehand = _wip!['t'] == 'pen' || _wip!['t'] == 'highlight';
                if (freehand) {
                  pts.add([p.dx, p.dy]);
                } else {
                  // A shape has two corners, so the second is REPLACED as the
                  // finger moves. Appending would store a thousand corners and
                  // leave the shape defined by whichever was last.
                  if (pts.length < 2) {
                    pts.add([p.dx, p.dy]);
                  } else {
                    pts[1] = [p.dx, p.dy];
                  }
                }
              });
            } else if (_tab == 0) {
              final c = _edit['crop'] as Map?;
              if (c == null) return;
              final ax = (c['_ax'] as num).toDouble();
              final ay = (c['_ay'] as num).toDouble();
              setState(() {
                _edit['crop'] = {
                  'x': math.min(ax, p.dx),
                  'y': math.min(ay, p.dy),
                  'w': (p.dx - ax).abs(),
                  'h': (p.dy - ay).abs(),
                  '_ax': ax,
                  '_ay': ay,
                };
              });
            }
          },
          onPanEnd: (_) {
            if (_tab == 3) {
              final w = _wip;
              setState(() => _wip = null);
              if (w != null && (w['p'] as List).length >= 2) {
                _setMarks([..._marks, w]);
              }
            } else if (_tab == 0) {
              final c = _edit['crop'] as Map?;
              if (c != null) {
                final cw = (c['w'] as num).toDouble();
                final ch = (c['h'] as num).toDouble();
                // A tap, not a drag. Clearing beats keeping a sliver: nobody
                // means to crop a photo to four pixels.
                if (cw < 0.05 || ch < 0.05) {
                  _set('crop', null);
                }
              }
            }
          },
          child: Stack(
            key: _frame,
            children: [
              ColorFiltered(
                colorFilter: _previewFilter(),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..rotateZ(((_edit['rotate'] as num?) ?? 0) * math.pi / 180)
                    // scaleByDouble, not scale: the two-argument scale()
                    // is deprecated and the analyzer is right that it is
                    // ambiguous about the z axis.
                    ..scaleByDouble(
                        _edit['flip'] == true ? -1.0 : 1.0, 1.0, 1.0, 1.0),
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 200,
                      child: Center(
                        child: Text('Could not load the photo',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _Overlay(
                      marks: [..._marks, ?_wip],
                      crop: _tab == 0 ? crop : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The preview's approximation of the server's work. Brightness, contrast
  /// and saturation are folded into one matrix with the named look.
  ColorFilter _previewFilter() {
    final b = _num('brightness', 1);
    final c = _num('contrast', 1);
    final s = _num('saturation', 1);
    final name = (_edit['filter'] ?? 'none').toString();

    List<double> m = _saturation(s);
    m = _multiply(_brightnessContrast(b, c), m);
    final look = _lookMatrix(name);
    if (look != null) m = _multiply(look, m);
    return ColorFilter.matrix(m);
  }

  Widget _panel() {
    return Container(
      color: const Color(0xFF151518),
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, label) in const [
                  (0, 'Crop & rotate'),
                  (1, 'Adjust'),
                  (2, 'Filters'),
                  (3, 'Markup'),
                ])
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
          ),
          const SizedBox(height: 10),
          if (_tab == 0) _cropPanel(),
          if (_tab == 1) _adjustPanel(),
          if (_tab == 2) _filterPanel(),
          if (_tab == 3) _markupPanel(),
        ],
      ),
    );
  }

  Widget _cropPanel() {
    final rot = ((_edit['rotate'] as num?) ?? 0).toInt();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            final next = (rot + 270) % 360;
            _set('rotate', next == 0 ? null : next);
          },
          icon: const Icon(Icons.rotate_left, size: 18),
          label: const Text('Left'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            final next = (rot + 90) % 360;
            _set('rotate', next == 0 ? null : next);
          },
          icon: const Icon(Icons.rotate_right, size: 18),
          label: const Text('Right'),
        ),
        OutlinedButton.icon(
          onPressed: () => _set('flip', _edit['flip'] == true ? null : true),
          icon: const Icon(Icons.flip, size: 18),
          label: const Text('Flip'),
        ),
        if (_edit['crop'] != null)
          OutlinedButton(
            onPressed: () => _set('crop', null),
            child: const Text('Clear crop'),
          ),
        if (_edit['crop'] == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Drag across the photo to crop it',
                style: TextStyle(color: Colors.white54, fontSize: 12.5)),
          ),
      ],
    );
  }

  Widget _adjustPanel() {
    return Column(
      children: [
        for (final (key, label) in const [
          ('brightness', 'Brightness'),
          ('contrast', 'Contrast'),
          ('saturation', 'Saturation'),
          ('sharpness', 'Sharpness'),
        ])
          Row(
            children: [
              SizedBox(
                width: 86,
                child: Text(label,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ),
              Expanded(
                child: Slider(
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  value: _num(key, 1).clamp(0.5, 2.0),
                  onChanged: (v) =>
                      _set(key, (v - 1).abs() < 0.02 ? null : double.parse(v.toStringAsFixed(2))),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text('${_num(key, 1).toStringAsFixed(2)}×',
                    textAlign: TextAlign.right,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
      ],
    );
  }

  Widget _filterPanel() {
    final current = (_edit['filter'] ?? 'none').toString();
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final entry in kFilterNames.entries)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () =>
                    _set('filter', entry.key == 'none' ? null : entry.key),
                child: Column(
                  children: [
                    // The swatch is the REAL photo under that look, so the
                    // choice is made by looking rather than by reading a word.
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: current == entry.key
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(
                              _lookMatrix(entry.key) ?? _identity()),
                          child: Image.network(widget.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: Colors.black26)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(entry.value,
                        style: TextStyle(
                            fontSize: 11,
                            color: current == entry.key
                                ? Colors.white
                                : Colors.white60)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _markupPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (key, icon, label) in kMarkTools)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _tool == key,
                    onSelected: (_) => setState(() => _tool = key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final entry in kMarkColours.entries)
              GestureDetector(
                onTap: () => setState(() => _colour = entry.key),
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _colour == entry.key
                          ? Colors.white
                          : Colors.white24,
                      width: 2,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            // Undo removes the whole MARK, which is why a stroke is only
            // committed when the finger lifts.
            TextButton(
              onPressed: _marks.isEmpty
                  ? null
                  : () => _setMarks(_marks.sublist(0, _marks.length - 1)),
              child: const Text('Undo'),
            ),
            TextButton(
              onPressed: _marks.isEmpty ? null : () => _setMarks(const []),
              child: const Text('Clear'),
            ),
          ],
        ),
        if (_tool == 'redact')
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Redaction removes what is underneath. “Use original” can still '
              'bring the photo back.',
              style: TextStyle(color: Color(0xFFFFD9C2), fontSize: 11.5),
            ),
          ),
      ],
    );
  }

  Future<void> _askText(Offset at) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(hintText: 'Rent receipt'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    _setMarks([
      ..._marks,
      {
        't': 'text',
        'c': _colour,
        'w': 0.02,
        'text': text,
        'p': [
          [at.dx, at.dy]
        ],
      }
    ]);
  }

  // ------------------------------------------------- colour matrices

  static List<double> _identity() => <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _saturation(double s) {
    // Luminance weights, the same ones every image library uses.
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final inv = 1 - s;
    return <double>[
      inv * lr + s, inv * lg, inv * lb, 0, 0, //
      inv * lr, inv * lg + s, inv * lb, 0, 0, //
      inv * lr, inv * lg, inv * lb + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _brightnessContrast(double b, double c) {
    // Brightness is a MULTIPLIER here, matching PIL's enhancer on the server —
    // not the offset ffmpeg uses. Mixing the two conventions is how a preview
    // and a render end up disagreeing.
    final t = (1 - c) * 127.5;
    return <double>[
      b * c, 0, 0, 0, t, //
      0, b * c, 0, 0, t, //
      0, 0, b * c, 0, t, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double>? _lookMatrix(String name) {
    switch (name) {
      case 'mono':
        return _saturation(0);
      case 'noir':
        return _multiply(_brightnessContrast(1, 1.35), _saturation(0));
      case 'sepia':
        return <double>[
          0.393, 0.769, 0.189, 0, 0, //
          0.349, 0.686, 0.168, 0, 0, //
          0.272, 0.534, 0.131, 0, 0, //
          0, 0, 0, 1, 0, //
        ];
      case 'vivid':
        return _saturation(1.45);
      case 'fade':
        return _multiply(_brightnessContrast(1.05, 0.75), _identity());
      case 'warm':
        return <double>[
          1.08, 0, 0, 0, 0, //
          0, 1, 0, 0, 0, //
          0, 0, 0.93, 0, 0, //
          0, 0, 0, 1, 0, //
        ];
      case 'cool':
        return <double>[
          0.93, 0, 0, 0, 0, //
          0, 1, 0, 0, 0, //
          0, 0, 1.08, 0, 0, //
          0, 0, 0, 1, 0, //
        ];
      default:
        return null;
    }
  }

  /// a · b, for 4x5 colour matrices.
  static List<double> _multiply(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        // The fifth column is an offset, not a coefficient, so it carries
        // through rather than being summed over. Getting this wrong makes
        // every contrast change also shift the brightness.
        if (col == 4) sum += a[row * 5 + 4];
        out[row * 5 + col] = sum;
      }
    }
    return out;
  }
}

/// Draws the marks and the crop box over the picture, in the same fractional
/// space the server renders them in — so what is on screen is what gets saved.
class _Overlay extends CustomPainter {
  _Overlay({required this.marks, this.crop});

  final List<Map<String, dynamic>> marks;
  final Map? crop;

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in marks) {
      final pts = ((m['p'] as List?) ?? const [])
          .whereType<List>()
          .map((p) => Offset(
                (p[0] as num).toDouble() * size.width,
                (p[1] as num).toDouble() * size.height,
              ))
          .toList();
      if (pts.isEmpty) continue;

      final colour = kMarkColours[m['c']] ?? kMarkColours['red']!;
      final stroke = math.max(
          2.0,
          ((m['w'] as num?)?.toDouble() ?? 0.007) *
              math.min(size.width, size.height));
      final tool = (m['t'] ?? 'pen').toString();

      if (tool == 'text') {
        final tp = TextPainter(
          text: TextSpan(
            text: (m['text'] ?? '').toString(),
            style: TextStyle(
              color: colour,
              fontSize: stroke * 6,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pts.first);
        continue;
      }

      if (tool == 'redact' || tool == 'rect' || tool == 'ellipse') {
        if (pts.length < 2) continue;
        final r = Rect.fromPoints(pts.first, pts.last);
        final paint = Paint()
          ..color = tool == 'redact' ? const Color(0xFF18181B) : colour
          ..style = tool == 'redact' ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = stroke;
        if (tool == 'ellipse') {
          canvas.drawOval(r, paint);
        } else {
          canvas.drawRect(r, paint);
        }
        continue;
      }

      final paint = Paint()
        ..color = tool == 'highlight' ? colour.withValues(alpha: 0.38) : colour
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = tool == 'highlight' ? stroke * 3 : stroke;

      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);

      if (tool == 'arrow' && pts.length >= 2) {
        // The head is sized from the STROKE, not the arrow's length: a short
        // arrow scaled to its length has almost no head, and a long one ends
        // up with a head the size of a house. Same rule as the server.
        final a = pts.first, b = pts.last;
        final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
        final head = math.max(10.0, stroke * 5);
        for (final spread in const [2.6, -2.6]) {
          canvas.drawLine(
            b,
            Offset(b.dx + head * math.cos(ang + spread),
                b.dy + head * math.sin(ang + spread)),
            paint,
          );
        }
      }
    }

    final c = crop;
    if (c != null) {
      final r = Rect.fromLTWH(
        (c['x'] as num).toDouble() * size.width,
        (c['y'] as num).toDouble() * size.height,
        (c['w'] as num).toDouble() * size.width,
        (c['h'] as num).toDouble() * size.height,
      );
      // Everything OUTSIDE the selection is dimmed, which is what makes a
      // crop readable — a bright outline on a busy photo disappears into it.
      final shade = Paint()..color = Colors.black.withValues(alpha: 0.5);
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRect(r),
        ),
        shade,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_Overlay old) => true;
}
