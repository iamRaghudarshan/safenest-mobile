/// Turning a confirmed date into a reminder.
///
/// This is why the confirm step exists. A warranty somebody tapped becomes a
/// notification two years later, and the whole chain has to be defensible then:
/// the person agreed to this date, they can see the words it came from, and
/// the reminder says which memory it belongs to rather than arriving as a bare
/// line about a washing machine.
///
/// WHEN IT RINGS, and why not on the day. A warranty that ends today is a
/// warranty you cannot use: whatever you were going to do about it — call,
/// claim, renew — takes longer than the morning it expires. A month's notice
/// is what makes the reminder worth having, and a second one a week before
/// catches the month somebody was away.
library;

import 'package:flutter/foundation.dart';

import '../alarms.dart';
import '../offline/store.dart';

/// How far ahead each warning fires.
const kMemoryWarnings = [Duration(days: 30), Duration(days: 7)];

/// Where Life Memory's alarm ids live.
///
/// THEY SHARE A NUMBER SPACE WITH THE REMINDERS MODULE, whose ids are server
/// row ids starting at 1. Two different things scheduling alarm id 7 means one
/// of them silently cancels the other — `Alarms.schedule` clears the id first,
/// by design, so there is no error and no symptom until a warranty warning
/// never arrives. The band keeps them apart, and it has to stay well below
/// `Alarms._extraBase` (1 << 28), which is where the repeat rings of each burst
/// live.
const kMemoryAlarmBase = 2000000;

@immutable
class MemoryReminder {
  const MemoryReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
  });

  /// Stable, so re-syncing moves a reminder instead of adding a second one.
  final int id;
  final String title;
  final String body;
  final DateTime when;

  @override
  bool operator ==(Object other) =>
      other is MemoryReminder &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.when == when;

  @override
  int get hashCode => Object.hash(id, title, body, when);

  @override
  String toString() => '$id:$title@$when';
}

/// The reminders a set of dated facts deserves.
///
/// Pure, so the rules can be argued with in a test rather than discovered on a
/// phone in 2028. [rows] are as `OfflineStore.memoryDates` returns them.
List<MemoryReminder> remindersFor(
  List<Map<String, dynamic>> rows,
  DateTime now,
) {
  final out = <MemoryReminder>[];
  for (final r in rows) {
    final at = DateTime.tryParse('${r['at']}');
    if (at == null) continue;
    final factId = r['id'];
    if (factId is! int) continue;

    final label = '${r['value'] ?? ''}'.trim();
    final words = '${r['body'] ?? ''}'.trim();

    for (var i = 0; i < kMemoryWarnings.length; i++) {
      final when = at.subtract(kMemoryWarnings[i]);
      // A warning already past is not a reminder, it is an interruption on the
      // next launch. Something confirmed a fortnight before it expires gets
      // the week's notice only, and that is correct.
      if (!when.isAfter(now)) continue;

      out.add(MemoryReminder(
        // The fact's id with the warning's index folded in, so the two
        // warnings for one date never collide and re-syncing replaces rather
        // than duplicates. Kept inside 32 bits because Android alarm ids are.
        id: memoryAlarmId(factId, i),
        title: label.isEmpty ? 'Something you noted' : label,
        // THE WORDS, not a restatement. In two years the only thing that will
        // make this reminder intelligible is the sentence that caused it.
        body: words.isEmpty
            ? 'You asked to be reminded about this.'
            : (words.length > 120 ? '${words.substring(0, 117)}…' : words),
        when: when,
      ));
    }
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

/// The alarm id for warning [warning] of fact [factId].
///
/// Stable across runs, so re-scheduling MOVES a warning instead of adding a
/// second one, and distinct per warning so the month's notice and the week's
/// never overwrite each other. Kept inside the band above and well inside 32
/// bits, because an Android notification id outside that range is dropped with
/// no error at all.
int memoryAlarmId(int factId, int warning) =>
    kMemoryAlarmBase + (factId.abs() % 1000000) * 10 + warning;

/// Where a NOTE's reminder lives.
///
/// A third band, for the same reason as the second. The reminders module uses
/// server row ids starting at 1, Life Memory uses the band above, and a note
/// scheduling alarm id 7 would silently cancel reminder 7 — `Alarms.schedule`
/// clears the id before setting it, by design, so there is no error and no
/// symptom until something does not go off.
const kNoteAlarmBase = 20000000;

int noteAlarmId(int noteId) => kNoteAlarmBase + (noteId.abs() % 1000000);

// ========================================================= doing something

/// The reminders Life Memory currently wants, read off the phone.
Future<List<MemoryReminder>> memoryReminders(OfflineStore store,
    {DateTime? now}) async {
  final at = now ?? DateTime.now();
  // Only dates still ahead — memoryDates already filters to those, and a
  // warning for something that expired last year is noise somebody has to
  // dismiss.
  final rows = await store.memoryDates(from: at);
  return remindersFor(rows, at);
}

/// Put them in the phone's alarm queue.
///
/// Returns how many were set. Best effort by nature: a phone that refuses exact
/// alarms must not take anything else down with it, which is why [Alarms] logs
/// rather than throws.
Future<int> scheduleMemoryReminders(OfflineStore store,
    {DateTime? now}) async {
  final wanted = await memoryReminders(store, now: now);
  for (final r in wanted) {
    await Alarms.instance.schedule(
      id: r.id,
      title: r.title,
      body: r.body,
      when: r.when,
    );
  }
  if (wanted.isNotEmpty) {
    debugPrint('[memory] ${wanted.length} warranty warnings scheduled');
  }
  return wanted.length;
}
