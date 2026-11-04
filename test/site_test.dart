// Ο ιστότοπος στο site/: τα δύο αντίγραφα του assetlinks.json ίδια (το drag and drop του Netlify παραλείπει τον
// κρυφό .well-known), το _redirects τα συνδέει με 200, και οι κεφαλίδες δίνουν JSON και στις δύο διευθύνσεις.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assetlinks.json: ίδιο στη ρίζα και στο .well-known, σωστό πακέτο', () {
    final root = File('site/public/assetlinks.json').readAsStringSync();
    expect(File('site/public/.well-known/assetlinks.json').readAsStringSync(), root);
    final j = jsonDecode(root) as List;
    expect(j.single['target']['package_name'], 'gr.ygeiaforma.ygeia_forma');
    expect((j.single['target']['sha256_cert_fingerprints'] as List).single, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
  });

  test('_redirects και _headers', () {
    expect(File('site/public/_redirects').readAsStringSync().trim(), '/.well-known/assetlinks.json  /assetlinks.json  200!');
    final h = File('site/public/_headers').readAsStringSync();
    for (final path in ['/.well-known/assetlinks.json', '/assetlinks.json']) {
      final block = h.split(RegExp(r'\n\s*\n')).firstWhere((b) => b.trim().split('\n').first.trim() == path);
      expect(block, contains('Content-Type: application/json'), reason: path);
      expect(block, contains('Cache-Control: public, max-age=300'), reason: path);
    }
  });
}
