/// A month calendar for the Expenses module.
///
/// The list answers "what did I spend on"; the calendar answers "what did a day
/// cost" and "which days were heavy" — the shape you cannot see in a flat list.
/// It works off the rows the screen already holds (no new endpoint), grouping
/// them by `txn_date` the same way the gallery groups photos by the day taken.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../dates.dart';
import '../theme.dart';
import 'motion.dart';

class ExpenseCalendar extends StatefulWidget {
  const ExpenseCalendar({
    super.key,
    required this.rows,
    required this.dateField,
    required this.amountField,
    required this.titleField,
    required this.subtitleField,
    required this.onTapRow,
  });

  final List<Map<String, dynamic>> rows;
  final String dateField;
  final String amountField;
  final String? titleField;
  final String? subtitleField;
  final void Function(Map<String, dynamic> row) onTapRow;

  @override
  State<ExpenseCalendar> createState() => _ExpenseCalendarState();
}

class _ExpenseCalendarState extends State<ExpenseCalendar> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _amber = Color(0xFFF59E0B); // kModuleColours['expenses']

  late DateTime _month; // first of the visible month
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    final t = DateTime(now.year, now.month, now.day);
    // Open on today if today has anything, otherwise leave it unselected so the
    // month reads as a whole rather than jumping to an empty day.
    if (_byDay()[t]?.isNotEmpty ?? false) _selected = t;
  }

  num _amount(Map<String, dynamic> r) {
    final v = r[widget.amountField];
    return v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
  }

  bool _isIncome(Map<String, dynamic> r) => '${r['kind'] ?? ''}' == 'income';

  String _money(num n) => NumberFormat.currency(
          locale: 'en_IN', symbol: '₹', decimalDigits: 0)
      .format(n);

  /// rows keyed by the midnight of their txn_date.
  Map<DateTime, List<Map<String, dynamic>>> _byDay() {
    final map = <DateTime, List<Map<String, dynamic>>>{};
    for (final r in widget.rows) {
      final d = parseDate('${r[widget.dateField] ?? ''}');
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      map.putIfAbsent(key, () => []).add(r);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDay = _byDay();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // This month's spend (expenses only) and income, for the header.
    num spent = 0, income = 0;
    for (final e in byDay.entries) {
      if (e.key.year != _month.year || e.key.month != _month.month) continue;
      for (final r in e.value) {
        if (_isIncome(r)) {
          income += _amount(r);
        } else {
          spent += _amount(r);
        }
      }
    }

    // Heaviest single day this month, to scale the heatmap tint on the cells.
    num maxDaySpend = 0;
    byDay.forEach((k, list) {
      if (k.year != _month.year || k.month != _month.month) return;
      num s = 0;
      for (final r in list) {
        if (!_isIncome(r)) s += _amount(r);
      }
      if (s > maxDaySpend) maxDaySpend = s;
    });

    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Sunday-first grid. weekday: Mon=1..Sun=7 → %7 gives Sun=0, Mon=1..Sat=6.
    final leading = first.weekday % 7;
    final weeks = ((leading + daysInMonth) / 7).ceil();

    final selectedItems =
        _selected == null ? const <Map<String, dynamic>>[] : (byDay[_selected] ?? const []);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
      children: [
        // ── The calendar itself, in one clean card ───────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: softShadow(theme.brightness == Brightness.dark),
          ),
          child: Column(children: [
            // Month, a step either side.
            Row(children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                  _selected = null;
                }),
              ),
              Expanded(
                child: Text('${_months[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month + 1);
                  _selected = null;
                }),
              ),
            ]),
            const SizedBox(height: 2),
            // The month at a glance — out and in.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                Expanded(
                    child: _statPill(theme, 'Spent', _money(spent), _amber)),
                const SizedBox(width: 8),
                Expanded(child: _statPill(theme, 'Income', _money(income), kOk)),
              ]),
            ),
            const SizedBox(height: 14),
            // Weekday labels.
            Row(
              children: [
                for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(d,
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.outline)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // The grid, each day tinted by how heavy it was.
            for (var w = 0; w < weeks; w++)
              Row(children: [
                for (var d = 0; d < 7; d++)
                  _cell(
                    context,
                    dayNumber: w * 7 + d - leading + 1,
                    daysInMonth: daysInMonth,
                    byDay: byDay,
                    today: today,
                    maxDaySpend: maxDaySpend,
                  ),
              ]),
          ]),
        ),

        const SizedBox(height: 16),

        // ── The selected day's expenses ──────────────────────────────────
        if (_selected != null) ...[
          Text(
            _selected == today
                ? 'Today'
                : '${_selected!.day} ${_months[_selected!.month - 1]}',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (selectedItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('Nothing on this day.',
                    style: TextStyle(color: theme.colorScheme.outline)),
              ),
            )
          else
            for (var i = 0; i < selectedItems.length; i++)
              stagger(context, i, _dayRow(context, selectedItems[i])),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('Tap a day to see what it cost.',
                  style: TextStyle(color: theme.colorScheme.outline)),
            ),
          ),
      ],
    );
  }

  /// A month-at-a-glance figure — spent or in — as a soft tinted tile.
  Widget _statPill(ThemeData theme, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  /// Compact money for a cramped cell — 1.2k, 3L — in the Indian scale that ₹ is.
  String _short(num v) {
    if (v >= 100000) {
      return '${(v / 100000).toStringAsFixed(v >= 1000000 ? 0 : 1)}L';
    }
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
    }
    return '${v.round()}';
  }

  Widget _cell(
    BuildContext context, {
    required int dayNumber,
    required int daysInMonth,
    required Map<DateTime, List<Map<String, dynamic>>> byDay,
    required DateTime today,
    required num maxDaySpend,
  }) {
    final theme = Theme.of(context);
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const Expanded(child: SizedBox(height: 50));
    }
    final day = DateTime(_month.year, _month.month, dayNumber);
    final items = byDay[day] ?? const [];
    final isSelected = _selected == day;
    final isToday = day == today;
    num spent = 0;
    for (final r in items) {
      if (!_isIncome(r)) spent += _amount(r);
    }

    // Heatmap: the more a day cost, the deeper its amber. A selected day fills
    // solid so the choice is unmistakable; a deep tint or a selection flips the
    // text to white to stay legible.
    final t = maxDaySpend > 0 ? (spent / maxDaySpend).clamp(0.0, 1.0) : 0.0;
    final deep = isSelected || t > 0.5;
    Color? bg;
    if (isSelected) {
      bg = _amber;
    } else if (spent > 0) {
      bg = _amber.withValues(alpha: 0.10 + 0.42 * t);
    } else if (items.isNotEmpty) {
      bg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    }
    final numColor = deep
        ? Colors.white
        : isToday
            ? theme.colorScheme.primary
            : null;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selected = isSelected ? null : day),
        child: Container(
          height: 50,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: isToday && !isSelected
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$dayNumber',
                  style: TextStyle(
                      fontSize: 13,
                      color: numColor,
                      fontWeight: isToday || isSelected
                          ? FontWeight.w800
                          : FontWeight.w500)),
              if (spent > 0) ...[
                const SizedBox(height: 1),
                Text(_short(spent),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        fontSize: 9.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: deep ? Colors.white : _amber)),
              ] else if (items.isNotEmpty)
                // Income-only day: a small green dot, no spend figure.
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 5,
                  height: 5,
                  decoration:
                      const BoxDecoration(color: kOk, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayRow(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final income = _isIncome(r);
    final colour = income ? kOk : _amber;
    final title = widget.titleField == null
        ? ''
        : '${r[widget.titleField] ?? ''}';
    final sub = widget.subtitleField == null
        ? ''
        : '${r[widget.subtitleField] ?? ''}';
    return InkWell(
      onTap: () => widget.onTapRow(r),
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
                income ? Icons.south_west : Icons.north_east,
                color: Colors.white,
                size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? (income ? 'Income' : 'Expense') : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _money(_amount(r)),
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: colour,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ]),
      ),
    );
  }
}
