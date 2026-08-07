// Do the record forms fit, and do they offer values the database will accept?
//
// TWO DIFFERENT FAILURES, and only one of them is a layout problem.
//
// The first is size. Reminders went from four fields to seven and loans from
// nine to eleven; `flutter analyze` reports zero issues for a sheet that cannot
// fit, because overflow is a runtime measurement. The Home screen shipped broken
// through seven versions on the strength of a clean analyse. So every module's
// sheet is laid out here at iPhone SE size.
//
// The second is worse and is not about pixels at all. Four of the choice lists
// in modules.dart were written from memory and every one of them was wrong
// against the real column: to-dos offered priority "normal" where the enum is
// ('low','medium','high'), status "open" where it is ('pending','done'),
// insurance "half-yearly" where it is half_yearly, and cards offered
// active/closed for a column with no such values. Each saved happily in the form
// and was refused by MySQL. Nothing in the app could catch that, so the enums
// are pinned here as literals — if someone changes a column, this fails and
// names it, which is the only warning there is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/modules.dart';
import 'package:safenest/screens/module_list_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

/// What the columns actually are, read out of information_schema on the running
/// database rather than remembered. Only the modules with an enum appear.
const _schemaEnums = <String, Map<String, List<String>>>{
  'expenses': {
    'kind': ['income', 'expense'],
  },
  'reminders': {
    'recurrence': ['none', 'daily', 'weekly', 'monthly', 'yearly'],
  },
  'todos': {
    'priority': ['low', 'medium', 'high'],
    'recurrence': ['none', 'daily', 'weekly', 'monthly'],
    'status': ['pending', 'done'],
  },
  'loans': {
    'status': ['active', 'closed'],
  },
  'insurance': {
    'frequency': ['monthly', 'quarterly', 'half_yearly', 'yearly'],
  },
};

/// Exactly what each endpoint will write. Anything a form offers that is not in
/// here is typed by the person and then silently dropped, which is how a
/// statement amount could be entered on a card and simply not be there after.
const _writableFields = <String, List<String>>{
  'expenses': ['kind', 'category', 'amount', 'method', 'txn_date', 'note'],
  'reminders': [
    'title', 'module_ref', 'due_date', 'due_time', 'recurrence',
    'notify_push', 'notify_email', 'is_done'
  ],
  'todos': ['title', 'priority', 'due_date', 'status', 'recurrence'],
  'cards': ['bank', 'last4', 'credit_limit', 'billing_day', 'due_date'],
  'loans': [
    'lender', 'loan_type', 'principal', 'interest_rate', 'emi',
    'tenure_months', 'outstanding', 'start_date', 'next_due_date', 'status',
    'notes'
  ],
  'insurance': [
    'policy_type', 'provider', 'policy_no', 'premium', 'sum_assured',
    'frequency', 'renewal_date'
  ],
  'investments': [
    'broker', 'invest_type', 'name', 'invested_amount', 'current_value',
    'units', 'maturity_date'
  ],
};

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      theme: buildTheme(const Brand(), brightness),
      home: child,
    ),
  );
}

void main() {
  group('every choice is a value the column accepts', () {
    for (final spec in kModules) {
      test('${spec.key}: no invented enum values', () {
        final enums = _schemaEnums[spec.key] ?? const {};
        for (final f in spec.fields) {
          if (f.kind != FieldKind.choice) continue;
          final allowed = enums[f.key];
          // module_ref is a free VARCHAR, not an enum — nothing to pin.
          if (allowed == null) continue;
          for (final c in f.choices) {
            expect(allowed, contains(c),
                reason: '${spec.key}.${f.key} offers "$c", which the column '
                    'does not accept. Allowed: $allowed');
          }
        }
      });
    }
  });

  group('every field offered is a field the endpoint writes', () {
    for (final spec in kModules) {
      test('${spec.key}: nothing typed is silently dropped', () {
        final writable = _writableFields[spec.key]!;
        for (final f in spec.fields) {
          expect(writable, contains(f.key),
              reason: '${spec.key} offers "${f.key}" but the endpoint does not '
                  'accept it — whatever is typed there is thrown away on save.');
        }
      });
    }
  });

  test('reminders can be given a time, which is the point of all this', () {
    final r = moduleByKey('reminders')!;
    final t = r.fields.where((f) => f.kind == FieldKind.time);
    expect(t.length, 1, reason: 'reminders should have exactly one time field');
    expect(t.first.key, 'due_time');
    // Optional on purpose: a reminder with no time arrives with the daily
    // summary, which is how every reminder worked before this existed.
    expect(t.first.required, isFalse,
        reason: 'a required time would put an alarm on every reminder ever set');
  });

  test('prettyChoice reads a database string aloud', () {
    expect(prettyChoice('half_yearly'), 'Half yearly');
    expect(prettyChoice('pending'), 'Pending');
    expect(prettyChoice('none'), 'None');
    expect(prettyChoice(''), '');
  });

  group('the sheets fit an iPhone SE', () {
    for (final spec in kModules) {
      testWidgets('${spec.label} — add', (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_wrap(
            ModuleListScreen(spec: spec, initialRows: const [])));
        await tester.pump();

        // By its icon, not by FloatingActionButton. The add control is a
        // gradient Container now (Material's FAB cannot express the brand's
        // 135° fill), and a test that names the widget CLASS fails on a change
        // that is invisible to the person using it. What matters is that there
        // is one + on the screen and tapping it opens the sheet.
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: '${spec.label}\'s add sheet overflowed');
        // Proof the sheet is really open and showing this module's fields,
        // rather than the test passing on an empty screen.
        expect(find.text(spec.fields.first.label), findsWidgets);
      });
    }
  });

  testWidgets('a reminder row shows its time and can be ticked off',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(ModuleListScreen(
      spec: moduleByKey('reminders')!,
      initialRows: const [
        {
          'id': 1,
          'title': 'Take the tablets',
          'due_date': '2026-08-07',
          'due_time': '18:30',
          'time_fmt': '6:30 pm',
          'recurrence': 'daily',
          'is_done': 0,
          'days': 0,
        },
        {
          'id': 2,
          'title': 'Renew the parking permit',
          'due_date': '2026-08-01',
          'is_done': 0,
          'days': -6,
        },
        {'id': 3, 'title': 'Already handled', 'is_done': 1, 'days': null},
      ],
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The hour is on the row, not hidden inside the record.
    expect(find.textContaining('6:30 pm'), findsWidgets);
    // A tick per row — the action that was not available at all before.
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('a row crowded with badges still fits the narrowest phone',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Worst case on purpose: a long bank name, a big amount, and every badge
    // this row can show at once. Rows grew a 44px icon tile and a wrap of pills,
    // and a row that only fits when it is nearly empty is not a row that fits.
    await tester.pumpWidget(_wrap(ModuleListScreen(
      spec: moduleByKey('cards')!,
      initialRows: const [
        {
          'id': 1,
          'bank': 'Housing Development Finance Corporation Bank',
          'last4': '4242',
          'credit_limit': 2500000,
          'next_due_fmt': '12-08-2026',
          'paid_this_month': false,
          'days': -6,
        },
      ],
    )));
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'a full card row overflowed');
    expect(find.text('Not paid'), findsOneWidget);
    expect(find.text('6d overdue'), findsOneWidget);
  });

  testWidgets('an empty module invites rather than just reporting',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(ModuleListScreen(
        spec: moduleByKey('loans')!, initialRows: const [])));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('No loans yet'), findsOneWidget);
    // The button matters more than the wording: the empty state is the first
    // thing a new customer sees in a module, and it used to be a dead end.
    expect(find.text('Add your first'), findsOneWidget);
  });

  testWidgets('money in and money out are not the same colour', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final spec = moduleByKey('expenses')!;
    final income = rowAccent(spec, const {'kind': 'income'});
    final spend = rowAccent(spec, const {'kind': 'expense'});
    expect(income.colour, isNot(spend.colour),
        reason: 'this is the one list where a wrong glance costs you a wrong '
            'belief about your month');
    expect(income.colour, kOk);

    await tester.pumpWidget(_wrap(ModuleListScreen(
      spec: spec,
      initialRows: const [
        {'id': 1, 'kind': 'income', 'category': 'Salary', 'amount': 150000},
        {'id': 2, 'kind': 'expense', 'category': 'Groceries', 'amount': 2400},
      ],
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('what is late comes first and what is done sinks',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(ModuleListScreen(
      spec: moduleByKey('todos')!,
      initialRows: const [
        {'id': 1, 'title': 'AAA done one', 'status': 'done', 'days': -30},
        {'id': 2, 'title': 'BBB due next week', 'status': 'pending', 'days': 7},
        {'id': 3, 'title': 'CCC overdue', 'status': 'pending', 'days': -3},
      ],
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final overdue = tester.getTopLeft(find.text('CCC overdue')).dy;
    final soon = tester.getTopLeft(find.text('BBB due next week')).dy;
    final done = tester.getTopLeft(find.text('AAA done one')).dy;
    expect(overdue, lessThan(soon), reason: 'the late one should be on top');
    expect(soon, lessThan(done), reason: 'the finished one should be last');
  });
}
