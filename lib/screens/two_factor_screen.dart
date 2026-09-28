/// The second half of a sign-in, for accounts that ask for a code.
///
/// The app used to refuse these outright — "not supported in the phone app
/// yet" — which meant that turning on two-step sign-in anywhere locked you out
/// of the phone, including on the owner's own account. The server has always
/// had the endpoint; only this screen was missing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';

class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({
    super.key,
    required this.brand,
    required this.pending,
    this.onSignedIn,
  });

  final Brand brand;
  final TwoFactorRequired pending;
  final VoidCallback? onSignedIn;

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _recovery = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The keyboard is up on arrival. This screen exists to take six digits and
    // nothing else, so making somebody tap the one field on it is pure friction.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Type the code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().completeTwoFactor(
            url: widget.pending.url,
            challenge: widget.pending.challenge,
            code: code,
          );
      widget.onSignedIn?.call();
      if (mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      // "That sign-in expired. Enter your password again." is the one failure
      // this screen cannot recover from: the challenge is single-use and
      // short-lived, so there is nothing left to retry against. Send them back
      // rather than leaving them typing codes into a dead form.
      final expired = e.message.toLowerCase().contains('expired');
      if (expired && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        return;
      }
      setState(() {
        _error = e.message;
        _busy = false;
      });
      _code.clear();
      _focus.requestFocus();
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.skin;

    return Scaffold(
      appBar: AppBar(title: const Text('One more step')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: t.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(t.radius),
              ),
              child: Icon(Icons.phonelink_lock_outlined, color: t.brand, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              _recovery ? 'Use a recovery code' : 'Enter your code',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _recovery
                  ? 'One of the codes you saved when you turned on two-step '
                      'sign-in. Each one works once.'
                  : 'Your password was right. Open your authenticator app and '
                      'type the six digits it shows for SafeNest.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _code,
              focusNode: _focus,
              autofocus: true,
              enabled: !_busy,
              // A recovery code is not six digits, so the keyboard and the
              // length limit both have to change with the mode — a numeric pad
              // in front of somebody holding a recovery code is a dead end.
              keyboardType:
                  _recovery ? TextInputType.text : TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: _recovery ? null : const [AutofillHints.oneTimeCode],
              inputFormatters: _recovery
                  ? null
                  : [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
              style: _recovery
                  ? null
                  : const TextStyle(
                      fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w700),
              textAlign: _recovery ? TextAlign.start : TextAlign.center,
              decoration: InputDecoration(
                hintText: _recovery ? 'Recovery code' : '000000',
                errorText: _error,
                prefixIcon: Icon(
                    _recovery ? Icons.vpn_key_outlined : Icons.pin_outlined),
              ),
              onChanged: (v) {
                if (_error != null) setState(() => _error = null);
                // Six digits is the whole answer, so there is nothing to
                // confirm — submitting on the last one saves a tap on the
                // screen people reach most often in a hurry.
                if (!_recovery && v.length == 6 && !_busy) _submit();
              },
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Sign in'),
            ),
            if (widget.pending.acceptsRecovery) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _recovery = !_recovery;
                          _code.clear();
                          _error = null;
                          _focus.requestFocus();
                        }),
                icon: Icon(_recovery
                    ? Icons.pin_outlined
                    : Icons.help_outline_rounded),
                label: Text(_recovery
                    ? 'I have my authenticator app'
                    : "I can't get to my authenticator"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
