/// The user's own lookup lists — categories, banks — and the client for them.
///
/// WHY THE PHONE NEEDED THIS AT ALL
/// Every form here offered a bare text box for "Category" and "Bank". The
/// server has had `/api/masters` all along, seeded per user with real defaults:
/// nine banks with their brand colours, expense categories with emoji, document
/// and vault categories. A text box does not merely look worse than a picker —
/// it produces DIFFERENT DATA. Typing "food" on the phone where the laptop
/// stored "Food & Dining" gives one person two categories that are the same
/// thing, and no total either of them adds up is right afterwards.
///
/// Seeded lazily by the server: the first GET for a type that has no rows
/// creates the defaults. So there is no "empty" case to design for on a fresh
/// account — asking is what fills it.
library;

import 'package:flutter/material.dart';

import 'api.dart';

class MasterItem {
  const MasterItem({
    required this.id,
    required this.key,
    required this.label,
    this.emoji,
    this.color,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final int id;

  /// The stable slug. Records store the LABEL (that is what the record columns
  /// hold and what the web app writes), so this is for identity here, not for
  /// what gets saved.
  final String key;
  final String label;
  final String? emoji;
  final String? color;
  final bool isActive;
  final int sortOrder;

  static MasterItem fromJson(Map<String, dynamic> j) => MasterItem(
        id: (j['id'] as num).toInt(),
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? ''}',
        emoji: '${j['emoji'] ?? ''}'.isEmpty ? null : '${j['emoji']}',
        color: '${j['color'] ?? ''}'.isEmpty ? null : '${j['color']}',
        isActive: (j['is_active'] ?? 1) == 1,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  /// '#004c8f' -> a Color. Returns null rather than throwing on anything odd,
  /// because a malformed colour must cost the tint and not the whole list.
  Color? get tint {
    final c = color;
    if (c == null) return null;
    final hex = c.replaceFirst('#', '').trim();
    if (hex.length != 6) return null;
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
}

/// The four types the server defines, with the field each one edits. Mirrors
/// `masters.py::MASTER_TYPES` — a type this does not know about is simply not
/// offered rather than guessed at.
class MasterType {
  const MasterType(this.type, this.label, this.field, this.icon, this.blurb);
  final String type;
  final String label;

  /// 'emoji' or 'color' — which extra the type carries. Banks have a brand
  /// colour; categories have a glyph. Offering both for both would invite
  /// setting one the server will drop.
  final String field;
  final IconData icon;
  final String blurb;
}

const kMasterTypes = <MasterType>[
  MasterType('expense_category', 'Expense categories', 'emoji',
      Icons.receipt_long_outlined, 'What you file a transaction under'),
  MasterType('bank', 'Banks', 'color', Icons.account_balance_outlined,
      'Card issuers and lenders, with their colours'),
  MasterType('document_category', 'Document categories', 'emoji',
      Icons.folder_outlined, 'How scanned paperwork is filed'),
  MasterType('vault_category', 'Vault categories', 'emoji', Icons.lock_outline,
      'How saved passwords are grouped'),
];

MasterType? masterTypeOf(String type) {
  for (final t in kMasterTypes) {
    if (t.type == type) return t;
  }
  return null;
}

/// One in-memory copy per type for the life of the app run.
///
/// A picker is opened far more often than these lists change, and every record
/// sheet would otherwise fetch the same nine banks again. Editing goes through
/// `forget()` so a list changed on the Masters screen is re-read the next time
/// a form asks — the same shape the server's own `app_name_cached` uses, and for
/// the same reason.
class MasterCache {
  MasterCache(this.apiOf);

  /// A FUNCTION returning the current client, not a client.
  ///
  /// `Session.api` is a getter that builds a fresh Api from whatever token is
  /// held right now. Capturing one at construction time would freeze the token
  /// as it was before anybody signed in, and every masters request would go out
  /// unauthenticated for the rest of the run.
  final Api Function() apiOf;

  final _cache = <String, List<MasterItem>>{};

  Future<List<MasterItem>> load(String type, {bool activeOnly = true}) async {
    final key = '$type/$activeOnly';
    final hit = _cache[key];
    if (hit != null) return hit;

    final d = await apiOf().get('/api/masters', {
      'type': type,
      if (activeOnly) 'active': '1',
    });
    final raw = d is Map ? (d['items'] as List? ?? const []) : const [];
    final items = [
      for (final e in raw) MasterItem.fromJson(Map<String, dynamic>.from(e as Map))
    ];
    _cache[key] = items;
    return items;
  }

  /// After any edit. Both variants of a type go, because activeOnly=true is a
  /// filtered view of the same rows and leaving it behind would show a list
  /// still containing something just hidden.
  void forget([String? type]) {
    if (type == null) {
      _cache.clear();
      return;
    }
    _cache.removeWhere((k, _) => k.startsWith('$type/'));
  }
}
