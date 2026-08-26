/// The Sync screen: what is waiting, and the button that sends it.
///
/// Deliberately plain about one thing — until these have synced, they exist on
/// this phone and nowhere else. That sentence is on the screen, not buried in a
/// help page, because it is the only reason any of this needs attention.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../offline/store.dart';
import '../offline/sync.dart';
import '../theme.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, this.initialPending});

  /// Test hook, following the convention the other screens use: a widget test
  /// can lay this out with no database and no server behind it.
  final List<PendingOp>? initialPending;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<PendingOp>? _ops;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ops = widget.initialPending;
    if (widget.initialPending == null) _load();
  }

  Future<void> _load() async {
    try {
      final sync = context.read<SyncService>();
      await sync.refreshPending();
      if (!mounted) return;
      setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _run() async {
    final sync = context.read<SyncService>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await sync.run();
    if (!mounted) return;
    await _load();
    if (!mounted) return;

    messenger.showSnackBar(SnackBar(
      content: Text(result.blocked
          ? result.blockedReason!
          : _sentence(result)),
      duration: Duration(seconds: result.blocked || result.outstanding > 0 ? 6 : 3),
    ));
  }

  /// What happened, in words rather than five counters.
  String _sentence(SyncResult r) {
    if (r.sent == 0) return 'Nothing was waiting';
    final parts = <String>[];
    if (r.saved > 0) parts.add('${r.saved} saved');
    if (r.already > 0) parts.add('${r.already} already there');
    if (r.conflicts > 0) {
      parts.add('${r.conflicts} changed on the computer too');
    }
    if (r.refused > 0) parts.add('${r.refused} refused');
    if (r.failed > 0) parts.add('${r.failed} could not be sent');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final cs = Theme.of(context).colorScheme;
    final waiting = _ops?.length ?? sync.pending;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(waiting == 0 ? Icons.cloud_done : Icons.cloud_upload,
                        color: waiting == 0 ? kOk : cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        waiting == 0
                            ? 'Everything is on your computer'
                            : '$waiting ${waiting == 1 ? 'change' : 'changes'} '
                                'waiting to be sent',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                  if (waiting > 0) ...[
                    const SizedBox(height: 8),
                    // The whole reason this screen exists. Not a footnote.
                    Text(
                      'Until these are sent they are only on this phone. If you '
                      'lose it, they are gone.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                  if (sync.running) ...[
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value: sync.total == 0 ? null : sync.progress,
                    ),
                    const SizedBox(height: 8),
                    Text(sync.step,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: sync.running || waiting == 0 ? null : _run,
                      icon: const Icon(Icons.sync),
                      label: Text(sync.running
                          ? 'Sending…'
                          : waiting == 0
                              ? 'Nothing to send'
                              : 'Sync now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: kDanger)),
          ],
          if ((_ops ?? const []).isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Waiting', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final o in _ops!) _OpRow(op: o),
          ],
        ],
      ),
    );
  }
}

class _OpRow extends StatelessWidget {
  const _OpRow({required this.op});
  final PendingOp op;

  static const _verb = {
    Op.create: 'New',
    Op.update: 'Edited',
    Op.delete: 'Deleted',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A refusal must not look like a queue. This is the same reason the store
    // keeps three states rather than a boolean: "waiting" and "was refused"
    // mean opposite things to whoever is looking at the list.
    final bad = op.state == OpState.failed;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        bad ? Icons.error_outline : Icons.schedule,
        color: bad ? kWarn : cs.onSurfaceVariant,
        size: 20,
      ),
      title: Text('${_verb[op.op]} · ${op.module}'),
      subtitle: op.lastError == null
          ? null
          : Text(op.lastError!, style: const TextStyle(fontSize: 12)),
    );
  }
}
