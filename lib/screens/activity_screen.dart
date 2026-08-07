/// The activity log — what has happened in this copy, newest first.
///
/// Reads the same /api/activity the web app does. It is worth having on a phone
/// for one reason above the others: it is where you look when something has
/// changed and you did not change it.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
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
      final d = await context.read<Session>().api.get('/api/activity', {'limit': '200'});
      final list = d is List ? d : (d is Map ? (d['items'] ?? d['rows'] ?? const []) : const []);
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

  /// A colour per kind of action, so a page of text has some shape to it.
  Color _tint(String action) {
    if (action.contains('delete') || action.contains('revoke')) return kDanger;
    if (action.contains('create') || action.contains('upload')) return kOk;
    if (action.contains('login') || action.contains('password')) return kBrand;
    return kWarn;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
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
                  ? const Center(child: Text('Nothing recorded yet'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, i) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final r = _rows[i];
                          final action = '${r['action'] ?? ''}';
                          final label = '${r['label'] ?? r['entity'] ?? ''}';
                          return ListTile(
                            leading: Container(
                              height: 30,
                              width: 30,
                              decoration: BoxDecoration(
                                color: _tint(action).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(Icons.circle,
                                  size: 9, color: _tint(action)),
                            ),
                            title: Text(action.replaceAll('_', ' ')),
                            subtitle: label.isEmpty ? null : Text(label),
                            trailing: Text('${r['created_at'] ?? r['at'] ?? ''}',
                                style: Theme.of(ctx).textTheme.labelSmall),
                          );
                        },
                      ),
                    ),
    );
  }
}
