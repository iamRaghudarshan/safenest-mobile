/// Finding a tab in the bottom bar, from a test.
///
/// Tests used to reach the bar by counting every InkWell on screen and taking
/// the last N, which is arithmetic over whatever the selected screen happened
/// to render. It worked until a slow run made it not — and a flaky test is
/// worse than no test, because it teaches people to press re-run rather than
/// look. Each nav item carries a `ValueKey('nav-<tab>')` now, so a test can
/// name the thing it means.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every nav item currently in the bar, in the order they are drawn.
///
/// Read from the render tree by key prefix rather than from a list of expected
/// tabs, because the bar is customisable and each skin ships a different
/// default — a helper that knew the tabs would have to be corrected every time
/// one moved.
List<Key> navItemKeys(WidgetTester tester) => [
      for (final e in find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith('nav-');
      }).evaluate())
        e.widget.key!,
    ];

/// The nav item at position [i] in the bar.
Finder navItemAt(WidgetTester tester, int i) {
  final keys = navItemKeys(tester);
  expect(i, lessThan(keys.length),
      reason: 'the bar has ${keys.length} tabs, so there is no tab $i');
  return find.byKey(keys[i]);
}

/// The nav item for a named tab — `navItem('gallery')`.
Finder navItem(String tab) => find.byKey(ValueKey('nav-$tab'));
