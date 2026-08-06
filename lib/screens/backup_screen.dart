/// One button. This is the screen the whole application was built for.
///
/// Everything the web app could not do is here: no picker, no selecting, no
/// fifty at a time. The app reads the library directly and sends what is not
/// already on the computer.
///
/// It does NOT start on its own. An app that copies somebody's entire camera
/// roll the moment it is opened is exactly what people are right to distrust,
/// and this product's whole argument is that it is not that. The owner presses
/// the button, or schedules it, and can stop it at any point — stopping loses
/// nothing, because what has already been sent is remembered.
library;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../backup.dart';
import '../session.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupService _service;

  @override
  void initState() {
    super.initState();
    _service = BackupService(context.read<Session>().api);
    _service.addListener(_onChange);
    _service.load();
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _service.removeListener(_onChange);
    _service.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _service.progress;
    final running = p.state == BackupState.running || p.state == BackupState.scanning;

    return Scaffold(
      appBar: AppBar(title: const Text('Back up this phone')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            'Every photo on this phone, copied to your own computer.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'No choosing, no batches. Photos already there are skipped, so you '
            'can run this as often as you like.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 30),

          if (running) ...[
            LinearProgressIndicator(value: p.total == 0 ? null : p.fraction),
            const SizedBox(height: 14),
            Text(
              p.state == BackupState.scanning
                  ? p.message
                  : '${p.handled} of ${p.total}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${p.done} sent · ${p.skipped} already there'
              '${p.failed > 0 ? ' · ${p.failed} could not be read' : ''}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _service.stop,
              child: const Text('Stop'),
            ),
            const SizedBox(height: 12),
            Text(
              'Keep this screen open while it runs.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: () => _service.runFullBackup(),
              icon: const Icon(Icons.backup),
              label: Text(p.state == BackupState.paused
                  ? 'Carry on backing up'
                  : 'Back up all my photos'),
            ),
            if (p.message.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(p.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (p.state == BackupState.failed) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: PhotoManager.openSetting,
                child: const Text('Open photo settings'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
