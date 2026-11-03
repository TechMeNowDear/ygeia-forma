// Oura: ανάγνωση των απαντήσεων (με τα αρχεία δοκιμής από το OpenAPI 1.43 και το sandbox), φάσεις,
// κύρια νύχτα και υπνάκοι, αλλαγή ώρας, σελίδες, πεδία που λείπουν, σφάλματα HTTP, ανανέωση tokens, PKCE.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/config.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
import 'package:ygeia_forma/oura/sha256.dart';
import 'package:ygeia_forma/sources.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/oura/$name').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> data(String name) =>
    [for (final x in fixture(name)['data'] as List) Map<String, dynamic>.from(x as Map)];

OuraBatch fixtureBatch() => parseOura(
      sleep: [...data('sleep_page1.json'), ...data('sleep_page2.json')],
      dailySleep: data('daily_sleep.json'),
      readiness: data('daily_readiness.json'),
    );

OuraNight night(OuraBatch b, String day) => b.nights.firstWhere((n) => dateKey(n.day) == day);

/// HTTP ψεύτικο: απαντήσεις στη σειρά, και κρατά τι στάλθηκε.
class FakeHttp {
  FakeHttp(this.handler);
  final OuraResponse Function(String method, Uri url, Map<String, String> headers, String? form) handler;
  final calls = <(String, Uri, Map<String, String>, String?)>[];

  Future<OuraResponse> send(String method, Uri url, {Map<String, String> headers = const {}, String? form}) async {
    calls.add((method, url, headers, form));
    return handler(method, url, headers, form);
  }
}

void main() {
  // ---------------------------------------------------------------------------
  group('SHA-256 και PKCE', () {
    test('Γνωστά αποτυπώματα (FIPS 180-4)', () {
      String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      expect(hex(sha256(utf8.encode(''))), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(hex(sha256(utf8.encode('abc'))), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
        hex(sha256(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      // Μήκος ακριβώς στο όριο του μπλοκ (55, 56, 64 bytes).
      expect(hex(sha256(List.filled(64, 0x61))), 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb');
    });

    test('RFC 7636 παράρτημα B', () {
      expect(pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('Το παράδειγμα της τεκμηρίωσης της Oura', () {
      expect(pkceChallenge('QUW2bsoMYITWSSPUgCDEc4CXCBfcVyu8TkujreHe8CXP4K4d4463gRztuxfo96YP'),
          '43Kb1gELSIjkvwzrPtAg0Lz2HqCG3BtS_SUMAQhjv7c');
    });

    test('Τυχαίος verifier: 43–128 επιτρεπτοί χαρακτήρες', () {
      final v = randomVerifier();
      expect(v.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
    });

    test('Σελίδα σύνδεσης: code, PKCE S256, state, μόνο daily', () {
      final p = OuraPending(state: 'st', verifier: 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk', created: DateTime(2026, 11, 6));
      final u = ouraAuthorizeUrl(clientId: 'CID', p: p);
      expect(u.toString(), startsWith('https://cloud.ouraring.com/oauth/authorize?'));
      expect(u.queryParameters['response_type'], 'code');
      expect(u.queryParameters['client_id'], 'CID');
      expect(u.queryParameters['redirect_uri'], 'https://ygeia-forma.netlify.app/oura/callback');
      expect(ouraRedirectUri, ouraRedirectHttps);
      expect(u.queryParameters['state'], 'st');
      expect(u.queryParameters['code_challenge_method'], 'S256');
      expect(u.queryParameters['code_challenge'], 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
      expect(u.queryParameters['scope'], 'daily');
      expect(u.queryParameters.containsKey('client_secret'), isFalse);
    });

    test('Επιστροφή: code/state/error από το query', () {
      final cb = parseCallback('ygeiaforma://oura-callback?code=C1&state=S1&scope=daily');
      expect(cb!.code, 'C1');
      expect(cb.state, 'S1');
      expect(parseCallback('ygeiaforma://oura-callback?error=access_denied&state=S1')!.error, 'access_denied');
      expect(parseCallback('https://example.com/?code=x'), isNull);
      expect(parseCallback('ygeiaforma://other?code=x'), isNull);
    });

    test('Επιστροφή: δεκτές ΜΟΝΟ οι δύο ακριβείς μορφές (App Link https και custom scheme)', () {
      final https = parseCallback('https://ygeia-forma.netlify.app/oura/callback?code=C2&state=S2');
      expect(https!.code, 'C2');
      expect(https.state, 'S2');
      expect(parseCallback('https://ygeia-forma.netlify.app/oura/callback?error=access_denied&state=S2')!.error, 'access_denied');
      expect(parseCallback('ygeiaforma://oura-callback/?code=C3&state=S3')!.code, 'C3');
      for (final bad in [
        'https://ygeia-forma.netlify.app/oura/callback2?code=x&state=s',
        'https://ygeia-forma.netlify.app/oura?code=x&state=s',
        'https://ygeia-forma.netlify.app/oura/callback/x?code=x&state=s',
        'https://evil-ygeia-forma.netlify.app/oura/callback?code=x&state=s',
        'https://ygeia-forma.netlify.app.evil.com/oura/callback?code=x&state=s',
        'https://ygeia-forma.netlify.app:8443/oura/callback?code=x&state=s',
        'https://user@ygeia-forma.netlify.app/oura/callback?code=x&state=s',
        'http://ygeia-forma.netlify.app/oura/callback?code=x&state=s',
        'ygeiaforma://oura-callback/extra?code=x&state=s',
        'ygeiaforma://oura-callback:1/?code=x&state=s',
        'intent://oura-callback?code=x',
      ]) {
        expect(parseCallback(bad), isNull, reason: bad);
      }
    });

    test('Καμία μυστική τιμή στον κώδικα', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final s = f.readAsStringSync();
        expect(RegExp(r"client_secret\s*[:=]\s*'[^']+'").hasMatch(s), isFalse, reason: f.path);
      }
      expect(ouraClientId.isEmpty || RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(ouraClientId), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('Ανάγνωση /sleep, /daily_sleep, /daily_readiness', () {
    test('Κανονική νύχτα: όλα τα πεδία, ώρα κινητού (Αθήνα)', () {
      final b = fixtureBatch();
      final n = night(b, '2026-10-23');
      final m = n.main!;
      expect(m.id, 's-1023');
      expect(m.totalMinutes, 420);
      expect(m.deep, 4200);
      expect(m.lowestHr, 52);
      expect(m.avgHr, 57.25);
      expect(m.avgHrv, 41);
      expect(m.avgBreath, 14.125);
      // 23:48:10 +03:00 = 20:48:10 UTC → στο κινητό (Europe/Athens στους ελέγχους) 23:48.
      expect(m.start.toUtc(), DateTime.utc(2026, 10, 22, 20, 48, 10));
      expect(m.onset!.toUtc(), DateTime.utc(2026, 10, 22, 21, 3, 10));
      expect(n.sleepScore, 82);
      expect(n.readiness, 78);
      expect(n.tempDeviation, 0.12);
    });

    test('Υπνάκος (sleep) την ίδια μέρα: χωριστά, ΔΕΝ προστίθεται στη νύχτα', () {
      final n = night(fixtureBatch(), '2026-10-23');
      expect(n.naps.length, 1);
      expect(n.napMinutes, 30);
      expect(n.main!.totalMinutes, 420);
      final row = ouraRow(n);
      expect(row[ouraKeys[K.sleepMin]], 420);
      expect(row[ouraKeys[K.napMin]], 30);
    });

    test('rest (λάθος ανίχνευση) αγνοείται· δύο long_sleep: κύρια η μεγαλύτερη, η άλλη χωριστά', () {
      final n = night(fixtureBatch(), '2026-10-24');
      expect(n.main!.id, 's-1024-b');
      expect(n.others.single.id, 's-1024-a');
      expect(n.naps, isEmpty);
      // Η διάρκεια της νύχτας είναι ΜΟΝΟ της κύριας περιόδου (όχι άθροισμα).
      expect(ouraRow(n)[ouraKeys[K.sleepMin]], 280);
      // Φάσεις από το app_sleep_phase_5_min όταν το sleep_phase_5_min είναι null.
      expect(n.main!.phases, '42222111223333222224');
    });

    test('Αλλαγή ώρας (25/10): +03:00 → +02:00, σωστή διάρκεια και ώρες', () {
      final n = night(fixtureBatch(), '2026-10-25');
      final m = n.main!;
      // 00:40 +03 ως 08:10 +02 = 8 ώρες 30 λεπτά πραγματικός χρόνος.
      expect(m.end.difference(m.start), const Duration(hours: 8, minutes: 30));
      expect(m.end.toUtc(), DateTime.utc(2026, 10, 25, 6, 10));
      if (DateTime(2026, 10, 25, 12).timeZoneOffset == const Duration(hours: 2)) {
        // Στην ώρα Αθήνας (CI): ξύπνημα 08:10 τοπική.
        expect(hm(m.end), '08:10');
        expect(minutesFromSix(m.end), 14 * 60 + 10);
      }
      // Οι φάσεις καλύπτουν τον πραγματικό χρόνο και δεν περνούν το τέλος.
      final st = m.stages;
      expect(st.first.start, m.start);
      expect(st.every((s) => !s.end.isAfter(m.end)), isTrue);
    });

    test('Πεδία που λείπουν (null): κενά, ποτέ 0', () {
      final n = night(fixtureBatch(), '2026-10-26');
      final m = n.main!;
      expect(m.totalMinutes, 360);
      expect(m.deep, isNull);
      expect(m.lowestHr, isNull);
      expect(m.onset, isNull);
      final row = ouraRow(n);
      expect(row[ouraKeys[K.sleepMin]], 360);
      for (final k in [K.deepPct, K.remPct, K.awakeMin, K.sleepHr, K.lowHr, K.hrv, K.breath, K.bedtime, K.sleepScore, K.energy, K.skinTemp]) {
        expect(row.containsKey(ouraKeys[k]), isFalse, reason: k);
      }
      expect(row[ouraKeys[K.wake]], isNotNull);
    });

    test('late_nap και χαλασμένη εγγραφή: ο υπνάκος χωριστά, η χαλασμένη παραλείπεται και μετριέται', () {
      final b = fixtureBatch();
      expect(b.skipped, 1);
      final n = night(b, '2026-10-27');
      expect(n.main, isNull);
      expect(n.naps.single.type, 'late_nap');
      expect(ouraRow(n).containsKey(ouraKeys[K.sleepMin]), isFalse);
    });

    test('Θερμοκρασία: από daily_readiness· αν λείπει, από το readiness της νύχτας', () {
      final b = fixtureBatch();
      expect(night(b, '2026-10-24').tempDeviation, -0.21);
      expect(night(b, '2026-10-25').tempDeviation, isNull);
      final withEmbedded = parseOura(
        sleep: [data('sleep_page1.json').first],
        dailySleep: const [],
        readiness: const [],
      );
      expect(withEmbedded.nights.single.tempDeviation, 0.12);
    });

    test('Ποσοστά φάσεων μόνο όταν υπάρχουν και οι τέσσερις', () {
      final row = ouraRow(night(fixtureBatch(), '2026-10-23'));
      expect(row[ouraKeys[K.deepPct]], closeTo(100 * 4200 / (4200 + 14400 + 6600 + 2610), 1e-9));
      expect(row[ouraKeys[K.awakeMin]], 43.5);
    });

    test('Σελίδα με λάθος μορφή → FormatException', () {
      expect(() => parseOuraPage({'nope': 1}), throwsFormatException);
      expect(() => parseOuraPage([1, 2]), throwsFormatException);
      final p = parseOuraPage(fixture('sleep_page1.json'));
      expect(p.next, 'page-2');
      expect(parseOuraPage(fixture('sleep_page2.json')).next, isNull);
    });

    test('Αποθήκευση και ανάγνωση των νυχτών: ίδιες τιμές', () {
      final b = fixtureBatch();
      final back = decodeOuraNights(encodeOuraNights(b.nights));
      expect(back.length, b.nights.length);
      for (var i = 0; i < back.length; i++) {
        expect(ouraRow(back[i]), ouraRow(b.nights[i]), reason: dateKey(back[i].day));
        expect(back[i].naps.length, b.nights[i].naps.length);
      }
      expect(decodeOuraNights('χαλασμένο'), isEmpty);
    });

    test('Συγχώνευση νυχτών: το διάστημα αντικαθίσταται όλο, οι παλιές μέρες έξω μένουν', () {
      final b = fixtureBatch();
      final merged = mergeOuraNights(b.nights, [night(b, '2026-10-25')],
          from: DateTime(2026, 10, 24), to: DateTime(2026, 10, 25), today: DateTime(2026, 10, 27));
      expect(merged.map((n) => dateKey(n.day)), ['2026-10-23', '2026-10-25', '2026-10-26', '2026-10-27']);
    });
  });

  // ---------------------------------------------------------------------------
  // S-C: χωρίς long_sleep, η νύχτα = η μεγαλύτερη «sleep» στο νυχτερινό παράθυρο· ποτέ άθροισμα.
  group('Σύντομη νύχτα (μόνο «sleep»)', () {
    final d = DateTime(2026, 11, 3);
    var seq = 0;
    Map<String, dynamic> rec(String type, DateTime start, DateTime end, {DateTime? day}) {
      final secs = end.difference(start).inSeconds;
      final k = day ?? d;
      return {
        'id': 'p${seq++}',
        'day': dateKey(k),
        'type': type,
        'bedtime_start': start.toUtc().toIso8601String(),
        'bedtime_end': end.toUtc().toIso8601String(),
        'time_in_bed': secs,
        'total_sleep_duration': secs - 300,
      };
    }

    OuraNight only(List<Map<String, dynamic>> sleep) =>
        parseOura(sleep: sleep, dailySleep: const [], readiness: const []).nights.single;
    DateTime at(int day, int h, int m) => DateTime(2026, 11, day, h, m);

    test('Μόνο «sleep» 01:10–03:40: είναι η νύχτα (σύντομη), όχι υπνάκος', () {
      final n = only([rec('sleep', at(3, 1, 10), at(3, 3, 40))]);
      expect(n.main, isNotNull);
      expect(n.shortNight, isTrue);
      expect(n.naps, isEmpty);
      final row = ouraRow(n);
      expect(row[ouraKeys[K.sleepMin]], 145);
      expect(row.containsKey(ouraKeys[K.napMin]), isFalse, reason: 'δεν μετριέται και ως υπνάκος');
      expect(shortNightLabel, 'Σύντομη νύχτα · κάτω από 3 ώρες');
    });

    test('long_sleep + απογευματινό «sleep»: κύρια η long_sleep, το «sleep» υπνάκος', () {
      final n = only([
        rec('long_sleep', at(2, 23, 30), at(3, 7, 0)),
        rec('sleep', at(3, 15, 0), at(3, 15, 40)),
      ]);
      expect(n.main!.type, 'long_sleep');
      expect(n.shortNight, isFalse);
      expect(n.pieces, isEmpty);
      expect(n.naps.single.type, 'sleep');
      expect(ouraRow(n)[ouraKeys[K.napMin]], 35);
    });

    test('Μόνο απογευματινό «sleep»: καμία νύχτα, λόγος «Μόνο υπνάκος από το δαχτυλίδι»', () {
      final n = only([rec('sleep', at(3, 15, 0), at(3, 16, 0))]);
      expect(n.main, isNull);
      expect(n.onlyNap, isTrue);
      expect(ouraRow(n).containsKey(ouraKeys[K.sleepMin]), isFalse);
      final plan = SourcePlan([SourceEra(Source.oura, at(1, 0, 0))]);
      final r = emptyNightReason(plan: plan, day: d, now: at(3, 18, 0), night: n, hasTokens: true, synced: at(3, 17, 0));
      expect(r, EmptyNight.onlyNap);
      expect(emptyNightText(r!), 'Μόνο υπνάκος από το δαχτυλίδι');
    });

    test('Δύο «sleep» 23:00–01:30 και 03:00–05:45: κύρια η μεγαλύτερη, η άλλη «άλλο κομμάτι», ποτέ άθροισμα', () {
      final n = only([
        rec('sleep', at(2, 23, 0), at(3, 1, 30)),
        rec('sleep', at(3, 3, 0), at(3, 5, 45)),
      ]);
      expect(hm(n.main!.start), '03:00');
      expect(n.pieces.length, 1);
      expect(hm(n.pieces.single.start), '23:00');
      expect(n.naps, isEmpty);
      final row = ouraRow(n);
      expect(row[ouraKeys[K.sleepMin]], 160, reason: 'μόνο η κύρια (165′ − 5′)');
      expect(row.containsKey(ouraKeys[K.napMin]), isFalse);
      // Αποθήκευση και ανάγνωση: το κομμάτι μένει χωριστά.
      final back = decodeOuraNights(encodeOuraNights([n])).single;
      expect(back.pieces.length, 1);
      expect(ouraRow(back), row);
    });

    test('Βραδινό «sleep» 19:00–21:00 (χωρίς νύχτα): μένει υπνάκος, ποτέ νύχτα', () {
      final n = only([rec('sleep', at(2, 19, 0), at(2, 21, 0))]);
      expect(n.main, isNull);
      expect(n.naps.single.type, 'sleep');
      expect(n.onlyNap, isTrue);
      expect(ouraRow(n).containsKey(ouraKeys[K.sleepMin]), isFalse);
      expect(ouraRow(n)[ouraKeys[K.napMin]], 115);
    });

    test('Σύντομη νύχτα που τελείωσε πριν από τα μεσάνυχτα (21:30–23:50): «Μόνο υπνάκος», με τις ώρες του', () {
      final n = only([rec('sleep', at(2, 21, 30), at(2, 23, 50))]);
      expect(n.main, isNull);
      expect(n.onlyNap, isTrue);
      expect(napTimes(n), '21:30–23:50 · 2 ώρες 15 λεπτά');
      expect(napTimes(null), '');
    });

    test('Παράθυρο: μόνο ό,τι επικαλύπτει 00:00–06:00 της μέρας', () {
      OuraSleep s(DateTime a, DateTime b) => OuraSleep.fromJson(rec('sleep', a, b))!;
      expect(inNightWindow(s(at(2, 22, 0), at(3, 0, 30)), d), isTrue);
      expect(inNightWindow(s(at(3, 5, 30), at(3, 8, 0)), d), isTrue);
      expect(inNightWindow(s(at(3, 6, 0), at(3, 8, 0)), d), isFalse);
      expect(inNightWindow(s(at(2, 20, 0), at(2, 23, 59)), d), isFalse);
      expect(inNightWindow(s(at(3, 14, 0), at(3, 15, 0)), d), isFalse);
    });

    test('late_nap στις 19:00: ποτέ νύχτα', () {
      final n = only([rec('late_nap', at(2, 19, 0), at(2, 19, 50))]);
      expect(n.main, isNull);
      expect(n.naps.single.type, 'late_nap');
      expect(ouraRow(n).containsKey(ouraKeys[K.sleepMin]), isFalse);
    });
  });

  group('Φάσεις ανά 5 λεπτά', () {
    test('Ενώνονται οι ίδιες, σωστές ώρες, άγνωστος χαρακτήρας = κενό', () {
      final s = DateTime(2026, 11, 6, 23);
      final st = ouraStages('1122x34', s, s.add(const Duration(hours: 2)));
      expect(st.map((x) => x.name), ['DEEP', 'LIGHT', 'REM', 'AWAKE']);
      expect(st[0].minutes, 10);
      expect(st[1].minutes, 10);
      expect(st[2].start, s.add(const Duration(minutes: 25)));
      expect(st[3].end, s.add(const Duration(minutes: 35)));
    });

    test('Δεν περνούν το τέλος της περιόδου', () {
      final s = DateTime(2026, 11, 6, 23);
      final st = ouraStages('2222', s, s.add(const Duration(minutes: 12)));
      expect(st.single.end, s.add(const Duration(minutes: 12)));
    });

    test('Κενό ή null: καμία φάση', () {
      expect(ouraStages(null, DateTime(2026), DateTime(2026, 1, 2)), isEmpty);
      expect(ouraStages('', DateTime(2026), DateTime(2026, 1, 2)), isEmpty);
    });
  });

  group('Sandbox της Oura (αρχεία 2/11/2026)', () {
    test('Διαβάζονται όλα με τον πραγματικό κώδικα', () {
      final b = parseOura(
        sleep: data('sandbox_sleep_2026-11-02.json'),
        dailySleep: data('sandbox_daily_sleep_2026-11-02.json'),
        readiness: data('sandbox_daily_readiness_2026-11-02.json'),
      );
      expect(b.skipped, 0);
      expect(b.nights.length, 32);
      expect(b.nights.where((n) => n.main != null).length, 16);
      expect(b.nights.where((n) => n.naps.isNotEmpty).length, 16);
      for (final n in b.nights) {
        expect(n.sleepScore, isNotNull);
        expect(n.readiness, isNotNull);
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('HTTP: σελίδες, 401, 403, 429, ανανέωση', () {
    final now = DateTime(2026, 11, 7, 9);
    OuraTokens tokens({String a = 'A0', String r = 'R0', Duration life = const Duration(days: 1)}) =>
        OuraTokens(access: a, refresh: r, expiresAt: now.add(life).millisecondsSinceEpoch);

    OuraLink link(FakeHttp http, MemoryVault v) =>
        OuraLink(vault: v, send: http.send, clock: () => now, clientId: 'CID', tokenEndpoint: 'https://api.ouraring.com/oauth/token');

    test('Σελίδες: next_token μέχρι null, όλα μαζί', () async {
      final http = FakeHttp((m, u, h, f) {
        final p = u.queryParameters['next_token'] == null ? 'sleep_page1.json' : 'sleep_page2.json';
        return OuraResponse(200, jsonEncode(fixture(p)));
      });
      final v = MemoryVault()..data[vaultTokens] = tokens().toJson();
      final all = await link(http, v).fetchAll('sleep', DateTime(2026, 10, 23), DateTime(2026, 10, 27));
      expect(all.length, 9);
      expect(http.calls.length, 2);
      expect(http.calls.first.$2.path, '/v2/usercollection/sleep');
      expect(http.calls.first.$2.queryParameters['start_date'], '2026-10-23');
      // Το end_date της Oura δεν περιλαμβάνει τη μέρα του: ζητάμε ως την επόμενη.
      expect(http.calls.first.$2.queryParameters['end_date'], '2026-10-28');
      expect(http.calls.last.$2.queryParameters['next_token'], 'page-2');
      expect(http.calls.first.$3['Authorization'], 'Bearer A0');
    });

    test('Ίδιο next_token ξανά: σταματά (όχι ατελείωτος βρόχος)', () async {
      final http = FakeHttp((m, u, h, f) => OuraResponse(200, jsonEncode({'data': [], 'next_token': 'same'})));
      final v = MemoryVault()..data[vaultTokens] = tokens().toJson();
      expect(
        () => link(http, v).fetchAll('sleep', DateTime(2026, 11, 1), DateTime(2026, 11, 7)),
        throwsA(isA<OuraError>().having((e) => e.kind, 'kind', OuraErrorKind.format)),
      );
    });

    test('403 → συνδρομή· 429 → αργότερα με Retry-After· 500 → δίκτυο', () async {
      for (final (status, kind) in [
        (403, OuraErrorKind.subscription),
        (429, OuraErrorKind.rateLimited),
        (503, OuraErrorKind.network),
      ]) {
        final http = FakeHttp((m, u, h, f) => OuraResponse(status, '{}', retryAfter: const Duration(seconds: 90)));
        final v = MemoryVault()..data[vaultTokens] = tokens().toJson();
        try {
          await link(http, v).fetchAll('sleep', DateTime(2026, 11, 1), DateTime(2026, 11, 7));
          fail('έπρεπε να αποτύχει');
        } on OuraError catch (e) {
          expect(e.kind, kind);
          if (status == 429) expect(e.retryAfter, const Duration(seconds: 90));
          expect(e.toString().contains('A0'), isFalse, reason: 'ποτέ token στο σφάλμα');
        }
      }
    });

    test('401 → μία ανανέωση, το ΝΕΟ refresh token αποθηκεύεται ΠΡΙΝ χρησιμοποιηθεί η νέα πρόσβαση', () async {
      final v = MemoryVault()..data[vaultTokens] = tokens().toJson();
      final order = <String>[];
      final http = FakeHttp((m, u, h, f) {
        if (m == 'POST') {
          order.add('refresh');
          expect(f, contains('grant_type=refresh_token'));
          expect(f, contains('refresh_token=R0'));
          expect(f, contains('client_id=CID'));
          expect(f, isNot(contains('client_secret')));
          return OuraResponse(200, jsonEncode({'access_token': 'A1', 'refresh_token': 'R1', 'expires_in': 86400}));
        }
        if (h['Authorization'] == 'Bearer A0') return const OuraResponse(401, '{}');
        // Τη στιγμή που χρησιμοποιείται το A1, το R1 είναι ήδη αποθηκευμένο.
        order.add('use A1 (saved=${OuraTokens.fromJson(v.data[vaultTokens])?.refresh})');
        return OuraResponse(200, jsonEncode({'data': [], 'next_token': null}));
      });
      await link(http, v).fetchAll('sleep', DateTime(2026, 11, 1), DateTime(2026, 11, 7));
      expect(order, ['refresh', 'use A1 (saved=R1)']);
      expect(OuraTokens.fromJson(v.data[vaultTokens])!.refresh, 'R1');
    });

    test('401 και μετά την ανανέωση → «Χρειάζεται νέα σύνδεση»', () async {
      final v = MemoryVault()..data[vaultTokens] = tokens().toJson();
      final http = FakeHttp((m, u, h, f) => m == 'POST'
          ? OuraResponse(200, jsonEncode({'access_token': 'A1', 'refresh_token': 'R1', 'expires_in': 86400}))
          : const OuraResponse(401, '{}'));
      expect(
        () => link(http, v).fetchAll('sleep', DateTime(2026, 11, 1), DateTime(2026, 11, 7)),
        throwsA(isA<OuraError>().having((e) => e.kind, 'kind', OuraErrorKind.reconnect)),
      );
    });

    test('Refresh token που δεν ισχύει (400) → νέα σύνδεση· τα παλιά tokens ΚΡΑΤΙΟΥΝΤΑΙ (σβήνονται μόνο με αποσύνδεση ή νέα σύνδεση)', () async {
      final old = tokens(life: Duration.zero).toJson();
      final v = MemoryVault()..data[vaultTokens] = old;
      final http = FakeHttp((m, u, h, f) => const OuraResponse(400, '{"error":"invalid_grant"}'));
      await expectLater(
        link(http, v).fetchAll('sleep', DateTime(2026, 11, 1), DateTime(2026, 11, 7)),
        throwsA(isA<OuraError>().having((e) => e.kind, 'kind', OuraErrorKind.reconnect)),
      );
      expect(v.data[vaultTokens], old);
    });

    test('Ανανέωση σε εξέλιξη την ώρα της αποσύνδεσης: τα νέα tokens ΔΕΝ αποθηκεύονται, ανακαλούνται', () async {
      final v = MemoryVault()..data[vaultTokens] = tokens().toJson();
      final gate = Completer<OuraResponse>();
      final revoked = <String>[];
      final http = FakeHttp((m, u, h, f) {
        if (u.path.endsWith('/revoke')) {
          revoked.add(u.queryParameters['access_token'] ?? '');
          return const OuraResponse(200, '{}');
        }
        throw StateError('μη αναμενόμενο');
      });
      final l = OuraLink(
        vault: v,
        send: (m, u, {headers = const {}, form}) => m == 'POST' && !u.path.endsWith('/revoke') ? gate.future : http.send(m, u, headers: headers, form: form),
        clock: () => now,
        clientId: 'CID',
        tokenEndpoint: 'https://api.ouraring.com/oauth/token',
      );
      final refresh = l.refresh();
      await Future<void>.delayed(Duration.zero);
      final disc = l.disconnect();
      gate.complete(OuraResponse(200, jsonEncode({'access_token': 'A1', 'refresh_token': 'R1', 'expires_in': 86400})));
      await disc;
      await refresh.catchError((_) => null);
      expect(v.data, isEmpty, reason: 'κανένα token μετά την αποσύνδεση');
      expect(await l.hasTokens, isFalse);
      expect(revoked, ['A1'], reason: 'ανακαλείται η νέα πρόσβαση');
    });

    test('Η αποθήκευση δεν απαντά (προσωρινά): σφάλμα δικτύου, τα tokens ΔΕΝ θεωρούνται χαμένα', () async {
      final v = MemoryVault()
        ..data[vaultTokens] = tokens().toJson()
        ..failLoads = true;
      final http = FakeHttp((m, u, h, f) => OuraResponse(200, jsonEncode({'data': [], 'next_token': null})));
      final l = link(http, v);
      await expectLater(l.hasTokens, throwsA(isA<OuraError>().having((e) => e.kind, 'kind', OuraErrorKind.network)));
      v.failLoads = false;
      expect(await l.hasTokens, isTrue);
      expect(v.data.containsKey(vaultTokens), isTrue);
    });

    test('Πρόωρη ανανέωση χωρίς δίκτυο: χρησιμοποιείται η πρόσβαση που ισχύει ακόμα', () async {
      final v = MemoryVault()..data[vaultTokens] = tokens(life: const Duration(minutes: 5)).toJson();
      final http = FakeHttp((m, u, h, f) {
        if (m == 'POST') throw const SocketException('χωρίς δίκτυο');
        return OuraResponse(200, jsonEncode({'data': [], 'next_token': null}));
      });
      await link(http, v).fetchAll('sleep', DateTime(2026, 11, 1), DateTime(2026, 11, 7));
      expect(http.calls.last.$3['Authorization'], 'Bearer A0');
    });

    test('Ανανεώσεις μία-μία: δύο ταυτόχρονες χρησιμοποιούν το refresh token μία φορά', () async {
      final v = MemoryVault()..data[vaultTokens] = tokens().toJson();
      var refreshes = 0;
      final http = FakeHttp((m, u, h, f) {
        refreshes++;
        return OuraResponse(200, jsonEncode({'access_token': 'A$refreshes', 'refresh_token': 'R$refreshes', 'expires_in': 86400}));
      });
      final l = link(http, v);
      final r = await Future.wait([l.refresh(), l.refresh(), l.refresh()]);
      expect(refreshes, 1);
      expect(r.map((t) => t!.refresh).toSet(), {'R1'});
    });

    test('Πρόσβαση που λήγει σε λίγο: ανανέωση πριν από το αίτημα', () async {
      final v = MemoryVault()..data[vaultTokens] = tokens(life: const Duration(minutes: 5)).toJson();
      final http = FakeHttp((m, u, h, f) => m == 'POST'
          ? OuraResponse(200, jsonEncode({'access_token': 'A1', 'refresh_token': 'R1', 'expires_in': 86400}))
          : OuraResponse(200, jsonEncode({'data': [], 'next_token': null})));
      await link(http, v).fetchAll('sleep', DateTime(2026, 11, 1), DateTime(2026, 11, 7));
      expect(http.calls.first.$1, 'POST');
      expect(http.calls.last.$3['Authorization'], 'Bearer A1');
    });

    test('Αποθήκευση απέτυχε: τα νέα tokens μένουν στη μνήμη και ξαναγράφονται στην επόμενη χρήση', () async {
      final v = MemoryVault()..data[vaultTokens] = tokens().toJson();
      final http = FakeHttp((m, u, h, f) =>
          OuraResponse(200, jsonEncode({'access_token': 'A1', 'refresh_token': 'R1', 'expires_in': 86400})));
      final l = link(http, v);
      v.failSaves = true;
      await l.refresh();
      expect(OuraTokens.fromJson(v.data[vaultTokens])!.refresh, 'R0');
      v.failSaves = false;
      await l.tokens();
      expect(OuraTokens.fromJson(v.data[vaultTokens])!.refresh, 'R1');
    });

    test('Χωρίς refresh token στην απάντηση: δεν συνδέεται (θα ήθελε σύνδεση κάθε 30 μέρες)', () {
      expect(() => OuraTokens.parseResponse('{"access_token":"A","expires_in":10}', now),
          throwsA(isA<OuraError>().having((e) => e.kind, 'kind', OuraErrorKind.noRefresh)));
    });
  });

  group('Σύνδεση (authorization code + PKCE)', () {
    final now = DateTime(2026, 11, 6, 10);

    test('begin → complete: ανταλλαγή χωρίς secret, με code_verifier, tokens κρυπτογραφημένα στο vault', () async {
      final v = MemoryVault();
      String? sentForm;
      final http = FakeHttp((m, u, h, f) {
        sentForm = f;
        expect(u.toString(), 'https://api.ouraring.com/oauth/token');
        return OuraResponse(200, jsonEncode(fixture('token.json')));
      });
      final l = OuraLink(vault: v, send: http.send, clock: () => now, clientId: 'CID', tokenEndpoint: 'https://api.ouraring.com/oauth/token');
      final url = await l.begin();
      final state = url.queryParameters['state']!;
      final pending = OuraPending.fromJson(v.data[vaultPending])!;
      expect(pkceChallenge(pending.verifier), url.queryParameters['code_challenge']);
      expect(await l.complete('https://ygeia-forma.netlify.app/oura/callback?code=THECODE&state=$state'), isTrue);
      final form = Uri.splitQueryString(sentForm!);
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], 'THECODE');
      expect(form['redirect_uri'], 'https://ygeia-forma.netlify.app/oura/callback', reason: 'ίδια με τη σελίδα σύνδεσης');
      expect(form['redirect_uri'], url.queryParameters['redirect_uri']);
      expect(form['client_id'], 'CID');
      expect(form['code_verifier'], pending.verifier);
      expect(form.containsKey('client_secret'), isFalse);
      expect(OuraTokens.fromJson(v.data[vaultTokens])!.refresh, 'REFRESH-1');
      expect(v.data.containsKey(vaultPending), isFalse, reason: 'state και verifier μιας χρήσης');
    });

    test('exchange: η πρώτη νύχτα ταξιδεύει με το state· τα tokens ΔΕΝ γράφονται πριν από το adopt', () async {
      final v = MemoryVault();
      final http = FakeHttp((m, u, h, f) => OuraResponse(200, jsonEncode(fixture('token.json'))));
      final l = OuraLink(vault: v, send: http.send, clock: () => now, clientId: 'CID');
      final st = (await l.begin(from: DateTime(2026, 11, 6))).queryParameters['state'];
      final ex = await l.exchange('$ouraRedirectHttps?code=C&state=$st');
      expect(ex!.from, DateTime(2026, 11, 6));
      expect(v.data.containsKey(vaultTokens), isFalse);
      expect(await l.hasTokens, isFalse);
      // Αποθήκευση που αποτυγχάνει: τίποτα δεν κρατιέται ούτε στη μνήμη.
      v.failSaves = true;
      expect(await l.adopt(ex.tokens, ex.gen), isFalse);
      expect(await l.hasTokens, isFalse);
      v.failSaves = false;
      expect(await l.adopt(ex.tokens, ex.gen), isTrue);
      expect(OuraTokens.fromJson(v.data[vaultTokens])!.refresh, 'REFRESH-1');
      // Αποσύνδεση στο μεταξύ (άλλη γενιά): δεν κρατιέται.
      await l.disconnect();
      expect(await l.adopt(ex.tokens, ex.gen), isFalse);
      expect(v.data.containsKey(vaultTokens), isFalse);
    });

    test('Άλλο state (CSRF) ή χωρίς εκκρεμή σύνδεση: αγνοείται, καμία κλήση', () async {
      final v = MemoryVault();
      final http = FakeHttp((m, u, h, f) => throw StateError('δεν έπρεπε να κληθεί'));
      final l = OuraLink(vault: v, send: http.send, clock: () => now, clientId: 'CID');
      expect(await l.complete('ygeiaforma://oura-callback?code=X&state=Y'), isFalse);
      await l.begin();
      expect(await l.complete('ygeiaforma://oura-callback?code=X&state=WRONG'), isFalse);
      expect(http.calls, isEmpty);
    });

    test('Άρνηση στη σελίδα της Oura → denied· άργησε → stale· η Oura απέρριψε → tokenRejected', () async {
      Future<OuraErrorKind?> run(String suffix, {Duration later = Duration.zero, int status = 200}) async {
        final v = MemoryVault();
        var t = now;
        final http = FakeHttp((m, u, h, f) => OuraResponse(status, status == 200 ? jsonEncode(fixture('token.json')) : '{}'));
        final l = OuraLink(vault: v, send: http.send, clock: () => t, clientId: 'CID');
        final st = (await l.begin()).queryParameters['state'];
        t = now.add(later);
        try {
          await l.complete('ygeiaforma://oura-callback?$suffix&state=$st');
          return null;
        } on OuraError catch (e) {
          return e.kind;
        }
      }

      expect(await run('error=access_denied'), OuraErrorKind.denied);
      expect(await run('code=X', later: const Duration(minutes: 30)), OuraErrorKind.stale);
      expect(await run('code=X', status: 400), OuraErrorKind.tokenRejected);
      expect(await run('code=X'), isNull);
    });

    test('Χωρίς Client ID: δεν ξεκινά (το κουμπί είναι ανενεργό)', () async {
      final l = OuraLink(vault: MemoryVault(), clientId: '');
      expect(l.configured, isFalse);
      expect(() => l.begin(), throwsA(isA<OuraError>().having((e) => e.kind, 'kind', OuraErrorKind.notConfigured)));
    });

    test('Αποσύνδεση: ανάκληση στην Oura και σβήσιμο tokens, ακόμα και χωρίς ίντερνετ', () async {
      final v = MemoryVault()
        ..data[vaultTokens] = OuraTokens(access: 'A', refresh: 'R', expiresAt: now.add(const Duration(days: 1)).millisecondsSinceEpoch).toJson();
      final http = FakeHttp((m, u, h, f) => throw const SocketException('χωρίς δίκτυο'));
      final l = OuraLink(vault: v, send: http.send, clock: () => now, clientId: 'CID');
      await l.disconnect();
      expect(v.data, isEmpty);
      expect(http.calls.single.$2.path, '/oauth/revoke');
      expect(http.calls.single.$2.queryParameters['access_token'], 'A');
      expect(await l.hasTokens, isFalse);
    });
  });

  group('Σύνδεση με το ιστορικό', () {
    test('mergeOura: γράφει μόνο μέρες με πηγή Oura, μόνο κλειδιά «o.*», σβήνει ό,τι δεν ήρθε πια', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 10, 24));
      final h = <String, Map<String, double>>{
        '2026-10-23': {K.sleepMin: 400, K.steps: 5000},
        '2026-10-26': {K.steps: 6000, 'o.sleepMin': 999, 'o.hrv': 99},
      };
      final rows = ouraRows(fixtureBatch().nights);
      final changed = mergeOura(h, rows, from: DateTime(2026, 10, 23), to: DateTime(2026, 10, 27), plan: plan);
      expect(h['2026-10-23'], {K.sleepMin: 400, K.steps: 5000}, reason: 'νύχτα του ρολογιού: το Oura δεν γράφεται');
      expect(h['2026-10-24']!['o.sleepMin'], 280);
      expect(h['2026-10-26']!['o.sleepMin'], 360);
      expect(h['2026-10-26']!.containsKey('o.hrv'), isFalse, reason: 'δεν ήρθε πια → φεύγει');
      expect(h['2026-10-26']![K.steps], 6000);
      expect(changed, containsAll(['2026-10-24', '2026-10-25', '2026-10-26']));
      for (final row in h.values) {
        for (final k in row.keys) {
          expect(ouraKeySet.contains(k) || !k.startsWith('o.'), isTrue);
        }
      }
    });

    test('Παράθυρα ύπνου: μόνο ώρες, για τους παλμούς της μέρας', () {
      final w = ouraSleepWindows(fixtureBatch().nights);
      expect(w.mains.keys.toSet(), {'2026-10-23', '2026-10-24', '2026-10-25', '2026-10-26'});
      expect(w.ranges.length, 7);
    });
  });
}
