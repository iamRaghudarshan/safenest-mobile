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
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';
import '../widgets/skeleton.dart';

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

  /// Add (or edit) a vault entry. This screen shipped with NO way to add one —
  /// the server has POST /api/vault, the phone just never called it, so the vault
  /// could be revealed and searched but never filled. This is that missing door.
  Future<void> _openEdit([Map<String, dynamic>? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VaultEditSheet(existing: existing),
    );
    if (saved == true) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(existing == null ? 'Saved to vault' : 'Saved'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    }
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
      floatingActionButton: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kBrand, kBrand2],
          ),
          boxShadow: [
            BoxShadow(
                color: kBrand.withValues(alpha: 0.44),
                blurRadius: 28,
                offset: const Offset(0, 12)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Semantics(
            button: true,
            label: 'Add a password',
            child: Tooltip(
              message: 'Add a password',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openEdit(),
                child: const Icon(Icons.add, size: 30, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
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
                ? const SkeletonList()
                : _error != null
                    ? _VaultProblem(message: _error!, onRetry: _load)
                    : shown.isEmpty
                        ? _VaultEmpty(filtered: _filter.isNotEmpty)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 4, 14, 24),
                              itemCount: shown.length,
                              itemBuilder: (ctx, i) {
                                final v = shown[i];
                                final cat = '${v['category'] ?? ''}';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: BrandCard(
                                    padding: const EdgeInsets.fromLTRB(
                                        14, 12, 10, 12),
                                    child: Row(children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: kModuleColours['vault'],
                                          borderRadius:
                                              BorderRadius.circular(13),
                                          boxShadow: [
                                            BoxShadow(
                                              color: kModuleColours['vault']!
                                                  .withValues(alpha: 0.32),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(Icons.key_outlined,
                                            size: 22, color: Colors.white),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('${v['title'] ?? 'Entry'}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              if ('${v['username'] ?? ''}'
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text('${v['username']}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(ctx)
                                                        .textTheme
                                                        .bodySmall),
                                              ],
                                              if (cat.isNotEmpty) ...[
                                                const SizedBox(height: 7),
                                                Pill(cat,
                                                    colour: kModuleColours[
                                                        'vault']),
                                              ],
                                            ]),
                                      ),
                                      // Still a button, still one entry at a
                                      // time, still nothing kept. The colour
                                      // changed; what it does did not.
                                      TextButton(
                                        onPressed: () => _reveal(v),
                                        child: const Text('Reveal'),
                                      ),
                                    ]),
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

/// The vault's empty state, which has a job the other modules' do not: say what
/// this app does with a secret. "Nothing here yet" is fine for expenses; for the
/// place someone keeps their passwords, the reassurance IS the content.
class _VaultEmpty extends StatelessWidget {
  const _VaultEmpty({required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 40, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: kModuleColours['vault'],
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: kModuleColours['vault']!.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.lock_outline, size: 30, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(filtered ? 'Nothing matches' : 'Nothing in the vault yet',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  filtered
                      ? 'Try a different search'
                      : 'Entries are encrypted on your own computer. This app '
                          'shows them one at a time and keeps none.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ]),
        )
      ]);
}

/// A vault that will not load is the most alarming version of this screen, so
/// it says plainly that nothing has been lost and nothing has been exposed.
class _VaultProblem extends StatelessWidget {
  const _VaultProblem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 40, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: kWarn.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Center(
                  child: Text('📡', style: TextStyle(fontSize: 30))),
            ),
            const SizedBox(height: 16),
            const Text('Can’t open the vault right now',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  'Your entries are safe and still encrypted on your computer. '
                  'Nothing was sent anywhere.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.outline)),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 190),
              child: BrandButton(label: 'Try again', onPressed: onRetry),
            ),
          ]),
        )
      ]);
}

/// Add or edit a vault entry. Title is required; the password is optional on an
/// edit (blank keeps the stored one) and is encrypted server-side — nothing here
/// or on the phone holds it in the clear.
class _VaultEditSheet extends StatefulWidget {
  const _VaultEditSheet({this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<_VaultEditSheet> createState() => _VaultEditSheetState();
}

class _VaultEditSheetState extends State<_VaultEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _category;
  bool _show = false;
  bool _busy = false;
  String? _error;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: '${e?['title'] ?? ''}');
    _username = TextEditingController(text: '${e?['username'] ?? ''}');
    _password = TextEditingController();
    _url = TextEditingController(text: '${e?['url'] ?? ''}');
    _category = TextEditingController(text: '${e?['category'] ?? ''}');
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'A title is needed');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'title': title,
      'username': _username.text.trim(),
      'url': _url.text.trim(),
      'category': _category.text.trim(),
      if (_password.text.isNotEmpty) 'password': _password.text,
    };
    try {
      final api = context.read<Session>().api;
      final id = widget.existing?['id'];
      if (id != null) {
        await api.put('/api/vault/$id', body);
      } else {
        await api.post('/api/vault', body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.existing != null;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 4, 18, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing ? 'Edit entry' : 'New password',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
              decoration: InputDecoration(
                  labelText: 'Title *',
                  hintText: 'Gmail, Bank, Wi-Fi…',
                  prefixIcon: const Icon(Icons.label_outline),
                  errorText: _titleError),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                  labelText: 'Username or email',
                  prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_show,
              decoration: InputDecoration(
                labelText:
                    editing ? 'New password (blank keeps it)' : 'Password',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Website', prefixIcon: Icon(Icons.link)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Category', prefixIcon: Icon(Icons.folder_outlined)),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline,
                      color: theme.colorScheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            BrandButton(
              label: editing ? 'Save changes' : 'Save to vault',
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 8),
            Text(
              'The password is encrypted on your computer. Nothing from the '
              'vault is stored on this phone.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
