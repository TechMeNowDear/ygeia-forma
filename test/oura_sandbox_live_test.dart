// Ζωντανός έλεγχος με το sandbox της Oura (συνθετικά δεδομένα, χωρίς δαχτυλίδι), με τον ΠΡΑΓΜΑΤΙΚΟ κώδικα
// ανάγνωσης (OuraLink + parseOura). Τρέχει μόνο στο check.yml (job «oura-sandbox»):
//   flutter test test/oura_sandbox_live_test.dart --dart-define=OURA_LIVE=1
// - Χωρίς δίκτυο ή αν η Oura δεν απαντά: γράφει «unreachable» και περνά (δεν μπλοκάρει).
// - Αν η απάντηση δεν διαβάζεται σωστά: αποτυγχάνει (αυτό θέλουμε να πιάνουμε).
// Το sandbox θέλει «οποιοδήποτε» Authorization (έλεγχος 2/11: χωρίς κεφαλίδα → 400 «Missing auth token»).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/oura/config.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_model.dart';

const _live = String.fromEnvironment('OURA_LIVE') == '1';

void main() {
  test('Sandbox Oura: ύπνος, βαθμολογίες, ετοιμότητα διαβάζονται με τον κώδικα της εφαρμογής', () async {
    if (!_live) {
      markTestSkipped('μόνο με --dart-define=OURA_LIVE=1');
      return;
    }
    HttpOverrides.global = null; // πραγματικό δίκτυο
    final now = DateTime.now();
    final vault = MemoryVault()
      ..data[vaultTokens] = OuraTokens(
        access: 'sandbox',
        refresh: 'sandbox',
        expiresAt: now.add(const Duration(days: 1)).millisecondsSinceEpoch,
      ).toJson();
    final link = OuraLink(vault: vault, clientId: 'sandbox', apiBase: ouraSandboxBase);
    final to = dayOf(now);
    final from = DateTime(to.year, to.month, to.day - 20);
    final OuraBatch b;
    try {
      b = await link.fetchNights(from, to);
    } on OuraError catch (e) {
      if (e.kind == OuraErrorKind.network || e.kind == OuraErrorKind.rateLimited) {
        File('oura_sandbox_result.txt').writeAsStringSync('unreachable ${e.kind.name}');
        markTestSkipped('Η Oura δεν απαντά τώρα (${e.kind.name})');
        return;
      }
      if (e.kind == OuraErrorKind.reconnect) {
        // 401: το sandbox άλλαξε και θέλει πραγματικό token. Δεν είναι σφάλμα ανάγνωσης· το γράφουμε.
        File('oura_sandbox_result.txt').writeAsStringSync('needs-auth HTTP ${e.status}');
        markTestSkipped('Το sandbox θέλει πλέον πραγματικό token (HTTP ${e.status}): μένουν τα αρχεία δοκιμής');
        return;
      }
      rethrow;
    }
    expect(b.skipped, 0, reason: 'εγγραφές χωρίς τα απαραίτητα πεδία');
    expect(b.nights, isNotEmpty);
    final mains = b.nights.where((n) => n.main != null).toList();
    expect(mains, isNotEmpty, reason: 'καμία long_sleep');
    for (final n in b.nights) {
      expect(!n.day.isBefore(from) && !n.day.isAfter(to), isTrue);
      final row = ouraRow(n);
      for (final v in row.values) {
        expect(v.isFinite, isTrue);
      }
    }
    expect(b.nights.any((n) => n.sleepScore != null), isTrue, reason: 'daily_sleep.score');
    expect(b.nights.any((n) => n.readiness != null), isTrue, reason: 'daily_readiness.score');
    File('oura_sandbox_result.txt').writeAsStringSync(
      'ok nights=${b.nights.length} main=${mains.length} naps=${b.nights.where((n) => n.naps.isNotEmpty).length}',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
