/// The hub: every record module the signed-in person is actually allowed to use.
///
/// It asks the server which ones those are rather than showing all seven and
/// letting the taps fail. `guard(module, action)` refuses at the API, so an app
/// that ignored permissions would present a full menu and then produce a 403 for
/// half of it — which reads as the app being broken rather than as the account
/// being limited. The permissions are per user and per action, set by whoever
/// administers that copy.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../modules.dart';
import '../session.dart';
import 'module_list_screen.dart';
import 'vault_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  Set<String>? _allowed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    try {
      final me = await session.api.get('/api/auth/me');
      final map = me is Map ? Map<String, dynamic>.from(me) : <String, dynamic>{};
      final user = map['user'] is Map ? Map<String, dynamic>.from(map['user'] as Map) : map;

      // An admin bypasses the per-module checks everywhere on the server, so
      // showing them everything is not a shortcut — it is the same rule.
      if (user['role'] == 'admin') {
        // 'vault' is not in kModules — it has a reveal flow rather than a
        // list-and-form, so it is not driven by a ModuleSpec — but an admin can
        // still open it, and leaving it out here would hide it from them.
        setState(() =>
            _allowed = {...kModules.map((m) => m.key), 'vault'});
        return;
      }

      // The shape differs between installations that predate the permissions
      // screen, so both are accepted rather than assuming one.
      final perms = map['modules'] ?? map['permissions'] ?? user['modules'];
      final allowed = <String>{};
      if (perms is List) {
        for (final p in perms) {
          if (p is String) allowed.add(p);
          if (p is Map && p['module_key'] != null && (p['can_view'] ?? 1) == 1) {
            allowed.add(p['module_key'] as String);
          }
        }
      } else if (perms is Map) {
        perms.forEach((k, v) {
          if (v == true || (v is Map && (v['can_view'] ?? 1) == 1)) allowed.add('$k');
        });
      }
      // Nothing came back in a shape we recognise: show everything rather than
      // an empty screen. The server still refuses what it should, so the worst
      // case is a 403 the person can read — not a menu that looks broken.
      setState(() => _allowed = allowed.isEmpty
          ? {...kModules.map((m) => m.key), 'vault'}
          : allowed);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed;
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!)))
          : allowed == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (allowed.contains('vault'))
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple.withValues(alpha: 0.14),
                          child: const Icon(Icons.lock_outline,
                              color: Colors.deepPurple),
                        ),
                        title: const Text('Vault'),
                        subtitle: const Text('Passwords, encrypted on your computer'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const VaultScreen()),
                        ),
                      ),
                    for (final m in kModules)
                      if (allowed.contains(m.key))
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: m.colour.withValues(alpha: 0.14),
                            child: Icon(m.icon, color: m.colour),
                          ),
                          title: Text(m.label),
                          subtitle: Text(m.blurb),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => ModuleListScreen(spec: m)),
                          ),
                        ),
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Everything here is read from the computer you signed in '
                        'to, and saved back to it. Nothing is kept on this phone.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
    );
  }
}
