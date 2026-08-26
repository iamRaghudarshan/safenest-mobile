/// "Work from this phone" — the switch, and an honest list of what that means.
///
/// The list is not decoration. Someone about to board a plane needs to know
/// before they leave that their passwords will not be there, and finding out at
/// the gate is the failure this screen exists to prevent. So both halves are
/// shown: what keeps working, and what does not, each with the reason.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../offline/mode.dart';
import '../offline/sync.dart';
import '../theme.dart';
import 'sync_screen.dart';

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<OfflineMode>();
    final sync = context.watch<SyncService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Working offline')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(children: [
              SwitchListTile(
                value: mode.on,
                onChanged: (v) => context.read<OfflineMode>().set(v),
                title: const Text('Work from this phone',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  mode.on
                      ? 'Your records are read and saved here. Nothing is sent '
                          'until you press Sync.'
                      : 'Your computer is used when it can be reached, and this '
                          'phone when it cannot.',
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      // The thing people get wrong about this setting, said
                      // where they are making the decision.
                      'Leaving this off does not mean the app stops working '
                      'away from your computer — it already copes. Turn it on '
                      'when you would rather it did not reach for your computer '
                      'at all.',
                      style: TextStyle(
                          fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                  ),
                ]),
              ),
            ]),
          ),

          if (sync.pending > 0) ...[
            const SizedBox(height: 12),
            Card(
              color: kWarn.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.cloud_upload_outlined, color: kWarn),
                title: Text(
                  '${sync.pending} '
                  '${sync.pending == 1 ? 'change is' : 'changes are'} only on '
                  'this phone',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Tap to review and send them'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SyncScreen()),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          _Heading('Works without your computer', Icons.check_circle, kOk),
          const SizedBox(height: 6),
          Card(
            child: Column(
              children: [
                for (final m in worksOffline)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.check, color: kOk, size: 20),
                    title: Text(m.label),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _Heading('Needs your computer', Icons.cloud_off, kWarn),
          const SizedBox(height: 6),
          Card(
            child: Column(
              children: [
                for (final m in needsComputer)
                  ListTile(
                    leading: const Icon(Icons.cloud_off, color: kWarn, size: 20),
                    title: Text(m.label),
                    // The reason, not just the fact. "Vault unavailable" invites
                    // a bug report; the sentence explains why it is deliberate.
                    subtitle: Text(m.reason!,
                        style: const TextStyle(fontSize: 12.5)),
                    isThreeLine: m.reason!.length > 60,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, this.icon, this.colour);
  final String text;
  final IconData icon;
  final Color colour;

  @override
  // Expanded, not a bare Text. "Works without your computer" at the larger
  // text sizes people actually use overflows an iPhone SE by 72 pixels — a
  // striped yellow bar across the heading. Caught by the layout test rather
  // than by anybody looking at it here.
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: colour),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ]);
}
