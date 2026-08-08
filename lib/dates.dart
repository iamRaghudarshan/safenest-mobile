/// One way to write a date, used everywhere a person reads one.
///
/// There were three. Documents said "8 Aug 2026", the photo viewer said
/// "8 August 2026", the scanner said "8/8/2026" without padding, and the
/// activity log fell back to "08-08-2026" only after a week had passed. Four
/// spellings of the same day, in one app, on screens people move between.
///
/// It is dd-mm-yyyy, which is what this app's own users write. Note that is a
/// DISPLAY decision only: `yyyy-MM-dd` is what the server is sent and must stay
/// exactly as it is — swapping the wire format for a nicer-looking one is how a
/// date arrives at the database meaning a different day.
library;

import 'package:intl/intl.dart';

/// 08-08-2026
final _date = DateFormat('dd-MM-yyyy');

/// 4:14 PM — twelve hour, with AM/PM. Not 16:14: a 24-hour clock is a thing
/// people convert in their heads, and this app is read by people checking when
/// a bill was paid, not by anyone on a rota.
final _time = DateFormat('h:mm a');

/// What the server expects. Never shown to anybody.
final _wire = DateFormat('yyyy-MM-dd');

String fmtDate(DateTime? d) => d == null ? '' : _date.format(d);

String fmtTime(DateTime? d) => d == null ? '' : _time.format(d);

/// 08-08-2026 · 4:14 PM
String fmtDateTime(DateTime? d) =>
    d == null ? '' : '${fmtDate(d)} · ${fmtTime(d)}';

/// For a value going to the API. Kept here beside the display formats so the
/// difference between them is visible in one file rather than being rediscovered.
String wireDate(DateTime d) => _wire.format(d);

/// Parses what the server sends, which is ISO, and what a person may have typed
/// in dd-mm-yyyy. Returns null rather than throwing: a date that cannot be read
/// should leave a field blank, not take down the screen it is on.
DateTime? parseDate(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  final m = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(s);
  if (m != null) {
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return DateTime(y, mo, d);
  }
  return null;
}

/// "2h ago" for something recent, the date once it stops being recent.
///
/// Kept because a log answers "when" and forcing arithmetic on the reader is
/// unkind — but it is no longer the ONLY thing shown. See the activity log,
/// where the exact date and time sit beside it: "2h ago" is useless the moment
/// you need to tell somebody when a record actually changed.
String relative(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return fmtDate(t);
}
