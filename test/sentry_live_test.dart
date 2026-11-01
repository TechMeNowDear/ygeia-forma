// Πραγματική αποστολή ενός δοκιμαστικού σφάλματος στο Sentry, με τον ίδιο κώδικα που έχει η εφαρμογή.
// Τρέχει μόνο όταν το ζητήσουμε (commit με «[sentry-test]» ή χειροκίνητο χτίσιμο με την επιλογή):
//   flutter test test/sentry_live_test.dart --dart-define=SENTRY_LIVE=1 --dart-define=APP_VERSION=0.1.N
// Πρώτα «χωρίς ίντερνετ» (μένει στην ουρά), μετά με ίντερνετ (φεύγει).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/error_report.dart';

const _live = bool.fromEnvironment('SENTRY_LIVE');
const _version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

void main() {
  test('δοκιμαστικό σφάλμα φτάνει στο Sentry', () async {
    HttpOverrides.global = null; // πραγματικό δίκτυο
    final dir = Directory.systemTemp.createTempSync('errq-live');
    var online = false;
    final statuses = <int>[];
    final r = ErrorReporter(
      dir: dir,
      release: 'ygeia-forma@$_version',
      environment: 'test',
      device: const {'model': 'GitHub Actions', 'android': '-'},
      post: (body) async {
        if (!online) throw const SocketException('δοκιμή χωρίς ίντερνετ');
        final s = await httpPost(body);
        statuses.add(s);
        return s;
      },
    );
    r.setBase('Δοκιμή');
    try {
      throw StateError('Δοκιμαστικό σφάλμα $_version — όλα καλά, μπορεί να κλείσει');
    } catch (e, st) {
      await r.report(e, st, extra: {'test': true});
    }
    expect(await r.pending(), 1, reason: 'χωρίς ίντερνετ πρέπει να μένει στην ουρά');
    online = true;
    await r.flush();
    expect(statuses, [200], reason: 'το Sentry πρέπει να απαντήσει 200');
    expect(await r.pending(), 0);
    dir.deleteSync(recursive: true);
  }, skip: !_live);
}
