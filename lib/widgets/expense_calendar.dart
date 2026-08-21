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

    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Sunday-first grid. weekday: Mon=1..Sun=7 → %7 gives Sun=0, Mon=1..Sat=6.
    final leading = first.weekday % 7;
    final weeks = ((leading + daysInMonth) / 7).ceil();

    final selectedItems =
        _selected == null ? const <Map<String, dynamic>>[] : (byDay[_selected] ?? const []);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
      children: [
        // ── Month header: ◀  Month Year  ▶  + this month's totals ─────────
        Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() {
              _month = DateTime(_month.year, _month.month - 1);
              _selected = null;
            }),
          ),
          Expanded(
            child: Column(children: [
              Text('${_months[_month.month - 1]} ${_month.year}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                income > 0
                    ? '${_money(spent)} spent · ${_money(income)} in'
                    : '${_money(spent)} spent',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() {
              _month = DateTime(_month.year, _month.month + 1);
              _selected = null;
            }),
          ),
        ]),
        const SizedBox(height: 6),

        // ── Weekday labels ───────────────────────────────────────────────
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

        // ── The month grid ──────────────────────────────────────────────
        for (var w = 0; w < weeks; w++)
          Row(children: [
            for (var d = 0; d < 7; d++)
              _cell(
                context,
                dayNumber: w * 7 + d - leading + 1,
                daysInMonth: daysInMonth,
                byDay: byDay,
                today: today,
              ),
          ]),

        const SizedBox(height: 14),

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
            for (final r in selectedItems) _dayRow(context, r),
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

  Widget _cell(
    BuildContext context, {
    required int dayNumber,
    required int daysInMonth,
    required Map<DateTime, List<Map<String, dynamic>>> byDay,
    required DateTime today,
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

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selected = isSelected ? null : day),
        child: Container(
          height: 50,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected
                ? _amber.withValues(alpha: 0.18)
                : items.isNotEmpty
                    ? theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : null,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(
              color: isSelected
                  ? _amber
                  : isToday
                      ? theme.colorScheme.outline.withValues(alpha: 0.7)
                      : Colors.transparent,
              width: isSelected || isToday ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$dayNumber',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isToday ? FontWeight.w800 : FontWeight.w500)),
              if (spent > 0) ...[
                const SizedBox(height: 1),
                Text(
                  spent >= 1000
                      ? '${(spent / 1000).toStringAsFixed(spent >= 10000 ? 0 : 1)}k'
                      : '$spent',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: _amber),
                ),
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
