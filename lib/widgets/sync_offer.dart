/// "You have changes waiting" — an offer, never an action.
///
/// This appears when something is queued and does exactly one thing: say so,
/// and give a way to deal with it. It does NOT sync. Nothing in this product
/// acts on the owner's data without being asked — the desktop updater will not
/// download unprompted, reminders never leave the device — and a phone that
/// quietly pushed records the moment it found the computer would be the one
/// piece that did.
///
/// It is loud on purpose. Unsynced work exists on this phone and nowhere else,
/// so a quiet indicator would be the wrong end of the trade: the failure being
/// guarded against is somebody losing a phone having forgotten there was a
/// week of expenses on it that never reached the computer.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../offline/sync.dart';
import '../screens/sync_screen.dart';
import '../theme.dart';

class SyncOffer extends StatelessWidget {
  const SyncOffer({super.key, this.pendingOverride});

  /// Test hook, matching the convention the other screens use.
  final int? pendingOverride;

  @override
  Widget build(BuildContext context) {
    final waiting = pendingOverride ?? context.watch<SyncService>().pending;
    if (waiting == 0) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Material(
        color: kWarn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kRadiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusSm),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SyncScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.cloud_upload_outlined, color: kWarn, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$waiting ${waiting == 1 ? 'change' : 'changes'} '
                        'not on your computer yet',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Only on this phone until you sync',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // The way in, not the doing of it. Tapping opens the Sync
                // screen, where the button and the progress live.
                Text('Review',
                    style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Icon(Icons.chevron_right, color: cs.primary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
