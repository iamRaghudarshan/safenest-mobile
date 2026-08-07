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

/// A LIST, as opposed to a value in one.
///
/// This used to be a `const` table of four, mirroring a dict on the server. Both
/// are now rows: a person can add lists of their own — insurers, landlords,
/// payment methods — so a fixed client-side list would show four of however many
/// they have, and the new ones would be invisible on the phone.
class MasterType {
  const MasterType({
    required this.id,
    required this.type,
    required this.label,
    this.field = 'emoji',
    this.icon,
    this.isBuiltin = false,
    this.count = 0,
  });

  final int id;

  /// The identity. Never editable, for a custom list as much as a built-in:
  /// every value points at its list through this, and the app's own forms name
  /// `expense_category` and `bank` in code.
  final String type;
  final String label;

  /// 'emoji' or 'color' — which extra this list's values carry. Banks have a
  /// brand colour; categories have a glyph. Offering both would invite setting
  /// one the server drops.
  final String field;

  /// The emoji shown for the list itself, if its owner picked one.
  final String? icon;

  /// One of the four the product itself reads. Renameable, not removable.
  final bool isBuiltin;
  final int count;

  static MasterType fromJson(Map<String, dynamic> j) => MasterType(
        id: (j['id'] as num).toInt(),
        type: '${j['type'] ?? ''}',
        label: '${j['label'] ?? ''}',
        field: '${j['field'] ?? 'emoji'}',
        icon: '${j['icon'] ?? ''}'.isEmpty ? null : '${j['icon']}',
        isBuiltin: (j['is_builtin'] ?? 0) == 1,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );

  bool get usesEmoji => field != 'color';

  /// A glyph for the four the product ships with, so they look like the module
  /// they belong to rather than all sharing one generic tag. A list somebody
  /// added gets the generic one unless they chose an emoji for it.
  IconData get fallbackIcon => switch (type) {
        'expense_category' => Icons.receipt_long_outlined,
        'bank' => Icons.account_balance_outlined,
        'document_category' => Icons.folder_outlined,
        'vault_category' => Icons.lock_outline,
        _ => Icons.label_outline,
      };

  /// Said only for the built-ins, because only for those does the app know what
  /// the list is FOR. Making something up for a list called "Landlords" would
  /// be the app explaining the person's own data back to them, wrongly.
  String get blurb => switch (type) {
        'expense_category' => 'What you file a transaction under',
        'bank' => 'Card issuers and lenders, with their colours',
        'document_category' => 'How scanned paperwork is filed',
        'vault_category' => 'How saved passwords are grouped',
        _ => count == 1 ? '1 entry' : '$count entries',
      };
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

  /// Every list this person has — the four built-ins plus any of their own.
  ///
  /// Not cached. It is read when the manage screen opens and after every change
  /// to it, and a stale one here would show a list somebody just deleted or hide
  /// one they just made — which on the screen whose whole job is editing them is
  /// the one place a cache cannot pay for itself.
  Future<List<MasterType>> lists() async {
    final d = await apiOf().get('/api/masters/types');
    final raw = d is Map ? (d['types'] as List? ?? const []) : const [];
    return [
      for (final e in raw) MasterType.fromJson(Map<String, dynamic>.from(e as Map))
    ];
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
