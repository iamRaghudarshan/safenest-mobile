/// Habits: build a routine on the customer's own machine, tick each day, keep
/// the streak. Like every screen here it is a thin client — the habit, its goal
/// and its whole history live on the computer; this lists them, records a tap,
/// and shows the streak the server computed. No habit state is judged here.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../dates.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/skeleton.dart';

// The server stores the accent as the web app's CSS variable so a habit looks
// the same on both. The phone cannot read a CSS var, so map the eight offered
// colours back to real ones — falling back to the habits accent.
const _kHabitColours = <String, Color>{
  'var(--c-habits)': Color(0xFFF97316),
  'var(--c-todo)': Color(0xFF14B8A6),
  'var(--c-reminders)': Color(0xFF8B5CF6),
  'var(--c-insurance)': Color(0xFF0EA5E9),
  'var(--c-investments)': Color(0xFF10B981),
  'var(--c-cards)': Color(0xFFEC4899),
  'var(--c-loans)': Color(0xFF6366F1),
  'var(--c-expenses)': Color(0xFFF59E0B),
};
Color _colour(String css) => _kHabitColours[css] ?? const Color(0xFFF97316);

const _kEmojis = ['💧', '🏃', '📚', '🧘', '💪', '🥗', '😴', '🚭', '☕', '🎯', '✍️', '🎸', '🦷', '🌅'];
const _kWeekdays = [
  (1, 'M'), (2, 'T'), (3, 'W'), (4, 'T'), (5, 'F'), (6, 'S'), (7, 'S'),
];

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
bool _bool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
String _str(dynamic v) => v == null ? '' : '$v';

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});
  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/habits');
      setState(() {
        _items = [
          for (final e in ((d as Map)['items'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _check(Map<String, dynamic> h, {int? count}) async {
    try {
      await context.read<Session>().api.post(
          '/api/habits/${h['id']}/check', count == null ? {} : {'count': count});
      await _load();
    } on ApiError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HabitEditor(existing: existing),
    );
    if (body == null) return;
    try {
      final api = context.read<Session>().api;
      if (existing != null) {
        await api.put('/api/habits/${existing['id']}', body);
      } else {
        await api.post('/api/habits', body);
      }
      await _load();
    } on ApiError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _archive(Map<String, dynamic> h) async {
    await context.read<Session>().api.post('/api/habits/${h['id']}/archive');
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${_str(h['name'])}”?'),
        content: const Text('Its whole history goes with it. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<Session>().api.delete('/api/habits/${h['id']}');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final doneToday = _items.where((h) => _bool(h['done_today'])).length;
    final dueToday = _items.where((h) => _bool(h['active_today'])).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        bottom: _items.isEmpty || _loading
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('$doneToday of $dueToday done today',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('New habit'),
      ),
      body: _loading
          ? const SkeletonList()
          : _error != null
              ? _Problem(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? _Empty(onAdd: () => _edit())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                        itemCount: _items.length,
                        itemBuilder: (ctx, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _HabitCard(
                            h: _items[i],
                            onCheck: (c) => _check(_items[i], count: c),
                            onOpen: () => _openDetail(_items[i]),
                            onEdit: () => _edit(_items[i]),
                            onArchive: () => _archive(_items[i]),
                            onDelete: () => _delete(_items[i]),
                          ),
                        ),
                      ),
                    ),
    );
  }

  void _openDetail(Map<String, dynamic> h) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HabitDetail(h: h),
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.h,
    required this.onCheck,
    required this.onOpen,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });
  final Map<String, dynamic> h;
  final void Function(int? count) onCheck;
  final VoidCallback onOpen, onEdit, onArchive, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = _colour(_str(h['color']));
    final done = _bool(h['done_today']);
    final activeToday = _bool(h['active_today']);
    final target = _int(h['target']);
    final unit = _str(h['unit']);
    final todayCount = _int(h['today_count']);
    final streak = _int(h['current_streak']);
    final measured = target > 1 && unit.isNotEmpty;
    final icon = _str(h['icon']);

    void tapCircle() {
      if (measured) {
        onCheck(done ? 0 : (todayCount + 1 > target ? target : todayCount + 1));
      } else {
        onCheck(done ? 0 : null);
      }
    }

    return BrandCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          GestureDetector(
            onTap: tapCircle,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? c : c.withValues(alpha: 0.12),
                border: Border.all(color: c, width: 2),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 24)
                    : Text(icon.isEmpty ? '◎' : icon, style: const TextStyle(fontSize: 20)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_str(h['name']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (streak > 0) ...[
                      Text('🔥 $streak',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                          measured
                              ? '$todayCount/$target $unit today'
                              : done
                                  ? 'Done today'
                                  : activeToday
                                      ? 'Not yet today'
                                      : 'Rest day',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ]),
                ]),
          ),
          _WeekStrip(week: (h['week'] as List? ?? const []), colour: c),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'archive') onArchive();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                  value: 'archive',
                  child: Text(_bool(h['archived']) ? 'Un-archive' : 'Archive')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        if (measured && activeToday) ...[
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 4),
            IconButton(
              onPressed: todayCount <= 0 ? null : () => onCheck(todayCount - 1),
              icon: const Icon(Icons.remove_circle_outline),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: target == 0 ? 0 : (todayCount / target).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: c.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(c),
                ),
              ),
            ),
            IconButton(
              onPressed: () => onCheck(todayCount + 1),
              icon: const Icon(Icons.add_circle_outline),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ],
      ]),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.week, required this.colour});
  final List week;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < week.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _dot(week[i] as Map, i == week.length - 1),
          ),
      ],
    );
  }

  Widget _dot(Map d, bool today) {
    final done = _bool(d['done']);
    final active = _bool(d['active']);
    Color bg;
    if (done) {
      bg = colour;
    } else if (active) {
      bg = colour.withValues(alpha: 0.2);
    } else {
      bg = Colors.grey.withValues(alpha: 0.25);
    }
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: today ? Border.all(color: colour, width: 1.5) : null,
      ),
    );
  }
}

/// Add / edit. Collects the fields and returns the body map to the caller, which
/// does the create/update — the same split the record modules use.
class _HabitEditor extends StatefulWidget {
  const _HabitEditor({this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _note;
  String _icon = '🎯';
  String _color = 'var(--c-habits)';
  String _kind = 'build';
  String _goal = 'daily';
  final Set<int> _days = {};
  int _target = 1;
  int _weekly = 3;
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: _str(e?['name']));
    _unit = TextEditingController(text: _str(e?['unit']));
    _note = TextEditingController(text: _str(e?['note']));
    if (e != null) {
      _icon = _str(e['icon']).isEmpty ? '🎯' : _str(e['icon']);
      _color = _str(e['color']).isEmpty ? 'var(--c-habits)' : _str(e['color']);
      _kind = _str(e['kind']).isEmpty ? 'build' : _str(e['kind']);
      _goal = _str(e['goal_type']).isEmpty ? 'daily' : _str(e['goal_type']);
      _target = _int(e['target_count']) < 1 ? 1 : _int(e['target_count']);
      _weekly = _int(e['weekly_target']) < 1 ? 3 : _int(e['weekly_target']);
      for (final p in _str(e['weekdays']).split(',')) {
        final n = int.tryParse(p.trim());
        if (n != null && n >= 1 && n <= 7) _days.add(n);
      }
      final t = _str(e['reminder_time']);
      if (t.contains(':')) {
        final parts = t.split(':');
        _time = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (_goal == 'weekdays' && _days.isEmpty) return;
    final t = _time;
    Navigator.pop(context, <String, dynamic>{
      'name': name,
      'icon': _icon,
      'color': _color,
      'kind': _kind,
      'goal_type': _goal,
      'weekdays': _goal == 'weekdays' ? (_days.toList()..sort()).join(',') : '',
      'target_count': _target,
      'unit': _target > 1 ? _unit.text.trim() : '',
      'weekly_target': _weekly,
      'reminder_time': t == null
          ? ''
          : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      'note': _note.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 4, 18, bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.existing != null ? 'Edit habit' : 'New habit',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            decoration: const InputDecoration(labelText: 'Habit', hintText: 'Drink water'),
          ),
          const SizedBox(height: 14),
          _label('Icon'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _kEmojis)
              GestureDetector(
                onTap: () => setState(() => _icon = e),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _icon == e ? kBrand : Theme.of(context).dividerColor,
                        width: _icon == e ? 2 : 1),
                    color: _icon == e ? kBrand.withValues(alpha: 0.1) : null,
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          _label('Colour'),
          Row(children: [
            for (final entry in _kHabitColours.entries)
              GestureDetector(
                onTap: () => setState(() => _color = entry.key),
                child: Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.value,
                    border: Border.all(
                        color: _color == entry.key ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 3),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          _label('Type'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'build', label: Text('Build')),
              ButtonSegment(value: 'quit', label: Text('Quit')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 14),
          _label('How often'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'daily', label: Text('Daily')),
              ButtonSegment(value: 'weekdays', label: Text('Days')),
              ButtonSegment(value: 'weekly', label: Text('Weekly')),
            ],
            selected: {_goal},
            onSelectionChanged: (s) => setState(() => _goal = s.first),
          ),
          if (_goal == 'weekdays') ...[
            const SizedBox(height: 12),
            Row(children: [
              for (final d in _kWeekdays)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      onTap: () => setState(() =>
                          _days.contains(d.$1) ? _days.remove(d.$1) : _days.add(d.$1)),
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _days.contains(d.$1) ? kBrand : Theme.of(context).dividerColor,
                              width: _days.contains(d.$1) ? 2 : 1),
                          color: _days.contains(d.$1) ? kBrand.withValues(alpha: 0.1) : null,
                        ),
                        child: Text(d.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
            ]),
          ],
          if (_goal == 'weekly') ...[
            const SizedBox(height: 12),
            Row(children: [
              _label('Days per week:'),
              const SizedBox(width: 12),
              _Stepper(value: _weekly, min: 1, max: 7, onChanged: (v) => setState(() => _weekly = v)),
            ]),
          ],
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Target per day'),
              _Stepper(value: _target, min: 1, max: 99, onChanged: (v) => setState(() => _target = v)),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _unit,
                enabled: _target > 1,
                decoration: const InputDecoration(labelText: 'Unit', hintText: 'glasses, min…'),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(_time == null ? 'No reminder' : 'Reminder at ${_time!.format(context)}',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            if (_time != null)
              TextButton(onPressed: () => setState(() => _time = null), child: const Text('Clear')),
            TextButton(
              onPressed: () async {
                final picked = await showTimePicker(
                    context: context, initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0));
                if (picked != null) setState(() => _time = picked);
              },
              child: Text(_time == null ? 'Set time' : 'Change'),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'Why this matters'),
          ),
          const SizedBox(height: 18),
          BrandButton(
            label: widget.existing != null ? 'Save changes' : 'Add habit',
            onPressed: _save,
          ),
        ]),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: Theme.of(context).textTheme.labelLarge),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});
  final int value, min, max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            onPressed: value <= min ? null : () => onChanged(value - 1),
            icon: const Icon(Icons.remove_circle_outline)),
        Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        IconButton(
            onPressed: value >= max ? null : () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline)),
      ]);
}

/// The calendar and the numbers. History comes from the server, laid out as the
/// last thirteen weeks in columns of seven days.
class _HabitDetail extends StatefulWidget {
  const _HabitDetail({required this.h});
  final Map<String, dynamic> h;
  @override
  State<_HabitDetail> createState() => _HabitDetailState();
}

class _HabitDetailState extends State<_HabitDetail> {
  Map<String, bool> _done = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<Session>().api.get('/api/habits/${widget.h['id']}/history');
      final days = (d as Map)['days'] as List? ?? const [];
      final m = <String, bool>{};
      for (final e in days) {
        m['${(e as Map)['date']}'] = _bool(e['done']);
      }
      if (mounted) setState(() { _done = m; _loading = false; });
    } on ApiError {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.h;
    final c = _colour(_str(h['color']));
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    // Monday twelve weeks back.
    final start = todayMid.subtract(Duration(days: (todayMid.weekday - 1) + 12 * 7));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_str(h['icon'])} ${_str(h['name'])}'.trim(),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        Row(children: [
          _stat('Current', '🔥 ${_int(h['current_streak'])}', c),
          const SizedBox(width: 10),
          _stat('Best', '${_int(h['best_streak'])}', c),
          const SizedBox(width: 10),
          _stat('30-day', '${_int(h['rate30'])}%', c),
        ]),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var w = 0; w < 13; w++)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Column(children: [
                      for (var day = 0; day < 7; day++)
                        _cell(start.add(Duration(days: w * 7 + day)), todayMid, c),
                    ]),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(_goalLine(h), style: Theme.of(context).textTheme.bodySmall),
        if (_str(h['note']).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(_str(h['note']), style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }

  String _goalLine(Map h) {
    final t = _int(h['target']);
    final unit = _str(h['unit']);
    final suffix = (t > 1 && unit.isNotEmpty) ? ' · $t $unit/day' : '';
    switch (_str(h['goal_type'])) {
      case 'weekly':
        final n = _int(h['weekly_target']);
        return 'Goal: $n day${n == 1 ? '' : 's'} a week$suffix';
      case 'weekdays':
        return 'Goal: on chosen weekdays$suffix';
      default:
        return 'Goal: every day$suffix';
    }
  }

  Widget _cell(DateTime d, DateTime today, Color c) {
    final future = d.isAfter(today);
    final key = wireDate(d);
    final done = _done[key] ?? false;
    return Container(
      width: 15,
      height: 15,
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: future ? Colors.transparent : (done ? c : Colors.grey.withValues(alpha: 0.2)),
      ),
    );
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
          ]),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 48, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: kModuleColours['habits'],
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.local_fire_department, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('No habits yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text('Add one thing to do each day and tick it off — the streak does the rest.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.55, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 190),
              child: BrandButton(label: 'Add a habit', icon: Icons.add, onPressed: onAdd),
            ),
          ]),
        )
      ]);
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 48, 22, 20),
          child: Column(children: [
            const Text('📡', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 12),
            const Text('Can’t load habits right now',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 190),
              child: BrandButton(label: 'Try again', onPressed: onRetry),
            ),
          ]),
        )
      ]);
}
