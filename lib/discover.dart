/// Find the computer on this wifi, so nobody has to know its IP address.
///
/// THE PROBLEM THIS SOLVES. Every customer runs their own copy, so the app has
/// to be told an address and there is no sensible default. At home that address
/// is something like 192.168.0.170:8080 — a number most people have never had
/// to find, that they must get from the computer, and that the router can
/// change without telling anybody. Asking somebody to type it is asking them to
/// do the hardest part of the setup first.
///
/// HOW. Every SafeNest answers /api/health with `service: finmate-api`, without
/// a token — it exists for exactly this kind of check. So the phone tries every
/// address on its own subnet and keeps the ones that answer with that marker.
///
/// It is a scan of the local network, which deserves saying plainly: it is the
/// phone's OWN subnet, only port 8080, only /api/health, and only when somebody
/// presses the button. Nothing is sent to any of them beyond the request.
///
/// mDNS would be tidier and is deliberately not used: it needs the server to
/// advertise itself, which means a new dependency on every customer's machine
/// and a service that can silently stop, and iOS additionally requires a
/// special entitlement for local network discovery that Apple grants sparingly.
/// A health check the app already has is less machinery and cannot drift.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

class Found {
  Found(this.url, this.name);
  final String url;

  /// The app's own name, from /api/branding — so a household with two of
  /// these can tell them apart rather than choosing between two IP addresses.
  final String name;
}

class Discover {
  /// Addresses on this wifi that answer as a SafeNest.
  ///
  /// Returns as soon as the sweep finishes; a /24 at 60 in flight takes a
  /// couple of seconds on a normal home network.
  static Future<List<Found>> onThisWifi({
    Duration timeout = const Duration(milliseconds: 900),
    int port = 8080,
  }) async {
    final base = await _subnetBase();
    if (base == null) return const [];

    final found = <Found>[];
    // In batches rather than 254 at once: a phone will happily open that many
    // sockets and then drop most of them, which produces false negatives that
    // look like the computer being off.
    const batch = 60;
    for (var start = 1; start < 255; start += batch) {
      final end = (start + batch).clamp(1, 255);
      final probes = <Future<Found?>>[];
      for (var i = start; i < end; i++) {
        probes.add(_probe('$base$i', port, timeout));
      }
      for (final r in await Future.wait(probes)) {
        if (r != null) found.add(r);
      }
      // Stop at the first hit. Households have one computer running this, and
      // finishing the sweep to be thorough would make it slower for everybody
      // to no purpose.
      if (found.isNotEmpty) break;
    }
    return found;
  }

  static Future<Found?> _probe(String host, int port, Duration timeout) async {
    final url = 'http://$host:$port';
    try {
      final r = await http
          .get(Uri.parse('$url/api/health'))
          .timeout(timeout);
      if (r.statusCode != 200) return null;
      // The MARKER, not merely a 200. Anything on a home network might answer
      // on 8080 — a router page, a printer, somebody's dev server — and
      // offering one of those as "your SafeNest" would send a password to it.
      if (!r.body.contains('finmate-api')) return null;

      var name = 'SafeNest';
      try {
        final b = await http
            .get(Uri.parse('$url/api/branding'))
            .timeout(timeout);
        final m = RegExp(r'"app_name"\s*:\s*"([^"]+)"').firstMatch(b.body);
        if (m != null) name = m.group(1)!;
      } catch (_) {
        // A name is a nicety; the address is the answer.
      }
      return Found(url, name);
    } catch (_) {
      return null;   // nothing there, which is the usual case 253 times over
    }
  }

  /// "192.168.0." for this phone, or null when it is not on wifi.
  static Future<String?> _subnetBase() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in interfaces) {
        for (final a in i.addresses) {
          final ip = a.address;
          // Private ranges only. Scanning whatever a mobile network handed out
          // would be probing somebody else's infrastructure.
          final private = ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
          if (!private) continue;
          final cut = ip.lastIndexOf('.');
          if (cut > 0) return ip.substring(0, cut + 1);
        }
      }
    } catch (_) {
      // Some platforms refuse to enumerate interfaces. Typing the address by
      // hand still works, which is why this is a shortcut and not the only way.
    }
    return null;
  }
}
