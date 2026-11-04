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

  test('Ο μεσάζων ελέγχει το ίδιο Client ID και ΜΟΝΟ τη διεύθυνση επιστροφής που στέλνει η εφαρμογή (https)', () {
    final fn = File('site/netlify/functions/oura-token.mjs').readAsStringSync();
    expect(fn.contains("const CLIENT_ID = '$ouraClientId';"), isTrue);
    expect(ouraRedirectUri, ouraRedirectHttps, reason: 'η ανταλλαγή στέλνει πάντα το https (App Link)');
    expect(fn.contains("'$ouraRedirectHttps'"), isTrue);
    // Έλεγχος 2, C10: το custom scheme δεν γίνεται δεκτό στον μεσάζοντα (μόνο η σελίδα επιστροφής το χρησιμοποιεί).
    final redirects = RegExp(r'const REDIRECTS = new Set\(\[([^\]]*)\]\)').firstMatch(fn)!.group(1)!;
    expect(redirects.contains(ouraRedirectCustom), isFalse);
    expect(fn.contains('code_verifier (PKCE) required'), isTrue);
    expect(fn.contains("path: '/api/oura/token'"), isTrue);
    expect(fn.contains('const UPSTREAM_TIMEOUT_MS = 8000;'), isTrue, reason: 'κάτω από το όριο του Netlify');
  });

  // Έλεγχος 2, C10: ο μεσάζων τρέχει πραγματικά (node, με ψεύτικα Netlify.env και fetch), όχι μόνο έλεγχος κειμένου.
  // Στο GitHub Actions (ubuntu-latest) υπάρχει node· τοπικά χωρίς node ο έλεγχος παραλείπεται.
  final node = () {
    try {
      return Process.runSync('node', ['--version']).exitCode == 0;
    } catch (_) {
      return false;
    }
  }();
  test('Ο μεσάζων με node: PKCE, μόνο https, 8 s, 502/503, όριο αιτημάτων', () {
    final r = Process.runSync('node', ['test/node/oura_token_test.mjs', 'site/netlify/functions/oura-token.mjs']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout.toString(), contains('ALL PASSED'));
  }, skip: node ? false : 'χωρίς node σε αυτό το μηχάνημα');
}
