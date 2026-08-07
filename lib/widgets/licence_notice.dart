/// What the phone says when the customer's licence has lapsed.
///
/// THERE IS NO LICENCE IN THIS APP, and that is the design.
///
/// One licence lives on the customer's own computer, and the gate that enforces
/// it is middleware over every /api/ path on that machine. So the phone, the
/// browser and the desktop are all governed by the same check without any of
/// them holding a licence of their own. Nothing here verifies anything: it
/// reports what the server said. A phone that could decide its own licence
/// state would be a second place to get it wrong, and the obvious way to get it
/// wrong is in the customer's favour.
///
/// The states differ and so should the words. "Expired" is something the owner
/// can fix by renewing. "Withdrawn" is not, and telling them to renew would send
/// them round a loop. GRACE lets reads through and refuses writes, so the app
/// keeps working and saving does not — which needs saying, or it reads as the
/// save button being broken.
///
/// And the thing that must be said in every state: their records are not gone,
/// and an export still works. A lapsed licence ends the right to USE the
/// software; it does not make somebody's own records ours to hold onto.
library;

import 'package:flutter/material.dart';

import '../api.dart';

class LicenceNotice extends StatelessWidget {
  const LicenceNotice({super.key, required this.error, this.onRetry});
  final ApiError error;
  final VoidCallback? onRetry;

  String get _state =>
      '${error.licence?['state'] ?? ''}'.toUpperCase();

  ({String title, String body}) get _words {
    switch (_state) {
      case 'EXPIRED':
        return (
          title: 'This licence has expired',
          body: 'Renew it with whoever supplied SafeNest and this app starts '
              'working again straight away — nothing has to be reinstalled.',
        );
      case 'REVOKED':
        return (
          title: 'This licence has been withdrawn',
          body: 'Get in touch with whoever supplied SafeNest. Renewing will not '
              'help here; the licence has been withdrawn rather than lapsed.',
        );
      case 'GRACE':
        return (
          title: 'This licence has just expired',
          body: 'You can still look at everything for a few days, but nothing '
              'new can be saved until it is renewed.',
        );
      case 'MISSING':
        return (
          title: 'No licence was found',
          body: 'The copy of SafeNest on your computer cannot find its licence '
              'file. Whoever supplied it can send it again.',
        );
      case 'INVALID':
        return (
          title: 'This licence could not be read',
          body: 'The licence file on your computer is damaged or is not for this '
              'copy. Whoever supplied it can issue another.',
        );
      default:
        return (
          title: 'This copy needs a valid licence',
          body: error.message,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _words;
    final keyId = '${error.licence?['key_id'] ?? ''}';
    final expires = '${error.licence?['expires_on'] ?? ''}';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_clock_outlined,
                size: 52, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 18),
            Text(w.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Text(w.body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            if (expires.isNotEmpty && expires != 'null') ...[
              const SizedBox(height: 10),
              Text('Expired on $expires',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (keyId.isNotEmpty && keyId != 'null') ...[
              const SizedBox(height: 6),
              // Shown because it is the first thing they will be asked for, and
              // hunting for it on another screen while the app is refusing to
              // work is a poor moment to go looking.
              SelectableText('Licence $keyId',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Your records are safe. Nothing has been deleted, and you can '
                'still take a copy of everything from SafeNest on your computer '
                '— that never stops working, whatever the licence says.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                  onPressed: onRetry, child: const Text('Check again')),
            ],
          ],
        ),
      ),
    );
  }
}
