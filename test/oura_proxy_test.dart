// Η εφαρμογή ανταλλάσσει κωδικό και ανανεώνει ΜΟΝΟ μέσω του μεσάζοντα στο Netlify (ο οποίος κρατά το secret).
// Η εφαρμογή δεν στέλνει ποτέ client_secret.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/oura/config.dart';

void main() {
  test('Το token πηγαίνει στον μεσάζοντα του ygeia-forma.netlify.app, με https', () {
    expect(ouraTokenProxy, 'https://ygeia-forma.netlify.app/api/oura/token');
    expect(ouraTokenEndpoint, ouraTokenProxy);
    expect(Uri.parse(ouraTokenEndpoint).scheme, 'https');
  });

  test('Ο κώδικας της εφαρμογής δεν περιέχει client_secret', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      expect(s.contains("'client_secret'"), isFalse, reason: f.path);
    }
  });

  test('Ο μεσάζων ελέγχει το ίδιο Client ID και τις ίδιες διευθύνσεις επιστροφής με την εφαρμογή', () {
    final fn = File('site/netlify/functions/oura-token.mjs').readAsStringSync();
    expect(fn.contains("const CLIENT_ID = '$ouraClientId';"), isTrue);
    expect(fn.contains("'$ouraRedirectHttps'"), isTrue);
    expect(fn.contains("'$ouraRedirectCustom'"), isTrue);
    expect(fn.contains('code_verifier (PKCE) required'), isTrue);
    expect(fn.contains("path: '/api/oura/token'"), isTrue);
  });
}
