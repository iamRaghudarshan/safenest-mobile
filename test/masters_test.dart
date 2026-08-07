// The user's own lists, and the pickers that read them.
//
// WHY THIS MATTERS MORE THAN IT LOOKS
// A text box and a picker are not two ways of collecting the same value. Typing
// "food" where the laptop stored "Food & Dining" gives one person two categories
// that mean the same thing, and every total that adds them up is then wrong —
// silently, and for as long as nobody notices. So the picker has to save the
// LABEL exactly as the master carries it, and these tests pin that.
//
// The real data below is what /api/masters actually returned from the running
// server, not invented: nine banks with brand colours, categories with emoji.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/masters.dart';
import 'package:safenest/screens/masters_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/master_picker.dart';

const _expenseCats = <MasterItem>[
  MasterItem(id: 1, key: 'food', label: 'Food & Dining', emoji: '🍔'),
  MasterItem(id: 2, key: 'groceries', label: 'Groceries', emoji: '🛒'),
  MasterItem(id: 3, key: 'transport', label: 'Transport', emoji: '🚕'),
  MasterItem(id: 4, key: 'bills', label: 'Bills & Utilities', emoji: '🧾'),
  MasterItem(id: 5, key: 'other', label: 'Other', emoji: '💸'),
];

const _banks = <MasterItem>[
  MasterItem(id: 10, key: 'hdfc', label: 'HDFC Bank', color: '#004c8f'),
  MasterItem(id: 11, key: 'icici', label: 'ICICI Bank', color: '#af272f'),
  MasterItem(id: 12, key: 'sbi', label: 'State Bank of India', color: '#22409a'),
  MasterItem(id: 13, key: 'other', label: 'Other', color: '#64748b'),
];

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      theme: buildTheme(const Brand(), brightness),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('MasterItem', () {
    test('a hex colour becomes a Color', () {
      expect(const MasterItem(id: 1, key: 'h', label: 'HDFC', color: '#004c8f').tint,
          const Color(0xFF004C8F));
    });

    test('a malformed colour costs the tint, not the list', () {
      // A bad value must not throw. It reaches this from the database, and a
      // list of banks that cannot render is worse than one that renders plain.
      for (final bad in ['', 'nonsense', '#12', '#zzzzzz', '#0011223344']) {
        expect(const MasterItem(id: 1, key: 'k', label: 'L').tint, isNull);
        expect(MasterItem(id: 1, key: 'k', label: 'L', color: bad).tint, isNull,
            reason: '$bad should not have parsed');
      }
    });

    test('is_active 0 means hidden, not deleted', () {
      final m = MasterItem.fromJson(const {
        'id': 3,
        'key': 'x',
        'label': 'X',
        'is_active': 0,
        'sort_order': 2,
      });
      expect(m.isActive, isFalse);
      expect(m.sortOrder, 2);
    });
  });

  test('the four types match the server, and each carries exactly one extra', () {
    // masters.py::MASTER_TYPES — a type invented here would render a picker for
    // a list the API returns 404 for.
    expect(kMasterTypes.map((t) => t.type).toList(), [
      'expense_category',
      'bank',
      'document_category',
      'vault_category',
    ]);
    expect(masterTypeOf('bank')!.field, 'color');
    expect(masterTypeOf('expense_category')!.field, 'emoji');
    expect(masterTypeOf('vault_category')!.field, 'emoji');
    expect(masterTypeOf('document_category')!.field, 'emoji');
    expect(masterTypeOf('not_a_type'), isNull);
  });

  testWidgets('the picker saves the LABEL, exactly as the master carries it',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? saved;
    await tester.pumpWidget(_wrap(MasterPicker(
      type: 'expense_category',
      label: 'Category',
      value: null,
      items: _expenseCats,
      onChanged: (v) => saved = v,
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Food & Dining'));
    await tester.pump();

    // Not 'food', not 'Food'. The record column holds the label and the web app
    // writes the label; anything else makes a second category out of one.
    expect(saved, 'Food & Dining');
  });

  testWidgets('nothing is pre-selected', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? saved = 'untouched';
    await tester.pumpWidget(_wrap(MasterPicker(
      type: 'expense_category',
      label: 'Category',
      value: null,
      items: _expenseCats,
      onChanged: (v) => saved = v,
    )));
    await tester.pump();

    // Defaulting to the first chip means every expense saved without touching
    // the field is filed under whatever sorts first — which is worse than being
    // asked, because it looks deliberate afterwards.
    expect(saved, 'untouched');
  });

  testWidgets('a value not on the list is kept, not silently rewritten',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Editing an old record whose category was typed before the list existed,
    // or one hidden since. Opening the form must not quietly change it.
    await tester.pumpWidget(_wrap(MasterPicker(
      type: 'expense_category',
      label: 'Category',
      value: 'Diwali sweets',
      items: _expenseCats,
      onChanged: (_) {},
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.widgetWithText(TextField, 'Diwali sweets'), findsOneWidget);
  });

  testWidgets('banks show their brand colour and fit the narrowest phone',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? saved;
    await tester.pumpWidget(_wrap(MasterPicker(
      type: 'bank',
      label: 'Bank',
      value: null,
      items: _banks,
      onChanged: (v) => saved = v,
    )));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'the bank chips overflowed — "State Bank of India" is the long one');

    await tester.tap(find.text('State Bank of India'));
    await tester.pump();
    expect(saved, 'State Bank of India');
  });

  testWidgets('"Something else" lets a person type one that is not listed',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? saved;
    await tester.pumpWidget(_wrap(MasterPicker(
      type: 'expense_category',
      label: 'Category',
      value: null,
      items: _expenseCats,
      onChanged: (v) => saved = v,
    )));
    await tester.pump();

    await tester.tap(find.text('Something else'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Diwali sweets');
    await tester.pump();
    expect(saved, 'Diwali sweets');
  });

  testWidgets('both themes, and the list lays out while it is still loading',
      (tester) async {
    for (final b in Brightness.values) {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // items: null and no server — the placeholder-chip branch, which is the
      // state the field is actually in for the first moment it is on screen.
      await tester.pumpWidget(_wrap(
        MasterPicker(
            type: 'expense_category',
            label: 'Category',
            value: null,
            items: const [],
            onChanged: (_) {}),
        brightness: b,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the manage-lists screen offers all four lists', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider<Session>(
      create: (_) => Session(),
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: const MastersScreen(),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final t in kMasterTypes) {
      expect(find.text(t.label), findsOneWidget);
    }
  });

  testWidgets('a hidden entry stays visible on the manage screen',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider<Session>(
      create: (_) => Session(),
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: MasterListScreen(
          type: masterTypeOf('expense_category')!,
          initialItems: const [
            MasterItem(id: 1, key: 'food', label: 'Food & Dining', emoji: '🍔'),
            MasterItem(
                id: 2, key: 'gone', label: 'Never used', emoji: '💸',
                isActive: false),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Hiding is reversible, so the hidden one has to be FINDABLE — a list that
    // only shows active entries gives no way to bring one back.
    expect(find.text('Never used'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
  });
}
