/// The vault: passwords, encrypted on the owner's own machine.
///
/// WHY THIS SCREEN IS DELIBERATELY DULL
/// The secret is AES-256-GCM on the server under a key that never leaves that
/// computer. This app therefore does the least it possibly can: it lists titles
/// and usernames, and asks for one password at a time, only when someone taps
/// Reveal. That is the whole design.
///
/// What it must never do, and does not:
///   * fetch the passwords with the list. A list endpoint that returned secrets
///     would put every one of them in this phone's memory — and in any crash
///     report — to render a screen that shows none of them.
///   * cache a revealed secret. It is held while the sheet is open and dropped
///     when it closes. There is no copy to leak afterwards.
///   * write one to disk. Nothing here touches storage, secure or otherwise.
///
/// So the exposure of a stolen phone is the session token, which can be revoked
/// from the computer by changing the password — token_version kills every
/// existing session. It is not the vault.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/vault');
      setState(() {
        _items = [
          for (final e in ((d as Map)['items'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _reveal(Map<String, dynamic> item) async {
    String? secret;
    String? failure;
    try {
      final d = await context
          .read<Session>()
          .api
          .post('/api/vault/${item['id']}/reveal');
      if (d is Map) {
        secret = '${d['password'] ?? d['secret'] ?? d['value'] ?? ''}';
      }
    } on ApiError catch (e) {
      failure = e.message;
    }
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isDismissible: true,
      builder: (ctx) => _RevealSheet(
        title: '${item['title'] ?? 'Entry'}',
        username: '${item['username'] ?? ''}',
        secret: secret,
        failure: failure,
      ),
    );
    // Nothing is retained: `secret` goes out of scope with the sheet, and there
    // is no field on this State holding it.
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filter.isEmpty
        ? _items
        : _items
            .where((i) =>
                '${i['title'] ?? ''} ${i['username'] ?? ''}'
                    .toLowerCase()
                    .contains(_filter.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Vault')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v),
              decoration: const InputDecoration(
                hintText: 'Find an entry',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                                onPressed: _load, child: const Text('Try again')),
                          ]),
                        ),
                      )
                    : shown.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(36),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.lock_outline, size: 44),
                                SizedBox(height: 14),
                                Text('Nothing in the vault yet'),
                                SizedBox(height: 8),
                                Text(
                                  'Entries are encrypted on your computer. This '
                                  'app shows them one at a time and keeps none.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ]),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              itemCount: shown.length,
                              separatorBuilder: (_, i) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final v = shown[i];
                                return ListTile(
                                  leading: const CircleAvatar(
                                      child: Icon(Icons.key_outlined, size: 18)),
                                  title: Text('${v['title'] ?? 'Entry'}'),
                                  subtitle: '${v['username'] ?? ''}'.isEmpty
                                      ? null
                                      : Text('${v['username']}'),
                                  trailing: TextButton(
                                    onPressed: () => _reveal(v),
                                    child: const Text('Reveal'),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _RevealSheet extends StatefulWidget {
  const _RevealSheet({
    required this.title,
    required this.username,
    required this.secret,
    required this.failure,
  });
  final String title;
  final String username;
  final String? secret;
  final String? failure;

  @override
  State<_RevealSheet> createState() => _RevealSheetState();
}

class _RevealSheetState extends State<_RevealSheet> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.secret;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            if (widget.username.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(widget.username,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 18),
            if (widget.failure != null)
              Text(widget.failure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))
            else if (s == null || s.isEmpty)
              const Text('Nothing was returned for this entry.')
            else ...[
              // Hidden until asked for even here, because a sheet that opens
              // straight onto a password is one that can be read over a
              // shoulder before anyone reacts.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _shown ? s : '•' * s.length.clamp(8, 24),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 16, letterSpacing: 1),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton.icon(
                  onPressed: () => setState(() => _shown = !_shown),
                  icon: Icon(_shown ? Icons.visibility_off : Icons.visibility,
                      size: 18),
                  label: Text(_shown ? 'Hide' : 'Show'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: s));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Copied — the clipboard is shared '
                                'with other apps, so paste it and move on')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            Text(
              'Closing this forgets it. Nothing from your vault is stored on '
              'this phone.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
