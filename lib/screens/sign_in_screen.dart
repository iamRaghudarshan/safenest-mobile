/// Signing in to YOUR SafeNest — which means saying which one first.
///
/// Every customer runs their own copy on their own machine, so the address is
/// the first question, not a setting buried later. Getting this wrong is the
/// most likely reason a new install fails, so the screen checks the address is
/// really a SafeNest before it sends a password to it: a domain that resolves to
/// somebody else's website answers 200 perfectly happily, and "wrong password"
/// would be a lie in that case.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../discover.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/brand_button.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.brand, this.onSignedIn});
  final Brand brand;
  final VoidCallback? onSignedIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  /// Addresses this phone has signed in with before.
  ///
  /// The SAME computer usually has two — a home address on the wifi and a
  /// domain from anywhere else — and which one works depends on where you are
  /// standing. Remembering both and offering them as taps is the difference
  /// between moving between them freely and retyping an IP address from memory
  /// every time you get home.
  List<String> _known = const [];
  bool _finding = false;

  @override
  void initState() {
    super.initState();
    // Signing out keeps the address, so someone coming back does not have to
    // remember which computer is theirs.
    _address.text = context.read<Session>().baseUrl ?? '';
    _loadKnown();
  }

  Future<void> _loadKnown() async {
    final list = await Session.knownAddresses();
    if (mounted) setState(() => _known = list);
  }

  /// Sweep the wifi for the computer, so nobody has to know its IP.
  Future<void> _find() async {
    setState(() {
      _finding = true;
      _error = null;
    });
    try {
      final found = await Discover.onThisWifi();
      if (!mounted) return;
      if (found.isEmpty) {
        setState(() => _error =
            'Nothing found on this wifi. Check the computer is awake and on '
            'the same network — or type the address if you know it.');
      } else {
        setState(() => _address.text = found.first.url);
      }
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<Session>()
          .signIn(_address.text, _email.text, _password.text);
      widget.onSignedIn?.call();
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BrandMasthead(brand: widget.brand),
                  const SizedBox(height: 6),
                  Text(
                    'Your records stay on your own computer.\n'
                    'This app just talks to it.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _address,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Address of your SafeNest',
                      hintText: 'safenest.example.com, or 192.168.0.170:8080',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                  ),

                  // The addresses this phone has used before, as taps. Home and
                  // away are usually two entries for one computer, and which
                  // works depends on where you are — so both are offered rather
                  // than the last one winning.
                  if (_known.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final a in _known)
                          ActionChip(
                            avatar: Icon(
                                a.contains('://192.168.') ||
                                        a.contains('://10.') ||
                                        a.contains('://172.')
                                    ? Icons.home_outlined
                                    : Icons.public,
                                size: 16),
                            label: Text(
                              a.replaceFirst(RegExp(r'^https?://'), ''),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            onPressed: () =>
                                setState(() => _address.text = a),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy || _finding ? null : _find,
                      icon: _finding
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_find, size: 19),
                      label: Text(_finding
                          ? 'Looking on this wifi...'
                          : 'Find my computer on this wifi'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: !_show,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _show ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 22),
                  BrandButton(
                    label: 'Sign in',
                    busy: _busy,
                    onPressed: _busy ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => const _AddressHelp(),
                    ),
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: const Text('What address do I use?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which address to type, for someone who has just installed both halves.
///
/// Two answers, and the difference matters: at home the phone can reach the
/// computer directly, and from anywhere it cannot unless a web address has been
/// set up on the computer first. Getting this wrong is the most likely reason a
/// new install fails, and "cannot reach your SafeNest" does not distinguish
/// between a wrong address, a sleeping computer and a tunnel that was never
/// created.
class _AddressHelp extends StatelessWidget {
  const _AddressHelp();

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        children: [
          Text('What address do I use?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 18),

          const _Step(
            n: 1,
            title: 'At home, on the same Wi-Fi',
            body: 'Use the computer’s own address on your network — it looks '
                'like 192.168.1.5:8080.\n\n'
                'Find it in SafeNest on that computer: Profile → This computer. '
                'The phone talks to it directly, which is the fastest way to '
                'back up photos and never leaves your house.',
          ),
          const _Step(
            n: 2,
            title: 'From anywhere — set a web address first',
            body: 'A home address only works at home. To reach your SafeNest '
                'from outside, open it on the computer and go to '
                'Profile → Reaching this app → Web address.\n\n'
                'It walks through all of it: buying a domain, adding it to '
                'Cloudflare, and connecting it. Every command it shows is built '
                'from what you type, so there is nothing to substitute.',
          ),
          const _Step(
            n: 3,
            title: 'Then use that domain here',
            body: 'Type it as safenest.yourdomain.com — no https:// needed, the '
                'app adds it.\n\n'
                'Home addresses may use plain http because a computer on your '
                'own network cannot have a certificate. Anything on the internet '
                'is forced to https, so your password is never sent in the '
                'clear.',
          ),

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Whichever you use, the computer running SafeNest has to be switched '
              'on — it is where everything of yours actually lives. If it sleeps, '
              'this app will say it cannot reach it, and that is the honest '
              'answer rather than showing you a stale copy.',
              style: small,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});
  final int n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text('$n',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(body,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      );
}
