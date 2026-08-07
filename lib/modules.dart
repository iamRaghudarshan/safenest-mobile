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

enum FieldKind { text, number, money, date, note, choice, toggle }

class ModuleField {
  const ModuleField(this.key, this.label, this.kind,
      {this.choices = const [], this.required = false});
  final String key;
  final String label;
  final FieldKind kind;
  final List<String> choices;
  final bool required;
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
      ModuleField('due_date', 'When', FieldKind.date, required: true),
      ModuleField('recurrence', 'Repeats', FieldKind.choice,
          choices: ['none', 'daily', 'weekly', 'monthly', 'yearly']),
      ModuleField('notify_push', 'Notify me', FieldKind.toggle),
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
      ModuleField('priority', 'Priority', FieldKind.choice,
          choices: ['low', 'normal', 'high']),
      ModuleField('due_date', 'By when', FieldKind.date),
      ModuleField('status', 'Status', FieldKind.choice,
          choices: ['open', 'done']),
    ],
  ),
  ModuleSpec(
    key: 'cards',
    label: 'Cards',
    icon: Icons.credit_card_outlined,
    colour: Color(0xFFEC4899),
    titleField: 'bank',
    subtitleField: 'last4',
    amountField: 'statement_amount',
    dateField: 'due_date',
    blurb: 'Credit cards and what is due',
    fields: [
      ModuleField('bank', 'Bank', FieldKind.text, required: true),
      ModuleField('last4', 'Last 4 digits', FieldKind.text),
      ModuleField('credit_limit', 'Limit', FieldKind.money),
      ModuleField('billing_day', 'Billing day', FieldKind.number),
      ModuleField('due_date', 'Due date', FieldKind.date),
      ModuleField('statement_amount', 'This statement', FieldKind.money),
      ModuleField('status', 'Status', FieldKind.choice,
          choices: ['active', 'closed']),
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
      ModuleField('next_due_date', 'Next due', FieldKind.date),
      ModuleField('status', 'Status', FieldKind.choice,
          choices: ['active', 'closed']),
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
      ModuleField('frequency', 'Paid', FieldKind.choice,
          choices: ['monthly', 'quarterly', 'half-yearly', 'yearly']),
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
