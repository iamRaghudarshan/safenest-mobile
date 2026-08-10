/// Home and away are two addresses for one computer, and both must work.
///
/// A LAN address must be accepted over http — insisting on https would make the
/// app unusable at home for anyone without a domain, which is everybody on the
/// day they install it. A PUBLIC address must not be, or the password goes over
/// the internet in the clear.
///
/// That single distinction is the whole of normaliseAddress, and it is the sort
/// of rule that is quietly relaxed by a later edit.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/session.dart';

void main() {
  group('what a person might type', () {
    test('a bare domain becomes https', () {
      expect(Session.normaliseAddress('safenest.example.com'),
          'https://safenest.example.com');
    });

    test('a home IP with a port stays http', () {
      // The case this whole feature exists for.
      expect(Session.normaliseAddress('192.168.0.170:8080'),
          'http://192.168.0.170:8080');
    });

    test('every private range is treated as home', () {
      for (final ip in ['192.168.1.5:8080', '10.0.0.4:8080',
                        '172.16.3.9:8080', '172.31.255.1:8080',
                        'localhost:8080', '127.0.0.1:8080']) {
        expect(Session.normaliseAddress(ip), startsWith('http://'),
            reason: '$ip is a private address and must not be forced to https');
      }
    });

    test('a PUBLIC address is forced to https', () {
      // 172.32 is outside the private range - one digit from 172.31, and the
      // reason the check is a range rather than a "starts with 172".
      expect(Session.normaliseAddress('172.32.0.1:8080'), startsWith('https://'));
      expect(Session.normaliseAddress('8.8.8.8'), startsWith('https://'));
      expect(Session.normaliseAddress('example.com'), startsWith('https://'));
    });

    test('trailing slashes and capitals are tidied', () {
      expect(Session.normaliseAddress('https://SafeNest.Example.com/'),
          'https://safenest.example.com');
      expect(Session.normaliseAddress('  safenest.example.com//  '),
          'https://safenest.example.com');
    });

    test('an explicit scheme is respected', () {
      // Somebody who typed http:// for a public host has said what they meant.
      expect(Session.normaliseAddress('http://192.168.0.170:8080'),
          'http://192.168.0.170:8080');
    });
  });
}
