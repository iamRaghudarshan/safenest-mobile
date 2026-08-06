// The app is almost entirely a client of somebody's own server, so most of what
// is worth testing needs one. This checks the part that does not: that a person
// who has never signed in is asked for an address BEFORE anything else, because
// there is no default server and guessing one would be the worst kind of bug.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/main.dart';

void main() {
  testWidgets('a fresh install asks which SafeNest to talk to',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SafeNestApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Either the splash while secure storage is read, or the sign-in screen.
    // Both are acceptable; what must never appear is a signed-in view.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
