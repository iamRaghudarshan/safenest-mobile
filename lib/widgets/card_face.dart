/// `.cc` — the credit-card visual, transcribed from the web app.
///
/// A card in this product does not look like a list row, and the phone was
/// showing one: bank name, last four, an amount. The web app draws an actual
/// card — a gradient chosen from the bank's own name, a gold chip, the masked
/// number, the due date and limit along the bottom, and a strip saying whether
/// this month is paid.
///
/// THE GRADIENT IS DERIVED, NOT STORED. `gradientFor()` hashes the bank name
/// into one of seven, so HDFC is the same colour on the laptop and on the phone
/// and stays that colour for ever without a column to hold it. The hash has to
/// match the web app's exactly — same multiplier, same unsigned 32-bit wrap —
/// or the same card would be two different colours on the two screens, which is
/// precisely the drift this file exists to stop.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'pill.dart';

/// The seven, in the web app's order. Index matters: it is what the hash picks.
const _gradients = <List<Color>>[
  [Color(0xFF5B3DF5), Color(0xFF8B5CF6)],
  [Color(0xFF0EA5E9), Color(0xFF2563EB)],
  [Color(0xFFEC4899), Color(0xFFBE185D)],
  [Color(0xFF10B981), Color(0xFF0F766E)],
  [Color(0xFFF59E0B), Color(0xFFB45309)],
  [Color(0xFF334155), Color(0xFF0F172A)],
  [Color(0xFF7C3AED), Color(0xFF4338CA)],
];

/// `for (const ch of bank) h = (h * 31 + ch.charCodeAt(0)) >>> 0`
///
/// `>>> 0` is JavaScript's unsigned 32-bit wrap. Dart's int is 64-bit, so the
/// mask is not optional — without it the value never wraps, the modulo lands
/// elsewhere, and every card is a different colour from the web app's.
List<Color> gradientFor(String bank) {
  final src = bank.isEmpty ? 'card' : bank;
  var h = 0;
  for (final unit in src.codeUnits) {
    h = (h * 31 + unit) & 0xFFFFFFFF;
  }
  return _gradients[h % _gradients.length];
}

/// 5 -> 5th, 22 -> 22nd, 11 -> 11th. The web app's `ordinal()`:
///
///     const s = ['th','st','nd','rd'], v = n % 100
///     return n + (s[(v-20)%10] || s[v] || s[0])
///
/// It relies on an out-of-range index giving `undefined` so the next fallback
/// runs — and on JS's % keeping the SIGN of the left operand. Dart's % is
/// always non-negative, so `(11-20) % 10` is -9 in JavaScript (out of range,
/// falls through to 'th') and 1 in Dart — which renders "11st".
///
/// `remainder()` is the truncated version and matches JS. Same shape as the
/// `>>> 0` above: two languages that look alike and disagree on negatives.
String ordinal(int n) {
  const s = ['th', 'st', 'nd', 'rd'];
  final v = n % 100;
  String? at(int i) => i >= 0 && i < s.length ? s[i] : null;
  return '$n${at((v - 20).remainder(10)) ?? at(v) ?? s[0]}';
}

class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    this.compact = false,
    this.onTap,
    this.onPay,
  });

  final Map<String, dynamic> card;

  /// The shorter form used as a preview. `.cc.compact`.
  final bool compact;
  final VoidCallback? onTap;

  /// Present in the list, absent in a preview — the paid strip only appears
  /// when there is something to press.
  final VoidCallback? onPay;

  String _money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (n == null || n == 0) return '';
    if (n >= 10000000) return '₹${(n / 10000000).toStringAsFixed(2)}Cr';
    if (n >= 100000) return '₹${(n / 100000).toStringAsFixed(2)}L';
    if (n >= 1000) return '₹${(n / 1000).toStringAsFixed(1)}k';
    return '₹${n.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final g = gradientFor('${card['bank'] ?? ''}');
    final paid = card['paid_this_month'] == true;
    final last4 = '${card['last4'] ?? ''}';
    final days = card['days_until'] is num
        ? (card['days_until'] as num).toInt()
        : null;
    final dueDay = card['due_day'] is num ? (card['due_day'] as num).toInt() : null;
    final limit = _money(card['credit_limit']);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 120 : 176),
        padding: EdgeInsets.all(compact ? 14 : 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: g,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: g.last.withValues(alpha: 0.45),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // .cc-glow — a soft disc bleeding off the top-right corner. Most of
          // what stops this looking like a coloured rectangle.
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text('${card['bank'] ?? 'Card issuer'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        )),
                  ),
                  const SizedBox(width: 8),
                  // .cc-chip — a real gold chip. Without it this is a gradient
                  // with text on it rather than a card.
                  Container(
                    width: 36,
                    height: 27,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF6D67B), Color(0xFFCAA24E)],
                      ),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3), width: 1),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 14 : 22),
              Text(
                '•••• •••• •••• ${last4.isEmpty ? '••••' : last4}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 15 : 18,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(height: compact ? 10 : 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _field(
                      paid ? 'Next due' : 'Payment due',
                      dueDay == null
                          ? '—'
                          : '${card['next_due_fmt'] ?? '${ordinal(dueDay)} monthly'}',
                    ),
                  ),
                  if (limit.isNotEmpty)
                    _field('Limit', limit, right: true),
                ],
              ),
              if (onPay != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.22))),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Row(children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: paid ? const Color(0xFF4ADE80) : kWarn,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            paid
                                ? 'Paid${card['paid_date'] != null ? ' · ${card['paid_date']}' : ''}'
                                : 'Not paid this month',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    // .cc-paybtn — white on the gradient, so the one action on
                    // the card is the brightest thing on it.
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: onPay,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Text(paid ? 'Undo' : 'Mark paid',
                              style: const TextStyle(
                                  color: Color(0xFF1A1327),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ),
          // .cc-pill — the overdue/due badge, dark and translucent so it reads
          // on any of the seven gradients.
          if (!paid && days != null)
            Positioned(
              top: 0,
              right: 46,
              child: Pill(
                days < 0
                    ? '${days.abs()}d overdue'
                    : days == 0
                        ? 'Due today'
                        : days == 1
                            ? 'Due tomorrow'
                            : 'In $days days',
                colour: Colors.white,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _field(String label, String value, {bool right = false}) => Column(
        crossAxisAlignment:
            right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 10,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ],
      );
}
