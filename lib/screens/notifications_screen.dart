/// Notifications — the inbox the web app keeps, on the phone.
///
/// Reads /api/notifications/inbox and marks things read. Push itself is not set
/// up here: that needs a VAPID key exchange and a per-device subscription, and
/// wiring half of it would leave a switch that looks like it works.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/notifications/inbox');
      final list = d is List ? d : (d is Map ? (d['items'] ?? const []) : const []);
      setState(() {
        _rows = [for (final e in (list as List)) Map<String, dynamic>.from(e as Map)];
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

  Future<void> _readAll() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api.post('/api/notifications/inbox/read-all');
      _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _rows.where((r) => (r['is_read'] ?? 0) == 0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(onPressed: _readAll, child: const Text('Mark all read')),
        ],
      ),
      body: _loading
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
              : _rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(36),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.notifications_none, size: 44),
                          SizedBox(height: 12),
                          Text('Nothing here'),
                          SizedBox(height: 6),
                          Text(
                            'Reminders that come due, and messages from whoever '
                            'supplied SafeNest, appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12),
                          ),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, i) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final n = _rows[i];
                          final read = (n['is_read'] ?? 0) == 1;
                          return ListTile(
                            leading: Icon(
                              read
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: read
                                  ? Theme.of(ctx).colorScheme.outline
                                  : kBrand,
                            ),
                            title: Text('${n['title'] ?? ''}',
                                style: TextStyle(
                                    fontWeight:
                                        read ? FontWeight.w400 : FontWeight.w700)),
                            subtitle: Text('${n['body'] ?? ''}'),
                            trailing: Text('${n['created_at'] ?? ''}',
                                style: Theme.of(ctx).textTheme.labelSmall),
                          );
                        },
                      ),
                    ),
    );
  }
}
