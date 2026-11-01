// Έλεγχοι για την αναφορά σφαλμάτων (lib/error_report.dart), χωρίς δίκτυο.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/error_report.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('errq'));
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, Object?> eventIn(String body) {
    final lines = body.split('\n');
    expect(lines, hasLength(3));
    expect(jsonDecode(lines[1]), {'type': 'event'});
    return jsonDecode(lines[2]) as Map<String, Object?>;
  }

  test('η στοίβα της Dart γίνεται γραμμές για το Sentry, η παλαιότερη πρώτη', () {
    const stack = '#0      FoodStore.add (package:ygeia_forma/food/food_store.dart:120:7)\n'
        '#1      _AddFoodScreenState._pick (package:ygeia_forma/pages/food_add.dart:131)\n'
        '<asynchronous suspension>\n'
        '#2      _rootRun (dart:async/zone.dart:1525:13)\n';
    final f = parseDartStack(stack);
    expect(f, hasLength(3));
    expect(f.first['filename'], 'dart:async/zone.dart');
    expect(f.first['in_app'], false);
    expect(f.last['function'], 'FoodStore.add');
    expect(f.last['lineno'], 120);
    expect(f.last['colno'], 7);
    expect(f.last['in_app'], true);
    expect(f[1]['lineno'], 131);
    expect(f[1].containsKey('colno'), false);
  });

  test('στέλνει σφάλμα, οθόνη, έκδοση — και αδειάζει την ουρά', () async {
    final sent = <String>[];
    final r = ErrorReporter(dir: dir, release: 'ygeia-forma@0.1.99', environment: 'test', device: const {'model': 'samsung SM-F976B', 'android': '16'}, post: (b) async {
      sent.add(b);
      return 200;
    });
    r.setBase('Διατροφή › Ημερολόγιο');
    await r.report(StateError('κάτι χάλασε\nδεύτερη γραμμή με 82,2 kg'), StackTrace.current);
    await r.flush();
    expect(sent, hasLength(1));
    final e = eventIn(sent.single);
    expect(e['release'], 'ygeia-forma@0.1.99');
    expect((e['tags'] as Map)['screen'], 'Διατροφή › Ημερολόγιο');
    final ex = ((e['exception'] as Map)['values'] as List).single as Map;
    expect(ex['type'], 'StateError');
    // Μόνο η πρώτη γραμμή του μηνύματος.
    expect(ex['value'], 'Bad state: κάτι χάλασε');
    expect(((ex['stacktrace'] as Map)['frames'] as List), isNotEmpty);
    expect(((e['contexts'] as Map)['device'] as Map)['model'], 'samsung SM-F976B');
    expect(await r.pending(), 0);
  });

  test('χωρίς ίντερνετ μένει στην ουρά και φεύγει αργότερα', () async {
    var online = false;
    var sent = 0;
    final r = ErrorReporter(dir: dir, post: (b) async {
      if (!online) throw const SocketException('offline');
      sent++;
      return 200;
    });
    await r.report(ArgumentError('α'), StackTrace.current);
    await r.flush();
    expect(await r.pending(), 1);
    online = true;
    await r.flush();
    expect(sent, 1);
    expect(await r.pending(), 0);
  });

  test('το ίδιο σφάλμα μία φορά το λεπτό, θόρυβος δικτύου ποτέ', () async {
    var now = DateTime(2026, 11, 1, 12);
    final r = ErrorReporter(dir: dir, clock: () => now, post: (_) async => throw const SocketException('offline'));
    for (var i = 0; i < 5; i++) {
      await r.report(StateError('ίδιο'), null);
    }
    await r.report(const SocketException('no route'), null);
    expect(await r.pending(), 1);
    now = now.add(const Duration(minutes: 2));
    await r.report(StateError('ίδιο'), null);
    expect(await r.pending(), 2);
  });

  test('η ουρά κρατάει το πολύ 20, τα παλαιότερα φεύγουν', () async {
    var now = DateTime(2026, 11, 1, 12);
    final r = ErrorReporter(dir: dir, clock: () => now, post: (_) async => throw const SocketException('offline'));
    for (var i = 0; i < 25; i++) {
      now = now.add(const Duration(seconds: 1));
      await r.report(StateError('σφάλμα $i'), null);
    }
    expect(await r.pending(), maxQueue);
  });

  test('το πολύ 30 αποστολές τη μέρα', () async {
    var now = DateTime(2026, 11, 1, 12);
    var sent = 0;
    var online = false;
    final r = ErrorReporter(dir: dir, clock: () => now, post: (_) async {
      if (!online) throw const SocketException('offline');
      sent++;
      return 200;
    });
    for (var round = 0; round < 2; round++) {
      for (var i = 0; i < 20; i++) {
        now = now.add(const Duration(seconds: 1));
        await r.report(StateError('σφάλμα $round-$i'), null);
      }
      online = true;
      await r.flush();
      online = false;
    }
    expect(sent, maxPerDay);
  });

  test('400 πετιέται, 429 και 5xx περιμένουν', () async {
    var status = 503;
    final r = ErrorReporter(dir: dir, post: (_) async => status);
    await r.report(StateError('x'), null);
    await r.flush();
    expect(await r.pending(), 1);
    status = 429;
    await r.flush();
    expect(await r.pending(), 1);
    status = 400;
    await r.flush();
    expect(await r.pending(), 0);
  });

  test('σφάλματα πριν έρθει ο φάκελος δεν χάνονται', () async {
    final r = ErrorReporter(post: (_) async => 200);
    await r.report(StateError('στην εκκίνηση'), null);
    await r.configure(dir: dir, release: 'ygeia-forma@0.1.5', device: const {'model': 'm', 'android': '16'});
    expect(await r.pending(), 1);
    final e = jsonDecode(dir.listSync().whereType<File>().single.readAsStringSync()) as Map;
    expect(e['release'], 'ygeia-forma@0.1.5');
  });

  test('σφάλμα γραμμένο από την πλευρά Android στέλνεται όπως είναι', () async {
    File('${dir.path}/00001793530000_abc.json').writeAsStringSync(jsonEncode({
      'event_id': 'abc',
      'platform': 'java',
      'exception': {'values': []},
    }));
    final sent = <String>[];
    final r = ErrorReporter(dir: dir, post: (b) async {
      sent.add(b);
      return 200;
    });
    await r.flush();
    expect(eventIn(sent.single)['platform'], 'java');
    expect(await r.pending(), 0);
  });
}
