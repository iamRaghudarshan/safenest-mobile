/// What the eight record modules are, described once.
///
/// WHY A SPEC AND NOT EIGHT SCREENS
/// Every one of them is the same shape on the server: GET `/api/<key>` returns a
/// list, POST creates, DELETE removes. Writing eight nearly-identical screens
/// would mean eight places for a fix to be applied and seven of them to be
/// forgotten in — and the web app has already been bitten by exactly that kind
/// of drift. One generic list and one generic form read this table instead.
///
/// The order matters: it is the order they appear on the Records screen, and it
/// is roughly how often a person opens them, not alphabetical.
///
/// The colours are NOT chosen here. They are the web app's per-module accents —
/// --c-expenses, --c-loans and the rest from index.css — so a module is the same
/// colour in the hand as on the laptop. The first version invented its own, and
/// the same module was two different colours depending on which screen you were
/// looking at.
library;

import 'package:flutter/material.dart';

enum FieldKind { text, number, money, date, time, note, choice, toggle }

class ModuleField {
  const ModuleField(this.key, this.label, this.kind,
      {this.choices = const [], this.required = false, this.hint});
  final String key;
  final String label;
  final FieldKind kind;

  /// EVERY value here must be one the column will accept.
  ///
  /// This is not a style note. Four of these lists were written from memory and
  /// all four were wrong against the real schema — to-dos offered priority
  /// "normal" where the column is enum('low','medium','high'), status "open"
  /// where it is enum('pending','done'), insurance "half-yearly" where it is
  /// half_yearly, and cards offered active/closed for a column that has no such
  /// value. Each one saved fine in the form and was refused by MySQL, which the
  /// phone showed as a bare failure with nothing to do about it. Read the enum
  /// before adding to one of these.
  final List<String> choices;
  final bool required;

  /// Shown under the field. For the ones where the app knows something the
  /// person does not — that a time is what turns a note into an alarm.
  final String? hint;
}

/// 'half_yearly' -> 'Half yearly'. The stored value is what the column wants;
/// this is only what it is called on screen, so no parallel list of labels can
/// drift out of step with the list of values above it.
String prettyChoice(String v) {
  if (v.isEmpty) return v;
  final words = v.replaceAll('_', ' ').replaceAll('-', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

class ModuleSpec {
  const ModuleSpec({
    required this.key,
    required this.label,
    required this.icon,
    required this.colour,
    required this.fields,
    required this.titleField,
    this.subtitleField,
    this.amountField,
    this.dateField,
    this.blurb = '',
  });

  /// Matches the API path and the permission key — /api/expenses is guarded by
  /// module_key "expenses". They are the same string on purpose.
  final String key;
  final String label;
  final IconData icon;
  final Color colour;
  final List<ModuleField> fields;

  /// Which field to show as the headline of a row, and what to put beside it.
  final String titleField;
  final String? subtitleField;
  final String? amountField;
  final String? dateField;
  final String blurb;
}

const kModules = <ModuleSpec>[
  ModuleSpec(
    key: 'expenses',
    label: 'Expenses',
    icon: Icons.receipt_long_outlined,
    colour: Color(0xFFF59E0B),
    titleField: 'category',
    subtitleField: 'note',
    amountField: 'amount',
    dateField: 'txn_date',
    blurb: 'What went out, and what came in',
    fields: [
      ModuleField('kind', 'Kind', FieldKind.choice,
          choices: ['expense', 'income'], required: true),
      ModuleField('category', 'Category', FieldKind.text, required: true),
      ModuleField('amount', 'Amount', FieldKind.money, required: true),
      ModuleField('method', 'Paid by', FieldKind.text),
      ModuleField('txn_date', 'Date', FieldKind.date, required: true),
      ModuleField('note', 'Note', FieldKind.note),
    ],
  ),
  ModuleSpec(
    key: 'reminders',
    label: 'Reminders',
    icon: Icons.notifications_outlined,
    colour: Color(0xFF8B5CF6),
    titleField: 'title',
    dateField: 'due_date',
    blurb: 'Things with a date attached',
    fields: [
      ModuleField('title', 'What', FieldKind.text, required: true),
      ModuleField('due_date', 'What day', FieldKind.date, required: true),
      // The field this whole change is about. Optional, and it has to stay
      // optional: a reminder with no time arrives with the daily summary, which
      // is how every reminder in this app worked until now. Filling it in is
      // what asks to be told at a particular hour instead.
      ModuleField('due_time', 'What time', FieldKind.time,
          hint: 'Leave empty to hear about it with the daily summary'),
      ModuleField('recurrence', 'Repeats', FieldKind.choice,
          choices: ['none', 'daily', 'weekly', 'monthly', 'yearly']),
      // Which module it belongs to. The web app groups the list by this and the
      // phone did not offer it at all, so everything added here landed in
      // "General" and could not be moved out of it from the phone.
      ModuleField('module_ref', 'Belongs to', FieldKind.choice, choices: [
        'general', 'loans', 'cards', 'insurance', 'investments', 'expenses', 'todo'
      ]),
      ModuleField('notify_push', 'Notify me', FieldKind.toggle),
      ModuleField('notify_email', 'Email me too', FieldKind.toggle),
    ],
  ),
  ModuleSpec(
    key: 'todos',
    label: 'To-dos',
    icon: Icons.checklist_outlined,
    colour: Color(0xFF14B8A6),
    titleField: 'title',
    subtitleField: 'status',
    dateField: 'due_date',
    blurb: 'The list',
    fields: [
      ModuleField('title', 'What', FieldKind.text, required: true),
      // 'medium', not 'normal' — enum('low','medium','high').
      ModuleField('priority', 'Priority', FieldKind.choice,
          choices: ['low', 'medium', 'high']),
      ModuleField('due_date', 'By when', FieldKind.date),
      // No 'yearly'. Unlike reminders, this column stops at monthly, and
      // offering a fifth value would be a save that fails at the database.
      ModuleField('recurrence', 'Repeats', FieldKind.choice,
          choices: ['none', 'daily', 'weekly', 'monthly']),
      // 'pending', not 'open' — enum('pending','done').
      ModuleField('status', 'Status', FieldKind.choice,
          choices: ['pending', 'done']),
    ],
  ),
  ModuleSpec(
    key: 'cards',
    label: 'Cards',
    icon: Icons.credit_card_outlined,
    colour: Color(0xFFEC4899),
    titleField: 'bank',
    subtitleField: 'last4',
    // Not statement_amount: nothing in the product ever writes that column, so
    // it is blank on every card and made the row look like it had failed to load.
    amountField: 'credit_limit',
    dateField: 'next_due_fmt',
    blurb: 'Credit cards and what is due',
    // Exactly cards.py's FIELDS, and no more. `statement_amount` and `status`
    // were both offered here and neither is accepted by the endpoint — they were
    // dropped on the floor, so typing a statement amount appeared to work and
    // then the value was simply gone.
    fields: [
      ModuleField('bank', 'Bank', FieldKind.text, required: true),
      ModuleField('last4', 'Last 4 digits', FieldKind.text),
      ModuleField('credit_limit', 'Limit', FieldKind.money),
      ModuleField('billing_day', 'Billing day', FieldKind.number,
          hint: 'Day of the month the bill is generated'),
      ModuleField('due_date', 'Due date', FieldKind.date),
    ],
  ),
  ModuleSpec(
    key: 'loans',
    label: 'Loans',
    icon: Icons.account_balance_outlined,
    colour: Color(0xFF6366F1),
    titleField: 'lender',
    subtitleField: 'loan_type',
    amountField: 'outstanding',
    dateField: 'next_due_date',
    blurb: 'What is owed, and the next instalment',
    fields: [
      ModuleField('lender', 'Lender', FieldKind.text, required: true),
      ModuleField('loan_type', 'Kind', FieldKind.text),
      ModuleField('principal', 'Principal', FieldKind.money),
      ModuleField('interest_rate', 'Interest %', FieldKind.number),
      ModuleField('emi', 'Instalment', FieldKind.money),
      ModuleField('tenure_months', 'Months', FieldKind.number),
      ModuleField('outstanding', 'Outstanding', FieldKind.money),
      // Both accepted by loans.py and both simply left out here, so a loan added
      // from the phone lost its start date and any note the person wrote about it.
      ModuleField('start_date', 'Started', FieldKind.date),
      ModuleField('next_due_date', 'Next due', FieldKind.date),
      ModuleField('status', 'Status', FieldKind.choice,
          choices: ['active', 'closed']),
      ModuleField('notes', 'Notes', FieldKind.note),
    ],
  ),
  ModuleSpec(
    key: 'insurance',
    label: 'Insurance',
    icon: Icons.health_and_safety_outlined,
    colour: Color(0xFF0EA5E9),
    titleField: 'provider',
    subtitleField: 'policy_no',
    amountField: 'premium',
    dateField: 'renewal_date',
    blurb: 'Policies and when they renew',
    fields: [
      ModuleField('provider', 'Provider', FieldKind.text, required: true),
      ModuleField('policy_type', 'Kind', FieldKind.text),
      ModuleField('policy_no', 'Policy number', FieldKind.text),
      ModuleField('premium', 'Premium', FieldKind.money),
      ModuleField('sum_assured', 'Sum assured', FieldKind.money),
      // half_yearly with an underscore. The hyphen version is not a value this
      // column has, and prettyChoice() is what makes it read properly on screen.
      ModuleField('frequency', 'Paid', FieldKind.choice,
          choices: ['monthly', 'quarterly', 'half_yearly', 'yearly']),
      ModuleField('renewal_date', 'Renews', FieldKind.date),
    ],
  ),
  ModuleSpec(
    key: 'investments',
    label: 'Investments',
    icon: Icons.trending_up_outlined,
    colour: Color(0xFF10B981),
    titleField: 'name',
    subtitleField: 'broker',
    amountField: 'current_value',
    dateField: 'maturity_date',
    blurb: 'What it was worth, and what it is worth',
    fields: [
      ModuleField('name', 'What', FieldKind.text, required: true),
      ModuleField('broker', 'Where', FieldKind.text),
      ModuleField('invest_type', 'Kind', FieldKind.text),
      ModuleField('invested_amount', 'Invested', FieldKind.money),
      ModuleField('current_value', 'Worth now', FieldKind.money),
      ModuleField('units', 'Units', FieldKind.number),
      ModuleField('maturity_date', 'Matures', FieldKind.date),
    ],
  ),
];

ModuleSpec? moduleByKey(String key) {
  for (final m in kModules) {
    if (m.key == key) return m;
  }
  return null;
}
