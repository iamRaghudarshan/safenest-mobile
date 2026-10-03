/// Track Me — where you were, on any day.
///
/// THE DAY IS WORDS FIRST AND A MAP SECOND, which is the opposite of how these
/// screens are usually built. A map answers "where" and answers "when" very
/// badly: you cannot see from a line on a map what time you left, how long you
/// were there, or whether the phone stopped recording for two hours — and those
/// are the questions. So the sentences are the screen, and the map sits above
/// them for the one thing it is better at.
///
/// THE TILES COME FROM THIS HOUSEHOLD'S OWN COMPUTER. places_screen.dart has
/// carried the rule since before this module existed: the request for a tile IS
/// the coordinate, so a map drawn from a public tile host posts a record of
/// everywhere its owner has been to that host. A location timeline makes that
/// very much worse than it was for photos. The server fetches each tile from
/// OpenStreetMap once and keeps it; the phone never speaks to a tile host.
///
/// AND IT IS OFF UNTIL SOMEBODY TURNS IT ON. The switch is on this screen, not
/// buried in Settings, next to the count of what has been recorded and the
/// button that deletes all of it — because the person who wants to stop should
/// not have to go looking, and the person deciding whether to start should be
/// able to see the way out before they do.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../offline/store.dart';
import '../session.dart';
import '../theme.dart';
import '../track/day.dart';
import '../track/recorder.dart';
import '../track/story.dart';

const kTrackTint = Color(0xFF1B6B50);

class TrackScreen extends StatefulWidget {
  const TrackScreen({
    super.key,
    this.embedded = false,
    this.debugFixes,
    this.debugPlaces,
    this.debugNow,
    this.recorder,
  });

  /// True when this IS a tab rather than a screen pushed on top of one.
  final bool embedded;

  /// Fixes and named places to draw instead of reading them, and a fixed clock.
  ///
  /// The same door the rest of the app uses: a widget test runs with a fake
  /// clock that never delivers real file-IO callbacks, so a screen that opens a
  /// database in initState hangs rather than failing. See
  /// `LifeMemoryScreen.debugRows` for the longer note.
  final List<Fix>? debugFixes;
  final List<Named>? debugPlaces;
  final DateTime? debugNow;

  /// Supplied by tests. The real one needs a GPS, and no machine this is
  /// developed on has one.
  final Recorder? recorder;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  late DateTime _day = _today;
  Day _read = const Day(spans: [], metres: 0);
  List<Named> _places = const [];
  bool _loading = true;
  int _kept = 0;

  DateTime get _today {
    final n = widget.debugNow ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  OfflineStore get _store => context.read<OfflineStore>();
  Recorder? get _recorder =>
      widget.recorder ?? (widget.debugFixes != null ? null : _provided);
  Recorder? get _provided {
    try {
      return context.read<Recorder>();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.debugFixes != null) {
      _read = readDay(widget.debugFixes!);
      _places = widget.debugPlaces ?? const [];
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _store.fixesOn(_day);
      final places = await _store.trackPlaces();
      final kept = await _store.fixCount();
      if (!mounted) return;
      setState(() {
        _read = readDay([
          for (final r in rows)
            Fix(
              // Stored UTC, read back local — the day boundary is a local
              // calendar question and a day abroad is otherwise unreadable.
              at: DateTime.parse('${r['at']}').toLocal(),
              lat: (r['lat'] as num).toDouble(),
              lon: (r['lon'] as num).toDouble(),
              accuracy: (r['accuracy'] as num?)?.toDouble() ?? 0,
            ),
        ]);
        _places = [
          for (final p in places)
            Named(
              name: '${p['name']}',
              lat: (p['lat'] as num).toDouble(),
              lon: (p['lon'] as num).toDouble(),
              radius: (p['radius'] as num?)?.toDouble() ?? 150,
            ),
        ];
        _kept = kept;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: _today,
    );
    if (picked == null || !mounted) return;
    setState(() => _day = DateTime(picked.year, picked.month, picked.day));
    await _load();
  }

  Future<void> _toggle(bool on) async {
    final rec = _recorder;
    if (rec == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!on) {
      await rec.stop();
      return;
    }
    final started = await rec.start();
    if (!mounted) return;
    if (!started) {
      messenger.showSnackBar(SnackBar(
          content: Text(_why(rec.problem)),
          duration: const Duration(seconds: 6)));
      return;
    }
    // One fix now, so turning it on puts something on the screen instead of a
    // blank day until the phone next moves a hundred metres.
    await rec.markNow();
    await _load();
  }

  String _why(NoLocation? p) => switch (p) {
        NoLocation.turnedOff =>
          'Location is switched off for the whole phone. Turn it on in '
              'Settings and try again.',
        NoLocation.refusedForGood =>
          'SafeNest has been refused location for good. Only Settings can '
              'change that now — Apps → SafeNest → Permissions.',
        NoLocation.onlyWhileOpen =>
          'SafeNest may only see where you are while the app is open, so your '
              'day will have gaps. Allow it "all the time" to record properly.',
        _ => 'SafeNest has not been allowed to see where you are.',
      };

  Future<void> _forget() async {
    final all = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget where you have been?'),
        content: const Text(
            'There is no bin for this. Everywhere else in SafeNest a deleted '
            'thing can be got back; a record of where you have been is the one '
            'thing that should go when you say so, and go completely.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'day'),
              child: const Text('Just this day')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Text('All of it')),
        ],
      ),
    );
    if (all == null || !mounted) return;
    if (all == 'all') {
      await _store.clearTrack();
    } else {
      await _store.clearTrackDay(_day);
    }
    await _load();
  }

  Future<void> _nameHere(Span span) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('What is this place?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Home, Office, Amma…'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          const SizedBox(height: 12),
          // Said out loud, because it is the reason this is a text box and not
          // a lookup — and because "it names every day you were ever here" is
          // not obvious and is the best thing about it.
          const Text(
              'Nothing is looked up. The name stays on your own machines, and '
              'it names every day you have ever been here — past ones too.',
              style: TextStyle(fontSize: 12, height: 1.45)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Name it')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _store.nameTrackPlace(name: name, lat: span.lat, lon: span.lon);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rec = _recorder;
    final lines = tell(_read, _places, now: widget.debugNow ?? DateTime.now());
    final session = context.read<Session>();
    // Off the Api rather than the Session: the token is private there, and the
    // Api is already the thing that knows how to present it.
    final base = session.baseUrl ?? '';
    final token = session.api.token ?? '';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        backgroundColor: kTrackTint,
        foregroundColor: Colors.white,
        title: const Text('Track Me'),
        actions: [
          IconButton(
            tooltip: 'Another day',
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Forget',
            onPressed: _kept == 0 && _read.isEmpty ? null : _forget,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (rec != null)
            ListenableBuilder(
              listenable: rec,
              builder: (_, _) => _Switch(
                on: rec.recording,
                problem: rec.problem,
                kept: _kept,
                onChanged: _toggle,
              ),
            ),
          _DayBar(
            day: _day,
            today: _today,
            summary: summarise(_read, _places),
            onEarlier: () {
              setState(() => _day = _day.subtract(const Duration(days: 1)));
              _load();
            },
            onLater: _day.isBefore(_today)
                ? () {
                    setState(() => _day = _day.add(const Duration(days: 1)));
                    _load();
                  }
                : null,
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_read.isEmpty)
            _Nothing(recording: rec?.recording ?? false, theme: theme)
          else ...[
            _Map(day: _read, base: base, token: token),
            for (final l in lines)
              _LineRow(
                line: l,
                onName: l.span.kind == Part.stay && l.place == null
                    ? () => _nameHere(l.span)
                    : null,
              ),
            const SizedBox(height: 10),
            _Footer(theme: theme),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

// =============================================================== pieces

class _Switch extends StatelessWidget {
  const _Switch({
    required this.on,
    required this.problem,
    required this.kept,
    required this.onChanged,
  });

  final bool on;
  final NoLocation? problem;
  final int kept;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: on
            ? kTrackTint.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Row(children: [
          Icon(on ? Icons.my_location : Icons.location_disabled,
              size: 20,
              color: on ? kTrackTint : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(on ? 'Recording' : 'Not recording',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  // A NUMBER, not a reassurance. "It is recording" is a claim
                  // somebody has to take on faith; a count of what is actually
                  // stored is the same claim with evidence behind it.
                  Text(
                      kept == 0
                          ? 'Nothing recorded yet'
                          : '$kept position${kept == 1 ? '' : 's'} kept on this '
                              'phone',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant)),
                ]),
          ),
          Switch(value: on, onChanged: onChanged),
        ]),
        if (on && problem == NoLocation.onlyWhileOpen)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 15, color: kWarn),
              const SizedBox(width: 8),
              // IT LOOKS LIKE IT IS WORKING, which is why this is said rather
              // than left to be discovered: the timeline fills in while the
              // phone is open and stops dead the moment it goes in a pocket.
              Expanded(
                child: Text(
                    'Only while the app is open — your day will have gaps. '
                    'Allow location "all the time" to record properly.',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.day,
    required this.today,
    required this.summary,
    required this.onEarlier,
    required this.onLater,
  });

  final DateTime day;
  final DateTime today;
  final String summary;
  final VoidCallback onEarlier;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Row(children: [
        IconButton(
            onPressed: onEarlier,
            tooltip: 'The day before',
            icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Column(children: [
            Text(_dayName(day, today),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 1),
            Text(summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        IconButton(
            onPressed: onLater,
            tooltip: 'The day after',
            icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }
}

String _dayName(DateTime d, DateTime today) {
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return '${d.day} ${months[d.month - 1]}'
      '${d.year == today.year ? '' : ' ${d.year}'}';
}

/// The day's path, drawn from tiles this household fetched itself.
class _Map extends StatelessWidget {
  const _Map({required this.day, required this.base, required this.token});

  final Day day;
  final String base;
  final String token;

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[
      for (final s in day.spans)
        if (s.kind == Part.journey)
          for (final f in s.path) LatLng(f.lat, f.lon),
    ];
    final stays = [
      for (final s in day.stays) LatLng(s.lat, s.lon),
    ];
    final all = [...points, ...stays];
    if (all.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 230,
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.coordinates(
            coordinates: all,
            padding: const EdgeInsets.all(34),
            maxZoom: 16,
          ),
          // No rotation: a timeline read sideways is a timeline nobody reads,
          // and a one-finger drag rotating the map is the commonest way that
          // happens by accident.
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
        ),
        children: [
          TileLayer(
            // THIS HOUSEHOLD'S OWN SERVER. Never a public tile host — see the
            // library note at the top of this file and the rule in
            // places_screen.dart that it is obeying.
            urlTemplate: '$base/api/track/tile/{z}/{x}/{y}.png',
            userAgentPackageName: 'online.raghudarshan.safenest',
            maxNativeZoom: 18,
            // The token goes on the PROVIDER, not the layer. The tile endpoint
            // is guarded like everything else — the set of tiles somebody has
            // fetched is itself a map of where they have been — so an
            // unauthenticated request gets a 401 and the map draws grey.
            tileProvider: NetworkTileProvider(
              headers: {'Authorization': 'Bearer $token'},
              // A tile that will not come is a grey square, not an exception
              // thrown through the widget tree on every pan.
              silenceExceptions: true,
            ),
          ),
          if (points.length > 1)
            PolylineLayer(polylines: [
              Polyline(
                  points: points,
                  strokeWidth: 4,
                  color: kTrackTint.withValues(alpha: 0.85)),
            ]),
          if (stays.isNotEmpty)
            MarkerLayer(markers: [
              for (final s in stays)
                Marker(
                  point: s,
                  width: 18,
                  height: 18,
                  child: Container(
                    decoration: BoxDecoration(
                      color: kTrackTint,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                  ),
                ),
            ]),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.onName});
  final Line line;
  final VoidCallback? onName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, tint) = switch (line.span.kind) {
      Part.stay => (Icons.place, kTrackTint),
      Part.journey => (Icons.trending_flat, theme.colorScheme.primary),
      Part.gap => (Icons.help_outline, theme.colorScheme.onSurfaceVariant),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 17, color: tint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.said,
                    style: const TextStyle(fontSize: 13.5, height: 1.5)),
                // OFFERED ON THE PLACE ITSELF, not in a settings list. The
                // moment somebody is most willing to name "Home" is while
                // looking at a row that says "somewhere you have not named".
                if (onName != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onName,
                    child: const Text('Name this place',
                        style: TextStyle(fontSize: 12)),
                  ),
              ]),
        ),
      ]),
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing({required this.recording, required this.theme});
  final bool recording;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(36, 50, 36, 50),
        child: Column(children: [
          Icon(Icons.map_outlined,
              size: 34, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(recording ? 'Nothing for this day' : 'Not recording',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(
              recording
                  ? 'Either you were not carrying the phone, or it was not '
                      'able to see where it was.'
                  : 'Turn it on above and SafeNest will keep a note of where '
                      'you have been, so you can look back at any day. It is '
                      'kept on this phone and sent only to your own computer.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: theme.colorScheme.onSurfaceVariant)),
        ]),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline,
              size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 7),
          Expanded(
            // SAYING WHERE THE MAP CAME FROM, both because OpenStreetMap asks
            // and because the interesting half is the other one: the phone did
            // not fetch it.
            child: Text(
                'Kept on this phone and your own computer. The map is drawn '
                'from tiles your computer fetched from OpenStreetMap — this '
                'phone never asks anyone else where you are.',
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
        ]),
      );
}
